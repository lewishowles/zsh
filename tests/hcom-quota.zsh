#!/usr/bin/env zsh
# Checks account selection with fixed quota figures and a fixed clock.

setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Repository root used to load the allocator without shell startup files.
readonly repo_dir="${0:A:h:h}"
source "$repo_dir/aliases.hcom-quota.zsh"

# Keeps the real probe under another name, so the live-probe case can still call it
# after the stub below replaces it.
functions -c _hcom_quota_probe _hcom_quota_probe_live

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
#     The provider under test.
_hcom_quota_probe() {
	if (( use_live_probe )); then
		_hcom_quota_probe_live "$@"
		return
	fi

	if (( probe_fails )); then
		print -u2 -r -- 'quota unavailable'
		return 1
	fi

	print -r -- "$default_session $default_session_reset 18000 $default_week $default_week_reset 604800"
	print -r -- "$second_session $second_session_reset 18000 $second_week $second_week_reset 604800"
}

# Runs the quota cases and reports every mismatch before returning failure.
main() {
	local -a fields  # A case's name, quota figures, reset offsets, and expected allocation.
	local -i failures=0  # Number of allocations that differed from the matrix.
	local test_case  # One pipe-separated row from the case matrix.
	local actual  # Heavier account, lighter account, and exhausted flag returned by the allocator.
	local default_session default_week  # Default account's remaining percentages.
	local second_session second_week  # Account 2's remaining percentages.
	local -i default_session_reset default_week_reset  # Default account's reset timestamps.
	local -i second_session_reset second_week_reset  # Account 2's reset timestamps.
	local expected  # The allocation this row requires.
	local decision  # Newest line appended to the allocation log.
	local expected_decision  # Complete line required for this case's quota figures.
	local -a default_score_details second_score_details  # Score, limit, and rooms for each fixture account.
	local -i probe_fails=0  # Whether the quota probe should fail for this case.
	local -i use_live_probe=0  # Whether this case reads the JSON stub through the real probe.
	local -i line_count  # Number of decisions after each allocation.
	local -i case_count=0  # Number of allocations run from the matrix.
	local -i probe_exit_code  # Exit code from the allocator when the live probe rejects invalid quota.
	local -a usable_cases  # Probe lines and expected usable percentages for focused checks.
	local usable_case  # One focused usable-percentage check.
	local usable_actual  # Usable percentage returned for the focused check.
	local state_dir  # Isolated state root so tests never write to the user's log.
	local log_file  # Decision log inside the isolated state root.

	state_dir="$(command mktemp -d)" || return 1
	export XDG_STATE_HOME="$state_dir"
	log_file="$state_dir/hcom-quota/decisions.log"
	trap 'command rm -rf -- "$XDG_STATE_HOME"' EXIT

	# Each row is: name | provider | default session left | session reset offset | default
	# week left | week reset offset | account 2 session left | session reset offset |
	# account 2 week left | week reset offset | expected heavier, lighter, exhausted |
	# default skipped | account 2 skipped | floors ignored.
	# A zero reset offset means no reset time. All session windows last five hours.
	local -a cases=(
		'Claude figures from 12 November favour account 2|claude|3|900|59|397440|58|900|94|509760|2 2 0|5h-floor|none|none'
		'Codex figures from 12 November favour default|codex|19|1380|18|172800|77|1380|13|172264|default 2 0|none|none|none'
		'weekly reset within five-hour window raises weekly room|claude|40|18000|20|604800|35|18000|10|3600|2 default 0|none|none|none'
		'missing weekly reset uses all time left|claude|40|18000|20|0|30|18000|35|604800|2 default 0|none|none|none'
		'account under five-hour floor is skipped|claude|9|60|80|604800|20|18000|20|604800|2 2 0|5h-floor|none|none'
		'account under weekly floor is skipped|claude|50|18000|4|60|20|18000|20|604800|2 2 0|weekly-floor|none|none'
		'both under five-hour floor use score|claude|3|900|50|604800|8|18000|50|604800|default 2 0|none|none|5h'
		'both under five-hour floor still enforce weekly floor|claude|3|18000|50|604800|8|900|4|60|default default 0|none|weekly-floor|5h'
		'both under weekly floor use score and exhaust provider|claude|50|18000|3|3600|60|18000|4|604800|default 2 1|none|none|weekly'
		'crossed floors use score when neither passes both|claude|9|18000|60|604800|30|18000|4|604800|default 2 0|none|none|all'
		'crossed floors favour account 2 when its score is higher|claude|3|18000|60|604800|30|18000|4|3600|2 default 0|none|none|all'
		'both accounts under both floors use score|claude|3|18000|3|604800|4|18000|4|604800|2 default 1|none|none|all'
		'account exactly on both floors remains eligible|claude|10|18000|5|604800|9|60|4|60|default default 0|none|5h-floor|none'
		'exact score tie favours default|claude|60|18000|60|604800|60|18000|60|604800|default 2 0|none|none|none'
	)

	for test_case in "${cases[@]}"; do
		fields=("${(@s:|:)test_case}")
		default_session="${fields[3]}"
		default_session_reset=$(( fields[4] == 0 ? 0 : test_now + fields[4] ))
		default_week="${fields[5]}"
		default_week_reset=$(( fields[6] == 0 ? 0 : test_now + fields[6] ))
		second_session="${fields[7]}"
		second_session_reset=$(( fields[8] == 0 ? 0 : test_now + fields[8] ))
		second_week="${fields[9]}"
		second_week_reset=$(( fields[10] == 0 ? 0 : test_now + fields[10] ))
		expected="${fields[11]}"

		actual="$(_hcom_quota_allocate hcom:team "${fields[2]}")"
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
		read -rA default_score_details <<< "$(_hcom_quota_score "$default_session $default_session_reset 18000 $default_week $default_week_reset 604800" "$test_now")"
		read -rA second_score_details <<< "$(_hcom_quota_score "$second_session $second_session_reset 18000 $second_week $second_week_reset 604800" "$test_now")"
		expected_decision="timestamp=$test_now command=hcom:team provider=${fields[2]}"
		expected_decision+=" default_5h_left=$default_session default_week_left=$default_week default_5h_room=$(printf '%.2f' "${default_score_details[3]}") default_week_room=$(printf '%.2f' "${default_score_details[4]}") default_score=$(printf '%.2f' "${default_score_details[1]}") default_limit=${default_score_details[2]} default_skipped=${fields[12]}"
		expected_decision+=" second_5h_left=$second_session second_week_left=$second_week second_5h_room=$(printf '%.2f' "${second_score_details[3]}") second_week_room=$(printf '%.2f' "${second_score_details[4]}") second_score=$(printf '%.2f' "${second_score_details[1]}") second_limit=${second_score_details[2]} second_skipped=${fields[13]}"
		expected_decision+=" heavier=${expected%% *} lighter=${${expected#* }%% *} floors_ignored=${fields[14]} exhausted=${expected##* }"
		if [[ "$decision" != "$expected_decision" ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: decision line has incorrect fields: $decision"
			(( failures += 1 ))
		fi
		if [[ "${fields[1]}" == 'Claude figures from 12 November favour account 2' && ( "$decision" != *'default_5h_room=0.60 default_week_room=0.90 default_score=0.60 default_limit=5h'* || "$decision" != *'second_5h_room=11.60 second_week_room=1.12 second_score=1.12 second_limit=weekly'* ) ]]; then
			print -u2 -r -- "FAIL: Claude fixture has incorrect rooms or limits: $decision"
			(( failures += 1 ))
		fi
	done

	# The team launcher still shows each account's usable quota, so check that figure
	# directly. Each row is: name | probe line | expected usable percentage.
	usable_cases=(
		'weekly quota below five percent|40 1018000 18000 4 1003600 604800|0'
		'weekly reset within one session window|40 1018000 18000 20 1003600 604800|40'
		'weekly quota caps session when reset is later|40 1018000 18000 20 1604800 604800|20'
		'weekly quota caps session when reset is missing|40 1018000 18000 20 0 604800|20'
	)
	for usable_case in "${usable_cases[@]}"; do
		fields=("${(@s:|:)usable_case}")
		usable_actual="$(_hcom_quota_usable "${fields[2]}" "$test_now")"
		if [[ "$usable_actual" != "${fields[3]}" ]]; then
			print -u2 -r -- "FAIL: ${fields[1]}: expected '${fields[3]}', got '$usable_actual'"
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
	if [[ "$decision" != "timestamp=$test_now command=hcom:team provider=claude default_5h_left=unavailable default_week_left=unavailable default_5h_room=unavailable default_week_room=unavailable default_score=unavailable default_limit=unavailable default_skipped=unavailable second_5h_left=unavailable second_week_left=unavailable second_5h_room=unavailable second_week_room=unavailable second_score=unavailable second_limit=unavailable second_skipped=unavailable heavier=default lighter=default floors_ignored=unavailable exhausted=unavailable result=probe-failed" ]]; then
		print -u2 -r -- "FAIL: failed probe decision: $decision"
		(( failures += 1 ))
	fi

	# A full log drops its oldest entry when another decision is recorded.
	command rm -f -- "$log_file"
	repeat 1000 print -r -- old >> "$log_file"
	probe_fails=0
	actual="$(_hcom_quota_allocate hcom:team claude)"
	line_count="$(command wc -l < "$log_file")"
	if (( line_count != 1000 )) || [[ "$(command head -n 1 "$log_file")" != old || "$(command tail -n 1 "$log_file")" != *' floors_ignored=none exhausted=0' ]]; then
		print -u2 -r -- 'FAIL: decision log did not keep the newest 1000 lines'
		(( failures += 1 ))
	fi

	# The live probe must pass a missing reset to the allocator as zero.
	command cat > "$state_dir/agent-quota" <<'EOF'
#!/usr/bin/env zsh
print -r -- '{"ok":true,"data":{"accounts":[{"provider":"claude","account":"default","session":{"used_percent":60,"resets_at":"1970-01-12T18:46:40+00:00","window_seconds":18000},"week":{"used_percent":80,"resets_at":null,"window_seconds":604800}},{"provider":"claude","account":"2","session":{"used_percent":70,"resets_at":"1970-01-12T18:46:40+00:00","window_seconds":18000},"week":{"used_percent":65,"resets_at":"1970-01-19T13:46:40+00:00","window_seconds":604800}}]}}'
EOF
	command chmod +x "$state_dir/agent-quota"
	export PATH="$state_dir:$PATH"
	use_live_probe=1
	actual="$(_hcom_quota_allocate hcom:team claude)"
	decision="$(command tail -n 1 "$log_file")"
	if [[ "$actual" != '2 default 0' || "$decision" != *' default_week_room=0.20 default_score=0.20 default_limit=weekly '* ]]; then
		print -u2 -r -- "FAIL: null reset did not reach the allocator as zero: $actual; $decision"
		(( failures += 1 ))
	fi

	# Only null means a window has no reset time, so an empty reset must fail the probe.
	command sed 's/"resets_at":null/"resets_at":""/' "$state_dir/agent-quota" > "$state_dir/agent-quota-empty"
	command mv -f "$state_dir/agent-quota-empty" "$state_dir/agent-quota"
	command chmod +x "$state_dir/agent-quota"
	if actual="$(_hcom_quota_allocate hcom:team claude 2>/dev/null)"; then
		print -u2 -r -- 'FAIL: empty reset returned success'
		(( failures += 1 ))
	else
		probe_exit_code=$?
		if (( probe_exit_code != 2 )) || [[ "$actual" != 'default default 0' ]]; then
			print -u2 -r -- "FAIL: empty reset returned exit $probe_exit_code and '$actual'"
			(( failures += 1 ))
		fi
	fi
	decision="$(command tail -n 1 "$log_file")"
	if [[ "$decision" != *' heavier=default lighter=default floors_ignored=unavailable exhausted=unavailable result=probe-failed' ]]; then
		print -u2 -r -- "FAIL: empty reset did not record probe failure: $decision"
		(( failures += 1 ))
	fi

	if (( failures > 0 )); then
		print -u2 -r -- "$failures quota allocation case(s) failed"
		return 1
	fi

	print -r -- "PASS: ${#cases} quota allocation cases"
}

main "$@"
