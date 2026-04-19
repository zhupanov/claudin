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
#   - jq-absent fallback: invoking the hook under a stub-only PATH that hides
#     jq exercises the printf fallback branch and produces byte-identical
#     stdout to the jq -cn branch (enforces the script's INVARIANT)
#
# Harness `jq` requirement: the assertions below validate JSON structure via
# `jq` queries, so harness `jq` is required. The harness fails hard if `jq`
# is missing rather than skipping silently — matching the precedent in
# scripts/test-sessionstart-health.sh:32-35 and ensuring `make lint` cannot
# pass on a machine where the hook's deterministic deny shape cannot be
# verified.
#
# Note: the hook itself (scripts/deny-edit-write.sh) has its own jq-absent
# fallback (static printf path) so the production deny semantics don't
# depend on `jq`. This harness still requires `jq` because validating the
# emitted JSON shape requires a JSON parser.
#
# Usage:
#   bash scripts/test-deny-edit-write.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed (first failing assertion listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$REPO_ROOT/scripts/deny-edit-write.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "ERROR: hook script not found or not executable: $HOOK" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: harness jq not on PATH; cannot validate JSON output" >&2
    exit 1
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

# Test 7 — jq-absent fallback path is byte-identical to the jq -cn path.
# Resolve bash from the ambient PATH before env -i scrubs the environment
# (matches the pattern in scripts/test-sessionstart-health.sh).
BASH_BIN=$(command -v bash)
# Build a stub PATH containing only `bash` and the bare essentials needed by
# the hook itself (`command`, `printf`, `exit` are all bash builtins). We
# deliberately omit any directory where `jq` lives so the `command -v jq`
# guard inside the hook routes through the printf fallback branch.
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-deny-edit-write-stub-XXXXXX")
trap 'rm -rf "$STUB_DIR"' EXIT
ln -s "$BASH_BIN" "$STUB_DIR/bash"
OUT_FALLBACK=$(env -i PATH="$STUB_DIR" "$BASH_BIN" "$HOOK" </dev/null)
if [[ "$OUT1" == "$OUT_FALLBACK" ]]; then
    pass
else
    fail "Test 7: printf fallback diverged from jq -cn output: '$OUT_FALLBACK' vs '$OUT1'"
fi

TOTAL=$((PASS + FAIL))
echo "deny-edit-write.sh: $PASS/$TOTAL passed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
