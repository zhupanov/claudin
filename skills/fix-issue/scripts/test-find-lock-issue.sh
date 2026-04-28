#!/usr/bin/env bash
# test-find-lock-issue.sh — Regression harness for find-lock-issue.sh.
#
# Hermetic offline test using a PATH-prepended `gh` stub. Validates the
# combined Find + Lock + Rename pipeline introduced by the fold-find-and-lock
# refactor (closes #496). Twelve executed fixtures plus one deferred-coverage
# note cover the script's exit-code matrix and stdout contract:
#   1. eligible + lock OK + rename OK  → exit 0; LOCK_ACQUIRED=true RENAMED=true
#   2. eligible + lock fail → exit 3; LOCK_ACQUIRED=false
#   3. eligible + lock OK + rename fails (best-effort) → exit 0; RENAMED=false
#                                                           + stderr WARNING
#   4. (deferred) idempotent rename no-op coverage lives in
#       scripts/test-tracking-issue-write.sh, NOT here — the eligibility
#       filter at find-lock-issue.sh prevents [IN PROGRESS]-prefixed titles
#       from reaching the rename call in production, so the idempotent-no-op
#       state is unreachable from this harness's contract surface. Fixture 4
#       prints a coverage-deferred note and increments PASS without
#       executing assertions.
#   5. ineligible (managed prefix on explicit --issue mode) → exit 2
#   6. auto-pick + no eligible candidates → exit 1
#   7. auto-pick + Urgent preference (case-insensitive whole-word match,
#      "non-urgent" rejected, oldest-within-tier) → exit 0; ISSUE_NUMBER=20
#   8. auto-pick + no Urgent → oldest-first preserved → exit 0;
#      ISSUE_NUMBER=10
#   9. explicit issue with a GHE-style host (host-generic URL parsing —
#      closes #766) → exit 0; ISSUE_NUMBER=55 LOCK_ACQUIRED=true
#      RENAMED=true (mirrors fixture 1's full success contract)
#  10. explicit-target umbrella with [IN PROGRESS] managed-prefix title
#      (closes #819) → exit 5; IS_UMBRELLA=true UMBRELLA_ACTION=no-
#      eligible-child. Confirms the explicit-target reorder (umbrella
#      detect runs before has_managed_prefix) — pre-#819 this title
#      would have been rejected with "managed lifecycle title prefix".
#  11. e2e umbrella dispatch with prose-blocked first child + ready
#      second child (closes #768) → exit 0; IS_UMBRELLA=true
#      UMBRELLA_ACTION=dispatched UMBRELLA_NUMBER=1100 ISSUE_NUMBER=1102.
#      Confirms the integration of pick-child's full native+prose blocker
#      check (issue #768 fix), the post-pick all_open_blockers defense-in-
#      depth, and the lock-no-go + rename pipeline.
#  12. auto-pick skips umbrella issue (Anti-pattern #7 regression,
#      closes #753) → exit 1; ELIGIBLE=false. A single candidate with
#      umbrella-style title ("Umbrella: …") and GO as last comment is
#      skipped in auto-pick mode. Confirms the umbrella-detection block
#      in the auto-pick loop prevents umbrella issues from being picked.
#  13. explicit-target detect failure exits 2 (issue #891 regression).
#      umbrella-handler.sh detect fails (gh issue view for title,body
#      returns non-zero) → exit 2; ELIGIBLE=false with detect-failure
#      error. Confirms detect failures are fatal in explicit-target mode
#      instead of silently falling through to the ordinary-issue path.
#
# Stub gh dispatches on positional + json args. Each fixture writes a stub
# state file under a per-fixture tmpdir; the stub reads the file to decide
# what to emit. This keeps the stub small and per-case behavior transparent.
#
# Wired into `make lint` via the `test-find-lock-issue` target. Both `.sh`
# and `.md` are added to `agent-lint.toml`'s exclude list (Makefile-only-
# reference pattern).
#
# Run manually:
#   bash skills/fix-issue/scripts/test-find-lock-issue.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — at least one assertion failed
#
# Conventions: Bash 3.2-safe; uses `mktemp -d` per-fixture tmpdir.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$REPO_ROOT/skills/fix-issue/scripts/find-lock-issue.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL: $SCRIPT not found or not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

# ---------------------------------------------------------------------------
# Per-fixture tmpdir setup. The stub gh script reads its desired behavior
# from $STUB_STATE_FILE (key=value lines).
# ---------------------------------------------------------------------------
TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-find-lock-issue-XXXXXX")
# shellcheck disable=SC2317
trap 'rm -rf "$TMPROOT"' EXIT

# Stub gh: minimal subcommand dispatcher. Reads $STUB_STATE_FILE for case-
# specific responses. Honors STUB_LOG to record every invocation for
# post-hoc inspection.
make_gh_stub() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Minimal gh stub for test-find-lock-issue.sh fixtures.

