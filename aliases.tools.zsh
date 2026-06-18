# Sync settings to their configuration repos.
alias settings:sync="~/Dev/Repositories/CLI/settings-sync/settings-sync.sh"

# Index the current repository in codebase-memory-mcp and store its architecture summary as an ADR.
function repo:index() {
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
function svg() {
	if ! command -v svgo &>/dev/null; then
		printf 'svgo is not installed or not on PATH\n' >&2
		return 1
	fi

	local -a files
	files=(~/Downloads/**/*.svg(N))

	if [[ ${#files} -eq 0 ]]; then
		printf 'No .svg files found in ~/Downloads\n'
		return 0
	fi

	pushd ~/Downloads > /dev/null && svgo "${files[@]}" && popd > /dev/null
}

# Open the main GitHub page for a repo.
#
# @param  {string}  repo  (optional)
#     Repo name. Defaults to the `name` field in package.json.
function repo:open() {
	local repo=$1

	if [[ -z "$repo" ]]; then
		if ! command -v jq &>/dev/null; then
			printf 'jq is required to read package.json\n' >&2
			return 1
		fi

		repo=$(jq -r .name package.json 2>/dev/null | awk -F/ '{print $NF}')
	fi

	if [[ -z "$repo" ]]; then
		printf 'Usage: repo:open <repo-name>\n' >&2
		return 1
	fi

	open "https://github.com/lewishowles/$repo"
}

# Open the main page, releases, and actions for a repo — three tabs.
#
# @param  {string}  repo  (optional)
#     Repo name. Defaults to the `name` field in package.json.
function repo:open:all() {
	local repo=$1

	if [[ -z "$repo" ]]; then
		if ! command -v jq &>/dev/null; then
			printf 'jq is required to read package.json\n' >&2
			return 1
		fi

		repo=$(jq -r .name package.json 2>/dev/null | awk -F/ '{print $NF}')
	fi

	if [[ -z "$repo" ]]; then
		printf 'Usage: repo:open:all <repo-name>\n' >&2
		return 1
	fi

	open "https://github.com/lewishowles/$repo"
	open "https://github.com/lewishowles/$repo/releases"
	open "https://github.com/lewishowles/$repo/actions"
}

# Set up agent files.
alias agents:setup:global="$HOME/Dev/Configuration/Agents/scripts/setup-global.sh --both"
alias agents:setup:claude:global="$HOME/Dev/Configuration/Agents/scripts/setup-global.sh --claude"
alias agents:setup:codex:global="$HOME/Dev/Configuration/Agents/scripts/setup-global.sh --codex"
alias agents:setup="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --both"
alias agents:setup:claude="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --claude"
alias agents:setup:codex="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --codex"
alias agents:capabilities="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --init-capabilities"
alias agents:capabilities:write="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --write-capabilities"
alias agents:capabilities:force="$HOME/Dev/Configuration/Agents/scripts/setup-project.sh --force-capabilities"
