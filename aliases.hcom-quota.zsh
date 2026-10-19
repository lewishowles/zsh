# Chooses HCOM accounts from session and weekly quota using the standalone Python helper.

# Provides EPOCHSECONDS, the current Unix time, which the pace calculation subtracts from
# a reset timestamp to find how much of a quota window is still to run.
zmodload -F zsh/datetime p:EPOCHSECONDS

# Prints one account's cached or fresh quota; failures include a diagnostic on stderr.
#
# The output is six space-separated values, session window before week, each giving
# remaining percentage, reset timestamp and window length in seconds.
#
# @param  {string}  provider
#     Quota source: claude or codex.
# @param  {string}  account
#     Account ID: default or 2, independent of inherited account overrides.
# @param  {integer}  ttl
#     How long a saved reading may still be used, in seconds. The script rejects a value
#     above its per-provider ceiling (Codex 300, Claude 600).
_hcom_quota_probe() {
	command python3 "$ZSH_CONFIG_ROOT/scripts/hcom-quota.py" "$1" "$2" "$3"
}

# Prints one Codex account's quota windows, reusing a cached reading for up to five minutes.
#
# Quota moves slowly enough that a launch a few minutes after the last one can reuse the
# same reading, and the Codex probe is a local call that costs no quota of its own.
#
# @param  {string}  account
#     Account ID: default or 2.
_hcom_quota_codex() {
	_hcom_quota_probe codex "$1" 300
}

# Prints one Claude account's quota windows, reusing a cached reading for up to ten minutes.
#
# Reading Claude's quota means asking Claude, which spends a little of the quota being
# measured, so this holds a reading longer than the Codex probe does. Ten minutes still
# covers the burst of launches that starting or restarting a team produces.
#
# @param  {string}  account
#     Account ID: default or 2.
_hcom_quota_claude() {
	_hcom_quota_probe claude "$1" 600
}

