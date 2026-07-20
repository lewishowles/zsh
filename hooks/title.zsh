# Use the Git repository name when available; otherwise use the current folder.
terminal_title_directory() {
    local git_root
    git_root="$(git rev-parse --show-toplevel 2>/dev/null)"

    if [[ -n "$git_root" ]]; then
        print -r -- "${git_root:t}"
    else
        print -r -- "${PWD:t}"
    fi
}

# Set the terminal title using the standard OSC title sequence.
terminal_title_set() {
    print -Pn "\e]0;$1\a"
}

# Show the current repository or directory while waiting at the prompt.
terminal_title_precmd() {
    terminal_title_set "$(terminal_title_directory)"
}

# Temporarily include the command currently being executed.
terminal_title_preexec() {
    local directory command

    directory="$(terminal_title_directory)"
    command="${1%% *}"

    terminal_title_set "$directory — $command"
}

autoload -Uz add-zsh-hook
add-zsh-hook precmd terminal_title_precmd
add-zsh-hook preexec terminal_title_preexec
