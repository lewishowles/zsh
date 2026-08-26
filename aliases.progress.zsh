# @desc  List all releases for the current project
# @cat   progress
alias releases="progress release list"
# @desc  List all tasks for the current project
# @cat   progress
alias tasks="progress task list"

# @desc  List all chunks for the provided task ID
# @cat   progress
chunks() {
	progress chunk list --task "$1"
}

# @desc  Complete the given task or chunk, depending on ID format
# @cat   progress
completed() {
	case "$1" in
		tsk_*) progress task complete "$1" ;;
		chk_*) progress chunk complete "$1" ;;
		*) print -u2 "Unknown progress ID: $1"; return 1 ;;
	esac
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
