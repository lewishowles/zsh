# Shared helpers for the hcom plan and insights-review launchers.

# Returns a peer tag combining a caller-supplied prefix with a sanitised pair ID.
# Reused by launchers that need two peers (e.g. Claude and Codex) sharing one tag.
#
# @param  {string}  prefix
#     Prefix identifying which workflow the peer belongs to.
# @param  {string}  peer_id
#     Optional. Pair ID shared with the peer's counterpart; generated when omitted.
_hcom_workflow_peer_tag() {
	local prefix="$1"  # Prefix identifying which workflow the peer belongs to.
	local peer_id="${2:-$(date -u +%Y%m%dT%H%M%SZ)-$$-${RANDOM}}"  # Pair ID, generated when the caller omits one.

	peer_id="${peer_id//[^[:alnum:]_.-]/-}"
	print -r -- "${prefix}-${peer_id}"
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
