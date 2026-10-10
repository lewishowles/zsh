#!/usr/bin/env zsh
# Checks task addresses, duplicate and unknown-task refusal, named-task
# eligibility and prompts, relaunch replacement, task-team isolation, and stop
# targeting.

setopt errexit nounset pipefail

repo_root="${0:A:h:h}"  # Repository containing the alias files under test.
fixture_dir="$(mktemp -d)"  # Isolated command stubs and agent-list data.
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/project" "$fixture_dir/worktree"

# Fails with a focused assertion message.
#
# @param  {string}  message
#     Contract that failed.
fail() {
	print -u2 -- "FAIL: $1"
	exit 1
}

# Supplies task records and active-task IDs without consulting the real project.
cat > "$fixture_dir/bin/progress" <<'STUB'
#!/usr/bin/env zsh
if [[ "$1" == task && "$2" == list && "$3" == --status && "$4" == in-progress && "$5" == --all && "$6" == --json ]]; then
	print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_A_B"},{"id":"tsk_a_B"}]}}'
	exit 0
fi
[[ "$1" == task && "$2" == get && "$4" == --json ]] || exit 1
task_status=ready
case "$3" in
	tsk_A_B) task_slug=continue-parallel-task-teams ;;
	tsk_a_B) task_slug=another-task; task_status=in-progress ;;
	tsk_A-B) task_slug=third-task ;;
	tsk_bad_slug) task_slug='Bad_Task' ;;
	tsk_blocked) task_slug=blocked-task; task_status=blocked ;;
	tsk_needs_decision) task_slug=decision-task; task_status=needs-decision ;;
	tsk_done) task_slug=finished-task; task_status=done ;;
	*) print -r -- '{"ok":false}'; exit 1 ;;
esac
print -r -- "{\"ok\":true,\"data\":{\"id\":\"$3\",\"slug\":\"$task_slug\",\"status\":\"$task_status\",\"project\":{\"slug\":\"${HCOM_FIXTURE_PROJECT_SLUG:-zsh-config}\"}}}"
STUB

# Supplies only the fixture's live HCOM agent records.
cat > "$fixture_dir/bin/hcom" <<'STUB'
#!/usr/bin/env zsh
[[ "$1" == list && "$2" == --json ]] || exit 1
cat "$HCOM_FIXTURE_AGENTS"
STUB
chmod +x "$fixture_dir/bin/progress" "$fixture_dir/bin/hcom"
export PATH="$fixture_dir/bin:$PATH"
export HCOM_FIXTURE_AGENTS="$fixture_dir/agents.json"
export ZSH_CONFIG_ROOT="$repo_root"
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

source "$repo_root/aliases.hcom-core.zsh"
source "$repo_root/aliases.hcom-team.zsh"

_hcom_parse_team_args hcom:team continue --task tsk_A_B --yes || fail 'continue --task parses'
[[ "${reply[1]}" == continue && "${reply[7]}" == tsk_A_B ]] || fail 'continue keeps the requested task'
_hcom_parse_team_args hcom:team:codex continue --task tsk_A_B --yes || fail 'Codex variant parses'
_hcom_parse_team_args hcom:team:claude continue --task tsk_A_B --yes || fail 'Claude variant parses'
_hcom_parse_team_args hcom:team resume --task tsk_A_B || fail 'resume --task still parses'
if _hcom_parse_team_args hcom:team continue --task tsk_A_B --team other 2>/dev/null; then
	fail '--task and --team must clash'
fi
_hcom_parse_team_args hcom:team continue --yes || fail 'plain continue parses'
[[ -z "${reply[2]}" && -z "${reply[7]}" ]] || fail 'plain continue retains root scope'

_hcom_read_task_team "$fixture_dir/project" tsk_A_B || fail 'task address derives'
project_tag="${reply[1]}"  # Stable project slug for comparisons.
team_label="${reply[2]}"  # Readable task slug for stop targeting.
[[ "$project_tag" == zsh-config && "$team_label" == continue-parallel-task-teams ]] || fail 'task address is not the Progress slugs'
[[ "$project_tag$team_label" != *[^a-z0-9-]* ]] || fail 'task address has unsafe characters'
_hcom_read_task_team "$fixture_dir/worktree" tsk_A_B || fail 'worktree address derives'
[[ "${reply[1]}" == "$project_tag" && "${reply[2]}" == "$team_label" ]] || fail 'worktree changes the address'
_hcom_read_task_team "$fixture_dir/project" tsk_a_B || fail 'case-distinct address derives'
[[ "${reply[2]}" != "$team_label" ]] || fail 'case-distinct tasks collide'
_hcom_read_task_team "$fixture_dir/project" tsk_A-B || fail 'separator-distinct address derives'
[[ "${reply[2]}" != "$team_label" ]] || fail 'separator-distinct tasks collide'
error_file="$fixture_dir/error"  # Captured refusal text for exact preflight checks.
if _hcom_read_task_team "$fixture_dir/project" tsk_unknown 2>"$error_file"; then
	fail 'unknown task ID resolved'
