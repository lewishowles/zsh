#!/usr/bin/env zsh
# Checks that generated command rows keep pipes inside their table cells.

setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Repository root used to load the table generator without shell startup files.
readonly repo_dir="${0:A:h:h}"
source "$repo_dir/aliases.discovery.zsh"

# Supplies one command with a pipe in every generated cell, and one without any pipes.
_alias_parse() {
	printf '%s\t%s\t%s\t%s\t%s\n' 'test' 'pipe|name' 'A|B' '' 'pipe|name first|second'
	printf '%s\t%s\t%s\t%s\t%s\n' 'test' 'plain' 'No pipes' '' 'plain argument'
}

# Generates a table and checks its visible rows and column count.
main() {
	# Temporary README that the generator can replace between its sentinels.
	local temp_file
	temp_file=$(mktemp "${TMPDIR:-/tmp}/zsh-docs-table.XXXXXX")
	trap "trash ${(q)temp_file} >/dev/null" EXIT
	printf '<!-- commands:start -->\n<!-- commands:end -->\n' > "$temp_file"

	_docs_write "$temp_file"

	if ! grep -Fqx '| `pipe\|name` | first\|second | A\|B |' "$temp_file"; then
		print -u2 -r -- 'FAIL: pipes are not escaped in every generated cell'
		return 1
	fi
	if ! grep -Fqx '| `plain` | argument | No pipes |' "$temp_file"; then
		print -u2 -r -- 'FAIL: the row without pipes changed'
		return 1
	fi

	# Removes escaped pipes from each command row, so the pipes left over mark
	# the three columns, and checks that both sample rows were found.
	if ! awk '
		/^\| `/ {
			row = $0
			gsub(/\\\|/, "", row)

			if (split(row, cells, /\|/) != 5) {
				exit 1
			}

			rows++
		}

		END {
			if (rows != 2) {
				exit 1
			}
		}
	' "$temp_file"; then
		print -u2 -r -- 'FAIL: a generated row does not have three columns'
		return 1
	fi

	print -r -- 'PASS: pipes stay inside all three command-table cells'
}

main "$@"
