# Sync items to a GitHub gist.
alias sync:gist="~/Dev/Repositories/CLI/gist-sync/gist-sync.sh"

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

# Symlink the global CLAUDE.md instruction set
function setup:claude() {
	echo ""

	if [ ! -f ".claude/CLAUDE.md" ]; then
		ln -s ~/Dev/Configuration/Claude/CLAUDE.md .claude/CLAUDE.md
		echo "${GREEN}✓${RESET_COLOUR} Symlinked ${PURPLE}CLAUDE.md${RESET_COLOUR}"
	else
		echo "${PURPLE}CLAUDE.md${RESET_COLOUR} already exists. No link was made."
	fi

	if [ ! -f ".claude/AGENTS.md" ]; then
		echo ""
		echo "${YELLOW}Important:${RESET_COLOUR} Make sure to set up project-specific instructions in ${PURPLE}AGENTS.md${RESET_COLOUR}. See AGENTS.md.template for an example."
	fi

	echo ""
}
