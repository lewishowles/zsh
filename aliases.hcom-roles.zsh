# Shared hcom role configuration and launchers.

# Clears the former team alias before the team function is loaded.
if (( $+aliases[team] )); then
	unalias team
fi

# Continues the next task or the task named by the first argument.
# @desc  Continue a complete hcom team with the next task or a task ID
# @cat   hcom
#
# @param  {string}  ...
#     An optional task ID followed by the team continue options.
cont() {
	if [[ $# -gt 0 && "$1" != -* ]]; then
		_hcom_launch_team cont orchestrator reviewer implementer scout continue --task "$1" "${@:2}"
		return
	fi

	_hcom_launch_team cont orchestrator reviewer implementer scout continue "$@"
}
if (( $+aliases[resume] )); then
	unalias resume
fi

# @desc  Resume a complete hcom team from the stored handoff or a task ID
# @cat   hcom
#
# @param  {string}  ...
#     An optional task ID followed by the team resume options.
resume() {
	if [[ $# -gt 0 && "$1" != -* ]]; then
		_hcom_launch_team resume orchestrator reviewer implementer scout resume --task "$1" "${@:2}"
		return
	fi

	_hcom_launch_team resume orchestrator reviewer implementer scout resume "$@"
}
# @desc  Resume a complete hcom team from the clipboard handoff
# @cat   hcom
alias handoff="team handoff"
# @desc  Start the Orchestrator hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
alias ho="orchestrator"
# @desc  Start the Reviewer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
alias hr="reviewer"
# @desc  Start the Implementer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
alias hi="implementer"
# @desc  Start the Scout hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
alias hs="scout"

# Role configuration fields: tool|tag|model|role_file|thinking.
# role_file may list several files, separated by commas with no spaces.
typeset -A HCOM_ROLE_CONFIG=(
	orchestrator "claude|orchestrator|opus|orchestrator.md|medium"
	implementer "codex|implementer|gpt-6-sol|implementer.md|medium"
	reviewer "claude|reviewer|opus|reviewer.md|medium"
	scout "codex|scout|gpt-6-luna|scout.md|medium"

	orchestrator-codex "codex|orchestrator|gpt-6-astra|orchestrator.md|medium"
	reviewer-codex "codex|reviewer|gpt-6-astra|reviewer.md|medium"

	implementer-claude "claude|implementer|sonnet|implementer.md|medium"
	scout-claude "claude|scout|haiku|scout.md|medium"

	learner-claude "claude|orchestrator|opus|orchestrator.md,learner.md|medium"
	learner-codex "codex|orchestrator|gpt-6-astra|orchestrator.md,learner.md|medium"
)

# Launches a role using its shared hcom configuration. With --task, or when the
# launch folder is a task's registered Progress worktree, the role joins that
# task's team in its worktree, the same team that team continue --task starts.
# A team label that is already set wins over the worktree folder, but not over --task.
#
# Call it as <role> [directory] [prompt] or <role> --task <id> [prompt].
# A launcher whose public name differs from the role, such as learn:claude,
# puts --command <name> straight after the role so errors use that name.
# Role commands such as scout pass their arguments straight through, so they
# accept --command too; it only changes the name shown in errors.
#
# @param  {string}  role
#     The configured role to launch.
# @param  {string}  command_name
#     Optional, given as --command <name>: the public command named in errors.
#     Defaults to the role name with colons, such as scout or orchestrator:codex.
# @param  {string}  task_id
#     Optional, given as --task <id>: the task whose team and worktree the role joins.
# @param  {string}  working_directory
#     Optional folder to launch in, defaulting to the current folder. Not accepted with --task.
# @param  {string}  initial_prompt
#     Optional first message for the role.
_hcom_launch_configured_role() {
	local role="$1"  # The configured role to launch.
	shift
	local command_name="${role//-/:}"  # The public command shown in error messages, such as scout.

	if [[ "${1:-}" == --command ]]; then
		command_name="$2"
		shift 2
	fi

	local original_directory="$PWD"  # The folder the command ran from, where Progress looks up the task.
	local working_directory=""  # The folder the role starts in.
	local initial_prompt=""  # The first message for the role, if any.
	local task_id=""  # The task whose team the role joins, from --task or the worktree folder name.
	local folder_task_id=""  # The launch folder's name, which is a task ID when the folder is a Progress worktree.
	local team_project_tag=""  # The task team's project tag, passed to the launched role.
	local team_label=""  # The task team's label, passed to the launched role.

	case "${1:-}" in
		--task)
			if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == --* ]]; then
				_hcom_command_error "$command_name" '' '--task' ' requires a task ID.'
				return 1
			fi

			task_id="$2"
			shift 2
			;;
		--*)
			_hcom_command_error "$command_name" 'unknown option: ' "$1"
			return 1
			;;
	esac

	if [[ -n "$task_id" ]]; then
		if [[ $# -gt 1 ]]; then
			_hcom_command_error "$command_name" 'usage: ' "$command_name --task <id> [prompt]"
			return 1
		fi

		initial_prompt="${1:-}"
	else
		working_directory="${1:-$PWD}"
		initial_prompt="${2:-}"
		folder_task_id="${working_directory:A:t}"

		# A team label the caller already set wins, so learn keeps its learner beside its Scout.
		if [[ -z "${HCOM_TEAM_LABEL:-}" && "$folder_task_id" == tsk_* ]] && _hcom_get_launch_checkout "$command_name" "$original_directory" "$folder_task_id" 2>/dev/null; then
			# Only the task's registered worktree joins its team; a subfolder or a lookalike folder launches as before.
			if [[ -n "${reply[1]}" && "$working_directory" -ef "${reply[1]}" ]]; then
				task_id="$folder_task_id"
			fi
		fi
	fi

	if [[ -n "$task_id" ]]; then
		_hcom_read_task_team "$command_name" "$original_directory" "$task_id" || return 1
		team_project_tag="${reply[1]}"
		team_label="${reply[2]}"
	fi

	# With --task, the launch folder is the task's registered worktree. The team is read
	# first so that an unknown task is reported as unknown, not as missing a worktree.
	if [[ -z "$working_directory" ]]; then
		_hcom_get_launch_checkout "$command_name" "$original_directory" "$task_id" || return 1
		working_directory="${reply[1]}"

		if [[ -z "$working_directory" ]]; then
			_hcom_command_error "$command_name" 'task ' "$task_id" ' has no registered worktree.'
			return 1
		fi
	fi

	local -a role_config
	role_config=("${(@s:|:)HCOM_ROLE_CONFIG[$role]}")

	local -a role_file_arguments  # One --role-file option for each configured role file.
	local role_file  # The configured role file being added.
	for role_file in "${(@s:,:)role_config[4]}"; do
		role_file_arguments+=(--role-file "$role_file")
	done

	local -a launch_arguments=(  # Options for the role launch, shared by both launch forms below.
		--command "$command_name"
		--tool "${role_config[1]}"
		--tag "${role_config[2]}"
		--model "${role_config[3]}"
		"${role_file_arguments[@]}"
		--thinking "${role_config[5]}"
		--working-dir "$working_directory"
		--initial-prompt "$initial_prompt"
	)

	# A task team's settings go in the launched role's environment, as team continue passes them.
	# Without a task, the role keeps whatever team settings the shell already has.
	if [[ -n "$task_id" ]]; then
		HCOM_TEAM_PROJECT_TAG="$team_project_tag" HCOM_TEAM_LABEL="$team_label" _hcom_launch_role "${launch_arguments[@]}"
	else
		_hcom_launch_role "${launch_arguments[@]}"
	fi
}

# @desc  Start the Orchestrator hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
orchestrator() {
	_hcom_launch_configured_role orchestrator "$@"
}

# @desc  Start the Codex Orchestrator hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
orchestrator:codex() {
	_hcom_launch_configured_role orchestrator-codex "$@"
}

# @desc  Start the Implementer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
implementer() {
	_hcom_launch_configured_role implementer "$@"
}

# @desc  Start the Claude Implementer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
implementer:claude() {
	_hcom_launch_configured_role implementer-claude "$@"
}

# @desc  Start the Reviewer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
reviewer() {
	_hcom_launch_configured_role reviewer "$@"
}

# @desc  Start the Codex Reviewer hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
reviewer:codex() {
	_hcom_launch_configured_role reviewer-codex "$@"
}

# @desc  Start the Scout hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
scout() {
	_hcom_launch_configured_role scout "$@"
}

# @desc  Start the Claude Scout hcom role on the account with more quota headroom; --task <id> joins that task's team
# @cat   hcom
scout:claude() {
	_hcom_launch_configured_role scout-claude "$@"
}
