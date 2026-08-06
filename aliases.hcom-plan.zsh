# hcom plan-review launchers.

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

	print -r -- "Use project-review-task in independent review mode to review task ${quoted_task_name}. Resolve exactly one task using the skill's exact-resolution order. Route one bounded repository-research packet to your existing same-model HCOM Scout before investigating; this is required HCOM team routing, not sub-agent spawning. Do not edit the task or contact the opposite planning reviewer. Retain the complete review packet, report the resolved path, content hash, verdict, every finding and its evidence, and \"Safe to reset: no\", then wait."
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
