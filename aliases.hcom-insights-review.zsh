# hcom insights-review launchers.

# Insights-review launchers

# @desc  Start the complete hcom insights review of a given report file in four Ghostty panes
# @cat   hcom
# Usage: hcom-insights-review <report-path>
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
hcom-insights-review() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-insights-review: usage: hcom-insights-review <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'hcom-insights-review: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local quoted_report_path="${(q)report_path}"
	local insights_review_pair_id="$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}"

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env
	account_env="$(_hcom_account_environment)"

	local reviewer_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom-insights-review-codex ${quoted_report_path}"
	local scout_claude_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom-scout-claude"
	local scout_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom-scout-codex"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-insights-review.applescript" \
		"$reviewer_codex_command" \
		"$scout_claude_command" \
		"$scout_codex_command" \
		"$insights_review_pair_id"

	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	HCOM_INSIGHTS_REVIEW_WORKFLOW=1 hcom-insights-review-claude "$report_path" "$insights_review_pair_id"
}

# Builds the shared insights-review-peer tag for one report review launch.
#
# @param  {string}  insights_review_pair_id
#     Optional. The ID shared by the Claude and Codex insights reviewers; when
#     omitted, a fresh ID is generated.
_hcom_insights_review_peer_tag() {
	local insights_review_pair_id="${1:-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}}"

	insights_review_pair_id="${insights_review_pair_id//[^[:alnum:]_.-]/-}"
	print -r -- "insights-review-peer-${insights_review_pair_id}"
}

# Builds the shared insights-review-peer independent-review initial prompt.
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
_hcom_insights_review_prompt() {
	local quoted_report_path="${(q)1}"
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md"

	if [[ ! -f "$prompt_file" ]]; then
		printf 'hcom-insights-review: prompt file not found: %s\n' "$prompt_file" >&2
		return 1
	fi

	local prompt_template="$(<"$prompt_file")"
	print -r -- "${prompt_template//__REPORT_PATH__/$quoted_report_path}"
}

# @desc  Start a Claude insights-review peer review of a given report file
# @cat   hcom
# Usage: hcom-insights-review-claude <report-path> [insights-review-pair-id]
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
# @param  {string}  insights_review_pair_id
#     Optional. The ID shared with the paired Codex insights reviewer; when
#     omitted, a fresh ID is generated.
function hcom-insights-review-claude() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom-insights-review-claude: usage: hcom-insights-review-claude <report-path> [insights-review-pair-id]\n' >&2
		return 1
	fi

	local report_path="$1"
	local insights_review_peer_tag="$(_hcom_insights_review_peer_tag "${2:-}")"

	_hcom_launch_role \
		--tool claude \
		--tag "$insights_review_peer_tag" \
		--model opus \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_insights_review_prompt "$report_path")"
}

# @desc  Start a Codex insights-review peer review of a given report file
# @cat   hcom
# Usage: hcom-insights-review-codex <report-path> [insights-review-pair-id]
#
# @param  {string}  report_path
#     The rendered Codex insights report file to review.
# @param  {string}  insights_review_pair_id
#     Optional. The ID shared with the paired Claude insights reviewer; when
#     omitted, a fresh ID is generated.
function hcom-insights-review-codex() {
	if [[ $# -lt 1 || $# -gt 2 ]]; then
		printf 'hcom-insights-review-codex: usage: hcom-insights-review-codex <report-path> [insights-review-pair-id]\n' >&2
		return 1
	fi

	local report_path="$1"
	local insights_review_peer_tag="$(_hcom_insights_review_peer_tag "${2:-}")"

	_hcom_launch_role \
		--tool codex \
		--tag "$insights_review_peer_tag" \
		--model gpt-5.6-sol \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$(_hcom_insights_review_prompt "$report_path")"
}
