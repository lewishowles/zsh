#!/usr/bin/env zsh

set -e

script_root="${0:A:h:h}"
source "$script_root/aliases.hcom-handoff.zsh"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_equal() {
	local expected="$1"
	local actual="$2"
	local message="$3"

	if [[ "$expected" != "$actual" ]]; then
		fail "$message: expected <$expected>, got <$actual>"
	fi
}

assert_contains() {
	local actual="$1"
	local fragment="$2"
	local message="$3"

	if [[ "$actual" != *"$fragment"* ]]; then
		fail "$message: missing <$fragment>"
	fi
}

assert_mode() {
	local expected="$1"
	local target_path="$2"
	local actual

	actual="$(stat -f '%Lp' "$target_path")"
	assert_equal "$expected" "$actual" "mode for $target_path"
}

cleanup() {
	export HOME="$original_home"
	trash "$test_root" 2>/dev/null || true
}

original_home="$HOME"
test_root="$(mktemp -d "${TMPDIR:-/tmp}/hcom-handoff.XXXXXX")"
trap cleanup EXIT

repository_root="$test_root/demo-repository"
home_root="$test_root/home"
mkdir -p "$repository_root/nested" "$home_root/.hcom"
chmod 700 "$home_root/.hcom"
git -C "$repository_root" init -q

export HOME="$home_root"
export HCOM_NAME='demo-repository-implementer-zuzu'
cd "$repository_root/nested"

expected_path="$HOME/.hcom/handoffs/demo-repository.md"
expected_directory="$HOME/.hcom/handoffs"

assert_equal "$expected_path" "$(hcom-handoff path)" 'derived handoff path'
show_output="$(hcom-handoff)"
assert_contains "$show_output" "$expected_path" 'show output path'
assert_contains "$show_output" 'No handoff exists yet' 'empty handoff message'

first_body="$test_root/first-body.md"
printf 'First record body.\n' >> "$first_body"
hcom-handoff append --kind checkpoint --file "$first_body" >/dev/null

assert_mode 700 "$expected_directory"
assert_mode 600 "$expected_path"
first_content="$(<"$expected_path")"
assert_contains "$first_content" '## checkpoint' 'first record kind'
assert_contains "$first_content" 'Role prefix: demo-repository-implementer' 'role prefix'
assert_contains "$first_content" 'Writer identity: demo-repository-implementer-zuzu' 'writer identity'
assert_contains "$first_content" 'First record body.' 'first record body'

second_output="$(printf 'Second record body.\n' | hcom-handoff append --kind decision)"
assert_contains "$second_output" 'Appended decision record' 'second append output'
second_content="$(<"$expected_path")"
assert_contains "$second_content" "$first_content" 'first record preserved'
assert_contains "$second_content" '## decision' 'second record kind'
assert_contains "$second_content" 'Second record body.' 'second record body'

before_unknown="$(<"$expected_path")"
if unknown_output="$(hcom-handoff append --kind unknown <<< 'Rejected body' 2>&1)"; then
	fail 'unknown record kind was accepted'
fi
assert_contains "$unknown_output" 'unsupported record kind' 'unknown record kind message'
after_unknown="$(<"$expected_path")"
assert_equal "$before_unknown" "$after_unknown" 'unknown record kind left file unchanged'

unset HCOM_NAME
if missing_identity_output="$(hcom-handoff append --kind claim <<< 'Rejected identity' 2>&1)"; then
	fail 'append without HCOM_NAME was accepted'
fi
assert_contains "$missing_identity_output" 'HCOM_NAME must be set' 'missing identity message'
assert_equal "$before_unknown" "$(<"$expected_path")" 'missing identity left file unchanged'
export HCOM_NAME='demo-repository-implementer-zuzu'

if close_output="$(hcom-handoff close 2>&1)"; then
	assert_contains "$close_output" 'Moved handoff to Trash' 'close output'
else
	fail "close failed: $close_output"
fi

if [[ -e "$expected_path" ]]; then
	fail 'close left the handoff file in place'
fi

printf 'PASS hcom-handoff fixture\n'
