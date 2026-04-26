#!/usr/bin/env bash
# test-classify-research-scale.sh — Offline regression harness for classify-research-scale.sh.
#
# Feeds canned question texts to the classifier and asserts exit code +
# SCALE=, REASON= lines match the contract in classify-research-scale.md.
#
# Wired into `make lint` via the `test-classify-research-scale` target.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
SCRIPT="$REPO_ROOT/skills/research/scripts/classify-research-scale.sh"

if [[ ! -x "$SCRIPT" ]]; then
  echo "FAIL: classifier script not found or not executable: $SCRIPT" >&2
  exit 1
fi

TMPDIR_TEST="$(mktemp -d -t test-classify-research-scale.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0
CASE_NUM=0

# run_case <case-name> <question-content> <expected-exit> <expected-pattern>
# expected-pattern is a grep -E regex matched against captured stdout.
run_case() {
  local name="$1"
  local question="$2"
  local expected_exit="$3"
  local expected_pattern="$4"

  CASE_NUM=$((CASE_NUM + 1))
  local question_file="$TMPDIR_TEST/case${CASE_NUM}-question.txt"
  local stderr_file="$TMPDIR_TEST/case${CASE_NUM}-stderr.txt"

  printf '%s' "$question" > "$question_file"

  # Capture stderr to a tempfile so it's available for failure diagnostics
  # (rather than swallowed unconditionally — addresses code review FINDING_6).
  local stdout_capture
  local actual_exit=0
  stdout_capture="$(bash "$SCRIPT" --question "$question_file" 2>"$stderr_file")" || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL [$name]: expected exit=$expected_exit, got exit=$actual_exit" >&2
    echo "       stdout: $stdout_capture" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "       stderr:" >&2
      sed 's/^/         /' "$stderr_file" >&2
    fi
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -E -q "$expected_pattern" <<<"$stdout_capture"; then
    echo "FAIL [$name]: stdout did not match pattern" >&2
    echo "       expected pattern: $expected_pattern" >&2
    echo "       actual stdout:    $stdout_capture" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "       stderr:" >&2
      sed 's/^/         /' "$stderr_file" >&2
    fi
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

# run_case_invocation <case-name> <expected-exit> <expected-pattern> [args...]
# Used for cases that need to test invocation forms (missing args, bad path)
# rather than question content. Trailing args[@] is allowed to be empty.
run_case_invocation() {
  local name="$1"
  local expected_exit="$2"
  local expected_pattern="$3"
  shift 3
  local -a args=("$@")

  CASE_NUM=$((CASE_NUM + 1))
  local stderr_file="$TMPDIR_TEST/case${CASE_NUM}-stderr.txt"

  # Capture stderr to a tempfile so it's available for failure diagnostics
  # (rather than swallowed unconditionally — addresses code review FINDING_6).
  local stdout_capture
  local actual_exit=0
  # The ${args[@]+"${args[@]}"} idiom works around `set -u` with an empty
  # array under bash 3.2 (macOS default).
  stdout_capture="$(bash "$SCRIPT" ${args[@]+"${args[@]}"} 2>"$stderr_file")" || actual_exit=$?

  if [[ "$actual_exit" -ne "$expected_exit" ]]; then
    echo "FAIL [$name]: expected exit=$expected_exit, got exit=$actual_exit" >&2
    echo "       stdout: $stdout_capture" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "       stderr:" >&2
      sed 's/^/         /' "$stderr_file" >&2
    fi
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -E -q "$expected_pattern" <<<"$stdout_capture"; then
    echo "FAIL [$name]: stdout did not match pattern" >&2
    echo "       expected pattern: $expected_pattern" >&2
    echo "       actual stdout:    $stdout_capture" >&2
    if [[ -s "$stderr_file" ]]; then
      echo "       stderr:" >&2
      sed 's/^/         /' "$stderr_file" >&2
    fi
    FAIL=$((FAIL + 1))
    return
  fi

  PASS=$((PASS + 1))
}

#-----------------------------------------------------------------------------
# Stage 1 — strong-deep signals
#-----------------------------------------------------------------------------

# 1a — length > 600 bytes triggers length_deep.
LONG_QUESTION="$(printf 'a%.0s' {1..650}) what is going on?"
run_case "length_deep_just_over_threshold" \
  "$LONG_QUESTION" 0 \
  '^SCALE=deep$'

# 1b — >=2 deep keywords triggers keyword_deep.
run_case "keyword_deep_compare_architecture" \
  "Compare the architecture of /research and /loop-review" 0 \
  '^SCALE=deep$'
run_case "keyword_deep_reason_token" \
  "Compare the architecture of /research and /loop-review" 0 \
  '^REASON=keyword_deep$'

# 1c — >=2 '?' triggers multi_part_deep.
run_case "multi_part_deep" \
  "What is X? And how does it interact with Y?" 0 \
  '^SCALE=deep$'
run_case "multi_part_deep_reason" \
  "What is X? And how does it interact with Y?" 0 \
  '^REASON=multi_part_deep$'

# 1b — single deep keyword does NOT fire (need >=2 hits).
# This question hits "compare" once and length<80 and one '?'; should NOT be deep.
run_case "single_deep_keyword_falls_through_to_standard_or_quick" \
  "How does this compare to that?" 0 \
  '^SCALE=standard$'

# vulnerab substring matches both "vulnerable" and "vulnerability" but counts as
# one keyword each occurrence. Two distinct deep words from the set fires deep.
run_case "deep_security_review_threat_model" \
  "Please do a security review and threat model of the auth flow." 0 \
  '^SCALE=deep$'

#-----------------------------------------------------------------------------
# Stage 2 — strong-quick signals (ALL must fire)
#-----------------------------------------------------------------------------

# 2 — short + lookup + single ? → quick.
run_case "lookup_quick_what_is" \
  "what is the value of FOO?" 0 \
  '^SCALE=quick$'
run_case "lookup_quick_reason" \
  "what is the value of FOO?" 0 \
  '^REASON=lookup_quick$'

run_case "lookup_quick_where_is" \
  "where is the deny-edit-write hook defined?" 0 \
  '^SCALE=quick$'

# A yes/no question without a lookup keyword falls through to standard
# (the asymmetric-conservatism direction) — `does` is deliberately excluded
# from the lookup set because it false-positives on "how does X work".
run_case "yes_no_question_falls_to_standard" \
  "does this repo use pre-commit?" 0 \
  '^SCALE=standard$'

run_case "lookup_quick_how_many" \
  "how many test harnesses ship?" 0 \
  '^SCALE=quick$'

# 2 — short + lookup but two '?' → multi_part_deep wins (Stage 1 priority).
run_case "two_questions_short_still_deep" \
  "what is X? what is Y?" 0 \
  '^SCALE=deep$'

# 2 — long lookup-style question (>=80 bytes) does NOT fire quick.
LONG_LOOKUP="what is the value of LARCH_TOKEN_RATE_PER_M and how does it interact with the cost column rendering in the token-tally script?"
run_case "long_lookup_falls_to_standard" \
  "$LONG_LOOKUP" 0 \
  '^SCALE=standard$'

# 2 — short non-lookup-keyword question → standard (Stage 2c fails).
run_case "short_no_lookup_keyword_standard" \
  "Should we refactor this?" 0 \
  '^SCALE=standard$'

# 2 — short lookup but contains a deep keyword → standard (Stage 2d fails).
# "audit" is a deep keyword.
run_case "short_lookup_with_deep_keyword_standard" \
  "what is the audit log location?" 0 \
  '^SCALE=standard$'

#-----------------------------------------------------------------------------
# Stage 3 — default standard
#-----------------------------------------------------------------------------

run_case "mid_length_explanatory_standard" \
  "How does the X system handle Y in production?" 0 \
  '^SCALE=standard$'
run_case "mid_length_explanatory_reason" \
  "How does the X system handle Y in production?" 0 \
  '^REASON=default_standard$'

#-----------------------------------------------------------------------------
# Failure modes
#-----------------------------------------------------------------------------

# Empty file → REASON=empty_input + exit 1.
run_case "empty_input" "" 1 '^REASON=empty_input$'

# Whitespace-only file → REASON=empty_input + exit 1.
run_case "whitespace_only_empty_input" "   $(printf '\t\n')   " 1 '^REASON=empty_input$'

# Missing --question arg → REASON=missing_arg + exit 2.
run_case_invocation "missing_question_arg" 2 '^REASON=missing_arg$'

# Unknown flag → REASON=missing_arg + exit 2.
run_case_invocation "unknown_arg" 2 '^REASON=missing_arg$' --bogus foo

# --question pointing at non-existent path → REASON=bad_path + exit 2.
run_case_invocation "bad_path_nonexistent" 2 '^REASON=bad_path$' \
  --question "$TMPDIR_TEST/does-not-exist.txt"

# --question pointing at a directory → REASON=bad_path + exit 2.
run_case_invocation "bad_path_directory" 2 '^REASON=bad_path$' \
  --question "$TMPDIR_TEST"

#-----------------------------------------------------------------------------
# Asymmetric conservatism — borderline cases default to standard, never quick
#-----------------------------------------------------------------------------

# A question that's short (<80 bytes), single ?, but no lookup keyword → standard.
run_case "borderline_short_single_q_no_lookup_standard" \
  "Why is this happening here?" 0 \
  '^SCALE=standard$'

# A question that has lookup keyword but is too long (>=80 bytes) → standard.
run_case "borderline_lookup_too_long_standard" \
  "what is the canonical way to handle empty input here in this script when wrapped?" 0 \
  '^SCALE=standard$'

#-----------------------------------------------------------------------------
# Summary
#-----------------------------------------------------------------------------

if (( FAIL > 0 )); then
  echo "" >&2
  echo "Result: $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "All $PASS test cases passed."
exit 0
