#!/usr/bin/env bash
# test-allocate-candidates.sh — Regression tests for allocate-candidates.sh.
#
# Covers issue #554's per-item floor algorithm: F = 0 if N>30 else
# min(3, floor(30/N)); two-pass selection (floor reservation + confidence-
# ranked spillover); union-credit semantics; tie-breaks; kind=both first-class;
# defensive-default row drops; N>30 stderr warning; empty-stdin / N=0; stdout-
# shape invariant; Bash 3.2 portability guard.
#
# Wired into `make lint` via the `test-allocate-candidates` target so the
# harness runs in CI on every PR. Run manually:
#
#   bash skills/issue/scripts/test-allocate-candidates.sh
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ALLOCATOR="$SCRIPT_DIR/allocate-candidates.sh"

if [[ ! -f "$ALLOCATOR" ]]; then
    echo "ERROR: allocator not found: $ALLOCATOR" >&2
    exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label"
        echo "    expected: $(printf '%q' "$expected")"
        echo "    actual:   $(printf '%q' "$actual")"
        exit 1
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label — expected to contain: $(printf '%q' "$needle")"
        echo "    actual: $(printf '%q' "$haystack")"
        exit 1
    fi
}

assert_not_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label — should NOT contain: $(printf '%q' "$needle")"
        echo "    actual: $(printf '%q' "$haystack")"
        exit 1
    fi
}

# Helper: run allocator with stdin, capture stdout and stderr separately.
# Usage: run_allocator <total-items> <stdin>
# Sets RUN_STDOUT, RUN_STDERR, RUN_RC.
run_allocator() {
    local n="$1" stdin="$2"
    local out_f err_f
    out_f="$(mktemp)"
    err_f="$(mktemp)"
    set +e
    printf '%s' "$stdin" | "$ALLOCATOR" --total-items "$n" >"$out_f" 2>"$err_f"
    RUN_RC=$?
    set -e
    RUN_STDOUT="$(cat "$out_f")"
    RUN_STDERR="$(cat "$err_f")"
    rm -f "$out_f" "$err_f"
}

# ----------------------------------------------------------------------
# Test 1 — Baseline N=3, F=3, every item gets up to 3 slots.
# ----------------------------------------------------------------------
echo "Test 1: baseline N=3, F=3"
INPUT_T1=$(printf 'CAND 1 100 dup high\nCAND 1 101 dep high\nCAND 1 102 dup medium\nCAND 2 200 dup high\nCAND 2 201 dep high\nCAND 3 300 dup high\nCAND 3 301 dep medium\nCAND 3 302 dup low\n')
run_allocator 3 "$INPUT_T1"
assert_eq "T1 exit code 0" "0" "$RUN_RC"
assert_eq "T1 CANDIDATES" "CANDIDATES=100,101,102,200,201,300,301,302" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 2 — N=10, F=3, full floor (each item emits 3 high-conf rows). Total 30, Pass B vacuous.
# ----------------------------------------------------------------------
echo "Test 2: N=10, F=3, full floor, total 30 (Pass B vacuous)"
INPUT_T2=""
expected_csv=""
for i in 1 2 3 4 5 6 7 8 9 10; do
    base=$(( i * 100 ))
    INPUT_T2="${INPUT_T2}CAND $i $base dup high
CAND $i $((base+1)) dep high
CAND $i $((base+2)) dup high
"
    expected_csv="${expected_csv}${expected_csv:+,}$base,$((base+1)),$((base+2))"
