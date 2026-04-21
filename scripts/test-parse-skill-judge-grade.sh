#!/usr/bin/env bash
# test-parse-skill-judge-grade.sh — Regression harness for
# scripts/parse-skill-judge-grade.sh.
#
# Asserts the parser's KV stdout contract across the documented
# PARSE_STATUS taxonomy (ok / missing_table / missing_file / bad_row /
# empty_file) and the per-dimension threshold arithmetic (D1..D8 with
# integer max=20 / max=15 / max=10 branches).
#
# Wired into `make lint` via the test-parse-skill-judge-grade target.
# Excluded from agent-lint via agent-lint.toml because agent-lint's
# dead-script rule does not follow Makefile-only references.
#
# Edits to scripts/parse-skill-judge-grade.sh must keep this harness
# passing.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
PARSER="$REPO_ROOT/scripts/parse-skill-judge-grade.sh"

if [[ ! -x "$PARSER" ]]; then
  echo "FAIL: parser not executable at $PARSER" >&2
  exit 1
fi

TMPROOT="$(mktemp -d -t parse-skill-judge-grade.XXXXXX)"
trap 'rm -rf "$TMPROOT"' EXIT

PASS_COUNT=0
FAIL_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

assert_kv() {
  # $1 = output (multi-line), $2 = key, $3 = expected value, $4 = label
  local output="$1" key="$2" expected="$3" label="$4"
  local actual
  actual="$(printf '%s\n' "$output" | LC_ALL=C grep -E "^${key}=" || true)"
  actual="${actual#"${key}"=}"
  if [[ "$actual" == "$expected" ]]; then
    pass "$label: ${key}=${actual}"
  else
    fail "$label: expected ${key}=${expected}, got ${key}=${actual}"
  fi
}

# Helper: write a fixture file with full table at given per-dim scores.
# Args: outfile D1 D2 D3 D4 D5 D6 D7 D8
write_full_table() {
  local outfile="$1"
  local d1="$2" d2="$3" d3="$4" d4="$5" d5="$6" d6="$7" d7="$8" d8="$9"
  cat > "$outfile" <<EOF
# Skill Evaluation Report: Test Skill

## Summary
- **Total Score**: $((d1+d2+d3+d4+d5+d6+d7+d8))/120

## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | $d1 | 20 | |
| D2: Mindset vs Mechanics | $d2 | 15 | |
| D3: Anti-Pattern Quality | $d3 | 15 | |
| D4: Specification Compliance | $d4 | 15 | |
| D5: Progressive Disclosure | $d5 | 15 | |
| D6: Freedom Calibration | $d6 | 15 | |
| D7: Pattern Recognition | $d7 | 10 | |
| D8: Practical Usability | $d8 | 15 | |

## Critical Issues
None.
EOF
}

echo "--- Case (a): all-A at exact thresholds ---"
F1="$TMPROOT/all-a.md"
write_full_table "$F1" 18 14 14 14 14 14 9 14
OUT="$($PARSER "$F1")"
assert_kv "$OUT" "PARSE_STATUS" "ok" "case-a"
assert_kv "$OUT" "GRADE_A" "true" "case-a"
assert_kv "$OUT" "NON_A_DIMS" "" "case-a"
assert_kv "$OUT" "TOTAL_NUM" "$((18+14+14+14+14+14+9+14))" "case-a"
assert_kv "$OUT" "TOTAL_DEN" "120" "case-a"
assert_kv "$OUT" "D1_NUM" "18" "case-a"
assert_kv "$OUT" "D7_DEN" "10" "case-a"

echo ""
echo "--- Case (b): D2 short by 1 ---"
F2="$TMPROOT/d2-short.md"
write_full_table "$F2" 18 13 14 14 14 14 9 14
OUT="$($PARSER "$F2")"
assert_kv "$OUT" "PARSE_STATUS" "ok" "case-b"
assert_kv "$OUT" "GRADE_A" "false" "case-b"
assert_kv "$OUT" "NON_A_DIMS" "D2" "case-b"

