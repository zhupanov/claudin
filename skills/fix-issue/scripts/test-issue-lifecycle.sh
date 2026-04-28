#!/usr/bin/env bash
# test-issue-lifecycle.sh — Regression harness for skills/fix-issue/scripts/issue-lifecycle.sh.
#
# Covers the `close` subcommand's idempotent-close behavior added for
# /fix-issue close idempotency (Phase 2 of umbrella #348). Uses a
# PATH-prepended stub `gh` under $TMPDIR that sub-dispatches on the first two
# positional args and on the `--json` argument for `issue view` (state vs body).
# The stub records every invocation to a sidecar log so fixtures can assert
# which gh subcommands ran.
#
# Fixtures:
#   1. OPEN, no --pr-url           — existing behavior; close invoked.
#   2. CLOSED, no --pr-url         — idempotency; close NOT invoked; stderr INFO.
#   3. CLOSED with --pr-url        — body backfill + DONE + skip close.
#   4. OPEN with --pr-url (parity) — body backfill + DONE + close.
#   5. Probe-failure, close succeeds — probe exits 1; WARNING to stderr; fall
#                                      back to close; CLOSED=true.
#   6. Probe-failure, close fails  — probe exits 1; close also fails; fatal with
#                                    CLOSED=false + ERROR=Failed to close.
#   7. Partial-success retry path  — call 1 fails (probe+close forced fail) AFTER
#                                    posting the DONE comment; call 2 succeeds;
#                                    combined log shows TWO comment|42|DONE lines
#                                    (regression guard for documented behavior).
#
# Scope: offline, hermetic (no network, no git state change). All scratch
# state under $TMPDIR; torn down by EXIT trap.
#
# Usage:
#   bash skills/fix-issue/scripts/test-issue-lifecycle.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed (first failure listed on stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$REPO_ROOT/skills/fix-issue/scripts/issue-lifecycle.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "ERROR: target script not found or not executable: $SCRIPT" >&2
    exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-issue-lifecycle-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

# --- Counters and helpers --------------------------------------------------
PASS=0
FAIL=0
FAILED_TESTS=()

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (== $expected)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected $(printf '%q' "$expected"), got $(printf '%q' "$actual"))")
        echo "  FAIL: $label (expected $(printf '%q' "$expected"), got $(printf '%q' "$actual"))" >&2
    fi
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (contains $needle)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing $needle)")
        echo "  FAIL: $label (missing $needle)" >&2
        echo "       haystack (first 500 chars): ${haystack:0:500}" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (does not contain $needle)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (unexpectedly contains $needle)")
        echo "  FAIL: $label (unexpectedly contains $needle)" >&2
        echo "       haystack (first 500 chars): ${haystack:0:500}" >&2
    fi
}

