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

	local task_name="$1"
	local quoted_task_name="${(q)task_name}"
	local planning_pair_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"

	local plan_codex_command="HCOM_PLANNING_WORKFLOW=1 hcom-plan-codex $quoted_task_name"
	local scout_claude_command="HCOM_PLANNING_WORKFLOW=1 hcom-scout-claude"
	local scout_codex_command="HCOM_PLANNING_WORKFLOW=1 hcom-scout-codex"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-plan.applescript" \
		"$plan_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command" \
		"$planning_pair_id"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_PLANNING_WORKFLOW=1 hcom-plan-claude "$task_name" "$planning_pair_id"
}

# Builds the shared planning-peer tag for one task review launch.
#
# @param  {string}  planning_pair_id
#     Optional. The ID shared by the Claude and Codex planning peers; when
#     omitted, a fresh ID is generated.
_hcom_plan_peer_tag() {
	local planning_pair_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}}"

	planning_pair_id="${planning_pair_id//[^[:alnum:]_.-]/-}"
	print -r -- "planning-peer-${planning_pair_id}"
}

# Builds the shared planning-peer independent-review initial prompt.
#
# @param  {string}  task_name
#     The task name or path to resolve for review.
_hcom_plan_prompt() {
	local quoted_task_name="${(q)1}"
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-plan.md"

	if [[ ! -f "$prompt_file" ]]; then
		printf 'hcom-plan: prompt file not found: %s\n' "$prompt_file" >&2
		return 1
	fi

	local prompt_template="$(<"$prompt_file")"
	print -r -- "${prompt_template//__TASK_NAME__/$quoted_task_name}"
}

# @desc  Start a Claude planning-peer task review
# @cat   hcom
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

	local task_name="$1"
	local planning_peer_tag="$(_hcom_plan_peer_tag "${2:-}")"

	_hcom_launch_role \
		--tool claude \
		--tag "$planning_peer_tag" \
		--model opus \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_plan_prompt "$task_name")"
}

# @desc  Start a Codex planning-peer task review
# @cat   hcom
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

	local task_name="$1"
	local planning_peer_tag="$(_hcom_plan_peer_tag "${2:-}")"

	_hcom_launch_role \
		--tool codex \
		--tag "$planning_peer_tag" \
		--model gpt-5.6-sol \
		--role-file planning-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_plan_prompt "$task_name")"
}
