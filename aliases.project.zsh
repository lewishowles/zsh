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
# @desc  Run unit tests matching an optional file path filter
# @cat   test
function test:unit:spec() {
	if [[ -n "$1" ]]; then
		bun test:unit -- "$1"
	else
		bun test:unit
	fi
}

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

# @desc  Run Xcode tests, which may include UI tests
# @cat   test
alias xcode:test="xcodebuild test -scheme Boilersuit -destination 'platform=macOS' -quiet"
# @desc  Build the current app in Xcode
# @cat   dev
alias xcode:build="xcodebuild build -scheme Boilersuit -destination 'platform=macOS' -quiet"

# @desc  Run lint, unit tests and build, stopping at the first failure
# @cat   dev
function check() {
	lint || return $?
	test:unit || return $?
	build
}