# new_stub_bin — builds a fresh $bin dir with a stub `gh` that reads
# $STUB_STATE (OPEN|CLOSED), $STUB_PROBE_FAIL (1 = probe fails), and
# $STUB_CLOSE_FAIL (1 = `gh issue close` exits non-zero). Logs invocations to
# $INVOCATIONS_LOG. Returns $bin on stdout.
new_stub_bin() {
    local bin="$TMPROOT/$1"
    mkdir -p "$bin"
    cat > "$bin/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Stub gh for test-issue-lifecycle.sh. Dispatches on "$1 $2" and on --json field.
# Logs every invocation to $INVOCATIONS_LOG (one line per call).
set -u

# Record invocation (one line: subcmd|issue|extra). The exact shape is simple
# so assertions can substring-match on the subcommand + args.
log_invocation() {
    local line="$1"
    printf '%s\n' "$line" >> "${INVOCATIONS_LOG:-/dev/null}"
}

case "${1:-}" in
    repo)
        if [[ "${2:-}" == "view" ]]; then
            # gh repo view --json nameWithOwner --jq .nameWithOwner
            echo "owner/repo"
            exit 0
        fi
        ;;
    issue)
        case "${2:-}" in
            view)
                # gh issue view <N> --json <field> --jq <filter>
                # Sub-dispatch on the --json argument to distinguish state vs body.
                local_json=""
                local_issue="${3:-}"
                shift 3 2>/dev/null || true
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --json) local_json="${2:-}"; shift 2 ;;
                        --jq) shift 2 ;;
                        *) shift ;;
                    esac
                done
                log_invocation "view|$local_issue|$local_json"
                case "$local_json" in
                    state)
                        if [[ "${STUB_PROBE_FAIL:-0}" == "1" ]]; then
                            echo "stub: probe failure forced" >&2
                            exit 1
                        fi
                        echo "${STUB_STATE:-OPEN}"
                        exit 0
                        ;;
                    body)
                        echo ""
                        exit 0
                        ;;
                    *)
                        echo ""
                        exit 0
                        ;;
                esac
                ;;
            comment)
                # gh issue comment <N> --body <text>
                local_issue="${3:-}"
                shift 3 2>/dev/null || true
                local_body=""
                while [[ $# -gt 0 ]]; do
                    case "$1" in
                        --body) local_body="${2:-}"; shift 2 ;;
                        *) shift ;;
                    esac
                done
                log_invocation "comment|$local_issue|$local_body"
                exit 0
                ;;
            edit)
                # gh issue edit <N> --body <text>
                local_issue="${3:-}"
                log_invocation "edit|$local_issue|body-updated"
                exit 0
                ;;
            close)
                # gh issue close <N>
                local_issue="${3:-}"
                log_invocation "close|$local_issue"
                if [[ "${STUB_CLOSE_FAIL:-0}" == "1" ]]; then
                    echo "stub: close failure forced" >&2
                    exit 1
                fi
                exit 0
                ;;
        esac
        ;;
    api)
        # Not exercised by cmd_close but included so harness stays robust if
        # cmd_close ever adds an api call.
        log_invocation "api|${*}"
        echo "[]"
        exit 0
        ;;
esac
# Any unhandled gh invocation: log and exit 0 (harness assertions decide).
log_invocation "UNHANDLED|$*"
exit 0
STUB_EOF
    chmod +x "$bin/gh"
    printf '%s' "$bin"
}

run_case() {
    # run_case <label> <stub_state> <probe_fail> <close_fail> <extra_args...>
    # Globals set: RC, CLOSE_STDOUT, CLOSE_STDERR, INVOCATIONS_LOG
    local label="$1" stub_state="$2" probe_fail="$3" close_fail="$4"
    shift 4
    local case_dir="$TMPROOT/$label"
    mkdir -p "$case_dir"
    local bin
    bin=$(new_stub_bin "$label.bin")
    export INVOCATIONS_LOG="$case_dir/gh-invocations.log"
    : > "$INVOCATIONS_LOG"
    export STUB_STATE="$stub_state"
    export STUB_PROBE_FAIL="$probe_fail"
    export STUB_CLOSE_FAIL="$close_fail"
    set +e
    CLOSE_STDOUT=$(PATH="$bin:$PATH" "$SCRIPT" close "$@" 2>"$case_dir/stderr.log")
    RC=$?
    set -e
    CLOSE_STDERR=$(cat "$case_dir/stderr.log")
    unset STUB_STATE STUB_PROBE_FAIL STUB_CLOSE_FAIL INVOCATIONS_LOG
}

# --- Fixture 1: OPEN, no --pr-url -----------------------------------------
echo "=== 1: OPEN, no --pr-url ==="
run_case "f1" "OPEN" "0" "0" --issue 42 --comment DONE
assert_eq "[f1] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f1] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f1] stdout has no CLOSED=false"
assert_not_contains "$CLOSE_STDOUT" "UPDATED=" "[f1] no UPDATED= leak on stdout"
log1=$(cat "$TMPROOT/f1/gh-invocations.log")
assert_contains "$log1" "comment|42|DONE" "[f1] DONE comment posted"
assert_contains "$log1" "close|42" "[f1] gh issue close invoked (OPEN branch)"

# --- Fixture 2: CLOSED, no --pr-url ---------------------------------------
echo ""
echo "=== 2: CLOSED, no --pr-url ==="
run_case "f2" "CLOSED" "0" "0" --issue 42 --comment DONE
assert_eq "[f2] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f2] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f2] stdout has no CLOSED=false"
assert_contains "$CLOSE_STDERR" "INFO: issue #42 already closed" "[f2] stderr INFO note present"
log2=$(cat "$TMPROOT/f2/gh-invocations.log")
assert_contains "$log2" "comment|42|DONE" "[f2] DONE comment posted"
assert_not_contains "$log2" "close|42" "[f2] gh issue close SKIPPED (CLOSED branch)"

