# hcom team layout and lifecycle commands.

# Returns the exact role tags for a team scope.
#
# @param  {string}  working_directory
#     The directory selected for the team.
# @param  {string}  team_label
#     The optional label selected for the team.
_hcom_team_tags() {
	local working_directory="$1"  # Directory that scopes the team.
	local team_label="$2"  # Optional label that further scopes the team.
	local repository_tag  # Exact repository tag for the working directory.
	local tag_prefix  # Repository tag plus the optional team label.

	repository_tag="$(_hcom_scoped_tag "$working_directory")" || return 1
	tag_prefix="$repository_tag"

	if [[ -n "$team_label" ]]; then
		tag_prefix+="-$team_label"
	fi

	print -r -- "$tag_prefix-orchestrator|$tag_prefix-reviewer|$tag_prefix-implementer|$tag_prefix-scout"
}

# Stops agents for exact team tags, ignoring agents that are already stopped.
#
# @param  {string}  team_tags
#     Pipe-separated exact hcom tags to stop.
_hcom_stop_team_tags() {
	local team_tags="$1"  # Pipe-separated exact tags for the team to stop.
	local tag  # Current exact tag passed to hcom kill.
	local -a exact_tags  # Exact tags split from the pipe-separated input.

	exact_tags=("${(@s:|:)team_tags}")

	for tag in "${exact_tags[@]}"; do
		if [[ -n "$tag" ]]; then
			command hcom kill "tag:$tag" >/dev/null 2>&1 || :
		fi
	done
}

# Closes tracked Ghostty panes and optionally focuses a remaining pane.
#
# @param  {string}  terminal_ids
#     Pipe-separated Ghostty terminal IDs to close.
# @param  {string}  focus_terminal_id
#     Optional Ghostty terminal ID to focus after closing the tracked panes.
_hcom_close_team_terminals() {
	local terminal_ids="$1"  # Pipe-separated Ghostty terminal IDs to close.
	local focus_terminal_id="${2:-}"  # Remaining Ghostty pane to focus after cleanup.

	if [[ -z "$terminal_ids" ]]; then
		return 0
	fi

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" --close "$terminal_ids" "$focus_terminal_id" >/dev/null 2>&1 || :
}

# Clears all stored state for the active team in the launching shell.
#
# The function has no parameters or output. It only unsets the active-team
# variables, so later no-argument stops cannot reuse a completed scope.
_hcom_clear_team_scope() {
	unset HCOM_ACTIVE_TEAM_DIRECTORY
	unset HCOM_ACTIVE_TEAM_LABEL
	unset HCOM_ACTIVE_TEAM_TAGS
	unset HCOM_ACTIVE_TEAM_TERMINAL_IDS
	unset HCOM_TEAM_TERMINAL_IDS
}

# Returns the orchestrator prompt for a team continuation mode.
#
# @param  {string}  launch_mode
#     Controls whether the orchestrator resumes a handoff or selects the next work.
_hcom_team_continuation_prompt() {
	local launch_mode="$1"  # Continuation mode that determines how progress records are used.

	case "$launch_mode" in
		resume)
			print -r -- "Retrieve the full handoff with progress context get --json, then resume the interrupted work from that handoff. Do not select a new task."
			;;
		continue)
			print -r -- "Use the project-continue skill to retrieve the current progress records and continue with the next ready work."
			;;
		*)
			printf 'hcom: unknown team continuation mode: %s\n' "$launch_mode" >&2
			return 1
			;;
	esac
}

