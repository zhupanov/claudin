#!/usr/bin/env bash
# test-render-umbrella-body.sh — runtime conformance harness for
# render-umbrella-body.sh.
#
# Pins:
#   - The --tmpdir writability preflight (closes #645): an unwritable tmpdir
#     produces ERROR=tmpdir not writable: <path> on stderr, exit 1, and NO
#     UMBRELLA_BODY_FILE= / UMBRELLA_TITLE_HINT= success KVs on stdout.
#   - The checked-write + atomic-rename happy path: writable tmpdir + valid
#     inputs produces a non-empty $TMPDIR/umbrella-body.md, exit 0, both
#     success KVs, and no leftover umbrella-body.md.* mktemp partial.
#   - The mv-failure branch: a PATH-injected fake `mv` that always exits 1
#     forces the script's `mv "$OUT_TMP" "$OUT" || { ... }` guard to fire,
#     producing ERROR=failed to write umbrella body: <path> on stderr,
#     exit 1, and no success KVs. PATH-injection is used because BSD and
#     GNU `mv` differ on what makes a same-directory rename fail (e.g.,
#     dest-as-empty-dir succeeds on BSD by moving source inside, fails
#     with EISDIR on GNU); mocking `mv` removes that platform divergence.
#   - The dest-as-directory branch: $OUT pre-existing as a directory triggers
#     the pre-rename `[ -e "$OUT" ] && [ ! -f "$OUT" ]` guard (added to fix
#     the BSD `mv source dir/` silent-nesting bug — same #645 class).
#   - The mktemp-failure branch: PATH-injected fake `mktemp` that always
#     exits 1 forces the `mktemp ... || { ... }` guard to fire.
#   - The existing children-TSV malformed path: a malformed children.tsv
#     produces ERROR=children.tsv malformed on stderr, exit 1.
#
# Pattern matches .claude/skills/umbrella/scripts/test-umbrella-parse-args.sh
# (mktemp workspace, trap cleanup, exit-code + stdout/stderr substring
# assertions). Distinct from test-umbrella-emit-output-contract.sh, which is
# a structural literal-substring test of SKILL.md / helpers.md.
#
# Precondition: must run as a non-root user. chmod 555 does not deny root,
# so the unwritable-tmpdir test would falsely pass under root.
#
# Run manually:
#   bash .claude/skills/umbrella/scripts/test-render-umbrella-body.sh
# Wired into make lint via the test-render-umbrella-body Makefile target.
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/render-umbrella-body.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "ERROR: render-umbrella-body.sh not found or not executable: $SCRIPT" >&2
    exit 1
fi

TMP=$(mktemp -d -t test-render-umbrella-body-XXXXXX)
# chmod 555 dirs need 755 restored before rm -rf can recurse into them.
trap 'chmod -R 755 "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT

PASS=0

# Run the script; capture stdout, stderr, and exit code separately.
# Usage: run_script <args...>; reads "$STDOUT_FILE" / "$STDERR_FILE" / $EXIT_CODE
STDOUT_FILE="$TMP/stdout"
STDERR_FILE="$TMP/stderr"
EXIT_CODE=0
run_script() {
  set +e
  bash "$SCRIPT" "$@" >"$STDOUT_FILE" 2>"$STDERR_FILE"
  EXIT_CODE=$?
  set -e
}

assert_exit_nonzero() {
  local label="$1"
  if [ "$EXIT_CODE" = "0" ]; then
    printf '  ❌ %s — expected non-zero exit, got 0. stderr: %s\n' "$label" "$(cat "$STDERR_FILE")" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
  printf '  ✅ %s\n' "$label"
}

assert_exit_zero() {
  local label="$1"
  if [ "$EXIT_CODE" != "0" ]; then
    printf '  ❌ %s — expected exit 0, got %s. stderr: %s\n' "$label" "$EXIT_CODE" "$(cat "$STDERR_FILE")" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
  printf '  ✅ %s\n' "$label"
}

assert_stderr_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$STDERR_FILE"; then
    PASS=$((PASS + 1))
    printf '  ✅ %s\n' "$label"
  else
    printf '  ❌ %s — stderr missing %q. stderr: %s\n' "$label" "$needle" "$(cat "$STDERR_FILE")" >&2
    exit 1
  fi
}

assert_stdout_contains() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$STDOUT_FILE"; then
    PASS=$((PASS + 1))
    printf '  ✅ %s\n' "$label"
  else
    printf '  ❌ %s — stdout missing %q. stdout: %s\n' "$label" "$needle" "$(cat "$STDOUT_FILE")" >&2
    exit 1
  fi
}

