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

# Symlink the global CLAUDE.md instruction set
function setup:claude() {
	local repo="/Users/lewis/Dev/Configuration/Claude"

	echo ""
	mkdir -p .claude

	if [ ! -f ".claude/CLAUDE.md" ]; then
		ln -s "$repo/CLAUDE.md" .claude/CLAUDE.md
		echo "${GREEN}✓${RESET_COLOUR} Symlinked ${PURPLE}CLAUDE.md${RESET_COLOUR}"
	else
		echo "${PURPLE}CLAUDE.md${RESET_COLOUR} already exists. No link was made."
	fi

	if [ ! -f ".claude/AGENTS.md" ]; then
		cp "$repo/templates/AGENTS.md.template" .claude/AGENTS.md
		echo "${GREEN}✓${RESET_COLOUR} Copied ${PURPLE}AGENTS.md${RESET_COLOUR} — edit it to document this project"
	else
		echo "${PURPLE}AGENTS.md${RESET_COLOUR} already exists. No changes made."
	fi

	if [ ! -f ".claude/settings.json" ]; then
		cp "$repo/templates/settings.json" .claude/settings.json
		echo "${GREEN}✓${RESET_COLOUR} Copied ${PURPLE}settings.json${RESET_COLOUR} — enable stack-specific skills as needed"
	else
		echo "${PURPLE}settings.json${RESET_COLOUR} already exists. No changes made."
	fi

	if [ ! -f ".claudeignore" ]; then
		cp "$repo/templates/.claudeignore" .claudeignore
		echo "${GREEN}✓${RESET_COLOUR} Copied ${PURPLE}.claudeignore${RESET_COLOUR} — edit to customise which directories to skip"
	else
		echo "${PURPLE}.claudeignore${RESET_COLOUR} already exists. No changes made."
	fi

	echo ""
}
