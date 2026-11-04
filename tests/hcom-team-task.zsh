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

# Skips every real wait in the suite, such as the retries while a busy pane is checked.
#
# @param  {number}  seconds
#     The delay the code under test asked for; ignored.
sleep() { :; }

# Supplies task records and active-task IDs without consulting the real project.
cat > "$fixture_dir/bin/progress" <<'STUB'
#!/usr/bin/env zsh
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
[[ "$1" == -C && "$3" == status && ( "$4" == --short || "$4" == --porcelain ) ]] || exit 1
print -r -- "$2 $4" >> "$HCOM_FIXTURE_GIT_CALLS"
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

# Records every rex call and answers the session list, new session and pane splits with fixture IDs.
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
	new) print -r -- "{\"session_id\":\"${HCOM_FIXTURE_REX_NEW_SESSION_ID:-session:fixture}\",\"initial_windows\":[{\"block_ids\":[\"block:orchestrator\"]}]}" ;;
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
		esac
		;;
	split)
		[[ "${HCOM_FIXTURE_REX_SPLIT_FAIL:-0}" == 1 ]] && exit 1
		case "$*" in
			*'--label implementer'*) print -r -- '{"block_ids":["block:implementer"]}' ;;
			*'--label reviewer'*) print -r -- '{"block_ids":["block:reviewer"]}' ;;
			*'--label scout'*) print -r -- '{"block_ids":["block:scout"]}' ;;
		esac
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
export XDG_STATE_HOME="$fixture_dir/state"
export HCOM_FIXTURE_GIT_DIRTY=0
export ZSH_CONFIG_ROOT="$repo_root"
export REX_SESSION=fixture-origin-session
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