fi
[[ "$(<"$error_file")" == "hcom: could not read task tsk_unknown in $fixture_dir/project." ]] || fail 'unknown task read error was misleading'
if _hcom_read_task_team "$fixture_dir/project" tsk_bad_slug 2>/dev/null; then
	fail 'invalid task slug was rewritten or accepted'
fi
if HCOM_FIXTURE_PROJECT_SLUG='Bad_Project' _hcom_read_task_team "$fixture_dir/project" tsk_A_B 2>/dev/null; then
	fail 'invalid project slug was rewritten or accepted'
fi

team_tags="$(HCOM_TEAM_PROJECT_TAG="$project_tag" _hcom_team_tags "$fixture_dir/project" "$team_label")"  # Role tags for the selected task.
[[ "$team_tags" == "$project_tag-$team_label-orchestrator|"* ]] || fail 'role tags do not share task address'
root_tags="$(_hcom_team_tags "$fixture_dir/project" '')"  # Existing unlabelled root role tags.
[[ "$root_tags" != "$team_tags" ]] || fail 'task team collides with root team'

print -r -- "[{\"tag\":\"${team_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if _hcom_refuse_live_team "$team_tags" 2>"$error_file"; then
	fail 'live role tag did not block launch'
fi
[[ "$(<"$error_file")" == "hcom: a live team already holds ${team_tags%%|*}." ]] || fail 'duplicate refusal text'
if _hcom_launch_team hcom:team:codex unused unused unused unused continue --task tsk_A_B --yes 2>"$error_file"; then
	fail 'duplicate task team launched'
fi
[[ "$(<"$error_file")" == "hcom: a live team already holds ${team_tags%%|*}." ]] || fail 'launcher duplicate refusal text'
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
if _hcom_launch_team hcom:team:codex unused unused unused unused continue --task tsk_unknown --yes 2>"$error_file"; then
	fail 'unknown task launched'
fi
[[ "$(<"$error_file")" == "hcom: could not read task tsk_unknown in $PWD." ]] || fail 'launcher unknown task refusal text'
if _hcom_launch_team hcom:team:codex unused unused unused unused continue --task tsk_A_B --yes 2>"$error_file"; then
	fail 'named continue reached launch'
fi
[[ "$(<"$error_file")" == 'hcom:team:codex: continuing a named task is not available yet: tsk_A_B' ]] || fail 'named continue refusal text'
expected_task_status=''  # Progress status expected in each eligibility refusal.
for task_id in tsk_blocked tsk_needs_decision tsk_done; do
	case "$task_id" in
		tsk_blocked) expected_task_status=blocked ;;
		tsk_needs_decision) expected_task_status=needs-decision ;;
		tsk_done) expected_task_status=done ;;
	esac
	if _hcom_launch_team hcom:team:codex unused unused unused unused continue --task "$task_id" --yes 2>"$error_file"; then
		fail "$task_id launched"
	fi
	[[ "$(<"$error_file")" == "hcom:team:codex: task $task_id has status $expected_task_status; only ready or in-progress tasks can continue." ]] || fail "$task_id eligibility refusal text"
done

plain_prompt="$(_hcom_team_continuation_prompt continue 0)"  # Prompt used by ordinary continue.
[[ "$plain_prompt" == 'Use the `project-continue` skill to retrieve the current progress records and continue with the next ready work.' ]] || fail 'plain continue prompt changed'
plain_ready_prompt="$(_hcom_team_continuation_prompt continue 1)"  # Prompt used by a ready default task.
[[ "$plain_ready_prompt" == *'Start the selected task. If it has no chunks, plan them with the `project-plan-task` skill.'* ]] || fail 'plain ready prompt changed'
# Prompt for a ready task chosen by ID.
named_prompt="$(_hcom_team_continuation_prompt continue 1 '' tsk_A_B "$fixture_dir/project")" || fail 'named ready prompt builds'
[[ "$named_prompt" == *'Continue task tsk_A_B. This selected task takes precedence over bare `progress next`.'* ]] || fail 'named prompt does not select the task'
[[ "$named_prompt" == *'Other in-progress task IDs: tsk_a_B.'* ]] || fail 'named prompt omits another active task'
[[ "$named_prompt" == *'progress task start tsk_A_B --secondary'* && "$named_prompt" == *'clean-tree check'* ]] || fail 'named ready prompt omits safe secondary start'
[[ "$named_prompt" != *'Other in-progress task IDs: tsk_A_B'* ]] || fail 'named prompt lists its own task as another'
# Prompt for an in-progress task chosen by ID.
named_started_prompt="$(_hcom_team_continuation_prompt continue 0 '' tsk_a_B "$fixture_dir/project")" || fail 'named in-progress prompt builds'
[[ "$named_started_prompt" == *'Other in-progress task IDs: tsk_A_B.'* && "$named_started_prompt" != *'progress task start'* ]] || fail 'named in-progress prompt restarts the task'
_hcom_parse_team_stop_args --task tsk_A_B --dir "$fixture_dir/worktree" || fail 'stop --task parses'
_hcom_resolve_team_stop_scope "${reply[3]}" "${reply[1]}" "${reply[2]}" "${reply[4]}" || fail 'stop --task resolves'
[[ "${reply[1]}" == "$team_tags" ]] || fail 'stop targets different tags'

