# zsh

My shell configuration, split into small files and loaded by a single `zshrc`. Lives here so it's version-controlled and edited from one place rather than buried in `~/.zshrc`.

macOS, zsh + Oh My Zsh + Powerlevel10k.

## Setup on a fresh machine

```sh
ln -sf ~/Dev/Configuration/zsh/zshrc ~/.zshrc
git config core.hooksPath hooks
```

Open a new terminal — the loader sources every `aliases.*.zsh` file automatically. Adding a new file doesn't require editing `zshrc`. The `core.hooksPath` step activates the pre-commit hook that keeps the README command table up to date.

## Private aliases

`aliases.private.zsh` is gitignored. Copy `aliases.private.zsh.example` to create it locally — the right place for `goto:` navigation shortcuts and anything else that's personal or machine-specific.

## Health check

```sh
zsh:doctor
```

Reports tool availability, required files, `goto:*` path validity, syntax errors, PATH duplicates, and whether the README command table is up to date.

## What's in here

| File                     | What it holds                                                                                      |
| ------------------------ | -------------------------------------------------------------------------------------------------- |
| `zshrc`                  | Loader. Sources all `aliases.*.zsh` files in sorted order. Symlinked from `~/.zshrc`.              |
| `aliases.config.zsh`     | Colour variables and the `zshrc` edit alias. Loaded first so colour vars are available everywhere. |
| `aliases.discovery.zsh`  | `alias:list`, `alias:find`, and `docs:generate` — browse commands and keep the README up to date.  |
| `aliases.doctor.zsh`     | `zsh:doctor` health check.                                                                         |
| `aliases.project.zsh`    | `dev`/`build`/`lint`/`test:*` project commands.                                                    |
| `aliases.packages.zsh`   | `deps:*` dependency helpers and `package:*` functions for local `@lewishowles/*` development.      |
| `aliases.tools.zsh`      | `repo:*`, `svg`, and `agents:*` setup helpers.                                                     |
| `oh-my-zsh-settings.zsh` | Oh My Zsh init + Powerlevel10k theme.                                                              |
| `bun-settings.zsh`       | bun PATH, env, and completions.                                                                    |

## Adding a new alias or function

Pick the file that matches what the thing does. Drop a new `aliases.<topic>.zsh` into the folder and it's sourced automatically.

Annotate it so it appears in `alias:list`, `alias:find`, and this README:

```zsh
# @desc  Short description shown in the command table
# @cat   category-name
# @needs optional-tool-dependency
alias my:command="..."
```

The pre-commit hook regenerates the command table automatically on each commit.

## Commands
<!-- commands:start -->

### agents

| Command | Description |
| --- | --- |
| `agents:capabilities` | Initialise AGENT_CAPABILITIES.md for the current project |
| `agents:capabilities:force` | Force-regenerate AGENT_CAPABILITIES.md for the current project |
| `agents:setup` | Set up agent files (Claude + Codex) for the current project |
| `agents:setup:global` | Set up agent files (Claude + Codex) globally |

### config

| Command | Description |
| --- | --- |
| `alias:find` | Interactively browse and run annotated commands with fzf |
| `alias:list` | List all annotated commands, grouped by category |
| `zsh:doctor` | Check zsh config health: files, tools, goto paths, syntax, PATH, docs |
| `zshrc` | Open .zshrc in VS Code |

### deps

| Command | Description |
| --- | --- |
| `deps:refresh` | Wipe node_modules and lockfile, then reinstall all dependencies |
| `deps:update` | Upgrade all dependencies to latest versions, then install |

### dev

| Command | Description |
| --- | --- |
| `build` | Build the project for production |
| `dev` | Run the dev server |
| `lint` | Run the linter |
| `xcode:build` | Build the current app in Xcode |

### docs

| Command | Description |
| --- | --- |
| `docs:generate` | Regenerate the command table in README.md from annotations |

### nav

| Command | Description |
| --- | --- |
| `goto:agents` | Open the agent configuration directory |
| `goto:anpr` | Open the Gatekeeper Admin root |
| `goto:blog` | Open the blog project |
| `goto:boilersuit` | Open the Boilersuit macOS app project |
| `goto:components` | Open the Vue component library project |
| `goto:helpers` | Open the JavaScript helper library project |
| `goto:howles` | Open the primary website project |
| `goto:sketch` | Open the Sketch plugins root |
| `goto:testing` | Open the testing helper library project |
| `goto:vscode` | Open the VS Code extensions root |

### package

| Command | Description |
| --- | --- |
| `package:link` | Symlink a local @lewishowles package into this project |
| `package:reinstall` | Wipe and reinstall a @lewishowles package from the registry |
| `package:relink` | Unlink then re-link a local @lewishowles package |
| `package:unlink` | Restore a linked @lewishowles package to its registry version |

### repo

| Command | Description |
| --- | --- |
| `repo:index` | Index the current repository in codebase-memory-mcp and store an ADR |
| `repo:link` | Link the current folder to the Chat GPT local setup |
| `repo:open` | Open the main GitHub page for a repo |
| `repo:open:all` | Open main page, releases, and actions for a repo (3 tabs) |

### test

| Command | Description |
| --- | --- |
| `test:e2e` | Run all e2e tests headlessly |
| `test:e2e:spec` | Run e2e tests matching an optional file path filter |
| `test:e2e:ui` | Run e2e tests in interactive UI mode |
| `test:unit` | Run unit tests headlessly |
| `test:unit:ui` | Run unit tests in browser UI mode |
| `xcode:test` | Run Xcode tests, which may include UI tests |

### tools

| Command | Description |
| --- | --- |
| `svg` | Optimise SVG files in ~/Downloads using SVGO |

<!-- commands:end -->
