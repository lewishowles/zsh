# hcom role launchers for manually managed Hyper tabs.

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

# Launches one role in the current terminal, using the selected project directory.
#
# @param  {string}  tool
#     The agent tool to launch, such as claude or codex.
# @param  {string}  tag
#     The stable hcom role tag.
# @param  {string}  model
#     The model passed to hcom.
# @param  {string}  role_file
#     The role prompt filename under HCOM_ROLE_DIR.
# @param  {string}  working_directory
#     The project directory, defaulting to the current directory.
# @param  {string}  initial_prompt
#     An optional initial user prompt for the new agent.
_hcom_launch_role() {
	local tool="$1"
	local tag="$2"
	local model="$3"
	local role_file="$4"
	local working_directory="${5:-$PWD}"
	local initial_prompt="${6:-}"
	local role_path="$HCOM_ROLE_DIR/$role_file"
	local role_prompt
	local -a hcom_arguments

	if [[ ! -d "$working_directory" ]]; then
		printf 'hcom: working directory not found: %s\n' "$working_directory" >&2
		return 1
	fi

	if [[ ! -f "$role_path" ]]; then
		printf 'hcom: role prompt not found: %s\n' "$role_path" >&2
		return 1
	fi

	role_prompt="$(<"$role_path")"
	hcom_arguments=(
		"$tool"
		--tag "$tag"
		--model "$model"
		--dir "$working_directory"
		--hcom-system-prompt "$role_prompt"
	)

	if [[ "$tool" = "codex" ]]; then
		hcom_arguments+=(--config 'model_reasoning_effort="xhigh"')
	fi

	if [[ -n "$initial_prompt" ]]; then
		hcom_arguments+=(--hcom-prompt "$initial_prompt")
	fi

	HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
}

# @desc  Start the Claude Orchestrator hcom role
# @cat   hcom
hcom-orchestrator() {
	_hcom_launch_role claude orchestrator sonnet orchestrator.md "$@"
}

# @desc  Start the Codex Implementer hcom role
# @cat   hcom
hcom-implementer() {
	_hcom_launch_role codex implementer gpt-5.6-luna implementer.md "$@"
}

# @desc  Start the Claude Reviewer hcom role
# @cat   hcom
hcom-reviewer() {
	_hcom_launch_role claude reviewer sonnet reviewer.md "$@"
}

# @desc  Start the Claude Scout hcom role
# @cat   hcom
hcom-scout() {
	_hcom_launch_role claude scout haiku scout.md "$@"
}
