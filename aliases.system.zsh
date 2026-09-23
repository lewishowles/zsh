# Reports processes with sustained CPU use and manages an optional notification watch.

# Converts a ps duration to seconds, including elapsed days and centiseconds.
#
# @param  {string}  duration
#     The elapsed or CPU time printed by ps.
#
# Prints the duration in seconds, or returns 1 for an invalid value.
_processes_seconds() {
	local duration="$1"  # Duration to parse.
	local days=0  # Full days in an elapsed duration.
	local hours=0  # Full hours in the remaining duration.
	local minutes=0  # Full minutes in the remaining duration.
	local seconds=0  # Seconds, including optional centiseconds.
	local -a parts  # Colon-separated time fields.

	if [[ "$duration" == *-* ]]; then
		days="${duration%%-*}"
		duration="${duration#*-}"
	fi

	parts=("${(@s/:/)duration}")
	case "${#parts}" in
		2) minutes="${parts[1]}"; seconds="${parts[2]}" ;;
		3) hours="${parts[1]}"; minutes="${parts[2]}"; seconds="${parts[3]}" ;;
		*) return 1 ;;
	esac

	if [[ ! "$days" == <-> || ! "$hours" == <-> || ! "$minutes" == <-> || ! "$seconds" == <->(|.<->) ]]; then
		return 1
	fi

	printf '%s\n' "$(( 10#$days * 86400 + 10#$hours * 3600 + 10#$minutes * 60 + seconds ))"
}

# @desc  Report processes with high average CPU use over a minimum age
# @cat   system
# Lists each flagged process with a kill command to copy. It never sends a signal itself.
#
# @param  {string}  options
#     Optional --min-cpu N, --min-age M in minutes, or --quiet.
processes:runaway() {
	local min_cpu=80  # Minimum lifetime average CPU percentage.
	local min_age=30  # Minimum process age in minutes.
	local quiet=0  # Whether to print one summary line.
	local snapshot  # One ps snapshot for the whole report.
	local line pid ppid state elapsed cpu_time current_cpu command  # Fields from ps.
	local age_seconds cpu_seconds average count=0 worst_average=0 worst_pid=0  # Report values.
	local marker  # Marks a process whose parent is launchd, which usually means its own parent exited.
	local width=$(( ${COLUMNS:-100} - 60 ))  # The command column gets whatever width the other columns leave, including the orphaned marker (60 characters).
	local -a rows kills  # Report rows and suggested commands.

	while (( $# )); do
		case "$1" in
			--min-cpu|--min-age)
				if (( $# < 2 )) || [[ ! "$2" == <-> ]]; then
					print -u2 -- "processes:runaway: $1 requires a non-negative integer"
					return 2
				fi
				if [[ "$1" == --min-cpu ]]; then min_cpu="$2"; else min_age="$2"; fi
				shift 2
				;;
			--quiet) quiet=1; shift ;;
			*) print -u2 -- "processes:runaway: unknown option: $1"; return 2 ;;
		esac
	done

	(( width >= 20 )) || width=20
	if ! snapshot="$(command ps -axo pid,ppid,state,etime,time,%cpu,command)"; then
		print -u2 -- 'processes:runaway: could not read processes'
		return 1
	fi

	while IFS= read -r line; do
		[[ "$line" == *PID*PPID* ]] && continue
		read -r pid ppid state elapsed cpu_time current_cpu command <<< "$line"
		[[ "$pid" == <-> && "$ppid" == <-> ]] || continue
		[[ "$command" == *'ps -axo pid,ppid,state,etime,time,%cpu,command'* ]] && continue

		age_seconds="$(_processes_seconds "$elapsed")" || continue
		cpu_seconds="$(_processes_seconds "$cpu_time")" || continue
		(( age_seconds > 0 && age_seconds >= min_age * 60 )) || continue
		average="$(( cpu_seconds * 100.0 / age_seconds ))"
		(( average >= min_cpu )) || continue

		(( count++ ))
		if (( average > worst_average )); then
			worst_average="$average"
			worst_pid="$pid"
		fi

		marker=''
		[[ "$ppid" == 1 ]] && marker=' orphaned'
		rows+=("$(printf '%-8s %-14s %8.1f %8s %-*.*s %8s%s' "$pid" "$elapsed" "$average" "$current_cpu" "$width" "$width" "$command" "$ppid" "$marker")")
		kills+=("kill $pid")
	done <<< "$snapshot"

	if (( quiet )); then
		printf '%s process(es); worst PID %s (%.1f%% average)\n' "$count" "$worst_pid" "$worst_average"
	elif (( count == 0 )); then
		print -- 'Nothing looks stuck.'
	else
		printf '%-8s %-14s %8s %8s %-*s %8s\n' PID AGE 'AVG %' 'NOW %' "$width" COMMAND PPID
		printf '%s\n' "${rows[@]}"
		printf '\n%s\n' "${kills[@]}"
	fi
}

# @desc  Install a 15-minute notification watch for runaway processes
# @cat   system
# @needs trash
# Writes and loads a LaunchAgent for the current user. Does nothing if one is already installed, and removes the file again if loading fails.
processes:watch-install() {
	local label='dev.howles.runaway-processes'  # LaunchAgent label.
	local directory="$HOME/Library/LaunchAgents"  # Per-user agent directory.
	local plist="$directory/$label.plist"  # Agent configuration path.
	local source_file="${${(%):-%x}:A}"  # The LaunchAgent sources this file directly, because a non-interactive login shell does not load the aliases.

	if [[ -f "$plist" ]]; then
		print -- "Already installed: $plist"
		return 0
	fi

	mkdir -p -- "$directory" || return 1
	cat > "$plist" <<EOF_PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>$label</string>
<key>ProgramArguments</key><array>
<string>/bin/zsh</string><string>-lc</string>
<string>source '$source_file'; result=\$(processes:runaway --quiet) || exit; count=\${result%% *}; if (( count &gt; 0 )); then /usr/bin/osascript -e "display notification \"\$result\" with title \"Runaway processes\""; fi</string>
</array>
<key>StartInterval</key><integer>900</integer>
</dict></plist>
EOF_PLIST
	if ! command launchctl bootstrap "gui/$UID" "$plist"; then
		command trash "$plist"
		return 1
	fi
}

# @desc  Remove the runaway-process notification watch
# @cat   system
# @needs trash
# Stops the LaunchAgent, then moves its file to the Trash.
processes:watch-uninstall() {
	local plist="$HOME/Library/LaunchAgents/dev.howles.runaway-processes.plist"  # Installed agent configuration.

	if [[ ! -f "$plist" ]]; then
		print -- 'Runaway-process watch is not installed.'
		return 0
	fi

	command launchctl bootout "gui/$UID" "$plist" || return 1
	command trash "$plist"
}
