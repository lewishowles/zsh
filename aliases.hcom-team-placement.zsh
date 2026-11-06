# Chooses Rex sessions and tabs for HCOM teams and restores their names.

# Chooses the launcher's reusable tab or an existing Rex session.
# Sets reply=(session ID, reusable tab ID, leftover role pane IDs). The session
# ID is the repository's session when one exists, otherwise the launcher's
# session. The tab ID is empty when a new tab is needed.
#
# @param  {string}  repository_name
#     Name of the repository session.
# @param  {string}  sessions_json
#     Current Rex session listing.
_hcom_team_choose_new_tab() {
	# Name of the repository session.
	local repository_name="$1"
	# Rex session listing from before the launch.
	local sessions_json="$2"
	# Launcher's tab, when a team can use it.
	local current_window_id=""
	# Idle role panes a stopped team left in the launcher's tab.
	local -a leftover_blocks
	# Session with the repository name, preferring the launcher's session.
	local named_session=""

	if [[ -n "${REX_BLOCK:-}" ]] && jq -e --arg id "${REX_SESSION:-}" '.sessions[] | select(.session_id == $id)' >/dev/null <<<"$sessions_json"; then
		_hcom_team_unused_current_window "$REX_SESSION" "$REX_BLOCK" || return 1
		current_window_id="${reply[1]}"

		if (( ${#reply} > 1 )); then
			leftover_blocks=("${(@)reply[2,-1]}")
		fi
	fi

	named_session="$(_hcom_team_named_session_id "$sessions_json" "$repository_name" "${REX_SESSION:-}")" || return 1

	# A session named after the repository wins over a free tab in any other session.
	if [[ -n "$current_window_id" && -n "$named_session" && "$named_session" != "$REX_SESSION" ]]; then
		current_window_id=""
	fi

	if [[ -n "$current_window_id" ]]; then
		reply=("$REX_SESSION" "$current_window_id" "${leftover_blocks[@]}")
	else
		reply=("${named_session:-${REX_SESSION:-}}" "")
	fi
}

# Finds the launcher's tab when it is alone there or shares it only with a
# stopped team's idle role panes.
# Sets reply=(tab ID, idle role pane IDs), or an empty tab ID when the team needs
# another tab.
#
# @param  {string}  session_id
#     Current Rex session.
# @param  {string}  current_block
#     Pane running the launcher.
_hcom_team_unused_current_window() {
	# Current Rex session.
	local session_id="$1"
	# Pane running the launcher.
	local current_block="$2"
	# Pane listing, narrowed to the launcher's tab once the tab is known.
	local blocks_json
	# Tab containing the launcher.
	local window_id
	# Saved task record being checked against this tab.
	local task_session_file
	# Set to 1 when a saved task record names this tab.
	local saved_tab=0
	# Another pane in the tab.
	local block_id
	# Foreground process of that pane.
	local process_json
	# Label of that pane.
	local block_label
	# Idle role panes the stopped team left behind.
	local -a leftover_blocks

	reply=("")
	blocks_json="$(command rex block ls -s "$session_id" --json)" || return 1
	window_id="$(_hcom_team_block_window "$current_block" "$blocks_json")" || return 1
	[[ -n "$window_id" ]] || return 0
	blocks_json="$(_hcom_team_blocks_in_window "$session_id" "$window_id" "$blocks_json")" || return 1

	if [[ "$(jq -r '.blocks | length' <<<"$blocks_json")" == 1 ]]; then
		reply=("$window_id")
		return 0
	fi

	for task_session_file in "$(_hcom_team_task_record_path)"*(N.); do
		_hcom_team_read_task_record "$task_session_file"

		if [[ "${reply[1]}" == "$session_id" && "${reply[2]}" == "$window_id" ]]; then
			saved_tab=1
			break
		fi
	done

	reply=("")
	(( saved_tab )) || return 0

	for block_id in "${(@f)$(jq -r '.blocks[].block_id' <<<"$blocks_json")}"; do
		[[ "$block_id" == "$current_block" ]] && continue
		block_label="$(jq -r --arg id "$block_id" '.blocks[] | select(.block_id == $id) | .label // empty' <<<"$blocks_json")" || return 1

		# A pane without a role label belongs to the human, so the team opens in another tab instead.
		case "$block_label" in
			orchestrator|implementer|reviewer|scout) ;;
			*) return 0 ;;
		esac

		process_json="$(command rex block call process -s "$session_id" -b "$block_id")" || return 1
		_hcom_team_pane_is_idle "$process_json" || return 0
		leftover_blocks+=("$block_id")
	done

	reply=("$window_id" "${leftover_blocks[@]}")
}

# Prints the ID of a session with the repository name, preferring the launcher's
# session and otherwise the first listed. Prints nothing when there is none.
#
# @param  {string}  sessions_json
#     Current Rex session listing.
# @param  {string}  repository_name
#     Name of the repository session.
# @param  {string}  preferred_id
#     Session to prefer when it has the repository name.
_hcom_team_named_session_id() {
	# Current Rex session listing.
	local sessions_json="$1"
	# Name of the repository session.
	local repository_name="$2"
	# Session to prefer when it has the repository name.
	local preferred_id="${3:-}"

	jq -r --arg name "$repository_name" --arg preferred_id "$preferred_id" '([.sessions[] | select(.label == $name and .session_id == $preferred_id) | .session_id][0] // [.sessions[] | select(.label == $name) | .session_id][0]) // empty' <<<"$sessions_json"
}

# Gets the chosen tab ready: closes a reused tab's leftover panes, or opens a
# new tab, then labels the first pane as orchestrator.
# Sets reply=(session ID, tab ID, orchestrator pane, reused launcher tab).
#
# @param  {string}  command_name
#     Public command used in errors.
# @param  {string}  tab_name
#     Name given to a new tab.
# @param  {string}  team_scope_directory
#     Directory opened by a new tab.
# @param  {string}  session_id
#     Chosen existing session.
# @param  {string}  window_id
#     The launcher's tab when it is being reused, or empty to open a new tab.
# @param  {string}  ...
#     Leftover role panes to close in the reused tab.
_hcom_team_open_chosen_tab() {
	# Public command used in errors.
	local command_name="$1"
	# Name given to a new tab.
	local tab_name="$2"
	# Directory opened by a new tab.
	local team_scope_directory="$3"
	# Chosen existing session.
	local session_id="$4"
	# The launcher's tab when it is being reused, or empty to open a new tab.
	local window_id="$5"
	shift 5
	# Leftover role panes to close in the reused tab.
	local -a leftover_blocks=("$@")
	# Leftover pane being closed.
	local block_id
	# Response from Rex when it opens a tab.
	local new_json
	# First pane of the team's tab.
	local orchestrator_block=""
	# Set to 1 when the team uses the launcher's tab.
	local reused_launcher_tab=0

	if [[ -n "$window_id" ]]; then
		for block_id in "${leftover_blocks[@]}"; do
			if ! command rex block close "$block_id" -s "$session_id"; then
				_hcom_command_error "$command_name" "stopped team pane $block_id could not be closed; no new panes launched."
				return 1
			fi
		done

		orchestrator_block="$REX_BLOCK"
		reused_launcher_tab=1
	else
		new_json="$(command rex window new -s "$session_id" "$tab_name" -c "$team_scope_directory" --focus=false --json)" || return 1
		window_id="$(jq -er '.window_id' <<<"$new_json")" || return 1
		orchestrator_block="$(jq -er '.block_ids[0]' <<<"$new_json")" || return 1
	fi

	if [[ -z "$window_id" ]]; then
		_hcom_command_error "$command_name" "team session $session_id was left partly built; its tab ID could not be read."
		return 1
	fi

	if ! command rex block rename -s "$session_id" "$orchestrator_block" orchestrator; then
		_hcom_command_error "$command_name" "team session $session_id was left partly built."
		return 1
	fi

	reply=("$session_id" "$window_id" "$orchestrator_block" "$reused_launcher_tab")
}

# Names the team's tab, and names the session after the repository when the
# team's pane is the only one in it and no other session already has that name.
#
# @param  {string}  command_name
#     Public command used in errors.
# @param  {string}  repository_name
#     Desired repository session name.
# @param  {string}  tab_name
#     Desired team tab name.
# @param  {string}  session_id
#     Session containing the team.
# @param  {string}  window_id
#     Tab containing the team, or empty when the tab is unknown.
# @param  {string}  sessions_json
#     Rex session listing from before the launch.
_hcom_team_apply_names() {
	# Public command used in errors.
	local command_name="$1"
	# Desired repository session name.
	local repository_name="$2"
	# Desired team tab name.
	local tab_name="$3"
	# Session containing the team.
	local session_id="$4"
	# Tab containing the team, or empty when the tab is unknown.
	local window_id="$5"
	# Rex session listing from before the launch.
	local sessions_json="$6"
	# Current name of the team's session.
	local current_name
	# Number of panes in the session before the team is split.
	local block_count

	current_name="$(jq -r --arg id "$session_id" '[.sessions[] | select(.session_id == $id) | .label][0] // empty' <<<"$sessions_json")" || return 1

	if [[ "$current_name" != "$repository_name" ]] && ! jq -e --arg id "$session_id" --arg name "$repository_name" '.sessions[] | select(.session_id != $id and .label == $name)' >/dev/null <<<"$sessions_json"; then
		block_count="$(command rex block ls -s "$session_id" --json | jq -er '.blocks | length')" || return 1

		if (( block_count == 1 )); then
			if ! command rex session rename "$session_id" "$repository_name"; then
				_hcom_command_error "$command_name" "team session $session_id was left partly built."
				return 1
			fi
		fi
	fi

	[[ -n "$window_id" ]] || return 0

	if ! command rex window rename -s "$session_id" "$window_id" "$tab_name"; then
		_hcom_command_error "$command_name" "team session $session_id was left partly built."
		return 1
	fi
}

# Prints the short tab name for a task slug, or Team for a team with no task.
#
# @param  {string}  team_label
#     Task slug used by the team's role tags, empty for a team with no task.
_hcom_team_launch_tab_name() {
	# Task slug, or empty for a team with no task.
	local team_label="$1"

	if [[ -z "$team_label" ]]; then
		print -r -- Team
		return
	fi

	# Slug without the quick-task prefix.
	local slug="${team_label#quick-}"
	# Slug words, split on hyphens so the name can be capped at five.
	local -a words
	words=("${(@s/-/)slug}")
	# Lowercase name, ready for its first letter to be capitalised.
	local name="${(L)${(j: :)words[1,5]}}"

	print -r -- "${(U)name[1]}${name[2,-1]}"
}
