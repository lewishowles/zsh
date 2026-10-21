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

	# Each row is: name | default session left | default week left | default reset offset |
	# account 2 session left | account 2 week left | account 2 reset offset | expected heavier,
	# lighter and exhausted. Quota figures are percentages left. Reset offsets are seconds from
	# test_now, and all session windows last five hours.
	local -a cases=(
		'account 2 week resets within its session window takes the heavier role|29|59|518400|76|14|3600|2 default 0'
		'account 2 week resets in two days keeps both roles on default|29|59|518400|76|14|172800|default default 0'
		'clear winner more than 20 points apart|80|80|518400|40|40|518400|default 2 0'
		'near tie decided by weekly pace|60|60|518400|55|55|86400|2 default 0'
		'exact tie favours default|60|60|518400|60|60|518400|default 2 0'
		'heavier role moves off an account under 15%|10|70|86400|20|20|518400|2 default 0'
		'both roles use an account with enough pace|60|60|518400|10|10|86400|default default 0'
		'weekly pace of exactly 0.25 still takes both roles|60|25|604800|10|10|518400|default default 0'
		'slow weekly pace refuses both roles|20|20|518400|10|10|518400|default 2 0'
		'one account has zero quota|0|0|518400|30|30|518400|2 2 0'
		'both accounts are exhausted|2|2|518400|3|3|518400|2 default 1'
		'soon reset cannot lift low session quota|60|60|518400|10|1|3600|default default 0'
		'weekly reset at session boundary|29|59|518400|76|14|18000|2 default 0'
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

		actual="$(_hcom_quota_allocate hcom:team claude)"
		if [[ "$actual" != "$expected" ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: expected '$expected', got '$actual'"
			(( failures += 1 ))
		fi
	done

	if (( failures > 0 )); then
		print -u2 -r -- "$failures quota allocation case(s) failed"
		return 1
	fi

	print -r -- "PASS: ${#cases} quota allocation cases"
}

main "$@"
