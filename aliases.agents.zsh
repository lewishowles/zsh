# hcom role launchers for manually managed Hyper tabs.

# @desc  Run Codex with shared configuration defaults
# @cat   agent
alias codex="codex";
# @desc  Run claude with auto-mode
# @cat   agent
alias claude="claude --permission-mode auto";

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

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

# @desc  Start the Orchestrator hcom role
# @cat   hcom
hcom-orchestrator() {
	_hcom_launch_role \
		--tool claude \
		--tag orchestrator \
		--model sonnet \
		--role-file orchestrator.md \
		--working-dir "${1:-$PWD}" \
		--initial-prompt "${2:-}"
}

# @desc  Start the Implementer hcom role
# @cat   hcom
hcom-implementer() {
	_hcom_launch_role \
		--tool codex \
		--tag implementer \
		--model gpt-5.6-terra \
		--role-file implementer.md \
		--thinking high \
		--working-dir "${1:-$PWD}" \
		--initial-prompt "${2:-}"
}

# @desc  Start the Reviewer hcom role
# @cat   hcom
hcom-reviewer() {
	_hcom_launch_role \
		--tool claude \
		--tag reviewer \
		--model sonnet \
		--role-file reviewer.md \
		--thinking high \
		--working-dir "${1:-$PWD}" \
		--initial-prompt "${2:-}"
}

# @desc  Start the Scout hcom role
# @cat   hcom
hcom-scout() {
	_hcom_launch_role \
		--tool codex \
		--tag scout \
		--model gpt-5.6-luna \
		--role-file scout.md \
		--thinking medium \
		--working-dir "${1:-$PWD}" \
		--initial-prompt "${2:-}"
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

	# Accepts a bare hcom name ("naru") or a role-prefixed shorthand ("orchestrator-naru");
	# hcom itself only ever resumes by the bare 4-letter name.
	local name="${raw_name##*-}"

	# `hcom list -v` only searches alive agents. A name worth resuming is stopped by
	# definition, so fall back to `hcom list --stopped` to find its tag.
	local details
	details="$(command hcom list -v "$name" 2>&1)"
	if [[ $? -ne 0 ]]; then
		details="$(command hcom list --stopped "$name" 2>&1)"
	fi

	local tag role
	tag="$(print -r -- "$details" | awk -F': *' '/^  Tag:/{print $2}')"

	if [[ -z "$tag" ]]; then
		printf 'hcom-resume: could not resolve %s (not alive or recently stopped)\n' "$name" >&2
		return 1
	fi

	role="${tag##*-}"
	printf 'Resuming %s (role: %s, tag: %s)\n' "$name" "$role" "$tag"
	command hcom r "$name" "$@"
}
