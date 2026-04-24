#!/usr/bin/env bash
# test-fix-issue-bail-detection.sh — Regression harness for /fix-issue Step 6a
# bail-detection prose (Phase 4 of umbrella #348).
#
# Asserts that skills/fix-issue/SKILL.md Step 6a block contains the load-bearing
# literals the runtime behavior depends on. The skill is prose; this harness is
# a CI guard against accidental removal of pinned strings, not a runtime
# conformance test. Runtime enforcement is the LLM-level orchestration of
# Step 6a per the prose contract.
#
# Five assertions against the extracted Step 6a block:
#   (a) Two occurrences of "--issue $ISSUE_NUMBER" (SIMPLE + HARD bullets).
#   (b) Literal token "IMPLEMENT_BAIL_REASON=adopted-issue-closed" present.
#   (c) Warning prefix "/implement bailed: issue #" present.
#   (d) Directive fragment "Do NOT call" present (skip-Step-7 contract guard).
#   (e) Literal "Skip to Step 9" present (cleanup redirect guard).
#
# Block extraction boundary: "### 6a " (start) through "## Step 7" prefix match
# (end — the real heading is "## Step 7 — Close Issue"; prefix pattern handles it).
#
# Wired into `make lint` via the `test-fix-issue-bail-detection` target.
# Referenced in agent-lint.toml's exclude list (Makefile-only harness pattern).
#
# Run manually:
#   bash skills/fix-issue/scripts/test-fix-issue-bail-detection.sh
#
# Exits 0 on success, 1 on the first failed assertion.

# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SKILL_MD="$REPO_ROOT/skills/fix-issue/SKILL.md"

if [[ ! -f "$SKILL_MD" ]]; then
    echo "ERROR: SKILL.md not found: $SKILL_MD" >&2
    exit 1
fi

# Extract the Step 6a block: from "### 6a " up to (but not including) the
# next "## Step 7" heading. awk range using two regexes.
STEP6A_BLOCK=$(awk '
    /^### 6a / { in_block=1 }
    /^## Step 7/ { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP6A_BLOCK" ]]; then
    echo "FAIL: Step 6a block extraction produced empty output." >&2
    echo "  Boundary regexes: '^### 6a ' (start) and '^## Step 7' (end)." >&2
    exit 1
fi

PASS_COUNT=0

# Assertion helper — literal-substring presence check.
# Usage: assert_contains <label> <literal>
assert_contains() {
    local label="$1" literal="$2"
    if grep -qF -- "$literal" <<<"$STEP6A_BLOCK"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        echo "  FAIL: $label" >&2
        echo "    missing literal: $literal" >&2
        exit 1
    fi
}

# Assertion helper — a specific bullet line contains a literal.
# Usage: assert_bullet_contains <label> <bullet_marker> <literal>
# <bullet_marker> is matched at line start (e.g., "- **SIMPLE**").
assert_bullet_contains() {
    local label="$1" marker="$2" literal="$3"
    local line
    line=$(grep -F -- "$marker" <<<"$STEP6A_BLOCK" | head -1 || true)
    if [[ -n "$line" && "$line" == *"$literal"* ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        echo "  FAIL: $label" >&2
        if [[ -z "$line" ]]; then
            echo "    bullet not found: $marker" >&2
        else
            echo "    bullet: $line" >&2
            echo "    missing literal: $literal" >&2
        fi
        exit 1
    fi
}

echo "Running test-fix-issue-bail-detection against $SKILL_MD"

# (a) --issue $ISSUE_NUMBER appears in both the SIMPLE and HARD /implement invocation bullets.
assert_bullet_contains "a1: SIMPLE bullet forwards --issue \$ISSUE_NUMBER" '- **SIMPLE**' '--issue $ISSUE_NUMBER'
assert_bullet_contains "a2: HARD bullet forwards --issue \$ISSUE_NUMBER"   '- **HARD**'   '--issue $ISSUE_NUMBER'

# (b) Bail-token literal present.
assert_contains "b: IMPLEMENT_BAIL_REASON=adopted-issue-closed literal" 'IMPLEMENT_BAIL_REASON=adopted-issue-closed'

# (c) User-visible warning prefix present.
assert_contains "c: warning prefix '/implement bailed: issue #'" '/implement bailed: issue #'

# (d) Skip-Step-7 directive present — guard against silent re-route back to Step 7.
assert_contains "d: 'Do NOT call' directive (Step-7-skip guard)" 'Do NOT call'

# (e) Cleanup redirect present.
assert_contains "e: 'Skip to Step 9' cleanup redirect" 'Skip to Step 9'

echo
echo "All $PASS_COUNT assertions passed."
