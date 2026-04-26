#!/usr/bin/env bash
# test-finalize-umbrella.sh — Regression harness for finalize-umbrella.sh.
#
# Hermetic offline test using a PATH-prepended `gh` stub. Validates the
# `finalize` subcommand's idempotency guard (FINDING_2) and the rename →
# close composition.
#
# Fixtures cover:
#   1. finalize-success — open umbrella, no marker comment → executes rename
#      + close, emits FINALIZED=true RENAMED=true CLOSED=true.
#   2. idempotent-when-marker-comment-exists (FINDING_2) — comment stream
#      contains the literal marker, even though state=OPEN and title has no
#      [DONE] prefix → emits FINALIZED=false ALREADY_FINALIZED=true REASON=
#      existing closing-comment marker detected.
#   3. idempotent-when-already-DONE-prefix — title starts with "[DONE] " →
#      same idempotent emission.
#   4. idempotent-when-already-CLOSED — state=CLOSED → same idempotent
#      emission (regardless of title or comments).
#   5. rename-failed-but-close-success — best-effort rename invariant: rename
#      delegate fails, but close succeeds. FINALIZED=true RENAMED=false
#      CLOSED=true; stderr WARNING surfaces the rename failure.
#
# Run manually:
#   bash skills/fix-issue/scripts/test-finalize-umbrella.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$REPO_ROOT/skills/fix-issue/scripts/finalize-umbrella.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL: $SCRIPT not found or not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-finalize-umbrella-XXXXXX")
# shellcheck disable=SC2317
trap 'rm -rf "$TMPROOT"' EXIT

make_gh_stub() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Minimal gh stub for test-finalize-umbrella.sh fixtures.

if [[ -n "${STUB_LOG:-}" ]]; then
    printf 'gh|%s\n' "$*" >> "$STUB_LOG"
fi

if [[ -n "${STUB_STATE_FILE:-}" && -f "${STUB_STATE_FILE}" ]]; then
    # shellcheck disable=SC1090
    source "$STUB_STATE_FILE"
fi

case "$1" in
    repo)
        case "$2" in
            view) echo "stub/repo"; exit 0 ;;
        esac
        ;;
    issue)
        case "$2" in
            view)
                STUB_TITLE="${ISSUE_TITLE:-Umbrella: foo}"
                STUB_STATE_VAL="${ISSUE_STATE:-OPEN}"
                STUB_BODY="${ISSUE_BODY:-Umbrella tracking issue.}"
                jq -n --arg title "$STUB_TITLE" --arg state "$STUB_STATE_VAL" \
                  --arg body "$STUB_BODY" --arg createdAt "2024-01-01T00:00:00Z" \
                  '{title: $title, state: $state, body: $body, createdAt: $createdAt}'
                exit 0 ;;
            close)
                if [[ "${CLOSE_FAIL:-false}" == "true" ]]; then
                    exit 1
                fi
                exit 0 ;;
            comment)
                if [[ "${COMMENT_FAIL:-false}" == "true" ]]; then
                    exit 1
                fi
                exit 0 ;;
            edit)
                if [[ "${RENAME_FAIL:-false}" == "true" ]]; then
                    echo "Error: failed to edit title" >&2
                    exit 1
                fi
                exit 0 ;;
        esac
        ;;
    api)
        shift
        STUB_URL=""
        STUB_METHOD="GET"
        for STUB_ARG in "$@"; do
            case "$STUB_ARG" in
                repos/*|/repos/*) STUB_URL="$STUB_ARG" ;;
            esac
        done
        # extract -X method
        STUB_PA=( "$@" )
        STUB_I=0
        while [[ $STUB_I -lt ${#STUB_PA[@]} ]]; do
            if [[ "${STUB_PA[$STUB_I]}" == "-X" ]]; then
                STUB_J=$((STUB_I + 1))
                STUB_METHOD="${STUB_PA[$STUB_J]}"
                break
            fi
            STUB_I=$((STUB_I + 1))
        done
        case "$STUB_URL" in
            */comments)
                if [[ "$STUB_METHOD" == "DELETE" ]]; then
                    exit 0
                fi
                printf '%s\n' "${ISSUE_COMMENTS:-[[]]}"
                exit 0 ;;
            *)
                exit 0 ;;
        esac
        ;;
esac
echo "STUB ERROR: unhandled gh invocation: $*" >&2
exit 99
STUB_EOF
    chmod +x "$stub_dir/gh"
}

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

echo "Running test-finalize-umbrella against $SCRIPT"

