# Provides hcom plan-review launchers and their prompt-loading helpers.

# @desc  Start the complete hcom plan review of a given task name or path in four Ghostty panes
# @cat   hcom
# Usage: plan <task-name>
#
# Creates this layout in the current Ghostty tab:
#
#   plan-claude  | plan-codex
#   scout-claude | scout-codex
#
# Each planning peer routes its research through the scout in its own
# column (`<repo>-plan-claude-scout` / `<repo>-plan-codex-scout`); once both peers
# report `Ready as written` or `Changes requested`, pick whichever one
# found more to consolidate with `project-review-task`.
# Both panes in a column share a team label (plan-claude or plan-codex), so
# each planning peer's team-send reaches only its own scout.
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
plan() {
	if [[ $# -ne 1 ]]; then
		printf 'plan: usage: plan <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to both planning peers.
	local quoted_task_name="${(q)task_name}"  # Shell-quoted task name for the typed launch command.

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env  # Optional account override to include in each fresh Ghostty shell.
	account_env="$(_hcom_account_environment)"

	local plan_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 plan:codex $quoted_task_name"  # Command for the Codex planning pane.
	local scout_claude_command="${account_env}HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=plan-claude scout"  # Command for the Claude scout pane.
	local scout_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=plan-codex scout"  # Command for the Codex scout pane.

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-plan.applescript" \
		"$plan_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command"

	local osascript_exit_code=$?  # Exit status from the Ghostty pane layout script.

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_PLANNING_WORKFLOW=1 plan:claude "$task_name"
}

# Builds the shared planning-peer independent-review initial prompt.
#
# @param  {string}  task_name
#     The task name or path to resolve for review.
_hcom_plan_prompt() {
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-plan.md"  # Planning prompt template used by both peers.

	_hcom_workflow_prompt plan "$prompt_file" __TASK_NAME__ "$1"
}

# @desc  Start a Claude planning-peer review of a given task name or path
# @cat   hcom
# Usage: plan:claude <task-name>
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
function plan:claude() {
	if [[ $# -ne 1 ]]; then
		printf 'plan:claude: usage: plan:claude <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to the planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'plan:claude: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL=plan-claude _hcom_launch_role \
		--command plan:claude \
		--tool claude \
		--tag orchestrator \
		--model opus \
		--role-file orchestrator.md \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}

# @desc  Start a Codex planning-peer review of a given task name or path
# @cat   hcom
# Usage: plan:codex <task-name>
#
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
function plan:codex() {
	if [[ $# -ne 1 ]]; then
		printf 'plan:codex: usage: plan:codex <task-name>\n' >&2
		return 1
	fi

	local task_name="$1"  # Task name or path passed to the planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'plan:codex: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL=plan-codex _hcom_launch_role \
		--command plan:codex \
		--tool codex \
		--tag orchestrator \
		--model gpt-6-astra \
		--role-file orchestrator.md \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}
