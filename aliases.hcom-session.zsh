# hcom session management.

# Session management

# Resolves a bare or role-prefixed hcom name and prints its name, tag, and role.
#
# @param  {string}  raw_name
#     The active or stopped agent name, optionally prefixed by its role.
_hcom_resolve_agent() {
	local raw_name="$1"
	local name="${raw_name##*-}"
	local tag role
	tag="$(_hcom_resolve_agent_tag "$name")"
	role="${tag##*-}"
	print -r -- "$name"
	print -r -- "$tag"
	print -r -- "$role"
}

# @desc  Start a fresh reviewer and announce it to the project orchestrator
# @cat   hcom
# Starts the normal reviewer role in the current directory without restoring the stopped Claude session.
#
# @param  {string}  name
#     The stopped reviewer name or role-prefixed shorthand.
# @param  {string}  initial_prompt
#     Optional task for the fresh reviewer after it announces itself.
hcom-restart-reviewer() {
	local raw_name="$1"
	shift

	if [[ -z "$raw_name" ]] || [[ $# -gt 1 ]]; then
		printf 'hcom-restart-reviewer: usage: hcom-restart-reviewer <name> [initial-prompt]\n' >&2
		return 1
	fi

	local -a resolved_agent
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"
	local tag="${resolved_agent[2]:-}"
	local role="${resolved_agent[3]:-}"

	if [[ -z "$tag" ]]; then
		printf 'hcom-restart-reviewer: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	if [[ "$role" != "reviewer" ]]; then
		printf 'hcom-restart-reviewer: %s is a %s, not a reviewer\n' "$name" "$role" >&2
		return 1
	fi

	local orchestrator_tag="${tag%-reviewer}-orchestrator"
	local -a prompt_lines
	prompt_lines=(
		"Before any other work, use the Bash tool to run this command, replacing YOUR_HCOM_NAME with your assigned hcom name:"
		"hcom send @${orchestrator_tag}- --name YOUR_HCOM_NAME -- \"Fresh replacement reviewer ready. Original reviewer: ${raw_name}.\""
	)

	if [[ -n "${1:-}" ]]; then
		prompt_lines+=("" "After announcing yourself, do this task:" "$1")
	else
		prompt_lines+=("" "Then wait for the orchestrator's task.")
	fi

	local launch_prompt
	launch_prompt="$(print -rl -- "${prompt_lines[@]}")"

	printf 'Starting a fresh reviewer for %s; it will announce itself to @%s.\n' "$name" "$orchestrator_tag"
	hcom-reviewer "$PWD" "$launch_prompt"
}

# @desc  Resume a stopped hcom agent by name (hcom r already replays its stored model/tag/role prompt)
# @cat   hcom
hcom-resume() {
	local raw_name="$1"
	shift

	if [[ -z "$raw_name" ]]; then
		printf 'hcom-resume: usage: hcom-resume <name> [tool-args...]\n' >&2
		return 1
	fi

	local -a resolved_agent
	resolved_agent=("${(@f)$(_hcom_resolve_agent "$raw_name")}")
	local name="${resolved_agent[1]:-}"
	local tag="${resolved_agent[2]:-}"
	local role="${resolved_agent[3]:-}"

	if [[ -z "$tag" ]]; then
		printf 'hcom-resume: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	printf 'Resuming %s (role: %s, tag: %s)\n' "$name" "$role" "$tag"
	command hcom r "$name" "$@"
}
