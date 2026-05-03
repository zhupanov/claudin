#!/usr/bin/env bash
# test-render-findings-batch.sh — Offline regression harness for render-findings-batch.sh.
#
# Feeds canned final-report fixtures to the helper and asserts:
#   - exit code matches expectation,
#   - COUNT=<N> on stdout matches expectation,
#   - the emitted sidecar round-trips through skills/issue/scripts/parse-input.sh
#     (ITEMS_TOTAL matches COUNT and no MALFORMED items appear).
#
# Wired into `make lint` via the `test-render-findings-batch` target.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SCRIPT="$REPO_ROOT/skills/research/scripts/render-findings-batch.sh"
PARSE_INPUT="$REPO_ROOT/skills/issue/scripts/parse-input.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: helper script not found or not executable: $SCRIPT" >&2
  exit 1
fi
if [[ ! -x "$PARSE_INPUT" ]]; then
  echo "FAIL: parse-input.sh not found or not executable (cross-skill round-trip dep): $PARSE_INPUT" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d -t test-render-findings-batch.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0
CASE_NUM=0

# Write a research-question file used by every case.
RQ_FILE="$TMPDIR_TEST/research-question.txt"
echo "Test research question" > "$RQ_FILE"

# run_case <name> <report-content> <expected-exit> <expected-count>
# When expected-count > 0, the case also asserts a parse-input.sh round-trip
# (ITEMS_TOTAL matches expected-count and no MALFORMED items).
run_case() {
  local name="$1"
  local report_content="$2"
  local expected_exit="$3"
  local expected_count="$4"

  CASE_NUM=$((CASE_NUM + 1))
  local report_file="$TMPDIR_TEST/case${CASE_NUM}-report.md"
  local out_file="$TMPDIR_TEST/case${CASE_NUM}-out.md"

  printf '%s' "$report_content" > "$report_file"

  local stdout_capture
  local actual_exit=0
  stdout_capture="$(bash "$SCRIPT" \
    --report "$report_file" --output "$out_file" \
    --research-question-file "$RQ_FILE" \
    --branch test-branch --commit deadbee 2>/dev/null)" || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL [$name]: expected exit=$expected_exit, got exit=$actual_exit. stdout:" >&2
    printf '%s\n' "$stdout_capture" >&2
    FAIL=$((FAIL + 1))
    return
  fi

  local actual_count
  actual_count="$(grep -E '^COUNT=' <<< "$stdout_capture" | head -1 | sed 's/^COUNT=//')"
  if [[ "$actual_count" != "$expected_count" ]]; then
    echo "FAIL [$name]: expected COUNT=$expected_count, got COUNT=$actual_count" >&2
    FAIL=$((FAIL + 1))
    return
  fi

  # Round-trip assertion — only when at least one item is expected.
  if [[ "$expected_count" -gt 0 ]]; then
    local parsed_dir="$TMPDIR_TEST/case${CASE_NUM}-parsed"
    local parse_stdout
    parse_stdout="$(bash "$PARSE_INPUT" --input-file "$out_file" --output-dir "$parsed_dir" 2>&1)"
    local items_total
    items_total="$(grep -E '^ITEMS_TOTAL=' <<< "$parse_stdout" | sed 's/^ITEMS_TOTAL=//')"
    if [[ "$items_total" != "$expected_count" ]]; then
      echo "FAIL [$name]: round-trip ITEMS_TOTAL=$items_total, expected $expected_count" >&2
      printf '%s\n' "$parse_stdout" >&2
      FAIL=$((FAIL + 1))
      return
    fi
    if grep -Eq '^ITEM_[0-9]+_MALFORMED=true' <<< "$parse_stdout"; then
      echo "FAIL [$name]: round-trip emitted MALFORMED items:" >&2
      grep -E '^ITEM_[0-9]+_(TITLE|MALFORMED)=' <<< "$parse_stdout" >&2
      FAIL=$((FAIL + 1))
      return
    fi
  fi

  PASS=$((PASS + 1))
}

# ---------------------------------------------------------------------------
# Fixtures
# ---------------------------------------------------------------------------

# Case 1: numbered list — three findings.
read -r -d '' FIXTURE_NUMBERED <<'EOF' || true
## Research Report

### Findings Summary

1. First finding here. With detail.
2. Second finding text.
3. Third finding mentioning `code`.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Feasible.

