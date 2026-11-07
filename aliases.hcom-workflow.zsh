# Shared helpers for the hcom team, plan, learning, and insights-review launchers.

# Prints the ID of the focused Ghostty pane, so a launcher can still open its
# layout beside the pane that ran it if the human switches tabs during the
# launch. Stops with an error when Ghostty is not running, is not the frontmost
# app, or has no window.
#
# @param  {string}  command_name
#     The public command named in the failure message.
_hcom_focused_ghostty_terminal_id() {
	local command_name="$1"  # Public command responsible for the pane lookup.
	local terminal_id  # Focused pane ID or a refusal returned by Ghostty.

	# Ask macOS whether the app is running instead of using pgrep, which cannot
	# see Ghostty's process. The check sits outside the tell block so a closed
	# Ghostty is reported rather than launched.
	terminal_id="$(/usr/bin/osascript \
		-e 'if application "Ghostty" is not running then return "not-running"' \
		-e 'tell application "Ghostty"' \
		-e 'if not frontmost then return "not-frontmost"' \
		-e 'if (count of windows) = 0 then return "no-windows"' \
		-e 'get id of focused terminal of selected tab of front window' \
		-e 'end tell' 2>/dev/null)" || {
		_hcom_command_error "$command_name" 'could not read the focused Ghostty pane.'
		return 1
	}

	case "$terminal_id" in
		not-running)
			_hcom_command_error "$command_name" 'Ghostty is not running.'
			return 1
			;;
		not-frontmost)
			_hcom_command_error "$command_name" 'run this command from a Ghostty terminal.'
			return 1
			;;
		no-windows)
			_hcom_command_error "$command_name" 'open a Ghostty terminal first.'
			return 1
			;;
		'')
			_hcom_command_error "$command_name" 'could not read the focused Ghostty pane.'
			return 1
			;;
	esac

	print -r -- "$terminal_id"
}

