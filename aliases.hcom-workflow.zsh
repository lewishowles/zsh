# Shared helpers for the hcom plan and insights-review launchers.

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
