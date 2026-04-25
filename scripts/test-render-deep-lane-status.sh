#!/usr/bin/env bash
# test-render-deep-lane-status.sh — offline regression harness for
# render-deep-lane-status.sh.
#
# Asserts byte-exact stdout for happy-path cases and the contract's behavior
# under error conditions (exit code + stderr) for missing-input / unknown-token /
# usage-error fixtures. Closes #451.
#
# Phase-segregation guard fixtures (F2 + F3) are the direct bug-fix witnesses
# for #451: they verify that a validation-only fallback does NOT taint
# research-phase attribution (and vice versa).
#
# Fixture cases:
#   F1 — happy path (all four lanes ok)
#   F2 — phase-segregation guard: research OK, validation fallback (BUG WITNESS)
#   F3 — phase-segregation guard: research fallback, validation OK (BUG WITNESS)
#   F4 — full fallback / mixed reasons with sanitization (=, |, whitespace)
#   F4b — runtime-failed reason exceeding 80 chars must truncate
#   F5 — unknown status token (asserts deep-attributed stderr)
#   F6 — missing input (asserts exit 2 + stderr)
#   F7 — usage error: --input flag omitted (asserts exit 1)
#   F7b — usage error: unknown flag (asserts exit 1)

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd -P)"
SCRIPT="$REPO_ROOT/scripts/render-deep-lane-status.sh"

PASS=0
FAIL=0
FAIL_DETAILS=()

fail() {
    FAIL=$((FAIL + 1))
    FAIL_DETAILS+=("$1")
}

pass() {
    PASS=$((PASS + 1))
}

assert_stdout_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass
    else
        fail "$label
  EXPECTED:
$(printf '%s' "$expected" | sed 's/^/    /')
  ACTUAL:
$(printf '%s' "$actual" | sed 's/^/    /')"
    fi
}

assert_stderr_contains() {
    local label="$1"
    local needle="$2"
    local actual="$3"
    case "$actual" in
        *"$needle"*) pass ;;
        *) fail "$label
  EXPECTED stderr to contain: $needle
  ACTUAL stderr:
$(printf '%s' "$actual" | sed 's/^/    /')" ;;
    esac
}

assert_exit_equals() {
    local label="$1"
    local expected="$2"
    local actual="$3"
    if [ "$actual" = "$expected" ]; then
        pass
    else
        fail "$label
  EXPECTED exit: $expected
  ACTUAL exit:   $actual"
    fi
}

TMPDIR_LOCAL="$(mktemp -d "/tmp/test-render-deep-lane-status-XXXXXX")"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

run_render() {
    local input="$1"
    local out_file err_file rc
    out_file="$TMPDIR_LOCAL/out"
    err_file="$TMPDIR_LOCAL/err"
    rc=0
    "$SCRIPT" --input "$input" >"$out_file" 2>"$err_file" || rc=$?
    STDOUT="$(cat "$out_file")"
    STDERR="$(cat "$err_file")"
    EXIT="$rc"
}

# ---------- Fixture 1 — happy path ----------
cat > "$TMPDIR_LOCAL/f1.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f1.txt"
assert_exit_equals "F1.exit" "0" "$EXIT"
assert_stdout_equals "F1.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: ✅, Cursor-Edge: ✅, Codex-Ext: ✅, Codex-Sec: ✅)
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 2 — PHASE SEGREGATION GUARD: research OK, validation fallback ----------
# Direct bug witness for #451: a validation-only fallback must NOT taint
# research-phase attribution. Cursor research slots stay ✅ even though
# Cursor validation is fallback_runtime_failed.
cat > "$TMPDIR_LOCAL/f2.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=fallback_runtime_failed
VALIDATION_CURSOR_REASON=cursor crashed during validation
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f2.txt"
assert_exit_equals "F2.exit" "0" "$EXIT"
assert_stdout_equals "F2.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: ✅, Cursor-Edge: ✅, Codex-Ext: ✅, Codex-Sec: ✅)
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: Claude-fallback (runtime failed: cursor crashed during validation), Codex: ✅)" "$STDOUT"

