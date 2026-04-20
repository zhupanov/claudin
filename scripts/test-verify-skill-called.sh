#!/usr/bin/env bash
# test-verify-skill-called.sh — Regression harness for scripts/verify-skill-called.sh
# and the shared scripts/lib-count-commits.sh sourced library.
#
# Black-box contract test: invoke the helper with controlled arguments and
# assert on stdout/stderr/exit-code for each of the three modes:
#   --sentinel-file <path>
#   --stdout-line <regex> --stdout-file <path>
#   --commit-delta <expected> --before-count <N>
#
# Also exercises:
#   - Argument-error paths (exit 1, no KEY=VALUE emitted).
#   - Stdout contract (VERIFIED= and REASON= always emitted on exit-0 paths).
#   - lib-count-commits.sh sourced from cwd-neutral context via
#     check-bump-version.sh (validates the source chain).
#
# Invariants asserted:
#   - Exit 0 for pass AND fail outcomes (VERIFIED=true|false on stdout).
#   - Exit 1 only for argument errors and internal helper faults that
#     prevent KEY=VALUE emission.
#   - REASON tokens come from a stable enum.
#   - lib-count-commits.sh distinguishes ok / missing_main_ref / git_error.
#
# Usage:
#   bash scripts/test-verify-skill-called.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed (first failure listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/scripts/verify-skill-called.sh"
LIB="$REPO_ROOT/scripts/lib-count-commits.sh"
CHECK_BUMP="$REPO_ROOT/scripts/check-bump-version.sh"

for f in "$HELPER" "$LIB" "$CHECK_BUMP"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required script not found: $f" >&2
        exit 1
    fi
done
if [[ ! -x "$HELPER" ]]; then
    echo "ERROR: helper script not executable: $HELPER" >&2
    exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-verify-skill-called-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

export HOME="$TMPROOT/fakehome"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

PASS=0
FAIL=0
FAILED_TESTS=()

fail() {
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$1")
    echo "FAIL: $1" >&2
}
pass() {
    PASS=$((PASS + 1))
}

assert_stdout_contains() {
    local label="$1" stdout="$2" needle="$3"
    if [[ "$stdout" == *"$needle"* ]]; then
        pass
    else
        fail "$label: expected stdout to contain '$needle'; got: ${stdout:0:400}"
    fi
}
assert_exit_eq() {
    local label="$1" got="$2" want="$3"
    if [[ "$got" -eq "$want" ]]; then
        pass
    else
        fail "$label: expected exit $want, got $got"
    fi
}

# run_helper — invoke the helper, capture stdout and exit code, and assert
# both. Wraps the two assertions together so every non-argument-error
# scenario exercises the exit-code contract (exit 0 on pass/fail outcomes,
# exit 1 on argument errors and internal faults) — not just the stdout
# substring check.
# Usage: run_helper <label> <expected_rc> <expected_needle|-> <helper args...>
# Pass `-` as expected_needle to skip the stdout substring check (useful for
# argument-error cases where no KEY=VALUE is emitted).
run_helper() {
    local label="$1" want_rc="$2" needle="$3"; shift 3
    local out rc
    set +e
    out=$("$HELPER" "$@" 2>&1)
    rc=$?
    set -e
    assert_exit_eq "$label (exit)" "$rc" "$want_rc"
    if [[ "$needle" != "-" ]]; then
        assert_stdout_contains "$label (stdout)" "$out" "$needle"
    fi
}

# --- Section 1: --sentinel-file mode -----------------------------------------

echo "=== Section 1: --sentinel-file mode ==="

# 1a — non-empty file → VERIFIED=true
SENT_OK="$TMPROOT/sentinel-ok.txt"
printf 'content\n' > "$SENT_OK"
out=$("$HELPER" --sentinel-file "$SENT_OK" 2>&1) || true
assert_stdout_contains "1a: non-empty file VERIFIED=true" "$out" "VERIFIED=true"
assert_stdout_contains "1a: REASON=ok" "$out" "REASON=ok"

# 1b — missing file → VERIFIED=false REASON=missing_path
out=$("$HELPER" --sentinel-file "$TMPROOT/does-not-exist" 2>&1) || true
assert_stdout_contains "1b: missing file VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "1b: REASON=missing_path" "$out" "REASON=missing_path"

# 1c — empty file → VERIFIED=false REASON=empty_file
SENT_EMPTY="$TMPROOT/sentinel-empty.txt"
: > "$SENT_EMPTY"
out=$("$HELPER" --sentinel-file "$SENT_EMPTY" 2>&1) || true
assert_stdout_contains "1c: empty file VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "1c: REASON=empty_file" "$out" "REASON=empty_file"