# Fixture 1: success path
echo "Fixture 1: finalize-success"
run_fixture "fixture-1"
{
    echo "ISSUE_TITLE='Umbrella: foo'"
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_BODY='Umbrella tracking issue.'"
    echo "ISSUE_COMMENTS='[[]]'"
} > "$STUB_STATE_FILE"
OUT=$("$SCRIPT" finalize --issue 100 2>&1) || true
assert_contains "$OUT" "FINALIZED=true" "[1] FINALIZED=true on success"
assert_contains "$OUT" "RENAMED=true" "[1] RENAMED=true"
assert_contains "$OUT" "CLOSED=true" "[1] CLOSED=true"

# Fixture 2: marker present + state=OPEN → close-only retry (FINDING_3)
# Per the umbrella-PR code-review panel, marker presence with OPEN state
# means a prior attempt got past comment-post but its close call failed —
# we MUST retry the close (without re-emitting the comment) rather than
# short-circuit. This fixture verifies the close-only retry path.
echo "Fixture 2: marker-present + OPEN → close-only retry (no double-comment)"
run_fixture "fixture-2"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_TITLE='Umbrella: foo'
ISSUE_STATE=OPEN
ISSUE_BODY='Umbrella tracking issue.'
ISSUE_COMMENTS='[[{"id":1,"body":"<!-- larch:fix-issue:umbrella-finalized -->\nAll tracked issues are closed. Marking umbrella as DONE and closing.","created_at":"2024-01-01T00:00:00Z"}]]'
STATE_EOF
OUT=$("$SCRIPT" finalize --issue 100 2>&1) || true
assert_contains "$OUT" "FINALIZED=true" "[2] FINALIZED=true (close-only retry succeeded)"
assert_contains "$OUT" "CLOSED=true" "[2] CLOSED=true (the close path WAS retried)"
assert_not_contains "$OUT" "ALREADY_FINALIZED=true" "[2] does NOT short-circuit when state=OPEN even with marker present"

# Fixture 3: [DONE] title + state=OPEN → close-only retry, skip rename (FINDING_3)
# Mirrors fixture 2's invariant for the title-prefix signal: prior rename
# succeeded (title is [DONE]) but close failed — retry close without
# re-renaming.
echo "Fixture 3: [DONE]-title + OPEN → close-only retry (skip rename)"
run_fixture "fixture-3"
{
    echo "ISSUE_TITLE='[DONE] Umbrella: foo'"
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_BODY='Umbrella tracking issue.'"
    echo "ISSUE_COMMENTS='[[]]'"
} > "$STUB_STATE_FILE"
OUT=$("$SCRIPT" finalize --issue 100 2>&1) || true
assert_contains "$OUT" "FINALIZED=true" "[3] FINALIZED=true (close path ran)"
assert_contains "$OUT" "RENAMED=false" "[3] RENAMED=false (rename skipped, title already [DONE])"
assert_contains "$OUT" "CLOSED=true" "[3] CLOSED=true (close path WAS retried)"
assert_not_contains "$OUT" "ALREADY_FINALIZED=true" "[3] does NOT short-circuit when state=OPEN even with [DONE] title"

# Fixture 4: idempotent on already CLOSED state
echo "Fixture 4: idempotent-when-already-CLOSED"
run_fixture "fixture-4"
{
    echo "ISSUE_TITLE='Umbrella: foo'"
    echo "ISSUE_STATE=CLOSED"
    echo "ISSUE_BODY='Umbrella tracking issue.'"
} > "$STUB_STATE_FILE"
OUT=$("$SCRIPT" finalize --issue 100 2>&1) || true
assert_contains "$OUT" "ALREADY_FINALIZED=true" "[4] ALREADY_FINALIZED=true"
assert_contains "$OUT" "already CLOSED" "[4] REASON identifies CLOSED state"

# Fixture 5: rename failed best-effort
echo "Fixture 5: rename-failed-but-close-success"
run_fixture "fixture-5"
{
    echo "ISSUE_TITLE='Umbrella: foo'"
    echo "ISSUE_STATE=OPEN"
    echo "ISSUE_BODY='Umbrella tracking issue.'"
    echo "ISSUE_COMMENTS='[[]]'"
    echo "RENAME_FAIL=true"
} > "$STUB_STATE_FILE"
OUT=$("$SCRIPT" finalize --issue 100 2>&1) || true
assert_contains "$OUT" "FINALIZED=true" "[5] FINALIZED=true (close succeeded)"
assert_contains "$OUT" "RENAMED=false" "[5] RENAMED=false (best-effort fail)"
assert_contains "$OUT" "CLOSED=true" "[5] CLOSED=true"

# Summary
echo
echo "test-finalize-umbrella: $PASS passed, $FAIL failed."
if [[ $FAIL -gt 0 ]]; then
    echo "Failed assertions:" >&2
    for f in "${FAILED_TESTS[@]}"; do
        echo "  - $f" >&2
    done
    exit 1
fi
exit 0