echo ""
echo "--- Case (c): multi-dim shortfall (D2, D5, D7) ---"
F3="$TMPROOT/multi-short.md"
write_full_table "$F3" 18 10 14 14 12 14 7 14
OUT="$($PARSER "$F3")"
assert_kv "$OUT" "PARSE_STATUS" "ok" "case-c"
assert_kv "$OUT" "GRADE_A" "false" "case-c"
assert_kv "$OUT" "NON_A_DIMS" "D2,D5,D7" "case-c"

echo ""
echo "--- Case (d): missing '## Dimension Scores' heading ---"
F4="$TMPROOT/no-heading.md"
cat > "$F4" <<'EOF'
# Some Report

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | 18 | 20 | |
EOF
OUT="$($PARSER "$F4")"
assert_kv "$OUT" "PARSE_STATUS" "missing_table" "case-d"
assert_kv "$OUT" "GRADE_A" "false" "case-d"

echo ""
echo "--- Case (e): 7 rows instead of 8 ---"
F5="$TMPROOT/seven-rows.md"
cat > "$F5" <<'EOF'
## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | 18 | 20 | |
| D2: Mindset vs Mechanics | 14 | 15 | |
| D3: Anti-Pattern Quality | 14 | 15 | |
| D4: Specification Compliance | 14 | 15 | |
| D5: Progressive Disclosure | 14 | 15 | |
| D6: Freedom Calibration | 14 | 15 | |
| D7: Pattern Recognition | 9 | 10 | |
EOF
OUT="$($PARSER "$F5")"
assert_kv "$OUT" "PARSE_STATUS" "bad_row" "case-e"
assert_kv "$OUT" "GRADE_A" "false" "case-e"

echo ""
echo "--- Case (f): N/A score cell ---"
F6="$TMPROOT/na-cell.md"
cat > "$F6" <<'EOF'
## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | 18 | 20 | |
| D2: Mindset vs Mechanics | N/A | 15 | |
| D3: Anti-Pattern Quality | 14 | 15 | |
| D4: Specification Compliance | 14 | 15 | |
| D5: Progressive Disclosure | 14 | 15 | |
| D6: Freedom Calibration | 14 | 15 | |
| D7: Pattern Recognition | 9 | 10 | |
| D8: Practical Usability | 14 | 15 | |
EOF
OUT="$($PARSER "$F6")"
assert_kv "$OUT" "PARSE_STATUS" "bad_row" "case-f"
assert_kv "$OUT" "GRADE_A" "false" "case-f"

echo ""
echo "--- Case (g): empty file ---"
F7="$TMPROOT/empty.md"
: > "$F7"
OUT="$($PARSER "$F7")"
assert_kv "$OUT" "PARSE_STATUS" "empty_file" "case-g"
assert_kv "$OUT" "GRADE_A" "false" "case-g"

echo ""
echo "--- Case (h): missing file arg (exit 1) ---"
set +e
"$PARSER" 2>/dev/null
RC=$?
set -e
if [[ "$RC" -eq 1 ]]; then
  pass "case-h: missing arg → exit 1"
else
  fail "case-h: expected exit 1, got $RC"
fi

echo ""
echo "--- Case (i): missing input file path ---"
OUT="$("$PARSER" "$TMPROOT/does-not-exist.md")"
assert_kv "$OUT" "PARSE_STATUS" "missing_file" "case-i"
assert_kv "$OUT" "GRADE_A" "false" "case-i"

echo ""
echo "--- Case (j): D1=17/20 below threshold (max=20 arithmetic branch) ---"
FJ="$TMPROOT/d1-short.md"
write_full_table "$FJ" 17 14 14 14 14 14 9 14
OUT="$($PARSER "$FJ")"
assert_kv "$OUT" "PARSE_STATUS" "ok" "case-j"
assert_kv "$OUT" "GRADE_A" "false" "case-j"
assert_kv "$OUT" "NON_A_DIMS" "D1" "case-j"
assert_kv "$OUT" "D1_NUM" "17" "case-j"
assert_kv "$OUT" "D1_DEN" "20" "case-j"

