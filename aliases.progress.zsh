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
# Rex team. The panes are only closed once Progress has actually removed the
# task's checkout. That check reads the default Progress database, even when
# --database names another one.
#
# @param  {string}  ...
#     Arguments passed to progress worktree cleanup.
cleanup() {
	# Arguments passed on unchanged to progress worktree cleanup.
	local -a cleanup_args=("$@")
	# Task named in the arguments, whose team panes are closed afterwards.
	local task_id=""
	# Argument currently being inspected.
	local argument
	# Whether the next argument is an option's value.
	local skip_value=0
	# Whether the arguments ask for help, so Progress only prints its usage.
	local show_help=0

	for argument in "${cleanup_args[@]}"; do
		if (( skip_value )); then
			skip_value=0
			continue
		fi
		case "$argument" in
			--branch|--database) skip_value=1 ;;
			-h|--help) show_help=1 ;;
			--branch=*|--database=*|--json) ;;
			tsk_*) task_id="$argument" ;;
		esac
	done

	progress worktree cleanup "${cleanup_args[@]}" || return $?
	if [[ -n "$task_id" && -n "${REX_SESSION:-}" ]] && (( ! show_help && $+functions[_hcom_team_cleanup_task] )); then
		_hcom_get_launch_checkout cleanup "$PWD" "$task_id" || return 1
		# Progress also succeeds when it keeps a worktree that still has work in it,
		# and the team stays open for that work.
		[[ -z "${reply[1]:-}" ]] || return 0
		_hcom_team_cleanup_task "$task_id"
	fi
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
