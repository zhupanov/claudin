#!/usr/bin/env bash
# test-ci-wait-exit-trap.sh — Regression test for scripts/ci-wait.sh #842 fix.
#
# Two sub-tests:
#
# A) `--output-file` SIGTERM-mid-poll convergence: launch ci-wait.sh in the
#    background with --output-file pointing at a tmp path, send SIGTERM
#    after the polling loop has entered (deterministic ready signal via
#    a stub ci-status.sh `touch loop-entered`), then assert (i) the KV
#    output file exists with a parseable ACTION= line and (ii) the
#    sentinel `<path>.done` exists with parseable numeric content.
#
# B) Default-mode (stdout) backward-compat: run ci-wait.sh WITHOUT
#    --output-file, with a stub ci-decide.sh returning ACTION=merge so
#    the script exits cleanly. Assert all 7 KV keys appear on stdout
#    in order, and that NO file-mode side effects occurred (no
#    output file, no .done sentinel created adjacent).
#
# SIGNAL CHOICE: The test sends SIGTERM, NOT SIGKILL. Bash CANNOT trap
# SIGKILL; no shell-side mechanism can write the sentinel under SIGKILL.
# The doc-layer fix (synchronous-only invocation contract in
# skills/implement/SKILL.md and skills/implement/references/rebase-rebump-subprocedure.md)
# is the operational defense for SIGKILL paths. This harness exercises
# the trap-deliverable signal class only.
#
# Fixture layout: a tmpdir contains a copy of ci-wait.sh + stubs for
# ci-status.sh and ci-decide.sh. The copy (not a symlink) is required
# so ci-wait.sh's `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` resolves
# to the fixture dir's stubs rather than the real $REPO/scripts.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMPDIR_BASE="$(mktemp -d -t ci-wait-test.XXXXXX)"

# shellcheck disable=SC2317  # body invoked via `trap cleanup EXIT`
cleanup() {
    if [[ -n "${BG_PID:-}" ]] && kill -0 "$BG_PID" 2>/dev/null; then
        kill -KILL "$BG_PID" 2>/dev/null || true
        wait "$BG_PID" 2>/dev/null || true
    fi
    rm -rf "$TMPDIR_BASE"
}
trap cleanup EXIT

PASS_COUNT=0
FAIL_COUNT=0

