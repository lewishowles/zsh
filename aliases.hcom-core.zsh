# Shared hcom launch helpers and tag resolution.

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

# Core launch helpers

# Checks that a team label is safe to include in an hcom tag.
#
# @param  {string}  team_label
#     The explicit label supplied for one team.
# @param  {string}  command_name
#     The public command name used in errors.
_hcom_validate_team_label() {
	local team_label="$1"
	local command_name="$2"

	if [[ -z "$team_label" ]] || [[ "$team_label" == -* ]] || [[ "$team_label" == *- ]] || [[ "$team_label" == *[^a-z0-9-]* ]]; then
		printf '%s: invalid team label: %s\n' "$command_name" "$team_label" >&2
		printf '%s: use lowercase letters, numbers, and internal hyphens.\n' "$command_name" >&2
		return 1
	fi
}

# Launches one role in the current terminal, using the selected project directory.
#
# `--hcom-system-prompt` doesn't reach the agent's actual system prompt (verified: the
# role text never appears in the transcript, only hcom's own onboarding block does).
# Deliver the role prompt through each tool's native mechanism instead: claude's
# `--append-system-prompt`, codex's `HCOM_CODEX_SYSTEM_PROMPT` env var.
#
# Usage:
#   _hcom_launch_role \
#     --tool claude \
#     --tag orchestrator \
#     --model sonnet \
#     --role-file orchestrator.md \
#     [--working-dir /path] \
#     [--initial-prompt "..."] \
#     [--thinking medium]
_hcom_launch_role() {
	local tool="" tag="" model="" role_file=""
	local working_directory="$PWD" initial_prompt="" thinking_effort=""
	local team_label="${HCOM_TEAM_LABEL:-}"

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--tool) tool="$2"; shift 2 ;;
			--tag) tag="$2"; shift 2 ;;
			--model) model="$2"; shift 2 ;;
			--role-file) role_file="$2"; shift 2 ;;
			--working-dir) working_directory="$2"; shift 2 ;;
			--initial-prompt) initial_prompt="$2"; shift 2 ;;
			--thinking) thinking_effort="$2"; shift 2 ;;
			*) printf 'hcom: unknown option: %s\n' "$1" >&2; return 1 ;;
		esac
	done

	# Validate required parameters
	if [[ -z "$tool" ]] || [[ -z "$tag" ]] || [[ -z "$model" ]] || [[ -z "$role_file" ]]; then
		printf 'hcom: missing required parameters\n' >&2
		return 1
	fi

	if [[ ! -d "$working_directory" ]]; then
		printf 'hcom: working directory not found: %s\n' "$working_directory" >&2
		return 1
	fi

	local role_path="$HCOM_ROLE_DIR/$role_file"
	if [[ ! -f "$role_path" ]]; then
		printf 'hcom: role prompt not found: %s\n' "$role_path" >&2
		return 1
	fi

	local role_prompt="$(<"$role_path")"
	local repository_tag scoped_tag
	repository_tag="$(_hcom_scoped_tag "$working_directory")" || return 1
	scoped_tag="${repository_tag}-${tag}"

	if [[ -n "$team_label" ]]; then
		_hcom_validate_team_label "$team_label" hcom || return 1
		scoped_tag="${repository_tag}-${team_label}-${tag}"
	fi

	local -a hcom_arguments
	hcom_arguments=(
		"$tool"
		--tag "$scoped_tag"
		--model "$model"
		--dir "$working_directory"
	)

	if [[ "$tool" != "codex" ]]; then
		hcom_arguments+=(--append-system-prompt "$role_prompt")
	fi

	[[ -n "$initial_prompt" ]] && hcom_arguments+=(--hcom-prompt "$initial_prompt")

	if [[ -n "$thinking_effort" ]]; then
		if [[ "$tool" = "codex" ]]; then
			hcom_arguments+=(--config "model_reasoning_effort=\"$thinking_effort\"")
		else
			hcom_arguments+=(--effort "$thinking_effort")
		fi
	fi

	if [[ "$tool" = "codex" ]]; then
		hcom_arguments+=(
			--config 'model_verbosity="low"'
			--config 'model_reasoning_summary="none"'
			--config 'hide_agent_reasoning=true'
		)
		HCOM_TERMINAL=default HCOM_CODEX_SYSTEM_PROMPT="$role_prompt" command hcom "${hcom_arguments[@]}"
	else
		HCOM_CLAUDE_ARGS='--permission-mode auto' HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
	fi
}

# Returns the repository portion of an hcom tag.
#
# @param  {string}  working_directory
#     The directory selected for the agent launch.
_hcom_scoped_tag() {
	local directory_name="${1:t}"
	local repository_tag

	repository_tag="$(print -r -- "$directory_name" | tr -cs '[:alnum:]' '-')"
	repository_tag="${repository_tag%-}"

	if [[ -z "$repository_tag" ]]; then
		printf 'hcom: cannot derive a tag from directory: %s\n' "$1" >&2
		return 1
	fi

	print -r -- "$repository_tag"
}

# Prints the tag for an active or recently stopped hcom agent.
#
# @param  {string}  name
#     The bare hcom agent name.
_hcom_resolve_agent_tag() {
	local name="$1"
	local details tag

	details="$(command hcom list -v "$name" 2>&1)"
	if [[ $? -ne 0 ]]; then
		details="$(command hcom list --stopped "$name" 2>&1)"
	fi

	tag="$(print -r -- "$details" | awk -F': *' '/^  Tag:/{print $2}')"
	print -r -- "$tag"
}