assert_stdout_lacks() {
  local label="$1" needle="$2"
  if grep -qF -- "$needle" "$STDOUT_FILE"; then
    printf '  ❌ %s — stdout unexpectedly contains %q. stdout: %s\n' "$label" "$needle" "$(cat "$STDOUT_FILE")" >&2
    exit 1
  fi
  PASS=$((PASS + 1))
  printf '  ✅ %s\n' "$label"
}

# -----------------------------------------------------------------------------
# Shared inputs: writable directory holding valid summary.txt + children.tsv.
# Used by every test below. The tests vary the --tmpdir target, not the inputs.
# -----------------------------------------------------------------------------
INPUTS="$TMP/inputs"
mkdir -p "$INPUTS"
printf 'Refactor the umbrella body composer for safer failure handling. This is a deliberately multi-sentence paragraph used as the summary.\n' > "$INPUTS/summary.txt"
printf '101\tFirst child issue\thttps://example.test/issues/101\n102\tSecond child issue\thttps://example.test/issues/102\n' > "$INPUTS/children.tsv"

echo "test-render-umbrella-body.sh: render-umbrella-body.sh runtime conformance"

# -----------------------------------------------------------------------------
# Case 1 — Unwritable tempdir (chmod 555). Closes #645 — confirms the
# writability preflight emits the documented ERROR= stderr line and that no
# success KVs leak to stdout on this failure path.
# -----------------------------------------------------------------------------
echo "Case 1: unwritable tempdir → ERROR=tmpdir not writable, no success KVs"
UNWRITABLE="$TMP/unwritable"
mkdir -p "$UNWRITABLE"
chmod 555 "$UNWRITABLE"
run_script --tmpdir "$UNWRITABLE" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children.tsv"
assert_exit_nonzero "case 1: exit non-zero"
assert_stderr_contains "case 1: stderr ERROR=tmpdir not writable:" "ERROR=tmpdir not writable:"
assert_stdout_lacks "case 1: stdout no UMBRELLA_BODY_FILE=" "UMBRELLA_BODY_FILE="
assert_stdout_lacks "case 1: stdout no UMBRELLA_TITLE_HINT=" "UMBRELLA_TITLE_HINT="
chmod 755 "$UNWRITABLE"

# -----------------------------------------------------------------------------
# Case 2 — Happy path. Writable tempdir + valid inputs.
# -----------------------------------------------------------------------------
echo "Case 2: happy path → exit 0, body written, both success KVs"
HAPPY="$TMP/happy"
mkdir -p "$HAPPY"
run_script --tmpdir "$HAPPY" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children.tsv"
assert_exit_zero "case 2: exit 0"
assert_stdout_contains "case 2: stdout UMBRELLA_BODY_FILE=" "UMBRELLA_BODY_FILE=$HAPPY/umbrella-body.md"
assert_stdout_contains "case 2: stdout UMBRELLA_TITLE_HINT=" "UMBRELLA_TITLE_HINT="
if [ ! -s "$HAPPY/umbrella-body.md" ]; then
  printf '  ❌ case 2: umbrella-body.md is missing or empty\n' >&2; exit 1
fi
PASS=$((PASS + 1))
printf '  ✅ case 2: umbrella-body.md exists and is non-empty\n'
# No leftover mktemp partial — the atomic-rename should have moved it into place.
LEFTOVERS=$(find "$HAPPY" -name 'umbrella-body.md.*' 2>/dev/null | wc -l | tr -d ' ')
if [ "$LEFTOVERS" != "0" ]; then
  printf '  ❌ case 2: %s leftover mktemp partial(s) found in %s\n' "$LEFTOVERS" "$HAPPY" >&2; exit 1
fi
PASS=$((PASS + 1))
printf '  ✅ case 2: no leftover mktemp partial\n'

