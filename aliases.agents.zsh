# Basic agent CLI aliases and Agents-repo setup shortcuts.

# Keep Claude Code in the normal terminal buffer for native selection and scrollback.
export CLAUDE_CODE_DISABLE_ALTERNATE_SCREEN=1

# @desc  Run Codex with shared configuration defaults
# @cat   agent
alias codex="codex"
# @desc  Run claude with auto-mode
# @cat   agent
alias claude="claude --permission-mode auto"

# @desc  Open the current PROGRESS.md file
# @cat   agent
alias progress="zed PROGRESS.md"
# @desc  Open the current AGENTS.md file
# @cat   agent
alias agents="zed AGENTS.md"

# @desc  Set up agent files (Claude + Codex) globally
# @cat   agents
alias agents:setup:global="$HOME/Dev/Configuration/Agents/scripts/setup-global.sh --both"
# @desc  Set up agent files (Claude + Codex) for the current project
# @cat   agents
alias agents:setup="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --both"
# @desc  Initialise WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --write-workspace"
# @desc  Force-regenerate WORKSPACE.md for the current project
# @cat   agents
alias agents:workspace:force="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --force-workspace"
