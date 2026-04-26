#!/usr/bin/env bash
# test-prepare-description.sh — Regression harness for
# skills/create-skill/scripts/prepare-description.sh.
#
# Pins the stdout grammar (MODE=verbatim | needs-synthesis | abort + ancillary
# fields), the synthesis-trigger error-literal substring matches, the F9
# pre-synthesis security scan rule, and the internal-error exit codes so future
# edits don't silently disable the Step 1.5 / Step 1.6 synthesis flow in
# skills/create-skill/SKILL.md. Wired into make lint via the explicit Makefile
# test-harnesses target.
#
# Exit: 0 on all tests pass; 1 on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PREPARE="$REPO_ROOT/skills/create-skill/scripts/prepare-description.sh"

if [[ ! -x "$PREPARE" ]]; then
  echo "FAIL: $PREPARE not found or not executable" >&2
  exit 1
fi

# Per-test scratch directory.
TMPDIR_TEST="$(mktemp -d -t test-prepare-description.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

pass_count=0
fail_count=0

check() {
  local name="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    ((pass_count++)) || true
  else
    ((fail_count++)) || true
    echo "FAIL: $name" >&2
    echo "  want: $want" >&2
    echo "  got:  $got" >&2
  fi
}

check_contains() {
  local name="$1" got="$2" needle="$3"
  if [[ "$got" == *"$needle"* ]]; then
    ((pass_count++)) || true
  else
    ((fail_count++)) || true
    echo "FAIL: $name" >&2
    echo "  expected substring: $needle" >&2
    echo "  got:                $got" >&2
  fi
}

# --- Test 1: verbatim path via --description ---------------------------------
out=$("$PREPARE" --name myskill --description "Use when doing X")
check "t1 MODE=verbatim" "$(echo "$out" | grep '^MODE=')" "MODE=verbatim"

# --- Test 2: verbatim path via --description-file ----------------------------
descfile="$TMPDIR_TEST/desc-t2.txt"
printf 'Use when doing Y' > "$descfile"
out=$("$PREPARE" --name myskill --description-file "$descfile")
check "t2 MODE=verbatim (file form)" "$(echo "$out" | grep '^MODE=')" "MODE=verbatim"

# --- Test 3: needs-synthesis on newlines (via --description-file) ------------
descfile="$TMPDIR_TEST/desc-t3.txt"
printf 'Line 1 of multi-line description.\nLine 2.\nLine 3.' > "$descfile"
out=$("$PREPARE" --name myskill --description-file "$descfile")
check "t3 MODE=needs-synthesis (newline)" "$(echo "$out" | grep '^MODE=')" "MODE=needs-synthesis"
check "t3 REASON=newlines-or-control-chars" "$(echo "$out" | grep '^REASON=')" "REASON=newlines-or-control-chars"

# --- Test 4: abort on XML tag (single-line) ----------------------------------
out=$("$PREPARE" --name myskill --description "Use when working with <xml> data")
check "t4 MODE=abort (XML)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"
check_contains "t4 ERROR mentions XML" \
  "$(echo "$out" | grep '^ERROR=')" "XML tag pattern"

# --- Test 5: abort on backtick (single-line) ---------------------------------
# shellcheck disable=SC2016  # literal backtick character intended in test fixture
out=$("$PREPARE" --name myskill --description 'Use when running `cmd` here')
check "t5 MODE=abort (backtick)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"
check_contains "t5 ERROR mentions backtick" \
  "$(echo "$out" | grep '^ERROR=')" "backtick"

# --- Test 6: abort on $( (single-line) ---------------------------------------
# shellcheck disable=SC2016  # literal two-char sequence in test fixture
out=$("$PREPARE" --name myskill --description 'Use when calling $(cmd) inline')
check "t6 MODE=abort (\$()" "$(echo "$out" | grep '^MODE=')" "MODE=abort"

# --- Test 7: needs-synthesis on length-only failure --------------------------
# Build a 1500-char single-line description with no anti-patterns.
long_desc=""
for _ in $(seq 1 100); do
  long_desc+="Use when handling repetitive batched workloads. "
done
out=$("$PREPARE" --name myskill --description "$long_desc")
check "t7 MODE=needs-synthesis (length)" "$(echo "$out" | grep '^MODE=')" "MODE=needs-synthesis"
check "t7 REASON=length-exceeds-cap" "$(echo "$out" | grep '^REASON=')" "REASON=length-exceeds-cap"

# --- Test 8: abort on standalone heredoc token -------------------------------
out=$("$PREPARE" --name myskill --description "Use when this fires EOF for sure")
check "t8 MODE=abort (heredoc)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"

# --- Test 9: internal error — missing --name ---------------------------------
set +e
err=$("$PREPARE" --description "anything" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t9 expected non-zero exit on missing --name, got 0" >&2
elif [[ "$err" != *"Missing required --name"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t9 expected 'Missing required --name' error; got: $err" >&2
else
  ((pass_count++)) || true
fi

# --- Test 10: F9 mixed-input — newline + XML --------------------------------
descfile="$TMPDIR_TEST/desc-t10.txt"
printf 'Line 1 with content.\n<xml>nested</xml> on line 2.' > "$descfile"
out=$("$PREPARE" --name myskill --description-file "$descfile")
check "t10 MODE=abort (mixed newline+XML)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"
check_contains "t10 ERROR mentions mixed-input" \
  "$(echo "$out" | grep '^ERROR=')" "Synthesis disabled for mixed-input cases"

# --- Test 11: F9 mixed-input — newline + backtick ---------------------------
descfile="$TMPDIR_TEST/desc-t11.txt"
# shellcheck disable=SC2016  # literal backtick character intended in test fixture
printf 'Line 1.\nLine 2 has `cmd` in it.' > "$descfile"
out=$("$PREPARE" --name myskill --description-file "$descfile")
check "t11 MODE=abort (mixed newline+backtick)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"

# --- Test 12: F9 mixed-input — length + backtick ----------------------------
# Build a >1024-char single-line description that also contains a backtick.
long_with_backtick=""
for _ in $(seq 1 50); do
  long_with_backtick+="Use when handling batched workloads with care. "
done
long_with_backtick+="\`cmd\` is mentioned somewhere"
out=$("$PREPARE" --name myskill --description "$long_with_backtick")
check "t12 MODE=abort (mixed length+backtick)" "$(echo "$out" | grep '^MODE=')" "MODE=abort"

# --- Test 13: ambiguous flags (both --description and --description-file) ----
descfile="$TMPDIR_TEST/desc-t13.txt"
printf 'X' > "$descfile"
set +e
err=$("$PREPARE" --name myskill --description "X" --description-file "$descfile" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t13 expected non-zero exit on ambiguous flags, got 0" >&2
elif [[ "$err" != *"mutually exclusive"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t13 expected 'mutually exclusive' error; got: $err" >&2
else
  ((pass_count++)) || true
fi

# --- Test 14: missing --description-file path --------------------------------
set +e
err=$("$PREPARE" --name myskill --description-file "$TMPDIR_TEST/does-not-exist.txt" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t14 expected non-zero exit on missing description-file, got 0" >&2
elif [[ "$err" != *"does not exist"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t14 expected 'does not exist' error; got: $err" >&2
else
  ((pass_count++)) || true
fi

echo
echo "test-prepare-description.sh: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
