# @desc  Read or append the current repository's HCOM cycle handoff
# @cat   hcom
# @needs trash
function hcom-handoff() {
	local repository_root repository_slug handoff_dir handoff_path action

	if ! repository_root=$(git rev-parse --show-toplevel 2>/dev/null); then
		printf 'hcom-handoff: current directory is not inside a Git repository.\n' >&2
		return 1
	fi

	if ! repository_root=$(cd -P -- "$repository_root" 2>/dev/null && pwd -P); then
		printf 'hcom-handoff: could not resolve the Git repository root.\n' >&2
		return 1
	fi

	if [[ -z "${HOME:-}" ]]; then
		printf 'hcom-handoff: HOME is not set.\n' >&2
		return 1
	fi

	repository_slug="${repository_root:t}"
	handoff_dir="$HOME/.hcom/handoffs"
	handoff_path="$handoff_dir/$repository_slug.md"

	if (( $# == 0 )); then
		printf '%s\n' "$handoff_path"
		if [[ -f "$handoff_path" ]]; then
			cat "$handoff_path"
		else
			printf 'No handoff exists yet at %s.\n' "$handoff_path"
		fi
		return 0
	fi

	action="$1"
	shift

	case "$action" in
		path)
			if (( $# != 0 )); then
				printf 'hcom-handoff: usage: hcom-handoff path\n' >&2
				return 1
			fi

			printf '%s\n' "$handoff_path"
			;;
		append)
			local kind="" body_file="" body_file_set=0 writer_identity="" role_prefix="" timestamp
			local body_with_sentinel="" body="" record=""

			while (( $# > 0 )); do
				case "$1" in
					--kind)
						if (( $# < 2 )); then
							printf 'hcom-handoff: --kind needs a record kind.\n' >&2
							return 1
						fi
						kind="$2"
						shift 2
						;;
					--file)
						if (( $# < 2 )); then
							printf 'hcom-handoff: --file needs a path.\n' >&2
							return 1
						fi
						body_file="$2"
						body_file_set=1
						shift 2
						;;
					*)
						printf 'hcom-handoff: unknown append option: %s\n' "$1" >&2
						return 1
						;;
				esac
			done

			if [[ -z "$kind" ]]; then
				printf 'hcom-handoff: append requires --kind <kind>.\n' >&2
				return 1
			fi

			case "$kind" in
				assignment|checkpoint|claim|decision|diagnostic|continuation|review|closed)
					;;
				*)
					printf 'hcom-handoff: unsupported record kind %s. Expected: assignment, checkpoint, claim, decision, diagnostic, continuation, review, closed.\n' "$kind" >&2
					return 1
					;;
			esac

			if (( body_file_set )); then
				if [[ ! -f "$body_file" ]]; then
					printf 'hcom-handoff: body file not found: %s\n' "$body_file" >&2
					return 1
				fi

				if [[ ! -r "$body_file" ]]; then
					printf 'hcom-handoff: body file is not readable: %s\n' "$body_file" >&2
					return 1
				fi
			fi

			writer_identity="${HCOM_NAME:-}"
			if [[ -z "$writer_identity" ]]; then
				printf 'hcom-handoff: HCOM_NAME must be set before appending a record.\n' >&2
				return 1
			fi

			role_prefix="${writer_identity%-????}"
			if [[ "$role_prefix" == "$writer_identity" || "$role_prefix" != *-* ]]; then
				printf 'hcom-handoff: HCOM_NAME must use <repo>-<role>-<CVCV> or <repo>-<team>-<role>-<CVCV>; got %s.\n' "$writer_identity" >&2
				return 1
			fi

			if ! timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ'); then
				printf 'hcom-handoff: could not create a timestamp.\n' >&2
				return 1
			fi

			(
				if ! mkdir -p -m 700 "$handoff_dir"; then
					printf 'hcom-handoff: could not create handoff directory: %s\n' "$handoff_dir" >&2
					exit 1
				fi

				if ! chmod 700 "$handoff_dir"; then
					printf 'hcom-handoff: could not set handoff directory mode: %s\n' "$handoff_dir" >&2
					exit 1
				fi

				if [[ ! -e "$handoff_path" ]]; then
					if ! : >> "$handoff_path"; then
						printf 'hcom-handoff: could not create handoff file: %s\n' "$handoff_path" >&2
						exit 1
					fi
				fi

				if [[ ! -f "$handoff_path" ]]; then
					printf 'hcom-handoff: handoff path is not a regular file: %s\n' "$handoff_path" >&2
					exit 1
				fi

				if ! chmod 600 "$handoff_path"; then
					printf 'hcom-handoff: could not set handoff file mode: %s\n' "$handoff_path" >&2
					exit 1
				fi

				if (( body_file_set )); then
					if ! body_with_sentinel=$(
						cat "$body_file" || exit 1
						printf '\001'
					); then
						exit 1
					fi
				else
					if ! body_with_sentinel=$(
						cat || exit 1
						printf '\001'
					); then
						exit 1
					fi
				fi

				body="${body_with_sentinel%$'\001'}"

				# Build the full record before writing so concurrent writers can't interleave a partial record.
				record=$(printf '## %s\n- Timestamp: %s\n- Role prefix: %s\n- Writer identity: %s' "$kind" "$timestamp" "$role_prefix" "$writer_identity")
				record+=$'\n\n'
				record+="$body"
				record+=$'\n\n'
				printf '%s' "$record" >> "$handoff_path"
			)
			local append_exit_code=$?

			if (( append_exit_code != 0 )); then
				return "$append_exit_code"
			fi

			printf 'Appended %s record to %s.\n' "$kind" "$handoff_path"
			;;
		close)
			if (( $# != 0 )); then
				printf 'hcom-handoff: usage: hcom-handoff close\n' >&2
				return 1
			fi

			if [[ ! -e "$handoff_path" ]]; then
				printf 'No handoff exists yet at %s.\n' "$handoff_path"
				return 0
			fi

			if [[ ! -f "$handoff_path" ]]; then
				printf 'hcom-handoff: handoff path is not a regular file: %s\n' "$handoff_path" >&2
				return 1
			fi

			if ! trash "$handoff_path"; then
				printf 'hcom-handoff: could not move handoff to Trash: %s\n' "$handoff_path" >&2
				return 1
			fi

			printf 'Moved handoff to Trash: %s\n' "$handoff_path"
			;;
		*)
			printf 'hcom-handoff: usage: hcom-handoff [path|append --kind <kind> [--file <path>]|close]\n' >&2
			return 1
			;;
	esac
}
