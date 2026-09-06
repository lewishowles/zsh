# Shared hcom role configuration and launchers.

# Provides short names for the team and shared role launchers.
# @desc  Start, resume, or continue the complete hcom team
# @cat   hcom
alias team="hcom:team"
# @desc  Start the Orchestrator hcom role
# @cat   hcom
alias ho="hcom:orchestrator"
# @desc  Start the Reviewer hcom role
# @cat   hcom
alias hr="hcom:reviewer"
# @desc  Start the Implementer hcom role
# @cat   hcom
alias hi="hcom:implementer"
# @desc  Start the Scout hcom role
# @cat   hcom
alias hs="hcom:scout"

# Role configuration fields: tool|tag|model|role_file|thinking.
typeset -A HCOM_ROLE_CONFIG=(
	orchestrator "claude|orchestrator|sonnet|orchestrator.md|high"
	orchestrator-codex "codex|orchestrator|gpt-6-astra|orchestrator.md|medium"
	implementer "codex|implementer|gpt-6-astra|implementer.md|low"
	reviewer "claude|reviewer|sonnet|reviewer.md|high"
	reviewer-codex "codex|reviewer|gpt-6-astra|reviewer.md|medium"
	scout "codex|scout|gpt-5.6-luna|scout.md|medium"
	scout-claude "codex|scout-claude|gpt-5.6-luna|scout.md|medium"
	scout-codex "codex|scout-codex|gpt-5.6-luna|scout.md|medium"
	learner-claude "claude|learner-claude|opus|learner.md|high"
	learner-codex "codex|learner-codex|gpt-6-astra|learner.md|high"
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
hcom:orchestrator() {
	_hcom_launch_configured_role orchestrator "$@"
}

# @desc  Start the Codex Orchestrator hcom role
# @cat   hcom
hcom:orchestrator:codex() {
	_hcom_launch_configured_role orchestrator-codex "$@"
}

# @desc  Start the Implementer hcom role
# @cat   hcom
hcom:implementer() {
	_hcom_launch_configured_role implementer "$@"
}

# @desc  Start the Reviewer hcom role
# @cat   hcom
hcom:reviewer() {
	_hcom_launch_configured_role reviewer "$@"
}

# @desc  Start the Codex Reviewer hcom role
# @cat   hcom
hcom:reviewer:codex() {
	_hcom_launch_configured_role reviewer-codex "$@"
}

# @desc  Start the Scout hcom role
# @cat   hcom
hcom:scout() {
	_hcom_launch_configured_role scout "$@"
}

# @desc  Start the Claude planning peer's Scout
# @cat   hcom
hcom:scout:claude() {
	_hcom_launch_configured_role scout-claude "$@"
}

# @desc  Start the Codex planning peer's Scout
# @cat   hcom
hcom:scout:codex() {
	_hcom_launch_configured_role scout-codex "$@"
}
