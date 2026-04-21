#!/usr/bin/env bash
# parse-skill-judge-grade.sh — Parse /skill-judge output for per-dimension
# grade-A status.
#
# Consumed by /loop-improve-skill (driver.sh — both in-loop per-iter grade
# parse and post-iter-cap final re-evaluation) to drive the grade-gated
# termination contract: the loop strives for grade A on every dimension
# D1..D8 and exits happy when achieved.
#
# Usage:
#   parse-skill-judge-grade.sh <judge-output-file>
#
# Output (stdout, KEY=VALUE; only the indicated subset on parse failure):
#   PARSE_STATUS=ok|missing_table|missing_file|bad_row|empty_file
#   GRADE_A=true|false
#   NON_A_DIMS=D2,D7        (when PARSE_STATUS=ok; empty if all A)
#   TOTAL_NUM=<int>          (when PARSE_STATUS=ok)
#   TOTAL_DEN=120            (when PARSE_STATUS=ok)
#   D1_NUM=<int> D1_DEN=<int>
#   ...                      (D1..D8, when PARSE_STATUS=ok)
#   D8_NUM=<int> D8_DEN=<int>
#   OVERALL_GRADE=A|B|C|D|F  (when PARSE_STATUS=ok, derived from total %)
#
# IMPORTANT: GRADE_A and OVERALL_GRADE measure DIFFERENT things and may
# diverge. GRADE_A=true requires per-dimension A on every D1..D8 (the
# integer thresholds below). OVERALL_GRADE is computed purely from the
# aggregate TOTAL_NUM/TOTAL_DEN against /skill-judge's percentage scale
# (A 90%+, B 80-89, C 70-79, D 60-69, F <60). A skill can have
# OVERALL_GRADE=A while GRADE_A=false (e.g., D1=17/20 plus all other
# dimensions at max gives ~97.5% total but D1 falls short of its
# per-dim threshold). The /loop-improve-skill termination contract
# uses GRADE_A (the strict per-dim form), not OVERALL_GRADE.
#
# Exit codes:
#   0 — always on parseable invocation (fail-closed contract is on stdout).
#   1 — argument errors (missing arg, etc.).
#
# Fail-closed contract: any non-ok PARSE_STATUS forces GRADE_A=false. The
# loop continues iterating rather than silently exiting as grade A on a
# parse failure. Defensive consistency check: PARSE_STATUS=ok AND
# GRADE_A=false AND NON_A_DIMS empty → override to PARSE_STATUS=bad_row,
# GRADE_A=false. This catches an internal coding bug; non-ok statuses
# preserve their PARSE_STATUS unchanged (missing_table etc. legitimately
# have empty NON_A_DIMS).
#
# Per-dimension thresholds (integer; A = score/max ≥ 0.90):
#   D1 ≥ 18/20  D2 ≥ 14/15  D3 ≥ 14/15  D4 ≥ 14/15
#   D5 ≥ 14/15  D6 ≥ 14/15  D7 ≥ 9/10   D8 ≥ 14/15
#
# Grammar pinned to the FIRST `## Dimension Scores` heading in the
# /skill-judge output (sourced from the "Step 5: Generate Report"
# template in the upstream /skill-judge SKILL.md, cached plugin install).
# The following section MUST contain a pipe table whose data rows
# start with `| D<N>` (1..8 in order) where the 2nd and 3rd cells are
# integer score/max with score <= max. Anything else → PARSE_STATUS=bad_row.

set -euo pipefail

if [[ $# -ne 1 ]]; then
  printf 'PARSE_ERROR=usage: %s <judge-output-file>\n' "$(basename "$0")" >&2
  exit 1
fi

INPUT="$1"

emit_failure() {
  # $1 = PARSE_STATUS token
  printf 'PARSE_STATUS=%s\n' "$1"
  printf 'GRADE_A=false\n'
}

if [[ ! -f "$INPUT" ]]; then
  emit_failure missing_file
  exit 0
fi

if [[ ! -s "$INPUT" ]]; then
  emit_failure empty_file
  exit 0
fi

# Per-dim thresholds and maxes (bash 3.2 compatible — no associative arrays).
threshold_for() {
  case "$1" in
    D1) echo 18 ;;
    D2|D3|D4|D5|D6|D8) echo 14 ;;
    D7) echo 9 ;;
    *) echo 0 ;;
  esac
}
expected_max_for() {
  case "$1" in
    D1) echo 20 ;;
    D2|D3|D4|D5|D6|D8) echo 15 ;;
    D7) echo 10 ;;
    *) echo 0 ;;
  esac
}

# Locate first "## Dimension Scores" heading line; capture lines after it
# until the next markdown heading or EOF, then extract the pipe-table
# data rows.
#
# `awk` walks the file once. State `in_section=1` after the heading; exit
# section on next `^## ` or `^# `. Within section, emit lines starting
# with `| D` (data rows). We accept the table header `| Dimension |
# Score | Max | Notes |` and the separator `|---|---|---|---|` by
# filtering only `| D<digit>` lines.
DATA_ROWS="$(LC_ALL=C awk '
  BEGIN { in_section = 0; printed_any = 0 }
  /^## Dimension Scores[[:space:]]*$/ {
    in_section = 1
    next
  }
  in_section == 1 && /^##[[:space:]]/ {
    in_section = 0
    next
  }
  in_section == 1 && /^\|[[:space:]]*D[1-8]/ {
    print
    printed_any = 1
  }
  END { exit (printed_any ? 0 : 1) }
