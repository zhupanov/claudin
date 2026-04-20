#!/usr/bin/env bash
# test-deny-edit-write.sh — Regression harness for scripts/deny-edit-write.sh.
#
# Black-box table-driven tests. Asserts on:
#   - deny shape for repo-path Edit/Write/NotebookEdit
#   - allow (empty stdout, exit 0) for /tmp/<file> Write and NotebookEdit
#   - deny for /tmp/../etc/passwd traversal (canonicalizes outside /tmp)
#   - deny for relative paths
#   - fail-closed deny for empty/missing path (was previously passthrough)
#   - fail-closed deny for malformed JSON
#   - NotebookEdit's notebook_path field is honored (no fail-open)
#   - idempotency: a second deny invocation produces byte-identical stdout
#   - jq-absent fallback: invoking the hook under a stub-only PATH that
#     hides jq produces byte-identical stdout to the jq -cn deny branch
#
# Harness `jq` requirement: the assertions below validate JSON structure
# via `jq` queries, so harness `jq` is required. The harness fails hard
# if `jq` is missing rather than skipping silently — matching the
# precedent in scripts/test-sessionstart-health.sh and ensuring
# `make lint` cannot pass on a machine where the hook's deterministic
# deny shape cannot be verified.
#
# Note: the hook itself (scripts/deny-edit-write.sh) has its own
# jq-absent fallback (static printf path) so the production deny
# semantics don't depend on `jq`. This harness still requires `jq`
# because validating the emitted JSON shape requires a JSON parser.
#
# Usage:
#   bash scripts/test-deny-edit-write.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed

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

invoke() {
    # Run the hook with the given JSON payload on stdin; echo stdout.
    local payload="$1"
    printf '%s' "$payload" | "$HOOK"
}

assert_deny() {
    local label="$1"
    local payload="$2"
    local out
    out=$(invoke "$payload")
    if ! printf '%s' "$out" | jq empty >/dev/null 2>&1; then
        fail "$label: stdout is not valid JSON: $out"
        return
    fi
    local decision
    decision=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecision // empty')
    local event
    event=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.hookEventName // empty')
    local reason
    reason=$(printf '%s' "$out" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty')
    if [[ "$event" == "PreToolUse" && "$decision" == "deny" && -n "$reason" ]]; then
        pass
    else
        fail "$label: expected deny shape, got event='$event' decision='$decision' reason='$reason'"
    fi
}

assert_allow() {
    local label="$1"
    local payload="$2"
    local out
    out=$(invoke "$payload")
    if [[ -z "$out" ]]; then
        pass
    else
        fail "$label: expected empty stdout on allow, got: $out"
    fi
}

# T1 — repo-path Write denies.
assert_deny "T1 Write repo path" "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/foo.txt\"}}"

# T2 — /tmp Write allows.
TMP_FILE="/tmp/test-deny-edit-write-$$-$RANDOM.txt"
assert_allow "T2 Write /tmp file" "{\"tool_input\":{\"file_path\":\"$TMP_FILE\"}}"

# T3 — /tmp traversal denies (canonicalizes to /etc/passwd).
assert_deny "T3 traversal /tmp/../etc/passwd" '{"tool_input":{"file_path":"/tmp/../etc/passwd"}}'

# T4 — relative path denies.
assert_deny "T4 relative path" '{"tool_input":{"file_path":"foo.txt"}}'

# T5 — empty / missing path denies (fail-closed).
assert_deny "T5 missing file_path" '{"tool_input":{}}'
assert_deny "T5b empty object" '{}'

# T6 — malformed JSON denies.
assert_deny "T6 malformed JSON" 'not json at all'

# T7 — NotebookEdit with notebook_path under /tmp allows.
TMP_IPYNB="/tmp/test-deny-edit-write-$$-$RANDOM.ipynb"
assert_allow "T7 NotebookEdit notebook_path /tmp" "{\"tool_input\":{\"notebook_path\":\"$TMP_IPYNB\"}}"

# T8 — NotebookEdit with notebook_path under repo denies.
assert_deny "T8 NotebookEdit notebook_path repo" "{\"tool_input\":{\"notebook_path\":\"$REPO_ROOT/notebook.ipynb\"}}"

# T9 — idempotency: two deny invocations produce byte-identical stdout.
OUT_A=$(invoke "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/foo.txt\"}}")
OUT_B=$(invoke "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/foo.txt\"}}")
if [[ "$OUT_A" == "$OUT_B" ]]; then
    pass
else
    fail "T9: deny output not idempotent ('$OUT_A' vs '$OUT_B')"
fi

# T10 — jq-absent fallback byte-identical to jq-present deny.
# Resolve bash from ambient PATH before env -i scrubs the environment.
BASH_BIN=$(command -v bash)
STUB_DIR=$(mktemp -d "${TMPDIR:-/tmp}/test-deny-edit-write-stub-XXXXXX")
trap 'rm -rf "$STUB_DIR"' EXIT
ln -s "$BASH_BIN" "$STUB_DIR/bash"
# jq-absent path denies unconditionally (top-level guard). Compare
# against a jq-present deny produced with the same-shape input.
OUT_JQ_PRESENT=$(invoke "{\"tool_input\":{\"file_path\":\"$REPO_ROOT/foo.txt\"}}")
OUT_JQ_ABSENT=$(env -i PATH="$STUB_DIR" "$BASH_BIN" "$HOOK" <<<"{\"tool_input\":{\"file_path\":\"$REPO_ROOT/foo.txt\"}}")
if [[ "$OUT_JQ_PRESENT" == "$OUT_JQ_ABSENT" ]]; then
    pass
else
    fail "T10: jq-absent deny output diverged from jq-present deny output: '$OUT_JQ_ABSENT' vs '$OUT_JQ_PRESENT'"
fi

TOTAL=$((PASS + FAIL))
echo "deny-edit-write.sh: $PASS/$TOTAL passed"

if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
exit 0
