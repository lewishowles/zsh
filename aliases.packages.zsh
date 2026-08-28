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
# Usage: package:link <library-name>
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
# Usage: package:unlink <library-name>
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
# Usage: package:relink <library-name>
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
# Usage: package:reinstall <library-name>
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

# Report whether each @lewishowles dependency is linked, installed, or missing.
#
# @param  {string}  library
#     Library name without scope. Optional; with no argument every
#     @lewishowles dependency is reported.
# @desc  Report the state of @lewishowles dependencies
# @cat   package
# Usage: package:status [library-name]
# @needs jq
function package:status() {
	local library=$1
	# Shared by the lookup, width, and report loops below.
	local dependency

	if [[ ! -f ./package.json ]]; then
		printf 'package:status must be run in a Node project with ./package.json\n' >&2
		return 1
	fi

	if ! command -v jq &>/dev/null; then
		printf 'jq is required to read package.json\n' >&2
		return 1
	fi

	# Merge both dependency lists and emit the @lewishowles names without their scope prefix.
	local dependencies
	if ! dependencies=$(jq -r '
		[.dependencies // {}, .devDependencies // {}]
		| add
		| keys[]
		| select(startswith("@lewishowles/"))
		| sub("^@lewishowles/"; "")
	' ./package.json 2>/dev/null); then
		printf 'Unable to read dependencies from ./package.json\n' >&2
		return 1
	fi

	local -a libraries
	libraries=(${(f)dependencies})

	if [[ -n "$library" ]]; then
		# Zero means the requested dependency was found.
		local found=1
		for dependency in "${libraries[@]}"; do
			if [[ "$dependency" == "$library" ]]; then
				found=0
				break
			fi
		done

		if (( found )); then
			printf '@lewishowles/%s is not a dependency of this project\n' "$library" >&2
			return 1
		fi

		libraries=("$library")
	fi

	local width=0
	for dependency in "${libraries[@]}"; do
		if (( ${#dependency} > width )); then
			width=${#dependency}
		fi
	done

	local package_path
	local version
	for dependency in "${libraries[@]}"; do
		package_path="node_modules/@lewishowles/$dependency"

		# A symlink is a local link; :A resolves it to the real package directory it points at.
		if [[ -L "$package_path" ]]; then
			printf "%-${width}s  %s\n" "$dependency" "${package_path:A}"
			continue
		fi

		if [[ -d "$package_path" ]]; then
			version=$(jq -r '.version // empty' "$package_path/package.json" 2>/dev/null)
			printf "%-${width}s  registry %s\n" "$dependency" "${version:-(unknown version)}"
			continue
		fi

		printf "%-${width}s  missing\n" "$dependency"
	done
}
