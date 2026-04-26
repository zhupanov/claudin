#!/bin/bash
# Test harness for skills/alias/scripts/resolve-target.sh.
# Exercises the (plugin-detect × --private) matrix plus fail-closed git failure
# and the two-file-predicate strict-AND case.
#
# See skills/alias/scripts/resolve-target.md for the contract under test.
# Exit 0 on all pass, exit 1 on any assertion failure.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SCRIPT="$REPO_ROOT/skills/alias/scripts/resolve-target.sh"

[[ -x "$SCRIPT" ]] || { echo "FAIL: resolve-target.sh missing or not executable: $SCRIPT" >&2; exit 1; }

PASS=0
FAIL=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [[ "$expected" == "$actual" ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2
    echo "  expected: $expected" >&2
    echo "  actual:   $actual" >&2
    FAIL=$((FAIL + 1))
  fi
}

assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    PASS=$((PASS + 1))
  else
    echo "FAIL: $label" >&2
    echo "  needle:   $needle" >&2
    echo "  haystack: $haystack" >&2
    FAIL=$((FAIL + 1))
  fi
}

# Each case runs in its own temp dir with controlled git state so the host repo
# layout does not leak in. Cleanup via trap.
TMPROOT=$(mktemp -d)
trap 'rm -rf "$TMPROOT"' EXIT

# Helper: spin up a fresh repo with controlled marker files.
# Args: $1 = case name (sub-dir), $2 = "with-plugin"|"without-plugin"|"plugin-only-no-implement"
make_repo() {
  local name="$1" mode="$2"
  local dir="$TMPROOT/$name"
  mkdir -p "$dir"
  (
    cd "$dir"
    git init -q
    # Best-effort branch rename to 'main' so the test repo's default branch is
    # predictable; older git versions reject 'checkout -b main' if 'main' is
    # already the current branch (created by the init-default-branch config).
    git checkout -q -b main 2>/dev/null || true
  )
  case "$mode" in
    with-plugin)
      mkdir -p "$dir/.claude-plugin" "$dir/skills/implement"
      printf '{}\n' > "$dir/.claude-plugin/plugin.json"
      printf '# stub\n' > "$dir/skills/implement/SKILL.md"
      ;;
    without-plugin)
      : # nothing extra
      ;;
    plugin-only-no-implement)
      mkdir -p "$dir/.claude-plugin"
      printf '{}\n' > "$dir/.claude-plugin/plugin.json"
      ;;
    *) echo "FAIL (test bug): unknown make_repo mode '$mode'" >&2; exit 1 ;;
  esac
  echo "$dir"
}

# Resolve the realpath of a directory so we can match what the script emits
# (git rev-parse --show-toplevel canonicalizes /private/var symlinks on macOS).
canon() {
  ( cd "$1" && pwd -P )
}

# ---------------------------------------------------------------------------
# Case A — full plugin repo, --private absent → PLUGIN_REPO=true, skills/<n>
# ---------------------------------------------------------------------------
dir=$(make_repo case-a with-plugin)
canon_dir=$(canon "$dir")
out=$( cd "$dir" && "$SCRIPT" --alias-name foo )
assert_contains "Case A: REPO_ROOT line"   "REPO_ROOT=$canon_dir"          "$out"
assert_contains "Case A: PLUGIN_REPO=true" "PLUGIN_REPO=true"              "$out"
assert_contains "Case A: TARGET_DIR=skills/foo" "TARGET_DIR=$canon_dir/skills/foo" "$out"

# ---------------------------------------------------------------------------
# Case B — full plugin repo, --private present → PLUGIN_REPO=true, .claude/skills/<n>
# ---------------------------------------------------------------------------
dir=$(make_repo case-b with-plugin)
canon_dir=$(canon "$dir")
out=$( cd "$dir" && "$SCRIPT" --alias-name foo --private )
assert_contains "Case B: PLUGIN_REPO=true"        "PLUGIN_REPO=true"                          "$out"
assert_contains "Case B: TARGET_DIR=.claude/skills/foo (private override)" \
  "TARGET_DIR=$canon_dir/.claude/skills/foo" "$out"

