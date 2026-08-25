local _zsh_config_dir="${0:A:h}"

# Shared annotation parser outputs cat TAB name TAB desc TAB needs TAB usage.
# Used by both alias:list and alias:find.
function _alias_parse() {
	local -a files
	files=("$ZSH_CONFIG_ROOT"/aliases.*.zsh(N))

	[[ ${#files} -eq 0 ]] && return

	awk '
		/^[[:space:]]*$/ { desc=""; cat=""; needs=""; usage=""; next }
		/^# @desc[[:space:]]/ {
			desc = $0; sub(/^# @desc[[:space:]]*/, "", desc); next
		}
		/^# @cat[[:space:]]/ { cat = $3; next }
		/^# @needs[[:space:]]/ {
			needs = $0; sub(/^# @needs[[:space:]]*/, "", needs); next
		}
		/^# Usage:[[:space:]]/ {
			usage = $0; sub(/^# Usage:[[:space:]]*/, "", usage); next
		}
		/^alias [^=]+=/ {
			if (cat == "") { desc=""; cat=""; needs=""; usage=""; next }
			name = $2; sub(/=.*/, "", name)
			print cat "\t" name "\t" desc "\t" needs "\t" usage
			desc=""; cat=""; needs=""; usage=""; next
		}
		/^function [[:alnum:]]/ {
			if (cat == "") { desc=""; cat=""; needs=""; usage=""; next }
			name = $2; sub(/\(\).*/, "", name); sub(/[[:space:]]+$/, "", name)
			print cat "\t" name "\t" desc "\t" needs "\t" usage
			desc=""; cat=""; needs=""; usage=""; next
		}
		/^[[:alnum:]_:-]+\(\)[[:space:]]*\{/ {
			if (cat == "") { desc=""; cat=""; needs=""; usage=""; next }
			name = $1; sub(/\(\)$/, "", name)
			print cat "\t" name "\t" desc "\t" needs "\t" usage
			desc=""; cat=""; needs=""; usage=""; next
		}
	' "${files[@]}" | sort -t$'\t' -k1,1 -k2,2
}

# @desc  List all annotated commands, grouped by category
# @cat   config
function alias:list() {
	local records
	records=$(_alias_parse)

	if [[ -z "$records" ]]; then
		printf 'No annotated commands found.\n'
		return 0
	fi

	local prev_cat=""
	while IFS=$'\t' read -r cat name desc _needs; do
		if [[ "$cat" != "$prev_cat" ]]; then
			[[ -n "$prev_cat" ]] && printf '\n'
			printf '%s%s%s\n' "$CYAN" "$cat" "$RESET_COLOUR"
			prev_cat="$cat"
		fi
		printf '  %-32s %s\n' "$name" "$desc"
	done <<< "$records"
}

# @desc  Interactively browse and run annotated commands with fzf
# @cat   config
# @needs fzf
function alias:find() {
	if ! command -v fzf &>/dev/null; then
		printf 'fzf is required — install with: brew install fzf\n' >&2
		return 1
	fi

	local category_filter="" copy_mode=0
	for arg in "$@"; do
		case "$arg" in
			--copy) copy_mode=1 ;;
			*) category_filter="$arg" ;;
		esac
	done

	local records
	records=$(_alias_parse)

	if [[ -n "$category_filter" ]]; then
		records=$(awk -F'\t' -v cat="$category_filter" '$1 == cat' <<< "$records")
	fi

	if [[ -z "$records" ]]; then
		printf 'No commands found%s\n' "${category_filter:+ in category: $category_filter}"
		return 0
	fi

	# Display name + desc; preview shows all fields.
	# The preview awk program is double-quoted for sh, so $ and " are escaped.
	local selected
	selected=$(printf '%s\n' "$records" | fzf \
		--delimiter=$'\t' \
		--with-nth=2,3 \
		--preview='printf "%s\n" {} | awk -F"\t" "{printf \"name:     %s\ncategory: %s\ndesc:     %s\n\", \$2, \$1, \$3; if (\$4 != \"\") printf \"needs:    %s\n\", \$4}"' \
		--preview-window='down:5:wrap' \
		--prompt='alias > ' \
		--height='50%' \
		--reverse \
		--no-multi)

	[[ -z "$selected" ]] && return 0

	local name
	name=$(cut -d$'\t' -f2 <<< "$selected")

	if (( copy_mode )); then
		printf '%s' "$name" | pbcopy
		printf 'Copied: %s\n' "$name"
	else
		eval "$name"
	fi
}

# Internal helper — writes the generated command table into a target file,
# replacing content between <!-- commands:start --> and <!-- commands:end -->.
function _docs_write() {
	local target=$1
	if ! grep -q '^<!-- commands:start -->' "$target" 2>/dev/null; then
		printf 'No <!-- commands:start --> sentinel found in %s\n' "$target" >&2
		return 1
	fi

	local before new_block after
	before=$(awk '/^<!-- commands:start -->/{exit} {print}' "$target")
	after=$(awk '/^<!-- commands:end -->/{found=1; next} found{print}' "$target")
	new_block=$(
		_alias_parse | awk -F'\t' '
			BEGIN { prev_cat = "" }
			{
				if ($1 != prev_cat) {
					if (prev_cat != "") printf "\n"
					printf "### %s\n\n| Command | Parameters | Description |\n| --- | --- | --- |\n", $1
					prev_cat = $1
				}
				parameters = $5
				sub(/^[^[:space:]]+[[:space:]]*/, "", parameters)
				printf "| `%s` | %s | %s |\n", $2, parameters, $3
			}
		'
	)
	{
		printf '%s\n' "$before"
		printf '<!-- commands:start -->\n\n'
		printf '%s\n' "$new_block"
		printf '\n<!-- commands:end -->\n'
		printf '%s' "$after"
	} > "$target"
}

# Internal — used by zsh:doctor. Returns 0 if README table matches annotations.
function _docs_check() {
	local readme="$ZSH_CONFIG_ROOT/README.md"
	[[ ! -f "$readme" ]] && return 1
	local tmp
	tmp=$(mktemp "${TMPDIR:-/tmp}/zsh-docs-check.XXXXXX")
	cp "$readme" "$tmp"
	_docs_write "$tmp" 2>/dev/null || { rm -f "$tmp"; return 1; }
	local result=0
	diff -q "$readme" "$tmp" &>/dev/null || result=1
	rm -f "$tmp"
	return $result
}

# @desc  Regenerate the command table in README.md from annotations
# @cat   docs
function docs:generate() {
	local readme="$ZSH_CONFIG_ROOT/README.md"
	if [[ ! -f "$readme" ]]; then
		printf 'README.md not found at %s\n' "$ZSH_CONFIG_ROOT" >&2
		return 1
	fi
	_docs_write "$readme" && printf 'README.md updated.\n'
}

# Return whether a command is available in the current shell.
#
# @param  {string}  command_name
#     Command to look up.
_updates_command_available() {
	local command_name="$1"

	(( $+commands[$command_name] ))
}

# Report whether a configured updater can run without starting it.
#
# @param  {string}  label
#     Human-readable updater name.
# @param  {string}  command_name
#     Command required by the updater.
_updates_check_command() {
	local label="$1"
	local command_name="$2"

	if _updates_command_available "$command_name"; then
		cli_style_status success "$label" "Ready"
		return 0
	fi

	cli_style_status info "$label" "Skipped, $command_name is not installed"
}

# Run an available updater without intercepting its terminal streams.
#
# @param  {string}  label
#     Human-readable updater name.
# @param  {string}  command_name
#     Command required by the updater.
# @param  {string}  ...
#     Command and arguments to run.
_updates_run_command() {
	local label="$1"
	shift

	local command_name="$1"

	if ! _updates_command_available "$command_name"; then
		cli_style_status info "$label" "Skipped, $command_name is not installed"
		return 0
	fi

	cli_style_status info "$label" "Running interactively"

	if "$@"; then
		cli_style_status success "$label" "Complete"
		return 0
	fi

	cli_style_status danger "$label" "Failed"
	return 1
}

# @desc  List available global updaters without starting them
# @cat   tools
# List the global update commands available in the current shell.
function updates:check() {
	cli_style_status info "Global updates" "Checking available updaters"

	_updates_check_command "Homebrew" brew
	_updates_check_command "Bun" bun
	_updates_check_command "uv tools" uv
	_updates_check_command "Codebase Memory MCP" codebase-memory-mcp
	_updates_check_command "npm global packages" npm
	_updates_check_command "GitHub CLI extensions" gh
}

# @desc  Update global tools while preserving each updater's interaction
# @cat   tools
# Update global tools while preserving each updater's interaction.
function updates:run() {
	local failures=0

	cli_style_status info "Global updates" "Running available updaters"

	_updates_run_command "Homebrew metadata" brew update || ((failures += 1))
	_updates_run_command "Homebrew packages" brew upgrade || ((failures += 1))
	_updates_run_command "Bun runtime" bun upgrade || ((failures += 1))
	_updates_run_command "uv tools" uv tool upgrade --all || ((failures += 1))
	_updates_run_command "Codebase Memory MCP" codebase-memory-mcp update || ((failures += 1))
	_updates_run_command "npm global packages" npm update --global || ((failures += 1))
	_updates_run_command "GitHub CLI extensions" gh extension upgrade --all || ((failures += 1))

	if ((failures > 0)); then
		cli_style_status danger "Global updates" "$failures updater commands failed"
		return 1
	fi

	cli_style_status success "Global updates" "All available updaters completed"
}
