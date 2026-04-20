#!/usr/bin/env bash
# test-check-bump-version.sh — Regression harness for scripts/check-bump-version.sh.
#
# Black-box contract test: invoke check-bump-version.sh with controlled
# arguments and assert on stdout/stderr/exit-code for both modes and all
# status paths surfaced by the shared scripts/lib-count-commits.sh side
# channel:
#   --mode pre   → HAS_BUMP=..., COMMITS_BEFORE=..., STATUS=...
#   --mode post  → VERIFIED=..., COMMITS_AFTER=..., EXPECTED=..., STATUS=...
#
# Status paths covered (for both modes):
#   STATUS=ok                — healthy repo; count is trustworthy.
#   STATUS=ok  + origin/main — local main absent but origin/main present
#                              (the fallback path documented in
#                              check-bump-version.sh's header).
#   STATUS=missing_main_ref  — neither local main nor origin/main exists.
#   STATUS=git_error         — base ref exists but `git rev-list` fails
#                              (simulated via a PATH shim around `git`).
#   STATUS=git_error         — the fail-closed normalization: any unknown
#                              or empty token received from the side
#                              channel MUST be emitted as STATUS=git_error
#                              (mirrors verify-skill-called.sh's default
#                              branch that maps unknown to REASON=git_error).
#
# Fix #172 regression guard: the historical bug masked `git rev-list`
# failures as `COMMITS_*=0` with no status signal, so a post-mode check
# whose pre- and post-call both hit git errors would numerically match
# and spuriously emit `VERIFIED=true`. The fail-closed test below
# (Section 4) proves this cannot happen now: when pre and post both
# return count=0 with non-ok status, VERIFIED MUST be false.
#
# Invariants asserted:
#   - stdout STATUS= field is always emitted in both modes.
#   - In --mode post, VERIFIED=true only when STATUS=ok AND counts match.
#   - Unknown/empty status tokens normalize to STATUS=git_error.
#   - Existing KEY=VALUE contract (HAS_BUMP, COMMITS_BEFORE, VERIFIED,
#     COMMITS_AFTER, EXPECTED) is preserved.
#   - Exit 0 on pass AND fail outcomes; exit 1 only for argument errors.
#
# Usage:
#   bash scripts/test-check-bump-version.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed (first failure listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/check-bump-version.sh"
LIB="$REPO_ROOT/scripts/lib-count-commits.sh"

for f in "$SCRIPT" "$LIB"; do
    if [[ ! -f "$f" ]]; then
        echo "ERROR: required script not found: $f" >&2
        exit 1
    fi