# --- Fixture 3: CLOSED with --pr-url --------------------------------------
echo ""
echo "=== 3: CLOSED with --pr-url ==="
run_case "f3" "CLOSED" "0" "0" --issue 42 --comment DONE --pr-url "https://example.com/pr/1"
assert_eq "[f3] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f3] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f3] stdout has no CLOSED=false"
# FINDING_2 regression guard: cmd_update_body's stdout must not leak into cmd_close's stdout.
assert_not_contains "$CLOSE_STDOUT" "UPDATED=" "[f3] no UPDATED= leak on stdout (FINDING_2 guard)"
assert_not_contains "$CLOSE_STDOUT" "SKIPPED=" "[f3] no SKIPPED= leak on stdout (FINDING_2 guard)"
assert_contains "$CLOSE_STDERR" "INFO: issue #42 already closed" "[f3] stderr INFO note present"
log3=$(cat "$TMPROOT/f3/gh-invocations.log")
assert_contains "$log3" "edit|42|" "[f3] body backfill (gh issue edit) ran"
assert_contains "$log3" "comment|42|DONE" "[f3] DONE comment posted"
assert_not_contains "$log3" "close|42" "[f3] gh issue close SKIPPED (CLOSED branch)"

# --- Fixture 4: OPEN with --pr-url (parity) -------------------------------
echo ""
echo "=== 4: OPEN with --pr-url (parity) ==="
run_case "f4" "OPEN" "0" "0" --issue 42 --comment DONE --pr-url "https://example.com/pr/1"
assert_eq "[f4] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f4] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "UPDATED=" "[f4] no UPDATED= leak on stdout"
log4=$(cat "$TMPROOT/f4/gh-invocations.log")
assert_contains "$log4" "edit|42|" "[f4] body backfill ran"
assert_contains "$log4" "comment|42|DONE" "[f4] DONE comment posted"
assert_contains "$log4" "close|42" "[f4] gh issue close invoked (OPEN branch)"

# --- Fixture 5: Probe failure, close succeeds -----------------------------
# On probe failure, cmd_close logs a WARNING to stderr and falls through to
# `gh issue close`. If close succeeds, the final outcome is CLOSED=true —
# the OPEN-path reliability from pre-PR days is preserved even when the
# read-side probe flakes.
echo ""
echo "=== 5: Probe failure, close succeeds ==="
run_case "f5" "OPEN" "1" "0" --issue 42 --comment DONE
assert_eq "[f5] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f5] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f5] stdout has no CLOSED=false"
assert_contains "$CLOSE_STDERR" "WARNING: failed to probe state for issue #42" "[f5] stderr WARNING on probe failure"
log5=$(cat "$TMPROOT/f5/gh-invocations.log")
assert_contains "$log5" "comment|42|DONE" "[f5] DONE comment posted"
assert_contains "$log5" "close|42" "[f5] gh issue close invoked (fallback on probe failure)"

# --- Fixture 6: Probe failure, close also fails ---------------------------
# If BOTH the probe AND the close fail, cmd_close reports the close failure
# (the final observable error) rather than the probe failure — matching
# the script's "last error wins" error-surfacing posture for gh calls.
echo ""
echo "=== 6: Probe failure, close also fails ==="
run_case "f6" "OPEN" "1" "1" --issue 42 --comment DONE
assert_eq "[f6] exit code" 1 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=false" "[f6] stdout has CLOSED=false"
assert_contains "$CLOSE_STDOUT" "ERROR=Failed to close issue #42" "[f6] stdout has ERROR=Failed to close"
assert_contains "$CLOSE_STDERR" "WARNING: failed to probe state for issue #42" "[f6] stderr WARNING on probe failure"
log6=$(cat "$TMPROOT/f6/gh-invocations.log")
assert_contains "$log6" "close|42" "[f6] gh issue close attempted (fallback, though it failed)"

