# Provides hcom plan-review launchers and their prompt-loading helpers.

# @desc  Start the complete hcom plan review of a given task name or path in four Ghostty panes
# @cat   hcom
# Usage: plan [--team <label>] <task-name>
#
# Creates this layout in the current Ghostty tab:
#
#   plan-claude  | plan-codex
#   scout-claude | scout-codex
#
# Each planning peer routes its research through the scout in its own
# column (`<repo>-plan-claude[-<label>]-scout` / `<repo>-plan-codex[-<label>]-scout`); once both peers
# report `Ready as written` or `Changes requested`, pick whichever one
# found more to consolidate with `project-review-task`.
# Both panes in a column share a team label (plan-claude or plan-codex, with
# `-<label>` added when --team is given), so each planning peer's team-send
# reaches only its own scout. A live planning team with the same tags is
# refused before any pane opens; a different --team label starts another.
#
# @param  {string}  --team <label>
#     Optional leading team label that keeps this planning review apart from others in the repository.
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
plan() {
	local usage='plan: usage: plan [--team <label>] <task-name>'  # Public usage for invalid arguments.
	_hcom_parse_labelled_args plan "$usage" "$@" || return 1
	local -a launch_args=("${reply[@]}")  # Label followed by the task name.
	if (( ${#launch_args} != 2 )); then
		printf '%s\n' "$usage" >&2
		return 1
	fi

	local label="${launch_args[1]}"  # Optional user-supplied team label.
	local task_name="${launch_args[2]}"  # Task name or path passed to both planning peers.
	local claude_team_label="plan-claude${label:+-${label}}"  # Team label shared by the Claude planner and its Scout.
	local codex_team_label="plan-codex${label:+-${label}}"  # Team label shared by the Codex planner and its Scout.
	local repository_tag  # Repository portion of every planning tag.
	repository_tag="$(_hcom_scoped_tag plan "$PWD")" || return 1

	# Check all four tags before opening any pane, so a duplicate leaves nothing behind.
	local collision_hint=" Rerun with --team <label> to start another planning review."  # Advice added to the refusal when a tag is already live.
	if [[ -n "$label" ]]; then
		collision_hint=" Choose a different --team label to start another planning review."
	fi
	local planning_tags="${repository_tag}-${claude_team_label}-orchestrator|${repository_tag}-${claude_team_label}-scout|${repository_tag}-${codex_team_label}-orchestrator|${repository_tag}-${codex_team_label}-scout"  # Every tag this launch would use.
	_hcom_refuse_live_tags plan "$planning_tags" '' "$collision_hint" || return 1

	local -a team_args=()  # The --team option passed on to both planning peers, empty without a label.
	if [[ -n "$label" ]]; then
		team_args=(--team "$label")
	fi
	local quoted_task_name="${(q)task_name}"  # Shell-quoted task name for the typed launch command.

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env  # Optional account override to include in each fresh Ghostty shell.
	account_env="$(_hcom_account_environment)"

	local plan_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 plan:codex ${label:+--team ${label} }$quoted_task_name"  # Command for the Codex planning pane.
	local scout_claude_command="${account_env}HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=$claude_team_label scout"  # Command for the Claude scout pane.
	local scout_codex_command="${account_env}HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=$codex_team_label scout"  # Command for the Codex scout pane.

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-plan.applescript" \
		"$plan_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command"

	local osascript_exit_code=$?  # Exit status from the Ghostty pane layout script.

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_PLANNING_WORKFLOW=1 plan:claude "${team_args[@]}" "$task_name"
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
# Usage: plan:claude [--team <label>] <task-name>
#
# @param  {string}  --team <label>
#     Optional leading team label that keeps this planning review apart from others in the repository.
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
function plan:claude() {
	local usage='plan:claude: usage: plan:claude [--team <label>] <task-name>'  # Public usage for invalid arguments.
	_hcom_parse_labelled_args plan:claude "$usage" "$@" || return 1
	local -a launch_args=("${reply[@]}")  # Label followed by the task name.
	if (( ${#launch_args} != 2 )); then
		printf '%s\n' "$usage" >&2
		return 1
	fi

	local label="${launch_args[1]}"  # Optional user-supplied team label.
	local task_name="${launch_args[2]}"  # Task name or path passed to the planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'plan:claude: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL="plan-claude${label:+-${label}}" _hcom_launch_role \
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
# Usage: plan:codex [--team <label>] <task-name>
#
# @param  {string}  --team <label>
#     Optional leading team label that keeps this planning review apart from others in the repository.
# @param  {string}  task_name
#     The task name or path to resolve for independent review.
function plan:codex() {
	local usage='plan:codex: usage: plan:codex [--team <label>] <task-name>'  # Public usage for invalid arguments.
	_hcom_parse_labelled_args plan:codex "$usage" "$@" || return 1
	local -a launch_args=("${reply[@]}")  # Label followed by the task name.
	if (( ${#launch_args} != 2 )); then
		printf '%s\n' "$usage" >&2
		return 1
	fi

	local label="${launch_args[1]}"  # Optional user-supplied team label.
	local task_name="${launch_args[2]}"  # Task name or path passed to the planning peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_plan_prompt "$task_name")"; then
		printf 'plan:codex: cannot launch without a readable planning prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-plan.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL="plan-codex${label:+-${label}}" _hcom_launch_role \
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
