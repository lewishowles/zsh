# Chooses HCOM accounts from session and weekly quota. The picker needs agent-quota on PATH.

# Provides EPOCHSECONDS, the current Unix time, which _hcom_quota_now reads to measure the
# time left before each reset.
zmodload -F zsh/datetime p:EPOCHSECONDS

# Prints the quota of a provider's default account, then account 2, from one agent-quota run.
#
# Each output line has six space-separated values, session window before week, each
# giving remaining percentage, reset timestamp and window length in seconds. A window that
# agent-quota reports with a null reset time is printed with a reset of 0; an empty reset
# time counts as unreadable.
#
# Fails with a diagnostic on stderr when agent-quota is missing or fails, or when either
# account is missing, reports an error, or has an unreadable window, because agent-quota
# still exits 0 when a single account cannot be read.
#
# @param  {string}  provider
#     Quota source: claude or codex.
_hcom_quota_probe() {
	local quota_json  # One agent-quota response containing all accounts.
	local quota_error_file  # Temporary file for agent-quota's own diagnostic.
	local last_error  # Last stderr line from a failed agent-quota request.

	if ! command -v agent-quota >/dev/null; then
		print -u2 -- 'agent-quota is not installed or is not on PATH'
		return 1
	fi

	quota_error_file="$(mktemp)" || return 1
	if ! quota_json="$(command agent-quota --json 2> "$quota_error_file")"; then
		last_error="$(tail -n 1 "$quota_error_file")"
		command rm -f -- "$quota_error_file"
		print -u2 -- "agent-quota could not read quota${last_error:+: $last_error}"
		return 1
	fi
	command rm -f -- "$quota_error_file"

	# Convert the selected provider's JSON windows to the allocator's six-value lines.
	command python3 -c '
import json
import math
import sys
from datetime import datetime

provider = sys.argv[1]

try:
	response = json.load(sys.stdin)
	if response["ok"] is not True:
		raise ValueError("quota request failed")
	accounts = response["data"]["accounts"]
	lines = []
	for account_id in ("default", "2"):
		entry = next((item for item in accounts if item["provider"] == provider and item["account"] == account_id), None)
		if entry is None:
			raise ValueError(f"account {account_id}: quota entry is missing")
		if "error" in entry:
			message = str(entry["error"])[:160]
			raise ValueError(f"account {account_id}: {message}")

		values = []
		for name in ("session", "week"):
			window = entry[name]
			used = window["used_percent"]
			reset = window["resets_at"]
			seconds = window["window_seconds"]
			if (type(used) not in (int, float) or not math.isfinite(used)
					or (reset is not None and (not isinstance(reset, str) or not reset))
					or type(seconds) not in (int, float) or not math.isfinite(seconds)
					or seconds <= 0):
				raise ValueError(f"account {account_id}: {name} quota is invalid")
			reset_time = int(datetime.fromisoformat(reset).timestamp()) if reset is not None else 0
			values.extend((100 - used, reset_time, seconds))
		lines.append(" ".join(map(str, values)))
except (KeyError, TypeError, ValueError, OverflowError) as error:
	print(f"invalid agent-quota response: {error}", file=sys.stderr)
	sys.exit(1)

print("\n".join(lines))
' "$1" <<< "$quota_json"
}

