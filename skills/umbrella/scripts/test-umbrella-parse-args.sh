#!/usr/bin/env bash
# test-umbrella-parse-args.sh — regression harness for /umbrella's parse-args.sh.
#
# Pins the stdout grammar (LABELS_COUNT + LABEL_<i>, TITLE_PREFIX, REPO,
# CLOSED_WINDOW_DAYS, DRY_RUN, GO, DEBUG, INPUT_FILE, UMBRELLA_SUMMARY_FILE,
# TASK, UMBRELLA_TMPDIR), the frozen ERROR= templates, the quoting subset,
# the paired-flag and TASK-mutual-exclusion validation rules for --input-file
# / --umbrella-summary-file, and the TASK byte-preservation contract documented
# in scripts/parse-args.md.
#
# Run manually:
#   bash skills/umbrella/scripts/test-umbrella-parse-args.sh
# Wire into make lint via the `test-umbrella-parse-args` Makefile target
# (parallel to `test-umbrella-helpers`).

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
PARSER="$HERE/parse-args.sh"
TMP=$(mktemp -d -t test-umbrella-parse-args-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

# Strip the UMBRELLA_TMPDIR=... line from stdout so the per-test expected
# output is deterministic across runs (mktemp picks a fresh path each call).
# Also clean up the actual temp dir the parser created, to keep /tmp tidy
# and not interfere with other tests.
#
# Also strip INPUT_FILE= and UMBRELLA_SUMMARY_FILE= lines when their values
# are empty, so the 25 pre-existing assert_stdout test cases (which were
# authored before these flags existed) continue to match without churning
# every expected string. Tests that exercise the new flags use the dedicated
# assert_raw_stdout_contains helper below instead.
run_parser() {
  local args_str="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  local exit_code
  set +e
  bash "$PARSER" "$args_str" >"$stdout_file" 2>"$stderr_file"
  exit_code=$?
  set -e
  # Capture and remove the parser-owned tmpdir if one was emitted.
  local emitted
  emitted=$(sed -n 's/^UMBRELLA_TMPDIR=//p' "$stdout_file")
  if [ -n "$emitted" ] && [ -d "$emitted" ]; then
    rm -rf "$emitted"
  fi
  # Strip the UMBRELLA_TMPDIR= line so expected-output comparison is stable.
  # Also strip empty INPUT_FILE= / UMBRELLA_SUMMARY_FILE= lines so pre-existing
  # assert_stdout cases that don't pass the new flags keep matching.
  sed -i.bak \
    -e '/^UMBRELLA_TMPDIR=/d' \
    -e '/^INPUT_FILE=$/d' \
    -e '/^UMBRELLA_SUMMARY_FILE=$/d' \
    "$stdout_file"
  rm -f "$stdout_file.bak"
  printf '%s' "$exit_code"
}

# assert_raw_stdout_contains LABEL "ARGS" "EXPECTED_LINE"
# Asserts: parser exits 0, raw stdout (UMBRELLA_TMPDIR stripped, but
# INPUT_FILE= / UMBRELLA_SUMMARY_FILE= preserved) contains EXPECTED_LINE.
# Used by new-flag tests where we want to verify the new KV lines are emitted.
assert_raw_stdout_contains() {
  local label="$1"
  local args_str="$2"
  local expected_line="$3"
  local stdout_file="$TMP/stdout-raw"
  local stderr_file="$TMP/stderr-raw"
  set +e
  bash "$PARSER" "$args_str" >"$stdout_file" 2>"$stderr_file"
  local exit_code=$?
  set -e
  local emitted
  emitted=$(sed -n 's/^UMBRELLA_TMPDIR=//p' "$stdout_file")
  if [ -n "$emitted" ] && [ -d "$emitted" ]; then
    rm -rf "$emitted"
  fi
  if [ "$exit_code" != "0" ]; then
    printf '  ❌ %s — expected exit 0, got %s. stderr: %s\n' "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi
  if ! grep -qxF "$expected_line" "$stdout_file"; then
    printf '  ❌ %s — expected line not in stdout: %s\n' "$label" "$expected_line"
    printf '     full stdout:\n%s\n' "$(cat "$stdout_file")"
    FAIL=$((FAIL + 1))
    return
  fi
  printf '  ✅ %s\n' "$label"
  PASS=$((PASS + 1))
}

# assert_stdout LABEL "ARGS" "EXPECTED_STDOUT"
# Asserts: parser exits 0, stdout (minus UMBRELLA_TMPDIR line) equals EXPECTED.
assert_stdout() {
  local label="$1"
  local args_str="$2"
  local expected="$3"
  local stdout_file="$TMP/stdout"
  local stderr_file="$TMP/stderr"
  local exit_code
  exit_code=$(run_parser "$args_str" "$stdout_file" "$stderr_file")
  if [ "$exit_code" != "0" ]; then
    printf '  ❌ %s — expected exit 0, got %s. stderr: %s\n' "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi
  local got
  got=$(cat "$stdout_file")
  if [ "$got" = "$expected" ]; then
    printf '  ✅ %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  ❌ %s — stdout mismatch.\n' "$label"
    printf '     expected:\n%s\n' "$expected" | sed 's/^/       /'
    printf '     got:\n%s\n' "$got" | sed 's/^/       /'
    FAIL=$((FAIL + 1))
  fi
}

# assert_error LABEL "ARGS" "STDERR_SUBSTRING"
# Asserts: parser exits non-zero, stderr contains STDERR_SUBSTRING.
assert_error() {
  local label="$1"
  local args_str="$2"
  local needle="$3"
  local stdout_file="$TMP/stdout"
  local stderr_file="$TMP/stderr"
  local exit_code
  exit_code=$(run_parser "$args_str" "$stdout_file" "$stderr_file")
  if [ "$exit_code" = "0" ]; then
    printf '  ❌ %s — expected non-zero exit, got 0.\n' "$label"
    FAIL=$((FAIL + 1))
    return
  fi
  local stderr_content
  stderr_content=$(cat "$stderr_file")
  if printf '%s' "$stderr_content" | grep -q -F -- "$needle"; then
    printf '  ✅ %s — error path triggered\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  ❌ %s — stderr missing substring %q. stderr: %s\n' "$label" "$needle" "$stderr_content"
    FAIL=$((FAIL + 1))
  fi
}

echo "test-umbrella-parse-args.sh: parse-args.sh stdout grammar + lexer"

# Default scalar fields (used to compose expected stdouts below).
DEFAULTS_NO_LABELS=$'TITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=false'

# 1. Single --label foo
assert_stdout "case 1: single --label" \
  "--label foo" \
  "$(printf 'LABELS_COUNT=1\nLABEL_1=foo\n%s\nTASK=' "$DEFAULTS_NO_LABELS")"

# 2. Quoted whitespace in --label
assert_stdout "case 2: --label with quoted whitespace" \
  '--label "good first issue"' \
  "$(printf 'LABELS_COUNT=1\nLABEL_1=good first issue\n%s\nTASK=' "$DEFAULTS_NO_LABELS")"

# 3. Repeated --label flags → indexed LABEL_1, LABEL_2, LABEL_3
assert_stdout "case 3: repeated --label" \
  "--label foo --label bar --label baz" \
  "$(printf 'LABELS_COUNT=3\nLABEL_1=foo\nLABEL_2=bar\nLABEL_3=baz\n%s\nTASK=' "$DEFAULTS_NO_LABELS")"

# 4. Quoted whitespace in --title-prefix
assert_stdout "case 4: --title-prefix with quoted whitespace" \
  '--title-prefix "[Infra Work]"' \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=[Infra Work]\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=false\nTASK=')"

# 5. --repo
assert_stdout "case 5: --repo" \
  "--repo owner/repo" \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=owner/repo\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=false\nTASK=')"

# 6. --closed-window-days valid integer
assert_stdout "case 6: --closed-window-days 30" \
  "--closed-window-days 30" \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=30\nDRY_RUN=false\nGO=false\nDEBUG=false\nTASK=')"

# 7. --closed-window-days non-integer → error
assert_error "case 7: --closed-window-days non-integer" \
  "--closed-window-days notanumber" \
  "must be a non-negative integer"

# 8. Boolean flags
assert_stdout "case 8: boolean flags" \
  "--dry-run --go --debug" \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=true\nGO=true\nDEBUG=true\nTASK=')"

# 9. TASK whitespace preservation — multi-space + trailing spaces, NO leading
#    whitespace contamination.
assert_stdout "case 9: TASK preserves embedded and trailing whitespace" \
  "--label foo  hello   world  " \
  "$(printf 'LABELS_COUNT=1\nLABEL_1=foo\n%s\nTASK=hello   world  ' "$DEFAULTS_NO_LABELS")"

# 10. -- end-of-flags marker
assert_stdout "case 10: -- end-of-flags" \
  "--debug -- --not-a-flag rest" \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=true\nTASK=--not-a-flag rest')"

# 11. Unclosed double quote → error
assert_error "case 11: unclosed double quote" \
  '--label "unclosed' \
  "unclosed double quote"

# 12. Stray trailing backslash → error.
# (shellcheck SC1003 false-positive: we deliberately pass a literal trailing
# backslash to the parser; this is not a shell escape attempt.)
# shellcheck disable=SC1003
assert_error "case 12: stray trailing backslash" \
  '--label foo\' \
  "stray backslash"

# 13. Missing value for --label → error
assert_error "case 13: --label requires value" \
  "--label" \
  "--label requires a value"

# 14. Unknown flag → error
assert_error "case 14: unknown flag" \
  "--unknown-flag" \
  "Unknown flag"

# 15. Empty input
assert_stdout "case 15: empty input" \
  "" \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=false\nTASK=')"

# 16. Escaped quote inside double-quoted run.
assert_stdout 'case 16: --label with escaped quote inside double-quote' \
  '--label "good \"first\" issue"' \
  "$(printf 'LABELS_COUNT=1\nLABEL_1=good "first" issue\n%s\nTASK=' "$DEFAULTS_NO_LABELS")"

# 17. Unclosed single quote → error
assert_error "case 17: unclosed single quote" \
  "--label 'foo" \
  "unclosed single quote"

# 18. Embedded newline inside quoted value → error
assert_error "case 18: embedded newline in quoted value" \
  $'--label "foo\nbar"' \
  "embedded newline in quoted value"

# 19. LABEL value containing literal '=' — survives in stdout.
assert_stdout "case 19: --label with embedded '='" \
  '--label "priority=high"' \
  "$(printf 'LABELS_COUNT=1\nLABEL_1=priority=high\n%s\nTASK=' "$DEFAULTS_NO_LABELS")"

# 20. Quoted positional starting with '--' — phase 1 stops; TASK is verbatim.
assert_stdout "case 20: quoted positional starting with --" \
  '--debug "--not-a-flag" rest' \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=true\nTASK=%s' '"--not-a-flag" rest')"

# 21. Newline as unquoted separator outside quotes.
assert_stdout "case 21: newline as unquoted separator" \
  $'--label foo\n--label bar\nhello' \
  "$(printf 'LABELS_COUNT=2\nLABEL_1=foo\nLABEL_2=bar\n%s\nTASK=hello' "$DEFAULTS_NO_LABELS")"

# 22. Unbalanced quote inside TASK — verbatim, lexer does NOT validate TASK.
assert_stdout "case 22: unbalanced quote inside TASK (verbatim)" \
  '--debug investigate "broken' \
  "$(printf 'LABELS_COUNT=0\nTITLE_PREFIX=\nREPO=\nCLOSED_WINDOW_DAYS=\nDRY_RUN=false\nGO=false\nDEBUG=true\nTASK=%s' 'investigate "broken')"

# 23. Embedded newline in TASK → error (would break single-line KV grammar).
#     Repro from /review FINDING_1: --debug followed by "hello\nworld" task body
#     emits TASK=hello + worldon-next-line + UMBRELLA_TMPDIR=... → consumer break.
assert_error "case 23: embedded newline in TASK" \
  $'--debug hello\nworld' \
  "embedded newline in TASK"

# 24. Backslash-escaped newline in unquoted value → error.
#     Repro from /review FINDING_2: backslash escapes the unquoted-separator
#     behavior of newline, letting it through into LABEL_<i>= and breaking KV.
#     NOTE: this path uses a DISTINCT frozen template `embedded newline in
#     unquoted value` — do NOT "dedupe" the assertion against cases 18/25,
#     which deliberately keep `embedded newline in quoted value` for the
#     genuinely quoted-value paths (parse-args.md frozen list).
# shellcheck disable=SC1003
assert_error "case 24: backslash-escaped newline in unquoted value" \
  $'--label foo\\\nbar' \
  "embedded newline in unquoted value"

# 25. Backslash-escaped newline inside double-quoted value → error.
#     Repro from /review FINDING_2: same hazard via the double-quoted reader's
#     \\) arm; without the post-backslash newline check, falls into the
#     literal-pass-through default and emits a multi-line LABEL value.
# shellcheck disable=SC1003
assert_error "case 25: backslash-escaped newline inside double-quote" \
  $'--label "foo\\\nbar"' \
  "embedded newline in quoted value"

# --- New cases: --input-file and --umbrella-summary-file ---

# 26. Both flags set together — INPUT_FILE and UMBRELLA_SUMMARY_FILE emitted.
assert_raw_stdout_contains "case 26: --input-file emitted" \
  "--input-file /tmp/foo.md --umbrella-summary-file /tmp/bar.txt" \
  "INPUT_FILE=/tmp/foo.md"
assert_raw_stdout_contains "case 26b: --umbrella-summary-file emitted" \
  "--input-file /tmp/foo.md --umbrella-summary-file /tmp/bar.txt" \
  "UMBRELLA_SUMMARY_FILE=/tmp/bar.txt"

# 27. Half-config: --input-file alone → error.
assert_error "case 27: --input-file without --umbrella-summary-file" \
  "--input-file /tmp/foo.md" \
  "must be passed together"

# 28. Half-config: --umbrella-summary-file alone → error.
assert_error "case 28: --umbrella-summary-file without --input-file" \
  "--umbrella-summary-file /tmp/bar.txt" \
  "must be passed together"

# 29. Mutual exclusion: --input-file + positional TASK → error.
assert_error "case 29: --input-file mutually exclusive with TASK" \
  "--input-file /tmp/foo.md --umbrella-summary-file /tmp/bar.txt some task" \
  "mutually exclusive with positional TASK"

# 30. --input-file requires a value (frozen ERROR template).
assert_error "case 30: --input-file requires a value" \
  "--input-file" \
  "--input-file requires a value"

# 31. --umbrella-summary-file requires a value (frozen ERROR template).
assert_error "case 31: --umbrella-summary-file requires a value" \
  "--umbrella-summary-file" \
  "--umbrella-summary-file requires a value"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