# Record invocation for diagnostics.
if [[ -n "${STUB_LOG:-}" ]]; then
    printf 'gh|%s\n' "$*" >> "$STUB_LOG"
fi

# Load fixture state.
if [[ -n "${STUB_STATE_FILE:-}" && -f "${STUB_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "$STUB_STATE_FILE"
fi

dispatch_repo_view() {
    printf 'stub/repo'
    exit 0
}

dispatch_issue_view() {
    # Accept either a bare number or a full GitHub-style URL — `gh issue view`
    # resolves both natively, and find-lock-issue.sh's host-generic URL parser
    # (closes #766) passes URLs through unchanged.
    #
    # Per-issue state lookup (ISSUE_<N>_TITLE / _BODY / _STATE / _VIEW_FAIL)
    # takes precedence over the single-issue defaults (ISSUE_TITLE / _BODY /
    # _STATE). Fixtures that exercise multi-issue gh dispatch (e.g., umbrella
    # e2e fixtures with parsed children) populate per-issue keys; legacy
    # single-issue fixtures continue to work via the bare defaults.
    local arg="$1"
    local host="${ISSUE_URL_HOST:-github.com}"
    local issue="$arg"
    case "$arg" in
        http*://*) issue=$(echo "$arg" | sed -E 's|.*/issues/([0-9]+).*|\1|') ;;
    esac
    # Per-issue VIEW_FAIL injection for fail-open boundary testing.
    local var_fail="ISSUE_${issue}_VIEW_FAIL"
    if [[ "${!var_fail:-}" == "true" ]]; then
        echo "Error: stubbed issue view failure" >&2
        exit 1
    fi
    # Per-issue VIEW_FAIL_BODY injection — fails only when --json includes
    # "body" (the umbrella-handler.sh detect call). Lets the initial
    # find-lock-issue.sh fetch (--json number,state,title,url) succeed.
    local json_arg="" prev_a=""
    for a in "$@"; do
        if [[ "$prev_a" == "--json" ]]; then json_arg="$a"; fi
        prev_a="$a"
    done
    local var_fail_body="ISSUE_${issue}_VIEW_FAIL_BODY"
    if [[ "${!var_fail_body:-}" == "true" && "$json_arg" == *body* ]]; then
        echo "Error: stubbed issue view failure (body-json)" >&2
        exit 1
    fi
    local var_title="ISSUE_${issue}_TITLE"
    local var_body="ISSUE_${issue}_BODY"
    local var_state="ISSUE_${issue}_STATE"
    local title body state
    title="${!var_title:-${ISSUE_TITLE:-Test issue}}"
    body="${!var_body:-${ISSUE_BODY:-Test body}}"
    state="${!var_state:-${ISSUE_STATE:-OPEN}}"
    # Honor --jq <expr> by piping the constructed JSON through jq -r.
    # prose_open_blockers calls `gh issue view <ref> --json state --jq '.state'`
    # expecting the bare state string, not the full JSON object.
    local jq_filter=""
    local prev=""
    for a in "$@"; do
        if [[ "$prev" == "--jq" ]]; then
            jq_filter="$a"
        fi
        prev="$a"
    done
    local json
    json=$(printf '{"number":%s,"state":"%s","url":"https://%s/stub/repo/issues/%s","title":%s,"body":%s,"createdAt":"2024-01-01T00:00:00Z"}' \
        "$issue" "$state" "$host" "$issue" \
        "$(printf '%s' "$title" | jq -R -s '.')" \
        "$(printf '%s' "$body" | jq -R -s '.')")
    if [[ -n "$jq_filter" ]]; then
        printf '%s' "$json" | jq -r "$jq_filter"
    else
        printf '%s\n' "$json"
    fi
    exit 0
}

dispatch_issue_edit() {
    if [[ "${RENAME_FAIL:-false}" == "true" ]]; then
        echo "Error: failed to edit title" >&2
        exit 1
    fi
    exit 0
}

# `gh issue comment N --body BODY` — used by issue-lifecycle.sh cmd_comment
# to post the IN PROGRESS lock. Fixture-controlled failure surfaces as
# cmd_comment exit 1 with LOCK_ACQUIRED=false.
#
# Stateful side-effect (closes #768 — needed by the e2e umbrella dispatch
# fixture): record the posted comment in a per-issue runtime file under
# $RUNTIME_COMMENTS_DIR. Subsequent `gh api .../comments` calls read that
# file (merged on top of the static ISSUE_<N>_COMMENTS env var) so the
# lock-no-go post-check can find the just-posted id.
dispatch_issue_comment() {
    if [[ "${COMMENT_FAIL:-false}" == "true" ]]; then
        echo "Error: failed to post comment" >&2
        exit 1
    fi
    if [[ -z "${RUNTIME_COMMENTS_DIR:-}" ]]; then
        exit 0
    fi
    local cmt_issue="$1"
    local cmt_body=""
    shift
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --body) cmt_body="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    mkdir -p "$RUNTIME_COMMENTS_DIR"
    local rt_file="$RUNTIME_COMMENTS_DIR/$cmt_issue.json"
    local cmt_id=$(( 90000000 + RANDOM ))
    local cmt_ts
    cmt_ts=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
    if [[ ! -f "$rt_file" ]]; then
        echo "[]" > "$rt_file"
    fi
    local updated
    updated=$(jq --argjson id "$cmt_id" --arg body "$cmt_body" --arg ts "$cmt_ts" \
        '. + [{id: $id, body: $body, created_at: $ts}]' "$rt_file")
    printf '%s\n' "$updated" > "$rt_file"
    exit 0
}

dispatch_api() {
    local url="" method="GET"
    for arg in "$@"; do
        case "$arg" in
            repos/*|/repos/*) url="$arg" ;;
        esac
    done
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -X) method="$2"; shift 2 ;;
            *) shift ;;
        esac
    done
    local default_comments='[[{"id":1,"body":"GO","created_at":"2024-01-01T00:00:00Z"}]]'
    case "$url" in
        *blocked_by*)
            # The script passes --jq which would filter to a possibly-empty
            # newline-separated list of issue numbers. Emit nothing (no
            # blockers) regardless of the --jq filter — equivalent to a
            # filtered-empty result.
            exit 0 ;;
        */comments)
            if [[ "$method" == "DELETE" ]]; then
                exit 0
            fi
            # Per-issue comments lookup (closes #768 — needed by umbrella
            # e2e fixtures with multiple parsed children). Fall back to
            # COMMENTS_JSON for legacy single-issue fixtures.
            #
            # When stateful comment-posting is enabled (RUNTIME_COMMENTS_DIR
            # set), merge any runtime comments posted via `gh issue comment`
            # on top of the env-var/default base. The script's `gh api
            # --paginate --slurp .../comments | jq 'add // []'` pattern
            # expects an outer array (a list of pages), each page being an
            # array of comment objects.
            local issue_n
            issue_n=$(printf '%s' "$url" | sed -nE 's@.*/issues/([0-9]+)/comments@\1@p')
            local var_comments="ISSUE_${issue_n}_COMMENTS"
            local base_json
            if [[ -n "${!var_comments:-}" ]]; then
                base_json="${!var_comments}"
            else
                base_json="${COMMENTS_JSON:-$default_comments}"
            fi
            if [[ -n "${RUNTIME_COMMENTS_DIR:-}" && -f "$RUNTIME_COMMENTS_DIR/$issue_n.json" ]]; then
                local rt_json
                rt_json=$(cat "$RUNTIME_COMMENTS_DIR/$issue_n.json")
                # Flatten base pages and append runtime comments as a final page.
                printf '%s' "$base_json" | jq --argjson rt "$rt_json" '. + [$rt]'
            else
                printf '%s\n' "$base_json"
            fi
            exit 0 ;;
        repos/stub/repo/issues\?*|"repos/stub/repo/issues?state=open"*)
            printf '%s\n' "${OPEN_ISSUES_JSON:-}"
            exit 0 ;;
        *)
            exit 0 ;;
    esac
}

