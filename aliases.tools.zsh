# Sync settings to their configuration repos.
alias sync:settings="~/Dev/Repositories/CLI/settings-sync/settings-sync.sh"

# Optimise any .svg file that exists in the Downloads folder using SVGO,
# and return to the previous folder.
alias svg="pushd ~/Downloads > /dev/null && svgo **/*.svg && popd > /dev/null"

# Quickly navigate to relevant GitHub locations
function github() {
	local repo=$1

	if [ -z "$repo" ]; then
		repo=$(jq -r .name package.json | awk -F/ '{print $NF}')
	fi

	open "https://github.com/lewishowles/$repo"
	open "https://github.com/lewishowles/$repo/releases"
	open "https://github.com/lewishowles/$repo/actions"
}

# Set up project-local agent files.
function setup:agents() {
	/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --both
}

function setup:claude() {
	/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --claude
}

function setup:codex() {
	/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --codex
}
