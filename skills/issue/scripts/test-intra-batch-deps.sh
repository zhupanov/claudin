#!/usr/bin/env bash
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

assert_absent() {
    local label="$1" needle="$2"
    if grep -qF "$needle" "$SKILL"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label — unexpected '$needle' found in SKILL.md" >&2
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    fi
}

echo "=== test-intra-batch-deps ==="

assert_present "step4e-redirect-to-step5" \
    "If \`N_NON_MALFORMED >= 2\`, proceed to Step 5"

assert_present "step5-gate-n-non-malformed" \
    "N_NON_MALFORMED >= 2"

assert_present "step5-conditional-fetch-skip" \
    "skip \`fetch-issue-details.sh\` entirely"

assert_present "step5-empty-candidates-verdict" \
    "Empty-CANDIDATES + multi-item path"

assert_absent "step4e-old-unconditional-shortcircuit" \
    "short-circuits cleanly via its existing"

echo "---"
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    echo "FAILED: test-intra-batch-deps" >&2
    exit 1
fi
echo "PASSED: test-intra-batch-deps"
