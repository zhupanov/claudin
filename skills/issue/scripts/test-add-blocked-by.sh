#!/usr/bin/env bash
# test-add-blocked-by.sh — Regression for skills/issue/scripts/add-blocked-by.sh.
# Self-contained; mocks `gh` via a function-shadow on PATH (matches the pattern
# in scripts/test-redact-secrets.sh).
#
# Coverage:
#   1. 200 success path
#   2. Idempotent 422 with each pinned message fragment ("already exists",
#      "already tracked", "already added", "duplicate dependency")
#   3. 5xx → retry with success on attempt 2
#   4. Non-idempotent 422 → retries → exhaustion → exit 2
#   5. 404 feature-unavailable → immediate fail (no retry)
#   6. Pre-supplied --blocker-id skips the lookup gh api call
#   7. Secret in error response is redacted in ERROR=
#
# Usage: bash test-add-blocked-by.sh
# Exit 0 on success, non-zero on any failure.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
HELPER="$SCRIPT_DIR/add-blocked-by.sh"
TMPDIR_TEST=$(mktemp -d -t test-add-blocked-by-XXXXXX)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASSED=0
FAILED=0

# Mock gh via a fake binary on PATH. Behavior is parameterized by env vars
# read by the fake; each test resets them before invoking the helper.
FAKE_GH_DIR="$TMPDIR_TEST/fake-bin"
mkdir -p "$FAKE_GH_DIR"
cat >"$FAKE_GH_DIR/gh" <<'FAKE_GH'
#!/usr/bin/env bash
# Fake gh. Reads MOCK_GH_SCRIPT (a path to a script returning the desired
# behavior) or falls back to per-arg env-driven dispatch.
#
# Recognized invocations:
#   gh repo view --json nameWithOwner --jq .nameWithOwner
#       => echoes $MOCK_REPO_OUT (default: "owner/repo")
#   gh api /repos/.../issues/N --jq .id
#       => echoes $MOCK_BLOCKER_ID_OUT (default: "777"); exit $MOCK_BLOCKER_ID_RC (default: 0)
#   gh api /repos/.../issues/N/dependencies/blocked_by -X POST --input -
#       => increments $MOCK_POST_COUNT (file at $MOCK_POST_COUNT_FILE) and
#          dispatches via $MOCK_POST_BEHAVIOR (default: "ok"):
#            "ok"             -> exit 0
#            "404"            -> stderr "HTTP 404: Not Found"; exit 1
#            "422-already"    -> stderr "HTTP 422: ...already exists..."; exit 1
#            "422-tracked"    -> stderr "HTTP 422: ...already tracked..."; exit 1
#            "422-added"      -> stderr "HTTP 422: ...already added..."; exit 1
#            "422-duplicate"  -> stderr "HTTP 422: ...duplicate dependency..."; exit 1
#            "422-other"      -> stderr "HTTP 422: validation failed"; exit 1
#            "5xx-then-ok"    -> first 1 attempt 5xx, then ok
#            "secret-leak"    -> stderr containing a fake token; exit 1
case "$1" in
    repo)
        if [[ "$2" == "view" ]]; then
            echo "${MOCK_REPO_OUT:-owner/repo}"
            exit 0
        fi
        ;;
    api)
        # Argument shape: gh api <path> [--jq ...] or gh api <path> -X POST --input -
        path="$2"
        # blocker id lookup
        if [[ "$path" == *"/issues/"* && "$path" != *"/dependencies/"* ]]; then
            echo "${MOCK_BLOCKER_ID_OUT:-777}"
            exit "${MOCK_BLOCKER_ID_RC:-0}"
        fi
        # blocked_by POST
        if [[ "$path" == *"/dependencies/blocked_by" ]]; then
            count_file="${MOCK_POST_COUNT_FILE:-/tmp/mock-post-count}"
            count=$(cat "$count_file" 2>/dev/null || echo 0)
            count=$((count + 1))
            echo "$count" > "$count_file"
            behavior="${MOCK_POST_BEHAVIOR:-ok}"
            case "$behavior" in
                ok) exit 0 ;;
                404) echo "HTTP 404: Not Found" >&2; exit 1 ;;
                422-already) echo "HTTP 422: Validation Failed: dependency already exists" >&2; exit 1 ;;
                422-tracked) echo "HTTP 422: dependency already tracked on this issue" >&2; exit 1 ;;
                422-added) echo "HTTP 422: relationship already added" >&2; exit 1 ;;
                422-duplicate) echo "HTTP 422: duplicate dependency entry" >&2; exit 1 ;;
                422-other) echo "HTTP 422: Validation Failed: locked issue" >&2; exit 1 ;;
                5xx-then-ok)
                    if [[ "$count" -lt 2 ]]; then
                        echo "HTTP 503: Service Unavailable" >&2
                        exit 1
                    fi
                    exit 0
                    ;;
                secret-leak)
                    echo "HTTP 500: leaked token ghp_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA" >&2
                    exit 1
                    ;;
            esac
        fi
        ;;