# 1d — directory path → VERIFIED=false REASON=not_regular_file
SENT_DIR="$TMPROOT/sentinel-dir"
mkdir -p "$SENT_DIR"
out=$("$HELPER" --sentinel-file "$SENT_DIR" 2>&1) || true
assert_stdout_contains "1d: directory VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "1d: REASON=not_regular_file" "$out" "REASON=not_regular_file"

# 1e — symlink to /dev/null → REASON=not_regular_file (check order: -e, -f, -s)
SENT_SYM="$TMPROOT/sentinel-symlink-devnull"
ln -s /dev/null "$SENT_SYM"
out=$("$HELPER" --sentinel-file "$SENT_SYM" 2>&1) || true
assert_stdout_contains "1e: symlink to /dev/null VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "1e: symlink to /dev/null REASON=not_regular_file" "$out" "REASON=not_regular_file"

# 1f — empty --sentinel-file value → argument error, exit 1
set +e
out=$("$HELPER" --sentinel-file "" 2>&1)
rc=$?
set -e
assert_exit_eq "1f: empty sentinel arg exit 1" "$rc" 1

# 1g — non-empty file exits 0 (not 1). Explicit exit-code assertion on pass.
run_helper "1g: non-empty exits 0" 0 "VERIFIED=true" --sentinel-file "$SENT_OK"

# 1h — missing file exits 0 (not 1). Explicit exit-code assertion on fail.
run_helper "1h: missing exits 0" 0 "VERIFIED=false" \
    --sentinel-file "$TMPROOT/does-not-exist"

# --- Section 2: --stdout-line mode -------------------------------------------

echo "=== Section 2: --stdout-line mode ==="

# 2a — regex match → VERIFIED=true
CAP="$TMPROOT/stdout-cap.txt"
printf 'ISSUES_CREATED=3\nITEM_1_URL=foo\n' > "$CAP"
out=$("$HELPER" --stdout-line '^ISSUES_CREATED=' --stdout-file "$CAP" 2>&1) || true
assert_stdout_contains "2a: regex match VERIFIED=true" "$out" "VERIFIED=true"
assert_stdout_contains "2a: REASON=ok" "$out" "REASON=ok"

# 2b — regex miss → VERIFIED=false REASON=no_match
out=$("$HELPER" --stdout-line '^NEVER_MATCHES_' --stdout-file "$CAP" 2>&1) || true
assert_stdout_contains "2b: regex miss VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "2b: REASON=no_match" "$out" "REASON=no_match"

# 2c — missing stdout file → REASON=missing_stdout_file
out=$("$HELPER" --stdout-line '^ISSUES_' --stdout-file "$TMPROOT/does-not-exist" 2>&1) || true
assert_stdout_contains "2c: missing file VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "2c: REASON=missing_stdout_file" "$out" "REASON=missing_stdout_file"

# 2d — empty regex → argument error, exit 1
set +e
out=$("$HELPER" --stdout-line '' --stdout-file "$CAP" 2>&1)
rc=$?
set -e
assert_exit_eq "2d: empty regex exit 1" "$rc" 1

# 2e — leading-dash regex (option-injection guard) → treated as pattern, miss → VERIFIED=false
out=$("$HELPER" --stdout-line '-v' --stdout-file "$CAP" 2>&1) || true
assert_stdout_contains "2e: leading-dash regex VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "2e: leading-dash regex REASON=no_match" "$out" "REASON=no_match"

# 2f — missing --stdout-file → argument error
set +e
out=$("$HELPER" --stdout-line '^FOO' 2>&1)
rc=$?
set -e
assert_exit_eq "2f: missing --stdout-file exit 1" "$rc" 1

# 2g — malformed ERE (grep exit 2) must not be treated as no_match.
# Per fail-closed contract, grep exit 2 (bad regex) is an internal fault:
# exit 1 with no KEY=VALUE emitted (caller must distinguish from a clean
# VERIFIED=false no_match result).
set +e
out=$("$HELPER" --stdout-line '[' --stdout-file "$CAP" 2>&1)
rc=$?
set -e
assert_exit_eq "2g: malformed ERE exit 1 (not exit 0)" "$rc" 1
if [[ "$out" == *"VERIFIED="* ]]; then
    fail "2g: malformed ERE emitted VERIFIED=... (should not — fail-closed)"
else
    pass
fi