done
# Sort the expected CSV ascending numerically.
expected_sorted=$(echo "$expected_csv" | tr ',' '\n' | sort -n | paste -sd, -)
run_allocator 10 "$INPUT_T2"
assert_eq "T2 exit code 0" "0" "$RUN_RC"
assert_eq "T2 CANDIDATES" "CANDIDATES=$expected_sorted" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 3 — N=10, F=3, partial floor (5 items emit 1 high-conf row each).
#   Pass A consumes 5 slots; Pass B fills 25 from leftover.
# ----------------------------------------------------------------------
echo "Test 3: N=10, F=3, partial floor consumption"
# Items 1-5 each emit 1 high-conf row (issues 100, 200, ..., 500).
# Items 6-10 each emit 6 medium-conf rows (issues 600-605, 700-705, ..., 1000-1005).
# Pass A: items 1-5 use 1 slot each (5). Items 6-10 use 3 slots each = 15. Total 20 in Pass A.
# Wait: F=3 for N=10, but items 1-5 only have 1 row each → floor_credits[i]=1. Items 6-10 have 6 rows, take first 3 → floor_credits[i]=3.
# So Pass A: 5 items × 1 + 5 items × 3 = 5 + 15 = 20.
# Pass B: 30 - 20 = 10 leftover slots; items 6-10 each have 3 leftover medium rows = 15 leftover total.
# Pass B sorts by conf desc (all medium) then issue asc — fills first 10. Issues 603,604,605,703,704,705,803,804,805,903 (10 of 15).
INPUT_T3=""
for i in 1 2 3 4 5; do
    INPUT_T3="${INPUT_T3}CAND $i $((i*100)) dup high
"
done
for i in 6 7 8 9 10; do
    base=$(( i * 100 ))
    for offset in 0 1 2 3 4 5; do
        INPUT_T3="${INPUT_T3}CAND $i $((base+offset)) dup medium
"
    done
done
run_allocator 10 "$INPUT_T3"
assert_eq "T3 exit code 0" "0" "$RUN_RC"
# Expected: items 1-5 contribute 100, 200, 300, 400, 500.
# Items 6-10 each take 3 floor slots (lowest issue numbers within item, sorted asc by issue): 600,601,602,700,701,702,800,801,802,900,901,902,1000,1001,1002. That's 15.
# Pass A total: 5 + 15 = 20.
# Pass B leftover: 603,604,605,703,704,705,803,804,805,903,904,905,1003,1004,1005. 15 rows.
# Sort by conf desc (all medium) then issue asc: 603, 604, 605, 703, 704, 705, 803, 804, 805, 903 (first 10).
# Final union: 100,200,300,400,500,600,601,602,603,604,605,700,701,702,703,704,705,800,801,802,803,804,805,900,901,902,903,1000,1001,1002. That's 30.
T3_EXPECTED="100,200,300,400,500,600,601,602,603,604,605,700,701,702,703,704,705,800,801,802,803,804,805,900,901,902,903,1000,1001,1002"
assert_eq "T3 CANDIDATES (partial floor + Pass B)" "CANDIDATES=$T3_EXPECTED" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 4 — N=11, F=2 (floor reduced; 22 floor + 8 spillover).
# ----------------------------------------------------------------------
echo "Test 4: N=11, F=2"
INPUT_T4=""
for i in 1 2 3 4 5 6 7 8 9 10 11; do
    base=$(( i * 100 ))
    INPUT_T4="${INPUT_T4}CAND $i $base dup high
CAND $i $((base+1)) dup high
CAND $i $((base+2)) dup medium
"
done
run_allocator 11 "$INPUT_T4"
assert_eq "T4 exit code 0" "0" "$RUN_RC"
# Pass A with F=2: each item picks first 2 high (sorted by conf desc, issue asc).
# Item 1: 100, 101. Item 2: 200, 201. ... Item 11: 1100, 1101. Total 22.
# Pass B leftover: 102, 202, ..., 1102 (11 medium rows). Sort by conf desc (medium) issue asc: 102, 202, 302, ..., 1002, 1102.
# Cap remaining: 30 - 22 = 8. Take first 8 medium rows: 102, 202, 302, 402, 502, 602, 702, 802.
# Final 30: 100,101,102,200,201,202,300,301,302,400,401,402,500,501,502,600,601,602,700,701,702,800,801,802,900,901,1000,1001,1100,1101.
T4_EXPECTED="100,101,102,200,201,202,300,301,302,400,401,402,500,501,502,600,601,602,700,701,702,800,801,802,900,901,1000,1001,1100,1101"
assert_eq "T4 CANDIDATES (N=11, F=2)" "CANDIDATES=$T4_EXPECTED" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 5 — N=15, F=2, total 30 exactly.
# ----------------------------------------------------------------------
echo "Test 5: N=15, F=2, exactly 30 in floor"
INPUT_T5=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15; do
    base=$(( i * 100 ))
    INPUT_T5="${INPUT_T5}CAND $i $base dup high
