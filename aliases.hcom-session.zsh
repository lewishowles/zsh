# hcom session management.

# Session commands resolve agent names through the active and stopped hcom lists.

# Resolves a bare or role-prefixed hcom name and prints its name, tag, and role.
# Name resolution removes everything through the final hyphen before looking up the
# bare name. The lookup checks active agents first, then stopped agents only when
# the active lookup fails; it does not validate the final CVCV name before lookup.
#
# @param  {string}  raw_name
#     The active or stopped agent name, optionally prefixed by its role.
# @output
#     Prints the bare name, resolved tag, and role on separate lines.
# @failure
#     Returns the lookup helper's status; an empty tag tells callers that no
#     active or recently stopped agent was found.
# @side-effects
#     Runs hcom list commands through _hcom_resolve_agent_tag without changing
#     files or agent state.
_hcom_resolve_agent() {
	local raw_name="$1"  # Agent name supplied by the caller.
	local name="${raw_name##*-}"  # Bare name after removing any role prefix.
	local tag  # Tag returned by the active or stopped agent lookup.
	local role  # Role taken from the final segment of the resolved tag.

	tag="$(_hcom_resolve_agent_tag "$name")"
	role="${tag##*-}"
	print -r -- "$name"
	print -r -- "$tag"
	print -r -- "$role"
}

# @desc  Start a fresh reviewer and announce it to the project orchestrator
# @cat   hcom
# Usage: hcom-restart-reviewer <name> [initial-prompt]
# Starts the normal reviewer role in the current directory without restoring the stopped Claude session.
#
# @param  {string}  name
#     The stopped reviewer name or role-prefixed shorthand.
# @param  {string}  initial_prompt
#     Optional task for the fresh reviewer after it announces itself.
# @output
#     Prints launch status and returns the reviewer launcher's status.
# @failure
#     Returns 1 for invalid arguments, an unresolved agent, a non-reviewer
#     role, or a missing prompt file.
# @side-effects
#     Starts a fresh reviewer process and passes it the optional task prompt.
hcom-restart-reviewer() {
	local raw_name="$1"  # Reviewer name or role-prefixed shorthand.
	shift

	if [[ -z "$raw_name" ]] || [[ $# -gt 1 ]]; then
		printf 'hcom-restart-reviewer: usage: hcom-restart-reviewer <name> [initial-prompt]\n' >&2
		return 1
	fi

	local -a resolved_agent  # Name, tag, and role returned by the resolver.
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"  # Bare name used for messages and launch.
	local tag="${resolved_agent[2]:-}"  # Full repository-scoped agent tag.
	local role="${resolved_agent[3]:-}"  # Role parsed from the full agent tag.

	if [[ -z "$tag" ]]; then
		printf 'hcom-restart-reviewer: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	if [[ "$role" != "reviewer" ]]; then
		printf 'hcom-restart-reviewer: %s is a %s, not a reviewer\n' "$name" "$role" >&2
		return 1
	fi

	local repository_tag="$(_hcom_scoped_tag "$PWD")" || return 1  # Current repository tag.
	local reviewer_scope="${tag%-reviewer}"  # Reviewer tag without its role suffix.
	local team_label=""  # Optional team label extracted from the reviewer scope.
	if [[ "$reviewer_scope" == "$repository_tag"-* ]]; then
		team_label="${reviewer_scope#"$repository_tag"-}"
	fi

	local orchestrator_tag="${tag%-reviewer}-orchestrator"  # Orchestrator that receives the announcement.
	local prompt_file="$ZSH_CONFIG_ROOT/prompts/hcom-restart-reviewer.md"  # Template for the fresh reviewer.
	if [[ ! -f "$prompt_file" ]]; then
		printf 'hcom-restart-reviewer: prompt file not found: %s\n' "$prompt_file" >&2
		return 1
	fi

	local prompt_template="$(<"$prompt_file")"  # Prompt template with its placeholders still present.
	prompt_template="${prompt_template//__ORCHESTRATOR_TAG__/$orchestrator_tag}"
	prompt_template="${prompt_template//__RAW_NAME__/$raw_name}"
	local -a prompt_lines  # Prompt lines with the task or wait instruction appended.
	prompt_lines=("${(@f)prompt_template}")

	if [[ -n "${1:-}" ]]; then
		prompt_lines+=("" "After announcing yourself, do this task:" "$1")
	else
		prompt_lines+=("" "Then wait for the orchestrator's task.")
	fi

	local launch_prompt  # Complete prompt passed to the fresh reviewer.
	launch_prompt="$(print -rl -- "${prompt_lines[@]}")"

	printf 'Starting a fresh reviewer for %s; it will announce itself to @%s.\n' "$name" "$orchestrator_tag"
	# Pass the optional team label through the launch environment for team-aware routing.
	HCOM_TEAM_LABEL="$team_label" hcom-reviewer "$PWD" "$launch_prompt"
}

# @desc  Resume a stopped hcom agent by name (hcom r already replays its stored model/tag/role prompt)
# @cat   hcom
# Name resolution strips any role prefix, checks the active list first, and
# checks the stopped list only when the active lookup fails. The name is not
# CVCV-validated before hcom performs that lookup.
#
# @param  {string}  name
#     The stopped agent name or role-prefixed shorthand.
# @param  {string}  tool_args
#     Optional arguments passed to hcom r.
# @output
#     Prints the resolved agent and returns hcom r's status.
# @failure
#     Returns 1 when no active or recently stopped agent can be resolved.
# @side-effects
#     Resumes the resolved stopped agent through hcom r.
hcom-resume() {
	local raw_name="$1"  # Agent name or role-prefixed shorthand.
	shift

	if [[ -z "$raw_name" ]]; then
		printf 'hcom-resume: usage: hcom-resume <name> [tool-args...]\n' >&2
		return 1
	fi

	local -a resolved_agent  # Name, tag, and role returned by the resolver.
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"  # Bare name used for resume output and hcom r.
	local tag="${resolved_agent[2]:-}"  # Full repository-scoped agent tag.
	local role="${resolved_agent[3]:-}"  # Role parsed from the full agent tag.

	if [[ -z "$tag" ]]; then
		printf 'hcom-resume: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	printf 'Resuming %s (role: %s, tag: %s)\n' "$name" "$role" "$tag"
	command hcom r "$name" "$@"
}
