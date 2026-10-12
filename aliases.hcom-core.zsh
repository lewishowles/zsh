# Shared hcom launch helpers and tag resolution.

AGENTS_CONFIG_ROOT="${AGENTS_CONFIG_ROOT:-${ZSH_CONFIG_ROOT:h}/Agents}"
HCOM_ROLE_DIR="${HCOM_ROLE_DIR:-$AGENTS_CONFIG_ROOT/teams/hcom/roles}"

# Core launch helpers

# Prints one option error line to stderr, with a muted command prefix and the
# words the user should act on highlighted. Colour is only used when stderr is
# a terminal and NO_COLOR is unset. cli-style checks stdout, which is captured
# here, so colour is forced once stderr has passed that check.
#
# @param  {string}  command_name
#     The public command that rejected the option.
# @param  {string}  ...
#     Message segments, alternating plain and highlighted text and starting
#     with plain text. Pass an empty first segment to highlight the opening word.
_hcom_team_option_error_line() {
	local command_name="$1"  # Command prefix shown before the error.
	shift
	local segment  # Current message segment.
	local highlight=0  # Whether the current segment is a word the user should act on.

	if [[ ! -t 2 || -n "${NO_COLOR:-}" ]]; then
		printf '%s: ' "$command_name" >&2
		printf '%s' "$@" >&2
		printf '\n' >&2
		return
	fi

	printf '%s' "$(FORCE_COLOR=1 cli_style_span "$command_name:" muted --weight normal)" >&2
	printf ' ' >&2
	for segment in "$@"; do
		if (( highlight )); then
			printf '%s' "$(FORCE_COLOR=1 cli_style_span "$segment" info)" >&2
		else
			printf '%s' "$segment" >&2
		fi
		highlight=$(( 1 - highlight ))
	done
	printf '\n' >&2
}

# Prints the first line of an option error after one blank line. Print any
# further lines with _hcom_team_option_error_line, so the whole error has a
# single blank line above it.
#
# @param  {string}  command_name
#     The public command that rejected the option.
# @param  {string}  ...
#     Message segments passed to _hcom_team_option_error_line.
_hcom_team_option_error() {
	printf '\n' >&2
	_hcom_team_option_error_line "$@"
}

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
		_hcom_team_option_error "$command_name" 'invalid team label: ' "$team_label"
		_hcom_team_option_error_line "$command_name" 'use lowercase letters, numbers, and internal hyphens.'
		return 1
	fi
}

# Builds the account environment passed to fresh HCOM terminals.
#
# Prints shell-safe assignments for the active Claude and Codex account
# overrides. Returns success with an empty string when no override is set.
_hcom_account_environment() {
	local account_environment=""  # Quoted account assignments for a child terminal.

	[[ -n "${CLAUDE_CONFIG_DIR:-}" ]] && account_environment+="CLAUDE_CONFIG_DIR=${(q)CLAUDE_CONFIG_DIR} "
	[[ -n "${CODEX_HOME:-}" ]] && account_environment+="CODEX_HOME=${(q)CODEX_HOME} "

	print -r -- "$account_environment"
}

# Refuses a launch when a live agent already holds any of the given role tags,
# and names that agent. Also refuses when HCOM cannot list the live agents.
#
# @param  {string}  command_name
#     The public command named in errors.
#     Role launchers pass hcom to keep their existing plain message.
# @param  {string}  role_tags
#     Pipe-separated full role tags that the launch would use.
_hcom_refuse_live_tags() {
	local command_name="$1"  # Public command responsible for the launch.
	local role_tags="$2"  # Full role tags that the launch would use.
	local agents_json  # Current live agent records from HCOM.
	local tag  # One role tag to check for a collision.
	local agent_name  # The name of the live agent that already holds the tag.
	local -a exact_tags  # Tags split for individual membership checks.

	if ! agents_json="$(command hcom list --json 2>/dev/null)" || ! jq -e 'type == "array"' >/dev/null 2>&1 <<<"$agents_json"; then
		if [[ "$command_name" == hcom ]]; then
			printf 'hcom: cannot check which agents are live.\n' >&2
		else
			_hcom_team_option_error "$command_name" 'cannot check which agents are live.'
		fi
		return 1
	fi

	exact_tags=("${(@s:|:)role_tags}")
	for tag in "${exact_tags[@]}"; do
		if jq -e --arg tag "$tag" 'any(.[]; .tag == $tag)' >/dev/null 2>&1 <<<"$agents_json"; then
			agent_name="$(jq -r --arg tag "$tag" 'first(.[] | select(.tag == $tag) | .name) // empty' <<<"$agents_json")"
			[[ -n "$agent_name" ]] || agent_name='a live agent'
			if [[ "$command_name" == hcom ]]; then
				printf 'hcom: %s already holds %s.\n' "$agent_name" "$tag" >&2
			else
				_hcom_team_option_error "$command_name" '' "$agent_name" ' already holds ' "$tag" '.'
			fi
			return 1
		fi
	done
}

