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

# /caveman:compress the original CLAUDE.md file to use fewer tokens.
function caveman() {
	pushd ~/Dev/Configuration/Claude > /dev/null

	if [[ -f CLAUDE.original.md ]]; then
		# Copy original content into CLAUDE.md in-place (preserves
		# inode/symlinks), then remove the backup so compress is willing to run.
		cp CLAUDE.original.md CLAUDE.md
		rm CLAUDE.original.md
	fi

	echo ""
	echo "Once Claude starts, run: ${PURPLE}/caveman:compress CLAUDE.md${RESET_COLOUR}"
	echo "Then type ${PURPLE}exit${RESET_COLOUR} to return here."
	echo ""

	claude

	# Claude has exited — symlinks already point to CLAUDE.md whose inode
	# never changed, so nothing further is needed.
	echo ""
	echo "${GREEN}✓${RESET_COLOUR} Done. Symlinks are intact."
	echo ""

	popd > /dev/null
}
