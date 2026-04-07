#!/usr/bin/env bash
# test-setup-larch.sh — Integration test for setup-larch.sh
#
# Creates a temporary fake client repo with larch as a subdirectory,
# runs setup-larch.sh, and verifies symlinks are created correctly
# for the larch/ subdirectory structure under scripts/generic/ and
# skills/shared/.
#
# Exit codes:
#   0 — all tests passed
#   1 — one or more tests failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LARCH_DIR="$(cd "$SCRIPT_DIR/.." && pwd -P)"

# Create a temporary directory for the fake client repo
TEST_REPO_DIR="$(mktemp -d)"
trap 'rm -rf "$TEST_REPO_DIR"' EXIT

echo "=== Setting up fake client repo in $TEST_REPO_DIR ==="

# Initialize a git repo
cd "$TEST_REPO_DIR"
git init -q
git config user.email "test@larch.test"
git config user.name "Larch Test"
git commit --allow-empty -m "init" -q

# Copy larch into the fake client repo as a subdirectory
# (not a real submodule, but setup-larch.sh only needs the directory structure)
cp -R "$LARCH_DIR" "$TEST_REPO_DIR/larch"

# Create settings.local.json fixture in the source so the settings*.json skip
# is exercised during Phase 1. In CI this file is gitignored and absent from
# the cp -R copy, so we create it explicitly to test the glob skip.
if [[ ! -f "$TEST_REPO_DIR/larch/.claude/settings.local.json" ]]; then
    echo '{}' > "$TEST_REPO_DIR/larch/.claude/settings.local.json"
fi

# Run setup-larch.sh from the repo root
echo ""
echo "=== Running setup-larch.sh ==="
./larch/setup-larch.sh

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
for skill_dir in "$TEST_REPO_DIR"/larch/.claude/skills/*/; do
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

# Verify setup-larch.sh does not conflict with a pre-existing relevant-checks directory
echo "--- relevant-checks conflict test ---"
mkdir -p ".claude/skills/relevant-checks"
echo "# Client-specific checks" > ".claude/skills/relevant-checks/SKILL.md"
# Re-run — should succeed without error despite the pre-existing directory
rc=0
./larch/setup-larch.sh > /dev/null 2>&1 || rc=$?
if [[ $rc -eq 0 ]]; then
    echo "  PASS: setup-larch.sh succeeds with pre-existing relevant-checks"
else
    echo "  FAIL: setup-larch.sh exited $rc with pre-existing relevant-checks"
    FAILURES=$((FAILURES + 1))
fi
# Verify the client's relevant-checks was not replaced
if [[ ! -L ".claude/skills/relevant-checks" && -f ".claude/skills/relevant-checks/SKILL.md" ]]; then
    echo "  PASS: client's relevant-checks preserved (not a symlink)"
else
    echo "  FAIL: client's relevant-checks was replaced or symlinked"
    FAILURES=$((FAILURES + 1))
fi

# Scripts under scripts/generic/larch/ should be file-level symlinks
echo "--- Scripts (file-level symlinks under scripts/generic/larch/) ---"
script_count=0
for script in "$TEST_REPO_DIR"/larch/.claude/scripts/generic/larch/*.sh; do
    script_name="$(basename "$script")"
    check_symlink ".claude/scripts/generic/larch/$script_name" "script: $script_name"
    script_count=$((script_count + 1))
done
echo "  (checked $script_count scripts)"

# Shared .md files under skills/shared/larch/ should be file-level symlinks
echo "--- Shared .md files (file-level symlinks under skills/shared/larch/) ---"
md_count=0
for md_file in "$TEST_REPO_DIR"/larch/.claude/skills/shared/larch/*.md; do
    md_name="$(basename "$md_file")"
    check_symlink ".claude/skills/shared/larch/$md_name" "shared md: $md_name"
    md_count=$((md_count + 1))
done
echo "  (checked $md_count shared .md files)"

# Agent files should be file-level symlinks
echo "--- Agent files ---"
for agent in "$TEST_REPO_DIR"/larch/.claude/agents/*.md; do
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
echo "=== Re-running setup-larch.sh (idempotency test) ==="
./larch/setup-larch.sh

echo ""
echo "=== Verifying symlinks still correct after re-run ==="
rerun_ok=true
for script in "$TEST_REPO_DIR"/larch/.claude/scripts/generic/larch/*.sh; do
    script_name="$(basename "$script")"
    if [[ ! -L ".claude/scripts/generic/larch/$script_name" ]] || [[ ! -e ".claude/scripts/generic/larch/$script_name" ]]; then
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
# Create a fake stale symlink simulating a pre-migration path pointing into larch
mkdir -p .claude/scripts/generic
ln -s "../../../larch/.claude/scripts/generic/nonexistent-old-script.sh" ".claude/scripts/generic/stale-old.sh"

# --- Phase 2 migration scenario: stale legacy-ns-namespace symlinks ---
# Simulate a client repo that was upgraded with an earlier PR (which populated
# both legacy-ns/ and larch/ subtrees) and is now being upgraded past a later
# PR (which deleted the legacy-ns/ subtree). The client carries over orphan
# legacy-ns symlinks whose targets no longer exist. Phase 2 must remove them.
mkdir -p .claude/scripts/generic/legacy-ns .claude/skills/shared/legacy-ns
ln -s "../../../../larch/.claude/scripts/generic/legacy-ns/nonexistent-post-migration.sh" ".claude/scripts/generic/legacy-ns/stale-migration.sh"
ln -s "../../../../larch/.claude/skills/shared/legacy-ns/nonexistent-post-migration.md" ".claude/skills/shared/legacy-ns/stale-migration.md"

# Re-run setup-larch.sh — Phase 2 should remove all stale symlinks
./larch/setup-larch.sh
check_not_exists ".claude/scripts/generic/stale-old.sh" "stale symlink should be removed by Phase 2"
check_not_exists ".claude/scripts/generic/legacy-ns/stale-migration.sh" "stale legacy-ns-namespace script symlink should be removed by Phase 2"
check_not_exists ".claude/skills/shared/legacy-ns/stale-migration.md" "stale legacy-ns-namespace shared-doc symlink should be removed by Phase 2"

# --- Summary ---
echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo "=== ALL TESTS PASSED ==="
    exit 0
else
    echo "=== $FAILURES TEST(S) FAILED ==="
    exit 1
fi
