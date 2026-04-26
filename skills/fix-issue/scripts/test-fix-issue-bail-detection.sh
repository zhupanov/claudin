#!/usr/bin/env bash
# test-fix-issue-bail-detection.sh — Regression harness for /fix-issue Step 5a
# bail-detection prose (Phase 4 of umbrella #348; renumbered to Step 5a from
# Step 6a by the fold-find-and-lock refactor closes #496).
#
# Asserts that skills/fix-issue/SKILL.md Step 5a block contains the load-bearing
# literals the runtime behavior depends on. The skill is prose; this harness is
# a CI guard against accidental removal of pinned strings, not a runtime
# conformance test. Runtime enforcement is the LLM-level orchestration of
# Step 5a per the prose contract.
#
# Eight assertions against the extracted Step 5a block:
#   (a1) SIMPLE bullet forwards "--issue $ISSUE_NUMBER".
#   (a2) HARD bullet forwards "--issue $ISSUE_NUMBER".
#   (a3) SIMPLE bullet forwards "--no-admin-fallback" (issue #559 — branch-protection bypass safety flag).
#   (a4) HARD bullet forwards "--no-admin-fallback" (issue #559 — branch-protection bypass safety flag).
#   (b)  Literal token "IMPLEMENT_BAIL_REASON=adopted-issue-closed" present.
#   (c)  Warning prefix "/implement bailed: issue #" present.
#   (d)  Specific directive "Do NOT call `issue-lifecycle.sh close`" present
#        (skip-Step-6 contract guard). The full phrase — not a bare
#        "Do NOT call" substring — is required because the awk extraction
#        window also includes section 5b, which contains the unrelated
#        sentence "Do NOT call `/implement`"; a bare match would false-pass.
#   (e)  Literal "Skip to Step 8" present (cleanup redirect guard).
#
# Block extraction boundary: "### 5a " (start) through "## Step 6" prefix match
# (end — the real heading is "## Step 6 — Close Issue"; prefix pattern handles it).
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

# Extract the Step 5a block: from "### 5a " up to (but not including) the
# next "## Step 6" heading. awk range using two regexes.
STEP5A_BLOCK=$(awk '
    /^### 5a / { in_block=1 }
    /^## Step 6/ { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP5A_BLOCK" ]]; then
    echo "FAIL: Step 5a block extraction produced empty output." >&2
    echo "  Boundary regexes: '^### 5a ' (start) and '^## Step 6' (end)." >&2
    exit 1
fi

PASS_COUNT=0

# Assertion helper — literal-substring presence check.
# Usage: assert_contains <label> <literal>
assert_contains() {
    local label="$1" literal="$2"
    if grep -qF -- "$literal" <<<"$STEP5A_BLOCK"; then
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
    line=$(grep -F -- "$marker" <<<"$STEP5A_BLOCK" | head -1 || true)
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

# (a3, a4) --no-admin-fallback forwarding — branch-protection bypass safety flag (issue #559).
# Without this guard, a future refactor could silently strip the forward, leaving
# /fix-issue --no-admin-fallback callers exposed to the silent --admin override.
assert_bullet_contains "a3: SIMPLE bullet forwards --no-admin-fallback" '- **SIMPLE**' '--no-admin-fallback'
assert_bullet_contains "a4: HARD bullet forwards --no-admin-fallback"   '- **HARD**'   '--no-admin-fallback'

# (b) Bail-token literal present.
assert_contains "b: IMPLEMENT_BAIL_REASON=adopted-issue-closed literal" 'IMPLEMENT_BAIL_REASON=adopted-issue-closed'

# (c) User-visible warning prefix present.
assert_contains "c: warning prefix '/implement bailed: issue #'" '/implement bailed: issue #'

# (d) Skip-Step-6 directive present — guard against silent re-route back to Step 6.
# The specific phrase "Do NOT call `issue-lifecycle.sh close`" is required; a
# bare "Do NOT call" substring would false-pass on section 5b's unrelated
# "Do NOT call `/implement`" line (the awk window includes 5b up to ## Step 6).
assert_contains "d: 'Do NOT call \`issue-lifecycle.sh close\`' directive (Step-6-skip guard)" 'Do NOT call `issue-lifecycle.sh close`'

# (e) Cleanup redirect present.
assert_contains "e: 'Skip to Step 8' cleanup redirect" 'Skip to Step 8'

echo
echo "All $PASS_COUNT assertions passed."