esac
echo "fake-gh: unrecognized invocation: $*" >&2
exit 1
FAKE_GH
chmod +x "$FAKE_GH_DIR/gh"

# Helper: run add-blocked-by.sh with mocks; capture stdout/stderr/exit
run_helper() {
    local stdout_file stderr_file rc
    stdout_file="$TMPDIR_TEST/stdout.$$"
    stderr_file="$TMPDIR_TEST/stderr.$$"
    set +e
    PATH="$FAKE_GH_DIR:$PATH" "$HELPER" "$@" >"$stdout_file" 2>"$stderr_file"
    rc=$?
    set -e
    LAST_STDOUT=$(cat "$stdout_file")
    LAST_STDERR=$(cat "$stderr_file")
    LAST_RC=$rc
    rm -f "$stdout_file" "$stderr_file"
}

# Helper: assert a substring appears in $LAST_STDOUT
assert_stdout_contains() {
    local needle="$1" desc="$2"
    if echo "$LAST_STDOUT" | grep -qF "$needle"; then
        PASSED=$((PASSED + 1))
        echo "  PASS: $desc"
    else
        FAILED=$((FAILED + 1))
        echo "  FAIL: $desc"
        echo "    stdout: $LAST_STDOUT"
        echo "    stderr: $LAST_STDERR"
    fi
}

assert_rc_eq() {
    local expected="$1" desc="$2"
    if [[ "$LAST_RC" -eq "$expected" ]]; then
        PASSED=$((PASSED + 1))
        echo "  PASS: $desc (rc=$LAST_RC)"
    else
        FAILED=$((FAILED + 1))
        echo "  FAIL: $desc (expected rc=$expected, got $LAST_RC)"
        echo "    stdout: $LAST_STDOUT"
        echo "    stderr: $LAST_STDERR"
    fi
}

# ---------- TEST 1: 200 success path ----------
echo "TEST 1: 200 success"
COUNT_FILE="$TMPDIR_TEST/c.1"
echo 0 > "$COUNT_FILE"
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=ok run_helper --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo
assert_rc_eq 0 "200 path returns 0"
assert_stdout_contains "BLOCKED_BY_ADDED=true" "BLOCKED_BY_ADDED on success"
assert_stdout_contains "CLIENT=100" "echoes client"
assert_stdout_contains "BLOCKER=200" "echoes blocker"

# ---------- TEST 2: idempotent 422 variants ----------
for variant in 422-already 422-tracked 422-added 422-duplicate; do
    echo "TEST 2.$variant: idempotent 422 ($variant)"
    echo 0 > "$COUNT_FILE"
    MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR="$variant" run_helper --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo
    assert_rc_eq 0 "$variant idempotent → rc=0"
    assert_stdout_contains "BLOCKED_BY_ADDED=true" "$variant emits ADDED=true"
done

# ---------- TEST 3: 5xx then OK ----------
echo "TEST 3: 5xx → retry → ok"
echo 0 > "$COUNT_FILE"
# Need to use sleep stub to keep the test fast
SLEEP_STUB_DIR="$TMPDIR_TEST/sleep-stub"
mkdir -p "$SLEEP_STUB_DIR"
cat >"$SLEEP_STUB_DIR/sleep" <<'STUB'
#!/usr/bin/env bash
exit 0
STUB
chmod +x "$SLEEP_STUB_DIR/sleep"
STUB_PATH="$SLEEP_STUB_DIR:$FAKE_GH_DIR:$PATH"
# Re-run the helper with the sleep stub in the front of PATH
set +e
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=5xx-then-ok PATH="$STUB_PATH" "$HELPER" --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo >"$TMPDIR_TEST/stdout.3" 2>"$TMPDIR_TEST/stderr.3"
LAST_RC=$?
set -e
LAST_STDOUT=$(cat "$TMPDIR_TEST/stdout.3")
LAST_STDERR=$(cat "$TMPDIR_TEST/stderr.3")
assert_rc_eq 0 "5xx-then-ok succeeds on retry"
assert_stdout_contains "BLOCKED_BY_ADDED=true" "retry path emits ADDED=true"
COUNT=$(cat "$COUNT_FILE")
if [[ "$COUNT" -ge 2 ]]; then
    PASSED=$((PASSED + 1)); echo "  PASS: retry actually re-invoked POST (count=$COUNT)"