CAND $i $((base+1)) dup high
"
done
run_allocator 15 "$INPUT_T5"
assert_eq "T5 exit code 0" "0" "$RUN_RC"
T5_EXPECTED="100,101,200,201,300,301,400,401,500,501,600,601,700,701,800,801,900,901,1000,1001,1100,1101,1200,1201,1300,1301,1400,1401,1500,1501"
assert_eq "T5 CANDIDATES (N=15, F=2)" "CANDIDATES=$T5_EXPECTED" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 6 — N=16, F=1, 16 floor + 14 spillover.
# ----------------------------------------------------------------------
echo "Test 6: N=16, F=1, 16 floor + 14 spillover"
INPUT_T6=""
for i in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16; do
    base=$(( i * 100 ))
    INPUT_T6="${INPUT_T6}CAND $i $base dup high
CAND $i $((base+1)) dup high
"
done
run_allocator 16 "$INPUT_T6"
assert_eq "T6 exit code 0" "0" "$RUN_RC"
# Pass A with F=1: each of 16 items adds 1 slot = 16 in union.
# Pass B leftover: 16 high rows. Sort high → issue asc → take first 14.
# Union: 100,101,200,201,300,301,400,401,500,501,600,601,700,701,800,801,900,901,1000,1001,1100,1101,1200,1201,1300,1301,1400,1401,1500,1600.
# 16 floor (100,200,300,400,500,600,700,800,900,1000,1100,1200,1300,1400,1500,1600).
# 14 spillover from leftover (101,201,301,...,1401), sorted asc: 101,201,301,401,501,601,701,801,901,1001,1101,1201,1301,1401.
# Total 30, sorted ascending.
T6_EXPECTED="100,101,200,201,300,301,400,401,500,501,600,601,700,701,800,801,900,901,1000,1001,1100,1101,1200,1201,1300,1301,1400,1401,1500,1600"
assert_eq "T6 CANDIDATES (N=16, F=1)" "CANDIDATES=$T6_EXPECTED" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 7 — N=30, F=1, each item gets exactly 1 slot.
# ----------------------------------------------------------------------
echo "Test 7: N=30, F=1, all 30 items"
INPUT_T7=""
expected_t7=""
for i in $(seq 1 30); do
    base=$(( i * 100 ))
    INPUT_T7="${INPUT_T7}CAND $i $base dup high
"
    expected_t7="${expected_t7}${expected_t7:+,}$base"
done
expected_t7_sorted=$(echo "$expected_t7" | tr ',' '\n' | sort -n | paste -sd, -)
run_allocator 30 "$INPUT_T7"
assert_eq "T7 exit code 0" "0" "$RUN_RC"
assert_eq "T7 CANDIDATES (N=30, F=1)" "CANDIDATES=$expected_t7_sorted" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 8 — N=31 degenerate, F=0, all 30 from confidence ranking only.
# ----------------------------------------------------------------------
echo "Test 8: N=31 degenerate, F=0"
INPUT_T8=""
for i in $(seq 1 31); do
    base=$(( i * 100 ))
    # Items 1-15 emit high, 16-25 medium, 26-31 low.
    if (( i <= 15 )); then conf=high
    elif (( i <= 25 )); then conf=medium
    else conf=low
    fi
    INPUT_T8="${INPUT_T8}CAND $i $base dup $conf
