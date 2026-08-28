# Provides hcom plan-review launchers and their prompt-loading helpers.

# @desc  Start the complete hcom plan review of a given task name or path in four Ghostty panes
# @cat   hcom
# Usage: hcom-plan <task-name>
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
# The two planning peers share a launch-specific tag so a consolidator can
# match the exact pair.
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
hcom-plan() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-plan: usage: hcom-plan <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to both planning peers.
	local quoted_task_name="${(q)task_name}"  # Shell-quoted task name for the typed launch command.
	local planning_pair_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"  # ID shared by the planning-peer tags.

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env  # Optional account override to include in each fresh Ghostty shell.
	account_env="$(_hcom_account_environment)"

	local plan_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 hcom-plan-codex $quoted_task_name"  # Command for the Codex planning pane.
	local scout_claude_command="${account_env}HCOM_PLANNING_WORKFLOW=1 hcom-scout-claude"  # Command for the Claude scout pane.
	local scout_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 hcom-scout-codex"  # Command for the Codex scout pane.

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-plan.applescript" \
		"$plan_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command" \
		"$planning_pair_id"

	local osascript_exit_code=$?  # Exit status from the Ghostty pane layout script.

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_PLANNING_WORKFLOW=1 hcom-plan-claude "$task_name" "$planning_pair_id"
}

# Builds the shared planning-peer independent-review initial prompt.
#
# @param  {string}  task_name
#     The task name or path to resolve for review.
_hcom_plan_prompt() {
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-plan.md"  # Planning prompt template used by both peers.

	_hcom_workflow_prompt hcom-plan "$prompt_file" __TASK_NAME__ "$1"
}

# @desc  Start a Claude planning-peer review of a given task name or path
# @cat   hcom
# Usage: hcom-plan-claude <task-name> [planning-pair-id]
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
# @param  {string}  planning_pair_id
#     Optional. The ID shared with the paired Codex planning peer; when
#     omitted, a fresh ID is generated.
function hcom-plan-claude() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom-plan-claude: usage: hcom-plan-claude <task-name> [planning-pair-id]\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to the planning peer.
	local planning_peer_tag="$(_hcom_workflow_peer_tag planning-peer "${2:-}")"  # Tag shared with the paired planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'hcom-plan-claude: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	_hcom_launch_role \
		--tool claude \
		--tag "$planning_peer_tag" \
		--model opus \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}

# @desc  Start a Codex planning-peer review of a given task name or path
# @cat   hcom
# Usage: hcom-plan-codex <task-name> [planning-pair-id]
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
# @param  {string}  planning_pair_id
#     Optional. The ID shared with the paired Claude planning peer; when
#     omitted, a fresh ID is generated.
function hcom-plan-codex() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom-plan-codex: usage: hcom-plan-codex <task-name> [planning-pair-id]\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to the planning peer.
	local planning_peer_tag="$(_hcom_workflow_peer_tag planning-peer "${2:-}")"  # Tag shared with the paired planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'hcom-plan-codex: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	_hcom_launch_role \
		--tool codex \
		--tag "$planning_peer_tag" \
		--model gpt-5.6-sol \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}
