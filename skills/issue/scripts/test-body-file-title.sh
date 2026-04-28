#!/usr/bin/env bash
# test-body-file-title.sh — Structural harness pinning /issue --body-file +
# trailing title semantics in SKILL.md. Wired into `make lint` via the
# `test-body-file-title` target. Run manually:
#
#   bash skills/issue/scripts/test-body-file-title.sh
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
SKILL="$SCRIPT_DIR/../SKILL.md"

if [[ ! -f "$SKILL" ]]; then
    echo "ERROR: SKILL.md not found: $SKILL" >&2
    exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

assert_present() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$SKILL"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label — expected '$needle' in SKILL.md" >&2
    fi
}

echo "=== test-body-file-title ==="

# Two-source semantics: --body-file bullet describes trailing arg as explicit title
assert_present "body-file-trailing-arg-explicit-title" \
    "trailing arg is the explicit title"

# EXPLICIT_TITLE variable in after-flag-stripping logic
assert_present "explicit-title-variable" \
    "EXPLICIT_TITLE"

# Step 3 single-mode two-branch rule
assert_present "step3-explicit-title-branch" \
    "if \`EXPLICIT_TITLE\` is set"

# Backward compat: derive-from-first-line path still present
assert_present "derive-from-description" \
    "derived from \`DESCRIPTION\`"

echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "FAILED: test-body-file-title" >&2
    exit 1
fi
echo "PASSED: test-body-file-title"