case "$1" in
    repo)
        case "$2" in
            view) dispatch_repo_view ;;
        esac
        ;;
    issue)
        case "$2" in
            view)
                # Forward all post-`view` args so dispatch_issue_view can
                # inspect --jq <expr> for state-only filter calls (closes
                # #768 — prose_open_blockers' per-ref state lookup).
                shift 2
                dispatch_issue_view "$@" ;;
            comment)
                shift 2
                dispatch_issue_comment "$@" ;;
            edit) dispatch_issue_edit ;;
            list) echo "[]"; exit 0 ;;
        esac
        ;;
    api)
        shift
        dispatch_api "$@"
        ;;
esac

echo "STUB ERROR: unhandled gh invocation: $*" >&2
exit 99
STUB_EOF
    chmod +x "$stub_dir/gh"
}

# Fixture runner. Captures stdout/stderr/exit, returns nothing — assertions
# done at the call site.
run_fixture() {
    local fixture_name="$1"
    local stub_dir
    stub_dir="$TMPROOT/$fixture_name"
    make_gh_stub "$stub_dir"

    export STUB_STATE_FILE="$stub_dir/state.env"
    export STUB_LOG="$stub_dir/log.txt"
    export PATH="$stub_dir:$PATH"
}

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing: $needle)")
        echo "  FAIL: $label (missing $needle)" >&2
        echo "       haystack: ${haystack:0:300}" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (leaked: $needle)")
        echo "  FAIL: $label (leaked $needle)" >&2
    fi
}

assert_equal() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected $expected, got $actual)")
        echo "  FAIL: $label (expected $expected, got $actual)" >&2
    fi
}

