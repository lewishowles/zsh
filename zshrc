ZSH_CONFIG_ROOT="${ZSH_CONFIG_ROOT:-$HOME/Dev/Configuration/zsh}"

source "$ZSH_CONFIG_ROOT/environment.zsh"

# Aliases & helpers — sources every aliases.*.zsh in sorted order.
# Drop a new file in and it's picked up automatically; private/optional files
# (e.g. aliases.external.zsh) simply don't error when absent.
for f in "$ZSH_CONFIG_ROOT"/aliases.*.zsh(N); do
	source "$f"
done

# Initialise completions (previously handled by Oh My Zsh).
autoload -Uz compinit && compinit

# Bun completions.
source "$ZSH_CONFIG_ROOT/bun-settings.zsh"

export NVM_DIR="$HOME/.nvm"

# Loads NVM and its completions once, on first use, instead of paying
# nvm.sh's startup cost on every new shell.
_nvm_lazy_load() {
	unset -f nvm node npm npx
	[[ -s "$NVM_DIR/nvm.sh" ]] && source "$NVM_DIR/nvm.sh"
	[[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
}

# Stub that loads NVM on first call, then runs the real nvm command.
nvm() {
	_nvm_lazy_load
	nvm "$@"
}

# Stub that loads NVM on first call, then runs the real Node binary.
node() {
	_nvm_lazy_load
	command node "$@"
}

# Stub that loads NVM on first call, then runs the real npm binary.
npm() {
	_nvm_lazy_load
	command npm "$@"
}

# Stub that loads NVM on first call, then runs the real npx binary.
npx() {
	_nvm_lazy_load
	command npx "$@"
}

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