# Starts a complete hcom team with the requested orchestrator and reviewer.
#
# Creates this layout in the current Ghostty tab:
#
#   orchestrator | implementer
#   reviewer     | scout
#
# Prints a labelled start notice when a team label is supplied and returns the
# foreground orchestrator's exit status. Validation and pane-launch failures
# return their own non-zero status. The function stores the new team scope,
# replaces a previous same-shell team when both prior tags and pane IDs exist,
# and cleans up teammate agents and panes unless --keep-agents is supplied.
# A local INT trap lets normal exit and Ctrl-C use the same cleanup path.
#
# @param  {string}  command_name
#     Public command name used in validation errors.
# @param  {string}  orchestrator_launcher
#     Function that starts the orchestrator role.
# @param  {string}  reviewer_launcher
#     Function that starts the reviewer role.
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional initial prompt for the orchestrator.
_hcom_launch_team() {
	local command_name="$1"  # Public command name used in diagnostics.
	local orchestrator_launcher="$2"  # Launcher for the foreground orchestrator.
	local reviewer_launcher="$3"  # Launcher for the reviewer pane.
	shift 3
	local launch_mode=""  # Optional resume or continue behaviour for the orchestrator.

	case "${1:-}" in
		resume|continue)
			launch_mode="$1"
			shift
			;;
	esac

	local team_label=""  # Optional label parsed from the launch options.
	local keep_agents=0  # Whether cleanup should leave agents and panes running.
	while [[ $# -gt 0 ]]; do
		case "$1" in
			--team)
				if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == --* ]]; then
					printf '%s: --team requires a label.\n' "$command_name" >&2
					return 1
				fi

				team_label="$2"
				shift 2
				;;
			--keep-agents)
				keep_agents=1
				shift
				;;
			--)
				shift
				break
				;;
			--*)
				printf '%s: unknown option: %s\n' "$command_name" "$1" >&2
				return 1
				;;
			*) break ;;
		esac
	done

	local maximum_positionals=2  # Directory and optional prompt accepted by a fresh launch.
	if [[ -n "$launch_mode" ]]; then
		maximum_positionals=1
	fi

	if [[ $# -gt maximum_positionals ]]; then
		printf '%s: usage: %s [resume|continue] [--team <label>] [--keep-agents] [working-directory] [initial-prompt]\n' "$command_name" "$command_name" >&2
		return 1
	fi

	if [[ -n "$team_label" ]]; then
		_hcom_validate_team_label "$team_label" "$command_name" || return 1
	fi

	local working_directory="${1:-$PWD}"  # Project directory for the team.
	local initial_prompt="${2:-}"  # Optional prompt passed to the orchestrator.

	if [[ -n "$launch_mode" ]]; then
		initial_prompt="$(_hcom_team_continuation_prompt "$launch_mode")" || return 1
	fi

	if [[ ! -d "$working_directory" ]]; then
		printf '%s: working directory not found: %s\n' "$command_name" "$working_directory" >&2
		return 1
	fi

	local quoted_working_directory="${(q)working_directory}"  # Zsh-quoted directory for typed pane commands.

	# Ghostty panes start fresh shells that don't inherit this shell's
	# exported env, so an active account override must ride along in the
	# typed command line instead.
	local account_env  # Account override prefix copied into each new pane command.
	account_env="$(_hcom_account_environment)"
	local team_env=""  # Optional HCOM_TEAM_LABEL assignment for new panes.
	[[ -n "$team_label" ]] && team_env+="HCOM_TEAM_LABEL=${(q)team_label} "
	local launch_env="${account_env}${team_env}"  # Combined environment prefix for pane commands.

	local reviewer_command="${launch_env}$reviewer_launcher $quoted_working_directory"  # Typed reviewer launch command.
	local implementer_command="${launch_env}hcom-implementer $quoted_working_directory"  # Typed implementer launch command.
	local scout_command="${launch_env}hcom-scout $quoted_working_directory"  # Typed scout launch command.
	local team_tags  # Exact role tags for the new team scope.
	team_tags="$(_hcom_team_tags "$working_directory" "$team_label")" || return 1

	# A terminal ID survives the agent session and lets the next launch replace
	# only the teammate panels created by this orchestrator shell.
	local previous_terminal_ids="${HCOM_TEAM_TERMINAL_IDS:-}"  # Prior same-shell pane IDs, if any.
	local previous_team_tags="${HCOM_ACTIVE_TEAM_TAGS:-}"  # Prior same-shell exact tags, if any.
	if [[ -n "$previous_terminal_ids" ]] && [[ -n "$previous_team_tags" ]]; then
		_hcom_stop_team_tags "$previous_team_tags"
	fi

	local team_terminal_ids  # Pipe-separated IDs returned for the new team panes.
	team_terminal_ids="$(
		/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-team.applescript" \
			"$reviewer_command" \
			"$implementer_command" \
			"$scout_command" \
			"$previous_terminal_ids"
	)"

	local osascript_exit_code=$?  # Result of creating and wiring the Ghostty panes.

	if (( osascript_exit_code != 0 )); then
		return "$osascript_exit_code"
	fi

	# The launching shell's stored scope, so hcom-team-stop needs no arguments
	# there and can tell which team it is scoped to.
	typeset -g HCOM_ACTIVE_TEAM_DIRECTORY="$working_directory"  # Stored directory for implicit or matching stops.
	typeset -g HCOM_ACTIVE_TEAM_LABEL="$team_label"  # Stored optional label for the active scope.
	typeset -g HCOM_ACTIVE_TEAM_TAGS="$team_tags"  # Stored exact role tags for the active scope.
	typeset -g HCOM_ACTIVE_TEAM_TERMINAL_IDS="$team_terminal_ids"  # Stored IDs for matching pane cleanup.
	typeset -g HCOM_TEAM_TERMINAL_IDS="$team_terminal_ids"  # Current IDs used by same-shell relaunch cleanup.

	if [[ -n "$team_label" ]]; then
		printf 'Starting hcom team %s in %s.\n' "$team_label" "$working_directory"
	fi

	local orchestrator_exit_code  # Foreground orchestrator result returned by this function.
	# Without this, SIGINT during the foreground orchestrator call aborts this whole function,
	# skipping the cleanup below; localtraps restores the prior INT trap on any return path.
	setopt localoptions localtraps
	trap ':' INT
	if HCOM_TEAM_LABEL="$team_label" "$orchestrator_launcher" "$working_directory" "$initial_prompt"; then
		orchestrator_exit_code=0
	else
		orchestrator_exit_code=$?
	fi

	if (( keep_agents == 0 )); then
		_hcom_stop_team_tags "${team_tags#*|}"
		local orchestrator_terminal_id="${team_terminal_ids%%|*}"  # Orchestrator pane restored after teammate cleanup.
		_hcom_close_team_terminals "${team_terminal_ids#*|}" "$orchestrator_terminal_id"
		_hcom_clear_team_scope
	fi

	return "$orchestrator_exit_code"
}

