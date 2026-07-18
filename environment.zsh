export BUN_INSTALL="$HOME/.bun"
export PATH="$BUN_INSTALL/bin:$PATH"

if [[ -x "/opt/homebrew/bin/brew" ]]; then
	eval "$(/opt/homebrew/bin/brew shellenv)"
fi

export PATH="$HOME/.local/bin:$PATH"

[[ -r "$HOME/.vite-plus/env" ]] && source "$HOME/.vite-plus/env"

# cli-style Bash adapter — cli_style_status, cli_style_row, etc. for zsh functions.
[[ -r "$HOME/Dev/Repositories/Packages/cli-style/adapters/bash/cli-style.sh" ]] && \
	source "$HOME/Dev/Repositories/Packages/cli-style/adapters/bash/cli-style.sh"
