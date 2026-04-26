#!/usr/bin/env bash
# render-batch-input.sh — convert pieces.json into /issue --input-file batch markdown.
#
# Inputs: --tmpdir DIR (working dir) --pieces-file FILE (JSON array of {title, body, depends_on:[int,...]})
# Output stdout: BATCH_INPUT_FILE=<path>, PIECES_TOTAL=<N>, PIECE_<i>_TITLE=<…>, PIECE_<i>_DEPENDS_ON=<csv>.

set -euo pipefail

TMPDIR=""
PIECES_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tmpdir) TMPDIR="$2"; shift 2 ;;
    --pieces-file) PIECES_FILE="$2"; shift 2 ;;
    *) echo "ERROR=Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "ERROR=--tmpdir is required and must exist" >&2; exit 1
fi
if [ -z "$PIECES_FILE" ] || [ ! -s "$PIECES_FILE" ]; then
  echo "ERROR=--pieces-file is required and must be non-empty" >&2; exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "ERROR=jq is required for /umbrella batch-input rendering but was not found in PATH" >&2; exit 1
fi

# Validate JSON shape and count.
PIECES_TOTAL=$(jq 'length' "$PIECES_FILE")
if [ "$PIECES_TOTAL" -lt 2 ]; then
  echo "ERROR=pieces.json must contain at least 2 entries; got $PIECES_TOTAL" >&2; exit 1
fi

# Per-entry validation: title non-empty, body non-empty, depends_on is array of ints with values < entry-index.
for i in $(seq 0 $((PIECES_TOTAL - 1))); do
  title=$(jq -r ".[$i].title // empty" "$PIECES_FILE")
  body=$(jq -r ".[$i].body // empty" "$PIECES_FILE")
  if [ -z "$title" ]; then
    echo "ERROR=pieces.json entry $((i + 1)) is missing 'title'" >&2; exit 1
  fi
  if [ -z "$body" ]; then
    echo "ERROR=pieces.json entry $((i + 1)) is missing 'body'" >&2; exit 1
  fi
  # depends_on must be an array of numbers, each in [1, i].
  deps_type=$(jq -r ".[$i].depends_on // [] | type" "$PIECES_FILE")
  if [ "$deps_type" != "array" ]; then
    echo "ERROR=pieces.json entry $((i + 1)) field 'depends_on' must be an array" >&2; exit 1
  fi
  bad_deps=$(jq -r --argjson idx "$i" '
    .[$idx].depends_on // [] |
    map(select((type != "number") or (. < 1) or (. > $idx))) |
    @csv
  ' "$PIECES_FILE")
  if [ -n "$bad_deps" ] && [ "$bad_deps" != '""' ]; then
    echo "ERROR=pieces.json entry $((i + 1)) has out-of-range depends_on values: $bad_deps (must be 1-based ints < entry index)" >&2; exit 1
  fi
done

OUT="$TMPDIR/batch-input.md"
: > "$OUT"

for i in $(seq 0 $((PIECES_TOTAL - 1))); do
  title=$(jq -r ".[$i].title" "$PIECES_FILE")
  body=$(jq -r ".[$i].body" "$PIECES_FILE")
  {
    printf '### %s\n\n' "$title"
    printf '%s\n\n' "$body"
  } >> "$OUT"
done

printf 'BATCH_INPUT_FILE=%s\n' "$OUT"
printf 'PIECES_TOTAL=%s\n' "$PIECES_TOTAL"
for i in $(seq 0 $((PIECES_TOTAL - 1))); do
  title=$(jq -r ".[$i].title" "$PIECES_FILE")
  deps=$(jq -r ".[$i].depends_on // [] | map(tostring) | join(\",\")" "$PIECES_FILE")
  printf 'PIECE_%d_TITLE=%s\n' "$((i + 1))" "$title"
  printf 'PIECE_%d_DEPENDS_ON=%s\n' "$((i + 1))" "$deps"
done