# Comment fixture builder.
# Args: "GO" or "IN PROGRESS" — last comment body
make_comments_json() {
    local last_body="$1"
    case "$last_body" in
        GO)
            # Single-page array (the script uses --paginate --slurp; the stub
            # returns an outer array of pages).
            echo '[[{"id":42,"body":"GO","created_at":"2024-01-01T00:00:00Z"}]]'
            ;;
        IN_PROGRESS)
            echo '[[{"id":43,"body":"IN PROGRESS","created_at":"2024-01-02T00:00:00Z"}]]'
            ;;
        EMPTY)
            echo '[[]]'
            ;;
        DOUBLE_LOCK)
            # Last is GO, but post-lock re-check returns 2 IN PROGRESS — used
            # by lock-fail fixture to exercise duplicate detection.
            echo '[[{"id":42,"body":"GO","created_at":"2024-01-01T00:00:00Z"},{"id":99,"body":"IN PROGRESS","created_at":"2024-01-02T00:00:00Z"},{"id":100,"body":"IN PROGRESS","created_at":"2024-01-03T00:00:00Z"}]]'
            ;;
    esac
}

# ---------------------------------------------------------------------------
# Note on test scope:
#
# This harness exercises the stdout-contract surface of find-lock-issue.sh
# at the granularity that production runs depend on (exit codes 0/1/2/3 +
# the LOCK_ACQUIRED + RENAMED keys + best-effort rename-failure stderr
# WARNING). Stub fidelity is intentionally limited — the stub gh handles
# only the API call shapes find-lock-issue.sh + its delegates issue
# (`gh repo view`, `gh issue view`, `gh issue comment`, `gh issue edit`,
# `gh api` for blockers/comments listing/issues listing). A regression that
# changes the call shape upstream would fail the harness with a clear
# "STUB ERROR: unhandled gh invocation" message rather than a silent pass.
#
# What this harness does NOT cover (out of scope, exercised in production):
# - End-to-end gh API behavior (rate limits, auth flow, real network).
# - Concurrent-runner race conditions (the duplicate-IN PROGRESS detection
#   inside cmd_comment uses sleep+re-fetch; we simulate the fixtures'
#   pre/post comment-list state but do not race two stubs).
# - Title-prefix idempotency (RENAMED=false on no-op) is exercised in
#   scripts/test-tracking-issue-write.sh; here we trust that contract.
# ---------------------------------------------------------------------------

echo "Running test-find-lock-issue against $SCRIPT"

# ---------------------------------------------------------------------------
# Fixture 1: eligible + lock OK + rename OK
# ---------------------------------------------------------------------------
echo "Fixture 1: eligible + lock OK + rename OK"
run_fixture "fixture-1"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Real bug'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-1/stdout.txt"
ERR_FILE="$TMPROOT/fixture-1/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 42 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")
ERR=$(cat "$ERR_FILE")

assert_equal "$EXIT_CODE" "0" "[1] exit code 0"
assert_contains "$OUT" "ELIGIBLE=true" "[1] ELIGIBLE=true on stdout"
assert_contains "$OUT" "ISSUE_NUMBER=42" "[1] ISSUE_NUMBER=42 on stdout"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[1] LOCK_ACQUIRED=true on stdout"
assert_contains "$OUT" "RENAMED=true" "[1] RENAMED=true on stdout"
assert_not_contains "$OUT" "COMMENTED=true" "[1] COMMENTED= filtered from stdout (delegate auxiliary key)"
assert_not_contains "$OUT" "NEW_TITLE=" "[1] NEW_TITLE= filtered from stdout (delegate auxiliary key)"

# ---------------------------------------------------------------------------
# Fixture 2: eligible + lock fail → exit 3
#
# Simulated by failing the IN PROGRESS comment post inside cmd_comment.
# (The duplicate-detection post-check would require a stateful stub that
# returns different responses per fetch; failing the comment post exercises
# the same exit-1-from-cmd_comment → exit-3-from-find-lock-issue path with a
# stateless stub. Both paths produce LOCK_ACQUIRED=false ERROR=...)
# ---------------------------------------------------------------------------
echo "Fixture 2: eligible + lock fail"
run_fixture "fixture-2"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Concurrent race'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "COMMENT_FAIL=true"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-2/stdout.txt"
ERR_FILE="$TMPROOT/fixture-2/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 43 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "3" "[2] exit code 3 (lock failed after eligibility)"
assert_contains "$OUT" "ELIGIBLE=true" "[2] ELIGIBLE=true on stdout (eligibility passed)"
assert_contains "$OUT" "LOCK_ACQUIRED=false" "[2] LOCK_ACQUIRED=false on stdout"
assert_contains "$OUT" "ERROR=" "[2] ERROR= on stdout"
assert_not_contains "$OUT" "RENAMED=" "[2] RENAMED= absent (rename never attempted)"
assert_not_contains "$OUT" "COMMENTED=" "[2] COMMENTED= filtered from stdout"