else
    FAILED=$((FAILED + 1)); echo "  FAIL: retry did not re-invoke (count=$COUNT)"
fi

# ---------- TEST 4: non-idempotent 422 → exhaustion ----------
echo "TEST 4: non-idempotent 422 → exhaustion"
echo 0 > "$COUNT_FILE"
set +e
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=422-other PATH="$STUB_PATH" "$HELPER" --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo >"$TMPDIR_TEST/stdout.4" 2>"$TMPDIR_TEST/stderr.4"
LAST_RC=$?
set -e
LAST_STDOUT=$(cat "$TMPDIR_TEST/stdout.4")
LAST_STDERR=$(cat "$TMPDIR_TEST/stderr.4")
assert_rc_eq 2 "422-other → rc=2 after 3 attempts"
assert_stdout_contains "BLOCKED_BY_FAILED=true" "exhaustion emits FAILED=true"
COUNT=$(cat "$COUNT_FILE")
if [[ "$COUNT" -eq 3 ]]; then
    PASSED=$((PASSED + 1)); echo "  PASS: 3 attempts made (count=$COUNT)"
else
    FAILED=$((FAILED + 1)); echo "  FAIL: expected 3 attempts (got count=$COUNT)"
fi

# ---------- TEST 5: 404 feature-unavailable, immediate fail ----------
echo "TEST 5: 404 immediate fail"
echo 0 > "$COUNT_FILE"
set +e
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=404 run_helper --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo
set -e
assert_rc_eq 2 "404 → rc=2"
assert_stdout_contains "BLOCKED_BY_FAILED=true" "404 emits FAILED=true"
assert_stdout_contains "feature-unavailable" "404 emits feature-unavailable in ERROR"
COUNT=$(cat "$COUNT_FILE")
if [[ "$COUNT" -eq 1 ]]; then
    PASSED=$((PASSED + 1)); echo "  PASS: 404 did not retry (count=$COUNT)"
else
    FAILED=$((FAILED + 1)); echo "  FAIL: 404 retried (count=$COUNT)"
fi

# ---------- TEST 6: --blocker-id skips lookup ----------
echo "TEST 6: --blocker-id skips lookup"
# This is implicit in tests 1-5 (we always pass --blocker-id and the lookup
# never fires). Add an explicit no-id test where lookup is needed.
echo 0 > "$COUNT_FILE"
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=ok MOCK_BLOCKER_ID_OUT=999 run_helper --client-issue 100 --blocker-issue 200 --repo owner/repo
assert_rc_eq 0 "no --blocker-id → rc=0 with implicit lookup"
assert_stdout_contains "BLOCKED_BY_ADDED=true" "implicit lookup path emits ADDED=true"

# ---------- TEST 7: secret in error response is redacted ----------
echo "TEST 7: secret leak redaction"
echo 0 > "$COUNT_FILE"
set +e
MOCK_POST_COUNT_FILE="$COUNT_FILE" MOCK_POST_BEHAVIOR=secret-leak PATH="$STUB_PATH" "$HELPER" --client-issue 100 --blocker-issue 200 --blocker-id 555 --repo owner/repo >"$TMPDIR_TEST/stdout.7" 2>"$TMPDIR_TEST/stderr.7"
LAST_RC=$?
set -e
LAST_STDOUT=$(cat "$TMPDIR_TEST/stdout.7")
LAST_STDERR=$(cat "$TMPDIR_TEST/stderr.7")
assert_rc_eq 2 "secret-leak → rc=2"
if echo "$LAST_STDOUT" | grep -qE 'ghp_[A-Za-z0-9]{36}'; then
    FAILED=$((FAILED + 1)); echo "  FAIL: secret token leaked into stdout!"
    echo "    stdout: $LAST_STDOUT"
else
    PASSED=$((PASSED + 1)); echo "  PASS: secret token redacted from stdout"
fi

# ---------- Summary ----------
echo
echo "PASSED: $PASSED"
echo "FAILED: $FAILED"
if [[ "$FAILED" -ne 0 ]]; then
    exit 1
fi
exit 0