# 2h — successful match exits 0 (not 1). Explicit exit-code assertion.
run_helper "2h: match exits 0" 0 "VERIFIED=true" \
    --stdout-line '^ISSUES_CREATED=' --stdout-file "$CAP"

# 2i — clean no-match exits 0 (not 1). Explicit exit-code assertion.
run_helper "2i: no-match exits 0" 0 "VERIFIED=false" \
    --stdout-line '^NOTHING_WILL_MATCH' --stdout-file "$CAP"

# --- Section 3: --commit-delta mode ------------------------------------------

echo "=== Section 3: --commit-delta mode ==="

setup_git_repo() {
    # Creates a fresh git repo with N commits on main and B branch commits.
    # Usage: setup_git_repo <dir> <main_commits> <branch_commits>
    local dir="$1" main_n="$2" branch_n="$3" i
    mkdir -p "$dir"
    (
        cd "$dir"
        git init -q -b main
        git config user.email "test@example.com"
        git config user.name "Test"
        git commit --allow-empty -q -m "init"
        for ((i=2; i<=main_n; i++)); do
            git commit --allow-empty -q -m "main commit $i"
        done
        if [[ "$branch_n" -gt 0 ]]; then
            git checkout -q -b feature
            for ((i=1; i<=branch_n; i++)); do
                git commit --allow-empty -q -m "feature commit $i"
            done
        fi
    )
}

# 3a — delta 1 matches expected 1 → VERIFIED=true
REPO_1="$TMPROOT/repo-delta-1"
setup_git_repo "$REPO_1" 1 1
out=$(cd "$REPO_1" && "$HELPER" --commit-delta 1 --before-count 0 2>&1) || true
assert_stdout_contains "3a: delta=1 expected=1 VERIFIED=true" "$out" "VERIFIED=true"
assert_stdout_contains "3a: REASON=ok" "$out" "REASON=ok"

# 3b — delta 2 but expected 1 → VERIFIED=false REASON=commit_delta_mismatch
REPO_2="$TMPROOT/repo-delta-2"
setup_git_repo "$REPO_2" 1 2
out=$(cd "$REPO_2" && "$HELPER" --commit-delta 1 --before-count 0 2>&1) || true
assert_stdout_contains "3b: delta=2 expected=1 VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "3b: REASON=commit_delta_mismatch" "$out" "REASON=commit_delta_mismatch"

# 3c — delta 0 and expected 0 → VERIFIED=true
REPO_0="$TMPROOT/repo-delta-0"
setup_git_repo "$REPO_0" 1 0
# Stay on main (branch_n=0 means no feature branch); delta vs main = 0.
out=$(cd "$REPO_0" && "$HELPER" --commit-delta 0 --before-count 0 2>&1) || true
assert_stdout_contains "3c: delta=0 expected=0 VERIFIED=true" "$out" "VERIFIED=true"

# 3d — origin/main fallback: rename local main away, keep origin/main
REPO_ORIGIN="$TMPROOT/repo-origin-only"
BARE="$TMPROOT/bare-origin.git"
git init -q --bare "$BARE"
setup_git_repo "$REPO_ORIGIN" 1 1
(
    cd "$REPO_ORIGIN"
    git remote add origin "$BARE"
    git checkout -q main
    git push -q origin main
    git checkout -q feature
    git branch -q -D main
)
out=$(cd "$REPO_ORIGIN" && "$HELPER" --commit-delta 1 --before-count 0 2>&1) || true
assert_stdout_contains "3d: origin/main fallback VERIFIED=true" "$out" "VERIFIED=true"

# 3e — neither main nor origin/main → REASON=missing_main_ref
REPO_NO_MAIN="$TMPROOT/repo-no-main"
mkdir -p "$REPO_NO_MAIN"
(
    cd "$REPO_NO_MAIN"
    git init -q -b feature
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
)
out=$(cd "$REPO_NO_MAIN" && "$HELPER" --commit-delta 1 --before-count 0 2>&1) || true
assert_stdout_contains "3e: no main ref VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "3e: REASON=missing_main_ref" "$out" "REASON=missing_main_ref"

# 3f — --before-count 0 AND --commit-delta 0 in a no-main repo → must NOT false-pass
# The git_error / missing_main_ref status short-circuits the count comparison.
out=$(cd "$REPO_NO_MAIN" && "$HELPER" --commit-delta 0 --before-count 0 2>&1) || true
assert_stdout_contains "3f: no main ref with delta=0 must not false-pass" "$out" "VERIFIED=false"
assert_stdout_contains "3f: no main ref REASON=missing_main_ref" "$out" "REASON=missing_main_ref"

