# hcom insights-review launchers.

# Insights-review launchers

# @desc  Start the complete hcom insights review of a given report file in five Rex panes
# @cat   hcom
# @needs agent-quota
# Usage: insights <report-path>
#
# Splits the calling Rex pane into this layout:
#
#   reviewer-claude  | reviewer-codex  | consolidator
#   scout-claude     | scout-codex     | consolidator
#
# Each reviewer routes its research through the scout in its own column
# (`<repo>-insights-claude-scout` / `<repo>-insights-codex-scout`).
# Both panes in a column share a team label (insights-claude or insights-codex),
# so each reviewer's team-send reaches only its own scout.
#
# @param  {string}  report_path
#     The rendered insights report file to review.
insights() {
	if [[ $# -ne 1 ]]; then
		printf 'insights: usage: insights <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'insights: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	if [[ -z "${REX_SESSION:-}" || -z "${REX_BLOCK:-}" ]]; then
		_hcom_command_error insights 'open Rex to start an insights review.'
		return 1
	fi

	local quoted_report_path="${(q)report_path}"  # Shell-quoted report path for the typed launch command.

	# New panes open in the launch folder, so a relative report path still
	# finds the report. Each command carries any active account override into
	# the new shell.
	local account_env
	account_env="$(_hcom_account_environment)"

	local reviewer_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 insights:codex ${quoted_report_path}"  # Command for the Codex reviewer pane.
	local scout_claude_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 HCOM_TEAM_LABEL=insights-claude scout"  # Command for the Claude scout pane.
	local scout_codex_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 HCOM_TEAM_LABEL=insights-codex scout"  # Command for the Codex scout pane.
	local consolidator_command="${account_env}HCOM_INSIGHTS_REVIEW_WORKFLOW=1 insights:consolidate ${quoted_report_path}"  # Command for the consolidator pane.

	_hcom_workflow_launch_rex_layout insights "$PWD" \
		0 right 33 insights-consolidator "$consolidator_command" \
		0 right 50 insights-codex "$reviewer_codex_command" \
		0 below 40 insights-scout-claude "$scout_claude_command" \
		2 below 40 insights-scout-codex "$scout_codex_command" || return 1

	HCOM_INSIGHTS_REVIEW_WORKFLOW=1 insights:claude "$report_path"
}

# Builds the shared insights-review-peer independent-review initial prompt.
#
# @param  {string}  report_path
#     The rendered insights report file to review.
_hcom_insights_review_prompt() {
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md"  # Insights-review prompt template used by both peers.

	_hcom_workflow_prompt insights "$prompt_file" __REPORT_PATH__ "$1"
}

# @desc  Start a Claude insights-review peer review of a given report file
# @cat   hcom
# @needs agent-quota
# Usage: insights:claude <report-path>
#
# @param  {string}  report_path
#     The rendered insights report file to review.
function insights:claude() {
	if [[ $# -ne 1 ]]; then
		printf 'insights:claude: usage: insights:claude <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'insights:claude: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_insights_review_prompt "$report_path")"; then
		printf 'insights:claude: cannot launch without a readable insights-review prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL=insights-claude _hcom_launch_role \
		--command insights:claude \
		--tool claude \
		--tag orchestrator \
		--model opus \
		--role-file team.md \
		--role-file orchestrator.md \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}

# @desc  Start a Codex insights-review peer review of a given report file
# @cat   hcom
# @needs agent-quota
# Usage: insights:codex <report-path>
#
# @param  {string}  report_path
#     The rendered insights report file to review.
function insights:codex() {
	if [[ $# -ne 1 ]]; then
		printf 'insights:codex: usage: insights:codex <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'insights:codex: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_insights_review_prompt "$report_path")"; then
		printf 'insights:codex: cannot launch without a readable insights-review prompt. Check: %s\n' "$ZSH_CONFIG_ROOT/prompts/hcom-insights-review.md" >&2
		return 1
	fi

	HCOM_TEAM_LABEL=insights-codex _hcom_launch_role \
		--command insights:codex \
		--tool codex \
		--tag orchestrator \
		--model gpt-6-astra \
		--role-file team.md \
		--role-file orchestrator.md \
		--role-file insights-review-peer.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}

# @desc  Start a Claude agent that combines both insights reviews of a given report file
# @cat   hcom
# Usage: insights:consolidate <report-path>
#
# @param  {string}  report_path
#     The rendered insights report file that both reviewers reviewed.
function insights:consolidate() {
	if [[ $# -ne 1 ]]; then
		printf 'insights:consolidate: usage: insights:consolidate <report-path>\n' >&2
		return 1
	fi

	local report_path="$1"  # Report file path passed by the caller.

	if [[ ! -f "$report_path" || ! -r "$report_path" ]]; then
		printf 'insights:consolidate: report file is missing or unreadable: %s\n' "$report_path" >&2
		return 1
	fi

	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-insights-consolidate.md"  # Consolidator prompt template.
	local initial_prompt  # Prompt text that must load successfully before launch.

	if ! initial_prompt="$(_hcom_workflow_prompt insights:consolidate "$prompt_file" __REPORT_PATH__ "$report_path")"; then
		printf 'insights:consolidate: cannot launch without a readable insights-consolidate prompt. Check: %s\n' "$prompt_file" >&2
		return 1
	fi

	# Both reviewers reach the consolidator with `team-send reviewer --team insights`,
	# so it runs under the insights team's reviewer tag.
	HCOM_TEAM_LABEL=insights _hcom_launch_role \
		--command insights:consolidate \
		--tool claude \
		--tag reviewer \
		--model opus \
		--role-file team.md \
		--role-file insights-consolidator.md \
		--thinking high \
		--working-dir "$PWD" \
		--initial-prompt "$initial_prompt"
}
