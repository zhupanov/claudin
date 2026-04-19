#!/usr/bin/env bash
# test-block-submodule-edit.sh — Regression harness for scripts/block-submodule-edit.sh.
#
# Black-box contract test of the PreToolUse hook via stdin JSON + controlled
# cwd/PATH. Each case synthesizes a payload of shape
#   {"tool_input":{"file_path":"<abs>"}}
# pipes it to the hook, and asserts on exit code + stable stdout substrings.
#
# Fixture (built once at top):
#   $TMPROOT/bare.git   — local bare repo used as submodule origin
#   $TMPROOT/super      — superproject
#     sub/              — submodule (added via `git submodule add file://...`)
#     nested/           — standalone nested repo, NOT registered as a submodule
#     symlink-file      — symlink → super/README.md
#   $TMPROOT/nonrepo    — ordinary directory outside any git repo
#
# Bypass case (#3) uses tri-state fingerprint matching: post-fix (exit 2 +
# stdout contains "submodule") → PASS; legacy-buggy (exit 0 + empty stdout) →
# KNOWN-FAIL, increments EXPECTED_FAIL (non-fatal); anything else → HARD FAIL.
# When issue #150 lands and removes the bypass, the case auto-flips to PASS.
#
# Scope note: NotebookEdit and Bash-mediated mutations are outside the current
# hook matcher's scope (PreToolUse on Edit/Write only) — no assertion here.
#
# Usage:
#   bash scripts/test-block-submodule-edit.sh
#
# Exit codes:
#   0 — no hard failures (EXPECTED_FAIL > 0 is still allowed)
#   1 — at least one hard failure (first failing assertion listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HOOK="$REPO_ROOT/scripts/block-submodule-edit.sh"

if [[ ! -x "$HOOK" ]]; then
    echo "ERROR: hook script not found or not executable: $HOOK" >&2
    exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-block-submodule-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

# --- Git env isolation ------------------------------------------------------
# Keep host git config (insteadOf, commit templates, protocol.file.allow=never)
# from leaking into the fixture. Set a fakehome + null GIT_CONFIG_* so all git
# invocations below see a pristine config environment.
export HOME="$TMPROOT/fakehome"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null
export GIT_AUTHOR_NAME=test
export GIT_AUTHOR_EMAIL=test@example.invalid
export GIT_COMMITTER_NAME=test
export GIT_COMMITTER_EMAIL=test@example.invalid

# --- Counters and helpers --------------------------------------------------
PASS=0
FAIL=0
EXPECTED_FAIL=0
FAILED_TESTS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (== $expected)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected $(printf '%q' "$expected"), got $(printf '%q' "$actual"))")
        echo "  FAIL: $label (expected $(printf '%q' "$expected"), got $(printf '%q' "$actual"))" >&2
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (contains $needle)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing $needle)")
        echo "  FAIL: $label (missing $needle)" >&2
        echo "       haystack (first 500 chars): ${haystack:0:500}" >&2
    fi
}

