#!/usr/bin/env zsh
# Checks task addresses, checkout selection, refusal before pane creation,
# relaunch replacement, task-team isolation, and stop targeting.

setopt errexit nounset pipefail

# Keep inherited team settings from affecting this fixture.
unset HCOM_TEAM_LABEL HCOM_TEAM_PROJECT_TAG

repo_root="${0:A:h:h}"  # Repository containing the alias files under test.
fixture_dir="$(mktemp -d)"  # Isolated command stubs and agent-list data.
trap 'rm -rf "$fixture_dir"' EXIT
mkdir -p "$fixture_dir/bin" "$fixture_dir/Agents" "$fixture_dir/project" "$fixture_dir/worktree-state" "$fixture_dir/tsk_A__B" "$fixture_dir/tsk_a_B" "$fixture_dir/tsk_A_-B" "$fixture_dir/tsk_quick"

# Fails with a focused assertion message.
#
# @param  {string}  message
#     Contract that failed.
fail() {
	print -u2 -- "FAIL: $1"
	exit 1
}

# Fails when a launch command sets or suppresses a terminal title.
#
# @param  {string}  command
#     The command text to check.
# @param  {string}  message
#     The assertion message to show on failure.
assert_no_role_title() {
	[[ "$1" != *'terminal_title_set'* && "$1" != *'CLAUDE_CODE_DISABLE_TERMINAL_TITLE'* && "$1" != *'HCOM_CODEX_ARGS'* && "$1" != *'tui.terminal_title'* ]] || fail "$2"
}

# Skips every real wait in the suite, such as the retries while a busy pane is checked.
#
# @param  {number}  seconds
#     The delay the code under test asked for; ignored.
sleep() { :; }

# Supplies task records and active-task IDs without consulting the real project.
cat > "$fixture_dir/bin/progress" <<'STUB'
#!/usr/bin/env zsh
if [[ "$1" == worktree && "$2" == cleanup ]]; then
	print -r -- "$*" >> "$HCOM_FIXTURE_CLEANUP_CALLS"
	[[ "${HCOM_FIXTURE_CLEANUP_FAIL:-0}" == 1 ]] && exit 1
	print -r -- 'Worktree cleaned'
	exit 0
fi
if [[ "$1" == task && "$2" == list && "$3" == --all && "$4" == --json ]]; then
	if [[ "${HCOM_FIXTURE_ALL_TASKS:-0}" == 1 ]]; then
		print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_a_B","title":"Other task","status":"in-progress","position":1},{"id":"tsk_A-B","title":"Earlier ready task","status":"ready","position":2},{"id":"tsk_A_B","title":"First task","status":"in-progress","position":3},{"id":"tsk_ready_two","title":"Second ready task","status":"ready","position":4},{"id":"tsk_done","title":"Finished task","status":"done","position":5}]}}'
		exit 0
	fi
	print -r -- "task list --all" >> "$HCOM_FIXTURE_QUICK_CALLS"
	case "${HCOM_FIXTURE_QUICK_STATE:-new}" in
		unfinished) print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_quick","slug":"quick-blue","status":"in-progress"}]}}' ;;
		ready) print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_quick","slug":"quick-blue","status":"ready"}]}}' ;;
		finished) print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_old_quick","slug":"quick-blue","status":"done"}]}}' ;;
		list-error) print -r -- '{"ok":false,"error":{"message":"task list unavailable"}}'; exit 1 ;;
		*) print -r -- '{"ok":true,"data":{"items":[]}}' ;;
	esac
	exit 0
fi
if [[ "$1" == task && "$2" == add ]]; then
	print -r -- "task add $*" >> "$HCOM_FIXTURE_QUICK_CALLS"
	if [[ "${HCOM_FIXTURE_QUICK_ADD_ERROR:-0}" == 1 ]]; then
		print -r -- '{"ok":false,"error":{"message":"task slug already exists"}}'
		exit 1
	fi
	print -r -- '{"ok":true,"data":{"id":"tsk_quick"}}'
	exit 0
fi
if [[ "$1" == task && "$2" == complete && "$4" == --json ]]; then
	print -r -- "$3" >> "$HCOM_FIXTURE_COMPLETE_CALLS"
	if [[ "${HCOM_FIXTURE_COMPLETE_ERROR:-0}" == 1 ]]; then
		print -r -- '{"ok":false,"error":{"message":"task completion failed"}}'
		exit 1
	elif [[ "${HCOM_FIXTURE_COMPLETE_REMOVED:-0}" == 1 ]]; then
		if [[ "${HCOM_FIXTURE_UNMERGED_COMMITS:-0}" != 0 ]]; then
			print -r -- "{\"ok\":true,\"data\":{\"status\":\"done\",\"worktree_cleanup\":{\"status\":\"removed\",\"reason\":\"folder already gone\",\"unmerged_commits\":${HCOM_FIXTURE_UNMERGED_COMMITS},\"base_branch\":\"${HCOM_FIXTURE_BASE_BRANCH-main}\",\"command\":\"git merge quick-blue\"}}}"
		elif [[ "${HCOM_FIXTURE_COUNT_ERROR:-0}" == 1 ]]; then
			print -r -- "{\"ok\":true,\"data\":{\"status\":\"done\",\"worktree_cleanup\":{\"status\":\"removed\",\"reason\":\"folder already gone\",\"count_error\":\"could not count commits\",\"base_branch\":\"${HCOM_FIXTURE_BASE_BRANCH-main}\",\"command\":\"git merge quick-blue\"}}}"
		else
			print -r -- '{"ok":true,"data":{"status":"done","worktree_cleanup":{"status":"removed","reason":"folder already gone"}}}'
		fi
	elif [[ "${HCOM_FIXTURE_COMPLETE_PENDING:-0}" == 1 ]]; then
		print -r -- '{"ok":true,"data":{"status":"done","worktree_cleanup":{"status":"pending","reason":"rebase conflict","command":"progress worktree cleanup tsk_quick"}}}'
	else
		print -r -- '{"ok":true,"data":{"status":"done","worktree_cleanup":{"status":"none"}}}'
	fi
	exit 0
fi
if [[ "$1" == task && "$2" == list && "$3" == --status && "$4" == in-progress && "$5" == --all && "$6" == --json ]]; then
	if [[ "${HCOM_FIXTURE_NO_ACTIVE_TASKS:-0}" == 1 ]]; then
		print -r -- '{"ok":true,"data":{"items":[]}}'
		exit 0
	fi
	if [[ -n "${HCOM_FIXTURE_ONLY_TASK_ID:-}" ]]; then
		print -r -- "{\"ok\":true,\"data\":{\"items\":[{\"id\":\"$HCOM_FIXTURE_ONLY_TASK_ID\"}]}}"
		exit 0
	fi
	print -r -- '{"ok":true,"data":{"items":[{"id":"tsk_A_B","title":"First task","status":"in-progress","position":3},{"id":"tsk_a_B","title":"Other task","status":"in-progress","position":1}]}}'
	exit 0
fi
if [[ "$1" == context && "$2" == get && "$3" == --task && "$5" == --json ]]; then
	print -r -- "$4" >> "$HCOM_FIXTURE_CONTEXT_CALLS"
	[[ "${HCOM_FIXTURE_TASK_CONTEXT_FAIL:-0}" == 1 ]] && exit 1
	if [[ -n "${HCOM_FIXTURE_HANDOFF_FILE:-}" ]]; then
		cat "$HCOM_FIXTURE_HANDOFF_FILE"
		exit 0
	fi
	if [[ "${HCOM_FIXTURE_HAS_HANDOFF:-0}" == 1 ]]; then
		if [[ "${HCOM_FIXTURE_LONG_NEXT_STEP:-0}" == 1 ]]; then
			print -r -- '{"ok":true,"data":{"current_goal":"Continue the fixture task","next_step":"Read the saved handoff carefully and resume the selected task with enough detail to wrap this single step under its label while keeping every displayed line within the terminal width."}}'
		else
			print -r -- '{"ok":true,"data":{"current_goal":"Continue the fixture task","next_step":"1. Read the saved handoff\n2. Resume the task"}}'
		fi
	else
		print -r -- '{"ok":true,"data":null}'
	fi
	exit 0
fi
if [[ "$1" == context && "$2" == get && "$3" == --json ]]; then
	[[ "${HCOM_FIXTURE_PROJECT_CONTEXT_FAIL:-0}" == 1 ]] && exit 1
	print -r -- '{"ok":true,"data":{"standing_context":"Project handoff line one\nProject handoff line two"}}'
	exit 0
fi
if [[ "$1" == next && "$2" == --json ]]; then
	if [[ "${HCOM_FIXTURE_NO_NEXT_TASK:-0}" == 1 ]]; then
		print -r -- '{"ok":true,"data":{"project":{"name":"Fixture"},"task":null,"chunk":null}}'
		exit 0
	fi
	print -r -- "{\"ok\":true,\"data\":{\"project\":{\"name\":\"Fixture\"},\"task\":{\"id\":\"${HCOM_FIXTURE_NEXT_TASK:-tsk_A_B}\",\"title\":\"Fixture task\",\"status\":\"${HCOM_FIXTURE_NEXT_STATUS:-ready}\",\"chunks\":[]},\"chunk\":null}}"
	exit 0
fi
if [[ "$1" == worktree && ( "$2" == get || "$2" == ensure ) && "$4" == --json ]]; then
	print -r -- "$2 $3" >> "$HCOM_FIXTURE_WORKTREE_CALLS"
	worktree_key="${3//A/A_}"  # Keeps task IDs that differ only in letter case apart on macOS, where folder names ignore case.
	worktree_state="$HCOM_FIXTURE_WORKTREE_STATE_DIR/$worktree_key"  # Recorded checkout for this task only.
	worktree_path="$HCOM_FIXTURE_WORKTREE_ROOT/$worktree_key"  # Managed checkout path for this task only.
	if [[ "$2" == get && ( "$3" == "${HCOM_FIXTURE_FINISHED_TASK_ID:-}" || ( "$3" == tsk_quick && "${HCOM_FIXTURE_NO_QUICK_CHECKOUT:-0}" == 1 ) ) ]]; then
		print -r -- '{"ok":false,"error":{"code":"not-found","message":"no managed checkout"}}'
		exit 1
	fi
	worktree_error="${HCOM_FIXTURE_WORKTREE_ERROR:-}"  # Failure code for get and ensure; HCOM_FIXTURE_ENSURE_ERROR replaces it for ensure.
	if [[ "$2" == ensure && -n "${HCOM_FIXTURE_ENSURE_ERROR:-}" ]]; then
		worktree_error="$HCOM_FIXTURE_ENSURE_ERROR"
	fi
	if [[ -n "$worktree_error" ]]; then
		print -r -- "{\"ok\":false,\"error\":{\"code\":\"$worktree_error\",\"message\":\"worktree $worktree_error\"}}"
		exit 1
	fi
	if [[ "$2" == get && ! -f "$worktree_state" ]]; then
		print -r -- '{"ok":false,"error":{"code":"not-found","message":"no managed checkout"}}'
		exit 1
	fi
	if [[ "$2" == ensure ]]; then
		print -r -- "$worktree_path" > "$worktree_state"
	fi
	print -r -- "{\"ok\":true,\"data\":{\"task_id\":\"$3\",\"path\":\"$(<"$worktree_state")\"}}"
	exit 0
fi
[[ "$1" == task && "$2" == get && "$4" == --json ]] || exit 1
task_status=ready
task_title='Selected task'  # Title the preview shows for the named task.
task_chunks='[]'  # Chunk records returned with the task, as JSON.
task_overview='Choose the next fixture task.'  # Purpose shown above the chunk list.
case "$3" in
	tsk_A_B) task_slug=continue-parallel-task-teams ;;
	tsk_a_B) task_slug=another-task; task_status=in-progress; task_title='Other task'; task_overview='Finish the fixture work in order.'; task_chunks='[{"id":"chk_pending","title":"Pending chunk","status":"pending","position":3},{"id":"chk_skipped","title":"Skipped chunk","status":"skipped","position":4},{"id":"chk_active","title":"Active chunk","status":"active","position":2},{"id":"chk_done","title":"Finished chunk","status":"done","position":1}]' ;;
	tsk_A-B) task_slug=third-task ;;
	tsk_ready_two) task_slug=second-ready-task ;;
	tsk_team_b) task_slug=other-task ;;
	tsk_legacy) task_slug=older-task ;;
	tsk_bad_slug) task_slug='Bad_Task' ;;
	tsk_blocked) task_slug=blocked-task; task_status=blocked ;;
	tsk_needs_decision) task_slug=decision-task; task_status=needs-decision ;;
	tsk_done) task_slug=finished-task; task_status=done ;;
	tsk_quick) task_slug=quick-blue; task_title='Quick: blue'; [[ "${HCOM_FIXTURE_QUICK_STATE:-new}" == unfinished ]] && task_status=in-progress ;;
	*) print -r -- '{"ok":false}'; exit 1 ;;
esac
[[ "$3" == "${HCOM_FIXTURE_FINISHED_TASK_ID:-}" ]] && task_status=done
print -r -- "{\"ok\":true,\"data\":{\"id\":\"$3\",\"title\":\"$task_title\",\"slug\":\"$task_slug\",\"status\":\"$task_status\",\"overview\":\"$task_overview\",\"updated_at\":\"2026-10-19T10:00:00.123456+00:00\",\"chunks\":$task_chunks,\"project\":{\"name\":\"Fixture\",\"slug\":\"${HCOM_FIXTURE_PROJECT_SLUG:-zsh-config}\"}}}"
STUB

# Resolves the main checkout, reports controlled changes, and logs Git status calls.
cat > "$fixture_dir/bin/git" <<'STUB'
#!/usr/bin/env zsh
if [[ "$1" == -C && "$3" == rev-parse && "$4" == --path-format=absolute && "$5" == --git-common-dir ]]; then
	[[ "${HCOM_FIXTURE_GIT_LOOKUP_FAIL:-0}" == 1 ]] && exit 1
	print -r -- "${HCOM_FIXTURE_GIT_COMMON_DIR:-$HCOM_FIXTURE_MAIN_CHECKOUT/.git}"
	exit 0
fi
if [[ "$1" == -C && "$3" == rev-parse && "$4" == --show-toplevel ]]; then
	if [[ "$2" == "$HCOM_FIXTURE_MAIN_CHECKOUT" || "$2" == "$HCOM_FIXTURE_MAIN_CHECKOUT/"* ]]; then
		print -r -- "$HCOM_FIXTURE_MAIN_CHECKOUT"
	else
		print -r -- "$2"
	fi
	exit 0
fi
[[ "$1" == -C && "$3" == status && ( "$4" == --short || "$4" == --porcelain ) ]] || exit 1
print -r -- "$2 $4" >> "$HCOM_FIXTURE_GIT_CALLS"
[[ "${HCOM_FIXTURE_GIT_STATUS_FAIL:-0}" == 1 ]] && exit 1
if [[ "${HCOM_FIXTURE_GIT_DIRTY:-0}" == 1 ]]; then
	print -r -- ' M fixture-file'
fi
STUB

# Supplies only the fixture's live HCOM agent records.
cat > "$fixture_dir/bin/hcom" <<'STUB'
#!/usr/bin/env zsh
[[ "$1" == list && "$2" == --json ]] || exit 1
cat "$HCOM_FIXTURE_AGENTS"
STUB

# Records Rex calls and answers tab creation and pane splits with fixture IDs.
cat > "$fixture_dir/bin/rex" <<'STUB'
#!/usr/bin/env zsh
print -r -- "$*" >> "$HCOM_FIXTURE_REX_CALLS"
case "$1" in
	ls)
		if [[ -n "${HCOM_FIXTURE_REX_SESSIONS:-}" ]]; then
			print -r -- "$HCOM_FIXTURE_REX_SESSIONS"
		else
			print -r -- '{"sessions":[]}'
		fi
		;;
	window)
		if [[ "$2" == new ]]; then
			print -r -- '{"window_id":"window:new","block_ids":["block:new"]}'
		elif [[ "$2" == ls ]]; then
			if [[ -n "${HCOM_FIXTURE_REX_WINDOWS:-}" ]]; then
				print -r -- "$HCOM_FIXTURE_REX_WINDOWS"
			else
				print -r -- '{"windows":[]}'
			fi
		fi
		;;
	block)
		case "$2" in
			ls)
				if [[ -n "${HCOM_FIXTURE_REX_BLOCKS:-}" ]]; then
					print -r -- "$HCOM_FIXTURE_REX_BLOCKS"
				else
					print -r -- '{"blocks":[{"block_id":"block:orchestrator","label":"orchestrator"},{"block_id":"block:implementer","label":"implementer"},{"block_id":"block:reviewer","label":"reviewer"},{"block_id":"block:scout","label":"scout"}]}'
				fi
				;;
			call)
				if [[ -n "${HCOM_FIXTURE_REX_PROCESS_ERROR_BLOCK:-}" && "$*" == *"$HCOM_FIXTURE_REX_PROCESS_ERROR_BLOCK"* ]]; then
					exit 1
				fi
				if [[ -n "${HCOM_FIXTURE_REX_BUSY_BLOCK:-}" && "$*" == *"$HCOM_FIXTURE_REX_BUSY_BLOCK"* ]]; then
					print -r -- '{"foreground":{"name":"claude"}}'
				else
					print -r -- "{\"foreground\":{\"name\":\"${HCOM_FIXTURE_REX_PROCESS:-zsh}\"}}"
				fi
				;;
			close)
				if [[ -n "${HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK:-}" && "$*" == *"$HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK"* ]]; then
					exit 1
				fi
				;;
		esac
		;;
	split)
		[[ "${HCOM_FIXTURE_REX_SPLIT_FAIL:-0}" == 1 ]] && exit 1
		[[ -n "${HCOM_FIXTURE_REX_SPLIT_FAIL_LABEL:-}" && "$*" == *"--label $HCOM_FIXTURE_REX_SPLIT_FAIL_LABEL"* ]] && exit 1
		case "$*" in
			*'--label implementer'*) print -r -- '{"block_ids":["block:implementer"]}' ;;
			*'--label reviewer'*) print -r -- '{"block_ids":["block:reviewer"]}' ;;
			*'--label scout'*) print -r -- '{"block_ids":["block:scout"]}' ;;
			*'--label plan-codex'*) print -r -- '{"block_ids":["block:plan-codex"]}' ;;
			*'--label plan-scout-claude'*) print -r -- '{"block_ids":["block:plan-scout-claude"]}' ;;
			*'--label plan-scout-codex'*) print -r -- '{"block_ids":["block:plan-scout-codex"]}' ;;
		esac
		;;
	api)
		if [[ "${HCOM_FIXTURE_REX_RESIZE_FAIL:-0}" == 1 ]]; then
			exit 1
		fi
		;;
	send)
		if [[ -n "${HCOM_FIXTURE_REX_SEND_ERROR_BLOCK:-}" && "$*" == *"$HCOM_FIXTURE_REX_SEND_ERROR_BLOCK"* ]]; then
			exit 1
		fi
		;;
esac
STUB
chmod +x "$fixture_dir/bin/progress" "$fixture_dir/bin/hcom" "$fixture_dir/bin/git" "$fixture_dir/bin/rex"
export PATH="$fixture_dir/bin:$PATH"
export HCOM_FIXTURE_AGENTS="$fixture_dir/agents.json"
export HCOM_FIXTURE_WORKTREE_CALLS="$fixture_dir/worktree-calls"
export HCOM_FIXTURE_QUICK_CALLS="$fixture_dir/quick-calls"
export HCOM_FIXTURE_COMPLETE_CALLS="$fixture_dir/complete-calls"
export HCOM_FIXTURE_GIT_CALLS="$fixture_dir/git-calls"
export HCOM_FIXTURE_MAIN_CHECKOUT="$fixture_dir/Agents"
export HCOM_FIXTURE_CONTEXT_CALLS="$fixture_dir/context-calls"
export HCOM_FIXTURE_WORKTREE_STATE_DIR="$fixture_dir/worktree-state"
export HCOM_FIXTURE_WORKTREE_ROOT="$fixture_dir"
export HCOM_FIXTURE_REX_CALLS="$fixture_dir/rex-calls"
export HCOM_FIXTURE_CLEANUP_CALLS="$fixture_dir/cleanup-calls"
export XDG_STATE_HOME="$fixture_dir/state"
export HCOM_FIXTURE_GIT_DIRTY=0
export ZSH_CONFIG_ROOT="$repo_root"
export REX_SESSION=fixture-origin-session
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

source "$repo_root/aliases.hcom-core.zsh"
source "$repo_root/aliases.hcom-workflow.zsh"
source "$repo_root/aliases.hcom-team-placement.zsh"
source "$repo_root/aliases.hcom-team.zsh"
source "$repo_root/aliases.progress.zsh"
functions -c _hcom_team_create_panes _hcom_team_create_panes_real
source "$repo_root/aliases.hcom-roles.zsh"
source "$repo_root/aliases.hcom-learn.zsh"
source "$repo_root/aliases.hcom-session.zsh"