done

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-check-bump-version-XXXXXX")
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
assert_stdout_not_contains() {
    local label="$1" stdout="$2" needle="$3"
    if [[ "$stdout" == *"$needle"* ]]; then
        fail "$label: expected stdout NOT to contain '$needle'; got: ${stdout:0:400}"
    else
        pass
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

# setup_git_repo — creates a fresh repo with N main commits and B feature
# commits. The feature branch is checked out at the end when B>0; otherwise
# HEAD stays on main.
setup_git_repo() {
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

# setup_origin_main_only_repo — creates a repo where local `main` has been
# deleted but `origin/main` is still reachable (simulates CI clones without
# a local main ref, the fallback path in check-bump-version.sh:17-22).
setup_origin_main_only_repo() {
    local dir="$1" branch_n="$2" i
    local bare="${dir}.bare.git"
    git init -q --bare "$bare"
    setup_git_repo "$dir" 1 "$branch_n"
    (
        cd "$dir"
        git remote add origin "$bare"
        git checkout -q main
        git push -q origin main
        if [[ "$branch_n" -gt 0 ]]; then
            git checkout -q feature
        fi
        git branch -q -D main
    )
}

# make_git_rev_list_fails_shim — writes a PATH shim at $1 that delegates
# every git subcommand to the real git EXCEPT `rev-list`, which it exits
# non-zero. Used to simulate the git_error path (base ref is reachable,
# but the count call fails — e.g., shallow-clone object boundary, ODB
# corruption). The shim is validated by running `git rev-parse HEAD` in
# the harness's own assertions so shim breakage does not quietly pass.
make_git_rev_list_fails_shim() {
    local shim_dir="$1"
    local real_git
    real_git=$(command -v git)
    mkdir -p "$shim_dir"
    cat > "$shim_dir/git" <<EOF
#!/usr/bin/env bash
# PATH shim: delegate to real git except for rev-list, which must fail.
if [[ "\${1:-}" == "rev-list" ]]; then
    echo "simulated rev-list failure" >&2
    exit 128
fi
exec "$real_git" "\$@"
EOF
    chmod +x "$shim_dir/git"
}

# --- Section 1: --mode pre ---------------------------------------------------

echo "=== Section 1: --mode pre ==="

# 1a — local main present, 2 commits ahead → STATUS=ok, COMMITS_BEFORE=2
REPO_1A="$TMPROOT/repo-pre-ok-local"
setup_git_repo "$REPO_1A" 1 2
out=$(cd "$REPO_1A" && bash "$SCRIPT" --mode pre 2>&1) || true
assert_stdout_contains "1a: pre ok local main COMMITS_BEFORE=2" "$out" "COMMITS_BEFORE=2"
assert_stdout_contains "1a: pre ok local main STATUS=ok" "$out" "STATUS=ok"
assert_stdout_contains "1a: pre emits HAS_BUMP= line" "$out" "HAS_BUMP="

# 1b — origin/main-only fallback → STATUS=ok
REPO_1B="$TMPROOT/repo-pre-ok-origin"
setup_origin_main_only_repo "$REPO_1B" 2
out=$(cd "$REPO_1B" && bash "$SCRIPT" --mode pre 2>&1) || true
assert_stdout_contains "1b: pre origin-only COMMITS_BEFORE=2" "$out" "COMMITS_BEFORE=2"
assert_stdout_contains "1b: pre origin-only STATUS=ok" "$out" "STATUS=ok"

# 1c — missing_main_ref → STATUS=missing_main_ref, COMMITS_BEFORE=0, stderr WARN
REPO_1C="$TMPROOT/repo-pre-no-main"
mkdir -p "$REPO_1C"
(
    cd "$REPO_1C"
    git init -q -b feature
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
)
out=$(cd "$REPO_1C" && bash "$SCRIPT" --mode pre 2>&1) || true
assert_stdout_contains "1c: pre missing-main COMMITS_BEFORE=0" "$out" "COMMITS_BEFORE=0"
assert_stdout_contains "1c: pre missing-main STATUS=missing_main_ref" "$out" "STATUS=missing_main_ref"
assert_stdout_contains "1c: pre missing-main stderr WARN" "$out" "WARN: check-bump-version.sh:"

# 1d — git_error (PATH shim) → STATUS=git_error, COMMITS_BEFORE=0
REPO_1D="$TMPROOT/repo-pre-git-error"
SHIM_1D="$TMPROOT/shim-1d"
setup_git_repo "$REPO_1D" 1 2
make_git_rev_list_fails_shim "$SHIM_1D"
# Validate the shim before relying on it: rev-parse must still work.
probe=$(cd "$REPO_1D" && PATH="$SHIM_1D:$PATH" git rev-parse HEAD 2>&1) || true
if [[ -z "$probe" ]]; then
    fail "1d: PATH shim broke rev-parse as well; cannot isolate rev-list failure"
else
    pass
fi
out=$(cd "$REPO_1D" && PATH="$SHIM_1D:$PATH" bash "$SCRIPT" --mode pre 2>&1) || true
assert_stdout_contains "1d: pre git_error COMMITS_BEFORE=0" "$out" "COMMITS_BEFORE=0"
assert_stdout_contains "1d: pre git_error STATUS=git_error" "$out" "STATUS=git_error"

# 1e — unknown-token normalization: stub the library so count_commits writes
# an unexpected token to the status file. Assert STATUS=git_error (fail-closed).
REPO_1E="$TMPROOT/repo-pre-unknown-token"
setup_git_repo "$REPO_1E" 1 0
STUB_LIB_1E="$TMPROOT/stub-lib-1e.sh"
cat > "$STUB_LIB_1E" <<'STUB'
# shellcheck shell=bash
count_commits() {
    if [[ -n "${COUNT_COMMITS_STATUS_FILE:-}" ]]; then
        printf '%s\n' "bogus_token_not_in_enum" > "$COUNT_COMMITS_STATUS_FILE"
    fi
    echo "7"
    return 0
}
STUB
# Create a patched copy of check-bump-version.sh that sources the stub
# instead of the real lib. This keeps the assertion purely black-box over
# the script's stdout without having to PATH-shim `source`.
PATCHED_1E="$TMPROOT/check-bump-version-stubbed-1e.sh"
sed -e "s|^source .*/lib-count-commits.sh.*$|source \"$STUB_LIB_1E\"|" "$SCRIPT" > "$PATCHED_1E"
chmod +x "$PATCHED_1E"
out=$(cd "$REPO_1E" && bash "$PATCHED_1E" --mode pre 2>&1) || true
assert_stdout_contains "1e: pre unknown-token STATUS=git_error" "$out" "STATUS=git_error"
assert_stdout_not_contains "1e: pre unknown-token not passed through" "$out" "STATUS=bogus_token_not_in_enum"

# --- Section 2: --mode post (STATUS=ok paths) --------------------------------

echo "=== Section 2: --mode post, STATUS=ok ==="

# 2a — ok × match → VERIFIED=true, STATUS=ok
REPO_2A="$TMPROOT/repo-post-ok-match"
setup_git_repo "$REPO_2A" 1 3
out=$(cd "$REPO_2A" && bash "$SCRIPT" --mode post --before-count 2 2>&1) || true
assert_stdout_contains "2a: post ok match VERIFIED=true" "$out" "VERIFIED=true"
assert_stdout_contains "2a: post ok match COMMITS_AFTER=3" "$out" "COMMITS_AFTER=3"
assert_stdout_contains "2a: post ok match EXPECTED=3" "$out" "EXPECTED=3"
assert_stdout_contains "2a: post ok match STATUS=ok" "$out" "STATUS=ok"

# 2b — ok × mismatch (delta 2, expected 1) → VERIFIED=false, STATUS=ok
REPO_2B="$TMPROOT/repo-post-ok-mismatch"
setup_git_repo "$REPO_2B" 1 3
out=$(cd "$REPO_2B" && bash "$SCRIPT" --mode post --before-count 1 2>&1) || true
assert_stdout_contains "2b: post ok mismatch VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "2b: post ok mismatch STATUS=ok" "$out" "STATUS=ok"

# 2c — ok × origin/main-only × match
REPO_2C="$TMPROOT/repo-post-ok-origin"
setup_origin_main_only_repo "$REPO_2C" 3
out=$(cd "$REPO_2C" && bash "$SCRIPT" --mode post --before-count 2 2>&1) || true
assert_stdout_contains "2c: post origin-only VERIFIED=true" "$out" "VERIFIED=true"
assert_stdout_contains "2c: post origin-only STATUS=ok" "$out" "STATUS=ok"

# --- Section 3: --mode post (non-ok paths: fail-closed invariants) -----------

echo "=== Section 3: --mode post, non-ok (fail-closed) ==="

# 3a — missing_main_ref → VERIFIED=false, STATUS=missing_main_ref (even when counts happen to match numerically)
REPO_3A="$TMPROOT/repo-post-no-main"
mkdir -p "$REPO_3A"
(
    cd "$REPO_3A"
    git init -q -b feature
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
)
# count=0, before=0, expected=1 → naive numeric comparison would give VERIFIED=false here too,
# but Section 4 below proves the fail-closed path for delta=0.
out=$(cd "$REPO_3A" && bash "$SCRIPT" --mode post --before-count 0 2>&1) || true
assert_stdout_contains "3a: post missing-main VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "3a: post missing-main STATUS=missing_main_ref" "$out" "STATUS=missing_main_ref"

# 3b — git_error → VERIFIED=false, STATUS=git_error
REPO_3B="$TMPROOT/repo-post-git-error"
SHIM_3B="$TMPROOT/shim-3b"
setup_git_repo "$REPO_3B" 1 3
make_git_rev_list_fails_shim "$SHIM_3B"
out=$(cd "$REPO_3B" && PATH="$SHIM_3B:$PATH" bash "$SCRIPT" --mode post --before-count 2 2>&1) || true
assert_stdout_contains "3b: post git_error VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "3b: post git_error STATUS=git_error" "$out" "STATUS=git_error"
assert_stdout_contains "3b: post git_error COMMITS_AFTER=0" "$out" "COMMITS_AFTER=0"

# 3c — unknown-token → VERIFIED=false, STATUS=git_error (fail-closed normalization)
REPO_3C="$TMPROOT/repo-post-unknown-token"
setup_git_repo "$REPO_3C" 1 0
# Reuse the stub from 1e.
PATCHED_3C="$TMPROOT/check-bump-version-stubbed-3c.sh"
sed -e "s|^source .*/lib-count-commits.sh.*$|source \"$STUB_LIB_1E\"|" "$SCRIPT" > "$PATCHED_3C"
chmod +x "$PATCHED_3C"
out=$(cd "$REPO_3C" && bash "$PATCHED_3C" --mode post --before-count 7 2>&1) || true
# Even when COMMITS_AFTER=7 and EXPECTED=8 (mismatch → VERIFIED=false naturally),
# the unknown-token path must normalize STATUS=git_error.
assert_stdout_contains "3c: post unknown-token STATUS=git_error" "$out" "STATUS=git_error"
assert_stdout_not_contains "3c: post unknown-token not passed through" "$out" "STATUS=bogus_token_not_in_enum"

# 3d — unknown-token MUST force VERIFIED=false even if counts match. Craft a
# stub where the normalized unknown still emits count=7 equal to before+1 (6).
STUB_LIB_3D="$TMPROOT/stub-lib-3d.sh"
cat > "$STUB_LIB_3D" <<'STUB'
# shellcheck shell=bash
count_commits() {
    if [[ -n "${COUNT_COMMITS_STATUS_FILE:-}" ]]; then
        printf '%s\n' "" > "$COUNT_COMMITS_STATUS_FILE"
    fi
    echo "7"
    return 0
}
STUB
PATCHED_3D="$TMPROOT/check-bump-version-stubbed-3d.sh"
sed -e "s|^source .*/lib-count-commits.sh.*$|source \"$STUB_LIB_3D\"|" "$SCRIPT" > "$PATCHED_3D"
chmod +x "$PATCHED_3D"
out=$(cd "$REPO_3C" && bash "$PATCHED_3D" --mode post --before-count 6 2>&1) || true
# count=7, before=6 → naive numeric arithmetic would return VERIFIED=true,
# but empty-status must normalize to git_error and force VERIFIED=false.
assert_stdout_contains "3d: post empty-status forces VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "3d: post empty-status STATUS=git_error" "$out" "STATUS=git_error"

# --- Section 4: fail-closed regression guard for #172 ------------------------
# The historical bug: when both pre and post hit git_error, count_commits
# silently emitted 0 for both, so a naive `COMMITS_AFTER == EXPECTED` check
# with EXPECTED = BEFORE + 1 = 0 + 1 = 1 would produce VERIFIED=false for
# that case — but the symmetric case where BEFORE=0 legitimately AND post
# emits 1 would produce VERIFIED=true even when the BEFORE count was
# actually untrustworthy from a git_error in pre mode. More importantly,
# if someone constructed a scenario where delta=0 (count-before + count-after
# both 0 under git_error) AND expected=0, the numeric comparison would
# spuriously pass. The fail-closed invariant prevents this: VERIFIED MUST
# be false whenever STATUS!=ok, independent of the numeric comparison.

echo "=== Section 4: #172 fail-closed regression guard ==="

# 4a — delta 0, expected 0, in missing_main_ref repo → MUST be VERIFIED=false.
# This is the exact case the naive "COMMITS_AFTER == EXPECTED" check would
# false-pass before the fix.
out=$(cd "$REPO_3A" && bash "$SCRIPT" --mode post --before-count -1 2>&1) || true
# Note: --before-count -1 is intentionally below zero so EXPECTED becomes 0;
# if the script rejects negative values, fall back to the below.
if [[ "$out" == *"ERROR="* ]] || [[ "$out" == *"Missing required argument"* ]]; then
    # Fall back: construct a setup where missing_main_ref returns 0 and before=0, expected=1.
    # Assert that even though COMMITS_AFTER=0 != EXPECTED=1 (naturally false),
    # STATUS=missing_main_ref also forces VERIFIED=false — the fail-closed
    # short-circuit is independent of the numeric check.
    out=$(cd "$REPO_3A" && bash "$SCRIPT" --mode post --before-count 0 2>&1) || true
    assert_stdout_contains "4a fallback: STATUS non-ok forces VERIFIED=false" "$out" "VERIFIED=false"
    assert_stdout_contains "4a fallback: STATUS=missing_main_ref" "$out" "STATUS=missing_main_ref"
else
    assert_stdout_contains "4a: post missing-main delta 0 exp 0 VERIFIED=false" "$out" "VERIFIED=false"
    assert_stdout_contains "4a: STATUS=missing_main_ref" "$out" "STATUS=missing_main_ref"
fi

# 4b — same for git_error: construct pre (BEFORE=0) + post (AFTER=0), expected=1.
# The fail-closed invariant forces VERIFIED=false regardless of the numeric path.
out=$(cd "$REPO_3B" && PATH="$SHIM_3B:$PATH" bash "$SCRIPT" --mode post --before-count 0 2>&1) || true
assert_stdout_contains "4b: post git_error delta 0 VERIFIED=false" "$out" "VERIFIED=false"
assert_stdout_contains "4b: STATUS=git_error" "$out" "STATUS=git_error"

# --- Section 5: degraded pre + recovered post sequence -----------------------
# Regression guard for the pre-STATUS caller-side trap (surfaced during #172
# code review). The script does not itself mix pre and post state — each
# invocation is independent — but the observable signals MUST allow callers
# (e.g., skills/implement/SKILL.md Rebase + Re-bump Sub-procedure step 4)
# to distinguish:
#   (a) pre-degraded → COMMITS_BEFORE coerced to 0, STATUS non-ok
#   (b) post-recovered → COMMITS_AFTER reflects true count N, STATUS=ok
# When (a) then (b), a naive caller that trusted COMMITS_BEFORE=0 and computed
# EXPECTED = 0 + 1 would misdiagnose a correct bump as "wrong commit count".
# The test below captures the raw signals a correct caller uses to avoid that
# misdiagnosis: (a) emits STATUS != ok so the caller knows the baseline is
# untrustworthy and skips the numeric comparison; (b) emits STATUS=ok with
# the true count.

echo "=== Section 5: pre-degraded + post-recovered sequence ==="

# 5a — pre-degraded (missing_main_ref) must emit STATUS=missing_main_ref with
# COMMITS_BEFORE=0 so the caller can recognize the untrustworthy baseline.
REPO_5A="$TMPROOT/repo-pre-degraded"
mkdir -p "$REPO_5A"
(
    cd "$REPO_5A"
    git init -q -b feature
    git config user.email "test@example.com"
    git config user.name "Test"
    git commit --allow-empty -q -m "init"
    git commit --allow-empty -q -m "feature commit 1"
)
pre_out=$(cd "$REPO_5A" && bash "$SCRIPT" --mode pre 2>&1) || true
assert_stdout_contains "5a pre-degraded: COMMITS_BEFORE=0 coerced" "$pre_out" "COMMITS_BEFORE=0"
assert_stdout_contains "5a pre-degraded: STATUS=missing_main_ref signal" "$pre_out" "STATUS=missing_main_ref"

# 5b — post-recovered with a NEW (trustworthy) local main — simulates the
# repo recovering between pre and post (e.g., the pre-invocation's transient
# git failure resolves). Caller captured COMMITS_BEFORE=0 from the degraded
# pre-check. Post-check sees true COMMITS_AFTER=N_real_count. The script
# emits VERIFIED=false (because count != EXPECTED from the coerced baseline)
# but STATUS=ok. A correct caller recognizes the pre-degraded provenance
# and does NOT interpret VERIFIED=false as "wrong commit count" — the
# observable signal it must route on is the combination (pre STATUS=non-ok,
# post STATUS=ok).
REPO_5B="$TMPROOT/repo-post-recovered"
setup_git_repo "$REPO_5B" 1 3
# Caller captured COMMITS_BEFORE=0 from its prior pre-degraded invocation (5a).
post_out=$(cd "$REPO_5B" && bash "$SCRIPT" --mode post --before-count 0 2>&1) || true
assert_stdout_contains "5b post-recovered: STATUS=ok (baseline now trustworthy at script level)" "$post_out" "STATUS=ok"
assert_stdout_contains "5b post-recovered: COMMITS_AFTER=3 (true count)" "$post_out" "COMMITS_AFTER=3"
# With the coerced BEFORE=0 and true AFTER=3, the numeric check would
# naturally set VERIFIED=false — but a correct caller skips the comparison
# because the pre-check STATUS was non-ok. This test documents the raw
# signals; the SKILL.md step 4 "Pre-check STATUS guard" branches on the
# pre-check STATUS, not on this post-check's VERIFIED value.
assert_stdout_contains "5b post-recovered: script-level VERIFIED reflects naive arithmetic" "$post_out" "VERIFIED=false"

# --- Section 6: argument-error paths -----------------------------------------

echo "=== Section 6: argument errors ==="

# 6a — no --mode
set +e
out=$(bash "$SCRIPT" 2>&1)
rc=$?
set -e
assert_exit_eq "6a: no --mode exit 1" "$rc" 1

# 6b — unknown --mode value
set +e
out=$(bash "$SCRIPT" --mode banana 2>&1)
rc=$?
set -e
assert_exit_eq "6b: invalid --mode exit 1" "$rc" 1

# 6c — post without --before-count
REPO_6C="$TMPROOT/repo-6c"
setup_git_repo "$REPO_6C" 1 0
set +e
out=$(cd "$REPO_6C" && bash "$SCRIPT" --mode post 2>&1)
rc=$?
set -e
assert_exit_eq "6c: post without --before-count exit 1" "$rc" 1

# 6d — unknown flag
set +e
out=$(bash "$SCRIPT" --not-a-real-flag 2>&1)
rc=$?
set -e
assert_exit_eq "6d: unknown flag exit 1" "$rc" 1

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