# @desc  Start, resume, or continue the complete hcom team
# @cat   hcom
#
# Usage: hcom-team [resume|continue] [--team <label>] [--keep-agents] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional orchestrator prompt for a fresh launch.
hcom-team() {
	_hcom_launch_team hcom-team hcom-orchestrator hcom-reviewer "$@"
}

# @desc  Start, resume, or continue the complete Codex hcom team
# @cat   hcom
#
# Usage: hcom-team-codex [resume|continue] [--team <label>] [--keep-agents] [working-directory] [initial-prompt]
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the current directory.
# @param  {string}  initial_prompt
#     Optional orchestrator prompt for a fresh launch.
hcom-team-codex() {
	_hcom_launch_team hcom-team-codex hcom-orchestrator-codex hcom-reviewer-codex "$@"
}

# Stops the exact hcom team for a directory and optional team label.
#
# With no scope arguments, stops the launching shell's stored team and clears
# that stored state. With an explicit scope, stops only its exact tags and
# closes panes or clears state when the canonical directory and label match the
# launching shell's stored scope. Missing agents, panes, or stored state are
# successful no-op cases, so repeating a stop is safe. Validation and tag
# resolution failures return non-zero; agent and pane cleanup failures are
# tolerated.
#
# @desc  Stop the exact hcom team for a directory and optional team label
# @cat   hcom
#
# Usage: hcom-team-stop [--team <label>] [working-directory]
#
# Run with no arguments from the shell that launched the team, or with
# --team/a directory from elsewhere. From another shell this always stops
# the team's agents, but can only close its Ghostty panes when that scope
# matches the launching shell's own stored team.
#
# @param  {string}  working_directory
#     Optional project directory. Defaults to the active team's directory or the current directory with an explicit scope.
# @param  {string}  team_label
#     Optional team label. Defaults to the active team's label when no scope is supplied.
hcom-team-stop() {
	local team_label=""  # Explicit label, or the stored label for an implicit stop.
	local working_directory=""  # Explicit directory, or the stored/current directory.
	local explicit_scope=0  # Whether --team or a directory was supplied, rather than using the launching shell's stored team.
	local usage_message="hcom-team-stop: usage: hcom-team-stop [--team <label>] [working-directory]"  # Shared usage error text.

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--team)
				if [[ $# -lt 2 ]] || [[ -z "$2" ]] || [[ "$2" == --* ]]; then
					printf 'hcom-team-stop: --team requires a label.\n' >&2
					return 1
				fi

				team_label="$2"
				explicit_scope=1
				shift 2
				;;
			--)
				shift
				break
				;;
			--*)
				printf 'hcom-team-stop: unknown option: %s\n' "$1" >&2
				return 1
				;;
			*)
				if [[ -n "$working_directory" ]]; then
					printf '%s\n' "$usage_message" >&2
					return 1
				fi

				working_directory="$1"
				explicit_scope=1
				shift
				;;
		esac
	done

	if [[ $# -gt 0 ]]; then
		if [[ -n "$working_directory" ]]; then
			printf '%s\n' "$usage_message" >&2
			return 1
		fi

		working_directory="$1"
		explicit_scope=1
		shift
	fi

	if [[ $# -gt 0 ]]; then
		printf '%s\n' "$usage_message" >&2
		return 1
	fi

	local team_tags=""  # Exact tags resolved for the requested stop scope.
	local terminal_ids=""  # Stored pane IDs available for matching pane cleanup.
	local scope_matches_active=0  # Whether an explicit scope matches stored directory and label, so its stored state can be cleared too.

	if (( explicit_scope == 0 )); then
		if [[ -z "${HCOM_ACTIVE_TEAM_TAGS:-}" ]]; then
			printf 'No active hcom team to stop.\n'
			return 0
		fi

		working_directory="$HCOM_ACTIVE_TEAM_DIRECTORY"
		team_label="$HCOM_ACTIVE_TEAM_LABEL"
		team_tags="$HCOM_ACTIVE_TEAM_TAGS"
		terminal_ids="$HCOM_ACTIVE_TEAM_TERMINAL_IDS"
	else
		working_directory="${working_directory:-$PWD}"

		if [[ ! -d "$working_directory" ]]; then
			printf 'hcom-team-stop: working directory not found: %s\n' "$working_directory" >&2
			return 1
		fi

		if [[ -n "$team_label" ]]; then
			_hcom_validate_team_label "$team_label" hcom-team-stop || return 1
		fi

		team_tags="$(_hcom_team_tags "$working_directory" "$team_label")" || return 1

		if [[ -n "${HCOM_ACTIVE_TEAM_DIRECTORY:-}" ]] && [[ "${working_directory:A}" = "${HCOM_ACTIVE_TEAM_DIRECTORY:A}" ]] && [[ "$team_label" = "${HCOM_ACTIVE_TEAM_LABEL:-}" ]]; then
			scope_matches_active=1
			terminal_ids="${HCOM_ACTIVE_TEAM_TERMINAL_IDS:-}"
		fi
	fi

	_hcom_stop_team_tags "$team_tags"
	_hcom_close_team_terminals "$terminal_ids"

	if (( explicit_scope == 0 || scope_matches_active == 1 )); then
		_hcom_clear_team_scope
	fi
}