# Supplies a pane ID for the learner and planning launch fixtures.
#
# @param  {string}  command_name
#     Public command requesting the pane ID.
_hcom_focused_ghostty_terminal_id() {
	print -r -- 'fixture-origin-pane'
}

# Shows preview text without relying on the installed colour helper.
#
# @param  {string}  content
#     Text displayed by the preview.
cli_style_span() {
	print -r -- "$1"
}

# Preview text for a ready named task.
named_preview="$(_hcom_preview_team_continuation team "$fixture_dir/project" 1 tsk_A_B)" || fail 'named task preview builds'
[[ "$named_preview" == *'Task     Selected task'* && "$named_preview" == *'         ready · Fixture · updated '*'ago'* && "$named_preview" == *'Overview Choose the next fixture task.'* && "$named_preview" == *'Chunks   Not planned yet.'* && "$named_preview" == *'Task: tsk_A_B'* ]] || fail 'named preview omits task status or purpose'
[[ "$named_preview" != *'Next     '* ]] || fail 'named preview shows a next step without a handoff'
[[ "$named_preview" != *'Fixture task'* ]] || fail 'named preview shows the default task'
# Preview text for a started named task with an active chunk.
started_preview="$(_hcom_preview_team_continuation team "$fixture_dir/project" 1 tsk_a_B)" || fail 'started task preview builds'
[[ "$started_preview" == *'Task     Other task'* && "$started_preview" == *'         in-progress · Fixture · updated '* && "$started_preview" == *'Overview Finish the fixture work in order.'* ]] || fail 'started preview omits task status or purpose'
[[ "$started_preview" == *'Chunks   done · Finished chunk'*'         current · Active chunk'*'         to-do · Pending chunk'*'         skipped · Skipped chunk'* && "$started_preview" == *'Task: tsk_a_B  Chunk: chk_active'* && "$started_preview" != *$'\nChunk '* ]] || fail 'started preview omitted, mislabelled, or misordered chunks'
export HCOM_FIXTURE_HAS_HANDOFF=1
handoff_preview="$(COLUMNS=45 _hcom_preview_team_continuation team "$fixture_dir/project" 1 tsk_a_B)" || fail 'handoff preview builds'
[[ "$handoff_preview" == *'Next     1. Read the saved handoff'*$'\n''         2. Resume the task'* ]] || fail 'next steps do not hang beneath their label'
[[ "$handoff_preview" != *'Details  '* ]] || fail 'preview still shows the old details block'
[[ "$handoff_preview" != *'Continue the fixture task'* ]] || fail 'handoff goal repeats the task title'
printf '%s\n' "$handoff_preview" | awk -F 'tsk_a_B' 'NF > 0 { count += NF - 1 } END { exit count != 1 }' || fail 'handoff preview repeats the task ID'
printf '%s\n' "$handoff_preview" | awk -F 'Active chunk' 'NF > 0 { count += NF - 1 } END { exit count != 1 }' || fail 'handoff preview repeats the chunk title'
export HCOM_FIXTURE_LONG_NEXT_STEP=1
long_next_preview="$(COLUMNS=80 _hcom_preview_team_continuation team "$fixture_dir/project" 1 tsk_a_B)" || fail 'long next step preview builds'
next_block="${long_next_preview#*Next     }"  # The Next row's text, without its label.
next_block="${next_block%%$'\n'         Task:*}"
next_lines=("${(@f)next_block}")  # Next row lines after the first label has been removed.
[[ "${#next_lines}" -gt 1 ]] || fail 'long next step did not wrap'
for continuation_line in "${next_lines[@]:1}"; do
	[[ "$continuation_line" == '         '* && "${#continuation_line}" -le 80 ]] || fail 'long next step lost its hanging indent or exceeded 80 columns'
done
for continuation_line in "${(@f)long_next_preview}"; do
	[[ "${#continuation_line}" -le 80 ]] || fail 'continuation preview exceeded 80 columns'
done
unset HCOM_FIXTURE_LONG_NEXT_STEP
unset HCOM_FIXTURE_HAS_HANDOFF

export HCOM_FIXTURE_HAS_HANDOFF=1
: > "$HCOM_FIXTURE_CONTEXT_CALLS"
ready_handoff_preview="$(_hcom_preview_team_continuation team "$fixture_dir/project" 1 tsk_A_B)" || fail 'ready task with a leftover handoff previews'
[[ "$ready_handoff_preview" != *'Next     '* && ! -s "$HCOM_FIXTURE_CONTEXT_CALLS" ]] || fail 'ready task preview read or showed a leftover handoff'
unset HCOM_FIXTURE_HAS_HANDOFF

_hcom_parse_team_args team continue --task tsk_A_B --yes || fail 'continue --task parses'
[[ "${reply[1]}" == continue && "${reply[6]}" == tsk_A_B ]] || fail 'continue keeps the requested task'
_hcom_parse_team_args team:codex continue --task tsk_A_B --yes || fail 'Codex variant parses'
_hcom_parse_team_args team:claude continue --task tsk_A_B --yes || fail 'Claude variant parses'
_hcom_parse_team_args team continue --task tsk_A_B || fail 'continue --task parses without --yes'
if _hcom_parse_team_args team continue --task tsk_A_B --team other 2>/dev/null; then
	fail '--task and --team must clash'
fi
_hcom_parse_team_args team continue --yes || fail 'plain continue parses'
[[ -z "${reply[2]}" && -z "${reply[6]}" ]] || fail 'plain continue retains root scope'

# Checks that a launcher rejects the call with status 1 and exactly this
# uncoloured error after a blank line. Stderr is redirected to a file.
#
# @param  {string}  expected
#     The error text that should follow the leading blank line.
# @param  {string}  ...
#     The launcher call and arguments that should be rejected.
assert_command_error() {
	local expected="$1"  # The uncoloured launcher error to check.
	local exit_code  # Status returned by the rejected call.
	shift

	if "$@" 2>"$error_file"; then
		fail "launcher accepted an invalid call: $expected"
	else
		exit_code=$?
	fi

	[[ "$exit_code" == 1 ]] || fail "launcher error returned status $exit_code instead of 1: $expected"
	[[ "$(<"$error_file")" == $'\n'"$expected" ]] || fail "launcher error changed: $expected"
}

error_file="$fixture_dir/error"  # Captured error output for the exact-text checks below.
assert_command_error 'team:codex: --dir requires a directory.' _hcom_parse_team_args team:codex --dir
assert_command_error 'team: --task requires a task ID.' team --task
assert_command_error 'cont: --task requires a task ID.' cont --task
assert_command_error 'team: --message requires text.' _hcom_parse_team_args team --message --yes
assert_command_error 'team: --team requires a label.' _hcom_parse_team_args team --team
assert_command_error 'team: invalid team label: Bad_Label'$'\n''team: use lowercase letters, numbers, and internal hyphens.' _hcom_parse_team_args team --team Bad_Label
assert_command_error 'team: --task requires a task ID.' _hcom_parse_team_args team continue --task
assert_command_error 'team: unknown option: --bad' _hcom_parse_team_args team --bad
assert_command_error 'team: unknown option: --keep-agents' _hcom_parse_team_args team --keep-agents
assert_command_error 'team: usage: team [continue|handover|handoff] [--task <id>] [--dir <path>] [--message <text>] [--clipboard] [--team <label>] [--yes]' _hcom_parse_team_args team extra
assert_command_error 'team: --task and --team cannot be used together.' _hcom_parse_team_args team continue --task tsk_A_B --team other
assert_command_error 'team: --task only works with continue, handover, or handoff.' _hcom_parse_team_args team --task tsk_A_B
# Clipboard contents are supplied by this fixture, never by the user's clipboard.
pbpaste() { print -rn -- "$fixture_clipboard"; }
# The fixture clipboard holds the text that pbpaste returns in the next cases.
fixture_clipboard='   '
assert_command_error 'team: clipboard is empty.' _hcom_parse_team_args team --clipboard
fixture_clipboard=$'--quoted "text" `literal` $VALUE\nsecond line'
_hcom_parse_team_args team --clipboard || fail 'clipboard note did not parse'
[[ "${reply[4]}" == "$fixture_clipboard" ]] || fail 'clipboard note changed during parsing'
_hcom_parse_team_args team --clipboard --message 'another note' || fail 'combined message and clipboard note did not parse'
[[ "${reply[4]}" == 'another note'$'\n\n'"$fixture_clipboard" ]] || fail 'combined message and clipboard note changed during parsing'
assert_command_error 'team: --clipboard cannot be used with handoff or handover.' _hcom_parse_team_args team handoff --clipboard
unfunction pbpaste
assert_command_error "team: working directory not found: $fixture_dir/missing" _hcom_parse_team_args team --dir "$fixture_dir/missing"
assert_command_error "team:done: working directory not found: $fixture_dir/missing" _hcom_resolve_team_stop_scope team:done "$fixture_dir/missing" tsk_A_B
export HCOM_FIXTURE_NO_NEXT_TASK=1  # Makes the progress stub return no task for the continuation error check.
assert_command_error 'cont: nothing to continue in Fixture.' _hcom_preview_team_continuation cont "$fixture_dir/project" 1
unset HCOM_FIXTURE_NO_NEXT_TASK

# Returns a blank clipboard, so the empty clipboard error is checked without reading the real one.
pbpaste() { print -r -- '   '; }
assert_command_error 'cont: clipboard is empty, copy the last messages first' _hcom_team_continuation_prompt cont handover 0
unfunction pbpaste
assert_command_error 'team:codex: unknown team continuation mode: invalid' _hcom_team_continuation_prompt team:codex invalid 0

_hcom_read_task_team team "$fixture_dir/project" tsk_A_B || fail 'task address derives'
project_tag="${reply[1]}"  # Stable main checkout folder tag for comparisons.
team_label="${reply[2]}"  # Readable task slug for stop targeting.
[[ "$project_tag" == Agents && "$team_label" == continue-parallel-task-teams ]] || fail 'task address does not use the main checkout folder'
[[ "$project_tag$team_label" != *[^a-zA-Z0-9-]* ]] || fail 'task address has unsafe characters'
_hcom_read_task_team team "$fixture_dir/tsk_A__B" tsk_A_B || fail 'worktree address derives'
[[ "${reply[1]}" == "$project_tag" && "${reply[2]}" == "$team_label" ]] || fail 'worktree changes the address'
_hcom_read_task_team team "$fixture_dir/project" tsk_a_B || fail 'case-distinct address derives'
[[ "${reply[2]}" != "$team_label" ]] || fail 'case-distinct tasks collide'
_hcom_read_task_team team "$fixture_dir/project" tsk_A-B || fail 'separator-distinct address derives'
[[ "${reply[2]}" != "$team_label" ]] || fail 'separator-distinct tasks collide'
if _hcom_read_task_team team "$fixture_dir/project" tsk_unknown 2>"$error_file"; then
	fail 'unknown task ID resolved'
fi
[[ "$(<"$error_file")" == $'\n'"team: could not read task tsk_unknown in $fixture_dir/project." ]] || fail 'unknown task read error was misleading'
if _hcom_read_task_team team "$fixture_dir/project" tsk_bad_slug 2>/dev/null; then
	fail 'invalid task slug was rewritten or accepted'
fi
HCOM_FIXTURE_PROJECT_SLUG='Bad_Project' _hcom_read_task_team team "$fixture_dir/project" tsk_A_B || fail 'unused project slug blocked the task address'
[[ "${reply[1]}" == Agents ]] || fail 'project slug changed the checkout folder tag'
HCOM_TEAM_PROJECT_TAG=Other _hcom_read_task_team team "$fixture_dir/project" tsk_A_B || fail 'inherited team tag blocked the task address'
[[ "${reply[1]}" == Agents ]] || fail 'inherited team tag replaced the checkout folder tag'
export HCOM_FIXTURE_GIT_LOOKUP_FAIL=1
assert_command_error "team: could not find the main checkout for $fixture_dir/project." _hcom_read_task_team team "$fixture_dir/project" tsk_A_B
unset HCOM_FIXTURE_GIT_LOOKUP_FAIL
export HCOM_FIXTURE_GIT_COMMON_DIR="$fixture_dir/Agents/.git/modules/example"
assert_command_error "team: could not find the main checkout for $fixture_dir/project." _hcom_read_task_team team "$fixture_dir/project" tsk_A_B
unset HCOM_FIXTURE_GIT_COMMON_DIR

team_tags="$(HCOM_TEAM_PROJECT_TAG="$project_tag" _hcom_team_tags team "$fixture_dir/project" "$team_label")"  # Role tags for the selected task.
[[ "$team_tags" == "$project_tag-$team_label-orchestrator|"* ]] || fail 'role tags do not share task address'
_hcom_resolve_team_stop_scope team:done "$fixture_dir/project" tsk_A_B || fail 'task stop scope resolves'
[[ "${reply[1]}" == "$team_tags" ]] || fail 'task stop targets different tags'
root_tags="$(_hcom_team_tags team "$PWD" '')"  # Existing unlabelled root role tags.
[[ "$root_tags" != "$team_tags" ]] || fail 'task team collides with root team'

print -r -- "[{\"tag\":\"${team_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if _hcom_refuse_live_tags team "$team_tags" 2>"$error_file"; then
	fail 'live role tag did not block launch'
fi
[[ "$(<"$error_file")" == $'\n'"team: peer already holds ${team_tags%%|*}. Switch to that agent, or stop it with \"hcom kill peer\" and run team again." ]] || fail 'duplicate refusal text'

# Records whether a single role reaches the launch boundary.
#
# @param  {string}  ...
#     Role launch arguments.
_hcom_role_invoke() {
	role_invoke_calls=$((role_invoke_calls + 1))
}

mkdir -p "$fixture_dir/roles"
print -r -- 'Fixture role prompt.' > "$fixture_dir/roles/scout.md"
print -r -- 'Fixture role prompt.' > "$fixture_dir/roles/orchestrator.md"
print -r -- 'Fixture role prompt.' > "$fixture_dir/roles/learner.md"
export HCOM_ROLE_DIR="$fixture_dir/roles"
role_invoke_calls=0  # Number of single-role launch calls.
scout_tag="$(_hcom_scoped_tag scout "$PWD")-scout"  # Full role tag for the fixture checkout.
print -r -- "[{\"tag\":\"$scout_tag\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if _hcom_launch_role --command scout --tool codex --tag scout --model fixture --role-file scout.md 2>"$error_file"; then
	fail 'duplicate single role launched'
fi
[[ "$(<"$error_file")" == $'\n'"scout: peer already holds $scout_tag. Switch to that agent, or stop it with \"hcom kill peer\" and run scout again." ]] || fail 'single-role duplicate refusal text'
[[ "$role_invoke_calls" == 0 ]] || fail 'duplicate single role reached the launch boundary'
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
_hcom_launch_role --command scout --tool codex --tag scout --model fixture --role-file scout.md || fail 'single role with no live duplicate did not launch'
[[ "$role_invoke_calls" == 1 ]] || fail 'single role with no live duplicate missed the launch boundary'

assert_command_error 'scout: unknown option: --bad' scout --bad
assert_command_error 'scout: task tsk_A_B has no registered worktree.' scout --task tsk_A_B
assert_command_error "agent:resume: 'bad' is not a valid agent name" _hcom_resolve_agent bad
mkdir -p "$fixture_dir/---"
assert_command_error "learn:codex: cannot derive a tag from directory: $fixture_dir/---" zsh -c 'source "$1/aliases.hcom-core.zsh"; source "$1/aliases.hcom-learn.zsh"; cd "$2"; _hcom_learning_context learn:codex learn-codex source ""' -- "$repo_root" "$fixture_dir/---"

print -r -- "[{\"tag\":\"${team_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if _hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes 2>"$error_file"; then
	fail 'duplicate task team launched'
fi
[[ "$(<"$error_file")" == $'\n'"team:codex: peer already holds ${team_tags%%|*}. Switch to that agent, or stop it with \"hcom kill peer\" and run team:codex again." ]] || fail 'launcher duplicate refusal text'
[[ ! -e "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B" ]] || fail 'duplicate task team created a checkout'
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
if _hcom_launch_team team:codex unused unused unused unused continue --task tsk_unknown --yes 2>"$error_file"; then
	fail 'unknown task launched'
fi
[[ "$(<"$error_file")" == $'\n'"team:codex: could not read task tsk_unknown in $PWD." ]] || fail 'launcher unknown task refusal text'
expected_task_status=''  # Progress status expected in each eligibility refusal.
for task_id in tsk_needs_decision tsk_done; do
	case "$task_id" in
		tsk_needs_decision) expected_task_status=needs-decision ;;
		tsk_done) expected_task_status=done ;;
	esac
	if _hcom_launch_team team:codex unused unused unused unused continue --task "$task_id" --yes 2>"$error_file"; then
		fail "$task_id launched"
	fi
	[[ "$(<"$error_file")" == $'\n'"team:codex: task $task_id has status $expected_task_status; only ready, in-progress, or blocked tasks can continue." ]] || fail "$task_id eligibility refusal text"
done

