#!/usr/bin/env bash
# test-deny-edit-write.sh — Regression harness for scripts/deny-edit-write.sh.
#
# Black-box contract test: invoke the hook with stdin closed (matcher already
# restricts trigger; the script ignores stdin) and assert on:
#   - exit code 0 on the happy path
#   - stdout is valid JSON
#   - hookSpecificOutput.hookEventName == "PreToolUse"
#   - hookSpecificOutput.permissionDecision == "deny"
#   - hookSpecificOutput.permissionDecisionReason is a non-empty string
#   - idempotency: a second invocation produces byte-identical stdout
#
# Skip-if-no-jq: jq is required for both the hook itself and the assertions
# below; if absent, the harness skips with exit 0 (matching repo precedent in
# scripts/test-sessionstart-health.sh).
#
# Usage:
#   bash scripts/test-deny-edit-write.sh
#
# Exit codes:
#   0 — all assertions passed (or skipped due to missing jq)
#   1 — at least one assertion failed (first failing assertion listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$REPO_ROOT/scripts/deny-edit-write.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "ERROR: hook script not found or not executable: $HOOK" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "SKIP: jq not on PATH; cannot run JSON assertions" >&2
    exit 0
fi

PASS=0
FAIL=0

fail() {
    FAIL=$((FAIL + 1))
    echo "FAIL: $1" >&2
}

pass() {
    PASS=$((PASS + 1))
}

# Capture one invocation for the body of the assertions.
OUT1=$("$HOOK" </dev/null)
EXIT1=$?

# Test 1 — exit code is 0 on the happy path.
if [[ "$EXIT1" -eq 0 ]]; then
    pass
else
    fail "Test 1: expected exit 0, got $EXIT1"
fi

# Test 2 — stdout is valid JSON.
if printf '%s' "$OUT1" | jq empty >/dev/null 2>&1; then
    pass
else
    fail "Test 2: stdout is not valid JSON: $OUT1"
fi

# Test 3 — hookEventName == "PreToolUse".
EVENT=$(printf '%s' "$OUT1" | jq -r '.hookSpecificOutput.hookEventName // empty')
if [[ "$EVENT" == "PreToolUse" ]]; then
    pass
else
    fail "Test 3: expected hookEventName=PreToolUse, got '$EVENT'"
fi

# Test 4 — permissionDecision == "deny".
DECISION=$(printf '%s' "$OUT1" | jq -r '.hookSpecificOutput.permissionDecision // empty')
if [[ "$DECISION" == "deny" ]]; then
    pass
else
    fail "Test 4: expected permissionDecision=deny, got '$DECISION'"
fi

# Test 5 — permissionDecisionReason is a non-empty string.
REASON=$(printf '%s' "$OUT1" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
if [[ -n "$REASON" ]]; then
    pass
else
    fail "Test 5: permissionDecisionReason is empty or missing"
fi

# Test 6 — idempotency: second invocation produces byte-identical stdout.
OUT2=$("$HOOK" </dev/null)
if [[ "$OUT1" == "$OUT2" ]]; then
    pass
else
    fail "Test 6: second invocation produced different stdout"
fi

TOTAL=$((PASS + FAIL))
echo "deny-edit-write.sh: $PASS/$TOTAL passed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
