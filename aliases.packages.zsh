# @desc  Wipe node_modules and lockfile, then reinstall all dependencies
# @cat   deps
alias deps:refresh="rm -rf node_modules; rm -f bun.lock bun.lockb; bun i";
# @desc  Upgrade all dependencies to latest versions, then install
# @cat   deps
# @needs ncu
alias deps:update="ncu -u; bun i";

# Symlink a locally-built @lewishowles package into this project.
# Removes any current registry version first so the link is the only copy.
#
# @param  {string}  library
#     Library name without scope (e.g. "helpers" for @lewishowles/helpers).
# @desc  Symlink a local @lewishowles package into this project
# @cat   package
# @needs bun
function package:link() {
	local library=$1
	local library_path="$HOME/Dev/Repositories/Packages/$library"

	if [[ -z "$library" ]]; then
		printf 'Usage: package:link <library-name>\n' >&2
		return 1
	fi

	if ! command -v bun &>/dev/null; then
		printf 'bun is not installed or not on PATH\n' >&2
		return 1
	fi

	if [[ ! -d "$library_path" ]]; then
		printf 'Library path not found: %s\n' "$library_path" >&2
		return 1
	fi

	# Register the library globally
	(cd "$library_path" && bun link) || return

	# Link it in the current project
	bun uninstall "@lewishowles/$library"
	bun link "@lewishowles/$library"
}

# Undo a previous `package:link` and restore the registry version.
# Removes the symlink via `bun unlink`, clears bun's cache to avoid stale
# tarballs, then installs the registry release.
#
# @param  {string}  library
#     Library name without scope.
# @desc  Restore a linked @lewishowles package to its registry version
# @cat   package
# @needs bun
function package:unlink() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: package:unlink <library-name>\n' >&2
		return 1
	fi

	if ! command -v bun &>/dev/null; then
		printf 'bun is not installed or not on PATH\n' >&2
		return 1
	fi

	bun unlink "@lewishowles/$library"
	bun pm cache rm
	bun i "@lewishowles/$library"
}

# Reset a linked package: unlink then re-link, clearing cache between.
#
# @param  {string}  library
#     Library name without scope.
# @desc  Unlink then re-link a local @lewishowles package
# @cat   package
# @needs bun
function package:relink() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: package:relink <library-name>\n' >&2
		return 1
	fi

	package:unlink "$library"
	package:link "$library"
}

# Wipe a registry-installed package and reinstall it from scratch.
# Unrelated to linking — use when a package install looks corrupt or stale.
#
# @param  {string}  library
#     Library name without scope.
# @desc  Wipe and reinstall a @lewishowles package from the registry
# @cat   package
# @needs bun
function package:reinstall() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: package:reinstall <library-name>\n' >&2
		return 1
	fi

	if ! command -v bun &>/dev/null; then
		printf 'bun is not installed or not on PATH\n' >&2
		return 1
	fi

	bun remove "@lewishowles/$library"
	bun pm cache rm
	bun add "@lewishowles/$library"
}
