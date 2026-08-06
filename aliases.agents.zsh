# hcom role launchers for manually managed Hyper tabs.

# Keep Claude Code in the normal terminal buffer for native selection and scrollback.
export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

# @desc  Run Codex with shared configuration defaults
# @cat   agent
alias codex="codex"
# @desc  Run claude with auto-mode
# @cat   agent
alias claude="claude --permission-mode auto"

# @desc  Open the current PROGRESS.md file
# @cat   agent
alias progress="zed PROGRESS.md"
# @desc  Open the current AGENTS.md file
# @cat   agent
alias agents="zed AGENTS.md"

# @desc  Set up agent files (Claude + Codex) globally
# @cat   agents
alias agents:setup:global="$HOME/Dev/Configuration/Agents/scripts/setup-global.sh --both"
# @desc  Set up agent files (Claude + Codex) for the current project
# @cat   agents
alias agents:setup="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --both"
# @desc  Initialise WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --write-workspace"
# @desc  Force-regenerate WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace:force="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --force-workspace"

# Core launch helpers

# Launches one role in the current terminal, using the selected project directory.
#
# `--hcom-system-prompt` doesn't reach the agent's actual system prompt (verified: the
# role text never appears in the transcript, only hcom's own onboarding block does).
# Deliver the role prompt through each tool's native mechanism instead: claude's
# `--append-system-prompt`, codex's `HCOM_CODEX_SYSTEM_PROMPT` env var.
#
# Usage:
#   _hcom_launch_role \
#     --tool claude \
#     --tag orchestrator \
#     --model sonnet \
#     --role-file orchestrator.md \
#     [--working-dir /path] \
#     [--initial-prompt "..."] \
#     [--thinking medium]
_hcom_launch_role() {
	local tool="" tag="" model="" role_file=""
	local working_directory="$PWD" initial_prompt="" thinking_effort=""

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--tool) tool="$2"; shift 2 ;;
			--tag) tag="$2"; shift 2 ;;
			--model) model="$2"; shift 2 ;;
			--role-file) role_file="$2"; shift 2 ;;
			--working-dir) working_directory="$2"; shift 2 ;;
			--initial-prompt) initial_prompt="$2"; shift 2 ;;
			--thinking) thinking_effort="$2"; shift 2 ;;
			*) printf 'hcom: unknown option: %s\n' "$1" >&2; return 1 ;;
		esac
	done

	# Validate required parameters
	if [[ -z "$tool" ]] || [[ -z "$tag" ]] || [[ -z "$model" ]] || [[ -z "$role_file" ]]; then
		printf 'hcom: missing required parameters\n' >&2
		return 1
	fi

	if [[ ! -d "$working_directory" ]]; then
		printf 'hcom: working directory not found: %s\n' "$working_directory" >&2
		return 1
	fi

	local role_path="$HCOM_ROLE_DIR/$role_file"
	if [[ ! -f "$role_path" ]]; then
		printf 'hcom: role prompt not found: %s\n' "$role_path" >&2
		return 1
	fi

	local role_prompt="$(<"$role_path")"
	local repository_tag scoped_tag
	repository_tag="$(_hcom_scoped_tag "$working_directory")" || return 1
	scoped_tag="${repository_tag}-${tag}"

	local -a hcom_arguments
	hcom_arguments=(
		"$tool"
		--tag "$scoped_tag"
		--model "$model"
		--dir "$working_directory"
	)

	if [[ "$tool" != "codex" ]]; then
		hcom_arguments+=(--append-system-prompt "$role_prompt")
	fi

	[[ -n "$initial_prompt" ]] && hcom_arguments+=(--hcom-prompt "$initial_prompt")

	if [[ -n "$thinking_effort" ]]; then
		if [[ "$tool" = "codex" ]]; then
			hcom_arguments+=(--config "model_reasoning_effort=\"$thinking_effort\"")
		else
			hcom_arguments+=(--effort "$thinking_effort")
		fi
	fi

	if [[ "$tool" = "codex" ]]; then
		hcom_arguments+=(
			--config 'model_verbosity="low"'
			--config 'model_reasoning_summary="none"'
			--config 'hide_agent_reasoning=true'
		)
		HCOM_TERMINAL=default HCOM_CODEX_SYSTEM_PROMPT="$role_prompt" command hcom "${hcom_arguments[@]}"
	else
		HCOM_CLAUDE_ARGS='--permission-mode auto' HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
	fi
}

# Returns the repository portion of an hcom tag.
#
# @param  {string}  working_directory
#     The directory selected for the agent launch.
_hcom_scoped_tag() {
	local directory_name="${1:t}"
	local repository_tag

	repository_tag="$(print -r -- "$directory_name" | tr -cs '[:alnum:]' '-')"
	repository_tag="${repository_tag%-}"

	if [[ -z "$repository_tag" ]]; then
		printf 'hcom: cannot derive a tag from directory: %s\n' "$1" >&2
		return 1
	fi

	print -r -- "$repository_tag"
}

# Prints the tag for an active or recently stopped hcom agent.
#
# @param  {string}  name
#     The bare hcom agent name.
_hcom_resolve_agent_tag() {
	local name="$1"
	local details tag

	details="$(command hcom list -v "$name" 2>&1)"
	if [[ $? -ne 0 ]]; then
		details="$(command hcom list --stopped "$name" 2>&1)"
	fi

	tag="$(print -r -- "$details" | awk -F': *' '/^  Tag:/{print $2}')"
	print -r -- "$tag"
}

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