# Prints the heavier and lighter account IDs, then 1 when both accounts have under 5% of
# their weekly quota left, or 0 otherwise.
#
# Each account's score is the lower of its five-hour and weekly room, so the tighter
# limit decides. The higher score takes the heavier role, and ties favour default.
# An account with under 10% of its five-hour quota or under 5% of its weekly quota takes
# no role while the other account is above that floor. When both accounts are under the
# same floor, that floor does not count, and when neither account passes both floors,
# the score alone decides. If only one account can take a role, it takes both.
#
# A failed probe still selects default for both roles, but returns 2 rather than 0, so the
# caller can stop and ask before launching a team on that allocation. It reports the
# provider as not exhausted because the probe did not establish how much quota remains.
# Every call, including one with a failed probe, adds a line to the decision log.
#
# @param  {string}  command_name
#     The public command that asked for the allocation, written to the decision log and
#     shown in the error for an unknown provider.
# @param  {string}  provider
#     claude assigns orchestrator/reviewer; codex assigns implementer/scout.
_hcom_quota_allocate() {
	local command_name="$1"  # Public command responsible for the allocation.
	local provider="$2"  # Provider whose two accounts are being compared.
	local available  # Both quota lines on success, or the probe diagnostic on failure.
	local -i heavier_index=1 lighter_index=2  # Positions in the per-account arrays, default first.
	local -i provider_exhausted  # 1 when both accounts have under 5% weekly quota left.
	local -i current_time  # One clock reading shared by both account scores.
	local -i account_index  # Position of the account being read, matching account_ids.

	local -a account_ids=(default 2)  # Account IDs in the order every per-account array uses.
	local -a quota_values  # One account's six probe values, split for indexing.
	local -a quota_lines  # Both accounts' six-value lines from one agent-quota run.
	local -a session_remaining  # Percentage of each five-hour quota left.
	local -a weekly_remaining  # Percentage of each account's weekly window left.
	local -a account_scores  # Each account's score: the lower of its five-hour and weekly room.
	local -a score_details  # One account's score, limiting window, and both rooms.
	local -a limiting_windows  # Window that set each account's score.
	local -a session_rooms  # Five-hour room for each account.
	local -a weekly_rooms  # Weekly room for each account.
	local -a skipped  # Floor that prevented each account from taking a role.
	local floors_ignored=none  # Floor set aside because both accounts were below it, or all when neither account cleared both floors.
	local -i session_floor_applies  # 1 unless both accounts have under 10% of their five-hour quota left.
	local -i weekly_floor_applies  # 1 unless both accounts have under 5% of their weekly quota left.
	local -a eligible  # Whether each account may take a role under the floors that apply.

	case "$provider" in
		claude|codex) ;;
		*)
			_hcom_command_error "$command_name" 'unknown quota provider: ' "$provider"
			return 1
			;;
	esac

	if ! available="$(_hcom_quota_probe "$provider" 2>&1)"; then
		printf '\n[hcom quota probe failed]\n  Provider: %s\n  Diagnostic: %s\n  Consequence: every role in this launch lands on the default account, the placement this balancing exists to avoid.\n\n' "$provider" "${available//$'\n'/; }" >&2
		_hcom_quota_record_decision "$(_hcom_quota_now)" "$command_name" "$provider" \
			unavailable unavailable unavailable unavailable unavailable unavailable unavailable \
			unavailable unavailable unavailable unavailable unavailable unavailable unavailable \
			default default unavailable unavailable probe-failed
		print -r -- 'default default 0'
		return 2
	fi

	quota_lines=("${(@f)available}")
	current_time="$(_hcom_quota_now)"

	for account_index in {1..2}; do
		read -rA quota_values <<< "${quota_lines[account_index]}"
		read -rA score_details <<< "$(_hcom_quota_score "${quota_lines[account_index]}" "$current_time")"
		session_remaining+=("${quota_values[1]}")
		weekly_remaining+=("${quota_values[4]}")
		account_scores+=("${score_details[1]}")
		limiting_windows+=("${score_details[2]}")
		session_rooms+=("${score_details[3]}")
		weekly_rooms+=("${score_details[4]}")
	done

	session_floor_applies=$(( session_remaining[1] >= 10 || session_remaining[2] >= 10 ))
	weekly_floor_applies=$(( weekly_remaining[1] >= 5 || weekly_remaining[2] >= 5 ))

	for account_index in {1..2}; do
		eligible[account_index]=$(( (! session_floor_applies || session_remaining[account_index] >= 10) && (! weekly_floor_applies || weekly_remaining[account_index] >= 5) ))
		if (( session_floor_applies && session_remaining[account_index] < 10 )); then
			skipped[account_index]=5h-floor
		elif (( weekly_floor_applies && weekly_remaining[account_index] < 5 )); then
			skipped[account_index]=weekly-floor
		else
			skipped[account_index]=none
		fi
	done

	# Each account failing a different floor would leave nothing to launch on, so the
	# score decides alone.
	if (( ! eligible[1] && ! eligible[2] )); then
		eligible=(1 1)
		skipped=(none none)
		floors_ignored=all
	elif (( ! session_floor_applies && ! weekly_floor_applies )); then
		floors_ignored=all
	elif (( ! session_floor_applies )); then
		floors_ignored=5h
	elif (( ! weekly_floor_applies )); then
		floors_ignored=weekly
	fi

	if (( eligible[2] && (! eligible[1] || account_scores[2] > account_scores[1]) )); then
		heavier_index=2
		lighter_index=1
	fi

	if (( ! eligible[lighter_index] )); then
		lighter_index=$heavier_index
	fi

	provider_exhausted=$(( weekly_remaining[1] < 5 && weekly_remaining[2] < 5 ))

	_hcom_quota_record_decision "$current_time" "$command_name" "$provider" \
		"${session_remaining[1]}" "${weekly_remaining[1]}" "$(printf '%.2f' "${session_rooms[1]}")" "$(printf '%.2f' "${weekly_rooms[1]}")" "$(printf '%.2f' "${account_scores[1]}")" "${limiting_windows[1]}" "${skipped[1]}" \
		"${session_remaining[2]}" "${weekly_remaining[2]}" "$(printf '%.2f' "${session_rooms[2]}")" "$(printf '%.2f' "${weekly_rooms[2]}")" "$(printf '%.2f' "${account_scores[2]}")" "${limiting_windows[2]}" "${skipped[2]}" \
		"${account_ids[heavier_index]}" "${account_ids[lighter_index]}" "$floors_ignored" "$provider_exhausted"
	print -r -- "${account_ids[heavier_index]} ${account_ids[lighter_index]} $provider_exhausted"
}