# Reads an optional leading `--team <label>` and sets `reply` to the label, which is
# empty when none was given, followed by the remaining arguments. Prints the caller's
# usage and returns 1 when the label is missing or invalid.
#
# @param  {string}  command_name
#     Public command name used in validation errors.
# @param  {string}  usage
#     Usage line to print when the label is missing or invalid.
# @param  {string}  ...
#     Launcher arguments, optionally starting with --team and its label.
_hcom_parse_labelled_args() {
	local command_name="$1"  # Public command name used in validation errors.
	local usage="$2"  # Caller-specific usage line.
	local team_label=""  # Optional label for the team being launched.
	shift 2
	reply=()

	if [[ "${1:-}" == --team ]]; then
		if (( $# < 2 )); then
			_hcom_command_error "$command_name" '--team requires a label.'
			printf '%s\n' "$usage" >&2
			return 1
		fi

		team_label="$2"
		if ! _hcom_validate_team_label "$team_label" "$command_name"; then
			printf '%s\n' "$usage" >&2
			return 1
		fi

		shift 2
	fi

	reply=("$team_label" "$@")
}

# Validates a launcher's prompt template file, then returns its contents with one
# placeholder replaced by a shell-quoted value. Returns 1 if the file is missing or
# unreadable, after printing an error prefixed with the caller's command name.
#
# @param  {string}  command_name
#     Public command name to prefix in the file-not-found/unreadable error.
# @param  {string}  prompt_file
#     Prompt template file to validate and read.
# @param  {string}  placeholder
#     Placeholder token to replace in the prompt template.
# @param  {string}  placeholder_value
#     Value to shell-quote and substitute for the placeholder.
_hcom_workflow_prompt() {
	local command_name="$1"  # Public command name to prefix in prompt-file errors.
	local prompt_file="$2"  # Prompt template file to validate and read.
	local placeholder="$3"  # Placeholder token to replace in the prompt template.
	local placeholder_value="$4"  # Value to shell-quote and substitute for the placeholder.

	if [[ ! -f "$prompt_file" ]]; then
		printf '%s: prompt file not found: %s\n' "$command_name" "$prompt_file" >&2
		return 1
	fi

	if [[ ! -r "$prompt_file" ]]; then
		printf '%s: prompt file is not readable: %s\n' "$command_name" "$prompt_file" >&2
		return 1
	fi

	local prompt_template="$(<"$prompt_file")"  # Prompt template contents before substitution.
	local quoted_placeholder_value="${(q)placeholder_value}"  # Shell-quoted value to insert into the prompt.

	print -r -- "${prompt_template//${placeholder}/$quoted_placeholder_value}"
}

# Opens panes beside the calling Rex pane and starts a command in each one.
# Each pane is described by five arguments: the pane to split (0 for the caller,
# 1 for the first new pane, and so on), the side to open on, the new pane's share
# of the split as a percentage, its label, and the command to run in it.
# Panes already opened stay open when a later one fails.
#
# @param  {string}  command_name
#     Public command named in a layout error.
# @param  {string}  working_directory
#     Directory every new pane starts in.
# @param  {string}  ...
#     Five arguments per new pane: parent index, side, percentage, label and command.
_hcom_workflow_launch_rex_layout() {
	local command_name="$1"  # Public command named in a layout error.
	local working_directory="$2"  # Directory every new pane starts in.
	shift 2
	local parent_index  # Position in pane_blocks of the pane to split.
	local new_block  # ID of the pane just opened.
	local -a pane_blocks=("$REX_BLOCK")  # The calling pane followed by each new pane.

	if (( $# % 5 != 0 )); then
		_hcom_command_error "$command_name" 'each Rex layout pane needs five arguments.'
		return 1
	fi

	while (( $# > 0 )); do
		parent_index="$1"

		if ! new_block="$(_hcom_workflow_open_rex_pane "${pane_blocks[$((parent_index + 1))]}" "$2" "$3" "$4" "$5" "$working_directory")"; then
			_hcom_command_error "$command_name" "could not set up the $4 pane in Rex."
			return 1
		fi

		pane_blocks+=("$new_block")
		shift 5
	done
}

# Splits a Rex pane, starts a command in the new pane and prints the new pane's ID.
# The new pane does not take focus, so the caller's agent keeps the keyboard.
#
# @param  {string}  parent_block
#     Rex pane to split.
# @param  {string}  split_direction
#     Side of the parent pane the new pane opens on, such as right or below.
# @param  {string}  pane_percentage
#     Percentage of the split given to the new pane.
# @param  {string}  pane_label
#     Label shown on the new pane.
# @param  {string}  launch_command
#     Shell command typed into the new pane and run.
# @param  {string}  working_directory
#     Directory the new pane starts in.
_hcom_workflow_open_rex_pane() {
	local parent_block="$1"  # Rex pane to split.
	local split_direction="$2"  # Side of the parent pane the new pane opens on.
	local pane_percentage="$3"  # Percentage of the split given to the new pane.
	local pane_label="$4"  # Label shown on the new pane.
	local launch_command="$5"  # Shell command typed into the new pane and run.
	local working_directory="$6"  # Directory the new pane starts in.
	local split_json  # Rex's reply to the split, which holds the new pane's ID.
	local new_block  # ID of the new pane.

	split_json="$(command rex split -s "$REX_SESSION" -b "$parent_block" --split="$split_direction" --ratio "$pane_percentage" --label "$pane_label" --focus=false -c "$working_directory" --json)" || return 1
	new_block="$(jq -er '.block_ids[0]' <<<"$split_json")" || return 1

	_hcom_workflow_type_rex_command "$REX_SESSION" "$new_block" "$launch_command" || return 1

	print -r -- "$new_block"
}

# Types a command into a Rex pane and presses enter.
#
# @param  {string}  session_id
#     Rex session containing the pane.
# @param  {string}  block_id
#     Pane that receives the command.
# @param  {string}  launch_command
#     Exact shell command to type and submit.
_hcom_workflow_type_rex_command() {
	local session_id="$1"  # Rex session containing the pane.
	local block_id="$2"  # Pane that receives the command.
	local launch_command="$3"  # Shell command typed into the pane.

	command rex send -s "$session_id" -b "$block_id" "$launch_command" || return 1
	command rex send-key -s "$session_id" -b "$block_id" enter
}

# Runs the given Ghostty layout AppleScript, passing it the command to type into
# the pane it creates and the ID of the pane that ran the launcher.
#
# @param  {string}  layout_script
#     Path to the AppleScript file that creates the Ghostty layout.
# @param  {string}  launch_command
#     Shell command to type into the pane the script creates.
# @param  {string}  origin_terminal_id
#     Ghostty pane that ran the launcher.
_hcom_workflow_launch_layout() {
	local layout_script="$1"  # Path to the AppleScript file that creates the layout.
	local launch_command="$2"  # Shell command to type into the pane the script creates.
	local origin_terminal_id="$3"  # Ghostty pane that ran the launcher.

	/usr/bin/osascript "$layout_script" "$launch_command" "$origin_terminal_id"
}