plain_prompt="$(_hcom_team_continuation_prompt team continue 0)"  # Prompt used by ordinary continue.
[[ "$plain_prompt" == 'Continue with the next ready work, using the project handoff and Git status in this prompt.' ]] || fail 'plain continue prompt changed'
plain_ready_prompt="$(_hcom_team_continuation_prompt team continue 1)"  # Prompt used by a ready default task.
[[ "$plain_ready_prompt" == *'Start the selected task. If it has no chunks, plan them with the `project-plan-task` skill.'* ]] || fail 'plain ready prompt changed'
# Prompt for a ready task chosen by ID.
named_prompt="$(_hcom_team_continuation_prompt team continue 1 '' tsk_A_B "$fixture_dir/project")" || fail 'named ready prompt builds'
[[ "$named_prompt" == 'Continue task tsk_A_B, not the `progress next` result.

These tasks are in progress and should not be modified: tsk_a_B

Your command to start the task is:
progress task start tsk_A_B --secondary' ]] || fail 'named ready prompt changed'
# Prompt for an in-progress task chosen by ID.
named_started_prompt="$(_hcom_team_continuation_prompt team continue 0 '' tsk_a_B "$fixture_dir/project")" || fail 'named in-progress prompt builds'
[[ "$named_started_prompt" == *'should not be modified: tsk_A_B' && "$named_started_prompt" != *'progress task start'* ]] || fail 'named in-progress prompt restarts the task'
# Check the real selector before the launch fixture replaces it.
_hcom_select_in_progress_task team "$fixture_dir/project" tsk_a_B || fail 'selector refused an explicitly named task'
[[ "${reply[1]}" == tsk_a_B && "${reply[2]}" == 0 ]] || fail 'selector treated an explicitly named task as a picker choice'
export HCOM_FIXTURE_NO_ACTIVE_TASKS=1
_hcom_select_in_progress_task team "$fixture_dir/project" '' || fail 'selector refused an empty in-progress list'
[[ -z "${reply[1]}" && "${reply[2]}" == 0 ]] || fail 'selector returned a task when none is in progress'
unset HCOM_FIXTURE_NO_ACTIVE_TASKS
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_select_in_progress_task team "$fixture_dir/project" '' || fail 'selector refused a task without a handoff'
[[ "${reply[1]}" == tsk_a_B && "${reply[2]}" == 0 ]] || fail 'selector reported a picker for the sole in-progress task'
export HCOM_FIXTURE_HAS_HANDOFF=1
_hcom_select_in_progress_task team "$fixture_dir/project" '' > "$fixture_dir/selector-preview" || fail 'selector refused a task with a handoff'
[[ "${reply[1]}" == tsk_a_B && "${reply[2]}" == 0 && ! -s "$fixture_dir/selector-preview" ]] || fail 'selector printed the handoff or reported a picker'
unset HCOM_FIXTURE_ONLY_TASK_ID HCOM_FIXTURE_HAS_HANDOFF

# Runs the real selector inside a pseudo-terminal and sends each answer only
# after its prompt appears.
cat > "$fixture_dir/select-task.zsh" <<'STUB'
# Makes progress return the full task list for the picker.
export HCOM_FIXTURE_ALL_TASKS=1
source "$ZSH_CONFIG_ROOT/aliases.hcom-core.zsh"
source "$ZSH_CONFIG_ROOT/aliases.hcom-team.zsh"
# Marks styled status text so the picker fixture can inspect its tone.
#
# @param  {string}  text
#     The status label.
# @param  {string}  tone
#     The tone requested by the picker.
cli_style_span() {
	print -r -- "[$2]$1[/]"
}
if _hcom_select_in_progress_task "${HCOM_FIXTURE_SELECTOR_COMMAND:-cont}" "$HCOM_FIXTURE_PROJECT_DIR" '' "${HCOM_FIXTURE_FORCE_PICKER:-0}"; then
	print -r -- "SELECTED:${reply[1]}:${reply[2]}"
else
	print -r -- 'CANCELLED'
fi
STUB
export HCOM_FIXTURE_PROJECT_DIR="$fixture_dir/project"
export HCOM_FIXTURE_SELECTOR_SCRIPT="$fixture_dir/select-task.zsh"
cat > "$fixture_dir/select-task.expect" <<'STUB'
#!/usr/bin/expect -f
set timeout 5
spawn -noecho /bin/zsh $env(HCOM_FIXTURE_SELECTOR_SCRIPT)
switch -- [lindex $argv 0] {
	invalid-then-pick {
		expect -re {Which task\? }
		send -- "9\r"
		expect -re {Choose a number from 1 to 4}
		expect -re {Which task\? }
		send -- "1\r"
		expect -re {SELECTED:tsk_a_B:1}
	}
	cancel-numbered {
		expect -re {Which task\? }
		send -- "\r"
		expect -re {CANCELLED}
	}
	pick-fzf { expect -re {SELECTED:tsk_a_B:1} }
	pick-ready { expect -re {SELECTED:tsk_A-B:1} }
	cancel-fzf { expect -re {CANCELLED} }
}
expect {
	eof {}
	timeout { close; exit 1 }
}
STUB
# A PATH that hides any installed fzf but keeps the fixture commands and jq.
numbered_path="$fixture_dir/bin:${$(command -v jq):h}:/usr/bin:/bin:/usr/sbin:/sbin"
numbered_output="$(env PATH="$numbered_path" NO_COLOR=1 expect "$fixture_dir/select-task.expect" invalid-then-pick)" || fail 'numbered selector process failed'
[[ "$numbered_output" == *'4. ready        Second ready task'*'3. in progress  First task'*'2. ready        Earlier ready task'*'1. in progress  Other task'* && "$numbered_output" == *'Choose a number from 1 to 4'* && "$numbered_output" == *'SELECTED:tsk_a_B:1'* && "$numbered_output" != *'Finished task'* ]] || fail 'numbered selector did not order and align the tasks'
numbered_output="$(env PATH="$numbered_path" NO_COLOR=1 expect "$fixture_dir/select-task.expect" cancel-numbered)" || fail 'numbered cancellation process failed'
[[ "$numbered_output" == *$'Other task\r\n  cont tsk_a_B'* && "$numbered_output" == *$'Earlier ready task\r\n  cont tsk_A-B'* && "$numbered_output" != *$'in progress  Other task\r\n  cont tsk_a_B'* && "$numbered_output" == *'CANCELLED'* && "$numbered_output" != *'SELECTED:'* ]] || fail 'empty answer did not print plain titles and continuation commands'
numbered_output="$(env PATH="$numbered_path" HCOM_FIXTURE_SELECTOR_COMMAND=team:codex NO_COLOR=1 expect "$fixture_dir/select-task.expect" cancel-numbered)" || fail 'team selector cancellation process failed'
[[ "$numbered_output" == *$'Other task\r\n  team:codex continue --task tsk_a_B'* && "$numbered_output" == *'CANCELLED'* && "$numbered_output" != *'  cont tsk_a_B'* ]] || fail 'team selector cancellation did not print its own continuation command'

# Stands in for fzf: records the rows it was shown, then picks the second task,
# or exits as if Esc was pressed when HCOM_FIXTURE_FZF_CANCEL is 1.
cat > "$fixture_dir/bin/fzf" <<'STUB'
#!/usr/bin/env zsh
cat > "$HCOM_FIXTURE_FZF_INPUT"
print -r -- "$*" > "$HCOM_FIXTURE_FZF_ARGS"
[[ "${HCOM_FIXTURE_FZF_CANCEL:-0}" == 1 ]] && exit 130
if [[ "${HCOM_FIXTURE_FZF_READY:-0}" == 1 ]]; then
	print -r -- $'tsk_A-B\tEarlier ready task'
	exit 0
fi
print -r -- $'tsk_a_B\tOther task'
STUB
chmod +x "$fixture_dir/bin/fzf"
export HCOM_FIXTURE_FZF_INPUT="$fixture_dir/fzf-input"
export HCOM_FIXTURE_FZF_ARGS="$fixture_dir/fzf-args"
fzf_output="$(env NO_COLOR=1 expect "$fixture_dir/select-task.expect" pick-fzf)" || fail 'fzf selector process failed'
[[ "$fzf_output" == *'SELECTED:tsk_a_B:1'* && "$(<"$HCOM_FIXTURE_FZF_INPUT")" == $'tsk_a_B\tin progress  Other task\tOther task\ntsk_A-B\tready        Earlier ready task\tEarlier ready task\ntsk_A_B\tin progress  First task\tFirst task\ntsk_ready_two\tready        Second ready task\tSecond ready task' ]] || fail 'fzf selector did not order and align active and ready tasks'
[[ "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'--ansi'* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'--with-nth=2'* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'--layout=default'* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'--gap'* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'--preview '* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'_hcom_preview_team_continuation'* && "$(<"$HCOM_FIXTURE_FZF_ARGS")" == *'aliases.hcom-team.zsh'* ]] || fail 'fzf selector did not hide the ID or wire the spaced preview'
fzf_output="$(env HCOM_FIXTURE_FORCE_PICKER=1 HCOM_FIXTURE_FZF_READY=1 NO_COLOR=1 expect "$fixture_dir/select-task.expect" pick-ready)" || fail 'declined-task picker process failed'
[[ "$fzf_output" == *'SELECTED:tsk_A-B:1'* && "$(<"$HCOM_FIXTURE_FZF_INPUT")" == *$'tsk_a_B\tin progress  Other task'* && "$(<"$HCOM_FIXTURE_FZF_INPUT")" == *$'tsk_A-B\tready        Earlier ready task'* ]] || fail 'declined-task picker lost the suggested task or a ready choice'
fzf_output="$(env HCOM_FIXTURE_FZF_CANCEL=1 NO_COLOR=1 expect "$fixture_dir/select-task.expect" cancel-fzf)" || fail 'fzf cancellation process failed'
[[ "$fzf_output" == *$'Other task\r\n  cont tsk_a_B'* && "$fzf_output" == *$'Second ready task\r\n  cont tsk_ready_two'* && "$fzf_output" != *$'in progress  Other task\r\n  cont tsk_a_B'* && "$fzf_output" == *'CANCELLED'* && "$fzf_output" != *'SELECTED:'* ]] || fail 'fzf cancellation did not print plain titles and continuation commands'
fzf_output="$(env -u NO_COLOR HCOM_FIXTURE_FZF_CANCEL=1 expect "$fixture_dir/select-task.expect" cancel-fzf)" || fail 'coloured fzf cancellation process failed'
[[ "$(<"$HCOM_FIXTURE_FZF_INPUT")" == *$'tsk_a_B\t[info]in progress[/]  Other task\tOther task'* && "$(<"$HCOM_FIXTURE_FZF_INPUT")" == *$'tsk_A-B\t[muted]ready      [/]  Earlier ready task\tEarlier ready task'* && "$fzf_output" == *$'Other task\r\n  cont tsk_a_B'* && "$fzf_output" == *$'Earlier ready task\r\n  cont tsk_A-B'* && "$fzf_output" != *'[info]'* && "$fzf_output" != *'[muted]'* && "$fzf_output" == *'CANCELLED'* ]] || fail 'coloured picker did not keep status markers out of cancellation titles'

# Stdin comes from /dev/null so the refusal is tested even when the suite runs in a terminal.
if _hcom_select_in_progress_task cont "$fixture_dir/project" '' </dev/null 2>"$error_file"; then
	fail 'non-interactive selector accepted several tasks'
fi
[[ "$(<"$error_file")" == *'2 tasks are in progress; choose one with --task:'* && "$(<"$error_file")" == *'tsk_A_B  First task'* && "$(<"$error_file")" == *'tsk_a_B  Other task'* && "$(<"$error_file")" != *'No task chosen.'* ]] || fail 'non-interactive selector did not list task IDs without a cancellation message'

# Stubs the final launch boundary; no fixture case can open a terminal.
#
# @param  {string}  command_name
#     The public command whose pane creation is being tested.
# @param  {string}  ...
#     Pane launch arguments, including the prior Rex session ID.
_hcom_team_create_panes() {
	# Public command responsible for the pane launch.
	local command_name="$1"
	shift
	replaced_session_id="$6"
	launched_pane_directory="$4"
	launched_orchestrator_prompt="${14}"
	launched_task_id="${17:-}"
	pane_calls=$((pane_calls + 1))
	# Tags derived using the launch's project scope.
	local resolved_tags
	resolved_tags="$(_hcom_team_tags "$command_name" "${4:-$PWD}" "$5")"
	launched_team_tags="$resolved_tags"
	reply=("$resolved_tags" "session:new" "window:new")
}

# Records the tags that an ordinary relaunch would stop.
#
# @param  {string}  team_tags
#     Prior ordinary team tags.
_hcom_stop_team_tags() {
	stopped_team_tags="$1"
}

# Supplies enough account data to reach the pane boundary.
#
# @param  {string}  command_name
#     The public command requesting quota.
# @param  {string}  provider
#     Provider requested by the launcher.
_hcom_quota_allocate() {
	print -r -- '1 2 0'
}

# Stands in for the task selector so launches never read a real handoff.
#
# Picks the named task, or the fixture's only in-progress task, and reports a
# handoff when HCOM_FIXTURE_HAS_HANDOFF is 1. Refuses like the real selector
# when HCOM_FIXTURE_SEVERAL_TASKS is 1 and no task is named.
# HCOM_FIXTURE_PICKER_TASK_ID chooses a task; HCOM_FIXTURE_PICKER_CANCEL cancels.
# HCOM_FIXTURE_PICKER_AFTER_DECLINE makes the picker answer only after a
# declined preview. The second reply element is 1 for a picker choice, 0 otherwise.
#
# @param  {string}  command_name
#     The public command requesting the continuation.
# @param  {string}  working_directory
#     Checkout selected for the team.
# @param  {string}  task_id
#     Named task selected for continuation.
# @param  {integer}  force_picker
#     1 when the caller reopens the picker after a declined preview.
_hcom_select_in_progress_task() {
	if [[ -z "$3" && ( -n "${HCOM_FIXTURE_PICKER_TASK_ID:-}" || "${HCOM_FIXTURE_PICKER_CANCEL:-0}" == 1 ) && ( "${HCOM_FIXTURE_PICKER_AFTER_DECLINE:-0}" == 0 || "${4:-0}" == 1 ) ]]; then
		[[ "${HCOM_FIXTURE_PICKER_CANCEL:-0}" == 1 ]] && return 2
		reply=("$HCOM_FIXTURE_PICKER_TASK_ID" 1)
		return 0
	fi
	if [[ -z "$3" && "${HCOM_FIXTURE_SEVERAL_TASKS:-0}" == 1 ]]; then
		_hcom_command_error "$1" '2 tasks are in progress; choose one with --task:'
		return 1
	fi

	reply=("${3:-${HCOM_FIXTURE_ONLY_TASK_ID:-}}" 0)
}

# Number of pane boundaries reached by test launches.
pane_calls=0
# Prior Rex session ID that the launch was asked to reuse.
replaced_session_id=""
# Prior tags passed to the stop boundary.
stopped_team_tags=""
# Folder given to the role panes; empty means the original checkout.
launched_pane_directory=""
# Continuation prompt given to the orchestrator.
launched_orchestrator_prompt=""
# Tags that the pane boundary received.
launched_team_tags=""
# Task ID that the pane boundary received.
launched_task_id=""
print -r -- "[{\"tag\":\"${team_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if cont --task tsk_A_B --yes 2>"$error_file"; then
	fail 'cont launched a duplicate task team'
fi
[[ "$(<"$error_file")" == $'\n'"cont: peer already holds ${team_tags%%|*}. Switch to that agent, or stop it with \"hcom kill peer\" and run cont again." && "$pane_calls" == 0 ]] || fail 'cont refusal lost its name or reached the pane boundary'
if cont --task tsk_A_B 2>"$error_file"; then
	fail 'cont launched a duplicate task team without --yes'
fi
[[ "$(<"$error_file")" == $'\n'"cont: peer already holds ${team_tags%%|*}. Switch to that agent, or stop it with \"hcom kill peer\" and run cont again." && "$pane_calls" == 0 ]] || fail 'cont refusal without --yes reached the pane boundary'
print -r -- "[{\"tag\":\"${root_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
if _hcom_launch_team team:codex unused unused unused unused 2>"$error_file"; then
	fail 'duplicate root team launched'
fi
[[ "$(<"$error_file")" == $'\n'"team:codex: peer already holds ${root_tags%%|*}. Switch to that agent, or stop it with \"hcom kill peer\" and run team:codex again." ]] || fail 'root-team duplicate refusal text'
[[ "$pane_calls" == 0 && -z "$stopped_team_tags" ]] || fail 'duplicate root team created panes or stopped agents'
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

_hcom_launch_team team:codex unused unused unused unused || fail 'ordinary team relaunch'
[[ -z "$stopped_team_tags" && -z "$replaced_session_id" && "$launched_team_tags" == "$root_tags" && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'root launch stopped another team or stored scope in the launching shell'
# Exact tags passed to the ordinary team.
ordinary_team_tags="$(_hcom_team_tags team "$PWD" '')"
stopped_team_tags=''
_hcom_launch_team team:codex unused unused unused unused || fail 'root relaunch'
[[ -z "$stopped_team_tags" && -z "$replaced_session_id" && "$launched_team_tags" == "$ordinary_team_tags" ]] || fail 'root relaunch stopped or reused another team'

stopped_team_tags=''
_hcom_launch_team team:codex unused unused unused unused || fail 'root after task team'
[[ -z "$stopped_team_tags" && -z "$replaced_session_id" ]] || fail 'root replaced prior task team'

stopped_team_tags=''
# A ready named task creates its checkout once and gives it to every role.
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
export HCOM_FIXTURE_HAS_HANDOFF=1
: > "$HCOM_FIXTURE_CONTEXT_CALLS"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes || fail 'named task checkout creation'
[[ "$(<"$HCOM_FIXTURE_CONTEXT_CALLS")" == tsk_A_B && "$launched_orchestrator_prompt" == *$'Task handoff for tsk_A_B:\n{"ok":true,"data":{"current_goal":"Continue the fixture task","next_step":"1. Read the saved handoff\\n2. Resume the task"}}'* ]] || fail 'ready task launch did not include its saved handoff'
unset HCOM_FIXTURE_HAS_HANDOFF
[[ -z "$stopped_team_tags" && -z "$replaced_session_id" && "$launched_task_id" == tsk_A_B && "$(<"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B")" == $'session:new\nwindow:new' && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'task launch replaced another team or lost its stored tab'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_A__B" ]] || fail 'named task roles launched in different checkouts'
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == $'get tsk_A_B\nensure tsk_A_B' ]] || fail 'named task did not look up then create its checkout'
# A named task skips the preview even when stdin cannot answer a prompt.
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B </dev/null &> "$fixture_dir/named-task-output" || fail 'named task without --yes did not launch'
[[ "$(<"$fixture_dir/named-task-output")" != *'Start this task?'* ]] || fail 'named task without --yes showed a confirmation'
unset REX_SESSION
assert_command_error "team:codex: could not read task tsk_unknown in $PWD." _hcom_launch_team team:codex unused unused unused unused continue --task tsk_unknown
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: open Rex to start a team.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'Rex refusal reached pane creation'
: > "$HCOM_FIXTURE_QUICK_CALLS"
assert_command_error 'team:codex: open Rex to start a team.' _hcom_launch_team team:codex unused unused unused unused --team blue
[[ ! -s "$HCOM_FIXTURE_QUICK_CALLS" ]] || fail 'Rex refusal created or searched for a quick task'
stopped_team_tags=''
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
assert_command_error 'team:codex: open Rex to start a team.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_ready_two
[[ -z "$stopped_team_tags" && ! -s "$HCOM_FIXTURE_WORKTREE_CALLS" ]] || fail 'Rex refusal stopped the prior team or checked out a task'
export REX_SESSION=fixture-origin-session
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes || fail 'named task repeat launch'
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == 'get tsk_A_B' ]] || fail 'repeat launch did not reuse the checkout'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_A_B, not the `progress next` result.'* ]] || fail 'ready task did not use the continue prompt'

# A label creates its quick task and launches through the named-task checkout path.
: > "$HCOM_FIXTURE_QUICK_CALLS"
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team blue --message 'Investigate the prompt' || fail 'labelled quick task launch'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == *'task add '*'--slug quick-blue --title Quick: blue --overview Investigate the prompt --done-when The human says this quick work is done. --json'* ]] || fail 'quick task creation lost its details'
[[ "$launched_task_id" == tsk_quick && "$launched_team_tags" == 'Agents-quick-blue-orchestrator|Agents-quick-blue-reviewer|Agents-quick-blue-implementer|Agents-quick-blue-scout' ]] || fail 'quick task launch lost task-scoped tags'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_quick" ]] || fail 'quick task team opened outside its checkout'
[[ "$launched_orchestrator_prompt" == 'Investigate the prompt' ]] || fail 'new quick task changed the human note'
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == $'get tsk_quick\nensure tsk_quick' ]] || fail 'quick task did not create its checkout'

# Clipboard text starting with -- survives the quick-task relaunch and a continuation unchanged.
pbpaste() { print -rn -- "$fixture_clipboard"; }
fixture_clipboard=$'--quoted "text" `literal` $VALUE\nsecond line'
_hcom_launch_team team:codex unused unused unused unused --team blue --clipboard || fail 'quick task rejected a clipboard note beginning with --'
[[ "$launched_orchestrator_prompt" == "$fixture_clipboard" ]] || fail 'quick task relaunch changed the clipboard note'
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --clipboard || fail 'continuation rejected clipboard text'
[[ "$launched_orchestrator_prompt" == *"$fixture_clipboard"* ]] || fail 'continuation changed the clipboard note'
unfunction pbpaste

# A new quick task without a note has no opening prompt.
: > "$HCOM_FIXTURE_QUICK_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team green || fail 'quick task without a note launch'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == *'task add '* && -z "$launched_orchestrator_prompt" ]] || fail 'new quick task without a note received a prompt'

# An unfinished quick task with the same label is reused without adding another.
export HCOM_FIXTURE_QUICK_STATE=unfinished
: > "$HCOM_FIXTURE_QUICK_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team blue || fail 'unfinished quick task reuse'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == 'task list --all' && "$launched_task_id" == tsk_quick ]] || fail 'unfinished quick task was added again'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_quick, not the `progress next` result.'* && "$launched_orchestrator_prompt" != *'progress task start'* ]] || fail 'existing quick task skipped the normal prompt'

# A ready quick task from an earlier launch gets the normal start prompt.
export HCOM_FIXTURE_QUICK_STATE=ready
: > "$HCOM_FIXTURE_QUICK_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team blue || fail 'ready quick task reuse'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == 'task list --all' && "$launched_task_id" == tsk_quick ]] || fail 'ready quick task was added again'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_quick, not the `progress next` result.'*$'Your command to start the task is:\nprogress task start tsk_quick --secondary'* ]] || fail 'ready quick task skipped the normal start prompt'

# A finished quick task is ignored, so the launcher asks Progress for a new one.
export HCOM_FIXTURE_QUICK_STATE=finished
: > "$HCOM_FIXTURE_QUICK_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team blue || fail 'finished quick task replacement'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == *'task add '* ]] || fail 'finished quick task was reused'

# A failed task add prints the Progress error and opens no panes.
export HCOM_FIXTURE_QUICK_ADD_ERROR=1
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: task slug already exists' _hcom_launch_team team:codex unused unused unused unused --team blue
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'failed quick task add opened panes'
unset HCOM_FIXTURE_QUICK_STATE HCOM_FIXTURE_QUICK_ADD_ERROR