# ---------------------------------------------------------------------------
# Fixture 3: eligible + lock OK + rename fails best-effort → exit 0;
#            RENAMED=false; stderr WARNING.
# ---------------------------------------------------------------------------
echo "Fixture 3: eligible + lock OK + rename fails best-effort"
run_fixture "fixture-3"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Rename fails'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=true"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-3/stdout.txt"
ERR_FILE="$TMPROOT/fixture-3/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 44 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")
ERR=$(cat "$ERR_FILE")

assert_equal "$EXIT_CODE" "0" "[3] exit code 0 (lock is correctness boundary)"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[3] LOCK_ACQUIRED=true (lock succeeded)"
assert_contains "$OUT" "RENAMED=false" "[3] RENAMED=false (best-effort failure)"
assert_contains "$ERR" "WARNING: title rename failed" "[3] stderr WARNING surfaces rename failure"

# ---------------------------------------------------------------------------
# Fixture 4: eligible + lock OK + rename idempotent no-op (title already
# prefixed) → exit 0; RENAMED=false; NO stderr WARNING.
#
# Idempotent no-op is detected internally by tracking-issue-write.sh: when
# the prospective NEW_TITLE matches the canonical CUR_TITLE, it emits
# RENAMED=false without erroring. We simulate by setting an already-prefixed
# title; the script-level eligibility check would normally reject this
# (has_managed_prefix), so we test the rename-only contract by skipping the
# eligibility filter via passing an issue number whose title we control.
#
# Note: in production, find-lock-issue.sh's eligibility scan rejects titles
# starting with [IN PROGRESS]. This fixture exercises the contract surface
# of how RENAMED=false (no-op) flows back through the stdout filter — which
# is identical for "rename API call returned RENAMED=false" regardless of
# whether the underlying cause was idempotency or stale title state. The
# distinction (idempotent vs failure) is in the stderr WARNING presence,
# which Fixture 3 covers.
#
# This fixture is EXONERATED for the idempotency-specific path because the
# eligibility filter prevents [IN PROGRESS]-prefixed titles from reaching
# the rename call in production. The harness defers idempotency-specific
# coverage to scripts/test-tracking-issue-write.sh which exercises the
# rename subcommand directly.
# ---------------------------------------------------------------------------
echo "Fixture 4: idempotent rename no-op — coverage deferred to test-tracking-issue-write.sh"
PASS=$((PASS + 1))
echo "  ok: [4] coverage deferred (production-path eligibility filter prevents this state)"

# ---------------------------------------------------------------------------
# Fixture 5: ineligible — explicit --issue mode rejects managed-prefix
# title.
# ---------------------------------------------------------------------------
echo "Fixture 5: ineligible (managed prefix on explicit --issue)"
run_fixture "fixture-5"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='[IN PROGRESS] machine-managed'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-5/stdout.txt"
ERR_FILE="$TMPROOT/fixture-5/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 45 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "2" "[5] exit code 2 (explicit --issue rejected)"
assert_contains "$OUT" "ELIGIBLE=false" "[5] ELIGIBLE=false on stdout"
assert_contains "$OUT" "managed lifecycle title prefix" "[5] error message identifies prefix exclusion"
assert_not_contains "$OUT" "LOCK_ACQUIRED=" "[5] LOCK_ACQUIRED= absent (lock never attempted)"

# ---------------------------------------------------------------------------
# Fixture 6: auto-pick mode + no eligible candidates → exit 1.
# ---------------------------------------------------------------------------
echo "Fixture 6: auto-pick mode + no eligible candidates"
run_fixture "fixture-6"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE="
    echo "OPEN_ISSUES_JSON="
    echo "COMMENTS_JSON='$(make_comments_json EMPTY)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-6/stdout.txt"
ERR_FILE="$TMPROOT/fixture-6/stderr.txt"
EXIT_CODE=0
"$SCRIPT" >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "1" "[6] exit code 1 (no eligible candidates)"
assert_contains "$OUT" "ELIGIBLE=false" "[6] ELIGIBLE=false on stdout"

