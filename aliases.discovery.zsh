local _zsh_config_dir="${0:A:h}"

# Return a task status as a human-readable label.
#
# @param  {string}  task_status
#     Task front matter status.
_progress_status_label() {
	local task_status="$1"

	case "$task_status" in
		ready) printf 'Ready\n' ;;
		in-progress) printf 'In progress\n' ;;
		blocked) printf 'Blocked\n' ;;
		needs-decision) printf 'Needs decision\n' ;;
		done) printf 'Done\n' ;;
		*) printf 'Unknown\n' ;;
	esac
}

# Return success when a `progress ... --json` response is non-empty and reports ok:true.
#
# @param  {string}  json
#     JSON text from a `progress` command's --json output.
_progress_json_ok() {
	local json="$1"

	if [[ -z "$json" ]]; then
		return 1
	fi

	jq -e '.ok == true' <<< "$json" >/dev/null 2>&1
}

# Summarise each progress-bound project: current task, commit-plan progress, and what's next.
progress:check() {
	local -a dirs task_parts next_title_lines
	local dir progress_project_id current_json fallback_next_json next_json task_json chunk_json release_json
	local current_task_id current_title current_status current_release_id
	local next_task_id next_title next_hint next_title_line
	local task_counts in_progress ready blocked needs_decision
	local chunk_counts completed_chunks total_chunks commit_colour
	local task_summary task_colour task_row_label status_label status_colour release_title

	# The shared ignore file normally excludes .git; strip that entry so this scan can still find each repo's progress binding.
	dirs=("${(@f)$(fd --hidden --no-ignore-vcs --type d '^\.git$' "$HOME/Dev" \
		--ignore-file <(sed '/^\.git\/$/d' "$_zsh_config_dir/ignores.fd") \
		--exec dirname {} |
		while IFS= read -r dir; do
			if progress_project_id="$(git -C "$dir" config --local --get progress.project-id 2>/dev/null)"; then
				[[ -n "$progress_project_id" ]] && printf '%s\n' "$dir"
			fi
		done |
		sort -u)}")

	[[ ${#dirs} -eq 1 && -z "${dirs[1]}" ]] && dirs=()

	printf '\n'

	for dir in "${dirs[@]}"; do
		cli_style_status info "$dir"

		current_json="$(cd "$dir" && progress next --json 2>/dev/null)"
		if ! _progress_json_ok "$current_json"; then
			cli_style_row "Progress" "Could not read project data" --label-width 14 --value-colour danger
			printf '\n'
			continue
		fi

		current_task_id="$(jq -r '.data.task.id // empty' <<< "$current_json")"
		current_title="$(jq -r '.data.task.title // empty' <<< "$current_json")"
		current_status="$(jq -r '.data.task.status // empty' <<< "$current_json")"
		current_release_id="$(jq -r '.data.task.release_id // empty' <<< "$current_json")"

		if [[ -z "$current_task_id" ]]; then
			fallback_next_json="$(cd "$dir" && progress next --json 2>/dev/null)"
			if ! _progress_json_ok "$fallback_next_json"; then
				cli_style_row "Progress" "Could not read project data" --label-width 14 --value-colour danger
				printf '\n'
				continue
			fi

			current_task_id="$(jq -r '.data.task.id // empty' <<< "$fallback_next_json")"
			current_title="$(jq -r '.data.task.title // empty' <<< "$fallback_next_json")"
			current_status="$(jq -r '.data.task.status // empty' <<< "$fallback_next_json")"
			current_release_id="$(jq -r '.data.task.release_id // empty' <<< "$fallback_next_json")"
		fi

		next_json="$(cd "$dir" && progress next --json 2>/dev/null)"
		if ! _progress_json_ok "$next_json"; then
			cli_style_row "Progress" "Could not read project data" --label-width 14 --value-colour danger
			printf '\n'
			continue
		fi

		next_task_id="$(jq -r '.data.task.id // empty' <<< "$next_json")"
		next_title="$(jq -r '.data.task.title // empty' <<< "$next_json")"
		next_hint="$(jq -r '.data.hint_command // empty' <<< "$next_json")"

		task_json="$(cd "$dir" && progress task list --limit 200 --json 2>/dev/null)"
		if ! _progress_json_ok "$task_json"; then
			cli_style_row "Progress" "Could not read project data" --label-width 14 --value-colour danger
			printf '\n'
			continue
		fi

		task_counts="$(jq -r --arg current_task_id "$current_task_id" '
			.data.items // [] |
			[
				(map(select(.id != $current_task_id and .status == "in-progress")) | length),
				(map(select(.id != $current_task_id and .status == "ready")) | length),
				(map(select(.id != $current_task_id and .status == "blocked")) | length),
				(map(select(.id != $current_task_id and .status == "needs-decision")) | length)
			] | @tsv
		' <<< "$task_json")"
		read -r in_progress ready blocked needs_decision <<< "$task_counts"

		if [[ -n "$current_task_id" ]]; then
			[[ -z "$current_title" ]] && current_title="$current_task_id"
			cli_style_row "Current task" "$current_title" --label-width 14 --value-colour info

			status_label=$(_progress_status_label "$current_status")
			status_colour="info"

			case "$current_status" in
				ready) status_colour="muted" ;;
				done) status_colour="success" ;;
				blocked) status_colour="danger" ;;
				needs-decision) status_colour="warning" ;;
			esac

			cli_style_row "Status" "$status_label" --label-width 14 --value-colour "$status_colour"

			chunk_json="$(cd "$dir" && progress chunk list --task "$current_task_id" --limit 200 --json 2>/dev/null)"
			if _progress_json_ok "$chunk_json"; then
				chunk_counts="$(jq -r '
					.data.items // [] |
					[length, (map(select(.status == "done")) | length)] | @tsv
				' <<< "$chunk_json")"
				read -r total_chunks completed_chunks <<< "$chunk_counts"

				commit_colour="info"
				if ((total_chunks > 0 && completed_chunks == total_chunks)); then
					commit_colour="success"
				fi

				if ((total_chunks > 0)); then
					cli_style_row "Commit plan" "$completed_chunks/$total_chunks complete" --label-width 14 --value-colour "$commit_colour"
				fi
			fi
		fi

		task_parts=()
		((in_progress > 0)) && task_parts+=("$in_progress in progress")
		((ready > 0)) && task_parts+=("$ready ready")
		((blocked > 0)) && task_parts+=("$blocked blocked")
		((needs_decision > 0)) && task_parts+=("$needs_decision need decision")
		((${#task_parts[@]} == 0)) && task_parts=("None")
		task_summary="${(j: · :)task_parts}"

		task_colour="info"
		((needs_decision > 0)) && task_colour="warning"
		((blocked > 0)) && task_colour="danger"

		task_row_label="Other tasks"
		[[ -z "$current_task_id" ]] && task_row_label="Tasks"

		cli_style_row "$task_row_label" "$task_summary" --label-width 14 --value-colour "$task_colour"

		if [[ -n "$current_release_id" ]]; then
			release_json="$(cd "$dir" && progress release get "$current_release_id" --json 2>/dev/null)"
			if _progress_json_ok "$release_json"; then
				release_title="$(jq -r '.data.title // empty' <<< "$release_json")"
				[[ -n "$release_title" ]] && cli_style_row "Release" "$release_title" --label-width 14 --value-colour success
			fi
		fi

		if [[ -n "$next_task_id" ]]; then
			next_title="$(jq -r 'if (.data.task.status_reason // "") != "" then .data.task.status_reason else (.data.task.title // empty) end' <<< "$next_json")"
			[[ -z "$next_title" ]] && next_title="$next_task_id"
			next_title_lines=("${(@f)$(fold -s -w 72 <<< "$next_title")}")
			cli_style_row "Next action" "${next_title_lines[1]}" --label-width 14 --value-colour muted
			for next_title_line in "${(@)next_title_lines[2,-1]}"; do
				cli_style_row "" "$next_title_line" --label-width 14 --value-colour muted
			done
			[[ -n "$next_hint" ]] && cli_style_row "" "$next_hint" --label-width 14 --value-colour muted
		fi

		printf '\n'
	done

	cli_style_status success "${#dirs[@]} project plans checked"

	printf '\n'
}

# Shared annotation parser — outputs cat TAB name TAB desc TAB needs.
# Used by both alias:list and alias:find.
function _alias_parse() {
	local -a files
	files=("$ZSH_CONFIG_ROOT"/aliases.*.zsh(N))

	[[ ${#files} -eq 0 ]] && return

	awk '
		/^[[:space:]]*$/ { desc=""; cat=""; needs=""; next }
		/^# @desc[[:space:]]/ {
			desc = $0; sub(/^# @desc[[:space:]]*/, "", desc); next
		}
		/^# @cat[[:space:]]/ { cat = $3; next }
		/^# @needs[[:space:]]/ {
			needs = $0; sub(/^# @needs[[:space:]]*/, "", needs); next
		}
		/^alias [^=]+=/ {
			if (cat == "") { desc=""; cat=""; needs=""; next }
			name = $2; sub(/=.*/, "", name)
			print cat "\t" name "\t" desc "\t" needs
			desc=""; cat=""; needs=""; next
		}
		/^function [[:alnum:]]/ {
			if (cat == "") { desc=""; cat=""; needs=""; next }
			name = $2; sub(/\(\).*/, "", name); sub(/[[:space:]]+$/, "", name)
			print cat "\t" name "\t" desc "\t" needs
			desc=""; cat=""; needs=""; next
		}
		/^[[:alnum:]_:-]+\(\)[[:space:]]*\{/ {
			if (cat == "") { desc=""; cat=""; needs=""; next }
			name = $1; sub(/\(\)$/, "", name)
			print cat "\t" name "\t" desc "\t" needs
			desc=""; cat=""; needs=""; next
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
					printf "### %s\n\n| Command | Description |\n| --- | --- |\n", $1
					prev_cat = $1
				}
				printf "| `%s` | %s |\n", $2, $3
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
