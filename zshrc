ZSH_CONFIG_ROOT="${ZSH_CONFIG_ROOT:-$HOME/Dev/Configuration/zsh}"

source "$ZSH_CONFIG_ROOT/environment.zsh"

# Aliases & helpers — sources every aliases.*.zsh in sorted order.
# Drop a new file in and it's picked up automatically; private/optional files
# (e.g. aliases.external.zsh) simply don't error when absent.
for f in "$ZSH_CONFIG_ROOT"/aliases.*.zsh(N); do
    source "$f"
done

# Settings for Zsh and Oh My Zsh.
source "$ZSH_CONFIG_ROOT/oh-my-zsh-settings.zsh"

# Bun completions.
source "$ZSH_CONFIG_ROOT/bun-settings.zsh"

export NVM_DIR="$HOME/.nvm"

# Load NVM.
[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"

# Load NVM shell completions.
[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"

# Smarter directory navigation.
eval "$(zoxide init zsh)"

# Fuzzy file, directory and history search.
eval "$(fzf --zsh)"

# Searchable, contextual shell history.
eval "$(atuin init zsh --disable-up-arrow --disable-ai)"

# Shell hooks.
for f in "$ZSH_CONFIG_ROOT"/hooks/*.zsh(N); do
    source "$f"
done

# Prompt.
eval "$(starship init zsh)"