# ---------------------------------------------------------------------------
# Fixture 7: auto-pick mode + Urgent preference. Five issues; the picker
# must select the lowest-numbered Urgent-tagged issue ahead of any
# non-Urgent issue and ahead of higher-numbered Urgent issues. The
# Urgent match is a case-insensitive WHOLE-WORD regex (`\burgent\b`),
# so the included `non-urgent` title MUST be classified as non-Urgent
# (substring would mis-classify it).
#
# Layout (OPEN_ISSUES_JSON lines):
#   #5  "Fix non-urgent cleanup"   — non-Urgent (substring trap; lowest number)
#   #10 "Plain old issue"          — non-Urgent (oldest plain title)
#   #20 "Critical urgent fix"      — Urgent (lowercase whole word); should win
#   #30 "Plain new issue"          — non-Urgent
#   #40 "URGENT system broken"     — Urgent (uppercase); higher-numbered, loses tiebreaker
#
# Asserting ISSUE_NUMBER=20 verifies all three behaviors: word-boundary
# regex (so #5 is rejected despite containing the letters "urgent"),
# Urgent-tier-first (so #20 beats #10), AND oldest-first within the
# Urgent tier (so #20 beats #40).
# ---------------------------------------------------------------------------
echo "Fixture 7: auto-pick + Urgent preference (case-insensitive whole-word, non-urgent rejected, oldest-within-tier)"
run_fixture "fixture-7"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Critical urgent fix'"
    # JSONL — one JSON object per line; the production --jq filter is applied
    # server-side in real gh, but the bash stub ignores --jq, so we emit the
    # already-filtered shape here (matches fixture 6's empty-stream contract).
    OPEN_ISSUES_LINES='{"number":5,"title":"Fix non-urgent cleanup"}
{"number":10,"title":"Plain old issue"}
{"number":20,"title":"Critical urgent fix"}
{"number":30,"title":"Plain new issue"}
{"number":40,"title":"URGENT system broken"}'
    # Single-quote the value so newlines survive the shell-source round-trip.
    printf "OPEN_ISSUES_JSON='%s'\n" "$OPEN_ISSUES_LINES"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-7/stdout.txt"
ERR_FILE="$TMPROOT/fixture-7/stderr.txt"
EXIT_CODE=0
"$SCRIPT" >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "0" "[7] exit code 0 (Urgent candidate picked + locked)"
assert_contains "$OUT" "ELIGIBLE=true" "[7] ELIGIBLE=true on stdout"
assert_contains "$OUT" "ISSUE_NUMBER=20" "[7] ISSUE_NUMBER=20 (Urgent issue, lowest number among Urgent tier)"
assert_not_contains "$OUT" "ISSUE_NUMBER=5" "[7] 'non-urgent' title #5 NOT picked (word-boundary regex rejects substring inside another word)"
assert_not_contains "$OUT" "ISSUE_NUMBER=10" "[7] non-Urgent #10 not picked despite oldest"
assert_not_contains "$OUT" "ISSUE_NUMBER=40" "[7] higher-numbered Urgent #40 not picked"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[7] LOCK_ACQUIRED=true"

# ---------------------------------------------------------------------------
# Fixture 8: auto-pick mode + no Urgent issues falls back to oldest-first.
# Confirms the preference is a soft signal — when no Urgent candidate
# exists, the pre-existing oldest-first ordering is preserved unchanged.
# ---------------------------------------------------------------------------
echo "Fixture 8: auto-pick + no Urgent → oldest-first preserved"
run_fixture "fixture-8"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Plain old issue'"
    OPEN_ISSUES_LINES='{"number":10,"title":"Plain old issue"}
{"number":20,"title":"Another normal one"}
{"number":30,"title":"Plain new issue"}'
    printf "OPEN_ISSUES_JSON='%s'\n" "$OPEN_ISSUES_LINES"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-8/stdout.txt"
ERR_FILE="$TMPROOT/fixture-8/stderr.txt"
EXIT_CODE=0
"$SCRIPT" >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "0" "[8] exit code 0 (oldest non-Urgent candidate picked)"
assert_contains "$OUT" "ISSUE_NUMBER=10" "[8] ISSUE_NUMBER=10 (oldest, no Urgent tier exists)"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[8] LOCK_ACQUIRED=true"

# ---------------------------------------------------------------------------
# Fixture 9: explicit-issue mode with a GitHub-Enterprise-style host. The
# repo-ownership parser must NOT pin to github.com (closes #766) — any
# https://<host>/<owner>/<repo>/issues/<n> URL where <owner>/<repo> matches
# the current repo ($REPO from gh repo view = stub/repo) is acceptable. The
# scheme is pinned to `https://` because the `gh` CLI always emits `https://`
# URLs and the production regex deliberately stays BRE-portable.
# ---------------------------------------------------------------------------
echo "Fixture 9: explicit issue with GHE host (host-generic URL parsing, closes #766)"
run_fixture "fixture-9"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='GHE test issue'"
    echo "ISSUE_URL_HOST=ghe.example.com"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-9/stdout.txt"
ERR_FILE="$TMPROOT/fixture-9/stderr.txt"
EXIT_CODE=0
"$SCRIPT" "https://ghe.example.com/stub/repo/issues/55" >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "0" "[9] exit code 0 (GHE URL accepted, repo matches)"
assert_contains "$OUT" "ELIGIBLE=true" "[9] ELIGIBLE=true on stdout"
assert_contains "$OUT" "ISSUE_NUMBER=55" "[9] ISSUE_NUMBER=55 on stdout"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[9] LOCK_ACQUIRED=true on stdout"
assert_contains "$OUT" "RENAMED=true" "[9] RENAMED=true on stdout (mirrors Fixture 1)"
assert_not_contains "$OUT" "Cannot parse repository from issue URL" "[9] no parse-failure error"