# A failed task list prints the Progress error and opens no panes.
export HCOM_FIXTURE_QUICK_STATE=list-error
: > "$HCOM_FIXTURE_QUICK_CALLS"
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: task list unavailable' _hcom_launch_team team:codex unused unused unused unused --team blue
[[ "$pane_calls" == "$prior_pane_calls" && "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == 'task list --all' ]] || fail 'failed quick task list added a task or opened panes'
unset HCOM_FIXTURE_QUICK_STATE

# A picker choice enters the same named-task path and skips the confirmation.
export HCOM_FIXTURE_PICKER_TASK_ID=tsk_A-B
prior_pane_calls="$pane_calls"
_hcom_launch_team team:codex unused unused unused unused continue || fail 'picker choice did not launch a ready task'
[[ "$pane_calls" == $((prior_pane_calls + 1)) && "$launched_task_id" == tsk_A-B && "$launched_orchestrator_prompt" == *'Continue task tsk_A-B, not the `progress next` result.'* ]] || fail 'picker choice missed the named ready-task launch path'
unset REX_SESSION
assert_command_error 'team:codex: open Rex to start a team.' _hcom_launch_team team:codex unused unused unused unused continue
export REX_SESSION=fixture-origin-session
unset HCOM_FIXTURE_PICKER_TASK_ID
export HCOM_FIXTURE_PICKER_CANCEL=1
prior_pane_calls="$pane_calls"
_hcom_launch_team team:codex unused unused unused unused continue || fail 'cancelled picker after several tasks returned an error'
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'cancelled picker after several tasks opened a pane'
unset HCOM_FIXTURE_PICKER_CANCEL

# Declining a preview opens the picker, then launches its ready choice without another preview.
functions -c _hcom_preview_team_continuation _hcom_saved_preview_team_continuation
# Declines the prompted preview and records any unexpected second preview.
#
# @param  {string}  command_name
#     Public command requesting the preview.
# @param  {string}  working_directory
#     Directory where progress records would be read.
# @param  {integer}  skip_confirmation
#     0 for the prompted preview, which is declined, or 1 after a picker choice.
# @param  {string}  selected_task_id
#     Task returned as the one to start.
_hcom_preview_team_continuation() {
	if [[ "$3" == 0 ]]; then
		print -r -- decline >> "$fixture_dir/preview-calls"
		return 2
	fi
	print -r -- accepted >> "$fixture_dir/preview-calls"
	reply=(1 "$4" ready 0)
}
export HCOM_FIXTURE_PICKER_TASK_ID=tsk_A-B HCOM_FIXTURE_PICKER_AFTER_DECLINE=1
: > "$fixture_dir/preview-calls"
prior_pane_calls="$pane_calls"
_hcom_launch_team team:codex unused unused unused unused continue || fail 'declined preview did not launch the chosen task'
[[ "$pane_calls" == $((prior_pane_calls + 1)) && "$(<"$fixture_dir/preview-calls")" == decline ]] || fail 'declined preview reopened confirmation or launched more than once'
unset HCOM_FIXTURE_PICKER_TASK_ID HCOM_FIXTURE_PICKER_AFTER_DECLINE
export HCOM_FIXTURE_PICKER_CANCEL=1 HCOM_FIXTURE_PICKER_AFTER_DECLINE=1
: > "$fixture_dir/preview-calls"
prior_pane_calls="$pane_calls"
_hcom_launch_team team:codex unused unused unused unused continue || fail 'cancelled picker after a declined preview returned an error'
[[ "$pane_calls" == "$prior_pane_calls" && "$(<"$fixture_dir/preview-calls")" == decline ]] || fail 'cancelled picker after a declined preview opened a pane or repeated the preview'
unset HCOM_FIXTURE_PICKER_CANCEL HCOM_FIXTURE_PICKER_AFTER_DECLINE
functions -c _hcom_saved_preview_team_continuation _hcom_preview_team_continuation
unfunction _hcom_saved_preview_team_continuation

# An in-progress task with a handoff uses its recorded checkout and resume prompt.
print -r -- "$fixture_dir/tsk_a_B" > "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B"
export HCOM_FIXTURE_HAS_HANDOFF=1
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes || fail 'named in-progress task with a handoff'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'named in-progress task ignored its recorded checkout'
[[ "$launched_orchestrator_prompt" == *'Resume the interrupted work on task tsk_a_B from the task handoff in this prompt. Do not select a new task.'* && "$launched_orchestrator_prompt" != *'progress context get --task tsk_a_B --json'* ]] || fail 'named in-progress task did not use the resume prompt'
# The public cont command launches the task it is given, under that task's team label.
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
prior_pane_calls="$pane_calls"
cont tsk_a_B --yes || fail 'public cont task ID did not launch'
[[ "$pane_calls" == $((prior_pane_calls + 1)) && "$launched_task_id" == tsk_a_B && "$launched_team_tags" == *'-another-task-orchestrator|'* ]] || fail 'public cont task ID selected the wrong task or team label'
[[ "$launched_orchestrator_prompt" == *'Resume the interrupted work on task tsk_a_B from the task handoff in this prompt. Do not select a new task.'* ]] || fail 'public cont task ID lost the resume instruction'
[[ "$launched_orchestrator_prompt" == *$'Task handoff for tsk_a_B:\n{"ok":true,"data":{"current_goal":"Continue the fixture task","next_step":"1. Read the saved handoff\\n2. Resume the task"}}'* ]] || fail 'public cont task ID lost the full task handoff'
[[ "$launched_orchestrator_prompt" == *$'Project handoff:\n{"ok":true,"data":{"standing_context":"Project handoff line one\\nProject handoff line two"}}'* ]] || fail 'public cont task ID lost the full project handoff'
[[ "$launched_orchestrator_prompt" == *"Git status for $fixture_dir/tsk_a_B:"$'\nClean checkout (no changes).'* ]] || fail 'public cont task ID missed its checkout status'
cont tsk_a_B </dev/null &> "$fixture_dir/cont-task-output" || fail 'public cont task ID without --yes did not launch'
[[ "$(<"$fixture_dir/cont-task-output")" != *'Start this task?'* ]] || fail 'public cont task ID without --yes showed a confirmation'
# A blocked task can resume only when a saved handoff exists.
print -r -- "$fixture_dir/tsk_a_B" > "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_blocked"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_blocked --yes || fail 'blocked task with a handoff did not resume'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'blocked task ignored its recorded checkout'
[[ "$launched_orchestrator_prompt" == *'Resume the interrupted work on task tsk_blocked from the task handoff in this prompt. Do not select a new task.'* ]] || fail 'blocked task did not use the resume prompt'
unset HCOM_FIXTURE_HAS_HANDOFF
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: blocked task tsk_blocked has no saved handoff to resume.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_blocked --yes
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'blocked task without a handoff reached pane creation'
export HCOM_FIXTURE_HAS_HANDOFF=1
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'plain continue with a sole in-progress task and handoff'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'plain continue ignored the recorded checkout'
[[ "$launched_orchestrator_prompt" == *'Resume the interrupted work on task tsk_a_B from the task handoff in this prompt. Do not select a new task.'* ]] || fail 'plain continue did not use the resume prompt'
unset HCOM_FIXTURE_ONLY_TASK_ID HCOM_FIXTURE_HAS_HANDOFF

# A named handoff uses the task checkout when Progress records one.
pbpaste() { print -rn -- 'Copied handoff messages'; }
handoff tsk_a_B || fail 'named handoff with a checkout did not launch'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'named handoff ignored its recorded checkout'
[[ "$launched_orchestrator_prompt" == *'The handover is for task tsk_a_B.'* ]] || fail 'named handoff did not name its task'
[[ "$launched_orchestrator_prompt" == *'Task handoff for tsk_a_B:'* && "$launched_orchestrator_prompt" == *'Project handoff:'* && "$launched_orchestrator_prompt" == *"Git status for $fixture_dir/tsk_a_B:"* ]] || fail 'named handover missed its startup facts'
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B.old"

# A started task without a recorded checkout must stay in its original checkout.
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old"
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'sole in-progress task without a handoff did not continue'
[[ -z "$launched_pane_directory" ]] || fail 'sole in-progress task without a checkout left the original checkout'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_a_B, not the `progress next` result.'* && "$launched_orchestrator_prompt" != *'progress context get --task tsk_a_B --json'* ]] || fail 'sole in-progress task without a handoff did not use the continue prompt'
unset HCOM_FIXTURE_ONLY_TASK_ID

: > "$HCOM_FIXTURE_WORKTREE_CALLS"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes || fail 'started task without a checkout did not continue'
[[ -z "$launched_pane_directory" ]] || fail 'started task left the original checkout'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_a_B, not the `progress next` result.'* && "$launched_orchestrator_prompt" != *'progress context get --task tsk_a_B --json'* ]] || fail 'started task without a handoff did not use the continue prompt'
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == $'get tsk_a_B\nget tsk_A_B' ]] || fail 'started task created or skipped a checkout lookup'

handoff tsk_a_B || fail 'named handoff without a checkout did not launch'
[[ -z "$launched_pane_directory" ]] || fail 'named handoff without a checkout left the original checkout'

prior_pane_calls="$pane_calls"  # Pane count before live-team refusal cases.
print -r -- "[{\"tag\":\"${root_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error 'team:codex: the root team is running in the original checkout; continue there, or stop it and run team:codex again.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes
assert_command_error 'handoff: the root team is running in the original checkout; continue there, or stop it and run handoff again.' handoff tsk_a_B
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'live root team reached pane creation'

print -r -- "[{\"tag\":\"${team_tags%%|*}\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error 'team:codex: task tsk_A_B is running in the original checkout; continue there, or stop it and run team:codex again.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes
assert_command_error 'handoff: task tsk_A_B is running in the original checkout; continue there, or stop it and run handoff again.' handoff tsk_a_B
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'live task team reached pane creation'
unfunction pbpaste

mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes || fail 'task in another checkout blocked continuation'
[[ -z "$launched_pane_directory" ]] || fail 'another task checkout changed the selected checkout'
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old"
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

export HCOM_FIXTURE_NEXT_STATUS=in-progress
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'in-progress default without checkout'
[[ -z "$launched_pane_directory" ]] || fail 'in-progress default without checkout left the original directory'
unset HCOM_FIXTURE_ONLY_TASK_ID
export HCOM_FIXTURE_SEVERAL_TASKS=1
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: 2 tasks are in progress; choose one with --task:' _hcom_launch_team team:codex unused unused unused unused continue --yes
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'several in-progress tasks reached pane creation'
unset HCOM_FIXTURE_SEVERAL_TASKS
HCOM_FIXTURE_NEXT_STATUS=ready
export HCOM_FIXTURE_NO_ACTIVE_TASKS=1
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'plain continue without an in-progress task'
[[ "$launched_orchestrator_prompt" == "$plain_ready_prompt"* && "$launched_orchestrator_prompt" != *'Task handoff for'* && "$launched_orchestrator_prompt" == *'Project handoff:'* && "$launched_orchestrator_prompt" == *"Git status for $PWD:"* ]] || fail 'plain continue without a selected task missed its startup facts'

# A blocked next task resumes from the handoff even when no task is in progress.
HCOM_FIXTURE_NEXT_STATUS=blocked
export HCOM_FIXTURE_HAS_HANDOFF=1
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'plain continue with a blocked next task and handoff'
[[ "$launched_orchestrator_prompt" == *'Resume the interrupted work on task tsk_A_B from the task handoff in this prompt. Do not select a new task.'* && "$launched_orchestrator_prompt" == *$'Task handoff for tsk_A_B:\n{"ok":true,"data":{"current_goal":"Continue the fixture task","next_step":"1. Read the saved handoff\\n2. Resume the task"}}'* ]] || fail 'plain continue with a blocked next task omitted its task handoff'
unset HCOM_FIXTURE_HAS_HANDOFF
HCOM_FIXTURE_NEXT_STATUS=ready

# A handoff or status that cannot be read is named in the prompt instead of left out.
export HCOM_FIXTURE_PROJECT_CONTEXT_FAIL=1
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'plain continue with unreadable startup facts'
[[ "$launched_orchestrator_prompt" == *'Missing: the project handoff could not be read.'* ]] || fail 'plain continue hid the failed project handoff'
unset HCOM_FIXTURE_PROJECT_CONTEXT_FAIL

# Give tsk_A_B its recorded checkout back for the named continue, then hide it again.
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B"
export HCOM_FIXTURE_TASK_CONTEXT_FAIL=1 HCOM_FIXTURE_GIT_STATUS_FAIL=1
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes || fail 'named continue with unreadable startup facts'
[[ "$launched_orchestrator_prompt" == *'Missing: the task handoff could not be read.'* && "$launched_orchestrator_prompt" == *'Missing: Git status could not be read.'* && "$launched_orchestrator_prompt" != *'Clean checkout (no changes).'* ]] || fail 'named continue hid failed startup reads'
unset HCOM_FIXTURE_TASK_CONTEXT_FAIL HCOM_FIXTURE_GIT_STATUS_FAIL
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old"
unset HCOM_FIXTURE_NO_ACTIVE_TASKS
prior_pane_calls="$pane_calls"
export HCOM_FIXTURE_WORKTREE_ERROR=git-binding-failed
if _hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes 2>"$error_file"; then
	fail 'worktree failure launched a team'
fi
[[ "$(<"$error_file")" == $'\nteam:codex: worktree git-binding-failed' && "$pane_calls" == "$prior_pane_calls" ]] || fail 'worktree failure did not stop before panes'
HCOM_FIXTURE_NEXT_STATUS=in-progress
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
if _hcom_launch_team team:codex unused unused unused unused continue --yes 2>"$error_file"; then
	fail 'in-progress default ignored a checkout error'
fi
[[ "$(<"$error_file")" == $'\nteam:codex: worktree git-binding-failed' ]] || fail 'in-progress default did not print the Progress error'
unset HCOM_FIXTURE_ONLY_TASK_ID
HCOM_FIXTURE_NEXT_STATUS=ready
unset HCOM_FIXTURE_WORKTREE_ERROR
prior_pane_calls="$pane_calls"
export HCOM_FIXTURE_ENSURE_ERROR=unresolved-dependencies
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
if _hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes 2>"$error_file"; then
	fail 'ensure failure launched a team'
fi
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == $'get tsk_A_B\nensure tsk_A_B' ]] || fail 'ensure failure did not follow a missing checkout'
[[ "$(<"$error_file")" == $'\nteam:codex: worktree unresolved-dependencies' ]] || fail 'ensure failure did not print the Progress error'
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'ensure failure came after pane creation'
unset HCOM_FIXTURE_ENSURE_ERROR

# A dirty original checkout gives a ready default task its own checkout.
HCOM_FIXTURE_GIT_DIRTY=1
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'dirty-root continuation'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_A__B" ]] || fail 'dirty-root roles did not use the checkout'
[[ "$launched_team_tags" == "$root_tags" ]] || fail 'dirty-root default changed the root tags'
export HCOM_FIXTURE_NEXT_STATUS=in-progress
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_A_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'in-progress default continuation'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_A__B" ]] || fail 'in-progress default ignored the recorded checkout'
[[ "$launched_team_tags" == "$root_tags" ]] || fail 'in-progress default changed the root tags'
HCOM_FIXTURE_NEXT_STATUS=ready
unset HCOM_FIXTURE_ONLY_TASK_ID
HCOM_FIXTURE_GIT_DIRTY=0
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'clean-root continuation'
[[ -z "$launched_pane_directory" ]] || fail 'clean original checkout did not retain its launch path'

# The root task completes before the secondary task team resumes its checkout.
export HCOM_FIXTURE_FINISHED_TASK_ID=tsk_A_B
export HCOM_FIXTURE_NEXT_TASK=tsk_A-B
print -r -- "$fixture_dir/tsk_a_B" > "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B"
rm -f "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B"
[[ "$(progress task get tsk_A_B --json | jq -r '.data.status')" == done ]] || fail 'root task did not complete in the fixture'
if progress worktree get tsk_A_B --json >/dev/null; then
	fail 'completed root task kept a recorded checkout'
fi
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes || fail 'task after root completion'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" && "$launched_team_tags" != "$root_tags" ]] || fail 'task after root completion lost its own checkout or tags'

# The secondary task completes before the next root task starts.
HCOM_FIXTURE_FINISHED_TASK_ID=tsk_a_B
rm -f "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B"
HCOM_FIXTURE_GIT_DIRTY=1
[[ "$(progress task get tsk_a_B --json | jq -r '.data.status')" == done ]] || fail 'secondary task did not complete in the fixture'
if progress worktree get tsk_a_B --json >/dev/null; then
	fail 'completed secondary task kept a recorded checkout'
fi
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'root after task completion'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_A_-B" && "$launched_team_tags" == "$root_tags" ]] || fail 'root after task completion lost its own checkout or tags'
[[ "$(<"$HCOM_FIXTURE_WORKTREE_CALLS")" == *'ensure tsk_A-B' ]] || fail 'root after task completion did not select the next task'

# Records solo tool launches without starting an installed agent.
cat > "$fixture_dir/bin/codex" <<'STUB'
#!/usr/bin/env zsh
print -r -- "codex ${CODEX_HOME:-} $*" >> "$HCOM_FIXTURE_SOLO_CALLS"
STUB
cat > "$fixture_dir/bin/claude" <<'STUB'
#!/usr/bin/env zsh
print -r -- "claude ${CLAUDE_CONFIG_DIR:-} $*" >> "$HCOM_FIXTURE_SOLO_CALLS"
STUB
chmod +x "$fixture_dir/bin/codex" "$fixture_dir/bin/claude"
export HCOM_FIXTURE_SOLO_CALLS="$fixture_dir/solo-calls"
source "$repo_root/aliases.hcom-quota.zsh"
source "$repo_root/aliases.agents.zsh"

# Records each solo launcher quota request and selects its second account.
_hcom_quota_allocate() {
	print -r -- "$1 $2" >> "$HCOM_FIXTURE_SOLO_CALLS"
	print -r -- '2 1 0'
}

unset CODEX_HOME CLAUDE_CONFIG_DIR
codex --fixture-codex || fail 'Codex solo fixture launch failed'
claude --fixture-claude || fail 'Claude solo fixture launch failed'
expected_solo_calls="$(printf '%s\n' 'codex codex' "codex $HOME/.codex-2 --fixture-codex" 'claude claude' "claude $HOME/.claude-2 --permission-mode auto --fixture-claude")"  # Quota requests and stubbed tool launches in order.
[[ "$(<"$HCOM_FIXTURE_SOLO_CALLS")" == "$expected_solo_calls" ]] || fail 'solo launchers lost the quota provider or second account'

# Records the learner role and team label without starting an agent.
#
# @param  {string}  role
#     Learner role selected by the public launcher.
# @param  {string}  ...
#     Role launch arguments following the configured role.
_hcom_launch_configured_role() {
	launched_learner_role="$1"
	learner_team_label="$HCOM_TEAM_LABEL"
}

launched_learner_role=""  # Most recent learner role sent to the launch boundary.
learner_team_label=""  # Most recent learner team label sent to the launch boundary.
learner_repository_tag="$(_hcom_scoped_tag learn:codex "$PWD")"  # Repository tag shared by fixture learners.
export REX_BLOCK=block:learner  # Rex pane the fixture learners run in.
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
: > "$HCOM_FIXTURE_REX_CALLS"

for provider in claude codex; do
	learn:$provider --team blue fixture-source fixture-context || fail "labelled $provider learner did not launch"
	[[ "$learner_team_label" == "learn-$provider-blue" && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"HCOM_TEAM_LABEL=learn-$provider-blue scout "* ]] || fail "labelled $provider learner and Scout use different labels"
	[[ "$launched_learner_role" == "learner-$provider" ]] || fail "labelled $provider launcher selected the wrong role"

	learn:$provider fixture-source || fail "unlabelled $provider learner did not launch"
	[[ "$learner_team_label" == "learn-$provider" && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"HCOM_TEAM_LABEL=learn-$provider scout "* ]] || fail "unlabelled $provider learner tags changed"
done
[[ "$(grep -c '^split -s fixture-origin-session -b block:learner --split=right --ratio 50 --label scout --focus=false -c .* --json$' "$HCOM_FIXTURE_REX_CALLS")" == 4 ]] || fail 'learners did not split their own Rex pane for each Scout'
[[ "$(grep -c '^send -s fixture-origin-session -b block:scout .* scout ' "$HCOM_FIXTURE_REX_CALLS")" == 4 && "$(grep -c '^send-key -s fixture-origin-session -b block:scout enter$' "$HCOM_FIXTURE_REX_CALLS")" == 4 ]] || fail 'learners did not start every Scout in its Rex pane'

print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
prior_learner_pane_calls="$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")"  # Pane count before duplicate and input errors.
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Rerun with --team <label> to start another learner team." learn:codex fixture-source
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == "$prior_learner_pane_calls" ]] || fail 'unlabelled duplicate opened a Scout pane'

print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-blue-scout\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-blue-scout. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Choose a different --team label to start another learner team." learn:codex --team blue fixture-source
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == "$prior_learner_pane_calls" ]] || fail 'labelled duplicate opened a Scout pane'
print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-blue-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-blue-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Choose a different --team label to start another learner team." learn:codex --team blue fixture-source
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == "$prior_learner_pane_calls" ]] || fail 'labelled learner duplicate opened a Scout pane'

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
assert_command_error $'learn:codex: invalid team label: Bad_Label\nlearn:codex: use lowercase letters, numbers, and internal hyphens.\nlearn:codex: usage: learn:codex [--team <label>] <source> [context]' learn:codex --team Bad_Label fixture-source
assert_command_error $'learn:codex: --team requires a label.\nlearn:codex: usage: learn:codex [--team <label>] <source> [context]' learn:codex --team
if learn:codex --team blue 2>"$error_file"; then
	fail 'learner accepted a label without source material'
fi
[[ "$(<"$error_file")" == 'learn:codex: usage: learn:codex [--team <label>] <source> [context]' ]] || fail 'missing learner source omitted usage'
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == "$prior_learner_pane_calls" ]] || fail 'invalid learner arguments opened a Scout pane'

: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'learn:codex: each Rex layout pane needs five arguments.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'invalid Rex layout opened a pane'

# The invalid second pane must be refused before the valid first pane opens.
assert_command_error 'learn:codex: invalid Rex layout parent for the reviewer pane: 2.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 2 right 50 reviewer 'reviewer second'
assert_command_error 'learn:codex: invalid Rex layout parent for the reviewer pane: abc.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' abc right 50 reviewer 'reviewer second'
assert_command_error 'learn:codex: invalid Rex layout side for the reviewer pane: diagonal.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 0 diagonal 50 reviewer 'reviewer second'
assert_command_error 'learn:codex: invalid Rex layout percentage for the reviewer pane: 0.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 0 right 0 reviewer 'reviewer second'
assert_command_error 'learn:codex: invalid Rex layout percentage for the reviewer pane: 100.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 0 right 100 reviewer 'reviewer second'
assert_command_error 'learn:codex: invalid Rex layout percentage for the reviewer pane: 50.5.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 0 right 50.5 reviewer 'reviewer second'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'invalid later Rex layout entry opened a pane'

_hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 1 below 40 reviewer 'reviewer second' || fail 'chained Rex layout did not launch'
layout_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"  # Rex calls recorded by the latest layout test.
[[ "$layout_calls" == *'split -s fixture-origin-session -b block:learner --split=right --ratio 50 --label scout'*'split -s fixture-origin-session -b block:scout --split=below --ratio 40 --label reviewer'*'send -s fixture-origin-session -b block:scout scout first'*'send-key -s fixture-origin-session -b block:scout enter'*'send -s fixture-origin-session -b block:reviewer reviewer second'* ]] || fail 'chained Rex layout split or command order changed'

: > "$HCOM_FIXTURE_REX_CALLS"
export HCOM_FIXTURE_REX_SPLIT_FAIL_LABEL=reviewer
assert_command_error 'learn:codex: could not set up the reviewer pane in Rex.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 1 below 40 reviewer 'reviewer second'
layout_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"
[[ "$layout_calls" == *'split -s fixture-origin-session -b block:learner --split=right'*'split -s fixture-origin-session -b block:scout --split=below'* && "$layout_calls" != *'send -s '* ]] || fail 'a later Rex split failure started a pane command'
unset HCOM_FIXTURE_REX_SPLIT_FAIL_LABEL

: > "$HCOM_FIXTURE_REX_CALLS"
export HCOM_FIXTURE_REX_SEND_ERROR_BLOCK=block:scout
assert_command_error 'learn:codex: could not start the scout pane in Rex.' _hcom_workflow_launch_rex_layout learn:codex "$PWD" 0 right 50 scout 'scout first' 1 below 40 reviewer 'reviewer second'
layout_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"
[[ "$layout_calls" == *'split -s fixture-origin-session -b block:learner --split=right'*'split -s fixture-origin-session -b block:scout --split=below'*'send -s fixture-origin-session -b block:scout scout first'* && "$layout_calls" != *'send -s fixture-origin-session -b block:reviewer'* ]] || fail 'failed Rex command typing skipped a split or started a later command'
unset HCOM_FIXTURE_REX_SEND_ERROR_BLOCK

: > "$HCOM_FIXTURE_REX_CALLS"
launched_learner_role=not-launched
export HCOM_FIXTURE_REX_SPLIT_FAIL=1
assert_command_error 'learn:codex: could not set up the scout pane in Rex.' learn:codex fixture-source
[[ "$launched_learner_role" == not-launched ]] || fail 'failed Scout pane started the learner'
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == 1 && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s '* ]] || fail 'failed Scout split sent a command or retried'
unset HCOM_FIXTURE_REX_SPLIT_FAIL

unset REX_SESSION
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'learn:codex: open Rex to start a learner.' learn:codex fixture-source
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'learner touched Rex outside a Rex session'
export REX_SESSION=fixture-origin-session
unset REX_BLOCK
assert_command_error 'learn:codex: open Rex to start a learner.' learn:codex fixture-source
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'learner touched Rex without a calling pane'

source "$repo_root/aliases.hcom-plan.zsh"

# Records each planning peer's team label without starting an agent.
#
# @param  {string}  ...
#     Role launch options, ignored by this recorder.
_hcom_launch_role() {
	plan_peer_team_labels+=("$HCOM_TEAM_LABEL")
}

export REX_BLOCK=block:plan-caller  # Calling Rex pane for the planning layout.
plan_peer_team_labels=()  # Team labels each planning peer launched with, oldest first.
plan_repository_tag="$(_hcom_scoped_tag plan "$PWD")"  # Repository tag shared by fixture planners.

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
: > "$HCOM_FIXTURE_REX_CALLS"
plan --team blue fixture-task || fail 'labelled plan did not launch'
plan_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"  # Rex calls recorded by the most recent plan launch.
[[ "$plan_calls" == *'split -s fixture-origin-session -b block:plan-caller --split=right --ratio 50 --label plan-codex'*'split -s fixture-origin-session -b block:plan-caller --split=below --ratio 40 --label plan-scout-claude'*'split -s fixture-origin-session -b block:plan-codex --split=below --ratio 40 --label plan-scout-codex'* ]] || fail 'labelled plan opened the wrong Rex layout'
[[ "$plan_calls" == *'send -s fixture-origin-session -b block:plan-codex '*'HCOM_PLANNING_WORKFLOW=1 plan:codex --team blue fixture-task'*'send -s fixture-origin-session -b block:plan-scout-claude '*'HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=plan-claude-blue scout'*'send -s fixture-origin-session -b block:plan-scout-codex '*'HCOM_PLANNING_WORKFLOW=1 HCOM_TEAM_LABEL=plan-codex-blue scout'* ]] || fail 'labelled plan commands lost their workflow flag or label'
[[ "$(print -r -- "$plan_calls" | grep -F -c -- "-c $PWD --json")" == 3 ]] || fail 'plan panes did not open in the launch directory'
[[ "$(print -r -- "$plan_calls" | grep -c '^split ')" == 3 && "$(print -r -- "$plan_calls" | grep -c '^send -s ')" == 3 && "$(print -r -- "$plan_calls" | grep -c '^send-key -s .* enter$')" == 3 ]] || fail 'labelled plan did not start three new panes'
[[ "${plan_peer_team_labels[-1]}" == plan-claude-blue ]] || fail 'labelled plan:claude used the wrong team label'

: > "$HCOM_FIXTURE_REX_CALLS"
plan fixture-task || fail 'unlabelled plan did not launch'
plan_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"
[[ "$plan_calls" == *'plan:codex fixture-task'*'HCOM_TEAM_LABEL=plan-claude scout'*'HCOM_TEAM_LABEL=plan-codex scout'* ]] || fail 'unlabelled plan commands changed'
[[ "${plan_peer_team_labels[-1]}" == plan-claude ]] || fail 'unlabelled plan:claude team label changed'

plan:claude --team blue fixture-task || fail 'labelled plan:claude did not launch'
[[ "${plan_peer_team_labels[-1]}" == plan-claude-blue ]] || fail 'plan:claude ignored the label'
plan:codex --team blue fixture-task || fail 'labelled plan:codex did not launch'
[[ "${plan_peer_team_labels[-1]}" == plan-codex-blue ]] || fail 'plan:codex ignored the label'

: > "$HCOM_FIXTURE_REX_CALLS"
print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-codex-scout\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "plan: peer already holds ${plan_repository_tag}-plan-codex-scout. Switch to that agent, or stop it with \"hcom kill peer\" and run plan again. Rerun with --team <label> to start another planning review." plan fixture-task
print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-claude-blue-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "plan: peer already holds ${plan_repository_tag}-plan-claude-blue-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run plan again. Choose a different --team label to start another planning review." plan --team blue fixture-task
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'duplicate plan touched Rex'

print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-claude-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
plan --team blue fixture-task || fail 'labelled plan was refused beside a live unlabelled planning team'
[[ "$(grep -c '^split ' "$HCOM_FIXTURE_REX_CALLS")" == 3 ]] || fail 'labelled plan beside a live unlabelled team did not open panes'
: > "$HCOM_FIXTURE_REX_CALLS"

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
assert_command_error $'plan: invalid team label: Bad_Label\nplan: use lowercase letters, numbers, and internal hyphens.\nplan: usage: plan [--team <label>] <task-name>' plan --team Bad_Label fixture-task
if plan --team blue 2>"$error_file"; then
	fail 'plan accepted a label without a task name'
fi
[[ "$(<"$error_file")" == 'plan: usage: plan [--team <label>] <task-name>' ]] || fail 'missing plan task omitted usage'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'invalid plan arguments touched Rex'

unset REX_SESSION
assert_command_error 'plan: open Rex to start a planning review.' plan fixture-task
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'plan touched Rex outside a Rex session'
export REX_SESSION=fixture-origin-session
unset REX_BLOCK
assert_command_error 'plan: open Rex to start a planning review.' plan fixture-task
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'plan touched Rex without a calling pane'

# Invalid close-out arguments and a missing quick task leave the team untouched.
_hcom_clear_team_scope
stopped_team_tags=''
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
: > "$HCOM_FIXTURE_WORKTREE_CALLS"
assert_command_error 'team:done: usage: team:done --team <label>' team:done
assert_command_error 'team:done: usage: team:done --team <label>' team:done --bad blue
assert_command_error 'team:done: usage: team:done --team <label>' team:done --team
assert_command_error 'team:done: no unfinished quick task for team blue.' team:done --team blue
[[ ! -s "$HCOM_FIXTURE_COMPLETE_CALLS" && ! -s "$HCOM_FIXTURE_WORKTREE_CALLS" && -z "$stopped_team_tags" ]] || fail 'missing quick task changed the team or task'

# A dirty managed checkout must be refused before stopping peers or completing the task.
export HCOM_FIXTURE_QUICK_STATE=unfinished
export HCOM_FIXTURE_GIT_DIRTY=1
: > "$HCOM_FIXTURE_GIT_CALLS"
assert_command_error "team:done: uncommitted work in $fixture_dir/tsk_quick; commit or discard it before finishing the team." team:done --team blue
[[ "$(<"$HCOM_FIXTURE_GIT_CALLS")" == "$fixture_dir/tsk_quick --porcelain" && ! -s "$HCOM_FIXTURE_COMPLETE_CALLS" && -z "$stopped_team_tags" ]] || fail 'dirty quick checkout was not refused before side effects'

# A clean checkout stops its task team and completes the task.
export HCOM_FIXTURE_GIT_DIRTY=0
team:done --team blue >/dev/null || fail 'clean quick task did not complete'
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick && "$stopped_team_tags" == 'Agents-quick-blue-orchestrator|Agents-quick-blue-reviewer|Agents-quick-blue-implementer|Agents-quick-blue-scout' ]] || fail 'clean quick task did not stop its peers and complete'

# A completion error is reported after the team has stopped.
export HCOM_FIXTURE_COMPLETE_ERROR=1
stopped_team_tags=''
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
assert_command_error 'team:done: task completion failed' team:done --team blue
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick && -n "$stopped_team_tags" ]] || fail 'completion error happened before the team stopped'
unset HCOM_FIXTURE_COMPLETE_ERROR

# The stop scope uses the checkout folder even when the project slug is invalid.
export HCOM_FIXTURE_PROJECT_SLUG=Bad_Project
stopped_team_tags=''
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
team:done --team blue >/dev/null || fail 'unused project slug blocked team completion'
[[ -n "$stopped_team_tags" && "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick ]] || fail 'project slug changed stop targeting or completion'
unset HCOM_FIXTURE_PROJECT_SLUG

# A quick task without a managed checkout still stops its peers and completes.
export HCOM_FIXTURE_NO_QUICK_CHECKOUT=1
stopped_team_tags=''
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
: > "$HCOM_FIXTURE_GIT_CALLS"
team:done --team blue >/dev/null || fail 'quick task without a checkout did not complete'
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick && -n "$stopped_team_tags" && ! -s "$HCOM_FIXTURE_GIT_CALLS" ]] || fail 'checkout-less quick task skipped its stop or completion'

# A recorded checkout whose folder has gone can still be completed.
unset HCOM_FIXTURE_NO_QUICK_CHECKOUT
mv "$fixture_dir/tsk_quick" "$fixture_dir/removed-quick"
export HCOM_FIXTURE_COMPLETE_REMOVED=1
stopped_team_tags=''
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
: > "$HCOM_FIXTURE_GIT_CALLS"
team:done --team blue >/dev/null || fail 'quick task with a missing checkout folder did not complete'
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick && -n "$stopped_team_tags" && ! -s "$HCOM_FIXTURE_GIT_CALLS" ]] || fail 'missing checkout folder blocked the stop or completion'

# Completion reports commits that remain unmerged after the folder is gone.
export HCOM_FIXTURE_UNMERGED_COMMITS=2
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
assert_command_error 'team:done: task completed, but 2 commits were not merged. Run from a checkout of main: git merge quick-blue' team:done --team blue
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick ]] || fail 'unmerged commits blocked task completion'
export HCOM_FIXTURE_UNMERGED_COMMITS=1
assert_command_error 'team:done: task completed, but 1 commit was not merged. Run from a checkout of main: git merge quick-blue' team:done --team blue
unset HCOM_FIXTURE_UNMERGED_COMMITS

# Completion reports an error when it cannot count the unmerged commits.
export HCOM_FIXTURE_COUNT_ERROR=1
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
assert_command_error 'team:done: task completed, but could not count unmerged commits: could not count commits. Run from a checkout of main: git merge quick-blue' team:done --team blue
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick ]] || fail 'commit count error blocked task completion'
export HCOM_FIXTURE_BASE_BRANCH=''
assert_command_error "team:done: task completed, but could not count unmerged commits: could not count commits. Find the task's base branch checkout, then run: git merge quick-blue" team:done --team blue
unset HCOM_FIXTURE_BASE_BRANCH
unset HCOM_FIXTURE_COUNT_ERROR HCOM_FIXTURE_COMPLETE_REMOVED
mv "$fixture_dir/removed-quick" "$fixture_dir/tsk_quick"

# Progress may complete the task while leaving checkout clean-up for a manual retry.
export HCOM_FIXTURE_COMPLETE_PENDING=1
: > "$HCOM_FIXTURE_COMPLETE_CALLS"
assert_command_error 'team:done: task completed, but checkout cleanup is pending: rebase conflict. Run: progress worktree cleanup tsk_quick' team:done --team blue
[[ "$(<"$HCOM_FIXTURE_COMPLETE_CALLS")" == tsk_quick ]] || fail 'pending checkout clean-up did not complete the task'

: > "$HCOM_FIXTURE_REX_CALLS"
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex || fail 'Rex team tab creation'
[[ "${reply[2]}" == 'fixture-origin-session' && "${reply[3]}" == 'window:new' ]] || fail 'Rex tab session and ID were not returned'
[[ "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/reviewer")" == '# hcom-team-role-v2 codex auto 2'$'\n''HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture reviewer:codex '* ]] || fail 'reviewer reset command lost its agent, account or team scope'
[[ "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/implementer")" == '# hcom-team-role-v2 codex auto 1'$'\n''HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture implementer '* ]] || fail 'implementer reset command lost its agent, account or team scope'
[[ "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/scout")" == '# hcom-team-role-v2 codex auto 2'$'\n''HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture scout '* ]] || fail 'scout reset command lost its agent, account or team scope'
for role in reviewer implementer scout; do
	# The command saved for this role, which a reset types into its pane again.
	role_command="$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/$role")"
	assert_no_role_title "$role_command" "$role reset command still sets or suppresses a title"
done
[[ -s "$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/orchestrator" ]] || fail 'new-tab orchestrator command was not saved on disk'
[[ "$(grep -c '^send-key .* enter$' "$HCOM_FIXTURE_REX_CALLS")" == 4 ]] || fail 'Rex did not submit all four role commands'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task -c '*'--focus=false --json'* ]] || fail 'Rex tab was not opened in the current session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'split -s fixture-origin-session -b block:new --split=right --ratio 33 --label implementer --focus=false --json'* ]] || fail 'Rex implementer pane was not split from the new tab'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'split -s fixture-origin-session -b block:implementer --split=below --ratio 67 --label reviewer --focus=false --json'* ]] || fail 'Rex reviewer pane was not split from the implementer'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'split -s fixture-origin-session -b block:reviewer --split=below --ratio 50 --label scout --focus=false --json'* ]] || fail 'Rex scout pane was not split from the reviewer'
grep -Fxq 'focus -s fixture-origin-session block:new' "$HCOM_FIXTURE_REX_CALLS" || fail 'Rex did not focus the new tab'
if grep -q '^new ' "$HCOM_FIXTURE_REX_CALLS"; then
	fail 'Rex opened a new session'
fi
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session.resize_pane'* ]] || fail 'new Rex tab was resized'
for role in implementer reviewer scout; do
	# The command typed into this role's pane.
	role_send="$(grep "^send -s fixture-origin-session -b block:$role " "$HCOM_FIXTURE_REX_CALLS")"
	assert_no_role_title "$role_send" "$role pane still sets or suppresses a title"
done
orchestrator_send="$(grep '^send -s fixture-origin-session -b block:new ' "$HCOM_FIXTURE_REX_CALLS")"
assert_no_role_title "$orchestrator_send" 'orchestrator pane still sets or suppresses a title'
# Exact directory in the saved orchestrator command.
checkout_path="$fixture_dir/project"
# Exact first prompt in the saved orchestrator command.
prompt_text='Continue fixture task.'
# Directory and prompt as the shell sees them.
expected_suffix=" ${(qq)checkout_path} ${(qq)prompt_text}"
# File that the short typed line runs.
saved_orchestrator_command="$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:new/orchestrator"
[[ "$orchestrator_send" == "send -s fixture-origin-session -b block:new source ${(qq)saved_orchestrator_command}" && "${#orchestrator_send}" -lt 1024 ]] || fail 'new pane received a long orchestrator command'
[[ "$(<"$saved_orchestrator_command")" == *"$expected_suffix; _hcom_team_return_to_main_checkout ${(qq)checkout_path}; }" ]] || fail 'saved orchestrator command lost its quoted checkout or prompt'
[[ "$(<"$saved_orchestrator_command")" == *'HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture '* ]] || fail 'saved orchestrator command lost its team scope'
assert_no_role_title "$(<"$saved_orchestrator_command")" 'saved orchestrator command still sets or suppresses a title'

