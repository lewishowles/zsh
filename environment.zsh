# A login interactive shell sources this file twice, from zprofile and then
# zshrc. This flag makes the second source a no-op so PATH doesn't gain a
# duplicate Bun entry and brew shellenv doesn't run again. Not exported, so
# each new shell that reads zprofile or zshrc still runs the setup for itself.
[[ -n "$_ZSH_ENVIRONMENT_LOADED" ]] && return
_ZSH_ENVIRONMENT_LOADED=1

export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if [[ -x "/opt/homebrew/bin/brew" ]]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
	export PATH="$HOME/.local/bin:$PATH"
fi

[[ -r "$HOME/.vite-plus/env" ]] && source "$HOME/.vite-plus/env"

# Claude Code initialises mouse tracking before it reads settings.json, so
# CLAUDE_CODE_DISABLE_MOUSE must be set here to keep native terminal text
# selection working.
export CLAUDE_CODE_DISABLE_MOUSE=1

# cli-style Bash adapter — cli_style_status, cli_style_row, etc. for zsh functions.
[[ -r "$HOME/Dev/Repositories/Packages/cli-style/adapters/bash/cli-style.sh" ]] && \
	source "$HOME/Dev/Repositories/Packages/cli-style/adapters/bash/cli-style.sh"
