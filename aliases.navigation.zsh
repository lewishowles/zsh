# @desc  Open the primary website project
# @cat   nav
alias goto:howles="cd ~/Dev/Repositories/Howles/howles.dev"
# @desc  Open the blog project
# @cat   nav
alias goto:blog="cd ~/Dev/Repositories/Howles/blog"
# @desc  Open the Boilersuit macOS app project
# @cat   nav
alias goto:boilersuit="cd ~/Dev/Repositories/macOS/Boilersuit"
# @desc  Open the agent configuration directory
# @cat   nav
alias goto:agents="cd ~/Dev/Configuration/Agents"
# @desc  Open the Vue component library project
# @cat   nav
alias goto:components="cd ~/Dev/Repositories/Packages/components"
# @desc  Open the JavaScript helper library project
# @cat   nav
alias goto:helpers="cd ~/Dev/Repositories/Packages/helpers"
# @desc  Open the testing helper library project
# @cat   nav
alias goto:testing="cd ~/Dev/Repositories/Packages/testing"
# @desc  Open the Sketch plugins root
# @cat   nav
alias goto:sketch="cd ~/Dev/Repositories/Extensions/Sketch"
# @desc  Open the VS Code extensions root
# @cat   nav
alias goto:vscode="cd ~/Dev/Repositories/Extensions/\"Visual Studio Code\""

# @desc  Run the dev server
# @cat   dev
alias dev="bun dev";
# @desc  Build the project for production
# @cat   dev
alias build="bun run build";
# @desc  Run the linter
# @cat   dev
alias lint="bun lint";

# @desc  Run unit tests headlessly
# @cat   test
alias test:unit="bun test:unit";
# @desc  Run unit tests in browser UI mode
# @cat   test
alias test:unit:ui="bun test:unit:ui";

# @desc  Run all e2e tests headlessly
# @cat   test
alias test:e2e="bun playwright test"
# @desc  Run e2e tests in interactive UI mode
# @cat   test
alias test:e2e:ui="bun playwright test --ui"
# @desc  Run e2e tests matching an optional file path filter
# @cat   test
function test:e2e:spec() {
	if [[ -n "$1" ]]; then
		bun playwright test "*$1*"
	else
		bun playwright test
	fi
}
