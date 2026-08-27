# Zsh configuration

Personal macOS Zsh configuration for shell startup, shared environment, aliases, functions, prompt integration, discovery commands, and agent/HCOM launchers.

## Functionality

- `zprofile` loads the login-shell environment.
- `zshrc` loads the interactive environment, aliases, hooks, and tool integrations.
- `aliases.*.zsh` files group public commands by purpose and are sourced automatically in sorted order.
- `alias:list`, `alias:find`, and `docs:generate` discover commands and maintain the generated README command table.
- `zsh:doctor` checks files, tools, paths, syntax, duplicate `PATH` entries, and README command drift.

## Technology choices

- Zsh on macOS, with shell-native functions and aliases.
- Starship supplies the prompt.
- Optional tools such as Atuin, fzf, zoxide, eza, bat, Bun, and HCOM are integrated when installed.
- No project package manager, build system, or automated test runner is assumed.

## Architecture

- Keep login and interactive loaders small. Put reusable environment values in `environment.zsh` and commands in the nearest `aliases.<topic>.zsh` file.
- Public commands use `# @desc`, `# @cat`, and optional `# @needs` annotations so discovery and README generation stay aligned.
- Agent aliases live in `aliases.agents.zsh`; HCOM launchers are split across `aliases.hcom-core.zsh`, `aliases.hcom-team.zsh`, `aliases.hcom-learn.zsh`, `aliases.hcom-plan.zsh` and `aliases.hcom-session.zsh`. Shared HCOM role prompts live in `/Users/lewis/Dev/Configuration/Agents/teams/hcom/roles/` and are injected through `_hcom_launch_role`.
- `README.md` documents setup, repository structure, and the generated command catalogue.

## Need to know

- Read `WORKSPACE.md` before choosing commands. It records the available diagnostics and forbidden operations.
- Run commands from the repository root unless the command contract explicitly accepts another directory.
- Match neighbouring Zsh style and keep public command annotations current.
- Regenerate the README command table through `docs:generate`; do not hand-edit content between `<!-- commands:start -->` and `<!-- commands:end -->`.
- Validate changed Zsh files with `zsh -n <file>`. Run `zsh:doctor` when command annotations, loaders, paths, or generated docs change.
- Do not install optional tools or run update, dependency, remote, release, or destructive commands without explicit approval.
- Preserve private and machine-specific aliases in gitignored `aliases.private.zsh`.

## Planning

Task, chunk, and handoff state live in the `progress` CLI. Run `progress next --json` at the start of a session.
