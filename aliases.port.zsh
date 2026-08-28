# @desc  Show the process listening on a TCP port
# @cat   port
# Usage: port:find <port>
# @needs lsof
function port:find() {
	local port="${1:-}"

	if [[ "$port" != <-> ]]; then
		printf 'Usage: port:find <port>\n' >&2
		return 1
	fi

	if command lsof -nP "-iTCP:$port" -sTCP:LISTEN; then
		return 0
	fi

	printf 'No process is listening on port %s.\n' "$port"
	return 1
}

# @desc  Kill the process listening on a TCP port
# @cat   port
# Usage: port:kill <port>
# @needs lsof
function port:kill() {
	local port="${1:-}"

	if [[ "$port" != <-> ]]; then
		printf 'Usage: port:kill <port>\n' >&2
		return 1
	fi

	local pids
	pids="$(command lsof -nP "-iTCP:$port" -sTCP:LISTEN -t 2>/dev/null)"

	if [[ -z "$pids" ]]; then
		printf 'No process is listening on port %s.\n' "$port"
		return 1
	fi

	local pid
	for pid in ${(fu)pids}; do
		if command kill "$pid"; then
			printf 'Killed process %s listening on port %s.\n' "$pid" "$port"
		else
			printf 'Unable to kill process %s listening on port %s.\n' "$pid" "$port" >&2
			return 1
		fi
	done
}
