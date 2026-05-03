#!/usr/bin/env bash
# test-step2-dispatch.sh — Offline harness for skills/implement/scripts/step2-implement.sh.
#
# Covers the dispatcher branches that do NOT require spawning Codex:
#   1. --codex-available false → STATUS=claude_fallback (no launcher run).
#   2. Missing required flag → exit 2 (caller-error path).
#   3. Bad enum value (--codex-available xyz) → exit 2.
#   4. Pre-seeded resume counter at 5; 6th --answers invocation → STATUS=bailed REASON=qa-loop-exceeded.
#   5. Baseline-file persistence: invocation N+1 reuses N's baseline / spawn-branch / plugin-json files.
#
# Codex-spawning paths (manifest validation, diff cross-check, sanitization,
# launcher-retry) are covered by a separate end-to-end test in CI with a real
# Codex stub on PATH; this offline harness intentionally stays narrow so it
# runs in <1s with no external dependencies.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
DISPATCHER="$REPO_ROOT/skills/implement/scripts/step2-implement.sh"

[[ -x "$DISPATCHER" ]] || { echo "FAIL: dispatcher not executable: $DISPATCHER" >&2; exit 1; }

PASS_COUNT=0
FAIL_COUNT=0
fail() { echo "FAIL [$1]: $2" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }
pass() { PASS_COUNT=$((PASS_COUNT + 1)); }

# Temp scratch.
SCRATCH=$(mktemp -d -t step2-dispatch-test.XXXXXX)
trap 'rm -rf "$SCRATCH"' EXIT

PLAN="$SCRATCH/plan.md"
FEATURE="$SCRATCH/feature.txt"
echo "fake plan" > "$PLAN"
echo "fake feature" > "$FEATURE"

# ---------------------------------------------------------------------------
# Test 1: --codex-available false → STATUS=claude_fallback, no other keys.
# ---------------------------------------------------------------------------
TMP1="$SCRATCH/test1"; mkdir -p "$TMP1"
OUT=$("$DISPATCHER" --tmpdir "$TMP1" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available false 2>&1)
if [[ "$OUT" == *"STATUS=claude_fallback"* ]] \
   && [[ "$OUT" != *"MANIFEST="* ]] \
   && [[ "$OUT" != *"TRANSCRIPT="* ]]; then
    pass
else
    fail 1 "claude_fallback branch wrong output: $OUT"
fi
# Baseline files MUST NOT have been written on the claude_fallback branch.
if [[ -f "$TMP1/step2-baseline.txt" ]]; then
    fail 1 "claude_fallback branch leaked baseline file"
else
    pass
fi

# ---------------------------------------------------------------------------
# Test 2: missing required flag → exit 2.
# ---------------------------------------------------------------------------
EXIT=0
"$DISPATCHER" --tmpdir "$SCRATCH/test2" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false >/dev/null 2>&1 || EXIT=$?
if [[ "$EXIT" == "2" ]]; then pass; else fail 2 "missing --codex-available should exit 2, got $EXIT"; fi

# ---------------------------------------------------------------------------
# Test 3: bad enum value → exit 2.
# ---------------------------------------------------------------------------
EXIT=0
"$DISPATCHER" --tmpdir "$SCRATCH/test3" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available maybe >/dev/null 2>&1 || EXIT=$?
if [[ "$EXIT" == "2" ]]; then pass; else fail 3 "bad --codex-available value should exit 2, got $EXIT"; fi

# ---------------------------------------------------------------------------
# Test 4: bad --tmpdir (not a directory) → exit 2.
# ---------------------------------------------------------------------------
EXIT=0
"$DISPATCHER" --tmpdir "$SCRATCH/nonexistent" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available true >/dev/null 2>&1 || EXIT=$?
if [[ "$EXIT" == "2" ]]; then pass; else fail 4 "missing tmpdir should exit 2, got $EXIT"; fi

# ---------------------------------------------------------------------------
# Test 5: resume cap. Pre-seed step2-baseline / spawn-branch / plugin-json /
# resume-counter to simulate the 6th --answers invocation. Dispatcher should
# bail with REASON=qa-loop-exceeded BEFORE attempting to spawn Codex.
# ---------------------------------------------------------------------------
TMP5="$SCRATCH/test5"; mkdir -p "$TMP5"
git -C "$REPO_ROOT" rev-parse HEAD > "$TMP5/step2-baseline.txt"
git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD > "$TMP5/step2-spawn-branch.txt"
if [[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]]; then
    git -C "$REPO_ROOT" hash-object "$REPO_ROOT/.claude-plugin/plugin.json" > "$TMP5/step2-plugin-json-baseline.txt"
