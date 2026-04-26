#!/usr/bin/env bash
# test-run-research-planner.sh — Offline regression harness for run-research-planner.sh.
#
# Feeds canned planner outputs to the validator and asserts exit code +
# REASON / COUNT / OUTPUT lines match the contract in run-research-planner.md.
#
# Wired into `make lint` via the `test-run-research-planner` target.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SCRIPT="$REPO_ROOT/skills/research/scripts/run-research-planner.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: validator script not found or not executable: $SCRIPT" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d -t test-run-research-planner.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0
CASE_NUM=0

# run_case <case-name> <raw-content> <expected-exit> <expected-pattern>
# expected-pattern is a grep -E regex matched against captured stdout.
run_case() {
  local name="$1"
  local raw_content="$2"
  local expected_exit="$3"
  local expected_pattern="$4"

  CASE_NUM=$((CASE_NUM + 1))
  local raw_file="$TMPDIR_TEST/case${CASE_NUM}-raw.txt"
  local out_file="$TMPDIR_TEST/case${CASE_NUM}-out.txt"

  printf '%s' "$raw_content" > "$raw_file"

  local stdout_capture
  local actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --raw "$raw_file" --output "$out_file" 2>/dev/null)" || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL [$name]: expected exit=$expected_exit, got exit=$actual_exit (stdout: $stdout_capture)" >&2
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -Eq "$expected_pattern" <<< "$stdout_capture"; then
    echo "FAIL [$name]: stdout did not match pattern '$expected_pattern'. Got:" >&2
    printf '%s\n' "$stdout_capture" >&2
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# ---------- Success cases ----------

# Case: 2 subquestions, plain.
run_case "count-2-plain" \
  $'What is X?\nWhat is Y?\n' \
  0 \
  '^COUNT=2$'

# Case: 3 subquestions, plain.
run_case "count-3-plain" \
  $'What is X?\nWhat is Y?\nWhat is Z?\n' \
  0 \
  '^COUNT=3$'

# Case: 4 subquestions, plain.
run_case "count-4-plain" \
  $'What is A?\nWhat is B?\nWhat is C?\nWhat is D?\n' \
  0 \
  '^COUNT=4$'

# Case: leading bullets stripped, still 3 questions.
run_case "leading-bullets" \
  $'- What is X?\n- What is Y?\n- What is Z?\n' \
  0 \
  '^COUNT=3$'

# Case: leading asterisks stripped.
run_case "leading-asterisks" \
  $'* What is X?\n* What is Y?\n' \
  0 \
  '^COUNT=2$'

# Case: leading + trailing whitespace trimmed.
run_case "whitespace-trim" \
  $'  What is X?  \n\tWhat is Y?\t\n' \
  0 \
  '^COUNT=2$'

# Case: empty lines dropped between question lines.
run_case "empty-lines-dropped" \
  $'\n\nWhat is X?\n\n\nWhat is Y?\n\n' \
  0 \
  '^COUNT=2$'

# Case: prose preamble line dropped (does not end with ?), 2 question lines retained.
# Defends against fail-open on planner replies like "Here are the subquestions: ..." + 2 questions.
run_case "prose-preamble-dropped" \
  $'Here are the subquestions:\nWhat is X?\nWhat is Y?\n' \
  0 \
  '^COUNT=2$'

# Case: prose preamble + bullets, 3 retained.
run_case "prose-preamble-and-bullets" \
  $'The following are the subquestions:\n- What is X?\n- What is Y?\n- What is Z?\n' \
  0 \
  '^COUNT=3$'

# Case: numeric-prefix text NOT stripped (deliberately — defensive simplification per design).
# A subquestion whose text legitimately starts with a number is preserved.
run_case "numeric-prefix-preserved" \
  $'1980s mainframe deployments — what survived?\nWhat is Y?\n' \
  0 \
  '^COUNT=2$'

# ---------- Failure cases ----------

# Case: empty file.
run_case "empty-file" "" 1 '^REASON=empty_input$'

# Case: only whitespace.
run_case "whitespace-only" $'   \n\t\n  \n' 1 '^REASON=count_below_minimum$'

# Case: 1 subquestion (below minimum).
run_case "count-1" $'What is X?\n' 1 '^REASON=count_below_minimum$'

# Case: 5 subquestions (above maximum).
run_case "count-5" \
  $'What is A?\nWhat is B?\nWhat is C?\nWhat is D?\nWhat is E?\n' \
  1 \
  '^REASON=count_above_maximum$'

# Case: 6 subquestions (well above maximum).
run_case "count-6" \
  $'What is A?\nWhat is B?\nWhat is C?\nWhat is D?\nWhat is E?\nWhat is F?\n' \
  1 \
  '^REASON=count_above_maximum$'

# Case: all lines lack `?` — fail-closed against pure prose.
run_case "no-question-marks" \
  $'This is a paragraph.\nIt continues here.\nAnd a third sentence.\n' \
  1 \
  '^REASON=count_below_minimum$'

# Case: subquestion contains literal `||` — rejected to protect lane-assignments.txt's
# unquoted `||` in-cell delimiter from silent mis-splitting at rehydration.
run_case "delimiter-collision-basic" \
  $'What is X?\nWhat is X || Y?\n' \
  1 \
  '^REASON=delimiter_collision$'