# Prints an account's score, the window that set it (5h or weekly), then its five-hour
# and weekly room, separated by spaces.
#
# @param  {string}  quota_line
#     The account's six probe values, session window before week.
# @param  {number}  current_time
#     Unix time shared by both room calculations.
_hcom_quota_score() {
	local -a quota_values  # One account's session and weekly probe values.
	local -F session_room  # Five-hour quota relative to the time left in that window.
	local -F weekly_room  # Weekly quota relative to the time left in that window.

	read -rA quota_values <<< "$1"
	session_room="$(_hcom_quota_room "${quota_values[1]}" "${quota_values[2]}" "${quota_values[3]}" "$2")"
	weekly_room="$(_hcom_quota_room "${quota_values[4]}" "${quota_values[5]}" "${quota_values[6]}" "$2")"

	if (( session_room <= weekly_room )); then
		printf '%.12g 5h %.12g %.12g\n' "$session_room" "$session_room" "$weekly_room"
	else
		printf '%.12g weekly %.12g %.12g\n' "$weekly_room" "$session_room" "$weekly_room"
	fi
}

# Prints the share of quota left divided by the share of time left in one window.
# A window with no reset time counts as having all of its time left. Above 1 means there
# is quota to spare before the reset; below 1 means it is being used faster than an even
# pace.
#
# @param  {number}  remaining
#     Percentage of the window's quota left.
# @param  {number}  reset
#     Unix time when the window refills, or zero when it has no reset time.
# @param  {number}  window
#     Full window length in seconds.
# @param  {number}  current_time
#     Unix time shared by both accounts.
_hcom_quota_room() {
	local -F remaining="$1"  # Percentage of quota left.
	local -i reset="$2"  # Unix time when the window refills.
	local -F window="$3"  # Full window length in seconds.
	local -i current_time="$4"  # Clock reading for this allocation.
	local -i time_left  # Seconds before the window refills, floored at one.

	if (( reset <= 0 )); then
		printf '%.12g\n' "$(( remaining / 100.0 ))"
		return
	fi

	time_left=$(( reset - current_time > 1 ? reset - current_time : 1 ))
	printf '%.12g\n' "$(( (remaining / 100.0) / (time_left / window) ))"
}

