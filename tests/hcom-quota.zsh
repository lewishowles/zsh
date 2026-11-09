#!/usr/bin/env zsh
# Checks which account the team launcher gives each role, using fixed quota figures and
# a fixed clock.

setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Repository root used to load the allocator without shell startup files.
readonly repo_dir="${0:A:h:h}"
source "$repo_dir/aliases.hcom-quota.zsh"

# Fixed time used for every reset offset in the test matrix.
readonly test_now=1000000

# Prints the fixed time in place of the allocator's live clock.
_hcom_quota_now() {
	print -r -- "$test_now"
}

# Prints both accounts' quota lines for the current case, in the probe's six-value format.
# The figures come from main's locals, which zsh makes visible to functions it calls.
#
# @param  {string}  provider
#     The provider under test. Every case uses Claude's five-hour session window.
_hcom_quota_probe() {
	if (( probe_fails )); then
		print -u2 -r -- 'quota unavailable'
		return 1
	fi

	print -r -- "$default_session $(( test_now + 18000 )) 18000 $default_week $(( test_now + default_reset )) 604800"
	print -r -- "$second_session $(( test_now + 18000 )) 18000 $second_week $(( test_now + second_reset )) 604800"
}

# Runs each quota case and reports every mismatch before returning failure.
main() {
	local -a fields  # A case's name, quota figures, reset offsets, and expected allocation.
	local -i failures=0  # Number of allocations that differed from the matrix.
	local test_case  # One pipe-separated row from the case matrix.
	local actual  # Heavier account, lighter account, and exhausted flag returned by the allocator.
	local default_session default_week default_reset  # Default account's remaining percentages and reset offset.
	local second_session second_week second_reset  # Account 2's remaining percentages and reset offset.
	local expected  # The allocation this row requires.
	local expected_rule  # Rule required for this allocation.
	local decision  # Newest line appended to the allocation log.
	local -i probe_fails=0  # Whether the quota probe should fail for this case.
	local -i line_count  # Number of decisions after each allocation.
	local -i case_count=0  # Number of allocations run from the matrix.
	local state_dir  # Isolated state root so tests never write to the user's log.
	local log_file  # Decision log inside the isolated state root.

	state_dir="$(command mktemp -d)" || return 1
	export XDG_STATE_HOME="$state_dir"
	log_file="$state_dir/hcom-quota/decisions.log"
	trap 'command rm -rf -- "$XDG_STATE_HOME"' EXIT

	# Each row is: name | default session left | default week left | default reset offset |
	# account 2 session left | account 2 week left | account 2 reset offset | expected heavier,
	# lighter and exhausted | expected rule | expected default usable | expected account 2 usable.
	# Quota figures are percentages left. Reset offsets are seconds from test_now, and all
	# session windows last five hours.
	local -a cases=(
		'account 2 empty week resetting within its session window gives both roles to default|29|59|518400|76|0|3600|default default 0|only-account-left|29|0'
		'account 2 under five percent of its week resetting within its session window gives both roles to default|29|59|518400|76|4|3600|default default 0|only-account-left|29|0'
		'both accounts under five percent of their week resetting within the session window flag the provider as spent|60|3|3600|76|4|3600|2 default 1|weekly-pace|0|0'
		'account 2 week resets within its session window takes the heavier role|29|59|518400|76|14|3600|2 default 0|ahead-of-reset|29|76'
		'account 2 week resets in two days keeps both roles on default|29|59|518400|76|14|172800|default default 0|weekly-pace+consolidate|29|14'
		'clear winner more than 20 points apart|80|80|518400|40|40|518400|default 2 0|more-usable|80|40'
		'account 2 spends quota before reset despite a large usable gap|44|92|570240|77|19|90000|2 default 0|ahead-of-reset|44|19'
		'account 2 ahead of reset but under 15% gives both roles to default|44|92|570240|14|19|90000|default default 0|protect-nearly-empty+consolidate|44|14'
		'both accounts ahead of reset use the usable quota order|90|90|518400|40|40|172800|default 2 0|more-usable|90|40'
		'near tie decided by weekly pace|60|60|518400|55|55|345600|2 default 0|weekly-pace|60|55'
		'exact tie favours default|60|60|518400|60|60|518400|default 2 0|tie-default|60|60'
		'heavier role moves off an account under 15%|10|70|86400|20|20|518400|2 default 0|protect-nearly-empty|10|20'
		'both roles use an account with enough pace|60|60|518400|10|10|86400|default default 0|more-usable+consolidate|60|10'
		'weekly pace of exactly 0.25 still takes both roles|60|25|604800|10|10|518400|default default 0|weekly-pace+consolidate|25|10'
		'slow weekly pace refuses both roles|20|20|518400|10|10|518400|default 2 0|weekly-pace|20|10'
		'one account has zero quota|0|0|518400|30|30|518400|2 2 0|only-account-left|0|30'
		'both accounts are exhausted|2|2|518400|3|3|518400|2 default 1|weekly-pace|0|0'
		'soon reset cannot lift low session quota|60|60|518400|10|1|3600|default default 0|only-account-left|60|0'
		'weekly reset at session boundary|29|59|518400|76|14|18000|2 default 0|ahead-of-reset|29|76'
	)

	for test_case in "${cases[@]}"; do
		fields=("${(@s:|:)test_case}")
		default_session="${fields[2]}"
		default_week="${fields[3]}"
		default_reset="${fields[4]}"
		second_session="${fields[5]}"
		second_week="${fields[6]}"
		second_reset="${fields[7]}"
		expected="${fields[8]}"
		expected_rule="${fields[9]}"

		actual="$(_hcom_quota_allocate hcom:team claude)"
		(( case_count += 1 ))
		if [[ "$actual" != "$expected" ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: expected '$expected', got '$actual'"
			(( failures += 1 ))
		fi

		line_count="$(command wc -l < "$log_file")"
		if (( line_count != case_count )); then
			print -u2 -r -- "FAIL: ${fields[1]}: expected $case_count decision lines, got $line_count"
			(( failures += 1 ))
		fi

		decision="$(command tail -n 1 "$log_file")"
		if [[ "$decision" != *"timestamp=$test_now command=hcom:team provider=claude default_usable=${fields[10]} default_weekly=$default_week default_reset=$(( test_now + default_reset )) second_usable=${fields[11]} second_weekly=$second_week second_reset=$(( test_now + second_reset )) heavier=${expected%% *} lighter=${${expected#* }%% *} exhausted=${expected##* } rule="* ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: decision line has incorrect fields: $decision"
			(( failures += 1 ))
		fi

		if [[ "$decision" != *" rule=$expected_rule" ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: expected rule $expected_rule, got $decision"
			(( failures += 1 ))
		fi
	done

	probe_fails=1
	if actual="$(_hcom_quota_allocate hcom:team claude 2>/dev/null)"; then
		print -u2 -r -- 'FAIL: failed probe returned success'
		(( failures += 1 ))
	elif [[ "$actual" != 'default default 0' ]]; then
		print -u2 -r -- "FAIL: failed probe returned '$actual'"
		(( failures += 1 ))
	fi
	decision="$(command tail -n 1 "$log_file")"
	if [[ "$decision" != "timestamp=$test_now command=hcom:team provider=claude default_usable=unavailable default_weekly=unavailable default_reset=unavailable second_usable=unavailable second_weekly=unavailable second_reset=unavailable heavier=default lighter=default exhausted=0 rule=probe-failed" ]]; then
		print -u2 -r -- "FAIL: failed probe decision: $decision"
		(( failures += 1 ))
	fi

	# A full log drops its oldest entry when another decision is recorded.
	command rm -f -- "$log_file"
	repeat 1000 print -r -- old >> "$log_file"
	probe_fails=0
	actual="$(_hcom_quota_allocate hcom:team claude)"
	line_count="$(command wc -l < "$log_file")"
	if (( line_count != 1000 )) || [[ "$(command head -n 1 "$log_file")" != old || "$(command tail -n 1 "$log_file")" != *' rule='* ]]; then
		print -u2 -r -- 'FAIL: decision log did not keep the newest 1000 lines'
		(( failures += 1 ))
	fi

	if (( failures > 0 )); then
		print -u2 -r -- "$failures quota allocation case(s) failed"
		return 1
	fi

	print -r -- "PASS: ${#cases} quota allocation cases"
}

main "$@"
