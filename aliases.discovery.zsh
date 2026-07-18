local _zsh_config_dir="${0:A:h}"

# Read a value from a task file's flat YAML front matter.
#
# @param  {string}  file
#     Task file to read.
# @param  {string}  field
#     Front matter field to return.
_progress_frontmatter_value() {
	local file="$1"
	local field="$2"

	awk -v field="$field" '
		NR == 1 && $0 == "---" { frontmatter = 1; next }
		frontmatter && $0 == "---" { exit }
		frontmatter {
			separator = index($0, ":")
			if (separator == 0) next

			key = substr($0, 1, separator - 1)
			if (key != field) next

			value = substr($0, separator + 1)
			sub(/^[[:space:]]+/, "", value)
			print value
			exit
		}
	' "$file"
}

# Count completed and total checklist items in a task's Tasks section.
#
# @param  {string}  file
#     Task file to inspect.
_progress_task_steps() {
	local file="$1"

	awk '
		/^## Tasks[[:space:]]*$/ { tasks = 1; next }
		tasks && /^## / { exit }
		tasks && /^- \[[ xX]\]/ {
			total++
			if ($0 ~ /^- \[[xX]\]/) completed++
		}
		END { printf "%d\t%d\n", completed, total }
	' "$file"
}

# Return the task path linked from the Session handoff's Active task section.
#
# @param  {string}  file
#     PROGRESS.md file to inspect.
_progress_active_task_path() {
	local file="$1"

	awk '
		/^### Active task[[:space:]]*$/ { active_task = 1; next }
		active_task && /^### / { exit }
		active_task && /\]\(\.agent\/tasks\/[^)]+\)/ {
			path = $0
			sub(/^.*\]\(/, "", path)
			sub(/\).*$/, "", path)
			print path
			exit
		}
	' "$file"
}

# Return the current and next roadmap release titles.
#
# @param  {string}  file
#     PROGRESS.md file containing the roadmap.
# @param  {string}  release_id
#     Preferred release ID from the active task, or an empty string.
_progress_roadmap_releases() {
	local file="$1"
	local release_id="$2"

	awk -F'|' -v release_id="$release_id" '
		function trim(value) {
			gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
			return value
		}

		/^## Roadmap[[:space:]]*$/ { roadmap = 1; next }
		roadmap && /^## / { exit }
		roadmap && /^\|/ {
			id = trim($2)
			title = trim($3)
			status = trim($5)

			if (id == "" || id == "ID" || id ~ /^-+$/) next

			count++
			ids[count] = id
			titles[count] = title
			statuses[count] = status
		}

		END {
			for (row_index = 1; row_index <= count; row_index++) {
				if (release_id != "" && ids[row_index] == release_id) {
					current = row_index
					break
				}
			}

			if (current == 0) {
				for (row_index = 1; row_index <= count; row_index++) {
					if (statuses[row_index] == "active") {
						current = row_index
						break
					}
				}
			}

			if (current == 0) exit

			for (row_index = current + 1; row_index <= count; row_index++) {
				if (statuses[row_index] != "done") {
					next_title = titles[row_index]
					break
				}
			}

			printf "%s\t%s\n", titles[current], next_title
		}
	' "$file"
}

# Summarise projects with an active PROGRESS.md file.
progress:check() {
	local -a dirs task_files
	local dir task_file active_task_path current_task current_title current_release task_status
	local ready in_progress blocked needs_decision done unknown
	local step_counts completed_steps total_steps progress_colour
	local task_summary task_colour
	local release_summary release_title next_release

	dirs=("${(@f)$(fd --hidden --no-ignore-vcs --type f '^PROGRESS\.md$' "$HOME/Dev" \
		--ignore-file "$ZSH_CONFIG_ROOT/ignores.fd" \
		--exec dirname {} |
		sort)}")

	[[ ${#dirs} -eq 1 && -z "${dirs[1]}" ]] && dirs=()

	printf '\n'

	for dir in "${dirs[@]}"; do
		cli_style_status info "$dir"

		task_files=("$dir"/.agent/tasks/*.md(N))

		active_task_path=$(_progress_active_task_path "$dir/PROGRESS.md")
		current_task=""
		current_title=""
		current_release=""
		ready=0
		in_progress=0
		blocked=0
		needs_decision=0
		done=0
		unknown=0

		for task_file in "${task_files[@]}"; do
			task_status=$(_progress_frontmatter_value "$task_file" status)

			case "$task_status" in
				ready) ((ready++)) ;;
				in-progress)
					((in_progress++))
					if [[ -z "$current_task" || "$task_file" == "$dir/$active_task_path" ]]; then
						current_task="$task_file"
						current_title=$(_progress_frontmatter_value "$task_file" title)
						current_release=$(_progress_frontmatter_value "$task_file" release)
					fi
					;;
				blocked) ((blocked++)) ;;
				needs-decision) ((needs_decision++)) ;;
				done) ((done++)) ;;
				*) ((unknown++)) ;;
			esac
		done

		if [[ -n "$current_task" ]]; then
			[[ -z "$current_title" ]] && current_title="${current_task:t:r}"
			cli_style_row "Current" "$current_title" --label-width 12 --value-colour info

			progress_colour="info"
			step_counts=$(_progress_task_steps "$current_task")
			completed_steps="${step_counts%%$'\t'*}"
			total_steps="${step_counts#*$'\t'}"

			if ((total_steps > 0 && completed_steps == total_steps)); then
				progress_colour="success"
			fi

			cli_style_row "Progress" "$completed_steps/$total_steps steps" --label-width 12 --value-colour "$progress_colour"
		fi

		task_summary="${#task_files[@]} total"
		((in_progress > 0)) && task_summary+=" · $in_progress in progress"
		((ready > 0)) && task_summary+=" · $ready ready"
		((blocked > 0)) && task_summary+=" · $blocked blocked"
		((needs_decision > 0)) && task_summary+=" · $needs_decision need decision"
		((done > 0)) && task_summary+=" · $done done"
		((unknown > 0)) && task_summary+=" · $unknown unknown"

		task_colour="info"
		((needs_decision > 0)) && task_colour="warning"
		((blocked > 0)) && task_colour="danger"
		((${#task_files[@]} == 0)) && task_colour="muted"
		cli_style_row "Tasks" "$task_summary" --label-width 12 --value-colour "$task_colour"

		release_summary=$(_progress_roadmap_releases "$dir/PROGRESS.md" "$current_release")
		release_title="${release_summary%%$'\t'*}"
		next_release="${release_summary#*$'\t'}"

		[[ -n "$release_title" ]] && cli_style_row "Release" "$release_title" --label-width 12 --value-colour success
		[[ -n "$next_release" ]] && cli_style_row "Next release" "$next_release" --label-width 12 --value-colour muted

		printf '\n'
	done

	cli_style_status success "${#dirs[@]} active PROGRESS.md file(s) found"

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