# ---------------------------------------------------------------------------
# Case C — non-plugin repo, --private absent → PLUGIN_REPO=false, .claude/skills/<n>
# ---------------------------------------------------------------------------
dir=$(make_repo case-c without-plugin)
canon_dir=$(canon "$dir")
out=$( cd "$dir" && "$SCRIPT" --alias-name foo )
assert_contains "Case C: PLUGIN_REPO=false"       "PLUGIN_REPO=false"                         "$out"
assert_contains "Case C: TARGET_DIR=.claude/skills/foo (default)" \
  "TARGET_DIR=$canon_dir/.claude/skills/foo" "$out"

# ---------------------------------------------------------------------------
# Case D — non-plugin repo, --private present → PLUGIN_REPO=false, .claude/skills/<n>
# (no-op for --private in non-plugin repo; no error)
# ---------------------------------------------------------------------------
dir=$(make_repo case-d without-plugin)
canon_dir=$(canon "$dir")
out=$( cd "$dir" && "$SCRIPT" --alias-name foo --private )
assert_contains "Case D: PLUGIN_REPO=false (--private no-op)"   "PLUGIN_REPO=false"                  "$out"
assert_contains "Case D: TARGET_DIR=.claude/skills/foo"         "TARGET_DIR=$canon_dir/.claude/skills/foo" "$out"

# ---------------------------------------------------------------------------
# Case E — outside any git repo → exit 1, ERROR on stderr, no stdout KEY=VALUE lines
# Use a tmp dir but do NOT git init in it.
# ---------------------------------------------------------------------------
dir="$TMPROOT/case-e"
mkdir -p "$dir"
set +e
out=$( cd "$dir" && "$SCRIPT" --alias-name foo 2>"$TMPROOT/case-e.err" )
rc=$?
set -e
assert_eq "Case E: exit code 1" "1" "$rc"
err=$(cat "$TMPROOT/case-e.err")
assert_contains "Case E: ERROR on stderr" "ERROR" "$err"
# stdout MUST NOT contain KEY=VALUE lines on the failure path
if [[ "$out" == *"TARGET_DIR="* ]]; then
  echo "FAIL: Case E: stdout should be empty on fail-closed exit, got: $out" >&2
  FAIL=$((FAIL + 1))
else
  PASS=$((PASS + 1))
fi

# ---------------------------------------------------------------------------
# Case F — only .claude-plugin/plugin.json (NO skills/implement/SKILL.md)
# Two-file predicate strict-AND: PLUGIN_REPO=false, TARGET_DIR=.claude/skills/<n>
# Guards against routing arbitrary plugin repos to skills/<n>/.
# ---------------------------------------------------------------------------
dir=$(make_repo case-f plugin-only-no-implement)
canon_dir=$(canon "$dir")
out=$( cd "$dir" && "$SCRIPT" --alias-name foo )
assert_contains "Case F: PLUGIN_REPO=false (partial-plugin repo)" "PLUGIN_REPO=false" "$out"
assert_contains "Case F: TARGET_DIR=.claude/skills/foo (no public route)" \
  "TARGET_DIR=$canon_dir/.claude/skills/foo" "$out"

# ---------------------------------------------------------------------------
# Defense-in-depth: invalid --alias-name fails fast.
# ---------------------------------------------------------------------------
dir=$(make_repo case-validation without-plugin)
set +e
out=$( cd "$dir" && "$SCRIPT" --alias-name "Bad-Name" 2>"$TMPROOT/case-validation.err" )
rc=$?
set -e
assert_eq "Validation: exit 1 on invalid alias-name" "1" "$rc"
err=$(cat "$TMPROOT/case-validation.err")
assert_contains "Validation: ERROR on stderr" "ERROR" "$err"

# ---------------------------------------------------------------------------
# Arity guard: --alias-name with no value emits the documented ERROR
# message (not bash's nounset 'unbound variable'). Regression for the
# review-finding fix.
# ---------------------------------------------------------------------------
dir=$(make_repo case-arity without-plugin)
set +e
out=$( cd "$dir" && "$SCRIPT" --alias-name 2>"$TMPROOT/case-arity.err" )
rc=$?
set -e
assert_eq "Arity: exit 1 when --alias-name has no value" "1" "$rc"
err=$(cat "$TMPROOT/case-arity.err")
assert_contains "Arity: documented ERROR message on stderr (not nounset crash)" \
  "ERROR: --alias-name requires a value" "$err"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "test-alias-target-resolution.sh: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
