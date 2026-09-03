# hcom insights-review launchers.

# Insights-review launchers

# @desc  Start the complete hcom insights review of a given report file in four Ghostty panes
# @cat   hcom
# Usage: hcom:insights <report-path>
#
# Creates this layout in the current Ghostty tab:
#
#   reviewer-claude  | reviewer-codex
#   scout-claude     | scout-codex
#
# Each reviewer routes its research through the scout in its own column
# (`<repo>-scout-claude` / `<repo>-scout-codex`). The two reviewers share a
# launch-specific tag so a consolidator can match the exact pair.
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
hcom:insights() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom:insights: usage: hcom:insights <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'hcom:insights: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local quoted_report_path="${(q)report_path}"  # Shell-quoted report path for the typed launch command.
	local insights_review_pair_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"  # ID shared by the paired insights-review tags.

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env
	account_env="$(_hcom_account_environment)"

	local reviewer_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom:insights:codex ${quoted_report_path}"  # Command for the Codex reviewer pane.
	local scout_claude_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom:scout:claude"  # Command for the Claude scout pane.
	local scout_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom:scout:codex"  # Command for the Codex scout pane.

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-insights-review.applescript" \
		"$reviewer_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command" \
		"$insights_review_pair_id"

	local osascript_exit_code=$?  # Exit status from the Ghostty pane layout script.

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom:insights:claude "$report_path" "$insights_review_pair_id"
}

# Builds the shared insights-review-peer independent-review initial prompt.
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
_hcom_insights_review_prompt() {
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md"  # Insights-review prompt template used by both peers.

	_hcom_workflow_prompt hcom:insights "$prompt_file" __REPORT_PATH__ "$1"
}

# @desc  Start a Claude insights-review peer review of a given report file
# @cat   hcom
# Usage: hcom:insights:claude <report-path> [insights-review-pair-id]
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
# @param  {string}  insights_review_pair_id
#     Optional. The ID shared with the paired Codex insights reviewer; when
#     omitted, a fresh ID is generated.
function hcom:insights:claude() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom:insights:claude: usage: hcom:insights:claude <report-path> [insights-review-pair-id]\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'hcom:insights:claude: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local insights_review_peer_tag="$(_hcom_workflow_peer_tag insights-review-peer "${2:-}")"  # Tag shared with the paired insights-review peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_insights_review_prompt "$report_path")"; then
		printf 'hcom:insights:claude: cannot launch without a readable insights-review prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md" >&2
		return 1
	fi

	_hcom_launch_role \
		--tool claude \
		--tag "$insights_review_peer_tag" \
		--model opus \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}

# @desc  Start a Codex insights-review peer review of a given report file
# @cat   hcom
# Usage: hcom:insights:codex <report-path> [insights-review-pair-id]
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
# @param  {string}  insights_review_pair_id
#     Optional. The ID shared with the paired Claude insights reviewer; when
#     omitted, a fresh ID is generated.
function hcom:insights:codex() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom:insights:codex: usage: hcom:insights:codex <report-path> [insights-review-pair-id]\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'hcom:insights:codex: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local insights_review_peer_tag="$(_hcom_workflow_peer_tag insights-review-peer "${2:-}")"  # Tag shared with the paired insights-review peer.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_insights_review_prompt "$report_path")"; then
		printf 'hcom:insights:codex: cannot launch without a readable insights-review prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md" >&2
		return 1
	fi

	_hcom_launch_role \
		--tool codex \
		--tag "$insights_review_peer_tag" \
		--model gpt-5.6-sol \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}