### Key Files and Areas
- file-a.md
- file-b.md

### Open Questions
EOF
run_case "numbered list" "$FIXTURE_NUMBERED" 0 3

# Case 2: top-level bulleted — two findings.
read -r -d '' FIXTURE_BULLETED <<'EOF' || true
## Research Report

### Findings Summary

- First bullet finding.
- Second bullet finding with more text.

### Risk Assessment
Medium

### Difficulty Estimate
M

### Feasibility Verdict
Yes

### Key Files and Areas
file.md

### Open Questions
- Question 1
EOF
run_case "bulleted list" "$FIXTURE_BULLETED" 0 2

# Case 3: paragraph-per-item.
read -r -d '' FIXTURE_PARAGRAPH <<'EOF' || true
## Research Report

### Findings Summary

First finding paragraph. With multiple sentences. And more.

Second finding paragraph here.

### Risk Assessment
High

### Difficulty Estimate
L

### Feasibility Verdict
Yes

### Key Files and Areas
- foo.md

### Open Questions
EOF
run_case "paragraph-per-item" "$FIXTURE_PARAGRAPH" 0 2

# Case 4: empty Findings Summary section.
read -r -d '' FIXTURE_EMPTY <<'EOF' || true
## Research Report

### Findings Summary

### Risk Assessment
N/A

### Difficulty Estimate
N/A

### Feasibility Verdict
N/A

### Key Files and Areas

### Open Questions
EOF
run_case "empty Findings Summary" "$FIXTURE_EMPTY" 3 0

# Case 5: missing Findings Summary entirely.
read -r -d '' FIXTURE_MISSING <<'EOF' || true
## Research Report

### Risk Assessment
N/A
EOF
run_case "missing Findings Summary" "$FIXTURE_MISSING" 3 0

# Case 6: planner-mode nested `#### Subquestion N` headings inside the section.
read -r -d '' FIXTURE_PLANNER <<'EOF' || true
## Research Report

### Findings Summary

#### Subquestion 1: How does X work?

1. Finding A about X.
2. Finding B about X.

#### Subquestion 2: How does Y work?

1. Finding C about Y.

### Risk Assessment
Low

### Difficulty Estimate
M

### Feasibility Verdict
Yes

### Key Files and Areas
- a.md
- b.md

### Open Questions
EOF
run_case "planner-mode nested subquestions" "$FIXTURE_PLANNER" 0 3

# Case 7: code fence containing `### Foo` line — should NOT terminate the section.
read -r -d '' FIXTURE_FENCED <<'EOF' || true
## Research Report

### Findings Summary

1. First finding. Has fenced code:

   ```
   ### NotAHeading
   ## NorThis
   ```
2. Second finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "fenced code with ### inside" "$FIXTURE_FENCED" 0 2

# Case 8: body line beginning with `### Foo` at column 0 — must be escaped to
# `\### Foo` so parse-input.sh round-trip preserves item count.
read -r -d '' FIXTURE_BODY_ESCAPE <<'EOF' || true
## Research Report

### Findings Summary

- First finding. The body has a literal heading-shaped line below.
### Bad Header Line
This line follows the heading-shaped one inside the first finding's body.
- Second finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "body-line ### escape" "$FIXTURE_BODY_ESCAPE" 0 2

# Case 9: empty-title fallback — first sentence has no `. /! /? ` in first 80
# chars and stripping punctuation yields empty.
read -r -d '' FIXTURE_TITLE_FALLBACK <<'EOF' || true
## Research Report

### Findings Summary

- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!?
- Normal second finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "empty-title fallback (Finding N)" "$FIXTURE_TITLE_FALLBACK" 0 2

# Case 10: special characters in finding text — backticks, dollars, asterisks.
read -r -d '' FIXTURE_SPECIAL <<'EOF' || true
## Research Report

### Findings Summary

1. First finding with `code` and $variable and **bold**.
2. Second finding has "quotes" and 'apostrophes'.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "special characters in body" "$FIXTURE_SPECIAL" 0 2

# Case 13 (#510 review FINDING_2): body line with `###<tab>Foo`.
# parse-input.sh:393's regex is `^\#\#\#[[:space:]]+`, which matches tab too.
# Without the FINDING_2 fix, this line would slip past the escape and split
# items downstream.
read -r -d '' FIXTURE_TAB_HEADER <<EOF || true
## Research Report

