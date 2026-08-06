# hcom source-learning launchers.

_hcom_launch_learning_scout_claude() {
	_hcom_launch_configured_role scout-learn-claude "$@"
}

_hcom_launch_learning_scout_codex() {
	_hcom_launch_configured_role scout-learn-codex "$@"
}

# Writes the source input to a scratch file and derives the learner/Scout
# tags and initial prompts, so the full source text never enters an agent's
# startup prompt directly.
#
# @param  {string}  command_name
#     The calling command, used in error output.
# @param  {string}  provider
#     "claude" or "codex", used to select the matching learner/Scout tags.
# @param  {string}  source_input
#     The raw URL or pasted text to route to the learner and Scout.
# @note
#     Sets the global $reply array to (source_path learner_tag scout_tag
#     learner_prompt scout_prompt) on success, following the zsh builtin
#     convention for returning multiple values without a subshell.
_hcom_learning_context() {
	local command_name="$1"
	local provider="$2"
	local source_input="$3"
	local role_file scratch_directory source_path repository_tag
	local learner_tag scout_tag learner_prompt scout_prompt

	for role_file in learner.md scout.md; do
		if [[ ! -f "$HCOM_ROLE_DIR/$role_file" ]]; then
			printf '%s: role prompt not found: %s\n' "$command_name" "$HCOM_ROLE_DIR/$role_file" >&2
			return 1
		fi
	done

	scratch_directory="$(mktemp -d "${TMPDIR:-/tmp}/hcom-learn.XXXXXX")" || {
		printf '%s: could not create a temporary source directory\n' "$command_name" >&2
		return 1
	}

	source_path="$scratch_directory/source.txt"
	if ! print -rn -- "$source_input" > "$source_path"; then
		printf '%s: could not write the temporary source file: %s\n' "$command_name" "$source_path" >&2
		return 1
	fi

	repository_tag="$(_hcom_scoped_tag "$PWD")" || return 1
	learner_tag="${repository_tag}-learner-${provider}"
	scout_tag="${repository_tag}-scout-learn-${provider}"
	learner_prompt="Use project-learn-from-source to analyse the source at ${(q)source_path}. Route source extraction and one bounded, batched packet of local factual checks through your exact Scout @${scout_tag}. Use the indexed scratch-file handoff from teams/hcom/roles/learner.md. Retain all adopt/adapt/reject judgement here, produce the project-learn-from-source response, and stop after the analysis."
	scout_prompt="Wait for a bounded request from the learner @${learner_tag}. The source input is at ${(q)source_path}. Use the indexed scratch-file handoff from teams/hcom/roles/learner.md for source extraction. Return facts only and leave all adopt/adapt/reject judgement to the learner."
	reply=("$source_path" "$learner_tag" "$scout_tag" "$learner_prompt" "$scout_prompt")
}

# @desc  Start a Claude source-learning learner and its dedicated Scout
# @cat   hcom
function hcom-learn-claude() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-learn-claude: usage: hcom-learn-claude <url-or-text>\n' >&2
		return 1
	fi

	local -a learning_context
	_hcom_learning_context hcom-learn-claude claude "$1" || return 1
	learning_context=("${reply[@]}")

	local working_directory="$PWD"
	local scout_command="_hcom_launch_learning_scout_claude ${(q)working_directory} ${(q)learning_context[5]}"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-learn.applescript" "$scout_command"
	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		printf 'hcom-learn-claude: layout command failed: %s\n' "$scout_command" >&2
		return "$osascript_exit_code"
	fi

	_hcom_launch_configured_role learner-claude "$working_directory" "${learning_context[4]}"
}

# @desc  Start a Codex source-learning learner and its dedicated Scout
# @cat   hcom
function hcom-learn-codex() {
	if [[ $# -ne 1 ]]; then
		printf 'hcom-learn-codex: usage: hcom-learn-codex <url-or-text>\n' >&2
		return 1
	fi

	local -a learning_context
	_hcom_learning_context hcom-learn-codex codex "$1" || return 1
	learning_context=("${reply[@]}")

	local working_directory="$PWD"
	local scout_command="_hcom_launch_learning_scout_codex ${(q)working_directory} ${(q)learning_context[5]}"

	/usr/bin/osascript "$ZSH_CONFIG_ROOT/scripts/hcom-learn.applescript" "$scout_command"
	local osascript_exit_code=$?

	if (( osascript_exit_code != 0 )); then
		printf 'hcom-learn-codex: layout command failed: %s\n' "$scout_command" >&2
		return "$osascript_exit_code"
	fi

	_hcom_launch_configured_role learner-codex "$working_directory" "${learning_context[4]}"
}