source "$repo_root/aliases.hcom-core.zsh"
source "$repo_root/aliases.hcom-workflow.zsh"
source "$repo_root/aliases.hcom-team.zsh"
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
assert_command_error 'team: usage: team [continue|handover|handoff] [--task <id>] [--dir <path>] [--message <text> | --clipboard] [--team <label>] [--yes]' _hcom_parse_team_args team extra
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
assert_command_error 'team: --clipboard and --message cannot be used together.' _hcom_parse_team_args team --clipboard --message 'another note'
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
[[ "$plain_prompt" == 'Use the `project-continue` skill to retrieve the current progress records and continue with the next ready work.' ]] || fail 'plain continue prompt changed'
plain_ready_prompt="$(_hcom_team_continuation_prompt team continue 1)"  # Prompt used by a ready default task.
[[ "$plain_ready_prompt" == *'Start the selected task. If it has no chunks, plan them with the `project-plan-task` skill.'* ]] || fail 'plain ready prompt changed'
# Prompt for a ready task chosen by ID.
named_prompt="$(_hcom_team_continuation_prompt team continue 1 '' tsk_A_B "$fixture_dir/project")" || fail 'named ready prompt builds'
[[ "$named_prompt" == 'Continue task tsk_A_B with the `project-continue` skill, not the `progress next` result.

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
	reply=("$resolved_tags" "session:new")
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
[[ ! -s "$HCOM_FIXTURE_CONTEXT_CALLS" && "$launched_orchestrator_prompt" != *'progress context get --task tsk_A_B --json'* ]] || fail 'ready task launch read a leftover handoff'
unset HCOM_FIXTURE_HAS_HANDOFF
[[ -z "$stopped_team_tags" && -z "$replaced_session_id" && "$launched_task_id" == tsk_A_B && "$(<"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B")" == session:new && -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]] || fail 'task launch replaced another team or lost its stored session ID'
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
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_A_B with '* ]] || fail 'ready task did not use the continue prompt'

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
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_quick with '* && "$launched_orchestrator_prompt" != *'progress task start'* ]] || fail 'existing quick task skipped the normal prompt'

# A ready quick task from an earlier launch gets the normal start prompt.
export HCOM_FIXTURE_QUICK_STATE=ready
: > "$HCOM_FIXTURE_QUICK_CALLS"
_hcom_launch_team team:codex unused unused unused unused --team blue || fail 'ready quick task reuse'
[[ "$(<"$HCOM_FIXTURE_QUICK_CALLS")" == 'task list --all' && "$launched_task_id" == tsk_quick ]] || fail 'ready quick task was added again'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_quick with '*$'Your command to start the task is:\nprogress task start tsk_quick --secondary'* ]] || fail 'ready quick task skipped the normal start prompt'

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
[[ "$pane_calls" == $((prior_pane_calls + 1)) && "$launched_task_id" == tsk_A-B && "$launched_orchestrator_prompt" == *'Continue task tsk_A-B with '* ]] || fail 'picker choice missed the named ready-task launch path'
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
[[ "$launched_orchestrator_prompt" == *'progress context get --task tsk_a_B --json'* ]] || fail 'named in-progress task did not use the resume prompt'
# The public cont command launches the task it is given, under that task's team label.
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
prior_pane_calls="$pane_calls"
cont tsk_a_B --yes || fail 'public cont task ID did not launch'
[[ "$pane_calls" == $((prior_pane_calls + 1)) && "$launched_task_id" == tsk_a_B && "$launched_team_tags" == *'-another-task-orchestrator|'* ]] || fail 'public cont task ID selected the wrong task or team label'
[[ "$launched_orchestrator_prompt" == *'progress context get --task tsk_a_B --json'* ]] || fail 'public cont task ID lost the selected task handoff'
cont tsk_a_B </dev/null &> "$fixture_dir/cont-task-output" || fail 'public cont task ID without --yes did not launch'
[[ "$(<"$fixture_dir/cont-task-output")" != *'Start this task?'* ]] || fail 'public cont task ID without --yes showed a confirmation'
# A blocked task can resume only when a saved handoff exists.
print -r -- "$fixture_dir/tsk_a_B" > "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_blocked"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_blocked --yes || fail 'blocked task with a handoff did not resume'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'blocked task ignored its recorded checkout'
[[ "$launched_orchestrator_prompt" == *'progress context get --task tsk_blocked --json'* ]] || fail 'blocked task did not use the resume prompt'
unset HCOM_FIXTURE_HAS_HANDOFF
prior_pane_calls="$pane_calls"
assert_command_error 'team:codex: blocked task tsk_blocked has no saved handoff to resume.' _hcom_launch_team team:codex unused unused unused unused continue --task tsk_blocked --yes
[[ "$pane_calls" == "$prior_pane_calls" ]] || fail 'blocked task without a handoff reached pane creation'
export HCOM_FIXTURE_HAS_HANDOFF=1
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'plain continue with a sole in-progress task and handoff'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'plain continue ignored the recorded checkout'
[[ "$launched_orchestrator_prompt" == *'progress context get --task tsk_a_B --json'* ]] || fail 'plain continue did not use the resume prompt'
unset HCOM_FIXTURE_ONLY_TASK_ID HCOM_FIXTURE_HAS_HANDOFF

# A named handoff uses the task checkout when Progress records one.
pbpaste() { print -rn -- 'Copied handoff messages'; }
handoff tsk_a_B || fail 'named handoff with a checkout did not launch'
[[ "$launched_pane_directory" == "$fixture_dir/tsk_a_B" ]] || fail 'named handoff ignored its recorded checkout'
[[ "$launched_orchestrator_prompt" == *'The handover is for task tsk_a_B.'* ]] || fail 'named handoff did not name its task'
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_a_B.old"

# A started task without a recorded checkout must stay in its original checkout.
mv "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B" "$HCOM_FIXTURE_WORKTREE_STATE_DIR/tsk_A__B.old"
export HCOM_FIXTURE_ONLY_TASK_ID=tsk_a_B
_hcom_launch_team team:codex unused unused unused unused continue --yes || fail 'sole in-progress task without a handoff did not continue'
[[ -z "$launched_pane_directory" ]] || fail 'sole in-progress task without a checkout left the original checkout'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_a_B with '* && "$launched_orchestrator_prompt" != *'progress context get --task tsk_a_B --json'* ]] || fail 'sole in-progress task without a handoff did not use the continue prompt'
unset HCOM_FIXTURE_ONLY_TASK_ID

: > "$HCOM_FIXTURE_WORKTREE_CALLS"
_hcom_launch_team team:codex unused unused unused unused continue --task tsk_a_B --yes || fail 'started task without a checkout did not continue'
[[ -z "$launched_pane_directory" ]] || fail 'started task left the original checkout'
[[ "$launched_orchestrator_prompt" == *'Continue task tsk_a_B with '* && "$launched_orchestrator_prompt" != *'progress context get --task tsk_a_B --json'* ]] || fail 'started task without a handoff did not use the continue prompt'
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
[[ "$launched_orchestrator_prompt" == "$plain_ready_prompt" ]] || fail 'plain continue without an in-progress task changed the ready prompt'
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

# Records the paired Scout pane command without opening Ghostty.
#
# @param  {string}  layout_script
#     Layout requested by the learner launcher.
# @param  {string}  launch_command
#     Command the learner would type into the Scout pane.
# @param  {string}  origin_terminal_id
#     Ghostty pane that ran the learner command.
_hcom_workflow_launch_layout() {
	learner_pane_calls=$((learner_pane_calls + 1))
	learner_scout_command="$2"
	learner_origin_terminal_id="$3"
}

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

learner_pane_calls=0  # Number of Scout panes requested by learner launches.
learner_scout_command=""  # Most recent command typed into the Scout pane.
learner_origin_terminal_id=""  # Launching pane ID most recently passed to the learner layout.
launched_learner_role=""  # Most recent learner role sent to the launch boundary.
learner_team_label=""  # Most recent learner team label sent to the launch boundary.
learner_repository_tag="$(_hcom_scoped_tag learn:codex "$PWD")"  # Repository tag shared by fixture learners.
print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"

for provider in claude codex; do
	learn:$provider --team blue fixture-source fixture-context || fail "labelled $provider learner did not launch"
	[[ "$learner_team_label" == "learn-$provider-blue" && "$learner_scout_command" == *"HCOM_TEAM_LABEL=learn-$provider-blue scout "* ]] || fail "labelled $provider learner and Scout use different labels"
	[[ "$launched_learner_role" == "learner-$provider" ]] || fail "labelled $provider launcher selected the wrong role"
	[[ "$learner_origin_terminal_id" == 'fixture-origin-pane' ]] || fail "labelled $provider learner did not pass the origin pane ID as argument 3"

	learn:$provider fixture-source || fail "unlabelled $provider learner did not launch"
	[[ "$learner_team_label" == "learn-$provider" && "$learner_scout_command" == *"HCOM_TEAM_LABEL=learn-$provider scout "* ]] || fail "unlabelled $provider learner tags changed"
	[[ "$learner_origin_terminal_id" == 'fixture-origin-pane' ]] || fail "unlabelled $provider learner did not pass the origin pane ID as argument 3"
done

print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
prior_learner_pane_calls="$learner_pane_calls"  # Pane count before duplicate and input errors.
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Rerun with --team <label> to start another learner team." learn:codex fixture-source
[[ "$learner_pane_calls" == "$prior_learner_pane_calls" ]] || fail 'unlabelled duplicate opened a Scout pane'

print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-blue-scout\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-blue-scout. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Choose a different --team label to start another learner team." learn:codex --team blue fixture-source
[[ "$learner_pane_calls" == "$prior_learner_pane_calls" ]] || fail 'labelled duplicate opened a Scout pane'
print -r -- "[{\"tag\":\"${learner_repository_tag}-learn-codex-blue-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "learn:codex: peer already holds ${learner_repository_tag}-learn-codex-blue-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run learn:codex again. Choose a different --team label to start another learner team." learn:codex --team blue fixture-source
[[ "$learner_pane_calls" == "$prior_learner_pane_calls" ]] || fail 'labelled learner duplicate opened a Scout pane'

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
assert_command_error $'learn:codex: invalid team label: Bad_Label\nlearn:codex: use lowercase letters, numbers, and internal hyphens.\nlearn:codex: usage: learn:codex [--team <label>] <source> [context]' learn:codex --team Bad_Label fixture-source
assert_command_error $'learn:codex: --team requires a label.\nlearn:codex: usage: learn:codex [--team <label>] <source> [context]' learn:codex --team
if learn:codex --team blue 2>"$error_file"; then
	fail 'learner accepted a label without source material'
fi
[[ "$(<"$error_file")" == 'learn:codex: usage: learn:codex [--team <label>] <source> [context]' ]] || fail 'missing learner source omitted usage'
[[ "$learner_pane_calls" == "$prior_learner_pane_calls" ]] || fail 'invalid learner arguments opened a Scout pane'

source "$repo_root/aliases.hcom-plan.zsh"

# Records the commands plan types into each Ghostty pane, without opening any pane.
#
# @param  {string}  script_path
#     The AppleScript that would build the layout, ignored here.
# @param  {string}  codex_command
#     The command for the Codex planning pane.
# @param  {string}  scout_claude_command
#     The command for the Claude Scout pane.
# @param  {string}  scout_codex_command
#     The command for the Codex Scout pane.
# @param  {string}  origin_terminal_id
#     The Ghostty pane that ran the planning command.
function /usr/bin/osascript() {
	plan_osascript_calls=$((plan_osascript_calls + 1))
	recorded_codex_command="$2"
	recorded_scout_claude_command="$3"
	recorded_scout_codex_command="$4"
	recorded_plan_origin_terminal_id="$5"
}

# Records each planning peer's team label without starting an agent.
#
# @param  {string}  ...
#     Role launch options, ignored by this recorder.
_hcom_launch_role() {
	plan_peer_team_labels+=("$HCOM_TEAM_LABEL")
}

plan_osascript_calls=0  # Number of Ghostty layouts requested by plan launches.
recorded_codex_command=""  # Most recent command typed into the Codex planning pane.
recorded_scout_claude_command=""  # Most recent command typed into the Claude Scout pane.
recorded_scout_codex_command=""  # Most recent command typed into the Codex Scout pane.
recorded_plan_origin_terminal_id=""  # Origin pane ID passed to the planning layout.
plan_peer_team_labels=()  # Team labels each planning peer launched with, oldest first.
plan_repository_tag="$(_hcom_scoped_tag plan "$PWD")"  # Repository tag shared by fixture planners.

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
plan --team blue fixture-task || fail 'labelled plan did not launch'
[[ "$recorded_plan_origin_terminal_id" == 'fixture-origin-pane' ]] || fail 'labelled plan did not pass the origin pane ID as argument 5'
[[ "$recorded_codex_command" == *'plan:codex --team blue fixture-task' && "$recorded_scout_claude_command" == *'HCOM_TEAM_LABEL=plan-claude-blue scout' && "$recorded_scout_codex_command" == *'HCOM_TEAM_LABEL=plan-codex-blue scout' ]] || fail 'labelled plan commands lost the label'
[[ "${plan_peer_team_labels[-1]}" == plan-claude-blue ]] || fail 'labelled plan:claude used the wrong team label'

plan fixture-task || fail 'unlabelled plan did not launch'
[[ "$recorded_codex_command" == *'plan:codex fixture-task' && "$recorded_scout_claude_command" == *'HCOM_TEAM_LABEL=plan-claude scout' && "$recorded_scout_codex_command" == *'HCOM_TEAM_LABEL=plan-codex scout' ]] || fail 'unlabelled plan commands changed'
[[ "${plan_peer_team_labels[-1]}" == plan-claude ]] || fail 'unlabelled plan:claude team label changed'

plan:claude --team blue fixture-task || fail 'labelled plan:claude did not launch'
[[ "${plan_peer_team_labels[-1]}" == plan-claude-blue ]] || fail 'plan:claude ignored the label'
plan:codex --team blue fixture-task || fail 'labelled plan:codex did not launch'
[[ "${plan_peer_team_labels[-1]}" == plan-codex-blue ]] || fail 'plan:codex ignored the label'

prior_plan_osascript_calls="$plan_osascript_calls"  # Layout count before duplicate and input errors.
print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-codex-scout\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "plan: peer already holds ${plan_repository_tag}-plan-codex-scout. Switch to that agent, or stop it with \"hcom kill peer\" and run plan again. Rerun with --team <label> to start another planning review." plan fixture-task
print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-claude-blue-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
assert_command_error "plan: peer already holds ${plan_repository_tag}-plan-claude-blue-orchestrator. Switch to that agent, or stop it with \"hcom kill peer\" and run plan again. Choose a different --team label to start another planning review." plan --team blue fixture-task
[[ "$plan_osascript_calls" == "$prior_plan_osascript_calls" ]] || fail 'duplicate plan opened panes'

print -r -- "[{\"tag\":\"${plan_repository_tag}-plan-claude-orchestrator\",\"name\":\"peer\"}]" > "$HCOM_FIXTURE_AGENTS"
plan --team blue fixture-task || fail 'labelled plan was refused beside a live unlabelled planning team'
[[ "$plan_osascript_calls" == "$((prior_plan_osascript_calls + 1))" ]] || fail 'labelled plan beside a live unlabelled team did not open panes'
prior_plan_osascript_calls="$plan_osascript_calls"

print -r -- '[]' > "$HCOM_FIXTURE_AGENTS"
assert_command_error $'plan: invalid team label: Bad_Label\nplan: use lowercase letters, numbers, and internal hyphens.\nplan: usage: plan [--team <label>] <task-name>' plan --team Bad_Label fixture-task
if plan --team blue 2>"$error_file"; then
	fail 'plan accepted a label without a task name'
fi
[[ "$(<"$error_file")" == 'plan: usage: plan [--team <label>] <task-name>' ]] || fail 'missing plan task omitted usage'
[[ "$plan_osascript_calls" == "$prior_plan_osascript_calls" ]] || fail 'invalid plan arguments opened panes'

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
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex || fail 'Rex team session creation'
[[ "${reply[2]}" == 'session:fixture' ]] || fail 'Rex session ID was not returned'
[[ "$(<"$XDG_STATE_HOME/hcom-team/session:fixture/reviewer")" == *'CODEX_HOME='*' HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture '*' reviewer:codex'* ]] || fail 'reviewer reset command lost its account or team scope'
[[ "$(<"$XDG_STATE_HOME/hcom-team/session:fixture/implementer")" == *'HCOM_ACCOUNT=1 HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture '*' implementer'* ]] || fail 'implementer reset command lost its account or team scope'
[[ "$(<"$XDG_STATE_HOME/hcom-team/session:fixture/scout")" == *'CODEX_HOME='*' HCOM_ACCOUNT=2 HCOM_TEAM_LABEL=fixture-task HCOM_TEAM_PROJECT_TAG=Fixture '*' scout'* ]] || fail 'scout reset command lost its account or team scope'
[[ "$(<"$XDG_STATE_HOME/hcom-team/session:fixture/scout")" == 'terminal_title_set scout; '*"CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 HCOM_CODEX_ARGS='-c tui.terminal_title=[]' "* ]] || fail 'scout reset command lost its title or agent title settings'
[[ ! -e "$XDG_STATE_HOME/hcom-team/session:fixture/orchestrator" ]] || fail 'orchestrator prompt was saved on disk'
[[ "$(grep -c '^send-key .* enter$' "$HCOM_FIXTURE_REX_CALLS")" == 4 ]] || fail 'Rex did not submit all four role commands'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'new Fixture · fixture-task -c '*'--window Fixture · fixture-task --json'*'split -s session:fixture -b block:orchestrator --split=right --ratio 33 --label implementer --focus=false --json'*'split -s session:fixture -b block:implementer --split=below --ratio 67 --label reviewer --focus=false --json'*'split -s session:fixture -b block:reviewer --split=below --ratio 50 --label scout --focus=false --json'*'focus -s session:fixture block:orchestrator' ]] || fail 'Rex pane layout or focus changed'
for role in orchestrator implementer reviewer scout; do
	# The command typed into this role's pane, which must set the pane title and
	# stop both agents changing it.
	role_send="$(grep "^send -s session:fixture -b block:$role " "$HCOM_FIXTURE_REX_CALLS")"
	[[ "$role_send" == *"terminal_title_set $role; "* && "$role_send" == *"CLAUDE_CODE_DISABLE_TERMINAL_TITLE=1 HCOM_CODEX_ARGS='-c tui.terminal_title=[]' "* ]] || fail "$role pane lost its title or agent title settings"
