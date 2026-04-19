#!/usr/bin/env bash
# test-audit-edit-write.sh — Regression test for the dev-only PostToolUse
# audit hook helper (scripts/audit-edit-write.sh).
#
# Four sections:
#   1. Happy path: feed a realistic Edit payload via stdin, assert one line
#      appended, last line parses via `jq .`, has correct .event/.ts/.payload.
#   2. Append semantics: invoke twice with different payloads, assert the log
#      has exactly 2 lines via `jq -se 'length == 2'` (the `-e` flag is
#      critical — plain `jq -s` exits 0 even when output is `false`).
#   3. Empty stdin: capture line count before/after, assert unchanged.
#   4. Invalid JSON stdin: same capture pattern, assert count unchanged.
#
# Usage:
#   bash scripts/test-audit-edit-write.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — one or more assertions failed

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/audit-edit-write.sh"

# NOTE: use TEST_TMPDIR, not TMPDIR — TMPDIR is POSIX-reserved and consulted
# by mktemp/bash/jq for their own temp files; overriding it corrupts those.
TEST_TMPDIR="$(mktemp -d -t claude-audit-test-XXXXXX)"
trap 'rm -rf "$TEST_TMPDIR"' EXIT

export CLAUDE_PROJECT_DIR="$TEST_TMPDIR"
mkdir -p "$TEST_TMPDIR/.claude"
LOG="$TEST_TMPDIR/.claude/hook-audit.log"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_true() {
    local cond_result="$1" label="$2"
    if [[ "$cond_result" == "true" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label")
        echo "  FAIL: $label" >&2
    fi
}

assert_equals() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected: $expected, got: $actual)")
        echo "  FAIL: $label (expected: $expected, got: $actual)" >&2
    fi
}

line_count() {
    if [[ -f "$1" ]]; then
        wc -l < "$1" | tr -d ' '
    else
        echo 0
    fi
}

# ---- Test 1: happy path ----
echo "Test 1: happy path (Edit payload)"
SAMPLE_EDIT='{"tool_name":"Edit","tool_input":{"file_path":"/tmp/foo.txt","old_string":"a","new_string":"b"}}'
printf '%s' "$SAMPLE_EDIT" | "$SCRIPT"

assert_true "$([[ -f "$LOG" ]] && echo true || echo false)" "log file created"
assert_equals "$(line_count "$LOG")" "1" "one line appended"
LAST=$(tail -n 1 "$LOG")
assert_true "$(echo "$LAST" | jq -e . >/dev/null 2>&1 && echo true || echo false)" "last line is valid JSON"
assert_equals "$(echo "$LAST" | jq -r .event)" "PostToolUse" ".event == PostToolUse"
assert_true "$(echo "$LAST" | jq -e -r '.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$")' >/dev/null 2>&1 && echo true || echo false)" ".ts is ISO-8601 UTC"
assert_equals "$(echo "$LAST" | jq -r .payload.tool_name)" "Edit" ".payload.tool_name == Edit"
assert_equals "$(echo "$LAST" | jq -r .payload.tool_input.file_path)" "/tmp/foo.txt" ".payload.tool_input.file_path preserved"

# ---- Test 2: append semantics ----
echo "Test 2: append semantics (invoke twice)"
SAMPLE_WRITE='{"tool_name":"Write","tool_input":{"file_path":"/tmp/bar.txt","content":"hello"}}'
printf '%s' "$SAMPLE_WRITE" | "$SCRIPT"

assert_equals "$(line_count "$LOG")" "2" "two lines after second invocation"
# jq -se — the -e flag is critical. Plain -s exits 0 even when output is `false`.
assert_true "$(jq -se 'length == 2' "$LOG" >/dev/null 2>&1 && echo true || echo false)" "jq -se confirms length == 2"

# Confirm both events are PostToolUse with distinct tool_name values
TOOL_NAMES=$(jq -s '[.[].payload.tool_name] | sort | join(",")' "$LOG" -r)
assert_equals "$TOOL_NAMES" "Edit,Write" "both Edit and Write payloads preserved in order"

# ---- Test 3: empty stdin ----
echo "Test 3: empty stdin appends no line"
BEFORE=$(line_count "$LOG")
printf '' | "$SCRIPT"
AFTER=$(line_count "$LOG")
assert_equals "$AFTER" "$BEFORE" "empty stdin: line count unchanged"

# ---- Test 4: invalid JSON stdin ----
echo "Test 4: invalid JSON stdin appends no line"
BEFORE=$(line_count "$LOG")
printf 'not-json at all' | "$SCRIPT"
AFTER=$(line_count "$LOG")
assert_equals "$AFTER" "$BEFORE" "invalid JSON: line count unchanged"

# ---- Summary ----
echo
echo "----------------------------------------"
echo "PASSED: $PASS"
echo "FAILED: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
