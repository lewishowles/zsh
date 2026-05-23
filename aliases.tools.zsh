# Sync settings to their configuration repos.
alias sync:settings="~/Dev/Repositories/CLI/settings-sync/settings-sync.sh"

# Index the current repository in codebase-memory-mcp and store its architecture summary as an ADR.
function index:repository() {
	if ! command -v codebase-memory-mcp &>/dev/null; then
		printf 'codebase-memory-mcp is not installed or not on PATH\n' >&2
		return 1
	fi

	if ! command -v jq &>/dev/null; then
		printf 'jq is required to build JSON payloads safely\n' >&2
		return 1
	fi

	local repo_path index_output project architecture

	repo_path="${PWD:A}"
	index_output="$(codebase-memory-mcp cli index_repository "$(jq -cn --arg repo_path "$repo_path" '{repo_path:$repo_path}')")" || return
	project="$(printf '%s' "$index_output" | jq -r '.project // empty' 2>/dev/null)"

	if [[ -z "$project" ]]; then
		project="$(codebase-memory-mcp cli list_projects '{}' | jq -r --arg repo_path "$repo_path" 'first(.projects[] | select(.root_path == $repo_path) | .name) // empty')"
	fi

	if [[ -z "$project" ]]; then
		printf 'Could not find an indexed project for %s\n' "$repo_path" >&2
		printf '%s\n' "$index_output" >&2
		return 1
	fi

	if [[ -n "$index_output" ]]; then
		printf '%s\n' "$index_output"
	fi

	architecture="$(codebase-memory-mcp cli get_architecture "$(jq -cn --arg project "$project" '{project:$project,aspects:["all"]}')" 2>/dev/null || codebase-memory-mcp cli get_architecture "$(jq -cn --arg project "$project" '{project:$project}')")" || return
	printf '%s\n' "$architecture"

	codebase-memory-mcp cli manage_adr "$(jq -cn --arg project "$project" --arg content "$architecture" '{project:$project,mode:"update",content:$content}')"
}

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

# Set up agent files.
alias setup:agents:global="/Users/lewis/Dev/Configuration/Agents/scripts/setup-global.sh --both"
alias setup:claude:global="/Users/lewis/Dev/Configuration/Agents/scripts/setup-global.sh --claude"
alias setup:codex:global="/Users/lewis/Dev/Configuration/Agents/scripts/setup-global.sh --codex"
alias setup:agents="/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --both"
alias setup:claude="/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --claude"
alias setup:codex="/Users/lewis/Dev/Configuration/Agents/scripts/setup-project.sh --codex"
