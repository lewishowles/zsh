# hcom team layout and configured role launchers.

alias team="hcom-team"
alias ho="hcom-orchestrator"
alias hr="hcom-reviewer"
alias hi="hcom-implementer"
alias hs="hcom-scout"

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
		printf '%s: usage: %s [--team <label>] [working-directory] [initial-prompt]\n' "$command_name" "$command_name" >&2
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

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" \
		"$reviewer_command" \
		"$implementer_command" \
		"$scout_command"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	if [[ -n "$team_label" ]]; then
		printf 'Starting hcom team %s in %s.\n' "$team_label" "$working_directory"
	fi

	HCOM_TEAM_LABEL="$team_label" "$orchestrator_launcher" "$working_directory" "$initial_prompt"
}

# @desc  Start the complete hcom team, optionally grouped by team label
# @cat   hcom
#
# Usage: hcom-team [--team <label>] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team() {
	_hcom_launch_team hcom-team hcom-orchestrator hcom-reviewer "$@"
}

# @desc  Start the complete Codex hcom team, optionally grouped by team label
# @cat   hcom
#
# Usage: hcom-team-codex [--team <label>] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team-codex() {
	_hcom_launch_team hcom-team-codex hcom-orchestrator-codex hcom-reviewer-codex "$@"
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
