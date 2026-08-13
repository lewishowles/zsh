# hcom team layout and configured role launchers.

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

	if [[ $# -gt 2 ]]; then
		printf '%s: usage: %s [working-directory] [initial-prompt]\n' "$command_name" "$command_name" >&2
		return 1
	fi

	local working_directory="${1:-$PWD}"
	local initial_prompt="${2:-}"

	if [[ ! -d "$working_directory" ]]; then
		printf '%s: working directory not found: %s\n' "$command_name" "$working_directory" >&2
		return 1
	fi

	local quoted_working_directory="${(q)working_directory}"

	local reviewer_command="$reviewer_launcher $quoted_working_directory"
	local implementer_command="hcom-implementer $quoted_working_directory"
	local scout_command="hcom-scout $quoted_working_directory"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" \
		"$reviewer_command" \
		"$implementer_command" \
		"$scout_command"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	"$orchestrator_launcher" "$working_directory" "$initial_prompt"
}

# @desc  Start the complete hcom team in four Ghostty panes
# @cat   hcom
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team() {
	_hcom_launch_team hcom-team hcom-orchestrator hcom-reviewer "$@"
}

# @desc  Start the complete Codex hcom team in four Ghostty panes
# @cat   hcom
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
	orchestrator-codex "codex|orchestrator|gpt-5.6-sol|orchestrator.md|medium"
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
