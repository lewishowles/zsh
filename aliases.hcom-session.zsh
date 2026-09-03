# hcom session management.

# Session commands resolve agent names through the active and stopped hcom lists.

# Checks that a name is a well-formed hcom agent name: four lowercase letters in
# consonant-vowel-consonant-vowel order, such as meke, liti, or raba. Callers use
# this to reject a mistyped or role-only reference before it reaches an hcom list
# lookup.
#
# @param  {string}  name
#     The bare name left after any role prefix is stripped.
_hcom_is_cvcv_name() {
	local name="$1"  # Bare candidate name to test against the CVCV shape.

	[[ "$name" == [a-z][a-z][a-z][a-z] ]] || return 1
	[[ "$name" == [^aeiou][aeiou][^aeiou][aeiou] ]]
}

# Resolves a bare or role-prefixed hcom name and prints its name, tag, and role.
# Name resolution removes everything through the final hyphen, then checks the
# bare name is a well-formed CVCV agent name before any lookup. The lookup checks
# active agents first, then stopped agents only when the active lookup fails.
#
# @param  {string}  raw_name
#     The active or stopped agent name, optionally prefixed by its role.
#
# Prints the bare name, resolved tag, and role on separate lines. Prints nothing
# when the stripped name is not a valid agent name. Returns 1 with a stderr
# message for an invalid name. When a valid name has no match, it succeeds with
# an empty tag line so callers report the lookup miss themselves. Runs hcom list
# through _hcom_resolve_agent_tag without changing files or agent state.
_hcom_resolve_agent() {
	local raw_name="$1"  # Agent name supplied by the caller.
	local name="${raw_name##*-}"  # Bare name after removing any role prefix.
	local tag  # Tag returned by the active or stopped agent lookup.
	local role  # Role taken from the final segment of the resolved tag.

	if ! _hcom_is_cvcv_name "$name"; then
		printf "hcom: '%s' is not a valid agent name\n" "$name" >&2
		return 1
	fi

	tag="$(_hcom_resolve_agent_tag "$name")"
	role="${tag##*-}"
	print -r -- "$name"
	print -r -- "$tag"
	print -r -- "$role"
}

# @desc  Resume a stopped hcom agent by name (hcom r already replays its stored model/tag/role prompt)
# @cat   hcom
# Name resolution strips any role prefix, rejects a name that is not a
# well-formed CVCV agent name, then checks the active list first and the stopped
# list only when the active lookup fails.
#
# @param  {string}  name
#     The stopped agent name or role-prefixed shorthand.
# @param  {string}  tool_args
#     Optional arguments passed to hcom r.
#
# Prints the resolved agent and returns hcom r's status. Returns 1 when the name
# is malformed or when no active or recently stopped agent can be resolved.
# Resumes the resolved stopped agent through hcom r.
hcom:resume() {
	local raw_name="$1"  # Agent name or role-prefixed shorthand.
	shift

	if [[ -z "$raw_name" ]]; then
		printf 'hcom:resume: usage: hcom:resume <name> [tool-args...]\n' >&2
		return 1
	fi

	local -a resolved_agent  # Name, tag, and role returned by the resolver.
	if ! resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}"); then
		return 1
	fi

	local name="${resolved_agent[1]:-}"  # Bare name used for resume output and hcom r.
	local tag="${resolved_agent[2]:-}"  # Full repository-scoped agent tag.
	local role="${resolved_agent[3]:-}"  # Role parsed from the full agent tag.

	if [[ -z "$tag" ]]; then
		printf 'hcom:resume: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	printf 'Resuming %s (role: %s, tag: %s)\n' "$name" "$role" "$tag"
	command hcom r "$name" "$@"
}