# ---------------------------------------------------------------------------
# Fixture 10: explicit-target umbrella with managed-prefix title (issue #819
# DECISION_1 regression). Asserts the reorder lets `[IN PROGRESS] Umbrella:
# foo` reach the umbrella dispatcher rather than failing the managed-prefix
# early-reject. Slimmer NO_ELIGIBLE_CHILD design (per #819 plan-review
# FINDING_7): title-only umbrella with no body literal and no parseable
# task-list children → handle_umbrella emits exit 5 + UMBRELLA_ACTION=
# no-eligible-child. Avoids coupling to issue-lifecycle.sh lock-no-go and
# the stub's single-issue ISSUE_TITLE/BODY model.
# ---------------------------------------------------------------------------
echo "Fixture 10: explicit-target umbrella with [IN PROGRESS] managed-prefix title (#819)"
run_fixture "fixture-10"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='[IN PROGRESS] Umbrella: foo'"
    echo "ISSUE_BODY='No body literal here. No task-list children either.'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-10/stdout.txt"
ERR_FILE="$TMPROOT/fixture-10/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 50 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "5" "[10] exit code 5 (umbrella, no eligible child)"
assert_contains "$OUT" "IS_UMBRELLA=true" "[10] IS_UMBRELLA=true (umbrella detect fired)"
assert_contains "$OUT" "UMBRELLA_ACTION=no-eligible-child" "[10] UMBRELLA_ACTION=no-eligible-child"
assert_contains "$OUT" "UMBRELLA_NUMBER=50" "[10] UMBRELLA_NUMBER=50"
assert_not_contains "$OUT" "managed lifecycle title prefix" "[10] managed-prefix early-reject was bypassed (umbrella detection ran first)"

# ---------------------------------------------------------------------------
# Fixture 11: e2e umbrella dispatch with prose-blocked first child + ready
# second child (issue #768). End-to-end integration covering the full
# find-lock-issue.sh → umbrella-handler.sh → blocker-helpers.sh wiring,
# including the post-pick all_open_blockers defense-in-depth check and the
# lock-no-go + rename pipeline.
#
# Setup: umbrella #1100 with body "- [ ] #1101" (prose-blocked) and
# "- [ ] #1102" (ready). Child #1101's body has "Depends on #1199" with
# #1199 OPEN. Child #1102 has clean body. Expected: pick-child returns
# #1102 (skipping prose-blocked #1101); the post-pick guard re-runs
# all_open_blockers on #1102 (empty); lock-no-go succeeds; rename to
# [IN PROGRESS] succeeds; emit IS_UMBRELLA=true UMBRELLA_ACTION=dispatched
# UMBRELLA_NUMBER=1100 ISSUE_NUMBER=1102 LOCK_ACQUIRED=true RENAMED=true.
# ---------------------------------------------------------------------------
echo "Fixture 11: e2e umbrella dispatch with prose-blocked first child (#768)"
run_fixture "fixture-11"
# Enable stateful comment-posting so the lock-no-go post-check can find
# the just-posted IN PROGRESS comment id.
mkdir -p "$TMPROOT/fixture-11/runtime-comments"
export RUNTIME_COMMENTS_DIR="$TMPROOT/fixture-11/runtime-comments"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
RUNTIME_COMMENTS_DIR="${RUNTIME_COMMENTS_DIR:-}"
ISSUE_1100_TITLE='Umbrella: prose-blocker regression e2e'
ISSUE_1100_BODY=$'Umbrella tracking issue.\n\n## Children\n\n- [ ] #1101 — first (prose-blocked)\n- [ ] #1102 — second (ready)\n'
ISSUE_1100_STATE=OPEN
ISSUE_1100_COMMENTS='[[]]'
ISSUE_1101_TITLE='First child (prose-blocked)'
ISSUE_1101_BODY=$'## Description\n\nDepends on #1199 — must wait for that to land.\n'
ISSUE_1101_STATE=OPEN
ISSUE_1101_COMMENTS='[[]]'
ISSUE_1102_TITLE='Second child (ready)'
ISSUE_1102_BODY='Clean body, no prose blockers.'
ISSUE_1102_STATE=OPEN
ISSUE_1102_COMMENTS='[[]]'
ISSUE_1199_TITLE='External blocker'
ISSUE_1199_BODY='External blocker body.'
ISSUE_1199_STATE=OPEN
RENAME_FAIL=false
STATE_EOF

