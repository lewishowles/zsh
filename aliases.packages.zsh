alias packages:refresh="rm -rf node_modules; rm bun.lock; bun i";
alias packages:updated="ncu -u; bun i";

# Symlink a locally-built @lewishowles package into this project.
# Removes any current registry version first so the link is the only copy.
#
# @param  {string}  library
#     Library name without scope (e.g. "helpers" for @lewishowles/helpers).
function link() {
	local library=$1

	bun uninstall @lewishowles/$library
	bun link @lewishowles/$library
}

# Undo a previous `link` and restore the registry version.
# Removes the symlink via `bun unlink`, clears bun's cache to avoid stale
# tarballs, then installs the registry release.
#
# @param  {string}  library
#     Library name without scope.
function unlink() {
	local library=$1

	bun unlink @lewishowles/$library
	bun pm cache rm
	bun i @lewishowles/$library
}

# Reset a linked package: unlink then re-link, clearing cache between.
#
# @param  {string}  library
#     Library name without scope.
function relink() {
	local library=$1

	unlink $library
	link $library
}

# Wipe a registry-installed package and reinstall it from scratch.
# Unrelated to linking — use when a package install looks corrupt or stale.
#
# @param  {string}  library
#     Library name without scope.
function reinstall() {
	local library=$1

	bun remove @lewishowles/$library
	bun pm cache rm
	bun add @lewishowles/$library
}
