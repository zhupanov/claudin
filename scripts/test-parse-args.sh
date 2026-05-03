#!/usr/bin/env bash
# test-parse-args.sh — Regression harness for skills/create-skill/scripts/parse-args.sh.
#
# Pins the stdout grammar, flag list, and error-message format so that future
# edits to parse-args.sh don't silently break the /create-skill SKILL.md parser
# or the downstream /im forwarding. Wired into `make lint` via the
# scripts/test-*.sh discovery.
#
# Exit: 0 on all tests pass; 1 on any failure.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PARSE_ARGS="$REPO_ROOT/skills/create-skill/scripts/parse-args.sh"

if [[ ! -x "$PARSE_ARGS" ]]; then
  echo "FAIL: $PARSE_ARGS not found or not executable" >&2
  exit 1
fi

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

# --- Test 1: minimal valid input (no flags) -----------------------------------
out=$("$PARSE_ARGS" myskill "Use when doing X")
check "t1 NAME"        "$(echo "$out" | grep '^NAME=')"        "NAME=myskill"
check "t1 DESCRIPTION" "$(echo "$out" | grep '^DESCRIPTION=')" "DESCRIPTION=Use when doing X"
check "t1 PLUGIN"      "$(echo "$out" | grep '^PLUGIN=')"      "PLUGIN=false"
check "t1 MULTI_STEP"  "$(echo "$out" | grep '^MULTI_STEP=')"  "MULTI_STEP=false"
check "t1 MERGE"       "$(echo "$out" | grep '^MERGE=')"       "MERGE=false"
check "t1 NO_SLACK"    "$(echo "$out" | grep '^NO_SLACK=')"    "NO_SLACK=false"

# --- Test 2: all flags set ----------------------------------------------------
out=$("$PARSE_ARGS" --plugin --multi-step --merge --no-slack foo "Use when doing Y")
check "t2 NAME"        "$(echo "$out" | grep '^NAME=')"        "NAME=foo"
check "t2 PLUGIN"      "$(echo "$out" | grep '^PLUGIN=')"      "PLUGIN=true"
check "t2 MULTI_STEP"  "$(echo "$out" | grep '^MULTI_STEP=')"  "MULTI_STEP=true"
check "t2 MERGE"       "$(echo "$out" | grep '^MERGE=')"       "MERGE=true"
check "t2 NO_SLACK"    "$(echo "$out" | grep '^NO_SLACK=')"    "NO_SLACK=true"

# --- Test 3: leading slash stripped -------------------------------------------
out=$("$PARSE_ARGS" /bar "Use when doing Z")
check "t3 NAME leading-slash stripped" "$(echo "$out" | grep '^NAME=')" "NAME=bar"

# --- Test 4: multi-word description preserved verbatim ------------------------
out=$("$PARSE_ARGS" baz "Use when  doing   multi-word things")
check "t4 DESCRIPTION verbatim" "$(echo "$out" | grep '^DESCRIPTION=')" "DESCRIPTION=Use when  doing   multi-word things"

# --- Test 5: unknown flag (error) ---------------------------------------------
set +e
err=$("$PARSE_ARGS" --bogus foo "desc" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t5 expected non-zero exit on --bogus, got 0" >&2
fi
if [[ "$err" != *"ERROR=Unknown flag '--bogus'"* ]] || [[ "$err" != *"--no-slack"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t5 expected ERROR= line mentioning '--bogus' and '--no-slack' in usage list; got: $err" >&2
else
  ((pass_count++)) || true
fi

# --- Test 6: rejected legacy --slack flag -------------------------------------
# Post-rename, --slack should be rejected with an 'Unknown flag' error so existing
# invocations fail loudly rather than silently misparse. (The project explicitly
# opted for a hard break; no deprecation shim.)
set +e
err=$("$PARSE_ARGS" --slack foo "desc" 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t6 expected non-zero exit on legacy --slack, got 0" >&2
elif [[ "$err" != *"Unknown flag"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t6 expected 'Unknown flag' error for legacy --slack; got: $err" >&2
else
  ((pass_count++)) || true
fi

# --- Test 7: missing skill-name -----------------------------------------------
set +e
err=$("$PARSE_ARGS" --plugin 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t7 expected non-zero exit on missing skill-name, got 0" >&2
elif [[ "$err" != *"Missing <skill-name>"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t7 expected 'Missing <skill-name>' error; got: $err" >&2
else
  ((pass_count++)) || true
fi

# --- Test 8: missing description ----------------------------------------------
set +e
err=$("$PARSE_ARGS" myskill 2>&1)
rc=$?
set -e
if [[ $rc -eq 0 ]]; then
  ((fail_count++)) || true
  echo "FAIL: t8 expected non-zero exit on missing description, got 0" >&2
elif [[ "$err" != *"Missing <description>"* ]]; then
  ((fail_count++)) || true
  echo "FAIL: t8 expected 'Missing <description>' error; got: $err" >&2
else
  ((pass_count++)) || true
fi

echo
echo "test-parse-args.sh: $pass_count passed, $fail_count failed"
[[ $fail_count -eq 0 ]]
