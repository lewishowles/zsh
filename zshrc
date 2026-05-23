# Aliases & helpers (config first — defines colour vars used by others)
source ~/Dev/Configuration/zsh/aliases.config.zsh
source ~/Dev/Configuration/zsh/aliases.navigation.zsh
source ~/Dev/Configuration/zsh/aliases.external.zsh
source ~/Dev/Configuration/zsh/aliases.scaffold.zsh
source ~/Dev/Configuration/zsh/aliases.packages.zsh
source ~/Dev/Configuration/zsh/aliases.tools.zsh

# Settings for ZSH and Oh My ZSH
source ~/Dev/Configuration/zsh/oh-my-zsh-settings.zsh
# Settings for nvm
source ~/Dev/Configuration/zsh/nvm-settings.zsh
# Settings for bun (incl. completions)
source ~/Dev/Configuration/zsh/bun-settings.zsh

export PATH="$HOME/.local/bin:$PATH"

# Added by codebase-memory-mcp install
export PATH="/Users/lewis/.local/bin:$PATH"
