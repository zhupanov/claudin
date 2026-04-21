#!/usr/bin/env bash
# report-deltas.sh — Emit a Markdown report comparing before and after sizes
# for a NUL-delimited set of .md files. Re-measures each file to capture the
# post-compression state.
#
# Usage:
#   report-deltas.sh --input <nul-list> --before <before.tsv> --output <report.md>
#
# The before TSV is produced by measure-set.sh (path<TAB>bytes<TAB>lines).
# The report is written to --output as Markdown; nothing structured is
# emitted on stdout.

set -euo pipefail

INPUT=""
BEFORE=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  INPUT="$2";  shift 2 ;;
    --before) BEFORE="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$INPUT"  ]] || { echo "ERROR=Missing --input"  >&2; exit 1; }
[[ -n "$BEFORE" ]] || { echo "ERROR=Missing --before" >&2; exit 1; }
[[ -n "$OUTPUT" ]] || { echo "ERROR=Missing --output" >&2; exit 1; }
[[ -f "$INPUT"  ]] || { echo "ERROR=Input list not found: $INPUT"    >&2; exit 1; }
[[ -f "$BEFORE" ]] || { echo "ERROR=Before TSV not found: $BEFORE" >&2; exit 1; }

# Look up before counts by path.
lookup_before_bytes() {
  awk -F '\t' -v p="$1" '$1==p { print $2; exit }' "$BEFORE"
}
lookup_before_lines() {
  awk -F '\t' -v p="$1" '$1==p { print $3; exit }' "$BEFORE"
}

TOTAL_BEFORE_BYTES=0
TOTAL_AFTER_BYTES=0
TOTAL_BEFORE_LINES=0
TOTAL_AFTER_LINES=0
FILE_COUNT=0

ROWS=""
while IFS= read -r -d '' path; do
  [[ -n "$path" ]] || continue
  if [[ ! -f "$path" ]]; then
    echo "ERROR=Listed file does not exist: $path" >&2
    exit 1
  fi
  before_bytes=$(lookup_before_bytes "$path")
  before_lines=$(lookup_before_lines "$path")
  [[ -n "$before_bytes" ]] || { echo "ERROR=No before entry for $path in $BEFORE" >&2; exit 1; }
  after_bytes=$(wc -c <"$path" | tr -d '[:space:]')
  after_lines=$(wc -l <"$path" | tr -d '[:space:]')
  delta_bytes=$(( after_bytes - before_bytes ))
  delta_lines=$(( after_lines - before_lines ))
  TOTAL_BEFORE_BYTES=$(( TOTAL_BEFORE_BYTES + before_bytes ))
  TOTAL_AFTER_BYTES=$((  TOTAL_AFTER_BYTES  + after_bytes  ))
  TOTAL_BEFORE_LINES=$(( TOTAL_BEFORE_LINES + before_lines ))
  TOTAL_AFTER_LINES=$((  TOTAL_AFTER_LINES  + after_lines  ))
  FILE_COUNT=$(( FILE_COUNT + 1 ))
  ROWS+="| \`${path}\` | ${before_bytes} → ${after_bytes} (${delta_bytes}) | ${before_lines} → ${after_lines} (${delta_lines}) |"$'\n'
done < "$INPUT"

TOTAL_DELTA_BYTES=$(( TOTAL_AFTER_BYTES - TOTAL_BEFORE_BYTES ))
TOTAL_DELTA_LINES=$(( TOTAL_AFTER_LINES - TOTAL_BEFORE_LINES ))

PCT_BYTES=""
if [[ "$TOTAL_BEFORE_BYTES" -gt 0 ]]; then
  PCT_BYTES=$(awk -v d="$TOTAL_DELTA_BYTES" -v b="$TOTAL_BEFORE_BYTES" 'BEGIN { printf "%+.1f%%", (d*100.0)/b }')
fi

{
  printf '## Compression report\n\n'
  printf 'Files compressed: %s\n\n' "$FILE_COUNT"
  printf '| File | Bytes (before → after, Δ) | Lines (before → after, Δ) |\n'
  printf '|------|---------------------------|---------------------------|\n'
  printf '%s' "$ROWS"
  printf '| **Totals** | **%s → %s (%s%s)** | **%s → %s (%s)** |\n' \
    "$TOTAL_BEFORE_BYTES" "$TOTAL_AFTER_BYTES" "$TOTAL_DELTA_BYTES" \
    "${PCT_BYTES:+, $PCT_BYTES}" \
    "$TOTAL_BEFORE_LINES" "$TOTAL_AFTER_LINES" "$TOTAL_DELTA_LINES"
} > "$OUTPUT"