typeset -A HCOM_ROLE_CONFIG=(
	orchestrator "claude|orchestrator|sonnet|orchestrator.md|high"
	implementer "codex|implementer|gpt-5.6-luna|implementer.md|xhigh"
	reviewer "claude|reviewer|sonnet|reviewer.md|high"
	scout "codex|scout|gpt-5.6-luna|scout.md|medium"
	scout-claude "codex|scout-claude|gpt-5.6-luna|scout.md|medium"
	scout-codex "codex|scout-codex|gpt-5.6-luna|scout.md|medium"
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

# Plan-review launchers

# @desc  Start the complete hcom plan review in four Ghostty panes
# @cat   hcom
#
# Creates this layout in the current Ghostty tab:
#
#   plan-claude  | plan-codex
#   scout-claude | scout-codex
#
# Each planning peer routes its research through the scout in its own
# column (`<repo>-scout-claude` / `<repo>-scout-codex`); once both peers
# report `Ready as written` or `Changes requested`, pick whichever one
# found more to consolidate with `project-review-task`.
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
hcom-plan() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-plan: usage: hcom-plan <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"
	local quoted_task_name="${(q)task_name}"

	local plan_codex_command="hcom-plan-codex $quoted_task_name"
	local scout_claude_command="hcom-scout-claude"
	local scout_codex_command="hcom-scout-codex"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-plan.applescript" \
		"$plan_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	hcom-plan-claude "$task_name"
}

# Builds the shared planning-peer independent-review initial prompt.
#
# @param  {string}  task_name
#     The task name or path to resolve for review.
_hcom_plan_prompt() {
	local quoted_task_name="${(q)1}"

	print -r -- "Use project-review-task in independent review mode to review task ${quoted_task_name}. Resolve exactly one task using the skill's exact-resolution order. Do not edit the task or contact the peer. Retain the complete review packet, report the resolved path, content hash, verdict, every finding and its evidence, and \"Safe to reset: no\", then wait."
}

# @desc  Start a Claude planning-peer task review
# @cat   hcom
function hcom-plan-claude() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-plan-claude: usage: hcom-plan-claude <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"

	_hcom_launch_role \
		--tool claude \
		--tag planning-peer \
		--model opus \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_plan_prompt "$task_name")"
}

# @desc  Start a Codex planning-peer task review
# @cat   hcom
function hcom-plan-codex() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-plan-codex: usage: hcom-plan-codex <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"

	_hcom_launch_role \
		--tool codex \
		--tag planning-peer \
		--model gpt-5.6-sol \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_plan_prompt "$task_name")"
}

# Session management

# Resolves a bare or role-prefixed hcom name and prints its name, tag, and role.
#
# @param  {string}  raw_name
#     The active or stopped agent name, optionally prefixed by its role.
_hcom_resolve_agent() {
	local raw_name="$1"
	local name="${raw_name##*-}"
	local tag role
	tag="$(_hcom_resolve_agent_tag "$name")"
	role="${tag##*-}"
	print -r -- "$name"
	print -r -- "$tag"
	print -r -- "$role"
}

# @desc  Start a fresh reviewer and announce it to the project orchestrator
# @cat   hcom
# Starts the normal reviewer role in the current directory without restoring the stopped Claude session.
#
# @param  {string}  name
#     The stopped reviewer name or role-prefixed shorthand.
# @param  {string}  initial_prompt
#     Optional task for the fresh reviewer after it announces itself.
hcom-restart-reviewer() {
	local raw_name="$1"
	shift

	if [[ -z "$raw_name" ]] || [[ $# -gt 1 ]]; then
		printf 'hcom-restart-reviewer: usage: hcom-restart-reviewer <name> [initial-prompt]\n' >&2
		return 1
	fi

	local -a resolved_agent
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"
	local tag="${resolved_agent[2]:-}"
	local role="${resolved_agent[3]:-}"

	if [[ -z "$tag" ]]; then
		printf 'hcom-restart-reviewer: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	if [[ "$role" != "reviewer" ]]; then
		printf 'hcom-restart-reviewer: %s is a %s, not a reviewer\n' "$name" "$role" >&2
		return 1
	fi

	local orchestrator_tag="${tag%-reviewer}-orchestrator"
	local -a prompt_lines
	prompt_lines=(
		"Before any other work, use the Bash tool to run this command, replacing YOUR_HCOM_NAME with your assigned hcom name:"
		"hcom send @${orchestrator_tag}- --name YOUR_HCOM_NAME -- \"Fresh replacement reviewer ready. Original reviewer: ${raw_name}.\""
	)

	if [[ -n "${1:-}" ]]; then
		prompt_lines+=("" "After announcing yourself, do this task:" "$1")
	else
		prompt_lines+=("" "Then wait for the orchestrator's task.")
	fi

	local launch_prompt
	launch_prompt="$(print -rl -- "${prompt_lines[@]}")"

	printf 'Starting a fresh reviewer for %s; it will announce itself to @%s.\n' "$name" "$orchestrator_tag"
	hcom-reviewer "$PWD" "$launch_prompt"
}

# @desc  Resume a stopped hcom agent by name (hcom r already replays its stored model/tag/role prompt)
# @cat   hcom
hcom-resume() {
	local raw_name="$1"
	shift

	if [[ -z "$raw_name" ]]; then
		printf 'hcom-resume: usage: hcom-resume <name> [tool-args...]\n' >&2
		return 1
	fi

	local -a resolved_agent
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"
	local tag="${resolved_agent[2]:-}"
	local role="${resolved_agent[3]:-}"

	if [[ -z "$tag" ]]; then
		printf 'hcom-resume: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	printf 'Resuming %s (role: %s, tag: %s)\n' "$name" "$role" "$tag"
	command hcom r "$name" "$@"
}