# @desc  Show five-hour and weekly quota used on both Claude and Codex accounts
# @cat   agent
# @needs python3
#
# Prints a table with one row per provider and account, using the same quota cache as
# team start-up. An account that can't be read shows as unavailable, and the other rows
# still print. Colour is checked here rather than at load time so piped output is plain.
# A Claude window that hasn't started yet shows an estimated reset time.
#
# Each window uses the Claude status line's pace bar: the filled cells are the share
# used, the tick marks how far through the window the clock is, and the colour turns
# from green to red as usage gets ahead of the clock.
agent:usage() {
	local provider  # Provider currently being displayed.
	local account  # Account currently being displayed.
	local label  # Name shown at the start of a row.
	local quota_line  # The probe's six quota values on one line.
	local session_window  # The five-hour pace bar, percentage used and reset time.
	local week_window  # The weekly pace bar, percentage used and reset time.
	local bold='' dim='' normal=''  # Terminal styles, empty for plain output.
	local colour=0  # Whether the terminal can show the pace colours.
	local -a quota_values  # The probe's session and weekly fields.

	if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
		colour=1
		bold=$'\033[1m'
		dim=$'\033[2m'
		normal=$'\033[0m'
	fi

	printf '%s%-12s  %-33s%s%s\n' "$bold" '' '5h used' 'week used' "$normal"

	for provider in claude codex; do
		for account in default 2; do
			label="$provider"
			if [[ "$account" == 2 ]]; then
				label+=' (2)'
			fi

			if quota_line="$("_hcom_quota_$provider" "$account" 2>/dev/null)" &&
				read -rA quota_values <<< "$quota_line" &&
				(( ${#quota_values} == 6 )) &&
				session_window="$(_agent_usage_window "$(( 100 - quota_values[1] ))" "${quota_values[2]}" "${quota_values[3]}" "$colour")" &&
				week_window="$(_agent_usage_window "$(( 100 - quota_values[4] ))" "${quota_values[5]}" "${quota_values[6]}" "$colour")"; then
				printf '%-12s  %s    %s\n' "$label" "$session_window" "$week_window"
			else
				printf '%-12s  %sunavailable%s\n' "$label" "$dim" "$normal"
			fi
		done
	done
}

# Prints one quota window the way the Claude status line draws it: a ten-cell pace bar,
# the percentage used and the reset time. Copied from render_window in Agents
# src/adapters/claude/statusline.sh, so change both together. Returns 1 when the reset
# time or window length can't be read.
#
# @param  {number}  used
#     Percentage of the window already used.
# @param  {number}  reset_timestamp
#     Unix time when the window resets, or zero when unknown.
# @param  {number}  window_seconds
#     Length of the window in seconds.
# @param  {integer}  colour
#     One for terminal colour, zero for plain output.
# @param  {integer}  now
#     Current Unix time. Tests pass a fixed value.
_agent_usage_window() {
	local used="$1"  # Percentage used in this window.
	local reset_timestamp="${2%%.*}"  # Whole seconds, because macOS date -r rejects fractions.
	local window_seconds="$3"  # Window duration in seconds.
	local colour="$4"  # 1 for terminal colour, 0 for plain text.
	local now="${5:-$EPOCHSECONDS}"  # Current time, or the fixed time a test passes.
	local reset_text=''  # Local reset time, empty when unknown.

	[[ "$reset_timestamp" == <-> && "$window_seconds" == <-> && "$window_seconds" != 0 ]] || return 1
	if (( reset_timestamp != 0 )); then
		reset_text="$(date -r "$reset_timestamp" '+%a %H:%M' 2>/dev/null)" || return 1
		reset_text="${reset_text:l}"
	fi

	# The bar is drawn in awk for its floating-point maths and to stay close to
	# render_window. The differences are the colour switch, the fixed widths that keep the
	# table columns aligned and the missing label. esc colours text when colour is on, dim
	# greys it, clamp keeps a value in range, and hue picks the pace colour from green
	# through amber to red.
	awk -v used="$used" -v resets="$reset_timestamp" -v window="$window_seconds" -v now="$now" -v colour="$colour" -v reset_text="$reset_text" '
	function esc(r, g, b, s) { if (!colour) return s; return sprintf("%c[38;2;%d;%d;%dm%s%c[0m", 27, r, g, b, s, 27) }
	function dim(s) { return esc(110, 110, 125, s) }
	function clamp(x, lo, hi) { if (x < lo) return lo; if (x > hi) return hi; return x }
	function hue(t,    r, g, b) {
		if (t < 0.5) { r = 90 + t * 2 * 155; g = 220 - t * 2 * 30; b = 160 - t * 2 * 90 }
		else { r = 245; g = 190 - (t - 0.5) * 2 * 110; b = 70 + (t - 0.5) * 2 * 30 }
		return int(r) SUBSEP int(g) SUBSEP int(b)
	}
	BEGIN {
		if (resets == 0) {
			clock = -1
		} else {
			left = resets - now; if (left < 0) left = 0
			elapsed = clamp(window - left, 0, window)
			clock = elapsed / window * 100
		}

		tone = (clock < 0) ? clamp(used, 0, 100) / 100 : clamp(0.5 - (clock - used) / 50, 0, 1)
		split(hue(tone), rgb, SUBSEP)
		r = rgb[1]; g = rgb[2]; b = rgb[3]

		cells = 10
		filled = int(clamp(used, 0, 100) / 100 * cells + 0.5)
		if (clock < 0) { at = -1 }
		else { at = clamp(int(clock / 100 * cells), 0, cells - 1) }

		bar = ""
		for (i = 0; i < cells; i++) {
			if (i == at) bar = bar esc(235, 235, 245, "┃")
			else if (i < filled) bar = bar esc(r, g, b, "█")
			else bar = bar dim("░")
		}

		out = bar " " esc(r, g, b, sprintf("%4s", sprintf("%d%%", used + 0.5)))

		if (resets != 0) out = out dim("  ↻  " reset_text)
		else out = out sprintf("%14s", "")

		printf "%s", out
	}
	'
}

# Prints the account ID for the heavier role, then the lighter one, then 1 when the provider
# has no usable quota left. Ties favour default.
#
# Each account is ranked by its usable quota: its session window left, capped by its
# weekly window left, because an account with an empty week cannot run however fresh its
# session is. The session window usually decides, as that is the quota a single sprint
# draws down. Weekly pace only breaks near-ties: two accounts within 20 points of each
# other on usable quota are interchangeable for the sprint, so the one with quota to burn
# before its weekly reset takes the heavier role.
#
# An account with under 15% usable quota is likely to run dry part-way through a task, so
# it does not take the heavier role while the other account can hold it. Both roles land
# on one account when the other is that close to empty and the survivor has both usable
# quota of its own and a weekly pace that can sustain them, or when the other account has
# nothing left at all. Otherwise two nearly empty accounts keep one role each rather than
# both landing on one.
#
# The third field flags a provider whose accounts are both spent, so team can move the
# whole team onto the other provider rather than split roles across two dead accounts.
#
# A failed probe still selects default for both roles, but returns 2 rather than 0, so the
# caller can stop and ask before launching a team on that allocation. It reports the
# provider as not exhausted, because a probe that did not answer says nothing about how
# much quota is left, and guessing at empty would strand a whole team on one provider.
#
# @param  {string}  command_name
#     The public command shown for an unknown provider.
# @param  {string}  provider
#     claude assigns orchestrator/reviewer; codex assigns implementer/scout.
_hcom_quota_allocate() {
	local command_name="$1"  # Public command responsible for the allocation.
	local provider="$2"  # Provider whose two accounts are being compared.
	local account  # Account currently being probed.
	local available  # Six-value quota line on success, or the probe diagnostic on failure.
	local -i heavier_index=1 lighter_index=2  # Positions in the per-account arrays, default first.
	local -i displaced_index  # Position the heavier role is moved off when that account is too close to empty.
	local -i provider_exhausted  # 1 when both accounts have under 5% usable quota, leaving the provider unusable.

	local -a account_ids=(default 2)  # Account IDs in the order every per-account array uses.
	local -a quota_values  # One account's six probe values, split for indexing.
	local -a usable_remaining  # Percentage each account can still spend: the lower of its session and weekly figures.
	local -a weekly_remaining  # Percentage of each account's weekly window left.
	local -a weekly_reset  # Unix timestamp each account's weekly window refills at.
	local -a weekly_window  # Length of each account's weekly window in seconds.

	local -a pace  # How far ahead of its weekly reset each account is running.
	local -F usable_gap  # Percentage points separating how much usable quota each account has left.

	case "$provider" in
		claude|codex) ;;
		*)
			_hcom_command_error "$command_name" 'unknown quota provider: ' "$provider"
			return 1
			;;
	esac

	for account in "${account_ids[@]}"; do
		if ! available="$("_hcom_quota_$provider" "$account" 2>&1)"; then
			printf '\n[hcom quota probe failed]\n  Provider: %s\n  Account: %s\n  Diagnostic: %s\n  Consequence: every role in this launch lands on the default account, the placement this balancing exists to avoid.\n\n' "$provider" "$account" "${available//$'\n'/; }" >&2
			print -r -- 'default default 0'
			return 2
		fi

		read -rA quota_values <<< "$available"
		# An empty weekly window stops an account whatever its session window says, so
		# the account can only spend the smaller of the two.
		usable_remaining+=("$(( quota_values[1] < quota_values[4] ? quota_values[1] : quota_values[4] ))")
		weekly_remaining+=("${quota_values[4]}")
		weekly_reset+=("${quota_values[5]}")
		weekly_window+=("${quota_values[6]}")
	done

	# Weekly quota left divided by the share of the week still to run. Above 1 means the
	# account is ahead of its own reset and holds quota it would otherwise waste; below 1
	# means it is spending faster than the week can refill. Seconds to reset are floored at
	# one so a window expiring as this runs cannot divide by zero.
	pace[1]=$(( (weekly_remaining[1] / 100.0) / ((weekly_reset[1] - EPOCHSECONDS > 1 ? weekly_reset[1] - EPOCHSECONDS : 1) / (weekly_window[1] * 1.0)) ))
	pace[2]=$(( (weekly_remaining[2] / 100.0) / ((weekly_reset[2] - EPOCHSECONDS > 1 ? weekly_reset[2] - EPOCHSECONDS : 1) / (weekly_window[2] * 1.0)) ))

	if (( usable_remaining[2] > usable_remaining[1] )); then
		heavier_index=2
		lighter_index=1
	fi

	usable_gap=$(( usable_remaining[1] > usable_remaining[2] ? usable_remaining[1] - usable_remaining[2] : usable_remaining[2] - usable_remaining[1] ))

	if (( usable_gap <= 20 )); then
		if (( pace[2] > pace[1] )); then
			heavier_index=2
			lighter_index=1
		elif (( pace[1] > pace[2] )); then
			heavier_index=1
			lighter_index=2
		fi
	fi

	# Under 15% usable quota is likely to run out part-way through a task, so hand
	# the heavier role to the other account whenever that account can still carry it.
	if (( usable_remaining[heavier_index] < 15 && usable_remaining[lighter_index] >= 15 )); then
		displaced_index=$heavier_index
		heavier_index=$lighter_index
		lighter_index=$displaced_index
	fi

	# Taking on a second role needs usable quota to spend it from and a weekly pace to
	# sustain it. A pace under 0.25 means the account holds less than a quarter of the weekly
	# quota its remaining time calls for, so it cannot carry both roles even when the other
	# account is nearly spent.
	if (( usable_remaining[lighter_index] < 15 && usable_remaining[heavier_index] >= 15 && pace[heavier_index] >= 0.25 )); then
		lighter_index="$heavier_index"
	fi

	# A role on an account with nothing left fails as soon as it starts, so when only one
	# account has any quota at all, both roles go to it however little that is.
	if (( usable_remaining[1] <= 0 && usable_remaining[2] > 0 )); then
		heavier_index=2
		lighter_index=2
	elif (( usable_remaining[2] <= 0 && usable_remaining[1] > 0 )); then
		heavier_index=1
		lighter_index=1
	fi

	# Below 5% even the better account cannot carry a role to the end of a task, so the whole
	# provider counts as spent.
	provider_exhausted=$(( usable_remaining[1] < 5 && usable_remaining[2] < 5 ))

	print -r -- "${account_ids[heavier_index]} ${account_ids[lighter_index]} $provider_exhausted"
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
