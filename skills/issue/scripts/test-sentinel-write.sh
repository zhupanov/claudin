#!/usr/bin/env bash
# test-sentinel-write.sh — Regression tests for write-sentinel.sh.
#
# Covers the seven cases from issue #509's Step 2b plan revised after Step 3
# review:
#   (a) all-success           → sentinel written with all 5 keys
#   (b) all-dedup             → sentinel written (FINDING_1: proves execution)
#   (c) partial-failure       → no write; stderr WROTE=false REASON=failures
#   (d) dry-run               → no write; stderr WROTE=false REASON=dry_run
#   (e) --path honored        → sentinel at the explicit path
#   (f) channel discipline    → status to stderr only; stdout is empty
#   (g) atomicity (structural)→ script uses same-dir mktemp + mv
#
# Plus argument-validation cases:
#   (h) missing --path                → ERROR=, exit 1
#   (i) non-absolute --path           → ERROR=, exit 1
#   (j) `..` in path                  → ERROR=, exit 1
#   (k) non-numeric counter           → ERROR=, exit 1
#
# Wired into `make lint` via the `test-sentinel-write` target. Run manually:
#
#   bash skills/issue/scripts/test-sentinel-write.sh
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="$SCRIPT_DIR/write-sentinel.sh"

if [[ ! -x "$HELPER" ]]; then
    echo "ERROR: helper not executable: $HELPER" >&2
    exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() {
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS: $1"
}

fail() {
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL: $1" >&2
    [[ -n "${2:-}" ]] && echo "    detail: $2" >&2
    exit 1
}

assert_file_exists() {
    [[ -f "$1" ]] || fail "$2" "expected file at $1 to exist"
    pass "$2"
}

assert_file_absent() {
    [[ ! -e "$1" ]] || fail "$2" "expected no file at $1 (found one)"
    pass "$2"
}

assert_grep() {
    local file="$1" pattern="$2" label="$3"
    grep -q "$pattern" "$file" || fail "$label" "pattern '$pattern' not in $file"
    pass "$label"
}

assert_string_eq() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label" "expected '$expected', got '$actual'"
    fi
}

# ---------------------------------------------------------------------------
echo
echo "Case (a): all-success → sentinel written with all 5 keys"
SENT_A="$TMPDIR_TEST/a/sentinel"
STDOUT_A=$("$HELPER" --path "$SENT_A" --issues-created 3 --issues-deduplicated 1 --issues-failed 0 2>"$TMPDIR_TEST/a-stderr")
assert_file_exists "$SENT_A" "  (a) sentinel file exists at explicit path"
assert_grep "$SENT_A" '^ISSUE_SENTINEL_VERSION=1$' "  (a) ISSUE_SENTINEL_VERSION=1 present"
assert_grep "$SENT_A" '^ISSUES_CREATED=3$' "  (a) ISSUES_CREATED=3 present"
assert_grep "$SENT_A" '^ISSUES_DEDUPLICATED=1$' "  (a) ISSUES_DEDUPLICATED=1 present"
assert_grep "$SENT_A" '^ISSUES_FAILED=0$' "  (a) ISSUES_FAILED=0 present"
assert_grep "$SENT_A" '^TIMESTAMP=' "  (a) TIMESTAMP= line present"
assert_grep "$TMPDIR_TEST/a-stderr" '^WROTE=true$' "  (a) stderr WROTE=true"
assert_string_eq "$STDOUT_A" "" "  (a) stdout empty"

# ---------------------------------------------------------------------------
echo
echo "Case (b): all-dedup (CREATED=0, FAILED=0, DEDUPLICATED>=1) → sentinel WRITTEN"
SENT_B="$TMPDIR_TEST/b/sentinel"
STDOUT_B=$("$HELPER" --path "$SENT_B" --issues-created 0 --issues-deduplicated 5 --issues-failed 0 2>"$TMPDIR_TEST/b-stderr")
assert_file_exists "$SENT_B" "  (b) sentinel file written despite ISSUES_CREATED=0 (FINDING_1 fix)"
assert_grep "$SENT_B" '^ISSUES_CREATED=0$' "  (b) ISSUES_CREATED=0 recorded"
assert_grep "$SENT_B" '^ISSUES_DEDUPLICATED=5$' "  (b) ISSUES_DEDUPLICATED=5 recorded"
assert_grep "$TMPDIR_TEST/b-stderr" '^WROTE=true$' "  (b) stderr WROTE=true"
assert_string_eq "$STDOUT_B" "" "  (b) stdout empty"

# ---------------------------------------------------------------------------
echo
echo "Case (c): partial-failure (FAILED>=1) → no write"
SENT_C="$TMPDIR_TEST/c/sentinel"
STDOUT_C=$("$HELPER" --path "$SENT_C" --issues-created 2 --issues-deduplicated 0 --issues-failed 1 2>"$TMPDIR_TEST/c-stderr")
assert_file_absent "$SENT_C" "  (c) no sentinel written"
assert_grep "$TMPDIR_TEST/c-stderr" '^WROTE=false REASON=failures$' "  (c) stderr WROTE=false REASON=failures"
assert_string_eq "$STDOUT_C" "" "  (c) stdout empty"

