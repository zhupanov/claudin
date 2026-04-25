#!/usr/bin/env bash
# test-fix-issue-step-order.sh — Regression harness pinning the
# /fix-issue Step 1 = lock, Step 2 = setup ordering established
# by closes #445 (fetch → lock → setup reorder, shipped in PR #468).
#
# Asserts that skills/fix-issue/SKILL.md carries the load-bearing
# literals the new step ordering depends on. The skill is prose;
# this harness is a CI guard against accidental reversion of the
# reorder or stale renumbering.
#
# Nine assertions against skills/fix-issue/SKILL.md:
#   (1) Step Name Registry contains "| 1 | lock |" row.
#   (2) Step Name Registry contains "| 2 | setup |" row.
#   (3) Section heading "## Step 1 — Lock Issue" present.
#   (4) Section heading "## Step 2 — Setup" present.
#   (5) Anti-pattern #1 contains "treat Step 1 as structural".
#   (6) Lock success breadcrumb literal "✅ 1: lock" present.
#   (7) Lock failure breadcrumb literal "⚠ 1: lock" present.
#   (8) No stale "✅ 2: lock" breadcrumb remains.
#   (9) No stale "⚠ 2: lock" breadcrumb remains.
#
# Wired into `make lint` via the `test-fix-issue-step-order` target.
# Referenced in agent-lint.toml's exclude list (Makefile-only harness pattern).
#
# Run manually:
#   bash skills/fix-issue/scripts/test-fix-issue-step-order.sh
#
# Exits 0 on success, 1 on the first failed assertion.

# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SKILL_MD="$REPO_ROOT/skills/fix-issue/SKILL.md"

if [[ ! -f "$SKILL_MD" ]]; then
    echo "FAIL: SKILL.md not found at $SKILL_MD" >&2
    exit 1
fi

fail=0

assert_contains() {
    local pattern="$1"
    local description="$2"
    if ! grep -qF -- "$pattern" "$SKILL_MD"; then
        echo "FAIL: $description (pattern not found: $pattern)" >&2
        fail=1
    fi
}

assert_not_contains() {
    local pattern="$1"
    local description="$2"
    if grep -qF -- "$pattern" "$SKILL_MD"; then
        echo "FAIL: $description (pattern unexpectedly found: $pattern)" >&2
        fail=1
    fi
}

# (1)-(2) Step Name Registry rows
assert_contains '| 1 | lock |' '(1) Step Name Registry has "1 | lock"'
assert_contains '| 2 | setup |' '(2) Step Name Registry has "2 | setup"'

# (3)-(4) Section headings
assert_contains '## Step 1 — Lock Issue' '(3) section "Step 1 — Lock Issue" present'
assert_contains '## Step 2 — Setup' '(4) section "Step 2 — Setup" present'

# (5) Anti-pattern #1 wording
assert_contains 'treat Step 1 as structural' '(5) anti-pattern #1 says "treat Step 1 as structural"'

# (6)-(7) Lock breadcrumb literals
assert_contains '✅ 1: lock' '(6) lock success breadcrumb uses "1: lock"'
assert_contains '⚠ 1: lock' '(7) lock failure breadcrumb uses "1: lock"'

# (8)-(9) No stale "2: lock" breadcrumbs
assert_not_contains '✅ 2: lock' '(8) no stale "✅ 2: lock" breadcrumb'
assert_not_contains '⚠ 2: lock' '(9) no stale "⚠ 2: lock" breadcrumb'

if [[ $fail -ne 0 ]]; then
    echo "test-fix-issue-step-order: FAILED" >&2
    exit 1
fi

echo "test-fix-issue-step-order: 9 assertions passed."
