# Chooses HCOM accounts from session and weekly quota. The picker needs agent-quota on PATH.

# Provides EPOCHSECONDS, the current Unix time, which _hcom_quota_now reads for the reset and
# pace calculations.
zmodload -F zsh/datetime p:EPOCHSECONDS

# Prints the quota of a provider's default account, then account 2, from one agent-quota run.
#
# Each output line has six space-separated values, session window before week, each
# giving remaining percentage, reset timestamp and window length in seconds. Fails with a
# diagnostic on stderr when agent-quota is missing or fails, or when either account is
# missing, reports an error, or has an unreadable window, because agent-quota still exits
# 0 when a single account cannot be read.
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
					or not isinstance(reset, str) or not reset
					or type(seconds) not in (int, float) or not math.isfinite(seconds)
					or seconds <= 0):
				raise ValueError(f"account {account_id}: {name} quota is invalid")
			values.extend((100 - used, int(datetime.fromisoformat(reset).timestamp()), seconds))
		lines.append(" ".join(map(str, values)))
except (KeyError, TypeError, ValueError, OverflowError) as error:
	print(f"invalid agent-quota response: {error}", file=sys.stderr)
	sys.exit(1)

print("\n".join(lines))
' "$1" <<< "$quota_json"
}

# Prints the account ID for the heavier role, then the lighter one, then 1 when the provider
# has no usable quota left. Ties favour default.
#
# Each account is ranked by its usable quota: its session window left, capped by its
# weekly window left. The cap is dropped when the week resets within one session window,
# because the weekly quota refills before the session quota could run out, and weekly
# quota left unspent at that reset is lost. Weekly pace only breaks near-ties: two
# accounts within 20 points of each other on usable quota are interchangeable for the
# sprint, so the one with quota to burn before its weekly reset takes the heavier role.
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
	local -i account_index  # Position of the account being read, matching account_ids.
	local available  # Both quota lines on success, or the probe diagnostic on failure.
	local -i heavier_index=1 lighter_index=2  # Positions in the per-account arrays, default first.
	local -i displaced_index  # Position the heavier role is moved off when that account is too close to empty.
	local -i provider_exhausted  # 1 when both accounts have under 5% usable quota, leaving the provider unusable.

	local -a account_ids=(default 2)  # Account IDs in the order every per-account array uses.
	local -a quota_values  # One account's six probe values, split for indexing.
	local -a quota_lines  # Both accounts' six-value lines from one agent-quota run.
	local -a usable_remaining  # Percentage each account can still spend: its session figure, capped by its weekly figure unless the week resets within one session window.
	local -a weekly_remaining  # Percentage of each account's weekly window left.
	local -a weekly_reset  # Unix timestamp each account's weekly window refills at.
	local -a weekly_window  # Length of each account's weekly window in seconds.

	local -a pace  # How far ahead of its weekly reset each account is running.
	local -F usable_gap  # Percentage points separating how much usable quota each account has left.
	local -i current_time  # One clock reading shared by the reset and pace calculations.

	case "$provider" in
		claude|codex) ;;
		*)
			_hcom_command_error "$command_name" 'unknown quota provider: ' "$provider"
			return 1
			;;
	esac

	if ! available="$(_hcom_quota_probe "$provider" 2>&1)"; then
		printf '\n[hcom quota probe failed]\n  Provider: %s\n  Diagnostic: %s\n  Consequence: every role in this launch lands on the default account, the placement this balancing exists to avoid.\n\n' "$provider" "${available//$'\n'/; }" >&2
		print -r -- 'default default 0'
		return 2
	fi

	quota_lines=("${(@f)available}")
	current_time="$(_hcom_quota_now)"

	for account_index in {1..2}; do
		read -rA quota_values <<< "${quota_lines[account_index]}"
		# A week that resets within one session window refills before the session quota can
		# run out, so only the session quota limits the account.
		if (( quota_values[5] - current_time <= quota_values[3] )); then
			usable_remaining+=("${quota_values[1]}")
		else
			usable_remaining+=("$(( quota_values[1] < quota_values[4] ? quota_values[1] : quota_values[4] ))")
		fi
		weekly_remaining+=("${quota_values[4]}")
		weekly_reset+=("${quota_values[5]}")
		weekly_window+=("${quota_values[6]}")
	done

	# Weekly quota left divided by the share of the week still to run. Above 1 means the
	# account is ahead of its own reset and holds quota it would otherwise waste; below 1
	# means it is spending faster than the week can refill. Seconds to reset are floored at
	# one so a window expiring as this runs cannot divide by zero.
	pace[1]=$(( (weekly_remaining[1] / 100.0) / ((weekly_reset[1] - current_time > 1 ? weekly_reset[1] - current_time : 1) / (weekly_window[1] * 1.0)) ))
	pace[2]=$(( (weekly_remaining[2] / 100.0) / ((weekly_reset[2] - current_time > 1 ? weekly_reset[2] - current_time : 1) / (weekly_window[2] * 1.0)) ))

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