done
# Exact directory at the end of the typed orchestrator command.
checkout_path="$fixture_dir/project"
# Exact first prompt at the end of that command.
prompt_text='Continue fixture task.'
# Directory and prompt as the shell sees them.
expected_suffix=" ${(qq)checkout_path} ${(qq)prompt_text}"
# One typed role command.
orchestrator_send="$(grep '^send -s session:fixture -b block:orchestrator ' "$HCOM_FIXTURE_REX_CALLS")"
[[ "$orchestrator_send" == *"$expected_suffix" ]] || fail 'orchestrator command lost its quoted checkout or prompt'

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
assert_command_error 'team:codex: team session session:fixture was left partly built.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task '' 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex
unset HCOM_FIXTURE_REX_SPLIT_FAIL

# A closed stored session discards its old commands before a new session starts.
trash() { print -r -- "$1" >> "$fixture_dir/trashed"; mkdir -p "$fixture_dir/trashed-state"; mv "$1" "$fixture_dir/trashed-state/${1:t}"; }
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[]}'
: > "$HCOM_FIXTURE_REX_CALLS"
print -r -- session:fixture > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:fixture 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B || fail 'closed Rex session replacement'
[[ "$(<"$fixture_dir/trashed")" == *"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"* && "$(<"$fixture_dir/trashed")" == *"$XDG_STATE_HOME/hcom-team/session:fixture"* && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'new Fixture · fixture-task'* ]] || fail 'closed session ID or commands were not discarded'