# A handoff with shell punctuation and a long line survives the saved command.
# Handoff text that the shell would change if the quoting were wrong.
harsh_text=$'Apostrophe '\'' backtick ` dollar $HOME substitution $(date) double "quote" slash \\n bang !!\nsecond line\n'
harsh_text+="$(printf '%02100d' 0)"
# That text in the JSON form that progress prints.
harsh_handoff="$(jq -n --arg next_step "$harsh_text" '{ok:true,data:{next_step:$next_step}}')"
print -rn -- "$harsh_handoff" > "$fixture_dir/harsh-handoff.json"
export HCOM_FIXTURE_HANDOFF_FILE="$fixture_dir/harsh-handoff.json"
# Startup facts holding that handoff, used as the launch prompt.
harsh_prompt="$(_hcom_team_startup_facts "$fixture_dir/project" tsk_A_B)"
unset HCOM_FIXTURE_HANDOFF_FILE
[[ "$harsh_prompt" == *"$harsh_handoff"* ]] || fail 'startup facts changed the harsh handoff'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex "$harsh_prompt" 1 codex tsk_A_B || fail 'long handoff pane creation'
orchestrator_send="$(grep '^send -s fixture-origin-session -b block:new ' "$HCOM_FIXTURE_REX_CALLS")"
[[ "$orchestrator_send" == "send -s fixture-origin-session -b block:new source ${(qq)saved_orchestrator_command}" && "${#orchestrator_send}" -lt 1024 ]] || fail 'long handoff produced a long typed command'
(
	_hcom_team_run_orchestrator() { print -rn -- "${@: -1}" > "$fixture_dir/replayed-handoff"; }
	source "$saved_orchestrator_command"
) || fail 'saved orchestrator command did not run'
[[ "$(<"$fixture_dir/replayed-handoff")" == "$harsh_prompt" ]] || fail 'sourcing the saved command changed the harsh handoff'

# A lone current pane becomes the orchestrator pane for a task team.
export REX_BLOCK=block:origin
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
long_prompt="$(printf '%01500d' 0)"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex "$long_prompt" 1 codex tsk_A_B || fail 'unused current Rex session reuse'
[[ "${reply[2]}" == fixture-origin-session ]] || fail 'current Rex session ID was not returned'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block rename -s fixture-origin-session block:origin orchestrator'*'session rename fixture-origin-session Fixture'*'window rename -s fixture-origin-session window:origin Fixture task'*'split -s fixture-origin-session -b block:origin --split=right'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block call process -s fixture-origin-session -b block:origin'* ]] || fail 'unused current session was not relabelled and split'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'split -s fixture-origin-session -b block:reviewer --split=below --ratio 50 --label scout --focus=false --json'*'api call -s fixture-origin-session session.resize_pane {"direction":"horizontal","before_block_id":"block:origin","after_block_id":"block:implementer","ratio":0.67}'*'api call -s fixture-origin-session session.resize_pane {"direction":"vertical","before_block_id":"block:implementer","after_block_id":"block:reviewer","ratio":0.33}'*'api call -s fixture-origin-session session.resize_pane {"direction":"vertical","before_block_id":"block:reviewer","after_block_id":"block:scout","ratio":0.5}'* ]] || fail 'reused Rex tab did not get the new-tab pane proportions'
[[ "$(grep -c 'session.resize_pane' "$HCOM_FIXTURE_REX_CALLS")" == 3 ]] || fail 'reused Rex session resized an unexpected number of borders'
orchestrator_send="$(grep '^send -s fixture-origin-session -b block:origin ' "$HCOM_FIXTURE_REX_CALLS")"
saved_orchestrator_command="$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:origin/orchestrator"
[[ "$orchestrator_send" == "send -s fixture-origin-session -b block:origin source ${(qq)saved_orchestrator_command}" && "${#orchestrator_send}" -lt 1024 && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* ]] || fail 'reused pane received a long orchestrator command'
[[ "$(<"$saved_orchestrator_command")" == *" ${(qq)long_prompt}; _hcom_team_return_to_main_checkout ${(qq)checkout_path}; }" && "$(<"$saved_orchestrator_command")" == "cd -- ${(qq)checkout_path} && "* ]] || fail 'saved orchestrator command lost the checkout or prompt'
assert_no_role_title "$(<"$saved_orchestrator_command")" 'saved orchestrator command still sets or suppresses a title'

# A worktree team's pane ends in the main checkout after the team shuts down, even when the Orchestrator exits with an error.
(
	orchestrator:codex() { return 1; }
	source "$saved_orchestrator_command"
	[[ -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'worktree pane kept the team scope'
	[[ "$PWD" == "$HCOM_FIXTURE_MAIN_CHECKOUT" ]] || fail 'worktree pane did not return to the main checkout after the role failed'
	(( ! ${+main_checkout} && ! ${+checkout_root} )) || fail 'returning to the main checkout left a variable set in the pane shell'
) || fail 'worktree pane command did not finish'

# The pane still returns when the team could not shut down cleanly.
(
	_hcom_team_run_orchestrator() { return 1; }
	source "$saved_orchestrator_command"
	[[ "$PWD" == "$HCOM_FIXTURE_MAIN_CHECKOUT" ]] || fail 'worktree pane stayed in the worktree after a failed shutdown'
) || fail 'failed shutdown pane command did not finish'

# A taskless team in a main-checkout subfolder leaves that pane in the subfolder.
mkdir -p "$HCOM_FIXTURE_MAIN_CHECKOUT/subfolder"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$HCOM_FIXTURE_MAIN_CHECKOUT/subfolder" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'main checkout pane creation'
saved_orchestrator_command="$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/orchestrator"
(
	orchestrator:codex() { return 0; }
	source "$saved_orchestrator_command"
	[[ -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'main checkout pane kept the team scope'
	[[ "$PWD" == "$HCOM_FIXTURE_MAIN_CHECKOUT/subfolder" ]] || fail 'main checkout pane left its starting subfolder'
) || fail 'main checkout pane command did not finish'

# A team without a task still returns from a linked worktree.
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$checkout_path" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'taskless worktree pane creation'
saved_orchestrator_command="$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/orchestrator"
(
	orchestrator:codex() { return 0; }
	source "$saved_orchestrator_command"
	[[ "$PWD" == "$HCOM_FIXTURE_MAIN_CHECKOUT" ]] || fail 'taskless worktree pane did not return to the main checkout'
) || fail 'taskless worktree pane command did not finish'

# An unnamed session takes the repository name when the launcher is its sole pane.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":""}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'unnamed launcher session reuse'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'session rename fixture-origin-session Fixture'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'window new'* ]] || fail 'unnamed launcher session kept its old name'
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'

# A team without a task also builds in an unused current tab and resizes its panes to match a new tab's layout.
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'bare team current Rex session reuse'
[[ "${reply[2]}" == fixture-origin-session && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'session rename fixture-origin-session Fixture'*'window rename -s fixture-origin-session window:origin Team'*'split -s fixture-origin-session -b block:origin --split=right'*'api call -s fixture-origin-session session.resize_pane'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* ]] || fail 'bare team did not reuse and resize the unused tab'

# A team without a task opens a new tab when the current tab has two panes.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"},{"block_id":"block:other","window_id":"window:origin","label":"other"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'bare team busy tab fallback'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Team -c '*'--focus=false --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename fixture-origin-session'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session.resize_pane'* ]] || fail 'bare team reused or resized a busy tab'

# A launcher pane without a tab ID opens a new tab even when older teams are ambiguous.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","label":"shell"},{"block_id":"block:older-a","label":"orchestrator"},{"block_id":"block:older-b","label":"orchestrator"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'launcher without a tab ID'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Team -c '*'--focus=false --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename fixture-origin-session'* ]] || fail 'launcher without a tab ID did not open a new tab'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'

# A resize failure warns and still starts all four roles in the reused tab.
export REX_SESSION=fixture-resize-failure
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-resize-failure","label":"Plain session"}]}'
export HCOM_FIXTURE_REX_RESIZE_FAIL=1
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_resize_failure 2>"$error_file" || fail 'resize failure stopped the team launch'
[[ "$(<"$error_file")" == 'team:codex: Rex panes could not be resized; the team is starting anyway.' ]] || fail 'resize failure did not give one warning'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'api call -s fixture-resize-failure session.resize_pane'* && "$(grep -c '^send-key .* enter$' "$HCOM_FIXTURE_REX_CALLS")" == 4 && "${reply[2]}" == fixture-resize-failure ]] || fail 'resize failure did not start all four roles'
unset HCOM_FIXTURE_REX_RESIZE_FAIL
export REX_SESSION=fixture-origin-session
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'

# Rex reports its own process in the launcher pane while the plain tab is being inspected.
export HCOM_FIXTURE_REX_PROCESS=rex
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'plain tab reuse while Rex reports its own process'
[[ "${reply[2]}" == fixture-origin-session && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'session rename fixture-origin-session Fixture'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block call process -s fixture-origin-session -b block:origin'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* ]] || fail 'Rex process report blocked plain tab reuse'
unset HCOM_FIXTURE_REX_PROCESS

# More than one pane opens a new tab in the current session.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"},{"block_id":"block:other","window_id":"window:origin","label":"other"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'multi-pane current session fallback'
[[ "${reply[2]}" == fixture-origin-session && "${reply[3]}" == window:new ]] || fail 'busy tab returned the wrong session or tab'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task -c '*'--focus=false --json'* ]] || fail 'busy tab did not open a new tab in the current session'
if grep -Eq '^(session rename fixture-origin-session|new )' "$HCOM_FIXTURE_REX_CALLS"; then
	fail 'busy tab renamed or opened a session'
fi

# A free launcher tab stays reusable when another tab shares its session.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"},{"block_id":"block:other","window_id":"window:other","label":"other"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'other tab in current session fallback'
[[ "${reply[2]}" == fixture-origin-session && "${reply[3]}" == window:origin && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block rename -s fixture-origin-session block:origin orchestrator'*'window rename -s fixture-origin-session window:origin Fixture task'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename fixture-origin-session'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'window new'* ]] || fail 'free tab in a multi-pane session was not reused without renaming the session'

# A named repository session gets a new tab when the launcher's tab is busy.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"},{"session_id":"session:repo","label":"Fixture"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'repository session new tab'
[[ "${reply[2]}" == session:repo && "${reply[3]}" == window:new && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:repo Fixture task -c '*'--focus=false --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename'* ]] || fail 'repository session was not reused with a new tab'

# A plain free tab yields to a repository session elsewhere.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'repository session preferred to plain tab'
[[ "${reply[2]}" == session:repo && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:repo Fixture task'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename fixture-origin-session'* ]] || fail 'plain tab displaced the repository session'

# The launcher's named session wins when more than one has the repository name.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:first","label":"Fixture"},{"session_id":"fixture-origin-session","label":"Fixture"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"},{"block_id":"block:other","window_id":"window:origin","label":"other"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'launcher repository session choice'
[[ "${reply[2]}" == fixture-origin-session && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task'* ]] || fail 'launcher repository session did not win'

# Without a launcher session, the first named repository session wins.
unset REX_SESSION REX_BLOCK
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'first repository session choice'
[[ "${reply[2]}" == session:first && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:first Fixture task'* ]] || fail 'first repository session did not win'
export REX_SESSION=fixture-origin-session REX_BLOCK=block:origin

# A stopped team's idle role panes are closed before new role panes are created.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Fixture"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"orchestrator"},{"block_id":"block:old-implementer","window_id":"window:origin","label":"implementer"},{"block_id":"block:old-reviewer","window_id":"window:origin","label":"reviewer"},{"block_id":"block:old-scout","window_id":"window:origin","label":"scout"}]}'
print -r -- $'fixture-origin-session\nwindow:origin' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_stopped"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'idle stopped tab reuse'
placement_calls="$(<"$HCOM_FIXTURE_REX_CALLS")"
[[ "${reply[2]}" == fixture-origin-session && "${reply[3]}" == window:origin && "$placement_calls" == *'block close block:old-implementer -s fixture-origin-session'*'block close block:old-reviewer -s fixture-origin-session'*'block close block:old-scout -s fixture-origin-session'*'split -s fixture-origin-session -b block:origin --split=right --ratio 33 --label implementer'*'split -s fixture-origin-session -b block:implementer --split=below --ratio 67 --label reviewer'*'split -s fixture-origin-session -b block:reviewer --split=below --ratio 50 --label scout'* && "$placement_calls" != *'window new'* ]] || fail 'stopped tab did not finish with one pane per role'
[[ "$(print -r -- "$placement_calls" | grep -c '^block close ')" == 3 && "$(print -r -- "$placement_calls" | grep -c '^split ')" == 3 ]] || fail 'stopped tab kept an old role pane or created an extra pane'

# A failed close stops the launch before the new role panes are split.
print -r -- $'fixture-origin-session\nwindow:origin' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_stopped"
export HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK=block:old-implementer
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture assert_command_error 'team:codex: stopped team pane block:old-implementer could not be closed; no new panes launched.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'split '* ]] || fail 'a failed pane close still created new role panes'
unset HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK

# An idle unlabelled shell in the saved tab sends the team to a new tab.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"orchestrator"},{"block_id":"block:other-shell","window_id":"window:origin","label":"shell"}]}'
print -r -- $'fixture-origin-session\nwindow:origin' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_stopped"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'unlabelled shell tab fallback'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:other-shell'* ]] || fail 'unlabelled shell was taken as an old team pane'

# A running role pane also sends the team to a new tab.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"orchestrator"},{"block_id":"block:old-implementer","window_id":"window:origin","label":"implementer"}]}'
print -r -- $'fixture-origin-session\nwindow:origin' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_stopped"
export HCOM_FIXTURE_REX_PROCESS=claude
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_A_B || fail 'busy leftover tab fallback'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task'* ]] || fail 'running pane did not force a new tab'
unset HCOM_FIXTURE_REX_PROCESS
trash "$XDG_STATE_HOME/hcom-team/tasks/tsk_stopped" >/dev/null

[[ "$(_hcom_team_launch_tab_name quick-review-source-notes-and-tests-extra)" == 'Review source notes and tests' && "$(_hcom_team_launch_tab_name fixture-TASK)" == 'Fixture task' && "$(_hcom_team_launch_tab_name '')" == Team ]] || fail 'team tab name derivation'

unset REX_BLOCK HCOM_FIXTURE_REX_SESSIONS HCOM_FIXTURE_REX_BLOCKS

# The orchestrator wrapper stops peers and clears scope after its role exits.
fixture_orchestrator() { return 0; }
: > "$HCOM_FIXTURE_REX_CALLS"
_hcom_team_run_orchestrator session:fixture block:implementer block:reviewer block:scout 'fixture-tags' fixture-task tsk_fixture fixture_orchestrator "$checkout_path" "$prompt_text" || fail 'orchestrator exit cleanup'
[[ "$(grep -c '^send-key .* ctrl+c ctrl+c$' "$HCOM_FIXTURE_REX_CALLS")" == 3 && -z "${HCOM_TEAM_SESSION_ID:-}" && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'orchestrator exit lost a pane or scope cleanup'
for role in implementer reviewer scout; do
	[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"send -s session:fixture -b block:$role clear"*"send-key -s session:fixture -b block:$role enter"* ]] || fail "$role pane was not cleared after stopping"
done
# A peer that stays busy reports its pane while the wrapper still clears scope.
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
if _hcom_team_run_orchestrator session:fixture block:implementer block:reviewer block:scout 'fixture-tags' fixture-task tsk_fixture fixture_orchestrator "$checkout_path" "$prompt_text" 2>"$error_file"; then
	fail 'orchestrator exit accepted a busy reviewer pane'
fi
[[ "$(<"$error_file")" == 'team: peer pane block:reviewer did not return to a shell prompt.' && -z "${HCOM_TEAM_SESSION_ID:-}" && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" && "$(grep -c '^send-key .* ctrl+c ctrl+c$' "$HCOM_FIXTURE_REX_CALLS")" == 3 ]] || fail 'busy peer exit missed its pane message or scope cleanup'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:fixture -b block:reviewer clear'* ]] || fail 'busy reviewer pane was cleared'
for role in implementer scout; do
	[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"send -s session:fixture -b block:$role clear"*"send-key -s session:fixture -b block:$role enter"* ]] || fail "$role pane was not cleared when the reviewer stayed busy"
done
unset HCOM_FIXTURE_REX_BUSY_BLOCK
# A failed process lookup uses the same pane message and clears scope.
export HCOM_FIXTURE_REX_PROCESS_ERROR_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
if _hcom_team_run_orchestrator session:fixture block:implementer block:reviewer block:scout 'fixture-tags' fixture-task tsk_fixture fixture_orchestrator "$checkout_path" "$prompt_text" 2>"$error_file"; then
	fail 'orchestrator exit accepted a failed reviewer process check'
fi
[[ "$(<"$error_file")" == 'team: peer pane block:reviewer did not return to a shell prompt.' && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'failed process lookup missed its pane message or scope cleanup'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:fixture -b block:reviewer clear'* ]] || fail 'failed process lookup cleared the reviewer pane'
for role in implementer scout; do
	[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"send -s session:fixture -b block:$role clear"*"send-key -s session:fixture -b block:$role enter"* ]] || fail "$role pane was not cleared after the reviewer process check failed"
done
unset HCOM_FIXTURE_REX_PROCESS_ERROR_BLOCK
# A failed clear reports the pane and still clears the other teammates.
export HCOM_FIXTURE_REX_SEND_ERROR_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
if _hcom_team_run_orchestrator session:fixture block:implementer block:reviewer block:scout 'fixture-tags' fixture-task tsk_fixture fixture_orchestrator "$checkout_path" "$prompt_text" 2>"$error_file"; then
	fail 'orchestrator exit accepted a failed reviewer clear'
fi
[[ "$(<"$error_file")" == 'team: peer pane block:reviewer could not be cleared.' && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'failed clear missed its pane message or scope cleanup'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key -s session:fixture -b block:reviewer enter'* ]] || fail 'failed clear submitted a command to the reviewer pane'
for role in implementer scout; do
	[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *"send -s session:fixture -b block:$role clear"*"send-key -s session:fixture -b block:$role enter"* ]] || fail "$role pane was not cleared after the reviewer clear failed"
done
unset HCOM_FIXTURE_REX_SEND_ERROR_BLOCK
unfunction fixture_orchestrator
print -r -- session:fixture > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_A_B --yes || fail 'task session bookmark relaunch'
[[ "$replaced_session_id" == session:fixture ]] || fail 'task relaunch ignored the stored session ID from another shell'

# A Claude startup hook can rename the session; its stored ID still finds the panes.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:fixture","label":"renamed by Claude"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex || fail 'renamed Rex session reuse'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s session:fixture --json'*'block call process -s session:fixture -b block:orchestrator'*'focus -s session:fixture block:orchestrator'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session kill'* ]] || fail 'stored session ID was not reused'

# A busy role pane stops relaunch before any command is typed.
export HCOM_FIXTURE_REX_PROCESS=claude
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team:codex: orchestrator pane block:orchestrator is still running an agent; stop it before relaunching.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send '* ]] || fail 'busy pane received a launch command'
unset HCOM_FIXTURE_REX_PROCESS

# A missing scout pane is created beneath the reviewer in the reused session.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:orchestrator","label":"orchestrator"},{"block_id":"block:implementer","label":"implementer"},{"block_id":"block:reviewer","label":"reviewer"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex || fail 'missing Rex scout pane creation'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'split -s session:fixture -b block:reviewer --split=below --ratio 50 --label scout'* ]] || fail 'missing scout pane was not restored'
unset HCOM_FIXTURE_REX_BLOCKS

# A failed split identifies the Rex session that needs manual inspection.
export HCOM_FIXTURE_REX_SPLIT_FAIL=1
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"},{"session_id":"session:fixture","label":"renamed by Claude"}]}'
assert_command_error 'team:codex: team session fixture-origin-session was left partly built.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex
unset HCOM_FIXTURE_REX_SPLIT_FAIL

# Records each path moved to the trash so tests can check what was removed.
trash() { print -r -- "$1" >> "$fixture_dir/trashed"; mkdir -p "$fixture_dir/trashed-state"; mv "$1" "$fixture_dir/trashed-state/${1:t}"; }
# A record without a known tab cannot keep a plain tab from being reused.
export REX_BLOCK=block:origin
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'
mkdir -p "$XDG_STATE_HOME/hcom-team/tasks"
print -r -- fixture-origin-session > "$XDG_STATE_HOME/hcom-team/tasks/tsk_other_task"
: > "$HCOM_FIXTURE_REX_CALLS"
: > "$fixture_dir/trashed"
export HCOM_FIXTURE_REX_SPLIT_FAIL=1
assert_command_error 'team:codex: team session fixture-origin-session was left partly built.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B
[[ -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_other_task" && ! -s "$fixture_dir/trashed" ]] || fail 'saved task record was removed before team panes were built'
unset HCOM_FIXTURE_REX_SPLIT_FAIL
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'plain tab reuse with another task record'
[[ "${reply[2]}" == fixture-origin-session && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* ]] || fail 'plain tab was not reused'
trash "$XDG_STATE_HOME/hcom-team/fixture-origin-session/window:origin" >/dev/null
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"orchestrator"}]}'
_hcom_team_forget_other_tasks_in_session fixture-origin-session window:origin tsk_A_B || fail 'record check after the launcher pane was relabelled'
[[ ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_other_task" ]] || fail 'an older record for the reused tab survived its pane rename'
unset REX_BLOCK HCOM_FIXTURE_REX_BLOCKS

# A closed stored session discards its old commands before a new tab opens.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'
mkdir -p "$XDG_STATE_HOME/hcom-team/session:fixture"
: > "$HCOM_FIXTURE_REX_CALLS"
print -r -- session:fixture > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'closed Rex session replacement'
grep -Fxq "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B" "$fixture_dir/trashed" || fail 'closed task record was not discarded'
grep -Fxq "$XDG_STATE_HOME/hcom-team/session:fixture" "$fixture_dir/trashed" || fail 'closed session commands were not discarded'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s fixture-origin-session Fixture task -c '*'--focus=false --json'* ]] || fail 'closed session did not open a tab in the current session'
if grep -q '^new ' "$HCOM_FIXTURE_REX_CALLS"; then
	fail 'closed session caused a new Rex session'
fi

# A task whose saved session has closed is built in the current plain pane.
export REX_BLOCK=block:origin
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'
print -r -- session:fixture > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'closed saved session current-pane reuse'
[[ "${reply[2]}" == fixture-origin-session && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'session rename fixture-origin-session Fixture'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* && "$(<"$fixture_dir/trashed")" == *"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"* ]] || fail 'closed saved session prevented current-pane reuse'
unset REX_BLOCK HCOM_FIXTURE_REX_BLOCKS

# A task can reuse its own saved session after its old orchestrator pane closes.
export REX_BLOCK=block:origin
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Fixture · fixture-task"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:origin","window_id":"window:origin","label":"shell"}]}'
print -r -- fixture-origin-session > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
: > "$HCOM_FIXTURE_REX_CALLS"
fixture_create_panes_definition="${functions[_hcom_team_create_panes]}"
functions[_hcom_team_create_panes]="${functions[_hcom_team_create_panes_real]}"
_hcom_launch_team team:codex orchestrator:codex reviewer:codex implementer scout continue --task tsk_A_B --yes || fail 'saved current Rex session reuse'
functions[_hcom_team_create_panes]="$fixture_create_panes_definition"
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s fixture-origin-session --json'*'block rename -s fixture-origin-session block:origin orchestrator'*'session rename fixture-origin-session Agents'*'window rename -s fixture-origin-session window:origin Continue parallel task teams'*'split -s fixture-origin-session -b block:origin --split=right'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* ]] || fail 'saved current session was not reused as the team session'
[[ "$(<"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B")" == $'fixture-origin-session\nwindow:origin' ]] || fail 'task was not saved to its reused tab'

# Continuing in an older named session focuses its tab without renaming a session that has several panes.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Fixture · older task"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:orchestrator","window_id":"window:older","label":"orchestrator"},{"block_id":"block:implementer","window_id":"window:older","label":"implementer"},{"block_id":"block:reviewer","window_id":"window:older","label":"reviewer"},{"block_id":"block:scout","window_id":"window:older","label":"scout"}]}'
print -r -- $'fixture-origin-session\nwindow:older' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_older_fixture"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task fixture-origin-session 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_older_fixture || fail 'older team tab reuse'
[[ "${reply[2]}" == fixture-origin-session && "${reply[3]}" == window:older && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window focus window:older -s fixture-origin-session'*'window rename -s fixture-origin-session window:older Fixture task'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session rename fixture-origin-session'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'window new'* ]] || fail 'older team tab was not focused and renamed in place'

# A saved tab with one pane keeps its session name when another session has the repository name.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Fixture · older task"},{"session_id":"session:repo","label":"Fixture"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:orchestrator","window_id":"window:older","label":"orchestrator"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task fixture-origin-session 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_older_fixture || fail 'saved sole-pane tab with another repository session'
grep -Fxq 'window focus window:older -s fixture-origin-session' "$HCOM_FIXTURE_REX_CALLS" || fail 'saved sole-pane tab was not focused'
if grep -q '^session rename fixture-origin-session ' "$HCOM_FIXTURE_REX_CALLS"; then
	fail 'saved sole-pane session took a name held by another session'
fi

# A saved tab with one pane names its session after the repository when that name is free.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Fixture · older task"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task fixture-origin-session 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_older_fixture || fail 'saved sole-pane tab without another repository session'
grep -Fxq 'window focus window:older -s fixture-origin-session' "$HCOM_FIXTURE_REX_CALLS" || fail 'saved sole-pane tab was not focused'
grep -Fxq 'session rename fixture-origin-session Fixture' "$HCOM_FIXTURE_REX_CALLS" || fail 'saved sole-pane session kept its older name'
trash "$XDG_STATE_HOME/hcom-team/tasks/tsk_older_fixture" >/dev/null
unset REX_BLOCK HCOM_FIXTURE_REX_BLOCKS

# An open session without an orchestrator pane is replaced after every old role is checked.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"fixture-origin-session","label":"Plain session"},{"session_id":"session:orphan","label":"Fixture · fixture-task"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:implementer","label":"implementer"},{"block_id":"block:reviewer","label":"reviewer"},{"block_id":"block:scout","label":"scout"}]}'
mkdir -p "$XDG_STATE_HOME/hcom-team/session:orphan"
print -r -- session:orphan > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:scout
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team:codex: scout pane block:scout is still running an agent; stop it before relaunching.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:orphan 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B" ]] || fail 'busy orphan session was replaced'
unset HCOM_FIXTURE_REX_BUSY_BLOCK
: > "$HCOM_FIXTURE_REX_CALLS"
# Run the public launcher so the test also checks that it saves the new tab for the task.
fixture_create_panes_definition="${functions[_hcom_team_create_panes]}"
functions[_hcom_team_create_panes]="${functions[_hcom_team_create_panes_real]}"
_hcom_launch_team team:codex orchestrator:codex reviewer:codex implementer scout continue --task tsk_A_B --yes || fail 'orphan Rex session replacement'
functions[_hcom_team_create_panes]="$fixture_create_panes_definition"
grep -Fxq "$XDG_STATE_HOME/hcom-team/session:orphan" "$fixture_dir/trashed" || fail 'orphan team commands were not discarded'
grep -Fxq "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B" "$fixture_dir/trashed" || fail 'orphan task record was not discarded'
[[ "$(<"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B")" == $'fixture-origin-session\nwindow:new' ]] || fail 'orphan task did not save the new tab'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block call process -s session:orphan -b block:scout'* ]] || fail 'orphan scout pane was not checked before replacement'
grep -q '^window new -s fixture-origin-session ' "$HCOM_FIXTURE_REX_CALLS" || fail 'orphan team did not open a tab in the current session'
if grep -q '^session kill' "$HCOM_FIXTURE_REX_CALLS"; then
	fail 'orphan team closed its old session'
fi
unset HCOM_FIXTURE_REX_BLOCKS
# A successful worktree cleanup closes idle teammate panes and forgets the task's saved session.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:cleanup"},{"session_id":"session:busy"},{"session_id":"session:self"},{"session_id":"session:close-error"}]}'
export REX_SESSION=fixture-origin-session
export REX_BLOCK=block:orchestrator
mkdir -p "$XDG_STATE_HOME/hcom-team/tasks" "$XDG_STATE_HOME/hcom-team/session:cleanup"
print -r -- session:cleanup > "$XDG_STATE_HOME/hcom-team/tasks/tsk_cleanup"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup_output="$(cleanup tsk_cleanup)" || fail 'worktree cleanup with idle teammates'
[[ "$cleanup_output" == 'Worktree cleaned' && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block close block:implementer -s session:cleanup'*'block close block:reviewer -s session:cleanup'*'block close block:scout -s session:cleanup'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:orchestrator'* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_cleanup" && ! -e "$XDG_STATE_HOME/hcom-team/session:cleanup" ]] || fail 'idle teammate panes or saved session survived cleanup'

# A running teammate stays open with an explanation while the task state is forgotten.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:busy"
print -r -- session:busy > "$XDG_STATE_HOME/hcom-team/tasks/tsk_busy"
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup_output="$(cleanup tsk_busy 2>&1)" || fail 'worktree cleanup with running teammate'
[[ "$cleanup_output" == *'reviewer pane block:reviewer was left open because an agent is still running there.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block close block:implementer -s session:busy'*'block close block:scout -s session:busy'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:reviewer'* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_busy" && ! -e "$XDG_STATE_HOME/hcom-team/session:busy" ]] || fail 'running teammate pane was closed or not explained'
unset HCOM_FIXTURE_REX_BUSY_BLOCK

# Two teams in one session keep their panes and saved commands separate.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:shared"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:a-orchestrator","window_id":"window:a","label":"orchestrator"},{"block_id":"block:a-implementer","window_id":"window:a","label":"implementer"},{"block_id":"block:a-reviewer","window_id":"window:a","label":"reviewer"},{"block_id":"block:a-scout","window_id":"window:a","label":"scout"},{"block_id":"block:b-orchestrator","window_id":"window:b","label":"orchestrator"},{"block_id":"block:b-implementer","window_id":"window:b","label":"implementer"},{"block_id":"block:b-reviewer","window_id":"window:b","label":"reviewer"},{"block_id":"block:b-scout","window_id":"window:b","label":"scout"}]}'
mkdir -p "$XDG_STATE_HOME/hcom-team/session:shared/window:a" "$XDG_STATE_HOME/hcom-team/session:shared/window:b"
printf 'session:shared\nwindow:a\n' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_a"
printf 'session:shared\nwindow:b\n' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_b"
print -rn -- 'team:a-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/window:a/scout"
print -rn -- 'team:b-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout"
print -rn -- 'legacy-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/scout"
print -r -- session:shared > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy"
print -r -- session:shared > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy_copy"
: > "$HCOM_FIXTURE_REX_CALLS"
_hcom_team_forget_other_tasks_in_session session:shared window:b tsk_team_b || fail 'shared session task record check'
[[ -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_a" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy_copy" && "$(grep -c '^block ls -s session:shared --json$' "$HCOM_FIXTURE_REX_CALLS")" == 1 ]] || fail 'other team records changed or their panes were listed more than once'
trash "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy_copy" >/dev/null
export REX_SESSION=session:shared REX_BLOCK=block:a-orchestrator
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'reset in a shared session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s session:shared --json'*'send -s session:shared -b block:a-scout team:a-scout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block:b-scout'* ]] || fail 'reset reached another team in the shared session'
# A side tab uses the only team with panes in its session.
# Panes in both team tabs, reused by the side-tab checks.
shared_blocks="$HCOM_FIXTURE_REX_BLOCKS"
export HCOM_FIXTURE_REX_BLOCKS="$(jq -c '.blocks |= map(select(.window_id == "window:a")) | .blocks += [{"block_id":"block:side","window_id":"window:side","label":"shell"}]' <<<"$shared_blocks")"
export REX_BLOCK=block:side
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'reset from a side tab with one team'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s session:shared -b block:a-scout team:a-scout'* ]] || fail 'side-tab reset missed the only team'

# A failed lookup of the current tab stops before another team can be selected.
functions -c _hcom_team_blocks_in_window _hcom_team_blocks_in_window_real
_hcom_team_blocks_in_window() { return 1; }
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'side-tab reset continued after its tab lookup failed'
fi
functions[_hcom_team_blocks_in_window]="${functions[_hcom_team_blocks_in_window_real]}"
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'window ls '* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:shared '* ]] || fail 'failed side-tab lookup selected or reset another team'

# A side tab with several teams lists their tabs and refuses to guess without a terminal.
export HCOM_FIXTURE_REX_BLOCKS="$(jq -c '.blocks += [{"block_id":"block:side","window_id":"window:side","label":"shell"}]' <<<"$shared_blocks")"
export HCOM_FIXTURE_REX_WINDOWS='{"windows":[{"window_id":"window:a","label":"First team"},{"window_id":"window:b","label":""}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset scout < /dev/null > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'side-tab reset guessed between two teams without a terminal'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'1. First team'*'2. other-task'*'several teams share Rex session session:shared (First team, other-task); choose one from a terminal.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:shared '* ]] || fail "ambiguous side-tab reset did not name and preserve both teams: $(<"$fixture_dir/reset-error")"

# An answered choice resets only the selected team and leaves the other command intact.
functions -c _hcom_team_reset_selection _hcom_team_reset_selection_real
_hcom_team_reset_selection() { reply=(2); }
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error" || fail 'side-tab reset with a chosen team'
functions[_hcom_team_reset_selection]="${functions[_hcom_team_reset_selection_real]}"
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s session:shared -b block:b-scout team:b-scout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block:a-scout'* && "$(<"$XDG_STATE_HOME/hcom-team/session:shared/window:a/scout")" == team:a-scout ]] || fail 'side-tab choice reached another team or changed its command'

# A side tab with no team has nothing to reset.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:side","window_id":"window:side","label":"shell"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team-reset: no team in Rex session session:shared.' team-reset scout
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:shared '* ]] || fail 'reset typed into a session without a team'
export HCOM_FIXTURE_REX_BLOCKS="$shared_blocks" REX_BLOCK=block:a-orchestrator
unset HCOM_FIXTURE_REX_WINDOWS
trash "$XDG_STATE_HOME/hcom-team/session:shared/window:a" >/dev/null
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'older team reset after another tab joined its session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s session:shared -b block:a-scout legacy-scout'* ]] || fail 'older team did not use its shared launch command'

# A side tab can name and select an older team while another team has its own folder.
export HCOM_FIXTURE_REX_BLOCKS="$(jq -c '.blocks += [{"block_id":"block:side","window_id":"window:side","label":"shell"}]' <<<"$shared_blocks")" REX_BLOCK=block:side
export HCOM_FIXTURE_REX_WINDOWS='{"windows":[{"window_id":"window:a","label":""},{"window_id":"window:b","label":"Second team"}]}'
functions -c _hcom_team_reset_selection _hcom_team_reset_selection_real
_hcom_team_reset_selection() { reply=(2); }
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error" || fail 'older team selection from a side tab'
functions[_hcom_team_reset_selection]="${functions[_hcom_team_reset_selection_real]}"
[[ "$(<"$fixture_dir/reset-error")" == *'older-task'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s session:shared -b block:a-scout legacy-scout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:shared -b block:b-scout '* ]] || fail 'side-tab choice did not use the older team name and command'
export HCOM_FIXTURE_REX_BLOCKS="$shared_blocks" REX_BLOCK=block:a-orchestrator
unset HCOM_FIXTURE_REX_WINDOWS

mkdir -p "$XDG_STATE_HOME/hcom-team/session:shared/window:a"
print -rn -- 'team:a-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/window:a/scout"
export REX_BLOCK=block:b-orchestrator
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'reset from the second team in a shared session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s session:shared -b block:b-scout team:b-scout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block:a-scout'* ]] || fail 'reset from the second team reached the first team'
trash "$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout" >/dev/null
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team-reset: no saved launch command for scout in Rex session session:shared.' team-reset scout
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s session:shared -b block:b-scout '* ]] || fail 'reset used another team command from the shared folder'
export REX_BLOCK=block:a-orchestrator

# Two tabs without saved folders cannot be assigned to an older team during cleanup.
mv "$XDG_STATE_HOME/hcom-team/session:shared/window:a" "$fixture_dir/ambiguous-older-window-a"
mv "$XDG_STATE_HOME/hcom-team/session:shared/window:b" "$fixture_dir/ambiguous-older-window-b"
: > "$HCOM_FIXTURE_REX_CALLS"
if cleanup tsk_legacy > "$fixture_dir/cleanup-output" 2> "$fixture_dir/cleanup-error"; then
	fail 'cleanup guessed which tab held an older team'
fi
[[ "$(<"$fixture_dir/cleanup-error")" == *"cannot tell which tab holds this task's team in Rex session session:shared; its saved state was kept."* && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy" && -f "$XDG_STATE_HOME/hcom-team/session:shared/scout" && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close '* ]] || fail 'ambiguous older-team cleanup lost its saved state or closed a pane'
mv "$fixture_dir/ambiguous-older-window-a" "$XDG_STATE_HOME/hcom-team/session:shared/window:a"
mv "$fixture_dir/ambiguous-older-window-b" "$XDG_STATE_HOME/hcom-team/session:shared/window:b"
print -rn -- 'team:b-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout"

: > "$HCOM_FIXTURE_REX_CALLS"
cleanup_output="$(cleanup tsk_legacy 2>&1)" || fail 'cleanup with an unknown tab in a shared session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close '* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy" && ! -e "$XDG_STATE_HOME/hcom-team/session:shared/scout" && -d "$XDG_STATE_HOME/hcom-team/session:shared/window:a" && -d "$XDG_STATE_HOME/hcom-team/session:shared/window:b" ]] || fail 'cleanup touched a saved team tab while forgetting an older task'
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_team_a >/dev/null || fail 'cleanup in a shared session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s session:shared --json'*'block close block:a-implementer -s session:shared'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:b-'* && ! -e "$XDG_STATE_HOME/hcom-team/session:shared/window:a" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_b" && -d "$XDG_STATE_HOME/hcom-team/session:shared/window:b" ]] || fail 'cleanup touched another team in the shared session'

# An older team's closed tab cannot adopt the remaining team's tab.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:b-orchestrator","window_id":"window:b","label":"orchestrator"},{"block_id":"block:b-implementer","window_id":"window:b","label":"implementer"},{"block_id":"block:b-reviewer","window_id":"window:b","label":"reviewer"},{"block_id":"block:b-scout","window_id":"window:b","label":"scout"}]}'
print -rn -- 'team:b-scout' > "$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout"
print -r -- session:shared > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_legacy >/dev/null || fail 'cleanup of an older team whose tab closed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:b-'* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_b" && "$(<"$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout")" == team:b-scout ]] || fail 'older team cleanup touched the remaining team'
print -r -- session:shared > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:shared 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_legacy || fail 'relaunch of an older team whose tab closed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:shared Fixture task -c '*'--focus=false --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block call process -s session:shared -b block:b-'* && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_b" && "$(<"$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout")" == team:b-scout ]] || fail 'older team relaunch adopted the remaining team'

# An older team's cleanup leaves a newer team's idle panes when the newer team's orchestrator pane has closed.
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:b-implementer","window_id":"window:b","label":"implementer"},{"block_id":"block:b-reviewer","window_id":"window:b","label":"reviewer"},{"block_id":"block:b-scout","window_id":"window:b","label":"scout"}]}'
print -r -- session:shared > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_legacy >/dev/null || fail 'cleanup after a newer orchestrator pane closed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:b-'* && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_team_b" && -f "$XDG_STATE_HOME/hcom-team/session:shared/window:b/scout" ]] || fail 'older team cleanup closed newer team panes'

# One orchestrator pane with no tab ID counts as one team, even when the session has no saved folder.
_hcom_team_older_tab session:no-folder '{"blocks":[{"block_id":"block:only","label":"orchestrator"}]}' || fail 'older tab lookup without a tab ID'
(( ${#reply} == 2 && reply[2] == 1 )) || fail 'one orchestrator pane with no tab ID was counted as several teams'

# A saved tab can close while its Rex session and other team tabs stay open.
printf 'session:shared\nwindow:gone\n' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_closed_tab"
mkdir -p "$XDG_STATE_HOME/hcom-team/session:shared/window:gone"
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:shared 2 1 2 codex codex codex orchestrator:codex '' 1 codex tsk_closed_tab || fail 'relaunch after a saved tab closed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:shared Fixture task -c '*'--focus=false --json'* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_closed_tab" && ! -e "$XDG_STATE_HOME/hcom-team/session:shared/window:gone" ]] || fail 'closed saved tab blocked relaunch or kept its state'
printf 'session:shared\nwindow:gone\n' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_closed_tab"
mkdir -p "$XDG_STATE_HOME/hcom-team/session:shared/window:gone"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_closed_tab >/dev/null || fail 'cleanup after a saved tab closed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close '* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_closed_tab" && ! -e "$XDG_STATE_HOME/hcom-team/session:shared/window:gone" ]] || fail 'cleanup touched another team after its saved tab closed'

# An older one-team session removes its shared commands after its tab is found.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:legacy"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:legacy-orchestrator","window_id":"window:legacy","label":"orchestrator"},{"block_id":"block:legacy-scout","window_id":"window:legacy","label":"scout"}]}'
mkdir -p "$XDG_STATE_HOME/hcom-team/session:legacy"
print -rn -- 'legacy-scout' > "$XDG_STATE_HOME/hcom-team/session:legacy/scout"
print -r -- session:legacy > "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy_single"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_legacy_single >/dev/null || fail 'cleanup of an older team with a known tab'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block close block:legacy-scout -s session:legacy'* && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_legacy_single" && ! -e "$XDG_STATE_HOME/hcom-team/session:legacy/scout" ]] || fail 'older team shared commands survived cleanup'

# Forgetting the last team removes its now empty session folder.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:empty/window:only"
print -r -- 'session:empty' > "$XDG_STATE_HOME/hcom-team/tasks/tsk_empty"
_hcom_team_forget_session tsk_empty session:empty window:only || fail 'forgetting the last team'
[[ ! -e "$XDG_STATE_HOME/hcom-team/session:empty" ]] || fail 'the empty session folder survived forgetting its last team'
unset HCOM_FIXTURE_REX_BLOCKS
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:cleanup"},{"session_id":"session:busy"},{"session_id":"session:self"},{"session_id":"session:close-error"}]}'
export REX_SESSION=fixture-origin-session REX_BLOCK=block:orchestrator

# Cleanup never closes its own pane, even when it has a teammate label.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:self"
print -r -- session:self > "$XDG_STATE_HOME/hcom-team/tasks/tsk_self"
export REX_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_self >/dev/null || fail 'worktree cleanup from a teammate pane'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'block close block:reviewer'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block close block:implementer -s session:self'*'block close block:scout -s session:self'* ]] || fail 'cleanup closed its own pane'
export REX_BLOCK=block:orchestrator

# A successful cleanup that keeps the checkout leaves the panes and saved state alone.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:kept"
mkdir -p "$fixture_dir/tsk_kept"
print -r -- session:kept > "$XDG_STATE_HOME/hcom-team/tasks/tsk_kept"
print -r -- "$fixture_dir/tsk_kept" > "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_kept"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_kept >/dev/null || fail 'worktree cleanup that kept its checkout'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_kept" && -d "$XDG_STATE_HOME/hcom-team/session:kept" ]] || fail 'kept checkout changed Rex panes or saved state'

# A saved session that has closed is forgotten without trying to inspect its panes.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:missing"
print -r -- session:missing > "$XDG_STATE_HOME/hcom-team/tasks/tsk_missing"
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_missing >/dev/null || fail 'worktree cleanup with a closed session'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == 'ls --json' && ! -e "$XDG_STATE_HOME/hcom-team/tasks/tsk_missing" && ! -e "$XDG_STATE_HOME/hcom-team/session:missing" ]] || fail 'closed Rex session kept its saved state or inspected panes'

# A pane that Rex cannot close is reported while cleanup continues with other panes.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:close-error"
print -r -- session:close-error > "$XDG_STATE_HOME/hcom-team/tasks/tsk_close_error"
export HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup_output="$(cleanup tsk_close_error 2>&1)" || fail 'worktree cleanup with a pane close failure'
[[ "$cleanup_output" == *'reviewer pane block:reviewer could not be closed.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block close block:reviewer -s session:close-error'*'block close block:scout -s session:close-error'* ]] || fail 'pane close failure stopped cleanup or hid the error'
unset HCOM_FIXTURE_REX_CLOSE_ERROR_BLOCK

# Help output never changes Rex panes or saved state.
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_kept --help >/dev/null || fail 'worktree cleanup help'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_kept" ]] || fail 'worktree cleanup help changed Rex state'

# Outside Rex and without a saved session, worktree cleanup still runs alone.
mkdir -p "$XDG_STATE_HOME/hcom-team/session:outside"
print -r -- session:outside > "$XDG_STATE_HOME/hcom-team/tasks/tsk_outside"
unset REX_SESSION
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_outside >/dev/null || fail 'worktree cleanup outside Rex'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_outside" ]] || fail 'cleanup changed a Rex team outside Rex'
export REX_SESSION=fixture-origin-session
: > "$HCOM_FIXTURE_REX_CALLS"
cleanup tsk_without_session >/dev/null || fail 'worktree cleanup without a saved session'
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'cleanup inspected Rex without a saved session'

# A failed worktree cleanup leaves every pane and saved file untouched.
export HCOM_FIXTURE_CLEANUP_FAIL=1
: > "$HCOM_FIXTURE_REX_CALLS"
if cleanup tsk_outside >/dev/null; then
	fail 'failed worktree cleanup reported success'
fi
[[ ! -s "$HCOM_FIXTURE_REX_CALLS" && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_outside" && -d "$XDG_STATE_HOME/hcom-team/session:outside" ]] || fail 'failed worktree cleanup touched Rex state'
unset HCOM_FIXTURE_CLEANUP_FAIL
[[ "$(<"$HCOM_FIXTURE_CLEANUP_CALLS")" == *'worktree cleanup tsk_cleanup'*'worktree cleanup tsk_busy'*'worktree cleanup tsk_self'*'worktree cleanup tsk_outside'*'worktree cleanup tsk_without_session'* ]] || fail 'cleanup did not pass task IDs to Progress'

unfunction trash
unset HCOM_FIXTURE_REX_SESSIONS

# Forced teams save the account selected by the launching shell.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:old-root","label":"Fixture"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
CLAUDE_CONFIG_DIR="$HOME/.claude-2" HCOM_ACCOUNT=2 HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:claude reviewer implementer:claude scout:claude "$fixture_dir/project" '' '' '' '' '' claude claude claude orchestrator:claude '' '' claude '' forced || fail 'forced Rex team session creation'
[[ "$(<"$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/scout")" == '# hcom-team-role-v2 claude forced 2'$'\n'*'scout:claude '*$'\n'*'scout '* ]] || fail 'Claude team did not save its account and both scout commands'

# Root teams use the repository session when one is already open.
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'root Rex session creation'
[[ "${reply[2]}" == session:old-root && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'window new -s session:old-root Team -c '*'--focus=false --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session kill'* ]] || fail 'root team did not reuse the repository session'
reviewer_saved="$(<"$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/reviewer")"
implementer_saved="$(<"$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/implementer")"
scout_saved="$(<"$XDG_STATE_HOME/hcom-team/${reply[2]}/${reply[3]}/scout")"
[[ "$reviewer_saved" == *$'\n'*'reviewer:codex '*$'\n'*'reviewer '* ]] || fail 'Codex team did not save both reviewer commands'
[[ "$implementer_saved" == *$'\n'*'implementer '*$'\n'*'implementer:claude '* ]] || fail 'Codex team did not save both implementer commands'
[[ "$scout_saved" == *$'\n'*'scout '*$'\n'*'scout:claude '* ]] || fail 'Codex team did not save both scout commands'
unset HCOM_FIXTURE_REX_SESSIONS

[[ "$(_hcom_team_other_launcher reviewer claude)" == reviewer:codex && "$(_hcom_team_other_launcher reviewer codex)" == reviewer && "$(_hcom_team_other_launcher implementer claude)" == implementer && "$(_hcom_team_other_launcher implementer codex)" == implementer:claude && "$(_hcom_team_other_launcher scout claude)" == scout && "$(_hcom_team_other_launcher scout codex)" == scout:claude ]] || fail 'alternate launchers do not cover every teammate agent pair'

mkdir -p "$XDG_STATE_HOME/hcom-team/fixture-origin-session"
# Reset quotas are mocked so these checks never inspect a real account.
functions -c _hcom_quota_probe _hcom_quota_probe_before_reset
# Prints the fixture's two account lines, or fails when a test asks for a failed
# usage check.
#
# @param  {string}  provider
#     The agent being checked, recorded so tests can confirm whether a check ran.
_hcom_quota_probe() {
	print -r -- "$1" >> "$fixture_dir/reset-quota-calls"
	[[ "${HCOM_FIXTURE_RESET_PROBE_FAIL:-0}" != 1 ]] || return 1
	[[ "${HCOM_FIXTURE_RESET_FAIL_PROVIDER:-}" != "$1" ]] || return 1
	if [[ "$1" == claude && -n "${HCOM_FIXTURE_RESET_CLAUDE_DEFAULT:-}" ]]; then
		print -r -- "$HCOM_FIXTURE_RESET_CLAUDE_DEFAULT"
		print -r -- "$HCOM_FIXTURE_RESET_CLAUDE_SECOND"
		return 0
	fi
	print -r -- "${HCOM_FIXTURE_RESET_DEFAULT:-90 9999999999 18000 90 9999999999 604800}"
	print -r -- "${HCOM_FIXTURE_RESET_SECOND:-90 9999999999 18000 90 9999999999 604800}"
}
_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' codex auto 2 || fail 'auto-allocated reset command save'
: > "$HCOM_FIXTURE_REX_CALLS"
CODEX_HOME="$fixture_dir/caller-account" HCOM_TEAM_LABEL=caller HCOM_TEAM_PROJECT_TAG=Caller team-reset scout >/dev/null || fail 'auto-allocated scout reset failed'
[[ "$(<"$fixture_dir/reset-quota-calls")" == codex && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout CODEX_HOME='*'/.codex-2 HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'caller-account'* ]] || fail 'reset changed a usable saved account or used the caller scope'

_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' codex auto default || fail 'default-account reset command save'
: > "$HCOM_FIXTURE_REX_CALLS"
CODEX_HOME="$fixture_dir/caller-account" team-reset scout >/dev/null || fail 'default-account scout reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout HCOM_ACCOUNT=default HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'caller-account'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s fixture-origin-session -b block:scout CODEX_HOME='* ]] || fail 'default-account reset used the caller account'

_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' codex auto 2 || fail 'low-account reset command save'
HCOM_FIXTURE_RESET_SECOND='4 9999999999 18000 90 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" || fail 'low saved account reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout HCOM_ACCOUNT=default HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout'* && "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on the default account.' ]] || fail 'reset did not report the switch from a low saved account'
[[ "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout")" == '# hcom-team-role-v2 codex auto default'$'\n'* ]] || fail 'switched account was not saved'
unset HCOM_FIXTURE_RESET_SECOND
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'second reset after account switch failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout HCOM_ACCOUNT=default HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout'* ]] || fail 'second reset moved back to the recovered old account'

# A failed save still reports the restarted teammate and leaves its old account in the saved header.
functions -c _hcom_team_save_role _hcom_team_save_role_before_failed_reset
# Refuses to save one role during a reset, while other roles use the real saver.
#
# @param  {string}  session_id
#     Rex session that contains the role's pane.
# @param  {string}  window_id
#     Tab containing the role's pane, when known.
# @param  {string}  role
#     Role whose saved command is being written.
# @param  {string}  ...
#     The remaining saved command details.
_hcom_team_save_role() {
	if [[ "$3" == "$HCOM_FIXTURE_RESET_SAVE_FAIL_ROLE" ]]; then
		return 1
	fi
	_hcom_team_save_role_before_failed_reset "$@"
}
_hcom_team_save_role_before_failed_reset fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto default || fail 'failed second-account save fixture'
HCOM_FIXTURE_RESET_SAVE_FAIL_ROLE=scout
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'reset reported success after the switched account could not be saved'
fi
[[ "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on account 2.' && "$(<"$fixture_dir/reset-error")" == *'could not save account 2 for scout, so the next reset checks the default account first.'* && "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout")" == '# hcom-team-role-v2 codex auto default'$'\n'* ]] || fail 'failed save did not report the restart and keep the default account'

_hcom_team_save_role_before_failed_reset fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto 2 || fail 'failed default-account save fixture'
unset HCOM_FIXTURE_RESET_DEFAULT
HCOM_FIXTURE_RESET_SECOND='4 9999999999 18000 90 9999999999 604800'
if team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'reset reported success after the default account could not be saved'
fi
[[ "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on the default account.' && "$(<"$fixture_dir/reset-error")" == *'could not save the default account for scout, so the next reset checks account 2 first.'* && "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout")" == '# hcom-team-role-v2 codex auto 2'$'\n'* ]] || fail 'failed save did not name the default account or changed the saved header'

_hcom_team_save_role_before_failed_reset fixture-origin-session '' reviewer 'HCOM_TEAM_LABEL=saved reviewer /saved/checkout' claude auto default || fail 'all-peer failed-save fixture'
_hcom_team_save_role_before_failed_reset fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto default || fail 'all-peer scout fixture'
HCOM_FIXTURE_RESET_SAVE_FAIL_ROLE=reviewer
unset HCOM_FIXTURE_RESET_SECOND
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset all > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'all-peer reset reported success after a switched account could not be saved'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'could not save account 2 for reviewer, so the next reset checks the default account first.'* && "$(<"$fixture_dir/reset-output")" == *'team-reset: restarted scout on account 2.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout '* ]] || fail 'all-peer reset stopped after a failed save'
unset HCOM_FIXTURE_RESET_DEFAULT HCOM_FIXTURE_RESET_SAVE_FAIL_ROLE
functions[_hcom_team_save_role]="${functions[_hcom_team_save_role_before_failed_reset]}"

# A low default account moves to account 2 and saves that choice.
_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto default || fail 'default-to-second reset command save'
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" || fail 'default-to-second reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout CODEX_HOME='*'/.codex-2 HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved scout /saved/checkout'* && "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on account 2.' && "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout")" == '# hcom-team-role-v2 codex auto 2'$'\n'* ]] || fail 'default-to-second reset did not report and save account 2'
unset HCOM_FIXTURE_RESET_DEFAULT

# Claude teammates use the same reset account rule.
_hcom_team_save_role fixture-origin-session '' reviewer 'HCOM_TEAM_LABEL=saved reviewer /saved/checkout' claude auto default || fail 'Claude reset command save'
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset reviewer >/dev/null || fail 'Claude reviewer reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:reviewer CLAUDE_CONFIG_DIR='*'/.claude-2 HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved reviewer /saved/checkout'* && "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/reviewer")" == '# hcom-team-role-v2 claude auto 2'$'\n'* ]] || fail 'Claude reviewer did not switch accounts'
unset HCOM_FIXTURE_RESET_DEFAULT

_hcom_team_save_role fixture-origin-session '' scout 'CODEX_HOME=/forced/account HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' codex forced 2 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout:claude /saved/checkout' || fail 'forced-account reset command save'
: > "$HCOM_FIXTURE_REX_CALLS"
: > "$fixture_dir/reset-quota-calls"
team-reset scout >/dev/null || fail 'forced-account scout reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout CODEX_HOME=/forced/account HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout'* && ! -s "$fixture_dir/reset-quota-calls" ]] || fail 'forced-account reset changed the saved account or probed quota'

_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto default || fail 'exhausted reset command save'
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
HCOM_FIXTURE_RESET_SECOND='90 9999999999 18000 4 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'reset stopped a teammate when both accounts were exhausted'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'under 5% usage left on both accounts'*'Restart the team'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key -s fixture-origin-session -b block:scout ctrl+c'* ]] || fail 'exhausted reset touched the running teammate'

# A new team can move its scout to the other agent's account with more usage left.
_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' codex auto default 'HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout:claude /saved/checkout' || fail 'cross-agent scout save'
HCOM_FIXTURE_RESET_CLAUDE_DEFAULT='40 9999999999 18000 40 9999999999 604800'
HCOM_FIXTURE_RESET_CLAUDE_SECOND='70 9999999999 18000 70 9999999999 604800'
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" || fail 'cross-agent scout reset'
[[ "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on Claude, account 2.' && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'CLAUDE_CONFIG_DIR='*'/.claude-2 HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout:claude /saved/checkout'* && "$(<"$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout")" == '# hcom-team-role-v2 claude auto 2'$'\n''HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout:claude /saved/checkout'$'\n''HCOM_TEAM_LABEL=saved HCOM_TEAM_PROJECT_TAG=Saved scout /saved/checkout' ]] || fail 'cross-agent reset did not use Claude and save both commands'

# The saved agent is checked first on the next reset, even if the old agent recovers.
unset HCOM_FIXTURE_RESET_DEFAULT HCOM_FIXTURE_RESET_SECOND
: > "$fixture_dir/reset-quota-calls"
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'reset after cross-agent move'
[[ "$(<"$fixture_dir/reset-quota-calls")" == claude && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'scout:claude /saved/checkout'* ]] || fail 'reset returned to the old agent before the new agent ran out'

# All four spent accounts leave the running pane untouched.
HCOM_FIXTURE_RESET_DEFAULT='4 9999999999 18000 90 9999999999 604800'
HCOM_FIXTURE_RESET_SECOND='90 9999999999 18000 4 9999999999 604800'
HCOM_FIXTURE_RESET_CLAUDE_DEFAULT="$HCOM_FIXTURE_RESET_DEFAULT"
HCOM_FIXTURE_RESET_CLAUDE_SECOND="$HCOM_FIXTURE_RESET_SECOND"
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'reset moved a teammate with all four accounts spent'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'all four accounts'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key -s fixture-origin-session -b block:scout ctrl+c'* ]] || fail 'all-account refusal touched the running scout'

# Unreadable usage on the other agent chooses its first account and warns.
_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto default 'HCOM_TEAM_LABEL=saved scout:claude /saved/checkout' || fail 'unreadable-other-agent fixture'
HCOM_FIXTURE_RESET_FAIL_PROVIDER=claude
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error" || fail 'unreadable-other-agent reset'
[[ "$(<"$fixture_dir/reset-error")" == *"could not check Claude usage; moving scout to that agent's default account."* && "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout on Claude, the default account.' && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'HCOM_ACCOUNT=default HCOM_TEAM_LABEL=saved scout:claude /saved/checkout'* ]] || fail 'unreadable-other-agent fallback did not move and warn'
unset HCOM_FIXTURE_RESET_FAIL_PROVIDER HCOM_FIXTURE_RESET_CLAUDE_DEFAULT HCOM_FIXTURE_RESET_CLAUDE_SECOND

# A Claude-only teammate can move to Codex when Claude's accounts are spent.
_hcom_team_save_role fixture-origin-session '' reviewer 'HCOM_TEAM_LABEL=saved reviewer /saved/checkout' claude auto default 'HCOM_TEAM_LABEL=saved reviewer:codex /saved/checkout' || fail 'Claude-only reviewer fixture'
HCOM_FIXTURE_RESET_CLAUDE_DEFAULT="$HCOM_FIXTURE_RESET_DEFAULT"
HCOM_FIXTURE_RESET_CLAUDE_SECOND="$HCOM_FIXTURE_RESET_SECOND"
unset HCOM_FIXTURE_RESET_DEFAULT HCOM_FIXTURE_RESET_SECOND
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset reviewer > "$fixture_dir/reset-output" || fail 'Claude-only reviewer reset'
[[ "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted reviewer on Codex, the default account.' && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'HCOM_ACCOUNT=default HCOM_TEAM_LABEL=saved reviewer:codex /saved/checkout'* ]] || fail 'Claude-only reviewer did not move to Codex'
unset HCOM_FIXTURE_RESET_CLAUDE_DEFAULT HCOM_FIXTURE_RESET_CLAUDE_SECOND

unset HCOM_FIXTURE_RESET_DEFAULT HCOM_FIXTURE_RESET_SECOND
_hcom_team_save_role fixture-origin-session '' scout 'HCOM_TEAM_LABEL=saved scout /saved/checkout' codex auto 2 || fail 'probe-failure reset command save'
HCOM_FIXTURE_RESET_PROBE_FAIL=1
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error" || fail 'quota-probe fallback reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'send -s fixture-origin-session -b block:scout CODEX_HOME='*'/.codex-2 HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=saved scout /saved/checkout'* && "$(<"$fixture_dir/reset-error")" == 'team-reset: could not check Codex usage; kept account 2.' ]] || fail 'quota-probe failure did not warn and keep the saved account'
unset HCOM_FIXTURE_RESET_PROBE_FAIL

# A header with no command is rejected before the running teammate is stopped.
print -rn -- '# hcom-team-role-v2 codex auto 2' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout"
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team-reset: invalid saved launch command for scout in Rex session fixture-origin-session.' team-reset scout
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key -s fixture-origin-session -b block:scout ctrl+c'* ]] || fail 'header-only command stopped the teammate'
functions[_hcom_quota_probe]="${functions[_hcom_quota_probe_before_reset]}"

print -rn -- 'HCOM_ACCOUNT=scout-agent team:scout' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout"
print -rn -- 'HCOM_ACCOUNT=implementer-agent team:implementer' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/implementer"
print -rn -- 'HCOM_ACCOUNT=reviewer-agent team:reviewer' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/reviewer"
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'scout reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s fixture-origin-session --json'*'send-key -s fixture-origin-session -b block:scout ctrl+c ctrl+c'*'block call process -s fixture-origin-session -b block:scout'*'send -s fixture-origin-session -b block:scout HCOM_ACCOUNT=scout-agent team:scout'*'send-key -s fixture-origin-session -b block:scout enter'* ]] || fail 'scout reset did not stop, check and replay its saved command'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s fixture-origin-session -b block:scout clear'* ]] || fail 'scout reset cleared its pane'

# Claude's shell has the public command but no private helpers. team-reset retries once in a full zsh that loads them.
mkdir -p "$fixture_dir/zdotdir"
cat > "$fixture_dir/zdotdir/.zshrc" <<'STUB'
source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-core.zsh"
source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-workflow.zsh"
source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-team.zsh"
STUB
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_FIXTURE_REPO_ROOT="$repo_root" ZDOTDIR="$fixture_dir/zdotdir" zsh -c 'source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-team.zsh"; unfunction _hcom_team_reset_role; team-reset scout' > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error" || fail 'reset did not reload missing helpers'
[[ "$(<"$fixture_dir/reset-output")" == 'team-reset: restarted scout.' && ! -s "$fixture_dir/reset-error" && "$(grep -c '^block ls -s fixture-origin-session --json$' "$HCOM_FIXTURE_REX_CALLS")" == 1 ]] || fail 'missing-helper reset did not restart scout exactly once'

# A retried reset still refuses a busy pane and passes on its failure.
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:scout
: > "$HCOM_FIXTURE_REX_CALLS"
if HCOM_FIXTURE_REPO_ROOT="$repo_root" ZDOTDIR="$fixture_dir/zdotdir" zsh -c 'source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-team.zsh"; unfunction _hcom_team_reset_role; team-reset scout' > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'missing-helper reset lost the inner failure status'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'peer pane block:scout did not return to a shell prompt.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s fixture-origin-session -b block:scout '* ]] || fail 'missing-helper reset typed into a busy pane'
unset HCOM_FIXTURE_REX_BUSY_BLOCK

# A shell that is already the retry fails instead of retrying again.
: > "$HCOM_FIXTURE_REX_CALLS"
if HCOM_TEAM_RESET_RETRIED=1 HCOM_FIXTURE_REPO_ROOT="$repo_root" ZDOTDIR="$fixture_dir/zdotdir" zsh -c 'source "$HCOM_FIXTURE_REPO_ROOT/aliases.hcom-team.zsh"; unfunction _hcom_team_reset_role; team-reset scout' > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'reset retried after the full shell lacked its helpers'
fi
[[ "$(<"$fixture_dir/reset-error")" == 'team-reset: a full interactive zsh did not load the team helpers.' && ! -s "$HCOM_FIXTURE_REX_CALLS" ]] || fail 'missing helpers caused a second retry'

: > "$HCOM_FIXTURE_REX_CALLS"
team-reset all >/dev/null || fail 'all-peer reset failed'
[[ "$(grep -c '^send-key .* ctrl+c ctrl+c$' "$HCOM_FIXTURE_REX_CALLS")" == 3 && "$(grep -c '^send-key .* enter$' "$HCOM_FIXTURE_REX_CALLS")" == 3 ]] || fail 'all-peer reset did not restart every teammate'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *' clear'* ]] || fail 'all-peer reset cleared a pane'

unset REX_SESSION
assert_command_error 'team-reset: open the team in Rex before resetting a teammate.' team-reset scout
export REX_SESSION=fixture-origin-session
assert_command_error 'team-reset: usage: team-reset scout|implementer|reviewer|all' team-reset orchestrator
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:orchestrator","label":"orchestrator"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team-reset: no scout pane in Rex session fixture-origin-session.' team-reset scout
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key '* ]] || fail 'missing scout pane received stop keys'
unset HCOM_FIXTURE_REX_BLOCKS
trash "$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout" >/dev/null
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team-reset: no saved launch command for scout in Rex session fixture-origin-session.' team-reset scout
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send-key '* ]] || fail 'missing saved launch command received stop keys'
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:reviewer
: > "$HCOM_FIXTURE_REX_CALLS"
if team-reset all > "$fixture_dir/reset-output" 2> "$fixture_dir/reset-error"; then
	fail 'all-peer reset succeeded despite a busy reviewer'
fi
[[ "$(<"$fixture_dir/reset-error")" == *'peer pane block:reviewer did not return to a shell prompt.'* && "$(<"$fixture_dir/reset-output")" == *'restarted implementer.'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s fixture-origin-session -b block:reviewer '* ]] || fail 'all-peer reset typed into a busy pane or stopped early'
unset HCOM_FIXTURE_REX_BUSY_BLOCK

print -r -- 'PASS: task address, checkout selection, quick tasks, quick-team completion, refusal before panes, relaunch isolation, stop targeting, solo quota selection, learner team labels, planning duplicates and team labels, Rex pane creation, and team reset'