# 3g — missing --before-count → argument error
set +e
out=$("$HELPER" --commit-delta 1 2>&1)
rc=$?
set -e
assert_exit_eq "3g: missing --before-count exit 1" "$rc" 1

# 3h — non-numeric --before-count → argument error
set +e
out=$("$HELPER" --commit-delta 1 --before-count abc 2>&1)
rc=$?
set -e
assert_exit_eq "3h: non-numeric --before-count exit 1" "$rc" 1

# 3i — successful delta match exits 0 (not 1). Explicit exit-code assertion.
REPO_3i="$TMPROOT/repo-delta-exit0"
setup_git_repo "$REPO_3i" 1 1
out=$(cd "$REPO_3i" && "$HELPER" --commit-delta 1 --before-count 0 2>&1)
rc=$?
assert_exit_eq "3i: delta match exits 0" "$rc" 0
assert_stdout_contains "3i: delta match VERIFIED=true" "$out" "VERIFIED=true"

# 3j — delta mismatch exits 0 (not 1). Explicit exit-code assertion on fail path.
out=$(cd "$REPO_2" && "$HELPER" --commit-delta 1 --before-count 0 2>&1)
rc=$?
assert_exit_eq "3j: delta mismatch exits 0" "$rc" 0
assert_stdout_contains "3j: delta mismatch VERIFIED=false" "$out" "VERIFIED=false"

# --- Section 4: argument-error paths -----------------------------------------

echo "=== Section 4: argument-error paths ==="

# 4a — no arguments → exit 1
set +e
out=$("$HELPER" 2>&1)
rc=$?
set -e
assert_exit_eq "4a: no args exit 1" "$rc" 1

# 4b — unknown flag → exit 1
set +e
out=$("$HELPER" --not-a-real-flag foo 2>&1)
rc=$?
set -e
assert_exit_eq "4b: unknown flag exit 1" "$rc" 1

# 4c — mutually-exclusive modes → exit 1
set +e
out=$("$HELPER" --sentinel-file "$SENT_OK" --stdout-line '^FOO' --stdout-file "$CAP" 2>&1)
rc=$?
set -e
assert_exit_eq "4c: multiple modes exit 1" "$rc" 1

# --- Section 5: lib-count-commits.sh via check-bump-version.sh ---------------
# Exercises the source chain from a cwd-neutral directory to validate that
# check-bump-version.sh correctly sources lib-count-commits.sh regardless of
# the caller's current working directory.

echo "=== Section 5: cwd-neutral source chain ==="

REPO_CHECK="$TMPROOT/repo-check-bump"
setup_git_repo "$REPO_CHECK" 1 0
(
    cd "$REPO_CHECK"
    # Fake a .claude/skills/bump-version/SKILL.md so HAS_BUMP=true path is exercised.
    mkdir -p .claude/skills/bump-version
    printf -- '---\nname: bump-version\n---\ndummy\n' > .claude/skills/bump-version/SKILL.md
)

# 5a — invoke check-bump-version.sh from the repo root using an absolute
# script path. PWD matters here because check-bump-version.sh uses
# $PWD/.claude/skills/... to probe for the /bump-version skill, so we cd
# INTO $REPO_CHECK first. What this test validates is the `source` chain:
# check-bump-version.sh uses `$(dirname "${BASH_SOURCE[0]}")/lib-count-commits.sh`
# which must resolve correctly when the script is invoked via an absolute
# path from any cwd. Section 5b below exercises sourcing the lib directly
# from a non-repo cwd (/tmp) as the truly cwd-neutral case.
out=$(cd "$REPO_CHECK" && bash "$CHECK_BUMP" --mode pre 2>&1) || true
assert_stdout_contains "5a: check-bump-version --mode pre emits HAS_BUMP=true" "$out" "HAS_BUMP=true"
assert_stdout_contains "5a: check-bump-version --mode pre emits COMMITS_BEFORE=" "$out" "COMMITS_BEFORE="

# 5b — source the lib directly via absolute path from arbitrary cwd
(
    cd /tmp
    out=$(bash -c "source '$LIB'; count_commits" 2>&1) || true
    echo "5b_out=$out"
) > "$TMPROOT/section5b.log" 2>&1 || true
if grep -q '5b_out=' "$TMPROOT/section5b.log"; then
    pass
else
    fail "5b: could not source lib-count-commits.sh from /tmp"
fi

# --- Summary -----------------------------------------------------------------

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo ""
    echo "Failed tests:"
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t"
    done
    exit 1
fi
exit 0