# --- Fixture 7: Partial-success retry path --------------------------------
# Documents the partial-success class noted in
# skills/fix-issue/scripts/issue-lifecycle.md "Partial-success semantics":
# the --comment (DONE) post runs BEFORE the state probe and `gh issue close`,
# so when the close fails after the comment succeeds, a naive caller retry
# re-posts the DONE comment. Call 1 forces the probe + close to fail (same
# pattern as Fixture 6) — the runner sees CLOSED=false but the issue already
# has the DONE comment posted. Call 2 is a clean retry — it posts a SECOND
# DONE comment, then probes (now succeeds and reports OPEN — first close
# never landed) and closes. The two run_case calls allocate separate stub
# bins and invocation logs; we concatenate the logs to assert exactly two
# comment|42|DONE lines, which is the regression guard the issue asks for:
# any future change that breaks the current comment-before-probe-then-close
# ordering (e.g., moves the comment post AFTER the close call), or that
# adds an idempotency guard for already-posted DONE comments, will drop
# one of the two comment|42|DONE lines and fail this fixture, forcing
# the documented partial-success-semantics contract in
# skills/fix-issue/scripts/issue-lifecycle.md to be updated in the same PR.
echo ""
echo "=== 7: Partial-success retry path (call 1 fails after comment, call 2 succeeds) ==="
# Call 1: probe + close both fail; DONE comment is posted before the failures.
run_case "f7a" "OPEN" "1" "1" --issue 42 --comment DONE
assert_eq "[f7a] exit code" 1 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=false" "[f7a] stdout has CLOSED=false"
assert_contains "$CLOSE_STDOUT" "ERROR=Failed to close issue #42" "[f7a] stdout has ERROR=Failed to close"
assert_contains "$CLOSE_STDERR" "WARNING: failed to probe state for issue #42" "[f7a] stderr WARNING on probe failure (pins probe+close-fail branch like Fixture 6)"
log7a=$(cat "$TMPROOT/f7a/gh-invocations.log")
assert_contains "$log7a" "comment|42|DONE" "[f7a] DONE comment WAS posted before close failed (partial-success class)"
assert_contains "$log7a" "close|42" "[f7a] gh issue close attempted (and failed)"

# Call 2: clean retry — probe succeeds, returns OPEN (first close never
# landed), close succeeds. A SECOND DONE comment is posted because cmd_close
# does not idempotently guard the comment post.
run_case "f7b" "OPEN" "0" "0" --issue 42 --comment DONE
assert_eq "[f7b] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f7b] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f7b] stdout has no CLOSED=false"
log7b=$(cat "$TMPROOT/f7b/gh-invocations.log")
assert_contains "$log7b" "comment|42|DONE" "[f7b] DONE comment posted on retry"
assert_contains "$log7b" "close|42" "[f7b] gh issue close invoked on retry"

# Combined-log duplicate-comment regression guard: exactly two DONE comments
# across the two runs (one from each call) — proves the documented
# partial-success retry behavior.
combined_log=$(cat "$TMPROOT/f7a/gh-invocations.log" "$TMPROOT/f7b/gh-invocations.log")
done_comment_count=$(printf '%s\n' "$combined_log" | grep -c '^comment|42|DONE$' || true)
assert_eq "[f7] DONE comment posted exactly twice across retry sequence" 2 "$done_comment_count"

# --- Fixture 8: --repo silently ignored ----------------------------------
# The LLM occasionally passes --repo to close (the script resolves repo
# internally via gh repo view). Verify --repo is silently consumed without
# affecting stdout or close behavior.
echo ""
echo "=== 8: close with spurious --repo (silently ignored) ==="
run_case "f8" "OPEN" "0" "0" --issue 42 --comment DONE --repo "owner/repo"
assert_eq "[f8] exit code" 0 "$RC"
assert_contains "$CLOSE_STDOUT" "CLOSED=true" "[f8] stdout has CLOSED=true"
assert_not_contains "$CLOSE_STDOUT" "CLOSED=false" "[f8] stdout has no CLOSED=false"
log8=$(cat "$TMPROOT/f8/gh-invocations.log")
assert_contains "$log8" "comment|42|DONE" "[f8] DONE comment posted"
assert_contains "$log8" "close|42" "[f8] gh issue close invoked"

# --- Summary --------------------------------------------------------------
echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if (( FAIL > 0 )); then
    echo "" >&2
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
exit 0
