# hcom team layout and configured role launchers.

alias team="hcom-team"
alias ho="hcom-orchestrator"
alias hr="hcom-reviewer"
alias hi="hcom-implementer"
alias hs="hcom-scout"

# Returns the exact role tags for a team scope.
#
# @param  {string}  working_directory
#     The directory selected for the team.
# @param  {string}  team_label
#     The optional label selected for the team.
_hcom_team_tags() {
	local working_directory="$1"
	local team_label="$2"
	local repository_tag
	local tag_prefix

	repository_tag="$(_hcom_scoped_tag "$working_directory")" || return 1
	tag_prefix="$repository_tag"

	if [[ -n "$team_label" ]]; then
		tag_prefix+="-$team_label"
	fi

	print -r -- "$tag_prefix-orchestrator|$tag_prefix-reviewer|$tag_prefix-implementer|$tag_prefix-scout"
}

# Stops agents for exact team tags, ignoring agents that are already stopped.
#
# @param  {string}  team_tags
#     Pipe-separated exact hcom tags to stop.
_hcom_stop_team_tags() {
	local team_tags="$1"
	local tag
	local -a exact_tags

	exact_tags=("${(@s:|:)team_tags}")

	for tag in "${exact_tags[@]}"; do
		if [[ -n "$tag" ]]; then
			command hcom kill "tag:$tag" >/dev/null 2>&1 || :
		fi
	done
}

# Closes tracked Ghostty panes, ignoring panes that have already disappeared.
#
# @param  {string}  terminal_ids
#     Pipe-separated Ghostty terminal IDs to close.
_hcom_close_team_terminals() {
	local terminal_ids="$1"

	if [[ -z "$terminal_ids" ]]; then
		return 0
	fi

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" --close "$terminal_ids" >/dev/null 2>&1 || :
}

# Clears the active team's shell state.
_hcom_clear_team_scope() {
	unset HCOM_ACTIVE_TEAM_DIRECTORY
	unset HCOM_ACTIVE_TEAM_LABEL
	unset HCOM_ACTIVE_TEAM_TAGS
	unset HCOM_ACTIVE_TEAM_TERMINAL_IDS
	unset HCOM_TEAM_TERMINAL_IDS
}

# Starts a complete hcom team with the requested orchestrator and reviewer.
#
# Creates this layout in the current Ghostty tab:
#
#   orchestrator | implementer
#   reviewer     | scout
#
# @param  {string}  command_name
#     Public command name used in validation errors.
# @param  {string}  orchestrator_launcher
#     Function that starts the orchestrator role.
# @param  {string}  reviewer_launcher
#     Function that starts the reviewer role.
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
_hcom_launch_team() {
	local command_name="$1"
	local orchestrator_launcher="$2"
	local reviewer_launcher="$3"
	shift 3

	local team_label=""
	local keep_agents=0
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--team)
				if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == --* ]]; then
					printf '%s: --team requires a label.\n' "$command_name" >&2
					return 1
				fi

				team_label="$2"
				shift 2
				;;
			--keep-agents)
				keep_agents=1
				shift
				;;
			--)
				shift
				break
				;;
			--*)
				printf '%s: unknown option: %s\n' "$command_name" "$1" >&2
				return 1
				;;
			*) break ;;
		esac
	done

	if [[ $# -gt 2 ]]; then
		printf '%s: usage: %s [--team <label>] [--keep-agents] [working-directory] [initial-prompt]\n' "$command_name" "$command_name" >&2
		return 1
	fi

	if [[ -n "$team_label" ]]; then
		_hcom_validate_team_label "$team_label" "$command_name" || return 1
	fi

	local working_directory="${1:-$PWD}"
	local initial_prompt="${2:-}"

	if [[ ! -d "$working_directory" ]]; then
		printf '%s: working directory not found: %s\n' "$command_name" "$working_directory" >&2
		return 1
	fi

	local quoted_working_directory="${(q)working_directory}"

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env=""
	[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && account_env+="CLAUDE_CONFIG_DIR=${(q)CLAUDE_CONFIG_DIR} "
	[[ -n "${CODEX_HOME:-}" ]] && account_env+="CODEX_HOME=${(q)CODEX_HOME} "
	local team_env=""
	[[ -n "$team_label" ]] && team_env+="HCOM_TEAM_LABEL=${(q)team_label} "
	local launch_env="${account_env}${team_env}"

	local reviewer_command="${launch_env}$reviewer_launcher $quoted_working_directory"
	local implementer_command="${launch_env}hcom-implementer $quoted_working_directory"
	local scout_command="${launch_env}hcom-scout $quoted_working_directory"
	local team_tags
	team_tags="$(_hcom_team_tags "$working_directory" "$team_label")" || return 1

	# A terminal ID survives the agent session and lets the next launch replace
	# only the teammate panels created by this orchestrator shell.
	local previous_terminal_ids="${HCOM_TEAM_TERMINAL_IDS:-}"
	local previous_team_tags="${HCOM_ACTIVE_TEAM_TAGS:-}"
	if [[ -n "$previous_terminal_ids" ]] && [[ -n "$previous_team_tags" ]]; then
		_hcom_stop_team_tags "$previous_team_tags"
	fi

	local team_terminal_ids
	team_terminal_ids="$(
		/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" \
			"$reviewer_command" \
			"$implementer_command" \
			"$scout_command" \
			"$previous_terminal_ids"
	)"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	# The launching shell's stored scope, so hcom-team-stop needs no arguments
	# there and can tell which team it is scoped to.
	typeset -g HCOM_ACTIVE_TEAM_DIRECTORY="$working_directory"
	typeset -g HCOM_ACTIVE_TEAM_LABEL="$team_label"
	typeset -g HCOM_ACTIVE_TEAM_TAGS="$team_tags"
	typeset -g HCOM_ACTIVE_TEAM_TERMINAL_IDS="$team_terminal_ids"
	typeset -g HCOM_TEAM_TERMINAL_IDS="$team_terminal_ids"

	if [[ -n "$team_label" ]]; then
		printf 'Starting hcom team %s in %s.\n' "$team_label" "$working_directory"
	fi

	local orchestrator_exit_code
	# Without this, SIGINT during the foreground orchestrator call aborts this whole function,
	# skipping the cleanup below; localtraps restores the prior INT trap on any return path.
	setopt localoptions localtraps
	trap ':' INT
	if HCOM_TEAM_LABEL="$team_label" "$orchestrator_launcher" "$working_directory" "$initial_prompt"; then
		orchestrator_exit_code=0
	else
		orchestrator_exit_code=$?
	fi

	if (( keep_agents == 0 )); then
		_hcom_stop_team_tags "${team_tags#*|}"
		_hcom_close_team_terminals "${team_terminal_ids#*|}"
		_hcom_clear_team_scope
	fi

	return "$orchestrator_exit_code"
}

# @desc  Start the complete hcom team, scoped to this directory and optionally a team label
# @cat   hcom
#
# Usage: hcom-team [--team <label>] [--keep-agents] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team() {
	_hcom_launch_team hcom-team hcom-orchestrator hcom-reviewer "$@"
}