"
done
run_allocator 31 "$INPUT_T8"
assert_eq "T8 exit code 0" "0" "$RUN_RC"
assert_contains "T8 N>30 stderr warning" "$RUN_STDERR" "dedup batch exceeds 30 non-malformed items"
# Pass B: sort by conf desc, issue asc. 15 high + 10 medium + 5 of 6 low (drop one). Top 30:
# all 15 high (100..1500), all 10 medium (1600..2500), 5 low (2600..3000).
T8_EXPECTED="100,200,300,400,500,600,700,800,900,1000,1100,1200,1300,1400,1500,1600,1700,1800,1900,2000,2100,2200,2300,2400,2500,2600,2700,2800,2900,3000"
assert_eq "T8 CANDIDATES" "CANDIDATES=$T8_EXPECTED" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 9 — Tie-break: same confidence → lower issue-number wins.
# ----------------------------------------------------------------------
echo "Test 9: tie-break — same confidence, lower issue-number wins"
# N=2, F=3 (2 items, F=min(3, floor(30/2))=3). Items each emit 1 row.
# Then add 31 medium rows (need cap to bind) — actually let's do a simpler case.
# N=10, F=3. Item 1 emits 5 medium rows. Items 2-10 emit nothing. Pass A: floor[1]=3 (top 3 by issue asc). Pass B: 27 slots free, 2 remaining medium rows from item 1 → fill all leftovers.
INPUT_T9="CAND 1 105 dup medium
CAND 1 102 dup medium
CAND 1 101 dup medium
CAND 1 104 dup medium
CAND 1 103 dup medium
"
run_allocator 10 "$INPUT_T9"
assert_eq "T9 exit code 0" "0" "$RUN_RC"
# Pass A with F=3: item 1 sorts by conf desc (all medium), issue asc → 101, 102, 103. Floor=3, stop.
# Pass B: leftover 104, 105 (medium). Cap 30-3=27 slots. Add both.
# Final: 101,102,103,104,105.
assert_eq "T9 CANDIDATES (tie-break by issue asc)" "CANDIDATES=101,102,103,104,105" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 10 — Union semantics: same issue nominated by 2 items counts for both floors.
# ----------------------------------------------------------------------
echo "Test 10: union semantics — shared candidate covers both items' floors"
# N=2, F=3. Item 1 nominates 100, 101. Item 2 nominates 100, 200.
# Pass A item 1: 100 high → add to union, floor[1]=1, floor[2]=1 (item 2 also nominated 100). 101 high → add, floor[1]=2.
# Pass A item 2: 100 already in union → floor[2]=2 without growing union. 200 high → add, floor[2]=3 (>=F). Stop.
# Pass B leftover: empty (no rows left). Union = 100, 101, 200.
INPUT_T10="CAND 1 100 dup high
CAND 1 101 dup high
CAND 2 100 dup high
CAND 2 200 dup high
"
run_allocator 2 "$INPUT_T10"
assert_eq "T10 exit code 0" "0" "$RUN_RC"
assert_eq "T10 CANDIDATES (union semantics)" "CANDIDATES=100,101,200" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 11 — kind=both first-class.
# ----------------------------------------------------------------------
echo "Test 11: kind=both first-class (single slot, single floor credit per nominator)"
INPUT_T11="CAND 1 100 both high
CAND 2 100 both medium
"
run_allocator 2 "$INPUT_T11"
assert_eq "T11 exit code 0" "0" "$RUN_RC"
# 100 added once (high beats medium in dedup); both items credit floor=1 from union semantics.
assert_eq "T11 CANDIDATES (kind=both)" "CANDIDATES=100" "$RUN_STDOUT"
assert_not_contains "T11 no kind=both warning" "$RUN_STDERR" "dropped malformed"

