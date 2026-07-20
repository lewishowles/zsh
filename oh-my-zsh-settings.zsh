# Oh My ZSH installation location
export ZSH="$HOME/.oh-my-zsh"

# Disable Oh My Zsh's built-in prompt so Starship can provide it.
ZSH_THEME=""

# Enabled plugins. Standard plugins can be found in $ZSH/plugins/
plugins=(git)

[[ -r "$ZSH/oh-my-zsh.sh" ]] && source "$ZSH/oh-my-zsh.sh"

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
#[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
