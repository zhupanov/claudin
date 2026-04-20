#!/usr/bin/env bash
# test-post-scaffold-hints.sh — Regression harness for
# skills/create-skill/scripts/post-scaffold-hints.sh.
#
# Black-box contract test. Each case invokes the hints script with controlled
# --target-dir and --plugin flags and asserts on exit code plus the presence
# (or absence) of specific literal strings in stdout. The harness does NOT
# assert exact full-text equality so that future additions to the common
# reminder block (e.g. new "Next steps:" bullets) do not force a test churn —
# instead, it asserts on the contract-critical tokens: the scaffolded-path
# line, the plugin-dev block, the dual Skill permission lines, the Bash
# permission line, and the README-subsection cross-reference.
#
# Usage:
#   bash scripts/test-post-scaffold-hints.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed (first failure listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HINTS="$REPO_ROOT/skills/create-skill/scripts/post-scaffold-hints.sh"

if [[ ! -x "$HINTS" ]]; then
    echo "ERROR: hints script not found or not executable: $HINTS" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing '$needle')")
        echo "  FAIL: $label (missing '$needle')" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (leaked '$needle')")
        echo "  FAIL: $label (leaked '$needle')" >&2
    fi
}

assert_count_eq() {
    local haystack="$1" needle="$2" expected="$3" label="$4"
    local actual
    actual=$(printf '%s\n' "$haystack" | grep -Fc -- "$needle" || true)
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (count=$expected)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected count=$expected, got $actual)")
        echo "  FAIL: $label (expected count=$expected, got $actual)" >&2
    fi
}

echo "=== Section 1: --plugin false branch ==="

out=$("$HINTS" --target-dir "/tmp/smoke/foo" --plugin false)

# Common reminder block MUST be present.
assert_contains "$out" "Scaffolded: /tmp/smoke/foo/SKILL.md" "scaffolded-path line appears"
assert_contains "$out" "Next steps:" "Next steps header appears"

# Plugin-dev block MUST be absent.
assert_not_contains "$out" "Plugin-dev reminders:" "plugin-dev block absent when --plugin false"
assert_not_contains "$out" "Skill(foo)" "bare Skill line absent when --plugin false"
assert_not_contains "$out" "Skill(larch:foo)" "qualified Skill line absent when --plugin false"

echo "=== Section 2: --plugin true branch, NAME=foo ==="

out=$("$HINTS" --target-dir "/tmp/smoke/foo" --plugin true)

# Common reminder block still present.
assert_contains "$out" "Scaffolded: /tmp/smoke/foo/SKILL.md" "scaffolded-path line appears"

# Plugin-dev block present.
assert_contains "$out" "Plugin-dev reminders:" "plugin-dev header appears"
assert_contains "$out" "/foo" "README row reminder references /foo"

# Dual Skill permission lines present exactly once each.
assert_count_eq "$out" '"Skill(foo)"' 1 "bare Skill(foo) appears exactly once"
assert_count_eq "$out" '"Skill(larch:foo)"' 1 "qualified Skill(larch:foo) appears exactly once"

# Bash permission line present. The script escapes \$PWD so the emitted token
# is a literal '$PWD' regardless of the caller's cwd. The literal '$PWD'
# inside the needle below is intentional (shellcheck SC2016 disabled).
# shellcheck disable=SC2016
assert_contains "$out" '"Bash($PWD/skills/foo/scripts/*)"' "Bash permission line present with literal \$PWD token"

# README cross-reference present.
assert_contains "$out" "Strict-permissions consumers" "README subsection cross-reference present"

# ASCII-ordering instruction mentions sort -u (not a "bare first" rule).
assert_contains "$out" "sort -u" "sort -u instruction present"
assert_not_contains "$out" "bare form first" "no stale bare-first ordering rule"

echo "=== Section 3: --plugin true, NAME=loop-review (ASCII edge case) ==="

# NAME starting with 'l' is the edge case where Skill(larch:NAME) sorts
# BEFORE Skill(NAME) in strict ASCII order. The hints script itself just
# emits both lines — the sort-and-interleave is a human step. This case
# confirms the two lines are still both emitted verbatim.

out=$("$HINTS" --target-dir "/tmp/smoke/loop-review" --plugin true)
assert_count_eq "$out" '"Skill(loop-review)"' 1 "bare Skill(loop-review) appears for edge-case name"
assert_count_eq "$out" '"Skill(larch:loop-review)"' 1 "qualified Skill(larch:loop-review) appears for edge-case name"

echo "=== Section 4: --target-dir required flag ==="

# Missing --target-dir must exit non-zero and print ERROR= to stderr.
set +e
out=$("$HINTS" --plugin true 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    PASS=$((PASS + 1))
    echo "  ok: missing --target-dir exits non-zero"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("missing --target-dir exits non-zero (got rc=$rc)")
    echo "  FAIL: missing --target-dir exits non-zero (got rc=$rc)" >&2
fi
assert_contains "$out" "ERROR=Missing --target-dir" "missing --target-dir prints ERROR= line"

echo "=== Section 5: unknown flag ==="

set +e
out=$("$HINTS" --target-dir "/tmp/smoke/foo" --plugin true --bogus-flag x 2>&1)
rc=$?
set -e
if [[ $rc -ne 0 ]]; then
    PASS=$((PASS + 1))
    echo "  ok: unknown flag exits non-zero"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("unknown flag exits non-zero (got rc=$rc)")
    echo "  FAIL: unknown flag exits non-zero (got rc=$rc)" >&2
fi
assert_contains "$out" "ERROR=Unknown argument:" "unknown flag prints ERROR= line"

echo ""
echo "=== Summary ==="
echo "PASS: $PASS"
echo "FAIL: $FAIL"

if [[ $FAIL -gt 0 ]]; then
    echo ""
    echo "Failed assertions:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi

exit 0