# @desc  Start the complete Codex hcom team, scoped to this directory and optionally a team label
# @cat   hcom
#
# Usage: hcom-team-codex [--team <label>] [--keep-agents] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team-codex() {
	_hcom_launch_team hcom-team-codex hcom-orchestrator-codex hcom-reviewer-codex "$@"
}

# @desc  Stop the exact hcom team for a directory and optional team label
# @cat   hcom
#
# Usage: hcom-team-stop [--team <label>] [working-directory]
#
# Run with no arguments from the shell that launched the team, or with
# --team/a directory from elsewhere. From another shell this always stops
# the team's agents, but can only close its Ghostty panes when that scope
# matches the launching shell's own stored team.
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the active team's directory or the current directory with an explicit scope.
# @param  {string}  team_label
#     Optional team label. Defaults to the active team's label when no scope is supplied.
hcom-team-stop() {
	local team_label=""
	local working_directory=""
	local explicit_scope=0  # Whether --team or a directory was given, rather than using the launching shell's stored team.
	local usage_message="hcom-team-stop: usage: hcom-team-stop [--team <label>] [working-directory]"

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--team)
				if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == --* ]]; then
					printf 'hcom-team-stop: --team requires a label.\n' >&2
					return 1
				fi

				team_label="$2"
				explicit_scope=1
				shift 2
				;;
			--)
				shift
				break
				;;
			--*)
				printf 'hcom-team-stop: unknown option: %s\n' "$1" >&2
				return 1
				;;
			*)
				if [[ -n "$working_directory" ]]; then
					printf '%s\n' "$usage_message" >&2
					return 1
				fi

				working_directory="$1"
				explicit_scope=1
				shift
				;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		if [[ -n "$working_directory" ]]; then
			printf '%s\n' "$usage_message" >&2
			return 1
		fi

		working_directory="$1"
		explicit_scope=1
		shift
	fi

	if [[ $# -gt 0 ]]; then
		printf '%s\n' "$usage_message" >&2
		return 1
	fi

	local team_tags=""
	local terminal_ids=""
	local scope_matches_active=0  # Whether an explicit --team/directory scope is also the launching shell's stored team, so its stored state can be cleared too.

	if (( explicit_scope == 0 )); then
		if [[ -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]]; then
			printf 'No active hcom team to stop.\n'
			return 0
		fi

		working_directory="$HCOM_ACTIVE_TEAM_DIRECTORY"
		team_label="$HCOM_ACTIVE_TEAM_LABEL"
		team_tags="$HCOM_ACTIVE_TEAM_TAGS"
		terminal_ids="$HCOM_ACTIVE_TEAM_TERMINAL_IDS"
	else
		working_directory="${working_directory:-$PWD}"

		if [[ ! -d "$working_directory" ]]; then
			printf 'hcom-team-stop: working directory not found: %s\n' "$working_directory" >&2
			return 1
		fi

		if [[ -n "$team_label" ]]; then
			_hcom_validate_team_label "$team_label" hcom-team-stop || return 1
		fi

		team_tags="$(_hcom_team_tags "$working_directory" "$team_label")" || return 1

		if [[ -n "${HCOM_ACTIVE_TEAM_DIRECTORY:-}" ]] && [[ "${working_directory:A}" = "${HCOM_ACTIVE_TEAM_DIRECTORY:A}" ]] && [[ "$team_label" = "${HCOM_ACTIVE_TEAM_LABEL:-}" ]]; then
			scope_matches_active=1
			terminal_ids="${HCOM_ACTIVE_TEAM_TERMINAL_IDS:-}"
		fi
	fi

	_hcom_stop_team_tags "$team_tags"
	_hcom_close_team_terminals "$terminal_ids"

	if (( explicit_scope == 0 || scope_matches_active == 1 )); then
		_hcom_clear_team_scope
	fi
}

# Role launchers

# Role configuration fields: tool|tag|model|role_file|thinking.
typeset -A HCOM_ROLE_CONFIG=(
	orchestrator "claude|orchestrator|sonnet|orchestrator.md|high"
	orchestrator-codex "codex|orchestrator|gpt-5.6-sol|orchestrator.md|high"
	implementer "codex|implementer|gpt-5.6-luna|implementer.md|xhigh"
	reviewer "claude|reviewer|sonnet|reviewer.md|high"
	reviewer-codex "codex|reviewer|gpt-5.6-sol|reviewer.md|high"
	scout "codex|scout|gpt-5.6-luna|scout.md|medium"
	scout-claude "codex|scout-claude|gpt-5.6-luna|scout.md|medium"
	scout-codex "codex|scout-codex|gpt-5.6-luna|scout.md|medium"
	learner-claude "claude|learner-claude|opus|learner.md|high"
	learner-codex "codex|learner-codex|gpt-5.6-sol|learner.md|high"
	scout-learn-claude "codex|scout-learn-claude|gpt-5.6-luna|scout.md|medium"
	scout-learn-codex "codex|scout-learn-codex|gpt-5.6-luna|scout.md|medium"
)

# Launches a role using its shared hcom configuration.
#
# @param  {string}  role
#     The configured role to launch.
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the role.
_hcom_launch_configured_role() {
	local role="$1"
	shift

	local -a role_config
	role_config=("${(@s:|:)HCOM_ROLE_CONFIG[$role]}")

	_hcom_launch_role \
		--tool "${role_config[1]}" \
		--tag "${role_config[2]}" \
		--model "${role_config[3]}" \
		--role-file "${role_config[4]}" \
		--thinking "${role_config[5]}" \
		--working-dir "${1:-$PWD}" \
		--initial-prompt "${2:-}"
}

# @desc  Start the Orchestrator hcom role
# @cat   hcom
hcom-orchestrator() {
	_hcom_launch_configured_role orchestrator "$@"
}

# @desc  Start the Codex Orchestrator hcom role
# @cat   hcom
hcom-orchestrator-codex() {
	_hcom_launch_configured_role orchestrator-codex "$@"
}

# @desc  Start the Implementer hcom role
# @cat   hcom
hcom-implementer() {
	_hcom_launch_configured_role implementer "$@"
}

# @desc  Start the Reviewer hcom role
# @cat   hcom
hcom-reviewer() {
	_hcom_launch_configured_role reviewer "$@"
}

# @desc  Start the Codex Reviewer hcom role
# @cat   hcom
hcom-reviewer-codex() {
	_hcom_launch_configured_role reviewer-codex "$@"
}

# @desc  Start the Scout hcom role
# @cat   hcom
hcom-scout() {
	_hcom_launch_configured_role scout "$@"
}

# @desc  Start the Claude planning peer's Scout
# @cat   hcom
hcom-scout-claude() {
	_hcom_launch_configured_role scout-claude "$@"
}

# @desc  Start the Codex planning peer's Scout
# @cat   hcom
hcom-scout-codex() {
	_hcom_launch_configured_role scout-codex "$@"
}
