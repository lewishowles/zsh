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

	# Symlink the global config (not a template, lives in repo root)
	if [ ! -f ".claude/CLAUDE.md" ]; then
		ln -s "$repo/CLAUDE.md" .claude/CLAUDE.md
		echo "${GREEN}✓${RESET_COLOUR} Symlinked ${PURPLE}CLAUDE.md${RESET_COLOUR}"
	else
		echo "${PURPLE}CLAUDE.md${RESET_COLOUR} already exists. No link was made."
	fi

	# Copy config files from templates. Format: .claude/<file> → templates/<file>
	local -a targets=(
		".claude/AGENTS.md"
		".claude/settings.json"
		".claude/.claudeignore"
	)

	local -A copy_messages=(
		[AGENTS.md]="edit it to document this project"
		[settings.json]="enable stack-specific skills as needed"
		[.claudeignore]="edit to customise which directories to skip"
	)

	for target in "${targets[@]}"; do
		local filename=$(basename "$target")
		local source="$repo/templates/$filename"

		if [ ! -f "$target" ]; then
			cp "$source" "$target"
			local msg="${copy_messages[$filename]}"
			if [ -n "$msg" ]; then
				echo "${GREEN}✓${RESET_COLOUR} Copied ${PURPLE}$filename${RESET_COLOUR} — $msg"
			else
				echo "${GREEN}✓${RESET_COLOUR} Copied ${PURPLE}$filename${RESET_COLOUR}"
			fi
		else
			echo "${PURPLE}$filename${RESET_COLOUR} already exists. No changes made."
		fi
	done

	echo ""
}
