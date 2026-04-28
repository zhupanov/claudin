#!/usr/bin/env bash
# test-fix-issue-step-order.sh — Regression harness pinning the
# /fix-issue Step 0 = find & lock, Step 1 = setup ordering established
# by the fold-find-and-lock refactor (closes #496).
#
# Asserts that skills/fix-issue/SKILL.md carries the load-bearing
# literals the new step ordering depends on. The skill is prose;
# this harness is a CI guard against accidental reversion of the
# fold or stale renumbering.
#
# Thirteen assertions against skills/fix-issue/SKILL.md (ten textual literal
# pins + three operational ordering pins via awk-scoped block extraction):
#   (1) Step Name Registry contains "| 0 | find & lock |" row.
#   (2) Step Name Registry contains "| 1 | setup |" row.
#   (3) Section heading "## Step 0 — Find and Lock" present.
#   (4) Section heading "## Step 1 — Setup" present.
#   (5) Anti-pattern #1 contains "treat Step 0 as structural".
#   (6) Find & lock success breadcrumb literal "✅ 0: find & lock" present.
#   (7) Find & lock failure breadcrumb literal "⚠ 0: find & lock" present.
#   (8) No stale "| 1 | lock |" step-name-registry row remains.
#   (9) No stale "| 2 | lock |" step-name-registry row remains.
#  (10) Step 0 (Find and Lock) block contains the find-lock-issue.sh invocation.
#  (11) Step 0 block does NOT contain `session-setup.sh` (operational ordering).
#  (12) Step 1 (Setup) block contains the session-setup.sh invocation.
#  (13) File-preamble Anti-halt rule is broadened to cover Bash tool calls
#       in addition to Skill calls (closes #530). The literal phrase
#       "child Bash tool calls into the canonical" is the load-bearing
#       broadening token — its presence proves the rule is no longer
#       Skill-only. The check is scoped to the preamble (start of file
#       through the first `##` heading) to enforce the locational claim,
#       not just substring presence anywhere in the file. Without this
#       broadening, the Step 6 → Step 7 → Step 8 Skill-free terminal
#       chain (and the parallel close/announce/cleanup tails in Step 3's
#       not-material closure flow and Step 6b → Step 7b → Step 8 NON_PR
#       close path) sits outside the rule's scope, leaving the
#       orchestrator vulnerable to the post-Bash-call halt observed in
#       production prior to #530.
#
# Block extraction boundaries (assertions 10-12): `## Step 0 — Find and Lock`
# (start, exact line match) through `## Step 1 — Setup` (end, exact line
# match) for Step 0; `## Step 1 — Setup` (start) through `## Step 2` (end,
# prefix match — heading is "## Step 2 — Read Issue Details") for Step 1.
# Block-scoped assertions catch the regression a future edit could otherwise
# slip through: keeping headings/registry/breadcrumbs intact while moving
# `session-setup.sh` back into the find-lock block.
#
# Wired into `make lint` via the `test-fix-issue-step-order` target.
# Referenced in agent-lint.toml's exclude list (Makefile-only harness pattern).
#
# Run manually:
#   bash skills/fix-issue/scripts/test-fix-issue-step-order.sh
#
# Exits 0 when all assertions pass; exits 1 after running every assertion
# if any failed (accumulator pattern, so all failures are reported).

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
assert_contains '| 0 | find & lock |' '(1) Step Name Registry has "0 | find & lock"'
assert_contains '| 1 | setup |' '(2) Step Name Registry has "1 | setup"'

# (3)-(4) Section headings
assert_contains '## Step 0 — Find and Lock' '(3) section "Step 0 — Find and Lock" present'
assert_contains '## Step 1 — Setup' '(4) section "Step 1 — Setup" present'

# (5) Anti-pattern #1 wording
assert_contains 'treat Step 0 as structural' '(5) anti-pattern #1 says "treat Step 0 as structural"'

# (6)-(7) Find & lock breadcrumb literals
assert_contains '✅ 0: find & lock' '(6) find & lock success breadcrumb uses "0: find & lock"'
assert_contains '⚠ 0: find & lock' '(7) find & lock failure breadcrumb uses "0: find & lock"'

# (8)-(9) No stale "lock" step-name-registry rows from the pre-fold structure
assert_not_contains '| 1 | lock |' '(8) no stale "| 1 | lock |" registry row'
assert_not_contains '| 2 | lock |' '(9) no stale "| 2 | lock |" registry row'

# (10)-(12) Operational-ordering assertions on awk-scoped step blocks.
# These guard against a future edit that keeps the headings/registry/
# breadcrumbs intact while moving session-setup.sh back into Step 0's body.
STEP0_BLOCK=$(awk '
    /^## Step 0 — Find and Lock/ { in_block=1; next }
    /^## Step 1 — Setup/         { in_block=0 }
    in_block { print }
' "$SKILL_MD")

STEP1_BLOCK=$(awk '
    /^## Step 1 — Setup/ { in_block=1; next }
    /^## Step 2/         { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP0_BLOCK" ]]; then
    echo "FAIL: Step 0 block extraction produced empty output (heading boundary missing?)" >&2
    fail=1
fi
if [[ -z "$STEP1_BLOCK" ]]; then
    echo "FAIL: Step 1 block extraction produced empty output (heading boundary missing?)" >&2
    fail=1
fi

# (10) Step 0 block contains the find-lock-issue.sh invocation.
if ! grep -qF -- 'find-lock-issue.sh' <<<"$STEP0_BLOCK"; then
    echo 'FAIL: (10) Step 0 block does not contain `find-lock-issue.sh`' >&2
    fail=1
fi

# (11) Step 0 block does NOT contain session-setup.sh (the regression guard).
if grep -qF -- 'session-setup.sh' <<<"$STEP0_BLOCK"; then
    echo 'FAIL: (11) Step 0 block unexpectedly contains `session-setup.sh` (operational ordering broken)' >&2
    fail=1
fi

# (12) Step 1 block contains the session-setup.sh invocation.
if ! grep -qF -- 'session-setup.sh --prefix claude-fix-issue --skip-branch-check' <<<"$STEP1_BLOCK"; then
    echo 'FAIL: (12) Step 1 block does not contain `session-setup.sh --prefix claude-fix-issue --skip-branch-check`' >&2
    fail=1
fi

# (13) Anti-halt rule broadened to cover Bash tool calls (closes #530).
# Scope to the file preamble — everything from the start of the file up to
# (but not including) the first `##` heading. This rules out a future edit
# that moves the broadening token to a deep-in-file location while still
# satisfying a whole-file substring match, and matches the locational claim
# made in this harness's sibling .md contract. The exit-then-print rule
# order ensures the heading line itself is excluded — `exit` halts the
# awk pass before the `{ print }` rule fires for that record, regardless
# of whether the heading happens to land on line 1 (frontmatter-less
# files) or later.
# Diagnose three distinct boundary failures separately so a future regression
# points at the actual cause:
#   - no `## ` heading anywhere in the file: preamble has no end boundary;
#     awk would silently fall back to whole-file output, defeating the
#     locational claim.
#   - first `## ` heading is on line 1: preamble is empty (file starts with
#     a section heading, no preamble exists).
#   - heading exists somewhere past line 1, preamble extracted but missing
#     the broadening token.
if ! grep -qE '^## ' "$SKILL_MD"; then
    echo 'FAIL: (13) no `## ` heading found anywhere in SKILL.md — preamble end boundary missing' >&2
    fail=1
else
    PREAMBLE_BLOCK=$(awk '
        /^## / { exit }
        { print }
    ' "$SKILL_MD")
    if [[ -z "$PREAMBLE_BLOCK" ]]; then
        echo 'FAIL: (13) preamble is empty — SKILL.md begins with a `## ` heading; the anti-halt rule must appear before the first section heading' >&2
        fail=1
    elif ! grep -qF -- 'child Bash tool calls into the canonical' <<<"$PREAMBLE_BLOCK"; then
        echo 'FAIL: (13) anti-halt rule in file preamble does not cover Bash tool calls (missing literal: child Bash tool calls into the canonical)' >&2
        fail=1
    fi
fi

if [[ $fail -ne 0 ]]; then
    echo "test-fix-issue-step-order: FAILED" >&2
    exit 1
fi

echo "test-fix-issue-step-order: 13 assertions passed."
