#!/usr/bin/env bash
# test-drop-bump-commit.sh — Offline regression harness for drop-bump-commit.sh.
# Creates isolated temp repos with controlled commit shapes and validates output.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DROP_SCRIPT="$SCRIPT_DIR/drop-bump-commit.sh"

PASS=0
FAIL=0
TMPDIR_BASE=""

cleanup() {
    [[ -n "$TMPDIR_BASE" && -d "$TMPDIR_BASE" ]] && rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

TMPDIR_BASE=$(mktemp -d)

# Helper: create a fresh git repo with an initial commit, then create a bump
# commit touching the specified files.
# Usage: setup_repo <repo_dir> <file1> [<file2> ...]
setup_repo() {
    local repo_dir="$1"; shift
    mkdir -p "$repo_dir"
    cd "$repo_dir"
    git init -q
    git config user.email "test@test.com"
    git config user.name "Test"

    # Initial commit
    mkdir -p .claude-plugin
    echo '{}' > .claude-plugin/plugin.json
    echo '' > CHANGELOG.md
    git add -A
    git commit -q -m "Initial commit"

    # Bump commit touching specified files
    for f in "$@"; do
        local dir
        dir=$(dirname "$f")
        [[ "$dir" != "." ]] && mkdir -p "$dir"
        echo "bumped" >> "$f"
    done
    git add -A
    git commit -q -m "Bump version to 1.2.3"
}

# Helper: run drop-bump-commit.sh and check DROPPED value
# Usage: run_test <test_name> <expected_dropped> [env_var_setting]
# env_var_setting: "unset" (default), "empty", or a value for LARCH_BUMP_FILES
run_test() {
    local test_name="$1"
    local expected="$2"
    local env_setting="${3:-unset}"

    local output
    if [[ "$env_setting" == "unset" ]]; then
        output=$(unset LARCH_BUMP_FILES; bash "$DROP_SCRIPT" 2>/dev/null) || true
    elif [[ "$env_setting" == "empty" ]]; then
        output=$(LARCH_BUMP_FILES="" bash "$DROP_SCRIPT" 2>/dev/null) || true
    else
        output=$(LARCH_BUMP_FILES="$env_setting" bash "$DROP_SCRIPT" 2>/dev/null) || true
    fi

    local actual
    actual=$(echo "$output" | grep "^DROPPED=" | head -1 | cut -d= -f2)

    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
    else
        echo "FAIL: $test_name — expected DROPPED=$expected, got DROPPED=$actual" >&2
        FAIL=$((FAIL + 1))
    fi
}

# --- Default path (LARCH_BUMP_FILES unset) ---

# Test 1: plugin.json only
REPO="$TMPDIR_BASE/test1"
setup_repo "$REPO" .claude-plugin/plugin.json
run_test "Default: plugin.json only → DROPPED=true" "true"

# Test 2: plugin.json + CHANGELOG.md
REPO="$TMPDIR_BASE/test2"
setup_repo "$REPO" .claude-plugin/plugin.json CHANGELOG.md
run_test "Default: plugin.json + CHANGELOG.md → DROPPED=true" "true"

# Test 3: unexpected file
REPO="$TMPDIR_BASE/test3"
setup_repo "$REPO" version.go
run_test "Default: unexpected file → DROPPED=false" "false"

# Test 4: CHANGELOG-only (must reject on default path)
REPO="$TMPDIR_BASE/test4"
setup_repo "$REPO" CHANGELOG.md
run_test "Default: CHANGELOG-only → DROPPED=false" "false"

# --- Custom path (LARCH_BUMP_FILES set) ---

# Test 5: single custom file
REPO="$TMPDIR_BASE/test5"
setup_repo "$REPO" version.go
run_test "Custom: single file → DROPPED=true" "true" "version.go"

# Test 6: single custom file + CHANGELOG.md
REPO="$TMPDIR_BASE/test6"
setup_repo "$REPO" version.go CHANGELOG.md
run_test "Custom: single + CHANGELOG.md → DROPPED=true" "true" "version.go"

# Test 7: multi-file (all present)
REPO="$TMPDIR_BASE/test7"
setup_repo "$REPO" version.go package.json
run_test "Custom: multi-file all present → DROPPED=true" "true" "version.go:package.json"

# Test 8: multi-file (subset — only one changed)
REPO="$TMPDIR_BASE/test8"
setup_repo "$REPO" version.go
run_test "Custom: multi-file subset → DROPPED=true" "true" "version.go:package.json"

# Test 9: missing file (commit touches unlisted file)
REPO="$TMPDIR_BASE/test9"
setup_repo "$REPO" package.json
run_test "Custom: missing file → DROPPED=false" "false" "version.go"

# Test 10: replacement blocks default (plugin.json not in custom set)
REPO="$TMPDIR_BASE/test10"
setup_repo "$REPO" .claude-plugin/plugin.json
run_test "Custom: replacement blocks default → DROPPED=false" "false" "version.go"

# Test 11: empty env var (fail-closed)
REPO="$TMPDIR_BASE/test11"
setup_repo "$REPO" version.go
run_test "Empty env var → DROPPED=false" "false" "empty"

# Test 12: whitespace segments
REPO="$TMPDIR_BASE/test12"
setup_repo "$REPO" version.go
run_test "Whitespace segments → DROPPED=true" "true" " version.go : "

# Test 13: all-empty segments (fail-closed)
REPO="$TMPDIR_BASE/test13"
setup_repo "$REPO" version.go
run_test "All-empty segments → DROPPED=false" "false" ":::"

# Test 14: CHANGELOG.md in custom set (harmless duplicate)
REPO="$TMPDIR_BASE/test14"
setup_repo "$REPO" version.go CHANGELOG.md
run_test "CHANGELOG.md in custom set → DROPPED=true" "true" "version.go:CHANGELOG.md"

# Test 15: CHANGELOG-only on custom path (must reject — no configured bump file touched)
REPO="$TMPDIR_BASE/test15"
setup_repo "$REPO" CHANGELOG.md
run_test "Custom: CHANGELOG-only → DROPPED=false" "false" "version.go"

# Test 16: empty-diff bump commit on custom path (must reject — no files at all)
REPO="$TMPDIR_BASE/test16"
mkdir -p "$REPO"
cd "$REPO"
git init -q
git config user.email "test@test.com"
git config user.name "Test"
mkdir -p .claude-plugin
echo '{}' > .claude-plugin/plugin.json
echo '' > CHANGELOG.md
git add -A
git commit -q -m "Initial commit"
git commit --allow-empty -q -m "Bump version to 1.2.3"
run_test "Custom: empty-diff → DROPPED=false" "false" "version.go"

# --- Summary ---
TOTAL=$((PASS + FAIL))
echo ""
echo "test-drop-bump-commit: $PASS/$TOTAL passed"
if [[ $FAIL -gt 0 ]]; then
    echo "FAILED: $FAIL test(s)" >&2
    exit 1
fi
