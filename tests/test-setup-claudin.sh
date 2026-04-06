#!/usr/bin/env bash
# test-setup-claudin.sh — Integration test for setup-claudin.sh
#
# Creates a temporary fake client repo with claudin as a subdirectory,
# runs setup-claudin.sh, and verifies symlinks are created correctly
# for the claudin/ subdirectory structure under scripts/generic/ and
# skills/shared/.
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
CLAUDIN_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Create a temporary directory for the fake client repo
TEST_REPO_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_REPO_DIR"' EXIT

echo "=== Setting up fake client repo in $TEST_REPO_DIR ==="

# Initialize a git repo
cd "$TEST_REPO_DIR"
git init -q
git config user.email "test@claudin.test"
git config user.name "Claudin Test"
git commit --allow-empty -m "init" -q

# Copy claudin into the fake client repo as a subdirectory
# (not a real submodule, but setup-claudin.sh only needs the directory structure)
cp -R "$CLAUDIN_DIR" "$TEST_REPO_DIR/claudin"

# Create settings.local.json fixture in the source so the settings*.json skip
# is exercised during Phase 1. In CI this file is gitignored and absent from
# the cp -R copy, so we create it explicitly to test the glob skip.
if [[ ! -f "$TEST_REPO_DIR/claudin/.claude/settings.local.json" ]]; then
    echo '{}' > "$TEST_REPO_DIR/claudin/.claude/settings.local.json"
fi

# Run setup-claudin.sh from the repo root
echo ""
echo "=== Running setup-claudin.sh ==="
./claudin/setup-claudin.sh

# --- Verification ---
FAILURES=0

check_symlink() {
    local path="$1"
    local description="$2"
    if [[ -L "$path" ]]; then
        if [[ -e "$path" ]]; then
            echo "  PASS: $description ($path)"
        else
            echo "  FAIL: $description — symlink exists but target does not resolve ($path -> $(readlink "$path"))"
            FAILURES=$((FAILURES + 1))
        fi
    else
        echo "  FAIL: $description — not a symlink ($path)"
        FAILURES=$((FAILURES + 1))
    fi
}

check_not_exists() {
    local path="$1"
    local description="$2"
    if [[ -e "$path" || -L "$path" ]]; then
        echo "  FAIL: $description — should not exist ($path)"
        FAILURES=$((FAILURES + 1))
    else
        echo "  PASS: $description ($path does not exist)"
    fi
}

echo ""
echo "=== Verifying symlinks ==="

# Skill directories should be directory-level symlinks
echo "--- Skill directories (directory-level symlinks) ---"
for skill_dir in "$TEST_REPO_DIR"/claudin/.claude/skills/*/; do
    skill_name="$(basename "$skill_dir")"
    [[ "$skill_name" == "shared" ]] && continue
    [[ "$skill_name" == "relevant-checks" ]] && continue
    if [[ -f "$skill_dir/SKILL.md" ]]; then
        check_symlink ".claude/skills/$skill_name" "skill dir: $skill_name"
    fi
done

# relevant-checks should NOT be symlinked (repo-specific skill)
echo "--- relevant-checks ---"
check_not_exists ".claude/skills/relevant-checks" "relevant-checks should not be symlinked"

# Verify setup-claudin.sh does not conflict with a pre-existing relevant-checks directory
echo "--- relevant-checks conflict test ---"
mkdir -p ".claude/skills/relevant-checks"
echo "# Client-specific checks" > ".claude/skills/relevant-checks/SKILL.md"
# Re-run — should succeed without error despite the pre-existing directory
./claudin/setup-claudin.sh > /dev/null 2>&1
rc=$?
if [[ $rc -eq 0 ]]; then
    echo "  PASS: setup-claudin.sh succeeds with pre-existing relevant-checks"
else
    echo "  FAIL: setup-claudin.sh exited $rc with pre-existing relevant-checks"
    FAILURES=$((FAILURES + 1))
fi
# Verify the client's relevant-checks was not replaced
if [[ ! -L ".claude/skills/relevant-checks" && -f ".claude/skills/relevant-checks/SKILL.md" ]]; then
    echo "  PASS: client's relevant-checks preserved (not a symlink)"
else
    echo "  FAIL: client's relevant-checks was replaced or symlinked"
    FAILURES=$((FAILURES + 1))
fi

# Scripts under scripts/generic/claudin/ should be file-level symlinks
echo "--- Scripts (file-level symlinks under scripts/generic/claudin/) ---"
script_count=0
for script in "$TEST_REPO_DIR"/claudin/.claude/scripts/generic/claudin/*.sh; do
    script_name="$(basename "$script")"
    check_symlink ".claude/scripts/generic/claudin/$script_name" "script: $script_name"
    script_count=$((script_count + 1))
done
echo "  (checked $script_count scripts)"

# Shared .md files under skills/shared/claudin/ should be file-level symlinks
echo "--- Shared .md files (file-level symlinks under skills/shared/claudin/) ---"
md_count=0
for md_file in "$TEST_REPO_DIR"/claudin/.claude/skills/shared/claudin/*.md; do
    md_name="$(basename "$md_file")"
    check_symlink ".claude/skills/shared/claudin/$md_name" "shared md: $md_name"
    md_count=$((md_count + 1))
done
echo "  (checked $md_count shared .md files)"

# Agent files should be file-level symlinks
echo "--- Agent files ---"
for agent in "$TEST_REPO_DIR"/claudin/.claude/agents/*.md; do
    agent_name="$(basename "$agent")"
    check_symlink ".claude/agents/$agent_name" "agent: $agent_name"
done

# settings.json should NOT be symlinked
echo "--- settings*.json ---"
check_not_exists ".claude/settings.json" "settings.json should not be symlinked"

# settings.local.json should NOT be symlinked (covered by settings*.json glob skip)
# Fixture was created before the first run (see above), so this assertion is meaningful.
check_not_exists ".claude/settings.local.json" "settings.local.json should not be symlinked"

# --- Re-run test (idempotency) ---
echo ""
echo "=== Re-running setup-claudin.sh (idempotency test) ==="
./claudin/setup-claudin.sh

echo ""
echo "=== Verifying symlinks still correct after re-run ==="
rerun_ok=true
for script in "$TEST_REPO_DIR"/claudin/.claude/scripts/generic/claudin/*.sh; do
    script_name="$(basename "$script")"
    if [[ ! -L ".claude/scripts/generic/claudin/$script_name" ]] || [[ ! -e ".claude/scripts/generic/claudin/$script_name" ]]; then
        echo "  FAIL: script $script_name broken after re-run"
        FAILURES=$((FAILURES + 1))
        rerun_ok=false
    fi
done
if $rerun_ok; then
    echo "  PASS: All symlinks correct after re-run"
fi

# --- Phase 2: Dead symlink removal ---
echo ""
echo "=== Testing Phase 2: Dead symlink removal ==="
# Create a fake stale symlink simulating a pre-migration path pointing into claudin
mkdir -p .claude/scripts/generic
ln -s "../../../claudin/.claude/scripts/generic/nonexistent-old-script.sh" ".claude/scripts/generic/stale-old.sh"
# Re-run setup-claudin.sh — Phase 2 should remove the stale symlink
./claudin/setup-claudin.sh
check_not_exists ".claude/scripts/generic/stale-old.sh" "stale symlink should be removed by Phase 2"

# --- Summary ---
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
else
    echo "=== $FAILURES TEST(S) FAILED ==="
    exit 1
fi
