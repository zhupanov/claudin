#!/usr/bin/env bash
# validate-pieces-json.sh — validates caller-supplied pieces.json dep-edge schema
#
# Usage: validate-pieces-json.sh --pieces-file <path> --count <N>
#
# Validates:
#   (a) valid JSON
#   (b) top-level array
#   (c) array length equals --count
#   (d) each entry has depends_on array of valid 1-based ints < entry index
#
# Does NOT validate title/body — those are the batch input's concern.
# Exits 0 on valid, exits 1 with ERROR=<msg> on invalid.
#
# See validate-pieces-json.md for the full contract.

set -euo pipefail

PIECES_FILE=""
COUNT=""

while [ $# -gt 0 ]; do
  case "$1" in
    --pieces-file)
      shift
      PIECES_FILE="${1:-}"
      ;;
    --count)
      shift
      COUNT="${1:-}"
      ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
  shift
done

if [ -z "$PIECES_FILE" ]; then
  echo "ERROR=--pieces-file is required" >&2
  exit 1
fi
if [ -z "$COUNT" ]; then
  echo "ERROR=--count is required" >&2
  exit 1
fi
case "$COUNT" in
  ''|*[!0-9]*)
    echo "ERROR=--count must be a non-negative integer; got '$COUNT'" >&2
    exit 1
    ;;
esac
if [ "$COUNT" -eq 0 ]; then
  echo "ERROR=--count must be >= 1; empty batch is structurally invalid" >&2
  exit 1
fi

if [ ! -f "$PIECES_FILE" ]; then
  echo "ERROR=pieces-json file not found: $PIECES_FILE" >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR=jq is required but was not found in PATH" >&2
  exit 1
fi

JQ_ERR=$(mktemp)
trap 'rm -f "$JQ_ERR"' EXIT

ACTUAL_LENGTH=$(jq 'length' "$PIECES_FILE" 2>"$JQ_ERR") || {
  reason=$(head -n 1 "$JQ_ERR" 2>/dev/null | sed -e 's/^jq: //' -e 's/[[:cntrl:]]//g')
  echo "ERROR=invalid pieces-json: ${reason:-jq parse failed}" >&2
  exit 1
}

ACTUAL_TYPE=$(jq -r 'type' "$PIECES_FILE" 2>/dev/null || true)
if [ "$ACTUAL_TYPE" != "array" ]; then
  echo "ERROR=invalid pieces-json: top-level value must be a JSON array, got ${ACTUAL_TYPE:-unknown}" >&2
  exit 1
fi

if [ "$ACTUAL_LENGTH" -ne "$COUNT" ]; then
  echo "ERROR=pieces-json length mismatch: expected $COUNT entries, got $ACTUAL_LENGTH" >&2
  exit 1
fi

for i in $(seq 0 $((ACTUAL_LENGTH - 1))); do
  deps_type=$(jq -r ".[$i].depends_on // [] | type" "$PIECES_FILE" 2>/dev/null || true)
  if [ "$deps_type" != "array" ]; then
    echo "ERROR=pieces-json entry $((i + 1)) field 'depends_on' must be an array" >&2
    exit 1
  fi
  bad_count=$(jq --argjson idx "$i" '
    .[$idx].depends_on // [] |
    map(select((type != "number") or (. != (. | floor)) or (. < 1) or (. > $idx))) |
    length
  ' "$PIECES_FILE" 2>"$JQ_ERR") || {
    reason=$(head -n 1 "$JQ_ERR" 2>/dev/null | sed -e 's/^jq: //' -e 's/[[:cntrl:]]//g')
    echo "ERROR=pieces-json entry $((i + 1)) dep-validation failed: ${reason:-jq error}" >&2
    exit 1
  }
  if [ "$bad_count" -gt 0 ]; then
    echo "ERROR=pieces-json entry $((i + 1)) has out-of-range depends_on values ($bad_count invalid; must be 1-based integers < entry index)" >&2
    exit 1
  fi
done
