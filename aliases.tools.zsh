# File and directory listings.
alias ls='eza'
alias ll='eza --long --header --git --icons'
alias la='eza --long --header --git --icons --all'
alias lt='eza --tree --level=2 --icons'
# Read files with syntax highlighting and paging.
alias b='bat --paging=never'

# @desc  Optimise SVG files in ~/Downloads using SVGO
# @cat   tools
# @needs svgo
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

# @internal
function _repo_name() {
	local repo=$1

	if [[ -n "$repo" ]]; then
		printf '%s\n' "$repo"
		return
	fi

	if ! command -v jq &>/dev/null; then
		printf 'jq is required to read package.json\n' >&2
		return 1
	fi

	jq -r '.name // empty' package.json 2>/dev/null | awk -F/ '{print $NF}'
}

# @internal
function _repo_open() {
	local repo_path=$1
	local repo=$2

	repo=$(_repo_name "$repo") || return 1

	if [[ -z "$repo" ]]; then
		printf 'Usage: repo:%s <repo-name>\n' "${repo_path:-open}" >&2
		return 1
	fi

	open "https://github.com/lewishowles/$repo${repo_path:+/$repo_path}"
}

# @desc  Open the main GitHub page for a repo
# @cat   repo
# @needs jq
function repo:open() {
	_repo_open "" "$1"
}

# @desc  Open the GitHub actions page for a repo
# @cat   repo
# @needs jq
function repo:actions() {
	_repo_open "actions" "$1"
}