ok() { echo "  PASS: $1"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "  FAIL: $1"; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# ----------------------------------------------------------------------
# Sub-test A — --output-file SIGTERM convergence
# ----------------------------------------------------------------------
echo "Sub-test A: --output-file SIGTERM-mid-poll convergence"

A_DIR="$TMPDIR_BASE/A"
mkdir -p "$A_DIR"
cp "$REPO_ROOT/scripts/ci-wait.sh" "$A_DIR/ci-wait.sh"
chmod +x "$A_DIR/ci-wait.sh"

# Stub ci-status.sh: touches loop-entered marker on each call (the test
# polls for this as a deterministic readiness signal, eliminating the
# stderr-readiness race the design dialectic flagged). Outputs values
# that drive the polling loop into ACTION=wait via ci-decide.sh below.
cat > "$A_DIR/ci-status.sh" <<'SH'
#!/usr/bin/env bash
touch "$(dirname "$0")/loop-entered"
echo "CI_STATUS=pending"
echo "BEHIND_COUNT=0"
echo "FAILED_RUN_ID="
SH
chmod +x "$A_DIR/ci-status.sh"

# Stub ci-decide.sh: always returns ACTION=wait so the polling loop
# never exits naturally — only SIGTERM can stop it.
cat > "$A_DIR/ci-decide.sh" <<'SH'
#!/usr/bin/env bash
echo "ACTION=wait"
echo "BAIL_REASON="
SH
chmod +x "$A_DIR/ci-decide.sh"

OUT_PATH="$A_DIR/out.txt"
STDERR_LOG="$A_DIR/stderr.log"

bash "$A_DIR/ci-wait.sh" \
    --pr 999 --repo test/repo --timeout 60 \
    --output-file "$OUT_PATH" \
    > "$A_DIR/stdout.log" 2> "$STDERR_LOG" &
BG_PID=$!

# Deterministic readiness: poll until the stub's loop-entered marker
# exists (set on first ci-status.sh call inside the polling loop).
# Cap the wait at ~10 seconds defensively.
DEADLINE=$((SECONDS + 10))
while [ ! -f "$A_DIR/loop-entered" ]; do
    if [ "$SECONDS" -ge "$DEADLINE" ]; then
        fail "A: loop-entered marker not created within 10s; ci-wait.sh did not enter polling loop"
        kill -KILL "$BG_PID" 2>/dev/null || true
        wait "$BG_PID" 2>/dev/null || true
        BG_PID=""
        break
    fi
    sleep 0.05
done

if [ -n "${BG_PID:-}" ] && kill -0 "$BG_PID" 2>/dev/null; then
    # Small additional buffer to ensure the trap chain is fully installed
    # and the loop has reached `sleep 10`.
    sleep 0.5

    # Send SIGTERM mid-poll. The EXIT trap must fire and produce both
    # the published KV output file AND the .done sentinel.
    kill -TERM "$BG_PID"
    wait "$BG_PID" 2>/dev/null || true
    BG_PID=""

    # Assertion 1: KV output file exists.
    if [ -f "$OUT_PATH" ]; then
        ok "A: <output-file> exists at $OUT_PATH"
    else
        fail "A: <output-file> NOT created at $OUT_PATH"
    fi

    # Assertion 2: KV output file has a parseable ACTION= line.
    if [ -f "$OUT_PATH" ] && grep -q '^ACTION=' "$OUT_PATH"; then
        ok "A: <output-file> contains parseable ACTION= line"
    else
        fail "A: <output-file> missing or malformed (no ACTION= line)"
    fi

    # Assertion 3: .done sentinel exists.
    if [ -f "${OUT_PATH}.done" ]; then
        ok "A: <output-file>.done sentinel exists"
    else
        fail "A: <output-file>.done sentinel NOT written"
    fi

    # Assertion 4: .done sentinel content is a parseable integer
    # (mirrors run-external-agent.sh's numeric exit-code idiom).
    if [ -f "${OUT_PATH}.done" ]; then
        DONE_CONTENT="$(tr -d '[:space:]' < "${OUT_PATH}.done")"
        if [[ "$DONE_CONTENT" =~ ^[0-9]+$ ]]; then
            ok "A: <output-file>.done content is parseable integer ($DONE_CONTENT)"
        else
            fail "A: <output-file>.done content not numeric: '$DONE_CONTENT'"
        fi
    fi

    # Assertion 5: temp-file artifact was cleaned up by the atomic publish.
    if [ ! -f "${OUT_PATH}.tmp" ]; then
        ok "A: <output-file>.tmp does not linger after atomic publish"
    else
        fail "A: <output-file>.tmp leaked — atomic publish (mv -f) did not complete"
    fi
fi

# ----------------------------------------------------------------------
# Sub-test B — default-mode (stdout) backward-compat
# ----------------------------------------------------------------------
echo
echo "Sub-test B: default-mode (stdout) backward-compat — no --output-file flag"

B_DIR="$TMPDIR_BASE/B"
mkdir -p "$B_DIR"
cp "$REPO_ROOT/scripts/ci-wait.sh" "$B_DIR/ci-wait.sh"
chmod +x "$B_DIR/ci-wait.sh"

# Stub ci-status.sh — returns pass status so ci-decide.sh can return ACTION=merge.
cat > "$B_DIR/ci-status.sh" <<'SH'
#!/usr/bin/env bash
echo "CI_STATUS=pass"
echo "BEHIND_COUNT=0"
echo "FAILED_RUN_ID="
SH
chmod +x "$B_DIR/ci-status.sh"

# Stub ci-decide.sh — returns ACTION=merge so the polling loop exits cleanly
# on the first iteration without needing a signal-kill.
cat > "$B_DIR/ci-decide.sh" <<'SH'
#!/usr/bin/env bash
echo "ACTION=merge"
echo "BAIL_REASON="
SH
chmod +x "$B_DIR/ci-decide.sh"

set +e
B_STDOUT="$(bash "$B_DIR/ci-wait.sh" --pr 999 --repo test/repo --timeout 5 2> "$B_DIR/stderr.log")"
B_EXIT=$?
set -e

# Assertion 6: script exited cleanly (exit 0) on the merge path.
if [ "$B_EXIT" -eq 0 ]; then
    ok "B: ci-wait.sh exited 0 on ACTION=merge path"
else
    fail "B: ci-wait.sh exited $B_EXIT (expected 0)"
fi

# Assertion 7: all 7 KV keys appear on stdout, in order.
EXPECTED_KEYS=("ACTION=" "CI_STATUS=" "BEHIND_COUNT=" "FAILED_RUN_ID=" "BAIL_REASON=" "ITERATION=" "ELAPSED=")
ALL_KEYS_PRESENT=true
LAST_LINE_NUM=0
for key in "${EXPECTED_KEYS[@]}"; do
    LINE_NUM="$(echo "$B_STDOUT" | grep -n -F "$key" | head -1 | cut -d: -f1)"
    if [ -z "$LINE_NUM" ]; then
        ALL_KEYS_PRESENT=false
        fail "B: expected stdout key '$key' not found"
        break
    fi
    if [ "$LINE_NUM" -le "$LAST_LINE_NUM" ]; then
        ALL_KEYS_PRESENT=false
        fail "B: stdout keys out of order — '$key' at line $LINE_NUM but previous at line $LAST_LINE_NUM"
        break
    fi
    LAST_LINE_NUM="$LINE_NUM"
done
if $ALL_KEYS_PRESENT; then
    ok "B: all 7 KV keys present on stdout in correct order"
fi

# Assertion 8: no file-mode side effects.
if [ ! -f "$B_DIR/out.txt" ] && [ ! -f "$B_DIR/out.txt.done" ] && [ ! -f "$B_DIR/out.txt.tmp" ]; then
    ok "B: no implicit file-mode side effects (no out.txt / out.txt.done / out.txt.tmp)"
else
    fail "B: file-mode side effects detected without --output-file"
fi

# ----------------------------------------------------------------------
# Sub-test C — fail-closed: publish failure must NOT produce .done sentinel
# ----------------------------------------------------------------------
# Forces the atomic publish (mv -f) to fail by directing --output-file at a
# path inside a read-only directory. The trap should NOT write .done when
# emit_output's publish chain fails — consumers waiting on .done time out
# rather than parsing a missing or stale <path>. Closes the regression vector
# flagged by /review's panel where the trap previously wrote .done unconditionally.
echo
echo "Sub-test C: fail-closed — publish failure must NOT create .done"

C_DIR="$TMPDIR_BASE/C"
mkdir -p "$C_DIR"
cp "$REPO_ROOT/scripts/ci-wait.sh" "$C_DIR/ci-wait.sh"
chmod +x "$C_DIR/ci-wait.sh"

# Stub helpers — same shape as Sub-test B (ACTION=merge, exit cleanly).
cat > "$C_DIR/ci-status.sh" <<'SH'
#!/usr/bin/env bash
echo "CI_STATUS=pass"
echo "BEHIND_COUNT=0"
echo "FAILED_RUN_ID="
SH
chmod +x "$C_DIR/ci-status.sh"

cat > "$C_DIR/ci-decide.sh" <<'SH'
#!/usr/bin/env bash
echo "ACTION=merge"
echo "BAIL_REASON="
SH
chmod +x "$C_DIR/ci-decide.sh"

# Read-only directory — atomic publish (mv into a read-only dir) MUST fail.
RO_DIR="$C_DIR/ro"
mkdir -p "$RO_DIR"
chmod 555 "$RO_DIR"
C_OUT_PATH="$RO_DIR/out.txt"

set +e
bash "$C_DIR/ci-wait.sh" \
    --pr 999 --repo test/repo --timeout 5 \
    --output-file "$C_OUT_PATH" \
    > "$C_DIR/stdout.log" 2> "$C_DIR/stderr.log"
set -e

# Restore writability so EXIT cleanup can rm -rf the tmpdir.
chmod 755 "$RO_DIR"

# Assertion 9: <path>.done MUST NOT exist on publish failure (fail-closed).
if [ ! -f "${C_OUT_PATH}.done" ]; then
    ok "C: <output-file>.done correctly absent on publish failure (fail-closed)"
else
    fail "C: <output-file>.done was written despite publish failure — fail-closed contract violated"
fi

# Assertion 10: <path> MUST NOT exist (or if it does, it should not be the
# stale-clear leftover the script removes at startup) — confirms publish
# never produced the final file.
if [ ! -f "$C_OUT_PATH" ]; then
    ok "C: <output-file> correctly absent on publish failure"
else
    fail "C: <output-file> exists despite read-only directory — atomic publish unexpectedly succeeded"
fi

# ----------------------------------------------------------------------
echo
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [ "$FAIL_COUNT" -gt 0 ]; then
    echo "FAIL"
    exit 1
fi
echo "PASS"
exit 0