# ----------------------------------------------------------------------
# Test 12 — Defensive default: missing confidence → low.
# ----------------------------------------------------------------------
echo "Test 12: missing confidence defaults to low"
INPUT_T12="CAND 1 100 dup
CAND 1 101 dup high
"
run_allocator 1 "$INPUT_T12"
assert_eq "T12 exit code 0" "0" "$RUN_RC"
# Both rows valid (confidence missing → low for 100, high for 101).
# F=3 (N=1), Pass A: sort high desc → 101, 100. Add both. Floor[1]=2. No more rows. Pass B vacuous.
assert_eq "T12 CANDIDATES" "CANDIDATES=100,101" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 13 — Defensive default: unknown kind → dup.
# ----------------------------------------------------------------------
echo "Test 13: unknown kind normalized to dup"
INPUT_T13="CAND 1 100 unknown high
CAND 1 101 weird medium
"
run_allocator 1 "$INPUT_T13"
assert_eq "T13 exit code 0" "0" "$RUN_RC"
# Both rows accepted (kind normalized to dup).
assert_eq "T13 CANDIDATES" "CANDIDATES=100,101" "$RUN_STDOUT"
assert_not_contains "T13 no malformed-row warnings" "$RUN_STDERR" "dropped malformed"

# ----------------------------------------------------------------------
# Test 14 — Defensive drop: non-numeric item → drop with stderr.
# ----------------------------------------------------------------------
echo "Test 14: non-numeric item index dropped"
INPUT_T14="CAND abc 100 dup high
CAND 1 101 dup high
"
run_allocator 1 "$INPUT_T14"
assert_eq "T14 exit code 0" "0" "$RUN_RC"
assert_contains "T14 stderr warning for bad item" "$RUN_STDERR" "non-numeric item index"
assert_eq "T14 CANDIDATES" "CANDIDATES=101" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 15 — Defensive drop: out-of-range item index.
# ----------------------------------------------------------------------
echo "Test 15: out-of-range item index dropped"
INPUT_T15="CAND 5 100 dup high
CAND 1 200 dup high
"
run_allocator 2 "$INPUT_T15"
assert_eq "T15 exit code 0" "0" "$RUN_RC"
assert_contains "T15 stderr warning for out-of-range" "$RUN_STDERR" "out of range"
assert_eq "T15 CANDIDATES" "CANDIDATES=200" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 16 — Defensive drop: non-numeric issue.
# ----------------------------------------------------------------------
echo "Test 16: non-numeric issue dropped"
INPUT_T16="CAND 1 abc dup high
CAND 1 200 dup high
CAND 1 0 dup high
"
run_allocator 1 "$INPUT_T16"
assert_eq "T16 exit code 0" "0" "$RUN_RC"
assert_contains "T16 stderr warning for non-numeric issue" "$RUN_STDERR" "non-numeric or non-positive issue number"
assert_eq "T16 CANDIDATES (only valid row 200)" "CANDIDATES=200" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 17 — N=0: empty CANDIDATES, exit 0 even with non-empty stdin.
# ----------------------------------------------------------------------
echo "Test 17: N=0 with non-empty stdin"
INPUT_T17="CAND 1 100 dup high
"
run_allocator 0 "$INPUT_T17"
assert_eq "T17 exit code 0" "0" "$RUN_RC"
assert_eq "T17 CANDIDATES (N=0)" "CANDIDATES=" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 18 — Empty stdin with N>0.
# ----------------------------------------------------------------------
echo "Test 18: empty stdin with N>0"
run_allocator 5 ""
assert_eq "T18 exit code 0" "0" "$RUN_RC"
assert_eq "T18 CANDIDATES (empty stdin)" "CANDIDATES=" "$RUN_STDOUT"

