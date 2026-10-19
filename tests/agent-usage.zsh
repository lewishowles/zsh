#!/usr/bin/env zsh
# Checks fixed-time pace bars and the four-account usage table without provider calls.

setopt errexit nounset pipefail
export TZ=UTC
# Counts the bar characters as one column each when checking alignment.
export LC_ALL=en_US.UTF-8

# Loads the quota display under test.
source "${0:A:h:h}/aliases.hcom-quota.zsh"

# Prints a focused failure and stops the fixture.
#
# @param  {string}  message
#     The output contract that failed.
fail() {
	print -u2 -- "FAIL: $1"
	exit 1
}

# Fixed time for the pace calculation.
local now=1700000000
# Reset halfway through a one-hour window.
local reset=1700001800
# A plain bar with four filled cells and a tick at the sixth cell.
local plain="$(_agent_usage_window 40 "$reset" 3600 0 "$now")"

[[ "$plain" == '████░┃░░░░  40%  ↻  tue 22:43' ]] || fail 'plain pace and lower-case reset'
[[ "$plain" != *$'\033'* ]] || fail 'plain output contains an escape byte'

# A window without a reset has no clock tick or reset text.
local no_reset="$(_agent_usage_window 25 0 3600 0 "$now")"
[[ "$no_reset" == '███░░░░░░░  25%              ' ]] || fail 'unknown reset pace'

# A coloured bar has the status line tone, dim empty cells and a pale clock tick.
local coloured="$(_agent_usage_window 40 "$reset" 3600 1 "$now")"
[[ "$coloured" == *$'\033[38;2;183;202;106m█'* ]] || fail 'pace tone'
[[ "$coloured" == *$'\033[38;2;235;235;245m┃'* ]] || fail 'clock tick colour'
[[ "$coloured" == *$'\033[38;2;110;110;125m░'* ]] || fail 'empty cell colour'

# Returns a fixed six-field quota reading, or fails for the second account when
# AGENT_USAGE_UNAVAILABLE is 1.
#
# @param  {string}  account
#     Account requested by the table.
_hcom_quota_claude() {
	if [[ "$1" == 2 && "${AGENT_USAGE_UNAVAILABLE:-0}" == 1 ]]; then
		return 1
	fi

	print -r -- '60 1700001800 3600 75 1700300000 604800'
}

# Returns the same fixed six-field quota reading for every account.
#
# @param  {string}  account
#     Account requested by the table.
_hcom_quota_codex() {
	print -r -- '60 1700001800 3600 75 1700300000 604800'
}

# Plain table output must include every account and both used percentages.
local table="$(NO_COLOR=1 agent:usage)"
[[ "$table" == *'5h used'*'week used'* ]] || fail 'used headers'
[[ "${#${(f)table}}" == 5 ]] || fail 'four account rows'
[[ "$table" == *'claude (2)'* && "$table" == *'codex (2)'* ]] || fail 'second accounts'
[[ "$table" == *'40%'*'25%'* ]] || fail 'used percentages'
[[ "$table" != *$'\033'* ]] || fail 'piped table contains an escape byte'

# The header text before the weekly heading, whose length is the weekly column.
local week_heading_prefix="${${(f)table}[1]%%week used*}"
# The first account row, whose weekly bar should start in that column.
local first_row="${${(f)table}[2]}"
[[ "${first_row:${#week_heading_prefix}:1}" == [█░┃] && "${first_row:$(( ${#week_heading_prefix} - 1 )):1}" == ' ' ]] || fail 'weekly column lines up with its heading'

# A failed probe affects its own row without hiding the other accounts.
local unavailable_table="$(AGENT_USAGE_UNAVAILABLE=1 NO_COLOR=1 agent:usage)"
[[ "$unavailable_table" == *'claude (2)    unavailable'* ]] || fail 'unavailable account'
[[ "$unavailable_table" == *'codex (2)'*'25%'* ]] || fail 'available accounts remain visible'

print -r -- 'PASS: agent usage pace bars'