# ---------- Fixture 3 — PHASE SEGREGATION GUARD: research fallback, validation OK ----------
# Inverse of F2. Research-phase fallback must NOT taint validation-phase
# attribution. The Cursor research aggregate covers BOTH Cursor-Arch and
# Cursor-Edge slots simultaneously per the deep aggregate semantics.
cat > "$TMPDIR_LOCAL/f3.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=fallback_runtime_timeout
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=ok
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f3.txt"
assert_exit_equals "F3.exit" "0" "$EXIT"
assert_stdout_equals "F3.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: Claude-fallback (runtime timeout), Cursor-Edge: Claude-fallback (runtime timeout), Codex-Ext: ✅, Codex-Sec: ✅)
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 4 — mixed fallback reasons with sanitization ----------
# Exercises every fallback variant + reason sanitization (= and | stripping,
# whitespace collapse). String after sanitization fits under 80 chars (no
# truncation).
{
    printf 'RESEARCH_CURSOR_STATUS=fallback_binary_missing\n'
    printf 'RESEARCH_CURSOR_REASON=\n'
    printf 'RESEARCH_CODEX_STATUS=fallback_probe_failed\n'
    printf 'RESEARCH_CODEX_REASON=connection refused on port 5050\n'
    printf 'VALIDATION_CURSOR_STATUS=fallback_runtime_failed\n'
    printf 'VALIDATION_CURSOR_REASON=exit code 124  killed after timeout |||  with == bad chars\n'
    printf 'VALIDATION_CODEX_STATUS=fallback_runtime_timeout\n'
    printf 'VALIDATION_CODEX_REASON=\n'
} > "$TMPDIR_LOCAL/f4.txt"
run_render "$TMPDIR_LOCAL/f4.txt"
assert_exit_equals "F4.exit" "0" "$EXIT"
assert_stdout_equals "F4.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: Claude-fallback (binary missing), Cursor-Edge: Claude-fallback (binary missing), Codex-Ext: Claude-fallback (probe failed: connection refused on port 5050), Codex-Sec: Claude-fallback (probe failed: connection refused on port 5050))
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: Claude-fallback (runtime failed: exit code 124 killed after timeout with bad chars), Codex: Claude-fallback (runtime timeout))" "$STDOUT"

# ---------- Fixture 4b — runtime-failed reason that exceeds 80 chars must truncate ----------
{
    printf 'RESEARCH_CURSOR_STATUS=ok\n'
    printf 'RESEARCH_CURSOR_REASON=\n'
    printf 'RESEARCH_CODEX_STATUS=fallback_runtime_failed\n'
    printf 'RESEARCH_CODEX_REASON=AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA_BEYOND_TRUNCATION\n'
    printf 'VALIDATION_CURSOR_STATUS=ok\n'
    printf 'VALIDATION_CURSOR_REASON=\n'
    printf 'VALIDATION_CODEX_STATUS=ok\n'
    printf 'VALIDATION_CODEX_REASON=\n'
} > "$TMPDIR_LOCAL/f4b.txt"
run_render "$TMPDIR_LOCAL/f4b.txt"
assert_exit_equals "F4b.exit" "0" "$EXIT"
assert_stdout_equals "F4b.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: ✅, Cursor-Edge: ✅, Codex-Ext: Claude-fallback (runtime failed: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA), Codex-Sec: Claude-fallback (runtime failed: AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA))
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"

# ---------- Fixture 5 — unknown status token (deep-attributed stderr per FINDING_2) ----------
cat > "$TMPDIR_LOCAL/f5.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=ok
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=fallback-binary-missing
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
run_render "$TMPDIR_LOCAL/f5.txt"
assert_exit_equals "F5.exit" "0" "$EXIT"
assert_stdout_equals "F5.stdout" \
"RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: ✅, Cursor-Edge: ✅, Codex-Ext: (unknown), Codex-Sec: (unknown))
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: ✅, Codex: ✅)" "$STDOUT"
# CRITICAL: this assertion locks in the deep-attributed warning per FINDING_2.
# If RENDER_LANE_CALLER is dropped or mis-set, the warning will say
# `render-lane-status:` instead of `render-deep-lane-status:` and this fails.
assert_stderr_contains "F5.stderr" "render-deep-lane-status: unknown status token fallback-binary-missing" "$STDERR"

# ---------- Fixture 6 — missing input ----------
run_render "$TMPDIR_LOCAL/does-not-exist.txt"
assert_exit_equals "F6.exit" "2" "$EXIT"
assert_stderr_contains "F6.stderr" "render-deep-lane-status: input file missing" "$STDERR"

# ---------- Fixture 7 — usage error: --input flag omitted ----------
EXIT=0
"$SCRIPT" >"$TMPDIR_LOCAL/out" 2>"$TMPDIR_LOCAL/err" || EXIT=$?
STDOUT="$(cat "$TMPDIR_LOCAL/out")"
STDERR="$(cat "$TMPDIR_LOCAL/err")"
assert_exit_equals "F7.exit" "1" "$EXIT"
assert_stderr_contains "F7.stderr" "render-deep-lane-status: --input is required" "$STDERR"

# ---------- Fixture 7b — usage error: unknown flag ----------
EXIT=0
"$SCRIPT" --bogus >"$TMPDIR_LOCAL/out" 2>"$TMPDIR_LOCAL/err" || EXIT=$?
STDOUT="$(cat "$TMPDIR_LOCAL/out")"
STDERR="$(cat "$TMPDIR_LOCAL/err")"
assert_exit_equals "F7b.exit" "1" "$EXIT"
assert_stderr_contains "F7b.stderr" "render-deep-lane-status: unknown flag: --bogus" "$STDERR"

# ---------- Summary ----------
TOTAL=$((PASS + FAIL))
if [ "$FAIL" -eq 0 ]; then
    echo "PASS: test-render-deep-lane-status.sh — $TOTAL assertions passed across 9 fixture cases"
    exit 0
else
    echo "FAIL: test-render-deep-lane-status.sh — $FAIL of $TOTAL assertions failed" >&2
    for d in "${FAIL_DETAILS[@]}"; do
        printf '%s\n' "$d" >&2
        echo "" >&2
    done
    exit 1
fi