# ----------------------------------------------------------------------
# Test 19 — Stdout-shape invariant: exactly one CANDIDATES= line.
# ----------------------------------------------------------------------
echo "Test 19: stdout exactly one CANDIDATES= line"
INPUT_T19="CAND 1 abc dup high
CAND 1 100 dup high
CAND 1 200 dup high
"
run_allocator 1 "$INPUT_T19"
assert_eq "T19 exit code 0" "0" "$RUN_RC"
T19_LINE_COUNT=$(echo "$RUN_STDOUT" | grep -cE '^CANDIDATES=' || true)
assert_eq "T19 stdout has exactly one CANDIDATES= line" "1" "$T19_LINE_COUNT"
T19_TOTAL_LINES=$(echo "$RUN_STDOUT" | wc -l | tr -d ' ')
assert_eq "T19 stdout total lines (one)" "1" "$T19_TOTAL_LINES"

# ----------------------------------------------------------------------
# Test 20 — Hard 30-cap: even with all-high confidence and many items.
# ----------------------------------------------------------------------
echo "Test 20: hard 30-cap respected"
INPUT_T20=""
for i in $(seq 1 5); do
    for issue_offset in $(seq 0 9); do
        INPUT_T20="${INPUT_T20}CAND $i $((i * 1000 + issue_offset)) dup high
"
    done
done
# 5 items × 10 rows each = 50 high rows, all unique.
run_allocator 5 "$INPUT_T20"
assert_eq "T20 exit code 0" "0" "$RUN_RC"
T20_COUNT=$(echo "$RUN_STDOUT" | sed 's/^CANDIDATES=//' | tr ',' '\n' | wc -l | tr -d ' ')
assert_eq "T20 union size capped at 30" "30" "$T20_COUNT"

# ----------------------------------------------------------------------
# Test 21 — Bash 3.2 portability guard.
# ----------------------------------------------------------------------
echo "Test 21: Bash 3.2 portability — no declare -A, mapfile, or \${var,,}"
# Strip leading-whitespace comments before checking, so the doc comment listing
# forbidden constructs doesn't trigger a false positive.
T21_OFFENDERS=$(grep -nE 'declare -A|mapfile|\$\{[A-Z_]+,,\}' "$ALLOCATOR" \
    | grep -vE '^[0-9]+:[[:space:]]*#' || true)
if [[ -n "$T21_OFFENDERS" ]]; then
    FAIL_COUNT=$((FAIL_COUNT + 1))
    echo "  FAIL: T21 — found Bash 4-only construct in $ALLOCATOR"
    echo "$T21_OFFENDERS"
    exit 1
else
    PASS_COUNT=$((PASS_COUNT + 1))
    echo "  PASS: T21 — no Bash 4-only constructs found"
fi

# ----------------------------------------------------------------------
# Test 22 — Usage error exits 1 when --total-items missing.
# ----------------------------------------------------------------------
echo "Test 22: missing --total-items returns exit 1"
set +e
echo "" | "$ALLOCATOR" >/dev/null 2>&1
RC=$?
set -e
assert_eq "T22 missing flag → exit 1" "1" "$RC"

# ----------------------------------------------------------------------
# Test 23 — Stderr-only diagnostics: N>30 banner appears in stderr, NOT stdout.
# ----------------------------------------------------------------------
echo "Test 23: N>30 warning is stderr-only"
run_allocator 31 ""
assert_eq "T23 exit code 0" "0" "$RUN_RC"
assert_eq "T23 stdout is just CANDIDATES= line" "CANDIDATES=" "$RUN_STDOUT"
assert_contains "T23 stderr has the N>30 warning" "$RUN_STDERR" "dedup batch exceeds 30"
assert_not_contains "T23 stdout does NOT have the N>30 warning" "$RUN_STDOUT" "dedup batch exceeds"

echo ""
echo "=========================================="
echo "Results: $PASS_COUNT passed, $FAIL_COUNT failed"
echo "=========================================="
exit 0