# Launches one role in the current terminal, using the selected project directory.
#
# `--hcom-system-prompt` doesn't reach the agent's actual system prompt (verified: the
# role text never appears in the transcript, only hcom's own onboarding block does).
# Deliver the role prompt through each tool's native mechanism instead: claude's
# `--append-system-prompt`, codex's `HCOM_CODEX_SYSTEM_PROMPT` env var.
#
# Repeat `--role-file` to give the role several prompt files. Their text is
# combined in the order given, separated by blank lines.
#
# Stops without launching when a live agent already holds the role's full tag,
# because a second agent with the same tag blocks every message sent to that role.
#
# Usage:
#   _hcom_launch_role \
#     --tool claude \
#     --tag orchestrator \
#     --model sonnet \
#     --role-file orchestrator.md \
#     [--role-file learner.md ...] \
#     [--working-dir /path] \
#     [--initial-prompt "..."] \
#     [--thinking medium]
_hcom_launch_role() {
	local tool="" tag="" model=""
	local working_directory="$PWD" initial_prompt="" thinking_effort=""
	local team_label="${HCOM_TEAM_LABEL:-}"
	local -a role_files  # Role prompt files to combine, in the order given.

	while [[ $# -gt 0 ]]; do
		case "$1" in
			--tool) tool="$2"; shift 2 ;;
			--tag) tag="$2"; shift 2 ;;
			--model) model="$2"; shift 2 ;;
			--role-file) role_files+=("$2"); shift 2 ;;
			--working-dir) working_directory="$2"; shift 2 ;;
			--initial-prompt) initial_prompt="$2"; shift 2 ;;
			--thinking) thinking_effort="$2"; shift 2 ;;
			*) printf 'hcom: unknown option: %s\n' "$1" >&2; return 1 ;;
		esac
	done

	# Validate required parameters
	if [[ -z "$tool" ]] || [[ -z "$tag" ]] || [[ -z "$model" ]] || [[ -z "${role_files[1]}" ]]; then
		printf 'hcom: missing required parameters\n' >&2
		return 1
	fi

	if [[ ! -d "$working_directory" ]]; then
		printf 'hcom: working directory not found: %s\n' "$working_directory" >&2
		return 1
	fi

	local -a role_prompts  # The text of each role file, in the order given.
	local role_file role_path  # The role file being read and its full path.
	for role_file in "${role_files[@]}"; do
		role_path="$HCOM_ROLE_DIR/$role_file"
		if [[ ! -f "$role_path" ]]; then
			printf 'hcom: role prompt not found: %s\n' "$role_path" >&2
			return 1
		fi

		role_prompts+=("$(<"$role_path")")
	done

	local role_prompt="${(pj:\n\n:)role_prompts}"  # The role files' text, separated by blank lines.
	local repository_tag scoped_tag
	repository_tag="$(_hcom_scoped_tag hcom "$working_directory")" || return 1
	scoped_tag="${repository_tag}-${tag}"

	if [[ -n "$team_label" ]]; then
		_hcom_validate_team_label "$team_label" hcom || return 1
		scoped_tag="${repository_tag}-${team_label}-${tag}"
	fi

	_hcom_refuse_live_tags hcom "$scoped_tag" || return 1

	_hcom_role_invoke "$tool" "$scoped_tag" "$model" "$working_directory" "$role_prompt" "$initial_prompt" "$thinking_effort"
}