' "$INPUT")" || {
  emit_failure missing_table
  exit 0
}

# Parse data rows. Expect 8 rows in order D1..D8. Each row format:
#   | D<N>: <Title> | <score> | <max> | <notes...> |
# Use `|` as field separator; cells 2 (D-label), 3 (score), 4 (max).
# bash 3.2 — use parallel index arrays instead of associative arrays.
DIM_NUMS=()  # 0-indexed, slot N-1 holds D<N> score
DIM_DENS=()
ROW_COUNT=0
EXPECTED_DIM=1
TOTAL_NUM=0

# IFS preserved; read each row.
while IFS= read -r ROW; do
  [[ -z "$ROW" ]] && continue
  ROW_COUNT=$((ROW_COUNT + 1))

  # Split on |, trim whitespace from each field.
  # awk approach is robust against extra trailing pipe.
  LABEL_CELL="$(printf '%s' "$ROW" | LC_ALL=C awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2 }')"
  SCORE_CELL="$(printf '%s' "$ROW" | LC_ALL=C awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $3); print $3 }')"
  MAX_CELL="$(printf '%s' "$ROW" | LC_ALL=C awk -F'|' '{ gsub(/^[[:space:]]+|[[:space:]]+$/, "", $4); print $4 }')"

  # Label must start with D<EXPECTED_DIM>
  if ! [[ "$LABEL_CELL" =~ ^D${EXPECTED_DIM}([:[:space:]]|$) ]]; then
    emit_failure bad_row
    exit 0
  fi

  # Score and max must be integers.
  if ! [[ "$SCORE_CELL" =~ ^[0-9]+$ ]]; then
    emit_failure bad_row
    exit 0
  fi
  if ! [[ "$MAX_CELL" =~ ^[0-9]+$ ]]; then
    emit_failure bad_row
    exit 0
  fi

  DIM="D${EXPECTED_DIM}"

  # Sanity: max must match expected.
  if [[ "$MAX_CELL" != "$(expected_max_for "$DIM")" ]]; then
    emit_failure bad_row
    exit 0
  fi

  # Sanity: score must not exceed max. A row like `D1 | 30 | 20` would
  # otherwise inflate TOTAL_NUM and could falsely pass the per-dim
  # threshold check, producing GRADE_A=true on impossible scores.
  if [[ "$SCORE_CELL" -gt "$MAX_CELL" ]]; then
    emit_failure bad_row
    exit 0
  fi

  DIM_NUMS[EXPECTED_DIM - 1]="$SCORE_CELL"
  DIM_DENS[EXPECTED_DIM - 1]="$MAX_CELL"
  TOTAL_NUM=$((TOTAL_NUM + SCORE_CELL))

  EXPECTED_DIM=$((EXPECTED_DIM + 1))
done <<< "$DATA_ROWS"

# Must be exactly 8 rows.
if [[ "$ROW_COUNT" -ne 8 ]]; then
  emit_failure bad_row
  exit 0
fi

# Compute NON_A_DIMS in D1..D8 order.
NON_A_LIST=()
for n in 1 2 3 4 5 6 7 8; do
  DIM="D${n}"
  IDX=$((n - 1))
  if [[ "${DIM_NUMS[$IDX]}" -lt "$(threshold_for "$DIM")" ]]; then
    NON_A_LIST+=("$DIM")
  fi
done

NON_A_DIMS=""
if [[ "${#NON_A_LIST[@]}" -gt 0 ]]; then
  NON_A_DIMS="$(IFS=,; printf '%s' "${NON_A_LIST[*]}")"
fi

if [[ -z "$NON_A_DIMS" ]]; then
  GRADE_A=true
else
  GRADE_A=false
fi

# Defensive consistency check (scoped to ok parses only).
if [[ "$GRADE_A" == "false" && -z "$NON_A_DIMS" ]]; then
  # Unreachable under correct logic above; defense-in-depth.
  emit_failure bad_row
  exit 0
fi

# Compute overall grade letter from total percentage. /skill-judge scale:
# A 90%+, B 80-89, C 70-79, D 60-69, F <60.
TOTAL_DEN=120
PERMILLE=$((TOTAL_NUM * 1000 / TOTAL_DEN))  # parts per thousand
if [[ "$PERMILLE" -ge 900 ]]; then
  OVERALL_GRADE=A
elif [[ "$PERMILLE" -ge 800 ]]; then
  OVERALL_GRADE=B
elif [[ "$PERMILLE" -ge 700 ]]; then
  OVERALL_GRADE=C
elif [[ "$PERMILLE" -ge 600 ]]; then
  OVERALL_GRADE=D
else
  OVERALL_GRADE=F
fi

# Emit happy-path KV output.
printf 'PARSE_STATUS=ok\n'
printf 'GRADE_A=%s\n' "$GRADE_A"
printf 'NON_A_DIMS=%s\n' "$NON_A_DIMS"
printf 'TOTAL_NUM=%s\n' "$TOTAL_NUM"
printf 'TOTAL_DEN=%s\n' "$TOTAL_DEN"
for n in 1 2 3 4 5 6 7 8; do
  DIM="D${n}"
  IDX=$((n - 1))
  printf '%s_NUM=%s\n' "$DIM" "${DIM_NUMS[$IDX]}"
  printf '%s_DEN=%s\n' "$DIM" "${DIM_DENS[$IDX]}"
done
printf 'OVERALL_GRADE=%s\n' "$OVERALL_GRADE"

exit 0
