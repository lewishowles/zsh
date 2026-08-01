# zsh

My macOS terminal and shell configuration, split into small, focused files and loaded from one version-controlled repository.

The configuration lives here so it can be version-controlled, reviewed and edited from one place rather than being buried in `~/.zshrc`.

Built around:

- Zsh and Oh My Zsh
- Starship
- Ghostty
- zoxide
- eza
- fzf
- Atuin
- bat

## Setup on a fresh machine

### 1. Install the terminal and font

Install [Homebrew](https://brew.sh/) first, then:

```sh
brew install --cask ghostty font-jetbrains-mono-nerd-font
```

The Nerd Font provides the symbols used by the Starship prompt.

### 2. Install the shell tools

```sh
brew install \
    atuin \
    bat \
    eza \
    fzf \
    starship \
    zoxide
```

These provide:

| Tool       | Purpose                                               |
| ---------- | ----------------------------------------------------- |
| `starship` | Configurable shell prompt                             |
| `zoxide`   | Frecency-based directory navigation with `z` and `zi` |
| `eza`      | Clearer file listings and directory trees             |
| `fzf`      | Fuzzy file, directory and command selection           |
| `atuin`    | Searchable, contextual shell history                  |
| `bat`      | Syntax-highlighted file viewing                       |

### 3. Install Oh My Zsh

```sh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
```

Do this before linking the repository configuration because the installer may create or replace `~/.zshrc`.

### 4. Link the configuration

Assuming this repository is checked out at `~/Dev/Configuration/zsh`:

```sh
mkdir -p ~/.config
mkdir -p "$HOME/Library/Application Support/com.mitchellh.ghostty"

ln -sf ~/Dev/Configuration/zsh/zshrc ~/.zshrc
ln -sf ~/Dev/Configuration/zsh/zprofile ~/.zprofile
ln -sf ~/Dev/Configuration/zsh/starship.toml ~/.config/starship.toml
ln -sf ~/Dev/Configuration/zsh/ghostty.config \
    "$HOME/Library/Application Support/com.mitchellh.ghostty/config.ghostty"

touch ~/.hushlogin

cd ~/Dev/Configuration/zsh
git config core.hooksPath hooks
```

`~/.hushlogin` suppresses macOS’s `Last login` message.

The Ghostty symlink keeps terminal appearance, padding, key behaviour and shell integration version-controlled alongside the Zsh configuration.

The `core.hooksPath` setting activates the repository’s Git hooks, including the pre-commit hook that keeps the README command table up to date.

Open a new terminal after linking the files. The shell automatically loads every `aliases.*.zsh` file in sorted order, so adding a new alias file does not require editing `zshrc`.

### 5. Import existing shell history

On a machine with existing Zsh history:

```sh
atuin import auto
```

Atuin remains local unless synchronisation is configured separately.

## Shell features

### Navigation

`zoxide` learns commonly visited directories:

```sh
z helpers
zi
```

`zi` opens an interactive directory picker powered by `fzf`.

### Fuzzy search

The fzf shell integration provides:

| Shortcut   | Action                                             |
| ---------- | -------------------------------------------------- |
| `Ctrl-R`   | Search command history through Atuin               |
| `Ctrl-T`   | Find a file and insert it into the current command |
| `Option-C` | Find a directory and change into it                |

Ghostty must treat Option as Alt for `Option-C` to work:

```ini
macos-option-as-alt = left
```

### File listings

The eza aliases provide progressively more detail:

| Command | Output                                               |
| ------- | ---------------------------------------------------- |
| `ls`    | Basic file listing                                   |
| `ll`    | Detailed listing with headings, icons and Git status |
| `la`    | Detailed listing including hidden files              |
| `lt`    | Two-level directory tree                             |

### Shell history

Atuin records commands with contextual information such as their directory, duration and exit status.

The normal up-arrow behaviour is preserved, while `Ctrl-R` opens Atuin’s searchable history.

### File viewing

Use `bat` for syntax-highlighted file output:

```sh
bat README.md
bat package.json
bat --diff src/example.ts
```

The standard `cat` command is left unchanged.

## Private aliases

`aliases.private.zsh` is gitignored.

Copy the example file to create it locally:

```sh
cp aliases.private.zsh.example aliases.private.zsh
```

It is intended for `goto:*` navigation shortcuts and other personal or machine-specific configuration.

## Health check

```sh
zsh:doctor
```

Reports:

- required file and tool availability;
- `goto:*` path validity;
- Zsh syntax errors;
- duplicate `PATH` entries;
- whether the generated README command table is current.

## Repository structure

| File                     | What it holds                                                                                                                 |
| ------------------------ | ----------------------------------------------------------------------------------------------------------------------------- |
| `zprofile`               | Login-shell loader. Sources the shared environment and is symlinked from `~/.zprofile`.                                       |
| `zshrc`                  | Interactive-shell loader. Sources the environment, aliases, hooks and interactive tool integrations.                          |
| `environment.zsh`        | Shared `PATH` and command environment for interactive and non-interactive login shells, including the cli-style Bash adapter. |
| `starship.toml`          | Starship prompt layout, Git status, package version, command duration and background-job configuration.                       |
| `aliases.config.zsh`     | Colour variables and configuration-editing aliases. Loaded first so shared values are available elsewhere.                    |
| `aliases.discovery.zsh`  | `alias:list`, `alias:find` and `docs:generate` for browsing commands and maintaining this README.                             |
| `aliases.doctor.zsh`     | The `zsh:doctor` health check.                                                                                                |
| `aliases.project.zsh`    | `dev`, `build`, `lint` and `test:*` project commands.                                                                         |
| `aliases.packages.zsh`   | `deps:*` dependency helpers and `package:*` functions for local `@lewishowles/*` development.                                 |
| `aliases.tools.zsh`      | Tool aliases, file listings, repository helpers, SVG optimisation and agent setup commands.                                   |
| `bun-settings.zsh`       | Bun shell completions.                                                                                                        |
| `oh-my-zsh-settings.zsh` | Oh My Zsh configuration and plugin initialisation.                                                                            |
| `ghostty.config`         | Ghostty typography, padding, cursor, shell integration, tab behaviour and macOS-specific settings.                            |
| `ignores.fd`             | Shared ignore patterns for file discovery.                                                                                    |
| `hooks/`                 | Zsh hooks, including repository-aware Ghostty tab titles.                                                                     |

## Adding an alias or function

Choose the file that matches the command’s purpose. Add a new `aliases.<topic>.zsh` file when no existing category is appropriate; it will be sourced automatically.

Annotate public commands so they appear in `alias:list`, `alias:find` and this README:

```zsh
# @desc  Short description shown in the command table
# @cat   category-name
# @needs optional-tool-dependency
alias my:command="..."
```

The pre-commit hook regenerates the command table automatically before each commit.

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

### agent

| Command | Description |
| --- | --- |
| `claude` | Run claude with auto-mode |
| `codex` | Run Codex with shared configuration defaults |

### agents

| Command | Description |
| --- | --- |
| `agents:setup` | Set up agent files (Claude + Codex) for the current project |
| `agents:setup:global` | Set up agent files (Claude + Codex) globally |
| `agents:workspace` | Initialise WORKSPACE.md for the current project |
| `agents:workspace:force` | Force-regenerate WORKSPACE.md for the current project |

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

### hcom

| Command | Description |
| --- | --- |
| `hcom-implementer` | Start the Implementer hcom role |
| `hcom-orchestrator` | Start the Orchestrator hcom role |
| `hcom-plan-claude` | Start a Claude planning-peer task review |
| `hcom-plan-codex` | Start a Codex planning-peer task review |
| `hcom-restart-reviewer` | Start a fresh reviewer and announce it to the project orchestrator |
| `hcom-resume` | Resume a stopped hcom agent by name (hcom r already replays its stored model/tag/role prompt) |
| `hcom-reviewer` | Start the Reviewer hcom role |
| `hcom-scout` | Start the Scout hcom role |
| `hcom-team` | Start the complete hcom team in four Ghostty panes |

### nav

| Command | Description |
| --- | --- |
| `goto:agents` | Open the agent configuration directory |
| `goto:anpr` | Open the Gatekeeper Admin root |
| `goto:blog` | Open the blog project |
| `goto:boilerplate` | Open the boilerplate project |
| `goto:boilersuit` | Open the Boilersuit macOS app project |
| `goto:cli` | Open the CLI style library project |
| `goto:components` | Open the Vue component library project |
| `goto:helpers` | Open the JavaScript helper library project |
| `goto:howles` | Open the primary website project |
| `goto:lint` | Open the central linting project |
| `goto:sketch` | Open the Sketch plugins root |
| `goto:testing` | Open the testing helper library project |
| `goto:tools` | Open the dev tools project |
| `goto:zsh` | Open the ZSH config repo |

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
| `updates:check` | List available global updaters without starting them |
| `updates:run` | Update global tools while preserving each updater's interaction |

<!-- commands:end -->
