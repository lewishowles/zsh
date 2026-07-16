ZSH_CONFIG_ROOT="${ZSH_CONFIG_ROOT:-$HOME/Dev/Configuration/zsh}"

source "$ZSH_CONFIG_ROOT/environment.zsh"

# Aliases & helpers — sources every aliases.*.zsh in sorted order.
# Drop a new file in and it's picked up automatically; private/optional files
# (e.g. aliases.external.zsh) simply don't error when absent.
for f in "$ZSH_CONFIG_ROOT"/aliases.*.zsh(N); do
    source "$f"
done

# Settings for ZSH and Oh My ZSH
source "$ZSH_CONFIG_ROOT/oh-my-zsh-settings.zsh"
# Bun completions
source "$ZSH_CONFIG_ROOT/bun-settings.zsh"

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion
