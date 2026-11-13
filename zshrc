ZSH_CONFIG_ROOT="${ZSH_CONFIG_ROOT:-$HOME/Dev/Repositories/Configuration/zsh}"

[[ -r "$ZSH_CONFIG_ROOT/environment.zsh" ]] && source "$ZSH_CONFIG_ROOT/environment.zsh"

# Aliases & helpers — sources every aliases.*.zsh in sorted order.
# Drop a new file in and it's picked up automatically; private/optional files
# (e.g. aliases.external.zsh) simply don't error when absent.
for f in "$ZSH_CONFIG_ROOT"/aliases.*.zsh(N); do
	source "$f"
done

# Initialise completions (previously handled by Oh My Zsh).
autoload -Uz compinit && compinit

# Bun completions. Sourced after compinit because ~/.bun/_bun calls compdef.
source "$ZSH_CONFIG_ROOT/bun-settings.zsh"

# Smarter directory navigation.
if (( $+commands[zoxide] )); then
	eval "$(zoxide init zsh)"
fi

# Fuzzy file, directory and history search. fzf's key bindings need a
# terminal: loading them in zsh -ic with no terminal prints zle warnings.
if (( $+commands[fzf] )) && [[ -t 0 ]]; then
	eval "$(fzf --zsh)"
fi

# Searchable, contextual shell history.
if (( $+commands[atuin] )); then
	eval "$(atuin init zsh --disable-up-arrow --disable-ai)"
fi

# Shell hooks.
for f in "$ZSH_CONFIG_ROOT"/hooks/*.zsh(N); do
	source "$f"
done

# Prompt.
if (( $+commands[starship] )); then
	eval "$(starship init zsh)"
fi

# bun completions
[ -s "/Users/lewis/.bun/_bun" ] && source "/Users/lewis/.bun/_bun"


# Added by Antigravity CLI installer
export PATH="/Users/lewis/.local/bin:$PATH"