# An open session without an orchestrator pane is replaced after every old role is checked.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:orphan","label":"Fixture · fixture-task"}]}'
export HCOM_FIXTURE_REX_BLOCKS='{"blocks":[{"block_id":"block:implementer","label":"implementer"},{"block_id":"block:reviewer","label":"reviewer"},{"block_id":"block:scout","label":"scout"}]}'
export HCOM_FIXTURE_REX_NEW_SESSION_ID=session:replacement
mkdir -p "$XDG_STATE_HOME/hcom-team/session:orphan"
print -r -- session:orphan > "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"
export HCOM_FIXTURE_REX_BUSY_BLOCK=block:scout
: > "$HCOM_FIXTURE_REX_CALLS"
assert_command_error 'team:codex: scout pane block:scout is still running an agent; stop it before relaunching.' _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" fixture-task session:orphan 2 1 2 codex codex codex orchestrator:codex 'Continue fixture task.' 1 codex tsk_A_B
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'new '* && -f "$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B" ]] || fail 'busy orphan session was replaced'
unset HCOM_FIXTURE_REX_BUSY_BLOCK
: > "$HCOM_FIXTURE_REX_CALLS"
# Run the public launcher so the test also checks that it saves the new session for the task.
fixture_create_panes_definition="${functions[_hcom_team_create_panes]}"
functions[_hcom_team_create_panes]="${functions[_hcom_team_create_panes_real]}"
_hcom_launch_team team:codex orchestrator:codex reviewer:codex implementer scout continue --task tsk_A_B --yes || fail 'orphan Rex session replacement'
functions[_hcom_team_create_panes]="$fixture_create_panes_definition"
[[ "$(<"$fixture_dir/trashed")" == *"$XDG_STATE_HOME/hcom-team/session:orphan"* && "$(<"$fixture_dir/trashed")" == *"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B"* && "$(<"$XDG_STATE_HOME/hcom-team/tasks/tsk_A_B")" == session:replacement && "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block call process -s session:orphan -b block:scout'*'new '* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session kill'* ]] || fail 'orphan session was not replaced and saved'
unset HCOM_FIXTURE_REX_BLOCKS HCOM_FIXTURE_REX_NEW_SESSION_ID
unfunction trash
unset HCOM_FIXTURE_REX_SESSIONS

# Root teams create a new session even when another session has the same label.
export HCOM_FIXTURE_REX_SESSIONS='{"sessions":[{"session_id":"session:old-root","label":"Fixture"}]}'
: > "$HCOM_FIXTURE_REX_CALLS"
HCOM_TEAM_PROJECT_TAG=Fixture _hcom_team_create_panes_real team:codex reviewer:codex implementer scout "$fixture_dir/project" '' '' 2 1 2 codex codex codex orchestrator:codex '' 1 codex || fail 'root Rex session creation'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'new Fixture -c '*'--window Fixture --json'* && "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'session kill'* ]] || fail 'root team reused or closed another session'
unset HCOM_FIXTURE_REX_SESSIONS

mkdir -p "$XDG_STATE_HOME/hcom-team/fixture-origin-session"
print -rn -- 'HCOM_ACCOUNT=scout-agent team:scout' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/scout"
print -rn -- 'HCOM_ACCOUNT=implementer-agent team:implementer' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/implementer"
print -rn -- 'HCOM_ACCOUNT=reviewer-agent team:reviewer' > "$XDG_STATE_HOME/hcom-team/fixture-origin-session/reviewer"
: > "$HCOM_FIXTURE_REX_CALLS"
team-reset scout >/dev/null || fail 'scout reset failed'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" == *'block ls -s fixture-origin-session --json'*'send-key -s fixture-origin-session -b block:scout ctrl+c ctrl+c'*'block call process -s fixture-origin-session -b block:scout'*'send -s fixture-origin-session -b block:scout HCOM_ACCOUNT=scout-agent team:scout'*'send-key -s fixture-origin-session -b block:scout enter'* ]] || fail 'scout reset did not stop, check and replay its saved command'
[[ "$(<"$HCOM_FIXTURE_REX_CALLS")" != *'send -s fixture-origin-session -b block:scout clear'* ]] || fail 'scout reset cleared its pane'

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
