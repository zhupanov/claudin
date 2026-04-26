#!/usr/bin/env bash
# render-umbrella-body.sh — compose the umbrella issue body from the LLM-supplied
# summary plus the resolved children TSV.
#
# Inputs: --tmpdir DIR --summary-file FILE --children-file FILE
#   summary.txt: a one-paragraph plain-text summary (≤ 4 sentences).
#   children.tsv: rows of "<number>\t<title>\t<url>", in pieces order.
# Output stdout: UMBRELLA_BODY_FILE=<path>, UMBRELLA_TITLE_HINT=<derived>.

set -euo pipefail

TMPDIR=""
SUMMARY_FILE=""
CHILDREN_FILE=""

while [ "$#" -gt 0 ]; do
  case "$1" in
    --tmpdir) TMPDIR="$2"; shift 2 ;;
    --summary-file) SUMMARY_FILE="$2"; shift 2 ;;
    --children-file) CHILDREN_FILE="$2"; shift 2 ;;
    *) echo "ERROR=Unknown flag: $1" >&2; exit 1 ;;
  esac
done

if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ]; then
  echo "ERROR=--tmpdir is required and must exist" >&2; exit 1
fi
if [ -z "$SUMMARY_FILE" ] || [ ! -s "$SUMMARY_FILE" ]; then
  echo "ERROR=--summary-file is required and must be non-empty" >&2; exit 1
fi
if [ -z "$CHILDREN_FILE" ] || [ ! -s "$CHILDREN_FILE" ]; then
  echo "ERROR=--children-file is required and must be non-empty" >&2; exit 1
fi

# Validate children.tsv: each row has exactly 3 tab-separated fields, first numeric.
bad_row=$(awk -F'\t' 'NF != 3 || $1 !~ /^[0-9]+$/ { print NR ": " $0; exit }' "$CHILDREN_FILE")
if [ -n "$bad_row" ]; then
  printf 'ERROR=children.tsv malformed at line %s (expected "<number><TAB><title><TAB><url>")\n' "$bad_row" >&2; exit 1
fi

OUT="$TMPDIR/umbrella-body.md"

# Derive title hint from the first sentence of the summary (≤ 80 chars, ellipsis on overflow).
TITLE_HINT=$(awk '
  {
    gsub(/\r/, "")
    line = line " " $0
  }
  END {
    sub(/^ +/, "", line)
    # First sentence: up to first ". " or end of buffer.
    n = index(line, ". ")
    if (n > 0) sentence = substr(line, 1, n - 1); else sentence = line
    if (length(sentence) > 80) {
      # Truncate at last whitespace before col 80, append ellipsis.
      cut = substr(sentence, 1, 80)
      pos = match(cut, /[^ ]+$/)
      if (pos > 1) cut = substr(cut, 1, pos - 2)
      printf "%s…", cut
    } else {
      printf "%s", sentence
    }
  }
' "$SUMMARY_FILE")

# Compose body.
{
  printf 'Umbrella tracking issue.\n\n'
  printf '## Summary\n\n'
  cat "$SUMMARY_FILE"
  printf '\n\n## Children\n\n'
  awk -F'\t' '{ printf "- [ ] #%s — %s\n", $1, $2 }' "$CHILDREN_FILE"
  printf '\n'
} > "$OUT"

printf 'UMBRELLA_BODY_FILE=%s\n' "$OUT"
printf 'UMBRELLA_TITLE_HINT=%s\n' "$TITLE_HINT"