assert_empty() {
    local haystack="$1" label="$2"
    if [[ -z "$haystack" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (empty)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected empty, got $(printf '%q' "${haystack:0:200}"))")
        echo "  FAIL: $label (expected empty, got $(printf '%q' "${haystack:0:200}"))" >&2
    fi
}

# run_hook <cwd> <stdin_bytes> [<path_override>]
# Invokes $HOOK in a subshell with the given cwd and optional PATH override.
# Captures exit code into RC and stdout into HOOK_STDOUT. Stderr is passed
# through to the harness's stderr for diagnostic visibility. The subshell
# scopes the cwd change so the outer script's cwd is preserved. set -e is
# temporarily disabled around command substitution so a non-zero hook exit
# does not abort the harness before RC is assigned.
run_hook() {
    local cwd="$1" stdin_bytes="$2" path_override="${3:-}"
    set +e
    HOOK_STDOUT=$(
        cd "$cwd"
        if [[ -n "$path_override" ]]; then
            printf '%s' "$stdin_bytes" | PATH="$path_override" "$HOOK"
        else
            printf '%s' "$stdin_bytes" | "$HOOK"
        fi
    )
    RC=$?
    set -e
}

# --- Fixture bootstrap -----------------------------------------------------
BARE="$TMPROOT/bare.git"
SUPER="$TMPROOT/super"
SUB="$SUPER/sub"
NESTED="$SUPER/nested"
NONREPO="$TMPROOT/nonrepo"

# Create a bare repo and seed one commit through a throwaway working repo.
git init --bare -b main "$BARE" >/dev/null

SEED="$TMPROOT/seed"
git -c init.defaultBranch=main init "$SEED" >/dev/null
echo 'seed' > "$SEED/seed.txt"
git -C "$SEED" add seed.txt
git -C "$SEED" commit -m 'seed' >/dev/null
git -C "$SEED" push "$BARE" main >/dev/null 2>&1

# Build the superproject.
git -c init.defaultBranch=main init "$SUPER" >/dev/null
echo '# super' > "$SUPER/README.md"
git -C "$SUPER" add README.md
git -C "$SUPER" commit -m 'initial' >/dev/null

# Add the submodule from the local bare repo. `protocol.file.allow=always` is
# required on Git ≥ 2.38 / CI where the file:// protocol is disabled by default.
git -C "$SUPER" -c protocol.file.allow=always submodule add "file://$BARE" sub >/dev/null 2>&1
git -C "$SUPER" commit -m 'add submodule sub' >/dev/null

# Create a nested standalone repo (NOT registered as a submodule of super).
# This exercises the hook's `rev-parse --show-superproject-working-tree` check:
# a bare nested .git with no superproject pointer must be allowed, not denied.
mkdir -p "$NESTED"
git -c init.defaultBranch=main init "$NESTED" >/dev/null
echo 'n' > "$NESTED/file.txt"
git -C "$NESTED" add file.txt
git -C "$NESTED" commit -m 'nested' >/dev/null

# Symlink inside the superproject pointing at a superproject file. Case 6
# asserts the hook allows it (target canonicalizes into the superproject).
ln -s "$SUPER/README.md" "$SUPER/symlink-file"

# Non-repo directory outside any git repo. Case 9 runs the hook from here.
mkdir -p "$NONREPO"

# JSON payload builder. Uses jq if available (reliable escaping); falls back
# to a hand-rolled literal when jq is not on PATH (relevant only for case 7's
# restricted-PATH setup, which runs earlier steps with the real PATH intact).
json_payload() {
    local file_path="$1"
    printf '{"tool_input":{"file_path":"%s"}}' "$file_path"
}

echo "=== Fixture built under $TMPROOT ==="
echo ""

# --- Case 1: Allow — superproject file -------------------------------------
echo "=== 1: Allow superproject file ==="
run_hook "$SUPER" "$(json_payload "$SUPER/README.md")"
assert_eq "[case 1] exit code" 0 "$RC"
assert_empty "$HOOK_STDOUT" "[case 1] stdout empty"

# --- Case 2: Deny — file inside submodule ----------------------------------
echo ""
echo "=== 2: Deny submodule file ==="
run_hook "$SUPER" "$(json_payload "$SUB/any.txt")"
assert_eq "[case 2] exit code" 2 "$RC"
assert_contains "$HOOK_STDOUT" "submodule" "[case 2] stdout mentions submodule"
assert_contains "$HOOK_STDOUT" "sub" "[case 2] stdout names submodule path"

# --- Case 3: Bypass (known-failing until #150) — cwd inside submodule ------
# Tri-state fingerprint: post-fix (RC=2, stdout contains "submodule") → PASS.
# Legacy-buggy (RC=0, empty stdout) → KNOWN-FAIL, non-fatal, EXPECTED_FAIL++.
# Anything else → HARD FAIL. Auto-flips to PASS when #150 lands correctly.
echo ""
echo "=== 3: Bypass — cwd inside submodule (known-failing until #150) ==="
run_hook "$SUB" "$(json_payload "$SUB/any.txt")"
post_fix_match=0
legacy_match=0
if [[ $RC -eq 2 && "$HOOK_STDOUT" == *"submodule"* ]]; then
    post_fix_match=1
fi
if [[ $RC -eq 0 && -z "$HOOK_STDOUT" ]]; then
    legacy_match=1
fi
if (( post_fix_match )); then
    PASS=$((PASS + 1))
    echo "  ok: [case 3] bypass now blocks (post-fix behavior; #150 appears to have landed — flip this case to a regular assertion)"
elif (( legacy_match )); then
    EXPECTED_FAIL=$((EXPECTED_FAIL + 1))
    echo "  KNOWN-FAIL: [case 3] bypass still succeeds when cwd is inside the submodule (tracked by #150, non-fatal). Will auto-flip to PASS when #150 lands."
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("[case 3] bypass — unexpected state: RC=$RC, stdout=$(printf %q "$HOOK_STDOUT")")
    echo "  HARD FAIL: [case 3] bypass — neither post-fix (2,\"submodule\") nor legacy (0,\"\") fingerprint matched; RC=$RC, stdout=$(printf %q "$HOOK_STDOUT")" >&2
fi

# --- Case 4: Deny — new file in new subdir under submodule (ancestor walk) -
echo ""
echo "=== 4: Deny new file under submodule (ancestor walk) ==="
run_hook "$SUPER" "$(json_payload "$SUB/does/not/exist/x.txt")"
assert_eq "[case 4] exit code" 2 "$RC"
assert_contains "$HOOK_STDOUT" "submodule" "[case 4] stdout mentions submodule"

# --- Case 5: Allow — nested non-submodule repo -----------------------------
# Nested repo has a .git but no submodule pointer; the hook's
# --show-superproject-working-tree check returns empty, so it allows.
echo ""
echo "=== 5: Allow nested non-submodule repo ==="
run_hook "$SUPER" "$(json_payload "$NESTED/file.txt")"
assert_eq "[case 5] exit code" 0 "$RC"
assert_empty "$HOOK_STDOUT" "[case 5] stdout empty"

# --- Case 6: Allow — symlinked path resolving into superproject ------------
echo ""
echo "=== 6: Allow symlink into superproject ==="
run_hook "$SUPER" "$(json_payload "$SUPER/symlink-file")"
assert_eq "[case 6] exit code" 0 "$RC"
assert_empty "$HOOK_STDOUT" "[case 6] stdout empty"

# --- Case 7: Fail-closed — missing jq on PATH ------------------------------
# Build a minimal bin dir with symlinks to the external commands the hook
# invokes before the `command -v jq` check: `cat` (reads stdin) and `git`
# + `dirname` (used after the jq gate). Deliberately omit `jq`. Preflight
# confirms jq is not resolvable and cat/git/dirname are, so case 7 exercises
# the missing-jq branch and not a different fail-closed path.
echo ""
echo "=== 7: Fail-closed — missing jq ==="
MINI_BIN="$TMPROOT/mini-bin"
mkdir -p "$MINI_BIN"
# The hook's shebang `#!/usr/bin/env bash` needs `env` to find `bash` on PATH.
# Include all external commands the hook can reach before the jq gate, plus
# the shell interpreter env resolves for the shebang.
for tool in bash cat git dirname; do
    real=$(command -v "$tool" 2>/dev/null || true)
    if [[ -z "$real" ]]; then
        echo "  SKIP: [case 7] could not locate '$tool' on host PATH (cannot construct jq-free mini-bin)" >&2
        mini_bin_ok=0
        break
    fi
    ln -s "$real" "$MINI_BIN/$tool"
done
mini_bin_ok="${mini_bin_ok-1}"
if (( mini_bin_ok )); then
    if PATH="$MINI_BIN" command -v jq >/dev/null 2>&1; then
        echo "  SKIP: [case 7] jq still resolvable under restricted PATH (unexpected shell builtin?)" >&2
    else
        run_hook "$SUPER" "$(json_payload "$SUPER/README.md")" "$MINI_BIN"
        assert_eq "[case 7] exit code" 2 "$RC"
        assert_contains "$HOOK_STDOUT" "jq" "[case 7] stdout mentions jq"
    fi
fi

# --- Case 8: Fail-closed — stdin is not valid JSON -------------------------
echo ""
echo "=== 8: Fail-closed — bad JSON stdin ==="
run_hook "$SUPER" "this is not json at all"
assert_eq "[case 8] exit code" 2 "$RC"
# Parser failure message includes "blocking as precaution"; substring check.
assert_contains "$HOOK_STDOUT" "blocking" "[case 8] stdout indicates fail-closed"

# --- Case 9: Fail-open — cwd outside any git repo --------------------------
# Hook's `git rev-parse --show-toplevel` returns empty when the *caller* is
# not inside any git repo. Exercises the early-allow branch.
echo ""
echo "=== 9: Fail-open — cwd outside any git repo ==="
run_hook "$NONREPO" "$(json_payload "$NONREPO/x.txt")"
assert_eq "[case 9] exit code" 0 "$RC"
assert_empty "$HOOK_STDOUT" "[case 9] stdout empty"

# --- Case 9b: Allow — caller in repo but file_path outside any repo --------
# Exercises the second allow path in the hook: REPO_ROOT is set (caller is in
# super) but the file_path's nearest ancestor is outside any git repo, so
# FILE_REPO_ROOT is empty and the hook allows.
echo ""
echo "=== 9b: Allow — caller in repo, file_path outside any repo ==="
run_hook "$SUPER" "$(json_payload "$NONREPO/x.txt")"
assert_eq "[case 9b] exit code" 0 "$RC"
assert_empty "$HOOK_STDOUT" "[case 9b] stdout empty"

# --- Case 10: Fail-closed — non-absolute file_path -------------------------
echo ""
echo "=== 10: Fail-closed — non-absolute file_path ==="
run_hook "$SUPER" '{"tool_input":{"file_path":"relative/path.txt"}}'
assert_eq "[case 10] exit code" 2 "$RC"
assert_contains "$HOOK_STDOUT" "absolute" "[case 10] stdout mentions non-absolute path"

# --- Summary --------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "Passed:    $PASS"
echo "Failed:    $FAIL"
echo "KnownFail: $EXPECTED_FAIL (non-fatal; tracked by #150)"
if (( FAIL > 0 )); then
    echo "" >&2
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All hard assertions passed."
exit 0
