# zsh

My shell configuration, split into small files and loaded by a single `zshrc`. Lives here so it's version-controlled and edited from one place rather than buried in `~/.zshrc`.

macOS, zsh + Oh My Zsh.

## Setup on a fresh machine

```sh
# Symlink ~/.zshrc to the loader in this folder
ln -sf ~/Dev/Configuration/zsh/zshrc ~/.zshrc

# Open a new terminal, or:
source ~/.zshrc
```

That's it — the loader sources everything else.

## What's in here

| File | What it holds |
|------|---------------|
| `zshrc` | Loader. Sources each file below in order. Symlinked from `~/.zshrc`. |
| `aliases.config.zsh` | Colour variables + `zshrc` / `claudemd` edit aliases. Loaded first so colour vars are available to functions in the other files. |
| `aliases.navigation.zsh` | `goto:*` project shortcuts + project commands (`dev`, `build`, `lint`, `unit`, `cypress:*`). |
| `aliases.scaffold.zsh` | `scaffold:*` and `convert:*` aliases, with relative `./support/...` paths so they resolve against the current project. |
| `aliases.packages.zsh` | `packages:refresh`, `packages:updated`, plus the `link` / `unlink` / `relink` / `reinstall` functions for local `@lewishowles/*` development. |
| `aliases.tools.zsh` | Misc tools `sync:gist`, `svg`, `github`, `setup:agents/setup:claude/setup:codex`, `caveman`. |
| `oh-my-zsh-settings.zsh` | Oh My Zsh init + powerlevel10k theme. |
| `nvm-settings.zsh` | nvm init. |
| `bun-settings.zsh` | bun PATH, env, and completions. |

## Adding a new alias or function

Pick the file that matches what the thing *does*, not what type it is. For example, a function and an alias for the same workflow belong in the same file. If nothing fits, add a new `aliases.<topic>.zsh` and source it from `zshrc`.

## The `link` family

For local development against `@lewishowles/*` packages:

```sh
link helpers       # symlink the locally-built @lewishowles/helpers into this project
unlink helpers     # undo the link, restore the registry version
relink helpers     # unlink then link again (clears bun's cache between)
reinstall helpers  # wipe and reinstall from the registry — unrelated to linking
```

`unlink` and `reinstall` look similar but mean different things: `unlink` reverses a `link`, `reinstall` is for when a registry install looks stale or corrupt.
