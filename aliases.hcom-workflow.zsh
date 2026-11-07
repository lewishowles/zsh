# Shared helpers for the hcom team, plan, learning, and insights-review launchers.

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

# Opens new panes by splitting the calling Rex pane or one opened earlier in the
# layout, and starts a command in each one.
# Each pane is described by five arguments: the pane to split (0 for the caller,
# 1 for the first new pane, and so on), the side to open on, the new pane's share
# of the split as a percentage, its label, and the command to run in it.
# The whole layout is checked before any pane opens, and no command starts until
# every pane is open. Panes already opened stay open, and idle, when a later
# split fails.
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
	local parent_index  # Number of the pane this entry splits, where 0 is the caller.
	local new_block  # ID of the pane just opened.
	local -a pane_blocks=("$REX_BLOCK")  # The calling pane followed by each new pane.
	local -a opened_panes=()  # The ID, label and command of each opened pane, in layout order.

	_hcom_workflow_check_rex_layout "$command_name" "$@" || return 1

	while (( $# > 0 )); do
		parent_index="$1"

		if ! new_block="$(_hcom_workflow_open_rex_pane "${pane_blocks[$((parent_index + 1))]}" "$2" "$3" "$4" "$working_directory")"; then
			_hcom_command_error "$command_name" "could not set up the $4 pane in Rex."
			return 1
		fi

		pane_blocks+=("$new_block")
		opened_panes+=("$new_block" "$4" "$5")
		shift 5
	done

	_hcom_workflow_start_rex_commands "$command_name" "${opened_panes[@]}"
}

# Refuses a Rex layout with a pane that has fewer than five arguments, a parent
# that is not the caller or an earlier pane, an unknown side, or a percentage
# outside 1 to 99.
#
# @param  {string}  command_name
#     Public command named in a layout error.
# @param  {string}  ...
#     Five arguments per new pane: parent index, side, percentage, label and command.
_hcom_workflow_check_rex_layout() {
	local command_name="$1"  # Public command named in a layout error.
	shift
	local pane_number=1  # Number of the pane being checked; earlier panes have smaller numbers.
	local parent_index  # Number of the pane this entry splits, where 0 is the caller.

	if (( $# % 5 != 0 )); then
		_hcom_command_error "$command_name" 'each Rex layout pane needs five arguments.'
		return 1
	fi

	while (( $# > 0 )); do
		parent_index="$1"
		# Refuse a number with more digits than the pane count before comparing,
		# so zsh never has to convert a huge number.
		if [[ ! "$parent_index" =~ '^(0|[1-9][0-9]*)$' ]] || (( ${#parent_index} > ${#pane_number} )) || (( parent_index >= pane_number )); then
			_hcom_command_error "$command_name" "invalid Rex layout parent for the $4 pane: $parent_index."
			return 1
		fi

		case "$2" in
			right|left|above|below) ;;
			*)
				_hcom_command_error "$command_name" "invalid Rex layout side for the $4 pane: $2."
				return 1
				;;
		esac

		if [[ ! "$3" =~ '^[1-9][0-9]?$' ]]; then
			_hcom_command_error "$command_name" "invalid Rex layout percentage for the $4 pane: $3."
			return 1
		fi

		(( pane_number++ ))
		shift 5
	done
}

# Starts the command in each opened Rex pane, in layout order.
# Stops at the first pane that cannot be started, so later panes stay idle.
#
# @param  {string}  command_name
#     Public command named in a launch error.
# @param  {string}  ...
#     Three arguments per pane: block ID, label and command.
_hcom_workflow_start_rex_commands() {
	local command_name="$1"  # Public command named in a launch error.
	shift

	while (( $# > 0 )); do
		if ! _hcom_workflow_type_rex_command "$REX_SESSION" "$1" "$3"; then
			_hcom_command_error "$command_name" "could not start the $2 pane in Rex."
			return 1
		fi
		shift 3
	done
}

# Splits a Rex pane and prints the new pane's ID.
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
# @param  {string}  working_directory
#     Directory the new pane starts in.
_hcom_workflow_open_rex_pane() {
	local parent_block="$1"  # Rex pane to split.
	local split_direction="$2"  # Side of the parent pane the new pane opens on.
	local pane_percentage="$3"  # Percentage of the split given to the new pane.
	local pane_label="$4"  # Label shown on the new pane.
	local working_directory="$5"  # Directory the new pane starts in.
	local split_json  # Rex's reply to the split, which holds the new pane's ID.
	local new_block  # ID of the new pane.

	split_json="$(command rex split -s "$REX_SESSION" -b "$parent_block" --split="$split_direction" --ratio "$pane_percentage" --label "$pane_label" --focus=false -c "$working_directory" --json)" || return 1
	new_block="$(jq -er '.block_ids[0]' <<<"$split_json")" || return 1

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

