# Basic agent CLI aliases and Agents-repo setup shortcuts.

# Keep Claude Code in the normal terminal buffer for native selection and scrollback.
export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1

export VISUAL="zed --wait"
export EDITOR="$VISUAL"

# @desc  Run Codex on the account with more quota headroom
# @cat   agent
#
# Runs Codex on whichever of the two accounts has more quota headroom, matching what
# hcom:team gives its orchestrator. A session with a single role is doing the orchestrator's
# job, which is the heavier of the two roles the allocator assigns.
#
# An account already chosen by hand, through acct2 or an inherited CODEX_HOME, is left
# alone. A failed quota probe falls back to the default account and launches anyway, because
# stopping a single session to ask would cost more than the imbalance it avoids.
#
# @param  {string}  arguments
#     Optional arguments forwarded to Codex.
codex() {
	if [[ -n "${CODEX_HOME:-}" ]]; then
		command codex "$@"
		return
	fi

	local account_directory  # Config directory for the second account; empty on the default account.
	account_directory="$(_hcom_quota_account_directory codex)"

	if [[ -n "$account_directory" ]]; then
		CODEX_HOME="$account_directory" command codex "$@"
	else
		command codex "$@"
	fi
}
# @desc  Run Claude in auto-mode on the account with more quota headroom
# @cat   agent
#
# Runs Claude in auto-mode on whichever of the two accounts has more quota headroom, matching
# what hcom:team gives its orchestrator. A session with a single role is doing the
# orchestrator's job, which is the heavier of the two roles the allocator assigns.
#
# An account already chosen by hand, through acct2 or an inherited CLAUDE_CONFIG_DIR, is left
# alone. A failed quota probe falls back to the default account and launches anyway, because
# stopping a single session to ask would cost more than the imbalance it avoids.
#
# Reading Claude's quota costs a small Claude call, so the probe's cached reading does most of
# the work here.
#
# @param  {string}  arguments
#     Optional arguments forwarded to Claude.
claude() {
	if [[ -n "${CLAUDE_CONFIG_DIR:-}" ]]; then
		command claude --permission-mode auto "$@"
		return
	fi

	local account_directory  # Config directory for the second account; empty on the default account.
	account_directory="$(_hcom_quota_account_directory claude)"

	if [[ -n "$account_directory" ]]; then
		CLAUDE_CONFIG_DIR="$account_directory" command claude --permission-mode auto "$@"
	else
		command claude --permission-mode auto "$@"
	fi
}
# @desc  Run any command under the second Claude/Codex account (e.g. acct2 claude, acct2 team)
# @cat   agent
acct2() {
	# "$@" bypasses alias expansion (aliases only expand in command
	# position while a line is parsed), so short aliases like `team` or
	# `ho` would otherwise silently fall through or drop their flags.
	# Expand one level of alias manually before dispatching.
	local head="$1"
	shift
	if (( ${+aliases[$head]} )); then
		local -a expanded
		expanded=("${(z)aliases[$head]}")
		set -- "${expanded[@]}" "$@"
	else
		set -- "$head" "$@"
	fi

	CLAUDE_CONFIG_DIR="$HOME/.claude-2" CODEX_HOME="$HOME/.codex-2" HCOM_ACCOUNT=2 "$@"
}

# @desc  Run any command under the default Claude/Codex account (e.g. acct1 claude, acct1 team)
# @cat   agent
#
# Naming the default account's directories stops the launchers from picking an account by
# quota headroom, the same way acct2 does for the second account.
acct1() {
	# Expand one level of alias by hand, for the same reason as acct2.
	local head="$1"
	shift
	if (( ${+aliases[$head]} )); then
		local -a expanded
		expanded=("${(z)aliases[$head]}")
		set -- "${expanded[@]}" "$@"
	else
		set -- "$head" "$@"
	fi

	CLAUDE_CONFIG_DIR="$HOME/.claude" CODEX_HOME="$HOME/.codex" HCOM_ACCOUNT=default "$@"
}
# @desc  Open the current AGENTS.md file
# @cat   agent
alias agents="zed AGENTS.md"

# @desc  Set up agent files (Claude + Codex) globally, for both accounts
# @cat   agents
agents:setup:global() {
	"$HOME/Dev/Configuration/Agents/scripts/setup-global.sh" --both "$@"
	"$HOME/Dev/Configuration/Agents/scripts/setup-global.sh" --both \
		--claude-dir "$HOME/.claude-2" --codex-dir "$HOME/.codex-2" "$@"
}
# @desc  Set up agent files (Claude + Codex) for the current project
# @cat   agents
alias agents:setup="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --both"
# @desc  Initialise WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --write-workspace"
# @desc  Force-regenerate WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace:force="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --force-workspace"
# @desc  Inspect agent token usage
# @cat   agents
alias agents:usage='python3 /Users/lewis/Dev/Configuration/Agents/scripts/audit/usage.py'
