# hcom role launchers for manually managed Hyper tabs.

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

# Launches one role in the current terminal, using the selected project directory.
#
# `--hcom-system-prompt` doesn't reach the agent's actual system prompt (verified: the
# role text never appears in the transcript, only hcom's own onboarding block does).
# Deliver the role prompt through each tool's native mechanism instead: claude's
# `--append-system-prompt`, codex's `HCOM_CODEX_SYSTEM_PROMPT` env var.
#
# @param  {string}  tool
#     The agent tool to launch, such as claude or codex.
# @param  {string}  tag
#     The stable hcom role tag.
# @param  {string}  model
#     The model passed to hcom.
# @param  {string}  role_file
#     The role prompt filename under HCOM_ROLE_DIR.
# @param  {string}  auto_mode
#     Non-empty for low-friction approvals: claude's `--permission-mode auto`,
#     or codex's `--ask-for-approval on-request --sandbox workspace-write`.
# @param  {string}  working_directory
#     The project directory, defaulting to the current directory.
# @param  {string}  initial_prompt
#     An optional initial user prompt for the new agent.
_hcom_launch_role() {
	local tool="$1"
	local tag="$2"
	local model="$3"
	local role_file="$4"
	local auto_mode="$5"
	local working_directory="${6:-$PWD}"
	local initial_prompt="${7:-}"
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
	)

	if [[ "$tool" = "codex" ]]; then
		[[ "$tag" = "implementer" ]] && hcom_arguments+=(--config 'model_reasoning_effort="xhigh"')
		[[ -n "$auto_mode" ]] && hcom_arguments+=(--ask-for-approval on-request --sandbox workspace-write)
	else
		hcom_arguments+=(--append-system-prompt "$role_prompt")
		[[ -n "$auto_mode" ]] && hcom_arguments+=(--permission-mode auto)
	fi

	if [[ -n "$initial_prompt" ]]; then
		hcom_arguments+=(--hcom-prompt "$initial_prompt")
	fi

	if [[ "$tool" = "codex" ]]; then
		HCOM_TERMINAL=default HCOM_CODEX_SYSTEM_PROMPT="$role_prompt" command hcom "${hcom_arguments[@]}"
	else
		HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
	fi
}

# @desc  Start the Claude Orchestrator hcom role (auto permission mode)
# @cat   hcom
hcom-orchestrator() {
	_hcom_launch_role claude orchestrator sonnet orchestrator.md 1 "$@"
}

# @desc  Start the Codex Implementer hcom role
# @cat   hcom
hcom-implementer() {
	_hcom_launch_role codex implementer gpt-5.6-luna implementer.md "" "$@"
}

# @desc  Start the Claude Reviewer hcom role (auto permission mode)
# @cat   hcom
hcom-reviewer() {
	_hcom_launch_role claude reviewer sonnet reviewer.md 1 "$@"
}

# @desc  Start the Codex Scout hcom role (auto approval mode)
# @cat   hcom
hcom-scout() {
	_hcom_launch_role codex scout gpt-5.4-mini scout.md 1 "$@"
}