# Assembles the hcom argument list from the resolved role settings and launches the
# agent with the tool-specific environment prefix.
#
# A solo role runs on whichever of the two accounts has more quota headroom, the same
# choice team makes for its orchestrator. The probe is skipped when an account is
# already chosen: by hand or acct2 (CODEX_HOME or CLAUDE_CONFIG_DIR set), or by team,
# which sets HCOM_ACCOUNT on every role it launches so a team's placement is never
# second-guessed. A failed quota probe falls back to the default account and launches anyway.
#
# @param  {string}  tool
#     Agent tool to launch, "codex" or "claude".
# @param  {string}  scoped_tag
#     Fully qualified hcom tag (repository, optional team label, then role).
# @param  {string}  model
#     Model identifier passed straight through to hcom.
# @param  {string}  working_directory
#     Directory the agent runs in.
# @param  {string}  role_prompt
#     Role instructions delivered as the agent's system prompt.
# @param  {string}  initial_prompt
#     Optional first message for the agent; omitted when empty.
# @param  {string}  thinking_effort
#     Optional reasoning effort passed to Claude; Codex uses its global default.
_hcom_role_invoke() {
	local tool="$1"  # Which agent to launch; selects the codex or claude branch.
	local scoped_tag="$2"  # Fully qualified hcom tag for the agent.
	local model="$3"  # Model identifier passed through to hcom.
	local working_directory="$4"  # Directory the agent runs in.
	local role_prompt="$5"  # Role instructions used as the system prompt.
	local initial_prompt="$6"  # Optional first message for the agent.
	local thinking_effort="$7"  # Optional reasoning effort for the agent.
	local -a hcom_arguments  # Assembled command line passed to hcom.
	local account_directory=""  # Config directory for the allocated account; empty when the default account is used.

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

	if [[ -n "$thinking_effort" && "$tool" != "codex" ]]; then
		hcom_arguments+=(--effort "$thinking_effort")
	fi

	if [[ -z "${CODEX_HOME:-}${CLAUDE_CONFIG_DIR:-}" && -z "${HCOM_ACCOUNT+x}" ]]; then
		account_directory="$(_hcom_quota_account_directory "$tool")"
	fi

	if [[ "$tool" = "codex" ]]; then
		if [[ -n "$account_directory" ]]; then
			CODEX_HOME="$account_directory" HCOM_TERMINAL=default HCOM_CODEX_SYSTEM_PROMPT="$role_prompt" command hcom "${hcom_arguments[@]}"
		else
			HCOM_TERMINAL=default HCOM_CODEX_SYSTEM_PROMPT="$role_prompt" command hcom "${hcom_arguments[@]}"
		fi
	else
		if [[ -n "$account_directory" ]]; then
			CLAUDE_CONFIG_DIR="$account_directory" HCOM_CLAUDE_ARGS='--permission-mode auto' HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
		else
			HCOM_CLAUDE_ARGS='--permission-mode auto' HCOM_TERMINAL=default command hcom "${hcom_arguments[@]}"
		fi
	fi
}

# Returns the repository portion of an hcom tag, or a task team's project tag.
#
# @param  {string}  command_name
#     The public command shown if the directory cannot form a tag.
#     Role launchers pass hcom to keep their existing plain message.
# @param  {string}  working_directory
#     The directory selected for the agent launch.
_hcom_scoped_tag() {
	local command_name="$1"  # Public command responsible for the tag.
	local working_directory="$2"  # Directory selected for the agent launch.
	# Task teams carry their Progress project slug into every role terminal.
	if [[ -n "${HCOM_TEAM_PROJECT_TAG:-}" ]]; then
		print -r -- "$HCOM_TEAM_PROJECT_TAG"
		return 0
	fi

	local directory_name="${working_directory:t}"
	local repository_tag

	repository_tag="$(print -r -- "$directory_name" | tr -cs '[:alnum:]' '-')"
	repository_tag="${repository_tag%-}"

	if [[ -z "$repository_tag" ]]; then
		if [[ "$command_name" == hcom ]]; then
			printf 'hcom: cannot derive a tag from directory: %s\n' "$working_directory" >&2
		else
			_hcom_team_option_error "$command_name" 'cannot derive a tag from directory: ' "$working_directory"
		fi
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