# Stubs the final launch boundary; no fixture case can open a terminal.
#
# @param  {string}  ...
#     Pane launch arguments, including prior IDs.
_hcom_team_create_panes() {
	replaced_terminal_ids="$6"
	pane_calls=$((pane_calls + 1))
	local resolved_tags  # Tags derived using the launch's project scope.
	resolved_tags="$(_hcom_team_tags "${4:-$PWD}" "$5")"
	reply=("$resolved_tags" "new|panes")
}

# Records the tags that an ordinary relaunch would stop.
#
# @param  {string}  team_tags
#     Prior ordinary team tags.
_hcom_stop_team_tags() {
	stopped_team_tags="$1"
}

# Keeps launch verification inside the fixture shell.
#
# @param  {string}  ...
#     Foreground orchestrator arguments.
_hcom_run_team_orchestrator() {
	return 0
}

# Supplies enough account data to reach the pane boundary.
#
# @param  {string}  provider
#     Provider requested by the launcher.
_hcom_quota_allocate() {
	print -r -- '1 2 0'
}

# Avoids reading a real handoff when checking the task-team replacement path.
#
# @param  {string}  working_directory
#     Checkout selected for the team.
# @param  {string}  task_id
#     Named task selected for resume.
_hcom_select_resume_task() {
	reply=("$2")
}

pane_calls=0  # Number of pane boundaries reached by test launches.
replaced_terminal_ids=""  # Prior pane IDs passed to the pane boundary.
stopped_team_tags=""  # Prior tags passed to the stop boundary.
HCOM_ACTIVE_TEAM_TAGS='old-root-orchestrator|old-root-reviewer'  # Existing ordinary team tags.
HCOM_TEAM_TERMINAL_IDS='old|panes'  # Existing ordinary team panes.
HCOM_ACTIVE_TEAM_TASK_ID=''  # Existing team is not task-scoped.
_hcom_launch_team hcom:team:codex unused unused unused unused --team blue || fail 'manual team relaunch'
[[ "$stopped_team_tags" == 'old-root-orchestrator|old-root-reviewer' && "$replaced_terminal_ids" == 'old|panes' ]] || fail 'manual team did not replace prior root'
manual_team_tags="$(_hcom_team_tags "$PWD" blue)"  # Exact tags stored for the ordinary manual team.
stopped_team_tags=''
_hcom_launch_team hcom:team:codex unused unused unused unused || fail 'root relaunch'
[[ "$stopped_team_tags" == "$manual_team_tags" && "$replaced_terminal_ids" == 'new|panes' ]] || fail 'root did not replace prior manual team'

stopped_team_tags=''
HCOM_ACTIVE_TEAM_TASK_ID=tsk_A_B
HCOM_ACTIVE_TEAM_TAGS="$team_tags"
HCOM_TEAM_TERMINAL_IDS='task|panes'
_hcom_launch_team hcom:team:codex unused unused unused unused || fail 'root after task team'
[[ -z "$stopped_team_tags" && -z "$replaced_terminal_ids" ]] || fail 'root replaced prior task team'

stopped_team_tags=''
_hcom_launch_team hcom:team:codex unused unused unused unused resume --task tsk_A_B || fail 'resume task team'
[[ -z "$stopped_team_tags" && -z "$replaced_terminal_ids" && "$HCOM_ACTIVE_TEAM_TASK_ID" == tsk_A_B ]] || fail 'task team replaced prior ordinary team'

_hcom_launch_team hcom:team:codex unused unused unused unused resume --task tsk_blocked || fail 'resume blocked task team'
[[ "$HCOM_ACTIVE_TEAM_TASK_ID" == tsk_blocked ]] || fail 'blocked task team did not retain its task ID'

print -r -- 'PASS: task address, duplicate and unknown-task refusal, named-task eligibility and prompts, relaunch replacement, task-team isolation, and stop targeting'
