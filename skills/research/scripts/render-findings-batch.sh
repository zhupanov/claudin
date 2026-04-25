#!/usr/bin/env bash
# render-findings-batch.sh — Extract findings from a /research final report and
# emit one `### <title>` block per finding to a batch-markdown file consumable
# by `skills/issue/scripts/parse-input.sh` (generic `### <title>` + body
# fallback path).
#
# Consumed by /research Step 3 after the rendered final report is written to
# $RESEARCH_TMPDIR/research-report-final.md. The orchestrator invokes this
# script with the report path; the script slices `### Findings Summary`,
# extracts global metadata sections (Risk / Difficulty / Feasibility / Key
# Files / Open Questions), runs the three-tier heuristic ladder
# (numbered → top-level bulleted → paragraph-per-item), and emits items.
#
# Stdout (machine output only):
#   On success (>=1 finding): COUNT=<N> on a single line, exit 0.
#   On empty findings: COUNT=0, exit 3 (sidecar still written, empty file).
#   On usage error: exit 1 with usage on stderr.
#   On --report missing: exit 2 with diagnostic on stderr.
#
# Stderr: human diagnostics. On exit 3, a warning text describing whether the
# Findings Summary section was empty or absent.
#
# See render-findings-batch.md for the full contract.

set -euo pipefail

REPORT_PATH=""
OUTPUT_PATH=""
RESEARCH_QUESTION_FILE=""
BRANCH=""
COMMIT=""
QUICK_DISCLAIMER=""

usage() {
  cat >&2 <<'USAGE'
Usage: render-findings-batch.sh \
  --report <path> --output <path> \
  --research-question-file <path> --branch <value> --commit <value> \
  [--quick-disclaimer <text>]

  --report <path>                 Required. Rendered /research final report (with
                                  ### Findings Summary etc. sections).
  --output <path>                 Required. Sidecar destination.
  --research-question-file <path> Required. File whose first line is the research
                                  question, embedded in the audit-context line.
  --branch <value>                Required. Branch under audit (Source line).
  --commit <value>                Required. Head SHA at audit time (Source line).
  --quick-disclaimer <text>       Optional. When non-empty, prepended to each item
                                  body as the first content line. Used by Quick mode.

Exit 0 on success (>=1 finding emitted), 3 on empty findings (empty output file
written + stderr warning), 1 on usage error, 2 on --report missing.
USAGE
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --report) REPORT_PATH="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --output) OUTPUT_PATH="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --research-question-file) RESEARCH_QUESTION_FILE="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --branch) BRANCH="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --commit) COMMIT="${2:-}"; shift 2 || { usage; exit 1; } ;;
    --quick-disclaimer) QUICK_DISCLAIMER="${2:-}"; shift 2 || { usage; exit 1; } ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done

if [[ -z "$REPORT_PATH" || -z "$OUTPUT_PATH" || -z "$RESEARCH_QUESTION_FILE" \
      || -z "$BRANCH" || -z "$COMMIT" ]]; then
  echo "ERROR: --report, --output, --research-question-file, --branch, --commit are required" >&2
  usage
  exit 1
fi

if [[ ! -f "$REPORT_PATH" ]]; then
  echo "ERROR: report file not found: $REPORT_PATH" >&2
  exit 2
fi

# Audit context — first non-empty line of the research-question file. If file
# missing or empty, fall back to a literal placeholder.
RESEARCH_QUESTION=""
if [[ -f "$RESEARCH_QUESTION_FILE" ]]; then
  RESEARCH_QUESTION=$(awk 'NF{print; exit}' "$RESEARCH_QUESTION_FILE" || true)
fi
if [[ -z "$RESEARCH_QUESTION" ]]; then
  RESEARCH_QUESTION="(research question unavailable)"