# Appends one allocation decision and keeps only the newest 1000 lines. A log failure
# does not change the account choice or stop a launch.
#
# @param  {number}  timestamp
#     Unix time used for the allocation.
# @param  {string}  command_name
#     Public command that requested the allocation.
# @param  {string}  provider
#     Quota provider whose accounts were compared.
# @param  {number|string}  default_5h_left
#     Five-hour quota left on the default account, or unavailable after a failed probe.
# @param  {number|string}  default_week_left
#     Weekly quota left on the default account, or unavailable after a failed probe.
# @param  {number|string}  default_5h_room
#     Five-hour room on the default account, or unavailable after a failed probe.
# @param  {number|string}  default_week_room
#     Weekly room on the default account, or unavailable after a failed probe.
# @param  {number|string}  default_score
#     Lower room on the default account, or unavailable after a failed probe.
# @param  {string}  default_limit
#     Window that set the default account's score, or unavailable after a failed probe.
# @param  {string}  default_skipped
#     Floor that skipped the default account, or unavailable after a failed probe.
# @param  {number|string}  second_5h_left
#     Five-hour quota left on account 2, or unavailable after a failed probe.
# @param  {number|string}  second_week_left
#     Weekly quota left on account 2, or unavailable after a failed probe.
# @param  {number|string}  second_5h_room
#     Five-hour room on account 2, or unavailable after a failed probe.
# @param  {number|string}  second_week_room
#     Weekly room on account 2, or unavailable after a failed probe.
# @param  {number|string}  second_score
#     Lower room on account 2, or unavailable after a failed probe.
# @param  {string}  second_limit
#     Window that set account 2's score, or unavailable after a failed probe.
# @param  {string}  second_skipped
#     Floor that skipped account 2, or unavailable after a failed probe.
# @param  {string}  heavier
#     Account chosen for the heavier role.
# @param  {string}  lighter
#     Account chosen for the lighter role.
# @param  {string}  floors_ignored
#     Floor set aside because both accounts were below it (5h or weekly), all when
#     neither account cleared both floors, none, or unavailable after a failed probe.
# @param  {number|string}  exhausted
#     1 when both accounts are below the weekly floor, or unavailable after a failed probe.
# @param  {string}  result
#     probe-failed when quota could not be read; omitted on a successful probe.
_hcom_quota_record_decision() {
	local state_dir="${XDG_STATE_HOME:-$HOME/.local/state}/hcom-quota"  # Directory for allocation history.
	local log_file="$state_dir/decisions.log"  # One line per allocation, newest last.
	local temp_file  # Temporary copy of the newest log lines.
	local line_count  # Number of recorded decisions before trimming.
	local result_field=''  # Probe failure marker, omitted after a successful probe.

	if ! command mkdir -p -- "$state_dir" 2>/dev/null; then
		return 0
	fi

	if [[ "${22:-}" == probe-failed ]]; then
		result_field=' result=probe-failed'
	fi
	if ! printf 'timestamp=%s command=%s provider=%s default_5h_left=%s default_week_left=%s default_5h_room=%s default_week_room=%s default_score=%s default_limit=%s default_skipped=%s second_5h_left=%s second_week_left=%s second_5h_room=%s second_week_room=%s second_score=%s second_limit=%s second_skipped=%s heavier=%s lighter=%s floors_ignored=%s exhausted=%s%s\n' "${@:1:21}" "$result_field" >> "$log_file" 2>/dev/null; then
		return 0
	fi

	line_count="$(command wc -l < "$log_file" 2>/dev/null)" || return 0
	if (( line_count <= 1000 )); then
		return 0
	fi

	temp_file="$(command mktemp "$state_dir/.decisions.XXXXXX" 2>/dev/null)" || return 0
	if command tail -n 1000 "$log_file" > "$temp_file" 2>/dev/null; then
		if ! command mv -f -- "$temp_file" "$log_file" 2>/dev/null; then
			command rm -f -- "$temp_file" 2>/dev/null
		fi
	else
		command rm -f -- "$temp_file" 2>/dev/null
	fi
	return 0
}

# Prints the percentage of usage one account can give a role. That is 0 when
# under 5% of its week is left, even if the week resets soon. It is the session
# percentage when the week resets within one session window, because the weekly
# quota refills before the session quota runs out. Otherwise it is the lower of
# the session and weekly percentages. A week with no reset time counts as a full
# week, so the weekly cap applies.
#
# @param  {string}  quota_line
#     The account's probe line: the session's remaining percentage, reset time
#     and window length, then the same three values for the week.
# @param  {number}  current_time
#     Unix time used to compare the weekly reset with the session window.
_hcom_quota_usable() {
	# The account's six probe values.
	local -a quota_values
	# The clock reading shared with the account's other quota comparisons.
	local -i current_time="$2"

	read -rA quota_values <<< "$1"

	if (( quota_values[4] < 5 )); then
		print -r -- 0
	elif (( quota_values[5] > 0 && quota_values[5] - current_time <= quota_values[3] )); then
		print -r -- "${quota_values[1]}"
	else
		print -r -- "$(( quota_values[1] < quota_values[4] ? quota_values[1] : quota_values[4] ))"
	fi
}

# Prints the current Unix time. Tests replace this function to fix the clock.
_hcom_quota_now() {
	print -r -- "$EPOCHSECONDS"
}

# Prints the config directory a solo launch should use, or nothing to stay on the default
# account. Only the heavier role's account from _hcom_quota_allocate matters here, because a
# solo launch is one role. A failed probe prints nothing and exits 0, so the caller launches
# on the default account rather than stopping; the allocator's diagnostic still reaches the
# terminal, so a single session can be moved by hand.
#
# @param  {string}  command_name
#     The public command shown in quota errors.
# @param  {string}  provider
#     "codex" or "claude", which also picks the second-account directory.
_hcom_quota_account_directory() {
	local command_name="$1"  # Public command responsible for the launch.
	local provider="$2"  # Provider whose accounts are compared.
	local allocation  # Allocator output: heavier account, lighter account, exhausted flag.

	if ! allocation="$(_hcom_quota_allocate "$command_name" "$provider")"; then
		return 0
	fi

	if [[ "${allocation%% *}" == 2 ]]; then
		if [[ "$provider" == "codex" ]]; then
			print -r -- "$HOME/.codex-2"
		else
			print -r -- "$HOME/.claude-2"
		fi
	fi
}
