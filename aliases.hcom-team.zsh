# hcom team layout and configured role launchers.

# Ghostty team layout (hcom-team and AppleScript)

# @desc  Start the complete hcom team in four Ghostty panes
# @cat   hcom
#
# Creates this layout in the current Ghostty tab:
#
#   orchestrator | implementer
#   reviewer     | scout
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
hcom-team() {
	if [[ $# -gt 2 ]]; then
		printf 'hcom-team: usage: hcom-team [working-directory] [initial-prompt]\n' >&2
		return 1
	fi

	local working_directory="${1:-$PWD}"
	local initial_prompt="${2:-}"

	if [[ ! -d "$working_directory" ]]; then
		printf 'hcom-team: working directory not found: %s\n' "$working_directory" >&2
		return 1
	fi

	local quoted_working_directory="${(q)working_directory}"

	local reviewer_command="hcom-reviewer $quoted_working_directory"
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

	hcom-orchestrator "$working_directory" "$initial_prompt"
}

# Role launchers

# Role configuration fields: tool|tag|model|role_file|thinking.
typeset -A HCOM_ROLE_CONFIG=(
	orchestrator "claude|orchestrator|sonnet|orchestrator.md|high"
	implementer "codex|implementer|gpt-5.6-luna|implementer.md|xhigh"
	reviewer "claude|reviewer|sonnet|reviewer.md|high"
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
