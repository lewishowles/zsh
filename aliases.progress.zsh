# @desc  List all releases for the current project
# @cat   progress
alias releases="progress release list"
# @desc  List all tasks for the current project
# @cat   progress
alias tasks="progress task list"
# @desc  Show details for the given task, or the selected next task if omitted
# @cat   progress
alias task="progress task get"
# @desc  Clean completed tasks and releases
# @cat   progress
alias clean="progress task clean --force"
# @desc  Clean up a completed worktree and its idle teammate panes
# @cat   progress
# Clears the former cleanup alias before the cleanup function is loaded.
if (( $+aliases[cleanup] )); then
	unalias cleanup
fi
# Cleans up a task's worktree, then closes the idle teammate panes of the task's
# Rex team. Cleanup runs from the task's main checkout, so it works from any
# folder, and the shell moves to the main checkout when cleanup removed the
# folder it was in. The panes are only closed once Progress has actually
# removed the task's checkout. That check reads the default Progress database,
# even when --database names another one.
#
# @param  {string}  ...
#     Arguments passed to progress worktree cleanup.
cleanup() {
	# Arguments for a cleanup run from the caller's folder, exactly as given.
	local -a cleanup_args=("$@")
	# Arguments for a cleanup run from the main checkout, with relative database paths made absolute.
	local -a checkout_args=("$@")
	# Task named in the arguments, whose team panes are closed afterwards.
	local task_id=""
	# Whether the arguments ask for help, so Progress only prints its usage.
	local show_help=0
	# Whether cleanup targets a branch without a task record.
	local branch_cleanup=0
	# Database option to use for the task lookup.
	local -a lookup_args=()
	# Main checkout for the task's project, when the lookup finds one.
	local main_checkout=""
	# The caller's folder, which cleanup removes when it is the task's worktree.
	local original_pwd="$PWD"

	_progress_cleanup_arguments

	if [[ -n "$task_id" ]] && (( ! show_help && ! branch_cleanup )); then
		main_checkout="$(_progress_cleanup_main_checkout "$task_id" "${lookup_args[@]}")" || main_checkout=""
	fi

	if [[ -n "$main_checkout" ]]; then
		(cd "$main_checkout" && progress worktree cleanup "${checkout_args[@]}") || return $?
		if [[ ! -d "$original_pwd" ]]; then
			cd "$main_checkout" || return $?
		fi
	else
		progress worktree cleanup "${cleanup_args[@]}" || return $?
	fi
	if [[ -n "$task_id" && -n "${REX_SESSION:-}" ]] && (( ! show_help && $+functions[_hcom_team_cleanup_task] )); then
		_hcom_get_launch_checkout cleanup "${main_checkout:-$PWD}" "$task_id" || return 1
		# Progress also succeeds when it keeps a worktree that still has work in it,
		# and the team stays open for that work.
		[[ -z "${reply[1]:-}" ]] || return 0
		_hcom_team_cleanup_task "$task_id"
	fi
}
# Reads cleanup_args and fills in task_id, show_help, branch_cleanup,
# lookup_args, and checkout_args. All of these are local variables of cleanup,
# which is the only caller. A relative database path stays as given for the task
# lookup, which runs from the caller's folder, and becomes absolute in
# checkout_args.
_progress_cleanup_arguments() {
	# Position of the argument currently being inspected.
	local argument_index=1
	# Database path read from either form of the --database option.
	local database_path

	while (( argument_index <= ${#cleanup_args} )); do
		case "${cleanup_args[argument_index]}" in
			--branch)
				branch_cleanup=1
				(( argument_index++ ))
				;;
			--database)
				if (( argument_index < ${#cleanup_args} )); then
					(( argument_index++ ))
					database_path="${cleanup_args[argument_index]}"
					lookup_args+=(--database "$database_path")
					if [[ "$database_path" != /* ]]; then
						checkout_args[argument_index]="$original_pwd/$database_path"
					fi
				fi
				;;
			-h|--help) show_help=1 ;;
			--branch=*) branch_cleanup=1 ;;
			--database=*)
				database_path="${cleanup_args[argument_index]#--database=}"
				lookup_args+=("${cleanup_args[argument_index]}")
				if [[ "$database_path" != /* ]]; then
					checkout_args[argument_index]="--database=$original_pwd/$database_path"
				fi
				;;
			--json) ;;
			tsk_*) task_id="${cleanup_args[argument_index]}" ;;
		esac
		(( argument_index++ ))
	done
}
# Prints the main checkout of a task's project. Prefers the checkout that shares
# the caller's Git folder; returns 1 when no recorded main checkout exists. A
# bare repository or a separate Git folder has no main checkout, so the helper
# skips any Git folder not named .git.
#
# @param  {string}  task_id
#     Task whose project owns the main checkout.
# @param  {string}  ...
#     Database option passed to the task lookup.
_progress_cleanup_main_checkout() {
	# Task whose project owns the main checkout.
	local task_id="$1"
	shift
	# Recorded checkout paths, including worktrees that may no longer exist.
	local -a checkouts=("${(@f)$(progress task find "$task_id" --json "$@" 2>/dev/null | jq -r '.data[]?.checkouts[]?' 2>/dev/null)}")
	# Recorded checkout currently being tried.
	local checkout
	# Git directory shared by the project's checkouts.
	local common_dir
	# Main checkout containing the shared Git directory.
	local main_checkout
	# Git directory shared by the caller's checkouts, if the caller is in one.
	local caller_common_dir="$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null)"
	# First main checkout found, used when the caller is outside the task's project.
	local first_checkout=""

	for checkout in "${checkouts[@]}"; do
		[[ -d "$checkout" ]] || continue
		common_dir="$(git -C "$checkout" rev-parse --path-format=absolute --git-common-dir 2>/dev/null)" || continue
		[[ "${common_dir:t}" == .git ]] || continue
		main_checkout="${common_dir:h}"
		if [[ -d "$main_checkout" ]]; then
			if [[ "$common_dir" == "$caller_common_dir" ]]; then
				print -r -- "$main_checkout"
				return 0
			fi
			[[ -n "$first_checkout" ]] || first_checkout="$main_checkout"
		fi
	done
	[[ -n "$first_checkout" ]] || return 1
	print -r -- "$first_checkout"
}
# @desc  List chunks for the selected next task, or for another task with --task ID
# @cat   progress
alias chunks="progress chunk list"
# @desc  Show details for the given chunk, or the selected next chunk if omitted
# @cat   progress
alias chunk="progress chunk get"
# @desc  Show the progress inbox messages
# @cat   progress
alias inbox="progress inbox"
# @desc  Add a new message to the progress inbox
# @cat   progress
alias inbox:add="progress inbox add"
# @desc  Complete the given task or chunk, depending on ID format
# @cat   progress
alias completed="progress complete";
# @desc  Summarise progress across all known projects
# @cat   progress
alias progress:check="progress summary"