# -----------------------------------------------------------------------------
# Case 3 — mv failure. Inject a fake `mv` at the front of PATH that always
# exits 1, so the script's `mv "$OUT_TMP" "$OUT" || { ... }` branch fires.
# PATH-injection is the only portable way: BSD `mv` (macOS default) and GNU
# `mv` differ on what makes a same-directory rename fail (e.g., dest-as-empty-
# dir succeeds on BSD by moving source inside, EISDIR on GNU). Mocking `mv`
# directly removes that platform divergence and isolates the test to the
# script's own error-handling logic — exactly what FINDING_6 asked for.
# -----------------------------------------------------------------------------
echo "Case 3: mv failure (PATH-injected fake mv) → ERROR=failed to write, no success KVs"
MVFAIL="$TMP/mvfail"
mkdir -p "$MVFAIL"
FAKE_BIN="$TMP/fake-bin"
mkdir -p "$FAKE_BIN"
cat > "$FAKE_BIN/mv" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN/mv"
# Run with the fake mv at the front of PATH. Only `mv` is overridden; mktemp,
# cat, awk, printf still resolve via the real PATH.
set +e
PATH="$FAKE_BIN:$PATH" bash "$SCRIPT" --tmpdir "$MVFAIL" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children.tsv" >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?
set -e
assert_exit_nonzero "case 3: exit non-zero"
assert_stderr_contains "case 3: stderr ERROR=failed to write umbrella body:" "ERROR=failed to write umbrella body:"
assert_stdout_lacks "case 3: stdout no UMBRELLA_BODY_FILE=" "UMBRELLA_BODY_FILE="
assert_stdout_lacks "case 3: stdout no UMBRELLA_TITLE_HINT=" "UMBRELLA_TITLE_HINT="

# -----------------------------------------------------------------------------
# Case 3b — Pre-existing $OUT as a directory. On BSD/macOS, `mv source dir/`
# silently nests source inside dir and exits 0 — same #645 failure-as-success
# class on a different surface. The script's pre-rename guard (`[ -e "$OUT" ]
# && [ ! -f "$OUT" ]`) must reject this before mv runs.
# -----------------------------------------------------------------------------
echo "Case 3b: dest pre-existing as directory → ERROR=failed to write, no success KVs"
DESTDIR="$TMP/destdir"
mkdir -p "$DESTDIR/umbrella-body.md"
run_script --tmpdir "$DESTDIR" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children.tsv"
assert_exit_nonzero "case 3b: exit non-zero"
assert_stderr_contains "case 3b: stderr ERROR=failed to write umbrella body:" "ERROR=failed to write umbrella body:"
assert_stdout_lacks "case 3b: stdout no UMBRELLA_BODY_FILE=" "UMBRELLA_BODY_FILE="
assert_stdout_lacks "case 3b: stdout no UMBRELLA_TITLE_HINT=" "UMBRELLA_TITLE_HINT="

# -----------------------------------------------------------------------------
# Case 3c — mktemp failure. PATH-injected fake `mktemp` that always exits 1
# forces the script's `mktemp ... || { ... }` guard to fire. Same pattern as
# Case 3.
# -----------------------------------------------------------------------------
echo "Case 3c: mktemp failure (PATH-injected fake mktemp) → ERROR=failed to write, no success KVs"
MKTEMP_FAIL="$TMP/mktemp-fail"
mkdir -p "$MKTEMP_FAIL"
FAKE_BIN_MKTEMP="$TMP/fake-bin-mktemp"
mkdir -p "$FAKE_BIN_MKTEMP"
cat > "$FAKE_BIN_MKTEMP/mktemp" <<'EOF'
#!/usr/bin/env bash
exit 1
EOF
chmod +x "$FAKE_BIN_MKTEMP/mktemp"
set +e
PATH="$FAKE_BIN_MKTEMP:$PATH" bash "$SCRIPT" --tmpdir "$MKTEMP_FAIL" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children.tsv" >"$STDOUT_FILE" 2>"$STDERR_FILE"
EXIT_CODE=$?
set -e
assert_exit_nonzero "case 3c: exit non-zero"
assert_stderr_contains "case 3c: stderr ERROR=failed to write umbrella body:" "ERROR=failed to write umbrella body:"
assert_stdout_lacks "case 3c: stdout no UMBRELLA_BODY_FILE=" "UMBRELLA_BODY_FILE="
assert_stdout_lacks "case 3c: stdout no UMBRELLA_TITLE_HINT=" "UMBRELLA_TITLE_HINT="

# -----------------------------------------------------------------------------
# Case 4 — Existing children-TSV malformed path (regression check on the
# pre-existing validation at lines 38-42 of render-umbrella-body.sh).
# -----------------------------------------------------------------------------
echo "Case 4: malformed children.tsv → ERROR=children.tsv malformed"
MALFORMED="$TMP/malformed"
mkdir -p "$MALFORMED"
printf 'not-a-number\tonly two fields\n' > "$INPUTS/children-bad.tsv"
run_script --tmpdir "$MALFORMED" --summary-file "$INPUTS/summary.txt" --children-file "$INPUTS/children-bad.tsv"
assert_exit_nonzero "case 4: exit non-zero"
assert_stderr_contains "case 4: stderr ERROR=children.tsv malformed" "ERROR=children.tsv malformed"

echo
echo "All $PASS assertions passed."