else
    printf '\n' > "$TMP5/step2-plugin-json-baseline.txt"
fi
echo "5" > "$TMP5/codex-resume-count.txt"
ANSWERS="$SCRATCH/answers.json"
echo '{"answers":[{"id":"q1","text":"x"}]}' > "$ANSWERS"

OUT=$(cd "$REPO_ROOT" && "$DISPATCHER" --tmpdir "$TMP5" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available true --answers "$ANSWERS" 2>&1)
if [[ "$OUT" == *"STATUS=bailed"* ]] && [[ "$OUT" == *"REASON=qa-loop-exceeded"* ]]; then
    pass
else
    fail 5 "resume cap should emit qa-loop-exceeded, got: $OUT"
fi

# ---------------------------------------------------------------------------
# Test 6: --answers but file does not exist → exit 2.
# ---------------------------------------------------------------------------
EXIT=0
( cd "$REPO_ROOT" && "$DISPATCHER" --tmpdir "$TMP5" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available true --answers "$SCRATCH/missing-answers.json" \
    >/dev/null 2>&1 ) || EXIT=$?
if [[ "$EXIT" == "2" ]]; then pass; else fail 6 "missing --answers file should exit 2, got $EXIT"; fi

# ---------------------------------------------------------------------------
# Test 7: corrupt resume counter (non-numeric) → STATUS=bailed
# REASON=manifest-schema-invalid (defense-in-depth against tmpdir tampering).
# ---------------------------------------------------------------------------
TMP7="$SCRATCH/test7"; mkdir -p "$TMP7"
git -C "$REPO_ROOT" rev-parse HEAD > "$TMP7/step2-baseline.txt"
git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD > "$TMP7/step2-spawn-branch.txt"
if [[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]]; then
    git -C "$REPO_ROOT" hash-object "$REPO_ROOT/.claude-plugin/plugin.json" > "$TMP7/step2-plugin-json-baseline.txt"
else
    printf '\n' > "$TMP7/step2-plugin-json-baseline.txt"
fi
echo "garbage" > "$TMP7/codex-resume-count.txt"
OUT=$(cd "$REPO_ROOT" && "$DISPATCHER" --tmpdir "$TMP7" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available true --answers "$ANSWERS" 2>&1)
if [[ "$OUT" == *"STATUS=bailed"* ]] && [[ "$OUT" == *"REASON=manifest-schema-invalid"* ]]; then
    pass
else
    fail 7 "corrupt resume counter should bail with manifest-schema-invalid, got: $OUT"
fi

# ---------------------------------------------------------------------------
# Test 8: --codex-available true outside a git working tree → exit 2
# (the new git-tree precondition added when REPO_ROOT was switched from
# SCRIPT_DIR-relative to git rev-parse --show-toplevel; closes the
# plugin-cache fallback regression).
# ---------------------------------------------------------------------------
TMP8="$SCRATCH/test8"; mkdir -p "$TMP8"
NON_GIT_DIR="$SCRATCH/not-a-repo"; mkdir -p "$NON_GIT_DIR"
EXIT=0
ERR=$(cd "$NON_GIT_DIR" && "$DISPATCHER" --tmpdir "$TMP8" --plan-file "$PLAN" --feature-file "$FEATURE" \
    --auto-mode false --codex-available true 2>&1 >/dev/null) || EXIT=$?
if [[ "$EXIT" == "2" ]] && [[ "$ERR" == *"must be invoked from within a git working tree"* ]]; then
    pass
else
    fail 8 "non-git cwd on Codex path should exit 2 with git-tree message, got exit=$EXIT err=$ERR"
fi
# A failed pre-spawn validation MUST NOT have written baseline files.
if [[ -f "$TMP8/step2-baseline.txt" ]]; then
    fail 8 "non-git cwd exit-2 leaked baseline file"
else
    pass
fi

# ---------------------------------------------------------------------------
# Summary.
# ---------------------------------------------------------------------------
TOTAL=$((PASS_COUNT + FAIL_COUNT))
if (( FAIL_COUNT == 0 )); then
    echo "PASS: test-step2-dispatch.sh — $PASS_COUNT/$TOTAL assertions"
    exit 0
else
    echo "FAIL: test-step2-dispatch.sh — $FAIL_COUNT/$TOTAL assertions failed" >&2
    exit 1
fi
