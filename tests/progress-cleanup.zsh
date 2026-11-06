#!/usr/bin/env zsh
# Checks cleanup folders, relative databases, kept work, pane closing, and fallback calls.

setopt errexit nounset pipefail

# Repository containing the cleanup function under test.
repo_root="${0:A:h:h}"
# Temporary repositories, database, and command output.
fixture_dir="$(mktemp -d /tmp/progress-cleanup.XXXXXX)"
trap 'cd "$repo_root"; trash "$fixture_dir"' EXIT
# Database path reserved for this fixture, never the user's Progress database.
export AGENTS_PROGRESS_DATABASE="$fixture_dir/progress.db"
# Main checkout for the task's project. The name differs from the main_checkout
# local in cleanup, which the Progress fixture would otherwise read instead.
fixture_main_checkout="$fixture_dir/main"
# Separate project from which cleanup can be called.
other_checkout="$fixture_dir/other"
# First recorded checkout when testing a second clone of the task's project.
first_recorded_checkout=""
# Only recorded checkout when testing a Git folder without a main checkout.
only_recorded_checkout=""
# Worktree currently recorded for the fixture task.
current_worktree=""
# Command output produced by the cleanup under test.
cleanup_output="$fixture_dir/cleanup-output"
# Calls made by the Progress fixture, including their working folders.
cleanup_calls="$fixture_dir/cleanup-calls"

touch "$AGENTS_PROGRESS_DATABASE"
git init -q "$fixture_main_checkout"
git init -q "$other_checkout"
: > "$cleanup_calls"

# Prints the behaviour that failed and stops the test.
#
# @param  {string}  message
#     Behaviour that failed.
fail() {
	print -u2 -- "FAIL: $1"
	exit 1
}

# Creates an empty task worktree without writing Git history.
#
# @param  {string}  name
#     Name of the fixture worktree and its branch.
make_worktree() {
	current_worktree="$fixture_dir/$1"
	git -C "$fixture_main_checkout" worktree add -q --orphan -b "$1" "$current_worktree" || fail 'could not create the fixture worktree'
}

