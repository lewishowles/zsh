alias packages:refresh="rm -rf node_modules; rm -f bun.lock bun.lockb; bun i";
alias packages:update="ncu -u; bun i";

# Symlink a locally-built @lewishowles package into this project.
# Removes any current registry version first so the link is the only copy.
#
# @param  {string}  library
#     Library name without scope (e.g. "helpers" for @lewishowles/helpers).
function link() {
	local library=$1
	local library_path="$HOME/Dev/Repositories/Packages/$library"

	if [[ -z "$library" ]]; then
		printf 'Usage: link <library-name>\n' >&2
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

# Undo a previous `link` and restore the registry version.
# Removes the symlink via `bun unlink`, clears bun's cache to avoid stale
# tarballs, then installs the registry release.
#
# @param  {string}  library
#     Library name without scope.
function unlink() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: unlink <library-name>\n' >&2
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
function relink() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: relink <library-name>\n' >&2
		return 1
	fi

	unlink "$library"
	link "$library"
}

# Wipe a registry-installed package and reinstall it from scratch.
# Unrelated to linking — use when a package install looks corrupt or stale.
#
# @param  {string}  library
#     Library name without scope.
function reinstall() {
	local library=$1

	if [[ -z "$library" ]]; then
		printf 'Usage: reinstall <library-name>\n' >&2
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