### Findings Summary

- First finding here. Body has tab-after-###:
###	Tabbed
- Second finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "tab-after-### body escape (FINDING_2)" "$FIXTURE_TAB_HEADER" 0 2

# Case 14 (#510 review FINDING_5): indented fenced block (3-space prefix)
# inside a bulleted item's body. Without the fix, the inner `### Foo` line
# would terminate the section prematurely or escape spuriously.
read -r -d '' FIXTURE_INDENTED_FENCE <<'EOF' || true
## Research Report

### Findings Summary

- First finding. Has indented fenced code:

   ```
   ### NotAHeading
   ```
- Second finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "indented fence with ### inside (FINDING_5)" "$FIXTURE_INDENTED_FENCE" 0 2

# Case 12: multi-paragraph bulleted item.
read -r -d '' FIXTURE_MULTILINE_BULLETS <<'EOF' || true
## Research Report

### Findings Summary

- First finding. With multiple sentences across the item.
  Continuation line for first finding.
- Second finding here.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- f.md

### Open Questions
EOF
run_case "multi-line bulleted continuation" "$FIXTURE_MULTILINE_BULLETS" 0 2

# Case 15 (#745): finding body containing an indented nested 1./2. enumeration
# must NOT promote the nested lines into separate top-level findings.
read -r -d '' FIXTURE_NESTED_NUMBERED <<'EOF' || true
## Research Report

### Findings Summary

1. First finding with a nested enumeration in its body:
   1. nested step one
   2. nested step two

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- g.md

### Open Questions
EOF
run_case "nested-numbered sublist (#745)" "$FIXTURE_NESTED_NUMBERED" 0 1

# Case 16 (#745 follow-up): two top-level numbered findings where the first has
# a nested 1./2. enumeration in its body. Verifies the post-flush re-init path:
# nested lines stay as continuation, then the second top-level `2.` re-flushes.
read -r -d '' FIXTURE_NESTED_THEN_TOPLEVEL <<'EOF' || true
## Research Report

### Findings Summary

1. First finding with a nested enumeration in its body:
   1. nested step one
   2. nested step two
2. Second top-level finding.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- h.md

### Open Questions
EOF
run_case "nested then top-level sibling (#745)" "$FIXTURE_NESTED_THEN_TOPLEVEL" 0 2

# Case 17 (#746): a column-0 non-planner `#### Some heading` line inside a
# finding's body must NOT be discarded by the splitter. Only `#### Subquestion
# <N>` planner organizers should flush; all other `####` lines are body
# content. Column-0 placement is essential — the old broad `^####` regex would
# have matched a column-0 line and silently dropped it, splitting the finding
# into two and corrupting COUNT. An indented `####` line never matched the old
# regex, so an indented fixture would not exercise the regression path.
read -r -d '' FIXTURE_NONPLANNER_HASH <<'EOF' || true
## Research Report

### Findings Summary

1. First finding with a subsection heading in its body.

#### Notes on the data
The notes section contains additional context that should not be lost.

### Risk Assessment
Low

### Difficulty Estimate
S

### Feasibility Verdict
Yes

### Key Files and Areas
- i.md

### Open Questions
EOF
run_case "non-planner #### preserved (#746)" "$FIXTURE_NONPLANNER_HASH" 0 1
# Post-condition (#746 FINDING_1): the `#### Notes on the data` heading must
# literally survive in the rendered sidecar. `run_case` only checks COUNT and
# round-trip ITEMS_TOTAL — neither catches data loss when a `####` line is
# silently dropped from the body. A standalone grep against the output file
# is the only path that traps the regression the fix targets.
if ! grep -Fq "#### Notes on the data" "$TMPDIR_TEST/case${CASE_NUM}-out.md"; then
  echo "FAIL [non-planner #### preserved (#746)]: '#### Notes on the data' missing from rendered sidecar" >&2
  FAIL=$((FAIL + 1))
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

if [[ "$FAIL" -gt 0 ]]; then
  echo "" >&2
  echo "FAIL: $FAIL of $((PASS + FAIL)) cases failed" >&2
  exit 1
fi

echo "PASS: test-render-findings-batch.sh — all $PASS cases passed"
exit 0
