# Primary website
alias goto:howles="cd ~/Dev/Repositories/Howles/howles.dev"
# Blog
alias goto:blog="cd ~/Dev/Repositories/Howles/blog"
# Boilersuit app
alias goto:boilersuit="cd ~/Dev/Repositories/macOS/Boilersuit"
# Agent configuration
alias goto:agents="cd ~/Dev/Configuration/Agents"
# Vue component library
alias goto:components="cd ~/Dev/Repositories/Packages/components"
# Javascript helper library
alias goto:helpers="cd ~/Dev/Repositories/Packages/helpers"
# Testing helper library
alias goto:testing="cd ~/Dev/Repositories/Packages/testing"
# Sketch plugins root
alias goto:sketch="cd ~/Dev/Repositories/Extensions/Sketch"
# Visual Studio Code plugins / tools root
alias goto:vscode="cd ~/Dev/Repositories/Extensions/\"Visual Studio Code\""
# settings-sync
alias goto:settings-sync="cd ~/Dev/Repositories/CLI/settings-sync"

# Quick project manipulation
alias dev="bun dev";
alias build="bun run build";
alias lint="bun lint";
alias test:unit="bun test:unit";
alias test:unit:ui="bun test:unit:ui";

# Run all e2e tests headlessly
alias test:e2e="bun playwright test"
# Run e2e tests in interactive UI mode
alias test:e2e:ui="bun playwright test --ui"
# Run e2e tests matching an optional file path filter
function test:e2e:spec() {
	if [[ -n "$1" ]]; then
		bun playwright test "*$1*"
	else
		bun playwright test
	fi
}