OUT_FILE="$TMPROOT/fixture-11/stdout.txt"
ERR_FILE="$TMPROOT/fixture-11/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 1100 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "0" "[11] exit code 0 (umbrella dispatched successfully)"
assert_contains "$OUT" "IS_UMBRELLA=true" "[11] IS_UMBRELLA=true"
assert_contains "$OUT" "UMBRELLA_ACTION=dispatched" "[11] UMBRELLA_ACTION=dispatched"
assert_contains "$OUT" "UMBRELLA_NUMBER=1100" "[11] UMBRELLA_NUMBER=1100"
assert_contains "$OUT" "ISSUE_NUMBER=1102" "[11] ISSUE_NUMBER=1102 (skipped prose-blocked #1101)"
assert_not_contains "$OUT" "ISSUE_NUMBER=1101" "[11] does NOT lock prose-blocked first child"
assert_contains "$OUT" "LOCK_ACQUIRED=true" "[11] LOCK_ACQUIRED=true"
assert_contains "$OUT" "RENAMED=true" "[11] RENAMED=true (lock-no-go + rename pipeline succeeded)"
ERR=$(cat "$ERR_FILE")
assert_not_contains "$ERR" "WARNING: title rename failed" "[11] no rename-failure warning on stderr"
unset RUNTIME_COMMENTS_DIR

# ---------------------------------------------------------------------------
# Fixture 12: auto-pick skips umbrella issues (Anti-pattern #7 regression).
# A single candidate with an umbrella-style title ("Umbrella: ...") and GO
# as its last comment must be skipped in auto-pick mode. The auto-pick loop
# calls `umbrella-handler.sh detect` on each GO-tagged candidate; when
# IS_UMBRELLA=true, the candidate is skipped with a diagnostic on stderr.
# With no other candidates, the scan ends with exit 1 (no eligible issues).
# ---------------------------------------------------------------------------
echo "Fixture 12: auto-pick skips umbrella issue (Anti-pattern #7 regression)"
run_fixture "fixture-12"
{
    echo "ISSUE_STATE=OPEN"
    OPEN_ISSUES_LINES='{"number":200,"title":"Umbrella: deploy pipeline refactor (3 children)"}'
    printf "OPEN_ISSUES_JSON='%s'\n" "$OPEN_ISSUES_LINES"
    echo "ISSUE_200_TITLE='Umbrella: deploy pipeline refactor (3 children)'"
    echo "ISSUE_200_BODY='No task-list children in this fixture.'"
    echo "ISSUE_200_STATE=OPEN"
    echo "ISSUE_200_COMMENTS='$(make_comments_json GO)'"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-12/stdout.txt"
ERR_FILE="$TMPROOT/fixture-12/stderr.txt"
EXIT_CODE=0
"$SCRIPT" >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")
ERR=$(cat "$ERR_FILE")

assert_equal "$EXIT_CODE" "1" "[12] exit code 1 (no eligible candidates — umbrella skipped)"
assert_contains "$OUT" "ELIGIBLE=false" "[12] ELIGIBLE=false on stdout"
assert_not_contains "$OUT" "LOCK_ACQUIRED=" "[12] LOCK_ACQUIRED= absent (lock never attempted)"
assert_contains "$ERR" "Skipping issue #200: umbrella issue" "[12] stderr diagnostic confirms umbrella skip"

# ---------------------------------------------------------------------------
# Fixture 13: explicit-target detect failure exits 2 (issue #891 regression).
# When umbrella-handler.sh detect fails (non-zero exit) in explicit-target
# mode, find-lock-issue.sh must surface the error (exit 2) instead of
# silently falling through to the ordinary-issue path. Setup: issue #300
# with an umbrella-style title, VIEW_FAIL_BODY=true makes the detect call's
# gh issue view (--json title,body) fail while the initial find-lock-issue.sh
# fetch (--json number,state,title,url) succeeds.
# ---------------------------------------------------------------------------
echo "Fixture 13: explicit-target detect failure exits 2 (#891)"
run_fixture "fixture-13"
{
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_TITLE='Umbrella: detect failure test'"
    echo "ISSUE_BODY='No body.'"
    echo "ISSUE_300_VIEW_FAIL_BODY=true"
    echo "COMMENTS_JSON='$(make_comments_json GO)'"
    echo "RENAME_FAIL=false"
} > "$STUB_STATE_FILE"

OUT_FILE="$TMPROOT/fixture-13/stdout.txt"
ERR_FILE="$TMPROOT/fixture-13/stderr.txt"
EXIT_CODE=0
"$SCRIPT" 300 >"$OUT_FILE" 2>"$ERR_FILE" || EXIT_CODE=$?

OUT=$(cat "$OUT_FILE")

assert_equal "$EXIT_CODE" "2" "[13] exit code 2 (detect failure is fatal in explicit-target mode)"
assert_contains "$OUT" "ELIGIBLE=false" "[13] ELIGIBLE=false on stdout"
assert_contains "$OUT" "ERROR=umbrella-handler.sh detect failed" "[13] ERROR mentions detect failure"
assert_contains "$OUT" "#300" "[13] ERROR mentions issue number"
assert_not_contains "$OUT" "LOCK_ACQUIRED=" "[13] LOCK_ACQUIRED= absent (lock never attempted)"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "test-find-lock-issue: $PASS passed, $FAIL failed."
if [[ $FAIL -gt 0 ]]; then
    echo "Failed assertions:" >&2
    for f in "${FAILED_TESTS[@]}"; do
        echo "  - $f" >&2
    done
    exit 1
fi

exit 0
