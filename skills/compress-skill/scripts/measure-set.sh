#!/usr/bin/env bash
# measure-set.sh — Record byte and line count for each file in a NUL-delimited
# list. Emits a TSV (path<TAB>bytes<TAB>lines) plus totals on stdout.
#
# Usage:
#   measure-set.sh --input <nul-delimited-list> --output <tsv-path>
#
# Output (stdout):
#   TOTAL_BYTES=<n>
#   TOTAL_LINES=<n>
#   FILE_COUNT=<n>

set -euo pipefail

INPUT=""
OUTPUT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --input)  INPUT="$2";  shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

[[ -n "$INPUT"  ]] || { echo "ERROR=Missing --input"  >&2; exit 1; }
[[ -n "$OUTPUT" ]] || { echo "ERROR=Missing --output" >&2; exit 1; }
[[ -f "$INPUT"  ]] || { echo "ERROR=Input list not found: $INPUT" >&2; exit 1; }

TOTAL_BYTES=0
TOTAL_LINES=0
FILE_COUNT=0

: > "$OUTPUT"

while IFS= read -r -d '' path; do
  [[ -n "$path" ]] || continue
  if [[ ! -f "$path" ]]; then
    echo "ERROR=Listed file does not exist: $path" >&2
    exit 1
  fi
  bytes=$(wc -c <"$path" | tr -d '[:space:]')
  lines=$(wc -l <"$path" | tr -d '[:space:]')
  printf '%s\t%s\t%s\n' "$path" "$bytes" "$lines" >> "$OUTPUT"
  TOTAL_BYTES=$(( TOTAL_BYTES + bytes ))
  TOTAL_LINES=$(( TOTAL_LINES + lines ))
  FILE_COUNT=$(( FILE_COUNT + 1 ))
done < "$INPUT"

printf 'TOTAL_BYTES=%s\n' "$TOTAL_BYTES"
printf 'TOTAL_LINES=%s\n' "$TOTAL_LINES"
printf 'FILE_COUNT=%s\n' "$FILE_COUNT"
