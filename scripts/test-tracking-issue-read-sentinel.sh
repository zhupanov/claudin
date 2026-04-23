#!/usr/bin/env bash
# test-tracking-issue-read-sentinel.sh — regression harness for
# scripts/tracking-issue-read.sh's --sentinel branch.
#
# Pins the ADOPTED= field contract defined by issue #359 for Phase 3
# consumption: allowed values (true|false), absence semantics (empty ==
# unusable, NEVER false), parser behavior (column-0 keys only, first
# match wins, BOM stripping, trailing \r stripping, other trailing
# whitespace preserved), and exact stdout shape on all paths.
#
# Structure mirrors the shared-helpers pattern of
# scripts/test-tracking-issue-write.sh (set -euo pipefail, REPO_ROOT,
# assert_* helpers, mktemp sandbox, PASS/FAIL accounting). No gh stub
# needed — --sentinel mode is purely local.
#
# Usage:
#   bash scripts/test-tracking-issue-read-sentinel.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — any assertion failed (summary at EOF)
#
# Conventions: Bash 3.2-safe.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
READ_SCRIPT="$REPO_ROOT/scripts/tracking-issue-read.sh"

if [[ ! -x "$READ_SCRIPT" ]]; then
    echo "FAIL: $READ_SCRIPT not found or not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

# On assertion failure, also surface LAST_STDERR (set by run_sentinel)
# so any regression that emits unexpected warnings / errors to stderr is
# visible in local debug output and CI logs.
print_stderr_if_any() {
    if [[ -n "${LAST_STDERR:-}" ]]; then
        echo "       stderr: $(printf '%q' "$LAST_STDERR")" >&2
    fi
}

assert_equal_stdout() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label")
        echo "  FAIL: $label" >&2
        echo "       expected (quoted): $(printf '%q' "$expected")" >&2
        echo "       actual   (quoted): $(printf '%q' "$actual")" >&2
        print_stderr_if_any
    fi
}

assert_equal_exit() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label")
        echo "  FAIL: $label (expected exit $expected, got $actual)" >&2
        print_stderr_if_any
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label")
        echo "  FAIL: $label (missing needle: $needle)" >&2
        echo "       haystack: $(printf '%q' "$haystack")" >&2
        print_stderr_if_any
    fi
}

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-tracking-issue-read-sentinel-XXXXXX")
# shellcheck disable=SC2317
trap 'rm -rf "$TMPROOT"' EXIT

# Helper: invoke --sentinel and capture stdout + exit code + stderr.
# Sets globals LAST_STDOUT, LAST_STDERR, and LAST_EXIT for the caller to
# assert against. Stderr is captured (not dropped) so regressions that
# emit unexpected warnings remain visible in local debugging and in CI
# --verbose logs.
run_sentinel() {
    local sentinel_path="$1"
    local stderr_file
    stderr_file=$(mktemp "${TMPROOT}/stderr-XXXXXX")
    LAST_STDOUT=""
    LAST_STDERR=""
    LAST_EXIT=0
    LAST_STDOUT=$(bash "$READ_SCRIPT" --sentinel "$sentinel_path" 2>"$stderr_file") || LAST_EXIT=$?
    LAST_EXIT="${LAST_EXIT:-0}"
    LAST_STDERR=$(cat "$stderr_file")
    rm -f "$stderr_file"
}

# ---------------------------------------------------------------------------
# (a) ADOPTED=true only
echo "(a) ADOPTED=true — exact stdout"
F="$TMPROOT/a.md"
printf 'ADOPTED=true\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(a) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=true')" "(a) stdout"

# (b) ADOPTED=false only
echo "(b) ADOPTED=false — exact stdout"
F="$TMPROOT/b.md"
printf 'ADOPTED=false\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(b) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=false')" "(b) stdout"

# (c) empty file → all three keys absent from source; keys still emitted with empty values
echo "(c) empty file — all values empty (keys still emitted with empty value)"
F="$TMPROOT/c.md"
: > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(c) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=')" "(c) stdout"

# (d) ADOPTED= (explicit empty) → same stdout as (c)
echo "(d) ADOPTED= (explicit empty)"
F="$TMPROOT/d.md"
printf 'ADOPTED=\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(d) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=')" "(d) stdout"

