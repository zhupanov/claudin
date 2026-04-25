#!/usr/bin/env bash
# run-research-planner.sh — Validate planner subagent output and persist canonical subquestions.
#
# Consumed by /research Step 1.1 (Planner Pre-Pass) when RESEARCH_PLAN=true.
# The orchestrator invokes a Claude Agent subagent (no subagent_type) with the
# planner prompt, captures the raw output to --raw, then calls this script to
# validate, sanitize, and persist subquestions.txt.
#
# Stdout (machine output only):
#   On success: COUNT=<N> followed by OUTPUT=<path>, exit 0.
#   On failure: REASON=<token> (one of empty_input | count_below_minimum |
#               count_above_maximum | missing_arg | bad_path), exit non-zero.
#   No other lines appear on stdout.
#
# Stderr: human diagnostics (one line per anomaly observed during sanitization).
#
# Validation rules (applied in order):
#   1. --raw file must exist and be non-empty (else REASON=empty_input).
#   2. Each line is sanitized: strip ASCII control chars (except newlines),
#      strip leading bullet markers `^[[:space:]]*[-*][[:space:]]*`, trim.
#      (No numeric-prefix strip — the planner prompt's "no numbering" instruction
#      makes that strip unnecessary and risks false positives on subquestions
#      whose text legitimately starts with a number followed by `.` or `)`.)
#   3. Each line MUST end with `?` (question heuristic). Lines that do not are
#      dropped (NOT counted) — this fail-closes against prose preambles like
#      "Here are the subquestions:".
#   4. Empty lines (post-sanitization) are dropped.
#   5. The retained line count N must satisfy 2 <= N <= 4.
#      (REASON=count_below_minimum if N<2, REASON=count_above_maximum if N>4.)
#
# On success, retained lines are written to --output, one per line, with a
# trailing newline.
#
# See run-research-planner.md for the full contract, callers, and edit-in-sync
# rules.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: run-research-planner.sh --raw <path> --output <path>

  --raw <path>     Required. Path to the captured raw planner output (the orchestrator
                   writes the Agent subagent's response here before invoking this script).
  --output <path>  Required. Path to write the canonical subquestions.txt on success.
                   Each retained subquestion is written on its own line.

Exit 0 on success; non-zero on validation failure (with REASON=<token> on stdout).
USAGE
}

RAW_PATH=""
OUTPUT_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --raw)
      RAW_PATH="${2:-}"
      shift 2 || { echo "REASON=missing_arg"; exit 2; }
      ;;
    --output)
      OUTPUT_PATH="${2:-}"
      shift 2 || { echo "REASON=missing_arg"; exit 2; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "REASON=missing_arg"
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$RAW_PATH" || -z "$OUTPUT_PATH" ]]; then
  echo "REASON=missing_arg"
  echo "Both --raw and --output are required." >&2
  exit 2
fi

# --raw must exist and be readable; non-existence is treated as empty input.
if [[ ! -f "$RAW_PATH" ]]; then
  echo "REASON=empty_input"
  echo "Raw input file does not exist: $RAW_PATH" >&2
  exit 1
fi

if [[ ! -s "$RAW_PATH" ]]; then
  echo "REASON=empty_input"
  echo "Raw input file is empty: $RAW_PATH" >&2
  exit 1
fi

# --output's parent directory must exist (orchestrator owns $RESEARCH_TMPDIR creation).
OUTPUT_DIR="$(dirname -- "$OUTPUT_PATH")"
if [[ ! -d "$OUTPUT_DIR" ]]; then
  echo "REASON=bad_path"
  echo "Output directory does not exist: $OUTPUT_DIR" >&2
  exit 2
fi

# Sanitize and filter. Use awk to:
#   - Strip ASCII control characters (except newline) via gsub.
#   - Strip leading bullet marker (`-` or `*` followed by whitespace).
#   - Trim leading and trailing whitespace.
#   - Drop empty lines.
#   - Drop lines that do not end with `?` (after trim).
SUBQUESTIONS=$(awk '
  {
    # Strip ASCII control chars (0x00-0x08, 0x0b-0x1f, 0x7f). Keep 0x09 (tab) and
    # convert to space below; newlines are line terminators here.
    gsub(/[\001-\010\013-\037\177]/, "", $0)
    # Convert tabs to single spaces for trim consistency.
    gsub(/\t/, " ", $0)
    # Strip leading bullet (single `-` or `*` followed by whitespace).
    sub(/^[[:space:]]*[-*][[:space:]]+/, "", $0)
    # Trim leading and trailing whitespace.
    sub(/^[[:space:]]+/, "", $0)
    sub(/[[:space:]]+$/, "", $0)
    # Drop empty lines.
    if (length($0) == 0) next
    # Drop lines that do not end with `?` (question heuristic — fail-closed against
    # prose preambles like "Here are the subquestions:").
    if (substr($0, length($0)) != "?") next
    print $0
  }
' "$RAW_PATH")

if [[ -z "$SUBQUESTIONS" ]]; then
  # All lines dropped — could be empty input post-sanitize OR no question-shaped lines.
  echo "REASON=count_below_minimum"
  echo "No question-shaped lines remained after sanitization (all lines dropped)." >&2
  exit 1
fi

# Count retained lines.
COUNT=$(printf '%s\n' "$SUBQUESTIONS" | wc -l | tr -d '[:space:]')

if (( COUNT < 2 )); then
  echo "REASON=count_below_minimum"
  echo "Only $COUNT question-shaped line(s) remained after sanitization (need 2-4)." >&2
  exit 1
fi

if (( COUNT > 4 )); then
  echo "REASON=count_above_maximum"
  echo "$COUNT question-shaped lines remained after sanitization (need 2-4)." >&2
  exit 1
fi

# Persist canonical output. Use printf to ensure trailing newline.
printf '%s\n' "$SUBQUESTIONS" > "$OUTPUT_PATH"

echo "COUNT=$COUNT"
echo "OUTPUT=$OUTPUT_PATH"
exit 0
