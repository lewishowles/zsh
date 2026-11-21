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

# The number of commands the current shell keeps in memory.
HISTSIZE=50000
# The number of commands kept in the history file for later shells.
SAVEHIST=50000
# Leave out repeats of the previous command, commands that start with a space
# and extra spaces, and save each command to the file as soon as it runs.
setopt HIST_IGNORE_DUPS HIST_IGNORE_SPACE HIST_REDUCE_BLANKS INC_APPEND_HISTORY

# Searchable, contextual shell history on Ctrl-R. The up arrow stays with zsh.
if (( $+commands[atuin] )); then
	eval "$(atuin init zsh --disable-ai --disable-up-arrow)"
fi

# The up and down arrows step through history. With nothing typed they act as
# normal; once something is typed they only show commands that start with it.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
# Terminals send either sequence for each arrow, so bind both.
bindkey '^[[A' up-line-or-beginning-search
bindkey '^[OA' up-line-or-beginning-search
bindkey '^[[B' down-line-or-beginning-search
bindkey '^[OB' down-line-or-beginning-search

# Grey suggestions from earlier commands as you type, when Homebrew has
# installed zsh-autosuggestions.
if [[ -r /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]]; then
	source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
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