# Answers task lookups and fails when cleanup uses the wrong checkout or database path.
#
# @param  {string}  ...
#     Progress arguments supplied by the cleanup function.
progress() {
	# Database path supplied to this Progress call.
	local database_path="$AGENTS_PROGRESS_DATABASE"
	# Whether the next argument is the database path.
	local database_value_next=0
	# Argument currently being checked for a database option.
	local progress_arg

	for progress_arg in "$@"; do
		if (( database_value_next )); then
			database_path="$progress_arg"
			database_value_next=0
			continue
		fi
		case "$progress_arg" in
			--database) database_value_next=1 ;;
			--database=*) database_path="${progress_arg#--database=}" ;;
		esac
	done
	[[ -f "$database_path" && "${database_path:A}" == "${AGENTS_PROGRESS_DATABASE:A}" ]] || fail 'Progress received the wrong database path'

	if [[ "$1" == task && "$2" == find ]]; then
		[[ "$3" == tsk_fixture ]] || return 1
		jq -n --arg missing "$fixture_dir/missing" --arg worktree "$current_worktree" --arg main "$fixture_main_checkout" --arg first "$first_recorded_checkout" --arg only "$only_recorded_checkout" '{data: [{checkouts: (if $only != "" then [$only] else [$missing, $first, $worktree, $main] | map(select(. != "")) end)}]}'
		return
	fi

	[[ "$1" == worktree && "$2" == cleanup ]] || fail 'cleanup called an unexpected Progress command'
	print -r -- "$PWD|$*" >> "$cleanup_calls"
	if [[ "${PWD:A}" == "${fixture_main_checkout:A}" && "$*" == *--database* ]]; then
		[[ "$database_path" == /* ]] || fail 'cleanup received a relative database path from another folder'
	fi
	if [[ "$*" == *--help* || "$*" == *--branch* || "$*" != *tsk_fixture* ]]; then
		print -r -- 'Original Progress response'
		return 0
	fi
	[[ "${PWD:A}" == "${fixture_main_checkout:A}" ]] || return 9
	if [[ -e "$current_worktree/unfinished" ]]; then
		print -r -- 'Worktree kept'
		return 0
	fi
	git -C "$fixture_main_checkout" worktree remove "$current_worktree" || return $?
	print -r -- 'Worktree cleaned'
}

source "$repo_root/aliases.progress.zsh"

# A caller inside one clone selects its main checkout even when another clone is listed first.
git clone -q --no-checkout "$fixture_main_checkout" "$fixture_dir/second-clone" 2>/dev/null || fail 'could not create the second clone'
first_recorded_checkout="$fixture_dir/second-clone"
cd "$fixture_main_checkout"
# Main checkout selected from the caller's shared Git folder.
selected_checkout="$(_progress_cleanup_main_checkout tsk_fixture)"
[[ "${selected_checkout:A}" == "${fixture_main_checkout:A}" ]] || fail 'cleanup selected the wrong clone for the caller'
first_recorded_checkout=""

# A separate Git folder does not make its parent a main checkout.
git init -q --separate-git-dir "$fixture_dir/separate.git" "$fixture_dir/separate-checkout" || fail 'could not create the separate Git folder'
only_recorded_checkout="$fixture_dir/separate-checkout"
cd "$other_checkout"
[[ -z "$(_progress_cleanup_main_checkout tsk_fixture)" ]] || fail 'cleanup treated a separate Git folder as a main checkout'
if cleanup tsk_fixture > "$cleanup_output"; then
	fail 'cleanup unexpectedly succeeded from another project with a separate Git folder'
fi
[[ "$(tail -n 1 "$cleanup_calls")" == "$other_checkout|worktree cleanup tsk_fixture" ]] || fail 'cleanup did not call Progress from the caller for a separate Git folder'
only_recorded_checkout=""

# Cleanup moves the shell to the main checkout when its worktree is removed.
make_worktree inside
cd "$current_worktree"
cleanup tsk_fixture --json > "$cleanup_output" || fail 'cleanup from inside the worktree failed'
[[ "${PWD:A}" == "${fixture_main_checkout:A}" && ! -d "$fixture_dir/inside" && "$(<"$cleanup_output")" == 'Worktree cleaned' ]] || fail "cleanup left the shell in the removed worktree or changed Progress output: expected ${fixture_main_checkout:A}, got ${PWD:A}"

# Cleanup leaves a shell in the main checkout when it started there.
make_worktree main_call
cleanup tsk_fixture > "$cleanup_output" || fail 'cleanup from the main checkout failed'
[[ "${PWD:A}" == "${fixture_main_checkout:A}" && ! -d "$fixture_dir/main_call" && "$(<"$cleanup_output")" == 'Worktree cleaned' ]] || fail 'cleanup from the main checkout changed the shell or output'

# Cleanup leaves another project's shell in place.
make_worktree other_call
cd "$other_checkout"
cleanup tsk_fixture > "$cleanup_output" || fail 'cleanup from another project failed'
[[ "${PWD:A}" == "${other_checkout:A}" && ! -d "$fixture_dir/other_call" && "$(<"$cleanup_output")" == 'Worktree cleaned' ]] || fail 'cleanup moved the shell from another project'

# The space-separated --database form finds the same file when cleanup runs from the main checkout.
make_worktree spaced_database
cleanup tsk_fixture --database ../progress.db > "$cleanup_output" || fail 'cleanup with a space-separated relative database path failed'
[[ "${PWD:A}" == "${other_checkout:A}" && ! -d "$fixture_dir/spaced_database" && "$(<"$cleanup_output")" == 'Worktree cleaned' ]] || fail 'cleanup with a space-separated database path changed the result'

# The --database=path form finds the same file too.
make_worktree equals_database
cleanup tsk_fixture --database=../progress.db > "$cleanup_output" || fail 'cleanup with an equals relative database path failed'
[[ "${PWD:A}" == "${other_checkout:A}" && ! -d "$fixture_dir/equals_database" && "$(<"$cleanup_output")" == 'Worktree cleaned' ]] || fail 'cleanup with an equals database path changed the result'

# Records the checkout used for the pane lookup and reports the task's worktree
# for as long as it exists, as the real lookup does.
#
# @param  {string}  ...
#     Cleanup name, checkout, and task ID supplied by cleanup.
_hcom_get_launch_checkout() {
	pane_lookup_checkout="$2"
	if [[ -d "$current_worktree" ]]; then
		reply=("$current_worktree")
	else
		reply=()
	fi
}

# Counts the times cleanup closes the task's idle panes.
#
# @param  {string}  ...
#     Task ID supplied by cleanup.
_hcom_team_cleanup_task() {
	(( ++pane_close_count ))
}

# Checkout most recently supplied to the pane lookup.
pane_lookup_checkout=""
# Number of times cleanup has closed the task's idle panes.
pane_close_count=0
# Marks the shell as inside Rex, which is when cleanup closes panes.
export REX_SESSION=fixture

# Pane cleanup uses the main checkout after removal of the caller's worktree.
make_worktree pane_call
cd "$current_worktree"
cleanup tsk_fixture > "$cleanup_output" || fail 'cleanup with team panes failed'
[[ "${pane_lookup_checkout:A}" == "${fixture_main_checkout:A}" && "$pane_close_count" == 1 && ! -d "$fixture_dir/pane_call" ]] || fail 'cleanup did not close panes using the main checkout'

# A worktree with uncommitted work is kept, and the shell stays in it.
make_worktree unfinished_call
touch "$current_worktree/unfinished"
cd "$current_worktree"
cleanup tsk_fixture > "$cleanup_output" || fail 'cleanup with uncommitted work failed'
[[ "${PWD:A}" == "${current_worktree:A}" && -f "$current_worktree/unfinished" && "$(<"$cleanup_output")" == 'Worktree kept' ]] || fail 'cleanup moved the shell or removed uncommitted work'
[[ "${pane_lookup_checkout:A}" == "${fixture_main_checkout:A}" && "$pane_close_count" == 1 ]] || fail 'cleanup closed panes for a kept worktree'
unset REX_SESSION

# Calls without a usable task record run Progress from the caller's folder.
cd "$other_checkout"
cleanup --help > "$cleanup_output" || fail 'cleanup help failed'
cleanup --branch old-branch > "$cleanup_output" || fail 'branch cleanup failed'
cleanup > "$cleanup_output" || fail 'cleanup without a task ID failed'
cleanup tsk_missing > "$cleanup_output" || fail 'cleanup with a missing task failed'
[[ "$(tail -n 4 "$cleanup_calls")" == *"$other_checkout|worktree cleanup --help"*"$other_checkout|worktree cleanup --branch old-branch"*"$other_checkout|worktree cleanup"*"$other_checkout|worktree cleanup tsk_missing"* ]] || fail 'fallback cleanup changed the caller folder'

cd "$repo_root"
print -- 'PASS: cleanup folders, clone selection, separate Git folders, relative databases, pane closing, kept work, and fallback calls'
