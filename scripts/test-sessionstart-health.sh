#!/usr/bin/env bash
# test-sessionstart-health.sh — Regression test for scripts/sessionstart-health.sh.
#
# Four cases, each run with a controlled PATH that contains only stub scripts
# for the tools we want "present" in that case — no real /usr/bin/jq or
# /usr/bin/git leaks in. The script-under-test is invoked via an absolute
# bash path (resolved once before `env -i` from the ambient PATH, so this
# works on Nix-style layouts where bash is not at /bin/bash) so its
# `#!/usr/bin/env bash` shebang never triggers PATH lookup for bash itself.
#
#   Case 1: jq + git both present        → exit 0, empty stdout
#   Case 2: jq missing, git present      → exit 0, JSON mentions jq
#   Case 3: jq present, git missing      → exit 0, JSON mentions git
#   Case 4: both missing                 → exit 0, JSON mentions both
#
# JSON validation uses the harness's own jq (from the outer PATH), not the
# stubs visible to the script-under-test.
#
# Usage:  bash scripts/test-sessionstart-health.sh
# Exit codes:  0 on success, 1 on first failure.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRIPT="$REPO_ROOT/scripts/sessionstart-health.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL: $SCRIPT does not exist or is not executable" >&2
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo "FAIL: harness jq not on PATH; cannot validate JSON output" >&2
    exit 1
fi

# Resolve bash from ambient PATH once, before env -i scrubs the environment.
# This lets the harness run on Nix-style layouts where bash is not at /bin/bash.
BASH_BIN=$(command -v bash)
if [[ -z "$BASH_BIN" || ! -x "$BASH_BIN" ]]; then
    echo "FAIL: could not resolve bash on ambient PATH" >&2
    exit 1
fi

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local got="$1" expected="$2" label="$3"
    if [[ "$got" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (got '$got', expected '$expected')")
        echo "  FAIL: $label" >&2
        echo "       got:      '$got'" >&2
        echo "       expected: '$expected'" >&2
    fi
}

assert_empty() {
    local got="$1" label="$2"
    if [[ -z "$got" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (stdout empty)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (stdout non-empty)")
        echo "  FAIL: $label" >&2
        echo "       got: '$got'" >&2
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (contains '$needle')"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing '$needle')")
        echo "  FAIL: $label (missing '$needle')" >&2
        echo "       haystack: '$haystack'" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (does not contain '$needle')"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (leaked '$needle')")
        echo "  FAIL: $label (leaked '$needle')" >&2
    fi
}

# Build a stub bin directory. Stubs are minimal: they just exit 0. The point
# is that `command -v <tool>` returns zero when the stub is present and
# non-zero when it is absent.
build_stub_dir() {
    local dir="$1"
    shift
    rm -rf "$dir"
    mkdir -p "$dir"
    for tool in "$@"; do
        printf '#!/bin/sh\nexit 0\n' > "$dir/$tool"
        chmod +x "$dir/$tool"
    done
}

# Run the script under test with a stub-only PATH. The pre-resolved $BASH_BIN
# bypasses the shebang's PATH-lookup of `env` and `bash`, so the only
# executables the script can see are the stubs in $stub_dir.
run_under_stubs() {
    local stub_dir="$1"
    local out_file="$2"
    local err_file="$3"
    local rc=0
    env -i PATH="$stub_dir" "$BASH_BIN" "$SCRIPT" < /dev/null > "$out_file" 2> "$err_file" || rc=$?
    printf '%s\n' "$rc"
}

echo "=== Case 1: jq + git both present ==="
build_stub_dir "$tmp/c1_bin" jq git
rc=$(run_under_stubs "$tmp/c1_bin" "$tmp/c1.out" "$tmp/c1.err")
assert_eq "$rc" "0" "case 1: exit code 0"
stdout=$(cat "$tmp/c1.out")
assert_empty "$stdout" "case 1: stdout empty"

echo "=== Case 2: jq missing, git present ==="
build_stub_dir "$tmp/c2_bin" git
rc=$(run_under_stubs "$tmp/c2_bin" "$tmp/c2.out" "$tmp/c2.err")
assert_eq "$rc" "0" "case 2: exit code 0"
stdout=$(cat "$tmp/c2.out")
# Must be valid JSON and a single line.
lines=$(printf '%s' "$stdout" | wc -l | tr -d ' ')
assert_eq "$lines" "0" "case 2: exactly one line of stdout (no trailing newline counted by wc -l)"
# Validate JSON structure via harness jq.
if ! printf '%s' "$stdout" | jq -e . >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("case 2: stdout is not valid JSON")
    echo "  FAIL: case 2: stdout is not valid JSON" >&2
    echo "       stdout: '$stdout'" >&2
else
    PASS=$((PASS + 1))
    echo "  ok: case 2: stdout is valid JSON"
fi
hook_event=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.hookEventName // empty')
assert_eq "$hook_event" "SessionStart" "case 2: hookEventName"
ctx=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "$ctx" "jq" "case 2: additionalContext mentions jq"
assert_not_contains "$ctx" "git not on PATH" "case 2: additionalContext does not mention git (git is present)"

echo "=== Case 3: jq present, git missing ==="
build_stub_dir "$tmp/c3_bin" jq
rc=$(run_under_stubs "$tmp/c3_bin" "$tmp/c3.out" "$tmp/c3.err")
assert_eq "$rc" "0" "case 3: exit code 0"
stdout=$(cat "$tmp/c3.out")
lines=$(printf '%s' "$stdout" | wc -l | tr -d ' ')
assert_eq "$lines" "0" "case 3: exactly one line of stdout"
if ! printf '%s' "$stdout" | jq -e . >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("case 3: stdout is not valid JSON")
    echo "  FAIL: case 3: stdout is not valid JSON" >&2
    echo "       stdout: '$stdout'" >&2
else
    PASS=$((PASS + 1))
    echo "  ok: case 3: stdout is valid JSON"
fi
hook_event=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.hookEventName // empty')
assert_eq "$hook_event" "SessionStart" "case 3: hookEventName"
ctx=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "$ctx" "git" "case 3: additionalContext mentions git"
assert_not_contains "$ctx" "jq not on PATH" "case 3: additionalContext does not mention jq (jq is present)"

echo "=== Case 4: both missing ==="
build_stub_dir "$tmp/c4_bin"
rc=$(run_under_stubs "$tmp/c4_bin" "$tmp/c4.out" "$tmp/c4.err")
assert_eq "$rc" "0" "case 4: exit code 0"
stdout=$(cat "$tmp/c4.out")
lines=$(printf '%s' "$stdout" | wc -l | tr -d ' ')
assert_eq "$lines" "0" "case 4: exactly one line of stdout"
if ! printf '%s' "$stdout" | jq -e . >/dev/null 2>&1; then
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("case 4: stdout is not valid JSON")
    echo "  FAIL: case 4: stdout is not valid JSON" >&2
    echo "       stdout: '$stdout'" >&2
else
    PASS=$((PASS + 1))
    echo "  ok: case 4: stdout is valid JSON"
fi
hook_event=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.hookEventName // empty')
assert_eq "$hook_event" "SessionStart" "case 4: hookEventName"
ctx=$(printf '%s' "$stdout" | jq -r '.hookSpecificOutput.additionalContext // empty')
assert_contains "$ctx" "jq" "case 4: additionalContext mentions jq"
assert_contains "$ctx" "git" "case 4: additionalContext mentions git"

echo
echo "=== Summary ==="
echo "  passed: $PASS"
echo "  failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo >&2
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi

echo "all tests passed"
exit 0
