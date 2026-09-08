# Chooses HCOM accounts from session quota using the standalone Python helper.

# Prints one account's cached or fresh quota; failures include a diagnostic on stderr.
#
# The output is six space-separated values, session window before week, each giving
# remaining percentage, reset timestamp and window length in seconds. Allocation reads
# only the first of them for now.
#
# @param  {string}  provider
#     Quota source: claude or codex.
# @param  {string}  account
#     Account ID: default or 2, independent of inherited account overrides.
# @param  {integer}  ttl
#     Maximum cache lifetime in seconds, capped again by source freshness.
_hcom_quota_probe() {
	command python3 "$ZSH_CONFIG_ROOT/scripts/hcom-quota.py" "$1" "$2" "$3"
}

# Prints one Codex account's quota windows with a 60-second cache.
#
# @param  {string}  account
#     Account ID: default or 2.
_hcom_quota_codex() {
	_hcom_quota_probe codex "$1" 60
}

# Prints one Claude account's quota windows with a cache lasting at most 180 seconds.
#
# @param  {string}  account
#     Account ID: default or 2.
_hcom_quota_claude() {
	_hcom_quota_probe claude "$1" 180
}

# Prints account IDs for the heavier then lighter role, favouring default on ties.
# A failed probe prints one notice and selects default for both roles. If either
# account has less than 15% left or the gap exceeds 30 percentage points, both
# roles use the healthier account.
#
# @param  {string}  provider
#     claude assigns orchestrator/reviewer; codex assigns implementer/scout.
_hcom_quota_allocate() {
	local provider="$1"  # Provider whose two accounts are being compared.
	local account  # Account currently being probed.
	local available  # Six-value quota line on success, or the probe diagnostic on failure.
	local -a session_remaining  # Default then second account, session percentage only.
	local heavier=default lighter=2  # Role assignments when default has more quota.
	local weaker  # Remaining percentage of the account assigned the lighter role.
	local stronger  # Remaining percentage of the account assigned the heavier role.
	local gap  # Difference in remaining percentage points between the accounts.

	case "$provider" in
		claude|codex) ;;
		*)
			printf 'hcom: unknown quota provider: %s\n' "$provider" >&2
			return 1
			;;
	esac

	for account in default 2; do
		if ! available="$("_hcom_quota_$provider" "$account" 2>&1)"; then
			printf 'hcom: %s account %s quota unavailable (%s); falling back to default-account behaviour.\n' "$provider" "$account" "${available//$'\n'/; }" >&2
			print -r -- 'default default'
			return 0
		fi

		session_remaining+=("${available%% *}")
	done

	weaker="${session_remaining[2]}"
	stronger="${session_remaining[1]}"
	if (( session_remaining[2] > session_remaining[1] )); then
		heavier=2
		lighter=default
		weaker="${session_remaining[1]}"
		stronger="${session_remaining[2]}"
	fi

	gap=$(( stronger - weaker ))

	if (( weaker < 15 || gap > 30 )); then
		lighter="$heavier"
	fi

	print -r -- "$heavier $lighter"
}