echo ""
echo "--- Case (k): full /skill-judge Step 5 report template (verbatim layout) ---"
FK="$TMPROOT/full-template.md"
cat > "$FK" <<'EOF'
# Skill Evaluation Report: Example Skill

## Summary
- **Total Score**: 111/120 (92%)
- **Grade**: A
- **Pattern**: Process
- **Knowledge Ratio**: E:A:R = 75:20:5
- **Verdict**: Excellent — production-ready expert Skill

## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | 19 | 20 | dense expert delta |
| D2: Mindset vs Mechanics | 14 | 15 | strong thinking patterns |
| D3: Anti-Pattern Quality | 15 | 15 | excellent NEVER list |
| D4: Specification Compliance | 14 | 15 | description clear |
| D5: Progressive Disclosure | 14 | 15 | good layering |
| D6: Freedom Calibration | 14 | 15 | matches task fragility |
| D7: Pattern Recognition | 10 | 10 | clear Process pattern |
| D8: Practical Usability | 14 | 15 | covers most edge cases |

## Critical Issues
None.

## Top 3 Improvements
1. ...
EOF
OUT="$($PARSER "$FK")"
assert_kv "$OUT" "PARSE_STATUS" "ok" "case-k"
assert_kv "$OUT" "GRADE_A" "true" "case-k"
assert_kv "$OUT" "NON_A_DIMS" "" "case-k"
assert_kv "$OUT" "TOTAL_NUM" "114" "case-k"
assert_kv "$OUT" "OVERALL_GRADE" "A" "case-k"

echo ""
echo "--- Case (l): missing_table heading present but empty section (no pipe rows) ---"
FL="$TMPROOT/empty-section.md"
cat > "$FL" <<'EOF'
## Dimension Scores

(scoring deferred — see follow-up)

## Next Section

| not | a | data | row |
EOF
OUT="$($PARSER "$FL")"
assert_kv "$OUT" "PARSE_STATUS" "missing_table" "case-l"
assert_kv "$OUT" "GRADE_A" "false" "case-l"
# Defensive: missing_table must NOT be rewritten to bad_row by F8 fix.
if printf '%s\n' "$OUT" | LC_ALL=C grep -q '^PARSE_STATUS=bad_row$'; then
  fail "case-l: PARSE_STATUS was rewritten to bad_row (F8 defensive rule mis-scoped)"
fi

echo ""
echo "--- Case (m): wrong row order (D1 row labels D2) ---"
FM="$TMPROOT/wrong-order.md"
cat > "$FM" <<'EOF'
## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D2: Mindset | 14 | 15 | |
| D1: Knowledge Delta | 18 | 20 | |
| D3: Anti-Pattern Quality | 14 | 15 | |
| D4: Specification Compliance | 14 | 15 | |
| D5: Progressive Disclosure | 14 | 15 | |
| D6: Freedom Calibration | 14 | 15 | |
| D7: Pattern Recognition | 9 | 10 | |
| D8: Practical Usability | 14 | 15 | |
EOF
OUT="$($PARSER "$FM")"
assert_kv "$OUT" "PARSE_STATUS" "bad_row" "case-m"
assert_kv "$OUT" "GRADE_A" "false" "case-m"

echo ""
echo "--- Case (n): wrong max for D1 (max=15 instead of 20) ---"
FN="$TMPROOT/wrong-max.md"
cat > "$FN" <<'EOF'
## Dimension Scores

| Dimension | Score | Max | Notes |
|-----------|-------|-----|-------|
| D1: Knowledge Delta | 14 | 15 | |
| D2: Mindset | 14 | 15 | |
| D3: Anti-Pattern Quality | 14 | 15 | |
| D4: Specification Compliance | 14 | 15 | |
| D5: Progressive Disclosure | 14 | 15 | |
| D6: Freedom Calibration | 14 | 15 | |
| D7: Pattern Recognition | 9 | 10 | |
| D8: Practical Usability | 14 | 15 | |
EOF
OUT="$($PARSER "$FN")"
assert_kv "$OUT" "PARSE_STATUS" "bad_row" "case-n"
assert_kv "$OUT" "GRADE_A" "false" "case-n"

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
