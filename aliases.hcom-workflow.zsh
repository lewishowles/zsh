# Shared helpers for the hcom plan, learning, and insights-review launchers.

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

# Runs the given Ghostty layout AppleScript, passing it the command to type into
# the pane it creates. Shared by launchers that open a dedicated peer pane.
#
# @param  {string}  layout_script
#     Path to the AppleScript file that creates the Ghostty layout.
# @param  {string}  launch_command
#     Shell command to type into the pane the script creates.
_hcom_workflow_launch_layout() {
	local layout_script="$1"  # Path to the AppleScript file that creates the layout.
	local launch_command="$2"  # Shell command to type into the pane the script creates.

	/usr/bin/osascript "$layout_script" "$launch_command"
}