fi

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# extract_section emits the body of a fenced-aware section bounded by
# `### Findings Summary` on the start side and any of the canonical "next
# top-level header" markers on the end side: `### Risk Assessment`,
# `### Difficulty Estimate`, `### Feasibility Verdict`, `### Key Files and Areas`,
# `### Open Questions`, or any `^## ` (top-level) header. Lines inside fenced
# code blocks (toggled by `^\`\`\``) are echoed verbatim and never trigger
# header detection. The starting `### Findings Summary` line itself is NOT
# included in the output.
extract_section() {
  local input="$1"
  local start_pattern="$2"
  shift 2
  local end_patterns=("$@")
  # Join end patterns with `|` (a character that never appears in a markdown
  # header line) so the awk -v variable carries no literal newlines.
  local ends_joined=""
  local p
  for p in "${end_patterns[@]}"; do
    if [[ -z "$ends_joined" ]]; then
      ends_joined="$p"
    else
      ends_joined="$ends_joined|$p"
    fi
  done
  awk -v start="$start_pattern" -v ends_str="$ends_joined" '
    BEGIN {
      n = split(ends_str, ends, "|")
      in_section = 0
      in_fence = 0
    }
    {
      # Toggle fence state on lines beginning exactly with three backticks.
      if ($0 ~ /^[[:space:]]*```/) {
        in_fence = 1 - in_fence
        if (in_section) print
        next
      }
      if (in_fence) {
        if (in_section) print
        next
      }
      if (!in_section) {
        if ($0 == start) { in_section = 1 }
        next
      }
      # in_section==1 and not in fence — check for end markers
      if ($0 ~ /^## /) { exit }
      for (i = 1; i <= n; i++) {
        if (length(ends[i]) > 0 && $0 == ends[i]) { exit }
      }
      print
    }
  ' "$input"
}

# extract_section_or_empty is the same as extract_section but returns empty
# (not a non-zero exit) when the section is absent. Detection of "absent"
# happens at the call site by checking whether the result has any non-blank
# lines.
extract_section_or_empty() {
  extract_section "$@"
}

FINDINGS=$(extract_section "$REPORT_PATH" "### Findings Summary" \
  "### Risk Assessment" "### Difficulty Estimate" "### Feasibility Verdict" \
  "### Key Files and Areas" "### Open Questions")

# Distinguish "section absent" from "section empty (zero meaningful lines)".
SECTION_ABSENT=0
if ! grep -q '^### Findings Summary$' "$REPORT_PATH"; then
  SECTION_ABSENT=1
fi

# Strip leading and trailing blank lines from FINDINGS for the empty check.
FINDINGS_TRIMMED=$(printf '%s' "$FINDINGS" | awk 'BEGIN{started=0} {
  if (!started && NF==0) next
  started=1
  buf[++n]=$0
} END{
  end=n; while (end>0 && buf[end] ~ /^[[:space:]]*$/) end--
  for (i=1;i<=end;i++) print buf[i]
}')

emit_empty() {
  : > "$OUTPUT_PATH"
  echo "COUNT=0"
  if [[ "$SECTION_ABSENT" -eq 1 ]]; then
    echo "WARNING: Findings Summary section not found in input (input may be malformed). The sidecar is empty; '/issue --input-file <path>' on it would create no issues." >&2
  else
    echo "WARNING: Findings Summary section is empty (zero findings). The sidecar is empty; '/issue --input-file <path>' on it would create no issues." >&2
  fi
  exit 3
}

if [[ -z "$FINDINGS_TRIMMED" ]]; then
  emit_empty
fi

# Extract metadata sections, fence-aware. Each is single-value (one section
# body). Trimmed of leading/trailing whitespace; collapsed paragraphs preserved
# as-is.
extract_meta() {
  local section_header="$1"
  local body
  body=$(extract_section_or_empty "$REPORT_PATH" "$section_header" \
    "### Risk Assessment" "### Difficulty Estimate" "### Feasibility Verdict" \
    "### Key Files and Areas" "### Open Questions")
  # Trim leading/trailing blanks and collapse multi-paragraph to single paragraph
  # for the metadata one-liner. For Files-touched and Open-Questions we want to
  # preserve list shape, so a separate path handles those (see below).
  printf '%s' "$body" | awk 'BEGIN{started=0} {
    if (!started && NF==0) next
    started=1
    buf[++n]=$0
  } END{
    end=n; while (end>0 && buf[end] ~ /^[[:space:]]*$/) end--
    for (i=1;i<=end;i++) print buf[i]
  }'
}

# A single-line meta value: collapses internal newlines to spaces, strips
# bullet markers if present.
flatten_meta() {
  local body
  body=$(extract_meta "$1")
  if [[ -z "$body" ]]; then
    printf 'N/A'
    return
  fi
  printf '%s' "$body" | awk '
    {
      # Strip leading list markers / blockquote markers.
      sub(/^[[:space:]]*[-*][[:space:]]*/, "")
      sub(/^[[:space:]]*>[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
    }
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (i > 1) printf " "
        printf "%s", lines[i]
      }
    }
  '
}

# Files-touched: keep comma-separated form. Bulleted list → join with `, `.
# Single line → keep as-is (after bullet strip).
flatten_files_touched() {
  local body
  body=$(extract_meta "### Key Files and Areas")
  if [[ -z "$body" ]]; then
    printf 'N/A'
    return
  fi
  printf '%s' "$body" | awk '
    {
      sub(/^[[:space:]]*[-*][[:space:]]*/, "")
      sub(/^[[:space:]]*>[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
    }
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (i > 1) printf ", "
        printf "%s", lines[i]
      }
    }
  '
}

# Open Questions: preserve as a single-line comma-joined summary for
# "**Open questions** (if any):" or empty if absent.
flatten_open_questions() {
  flatten_files_touched_inner "### Open Questions"
}

flatten_files_touched_inner() {
  local body
  body=$(extract_meta "$1")
  if [[ -z "$body" ]]; then
    printf ''
    return
  fi
  printf '%s' "$body" | awk '
    {
      sub(/^[[:space:]]*[-*][[:space:]]*/, "")
      sub(/^[[:space:]]*>[[:space:]]*/, "")
      gsub(/[[:space:]]+$/, "")
    }
    NF { lines[++n] = $0 }
    END {
      for (i = 1; i <= n; i++) {
        if (i > 1) printf "; "
        printf "%s", lines[i]
      }
    }
  '
}

RISK=$(flatten_meta "### Risk Assessment")
DIFFICULTY=$(flatten_meta "### Difficulty Estimate")
FEASIBILITY=$(flatten_meta "### Feasibility Verdict")
FILES_TOUCHED=$(flatten_files_touched)
OPEN_QUESTIONS=$(flatten_open_questions)

# Heuristic ladder: split FINDINGS_TRIMMED into items.
#  Tier 1 — numbered list at top level (lines starting with `^[[:space:]]*[0-9]+\.[[:space:]]`).
#           If at least one such line exists, treat each as a new item; lines between are continuations.
#  Tier 2 — top-level bulleted list (`^[[:space:]]*[-*][[:space:]]`, indent depth 0-1).
#  Tier 3 — paragraph-per-item (blank-line separated paragraphs).
ITEMS_FILE=$(mktemp -t rfb-items.XXXXXX)
ITEM_COUNT_FILE=$(mktemp -t rfb-count.XXXXXX)
trap 'rm -f "$ITEMS_FILE" "$ITEM_COUNT_FILE"' EXIT

printf '%s\n' "$FINDINGS_TRIMMED" | awk -v items_path="$ITEMS_FILE" -v count_path="$ITEM_COUNT_FILE" '
  function emit_item(text,    n) {
    if (text == "") return
    # Trim leading/trailing whitespace
    sub(/^[[:space:]]+/, "", text)
    sub(/[[:space:]]+$/, "", text)
    if (text == "") return
    n = ++item_count
    # Use a NUL byte boundary between items so multi-line bodies are preserved.
    printf "%s%c", text, 0 >> items_path
  }
  BEGIN {
    item_count = 0
    in_fence = 0
    mode = ""    # "" / "numbered" / "bulleted" / "paragraph"
    current = ""
    # First pass-equivalent: detect tier by examining each line outside fences.
  }
  {
    line = $0
    if (line ~ /^```/) {
      in_fence = 1 - in_fence
      if (current == "") current = line
      else current = current "\n" line
      next
    }
    if (in_fence) {
      if (current == "") current = line
      else current = current "\n" line
      next
    }
    # Skip sub-headings (lines starting with `#### ` or deeper) — these are
    # planner-mode section organizers (`#### Subquestion 1: ...`), not findings.
    # They flush any in-progress item without becoming items themselves.
    if (line ~ /^####/) {
      if (current != "") { emit_item(current); current = "" }
      next
    }
    is_numbered = (line ~ /^[[:space:]]*[0-9]+\.[[:space:]]/)
    is_bulleted = (line ~ /^[[:space:]]{0,2}[-*][[:space:]]/)
    if (mode == "") {
      if (is_numbered) {
        mode = "numbered"; current = line; next
      } else if (is_bulleted) {
        mode = "bulleted"; current = line; next
      } else if (NF > 0) {
        mode = "paragraph"; current = line; next
      } else {
        next
      }
    }
    # Adaptive: in any mode, a fresh top-level numbered/bulleted item flushes
    # the current item and starts a new one. This handles planner-mode
    # paragraphs interleaved with numbered lists, and lists following prose.
    if (is_numbered || is_bulleted) {
      if (current != "") { emit_item(current) }
      current = line
      mode = is_numbered ? "numbered" : "bulleted"
      next
    }
    # Continuation: blank lines flush in paragraph mode; in list modes blank
    # lines stay with the current item until another list marker arrives.
    if (mode == "paragraph") {
      if (NF == 0) {
        if (current != "") { emit_item(current); current = "" }
      } else {
        if (current == "") current = line
        else current = current "\n" line
      }
      next
    }
    # numbered/bulleted continuation
    if (current == "") current = line
    else current = current "\n" line
    next
  }
  END {
    emit_item(current)
    print item_count > count_path
  }
'

ITEM_COUNT=$(cat "$ITEM_COUNT_FILE")

if [[ "$ITEM_COUNT" == "0" ]]; then
  emit_empty
fi

# title_from_body extracts the first sentence (split on `. `, `! `, `? `, or
# first newline) of the input, truncated to 80 chars, with bullet/numbering
# markers stripped. Punctuation is stripped from the truncation tail. If the
# result is empty, returns the literal "Finding <N>".
title_from_body() {
  local body="$1"
  local n="$2"
  local first
  # Strip leading bullet/numbering and whitespace from the first line.
  first=$(printf '%s' "$body" | awk 'NR==1 {
    sub(/^[[:space:]]*[0-9]+\.[[:space:]]+/, "")
    sub(/^[[:space:]]*[-*][[:space:]]+/, "")
    sub(/^[[:space:]]+/, "")
    print
    exit
  }')
  # Take everything up to the first sentence terminator (`. `, `! `, `? `).
  # Use awk for portable substring handling.
  local sentence
  sentence=$(printf '%s' "$first" | awk '{
    n = length($0)
    out = $0
    for (i = 1; i <= n - 1; i++) {
      ch = substr($0, i, 1)
      next_ch = substr($0, i + 1, 1)
      if ((ch == "." || ch == "!" || ch == "?") && next_ch == " ") {
        out = substr($0, 1, i - 1)
        break
      }
    }
    print out
  }')
  # Truncate to 80 chars, then strip trailing punctuation/whitespace.
  if [[ ${#sentence} -gt 80 ]]; then
    sentence="${sentence:0:80}"
  fi
  # Strip trailing whitespace and punctuation.
  while [[ -n "$sentence" && "$sentence" =~ [[:space:][:punct:]]$ ]]; do
    sentence="${sentence%?}"
  done
  if [[ -z "$sentence" ]]; then
    sentence="Finding $n"
  fi
  printf '%s' "$sentence"
}

# escape_body_lines prefixes any line starting with `### ` with a backslash so
# `parse-input.sh`'s `^\#\#\#[[:space:]]+(.+)$` regex (line 393 of
# parse-input.sh) no longer matches it as a new-item boundary. Markdown
# rendering displays the line unchanged. Toggles `IN_FENCE` on `^\`\`\`` so
# code-block contents are NOT escaped.
escape_body_lines() {
  awk '
    BEGIN { in_fence = 0 }
    {
      if ($0 ~ /^[[:space:]]*```/) {
        in_fence = 1 - in_fence
        print
        next
      }
      # Match the parse-input.sh line 393 regex (any whitespace after the
      # three hashes), not just literal U+0020 space, so a body line with a
      # tab after the hashes does not slip past the escape and split items
      # downstream (#510 review FINDING_2).
      if (!in_fence && $0 ~ /^###[[:space:]]/) {
        print "\\" $0
        next
      }
      print
    }
  '
}

# Compose the output. Iterate over NUL-delimited items written by the awk
# splitter above.
: > "$OUTPUT_PATH"
i=0
while IFS= read -r -d '' item; do
  i=$((i + 1))
  title=$(title_from_body "$item" "$i")
  # Body lines: optional disclaimer, finding prose (escaped).
  prose_escaped=$(printf '%s\n' "$item" | escape_body_lines)
  {
    printf '### %s\n\n' "$title"
    if [[ -n "$QUICK_DISCLAIMER" ]]; then
      printf '%s\n\n' "$QUICK_DISCLAIMER"
    fi
    # shellcheck disable=SC2016 # backticks here are literal markdown (rendered as inline code in the issue body), NOT command substitution
    printf '**Source**: /research output, branch `%s` at `%s`, run %s\n' \
      "$BRANCH" "$COMMIT" "$TIMESTAMP"
    printf '**Risk**: %s\n' "$RISK"
    printf '**Difficulty**: %s\n' "$DIFFICULTY"
    printf '**Feasibility**: %s\n' "$FEASIBILITY"
    printf '**Files touched**: %s\n\n' "$FILES_TOUCHED"
    printf '%s\n' "$prose_escaped"
    if [[ -n "$OPEN_QUESTIONS" ]]; then
      printf '\n**Open questions** (if any): %s\n' "$OPEN_QUESTIONS"
    fi
    printf '\n---\n*This issue was filed from /research output. Audit context: %s*\n\n' \
      "$RESEARCH_QUESTION"
  } >> "$OUTPUT_PATH"
done < "$ITEMS_FILE"

echo "COUNT=$i"
exit 0