# ---------------------------------------------------------------------------
echo
echo "Case (d): dry-run → no write (even with ISSUES_CREATED>=1)"
SENT_D="$TMPDIR_TEST/d/sentinel"
STDOUT_D=$("$HELPER" --path "$SENT_D" --issues-created 2 --issues-deduplicated 0 --issues-failed 0 --dry-run 2>"$TMPDIR_TEST/d-stderr")
assert_file_absent "$SENT_D" "  (d) no sentinel written on dry-run"
assert_grep "$TMPDIR_TEST/d-stderr" '^WROTE=false REASON=dry_run$' "  (d) stderr WROTE=false REASON=dry_run"
assert_string_eq "$STDOUT_D" "" "  (d) stdout empty"

# ---------------------------------------------------------------------------
echo
echo "Case (e): --path honored at explicit location"
SENT_E="$TMPDIR_TEST/e/deep/nested/sentinel.txt"
"$HELPER" --path "$SENT_E" --issues-created 1 --issues-deduplicated 0 --issues-failed 0 2>/dev/null
assert_file_exists "$SENT_E" "  (e) sentinel at deep nested explicit path"

# ---------------------------------------------------------------------------
echo
echo "Case (f): channel discipline — status to stderr, stdout empty"
SENT_F="$TMPDIR_TEST/f/sentinel"
STDOUT_F=$("$HELPER" --path "$SENT_F" --issues-created 1 --issues-deduplicated 0 --issues-failed 0 2>/dev/null)
assert_string_eq "$STDOUT_F" "" "  (f) stdout is strictly empty (no WROTE= leakage)"

# ---------------------------------------------------------------------------
echo
echo "Case (g): atomicity — script uses same-dir mktemp + mv (structural)"
# Assert the script source contains the load-bearing structural pattern.
# The atomicity invariant is a structural property of the mv-based promote
# (FINDING_7 exoneration: structural assertion is sufficient; race-stress in
# pure Bash is unreliable).
assert_grep "$HELPER" 'mktemp ' "  (g) script invokes mktemp"
# Single-quoted intentionally — pinning literal `${PATH_ARG}` and `$TMPFILE`/`$PATH_ARG`
# tokens in the script source via grep -E. Shell expansion would defeat the assertion.
# shellcheck disable=SC2016
assert_grep "$HELPER" '\${PATH_ARG}\.tmp\.XXXXXX' "  (g) mktemp uses same-directory template"
# shellcheck disable=SC2016
assert_grep "$HELPER" '^mv "\$TMPFILE" "\$PATH_ARG"$' "  (g) script promotes via mv from temp"

# ---------------------------------------------------------------------------
echo
echo "Case (h): missing --path → ERROR, exit 1"
set +e
STDOUT_H=$("$HELPER" --issues-created 1 --issues-deduplicated 0 --issues-failed 0 2>"$TMPDIR_TEST/h-stderr")
EXIT_H=$?
set -e
if [[ "$EXIT_H" == "1" ]]; then pass "  (h) exit code 1"; else fail "  (h) exit code 1" "got $EXIT_H"; fi
assert_grep "$TMPDIR_TEST/h-stderr" '^ERROR=' "  (h) stderr ERROR= emitted"
assert_string_eq "$STDOUT_H" "" "  (h) stdout empty"

# ---------------------------------------------------------------------------
echo
echo "Case (i): non-absolute --path → ERROR, exit 1"
set +e
"$HELPER" --path "relative/path" --issues-created 1 --issues-deduplicated 0 --issues-failed 0 2>"$TMPDIR_TEST/i-stderr"
EXIT_I=$?
set -e
if [[ "$EXIT_I" == "1" ]]; then pass "  (i) exit code 1"; else fail "  (i) exit code 1" "got $EXIT_I"; fi
assert_grep "$TMPDIR_TEST/i-stderr" '^ERROR=.*absolute' "  (i) stderr ERROR= mentions absolute"

# ---------------------------------------------------------------------------
echo
echo "Case (j): '..' in --path → ERROR, exit 1"
set +e
"$HELPER" --path "/tmp/foo/../bar" --issues-created 1 --issues-deduplicated 0 --issues-failed 0 2>"$TMPDIR_TEST/j-stderr"
EXIT_J=$?
set -e
if [[ "$EXIT_J" == "1" ]]; then pass "  (j) exit code 1"; else fail "  (j) exit code 1" "got $EXIT_J"; fi
assert_grep "$TMPDIR_TEST/j-stderr" "ERROR=.*'\\.\\.'" "  (j) stderr ERROR= mentions '..'"

# ---------------------------------------------------------------------------
echo
echo "Case (k): non-numeric counter → ERROR, exit 1"
set +e
"$HELPER" --path "/tmp/k-sentinel" --issues-created abc --issues-deduplicated 0 --issues-failed 0 2>"$TMPDIR_TEST/k-stderr"
EXIT_K=$?
set -e
if [[ "$EXIT_K" == "1" ]]; then pass "  (k) exit code 1"; else fail "  (k) exit code 1" "got $EXIT_K"; fi
assert_grep "$TMPDIR_TEST/k-stderr" '^ERROR=.*non-negative integers' "  (k) stderr ERROR= mentions integers"

# ---------------------------------------------------------------------------
echo
echo "All write-sentinel.sh regression cases passed: $PASS_COUNT pass, $FAIL_COUNT fail"
[[ "$FAIL_COUNT" -eq 0 ]] || exit 1
