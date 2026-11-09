#!/usr/bin/env zsh
# Checks that each launcher passes the complete role text to HCOM as an argument.

setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Repository containing the launcher under test.
readonly repo_dir="${0:A:h:h}"
# Temporary executable that checks arguments without launching an agent.
readonly fixture_dir="$(mktemp -d)"
trap 'trash "$fixture_dir"' EXIT

# Keep the test on the explicitly selected account, without probing live quotas.
export HCOM_ACCOUNT=default
# Configuration root required when loading the launcher helpers.
export AGENTS_CONFIG_ROOT="$fixture_dir"
# Role text includes characters that must survive argument passing unchanged.
export HCOM_TEST_ROLE=$'# Team rules\nKeep "quotes", `commands`, $variables and apostrophes: don\'t change them.\n\n# Orchestrator\nRead the named task.'
# Working directory passed through to HCOM.
export HCOM_TEST_DIRECTORY="$fixture_dir"

cat > "$fixture_dir/hcom" <<'STUB'
#!/usr/bin/env zsh
setopt ERR_EXIT NO_UNSET PIPE_FAIL

# Expected arguments for the selected tool, including its supported prompt flag.
expected=("$HCOM_TEST_TOOL" --tag fixture-orchestrator --model fixture-model --dir "$HCOM_TEST_DIRECTORY")
if [[ "$HCOM_TEST_TOOL" == codex ]]; then
	expected+=(--hcom-system-prompt "$HCOM_TEST_ROLE")
else
	expected+=(--append-system-prompt "$HCOM_TEST_ROLE")
fi
expected+=(--hcom-prompt 'Read the named task')
if [[ "$HCOM_TEST_TOOL" == claude ]]; then
	expected+=(--effort medium)
fi

if (( $# != ${#expected} )); then
	print -u2 -- "FAIL: $HCOM_TEST_TOOL received $# arguments; expected ${#expected}"
	exit 1
fi

# Compare each argument separately so multiline text cannot hide a split argument.
for expected_argument in "${expected[@]}"; do
	if [[ "$1" != "$expected_argument" ]]; then
		print -u2 -- "FAIL: $HCOM_TEST_TOOL received an unexpected argument"
		exit 1
	fi
	shift
done
STUB
chmod +x "$fixture_dir/hcom"
export PATH="$fixture_dir:$PATH"
source "$repo_dir/aliases.hcom-core.zsh"

# Check both tools without calling HCOM or a model provider.
for HCOM_TEST_TOOL in codex claude; do
	export HCOM_TEST_TOOL
	_hcom_role_invoke orchestrator "$HCOM_TEST_TOOL" fixture-orchestrator fixture-model "$fixture_dir" "$HCOM_TEST_ROLE" 'Read the named task' medium
done

print -r -- 'PASS: Codex and Claude receive the complete role text and launch arguments'