# (e) ADOPTED=yes → invalid, exit 1, exact envelope
echo "(e) ADOPTED=yes — invalid"
F="$TMPROOT/e.md"
printf 'ADOPTED=yes\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "1" "(e) exit 1"
assert_equal_stdout "$LAST_STDOUT" "$(printf "FAILED=true\nERROR=invalid ADOPTED value in sentinel: 'yes' (expected 'true' or 'false' or absent)")" "(e) stdout"

# (f) ADOPTED=TRUE → case-strict rejection
echo "(f) ADOPTED=TRUE — case-strict reject"
F="$TMPROOT/f.md"
printf 'ADOPTED=TRUE\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "1" "(f) exit 1"
assert_contains "$LAST_STDOUT" "'TRUE'" "(f) stdout names the rejected value"

# (g) ADOPTED=1 → numeric rejection
echo "(g) ADOPTED=1 — numeric reject"
F="$TMPROOT/g.md"
printf 'ADOPTED=1\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "1" "(g) exit 1"
assert_contains "$LAST_STDOUT" "'1'" "(g) stdout names the rejected value"

# (h) ADOPTED=true (trailing space, no \r) → rejected
echo "(h) ADOPTED=true␠ — trailing space reject"
F="$TMPROOT/h.md"
printf 'ADOPTED=true \n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "1" "(h) exit 1"
assert_contains "$LAST_STDOUT" "'true '" "(h) stdout names the rejected value"

# (i) sentinel file not found
echo "(i) sentinel file not found"
F="$TMPROOT/does-not-exist.md"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "1" "(i) exit 1"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'FAILED=true\nERROR=sentinel file not found: %s' "$F")" "(i) stdout"

# (j) all three keys valid
echo "(j) all three keys valid"
F="$TMPROOT/j.md"
printf 'ISSUE_NUMBER=123\nANCHOR_COMMENT_ID=456\nADOPTED=true\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(j) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=123\nANCHOR_COMMENT_ID=456\nADOPTED=true')" "(j) stdout"

# (k) duplicate ADOPTED lines — first wins
echo "(k) duplicate ADOPTED — first wins"
F="$TMPROOT/k.md"
printf 'ADOPTED=true\nADOPTED=false\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(k) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=true')" "(k) stdout"

# (l) CRLF line endings — \r stripped from value (all three keys)
printf '(l) CRLF line endings -- \\r stripped (all three keys)\n'
F="$TMPROOT/l.md"
printf 'ISSUE_NUMBER=123\r\nANCHOR_COMMENT_ID=456\r\nADOPTED=true\r\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(l) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=123\nANCHOR_COMMENT_ID=456\nADOPTED=true')" "(l) stdout (all three values \\r-stripped)"

# (m) UTF-8 BOM at start — stripped before parsing
echo "(m) UTF-8 BOM — stripped"
F="$TMPROOT/m.md"
printf '\xef\xbb\xbfISSUE_NUMBER=42\nADOPTED=true\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(m) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=42\nANCHOR_COMMENT_ID=\nADOPTED=true')" "(m) stdout"

# (n) Leading whitespace — column-0 rule; indented line treated as absent
echo "(n) leading whitespace — column-0 rule"
F="$TMPROOT/n.md"
printf '  ADOPTED=true\n' > "$F"
run_sentinel "$F"
assert_equal_exit "$LAST_EXIT" "0" "(n) exit 0"
assert_equal_stdout "$LAST_STDOUT" "$(printf 'ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=')" "(n) stdout"

# (o) Unreadable sentinel file (mode 000) — fail-closed with envelope.
# Skipped when running as root because chmod 000 does not block root reads
# (root bypasses DAC mode bits on most Unix kernels).
echo "(o) unreadable sentinel — fail-closed with envelope"
if (( EUID == 0 )); then
    echo "  skip: (o) root can read mode-000 files; skipping"
else
    F="$TMPROOT/o.md"
    printf 'ADOPTED=true\n' > "$F"
    chmod 000 "$F"
    run_sentinel "$F"
    chmod 600 "$F"  # restore so EXIT trap can delete
    assert_equal_exit "$LAST_EXIT" "1" "(o) exit 1"
    assert_equal_stdout "$LAST_STDOUT" "$(printf 'FAILED=true\nERROR=sentinel file not readable: %s' "$F")" "(o) stdout envelope"
fi

# ---------------------------------------------------------------------------
# Summary
echo
echo "=========================================="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if (( FAIL > 0 )); then
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
echo "All assertions passed."