# Case: `||` at end of a retained line — same outcome.
run_case "delimiter-collision-at-boundary" \
  $'What is A?\nWhat is B?\nWhat is C ||?\n' \
  1 \
  '^REASON=delimiter_collision$'

# Case: `||` rejection precedes count gate — operator with both `||` AND too many lines
# sees the more actionable `delimiter_collision` token, not `count_above_maximum`.
run_case "delimiter-collision-precedes-count" \
  $'What is A?\nWhat is B?\nWhat is C?\nWhat is D?\nWhat is E || F?\n' \
  1 \
  '^REASON=delimiter_collision$'

# Case: single `|` is fine — only the literal substring `||` is forbidden.
run_case "single-pipe-allowed" \
  $'What is X | Y in regex?\nWhat is Z?\n' \
  0 \
  '^COUNT=2$'

# Case: control characters stripped, 2 questions retained.
# (Insert a literal BEL character between the leading content and the rest.)
run_case "control-chars-stripped" \
  $'What is\bX?\nWhat is\aY?\n' \
  0 \
  '^COUNT=2$'

# ---------- Argument-error cases ----------

# Case: missing --raw argument.
{
  CASE_NUM=$((CASE_NUM + 1))
  out_file="$TMPDIR_TEST/case${CASE_NUM}-out.txt"
  actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --output "$out_file" 2>/dev/null)" || actual_exit=$?
  if [[ "$actual_exit" -eq 2 ]] && grep -Eq '^REASON=missing_arg$' <<< "$stdout_capture"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL [missing-raw]: expected exit=2 + REASON=missing_arg, got exit=$actual_exit (stdout: $stdout_capture)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Case: missing --output argument.
{
  CASE_NUM=$((CASE_NUM + 1))
  raw_file="$TMPDIR_TEST/case${CASE_NUM}-raw.txt"
  printf 'What is X?\nWhat is Y?\n' > "$raw_file"
  actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --raw "$raw_file" 2>/dev/null)" || actual_exit=$?
  if [[ "$actual_exit" -eq 2 ]] && grep -Eq '^REASON=missing_arg$' <<< "$stdout_capture"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL [missing-output]: expected exit=2 + REASON=missing_arg, got exit=$actual_exit (stdout: $stdout_capture)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Case: --raw points at a non-existent file.
{
  CASE_NUM=$((CASE_NUM + 1))
  raw_file="$TMPDIR_TEST/does-not-exist.txt"
  out_file="$TMPDIR_TEST/case${CASE_NUM}-out.txt"
  actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --raw "$raw_file" --output "$out_file" 2>/dev/null)" || actual_exit=$?
  if [[ "$actual_exit" -eq 1 ]] && grep -Eq '^REASON=empty_input$' <<< "$stdout_capture"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL [missing-raw-file]: expected exit=1 + REASON=empty_input, got exit=$actual_exit (stdout: $stdout_capture)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Case: --output's parent directory does not exist.
{
  CASE_NUM=$((CASE_NUM + 1))
  raw_file="$TMPDIR_TEST/case${CASE_NUM}-raw.txt"
  printf 'What is X?\nWhat is Y?\n' > "$raw_file"
  out_file="$TMPDIR_TEST/nonexistent-dir/out.txt"
  actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --raw "$raw_file" --output "$out_file" 2>/dev/null)" || actual_exit=$?
  if [[ "$actual_exit" -eq 2 ]] && grep -Eq '^REASON=bad_path$' <<< "$stdout_capture"; then
    PASS=$((PASS + 1))
  else
    echo "FAIL [bad-output-dir]: expected exit=2 + REASON=bad_path, got exit=$actual_exit (stdout: $stdout_capture)" >&2
    FAIL=$((FAIL + 1))
  fi
}

# ---------- Output content verification ----------

# Verify that on a known-good run, --output contains exactly the retained lines.
{
  CASE_NUM=$((CASE_NUM + 1))
  raw_file="$TMPDIR_TEST/case${CASE_NUM}-raw.txt"
  out_file="$TMPDIR_TEST/case${CASE_NUM}-out.txt"
  printf -- '- What is X?\n- What is Y?\nHere is preamble:\n- What is Z?\n' > "$raw_file"
  actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --raw "$raw_file" --output "$out_file" 2>/dev/null)" || actual_exit=$?
  # Compare via diff against a temp expected file (avoids trailing-newline trim from
  # bash command substitution `$(cat ...)`).
  expected_file="$TMPDIR_TEST/case${CASE_NUM}-expected.txt"
  printf 'What is X?\nWhat is Y?\nWhat is Z?\n' > "$expected_file"
  if [[ "$actual_exit" -eq 0 ]] && grep -Eq '^COUNT=3$' <<< "$stdout_capture" && diff -q "$expected_file" "$out_file" > /dev/null 2>&1; then
    PASS=$((PASS + 1))
  else
    echo "FAIL [output-content]: expected COUNT=3 + 3 retained lines, got exit=$actual_exit, stdout=$stdout_capture, output:" >&2
    cat "$out_file" >&2
    FAIL=$((FAIL + 1))
  fi
}

# ---------- Summary ----------

TOTAL=$((PASS + FAIL))
echo "test-run-research-planner.sh: $PASS / $TOTAL passed"

if (( FAIL > 0 )); then
  echo "FAIL: $FAIL test case(s) failed" >&2
  exit 1
fi

exit 0
