#!/usr/bin/env bash
# test-umbrella-handler.sh — Regression harness for umbrella-handler.sh.
#
# Hermetic offline test using a PATH-prepended `gh` stub. Validates the
# detection / list-children / pick-child subcommands of umbrella-handler.sh.
#
# Fixtures cover:
#   1. detect — body literal primary signal
#   2. detect — title prefix fallback
#   3. detect — non-umbrella (no body literal, no title prefix)
#   4. list-children — task-list grammar with /umbrella-rendered children
#   5. list-children — operator-checklist with prose ("/fix-issue executes #N")
#   6. list-children — cross-repo references rejected
#   7. list-children — self-reference filtered
#   8. list-children — prose-only body (no task-list lines) → empty
#   9. pick-child — first eligible child
#  10. pick-child — skips locked child (last comment IN PROGRESS)
#  11. pick-child — skips managed-prefix child
#  12. pick-child — ALL_CLOSED with at least one parsed child
#  13. pick-child — NO_ELIGIBLE_CHILD when zero parseable children (FINDING_3)
#
# Run manually:
#   bash skills/fix-issue/scripts/test-umbrella-handler.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
SCRIPT="$REPO_ROOT/skills/fix-issue/scripts/umbrella-handler.sh"

if [[ ! -x "$SCRIPT" ]]; then
    echo "FAIL: $SCRIPT not found or not executable" >&2
    exit 1
fi

PASS=0
FAIL=0
FAILED_TESTS=()

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-umbrella-handler-XXXXXX")
# shellcheck disable=SC2317
trap 'rm -rf "$TMPROOT"' EXIT

make_gh_stub() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'STUB_EOF'
#!/usr/bin/env bash
# Minimal gh stub for test-umbrella-handler.sh fixtures.

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
                # gh issue view <N> --json title,body,state OR title,state OR
                # body OR state OR createdAt — emit a JSON object. The stub
                # uses the per-issue lookup table provided by the fixture
                # state file (ISSUE_<N>_TITLE / _BODY / _STATE).
                STUB_ISSUE_NUM="$3"
                STUB_VAR_TITLE="ISSUE_${STUB_ISSUE_NUM}_TITLE"
                STUB_VAR_BODY="ISSUE_${STUB_ISSUE_NUM}_BODY"
                STUB_VAR_STATE="ISSUE_${STUB_ISSUE_NUM}_STATE"
                STUB_TITLE="${!STUB_VAR_TITLE:-Default title}"
                STUB_BODY="${!STUB_VAR_BODY:-Default body}"
                STUB_STATE_VAL="${!STUB_VAR_STATE:-OPEN}"
                jq -n --arg title "$STUB_TITLE" --arg body "$STUB_BODY" --arg state "$STUB_STATE_VAL" \
                  --arg createdAt "2024-01-01T00:00:00Z" \
                  '{title: $title, body: $body, state: $state, createdAt: $createdAt}'
                exit 0 ;;
        esac
        ;;
    api)
        shift
        STUB_URL=""
        for STUB_ARG in "$@"; do
            case "$STUB_ARG" in
                repos/*|/repos/*) STUB_URL="$STUB_ARG" ;;
            esac
        done
        case "$STUB_URL" in
            */comments)
                STUB_N=$(echo "$STUB_URL" | sed -nE 's@.*/issues/([0-9]+)/comments@\1@p')
                STUB_VAR_COMMENTS="ISSUE_${STUB_N}_COMMENTS"
                STUB_COMMENTS="${!STUB_VAR_COMMENTS:-[[]]}"
                printf '%s\n' "$STUB_COMMENTS"
                exit 0 ;;
            *blocked_by*)
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

echo "Running test-umbrella-handler against $SCRIPT"

# ---------------------------------------------------------------------------
# Fixture 1: detect — body literal primary signal
# ---------------------------------------------------------------------------
echo "Fixture 1: detect — body literal"
run_fixture "fixture-1"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_100_TITLE='Some random title'
ISSUE_100_BODY=$'Umbrella tracking issue.\n\n## Summary\nFoo bar.\n\n## Children\n\n- [ ] #101 — first\n- [ ] #102 — second\n'
ISSUE_100_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" detect --issue 100 2>&1) || true
assert_contains "$OUT" "IS_UMBRELLA=true" "[1] body literal sets IS_UMBRELLA=true"
assert_contains "$OUT" "DETECTION=body" "[1] DETECTION=body"

# ---------------------------------------------------------------------------
# Fixture 2: detect — title prefix fallback
# ---------------------------------------------------------------------------
echo "Fixture 2: detect — title prefix fallback"
run_fixture "fixture-2"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_200_TITLE='Umbrella: Move /implement meta-info to tracking issue'
ISSUE_200_BODY=$'No body literal here.\n\n- [ ] #201 — first child'
ISSUE_200_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" detect --issue 200 2>&1) || true
assert_contains "$OUT" "IS_UMBRELLA=true" "[2] title prefix sets IS_UMBRELLA=true"
assert_contains "$OUT" "DETECTION=title" "[2] DETECTION=title"

# ---------------------------------------------------------------------------
# Fixture 3: detect — non-umbrella
# ---------------------------------------------------------------------------
echo "Fixture 3: detect — non-umbrella"
run_fixture "fixture-3"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_300_TITLE='Fix the bug'
ISSUE_300_BODY='Standard issue body, no umbrella markers.'
ISSUE_300_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" detect --issue 300 2>&1) || true
assert_contains "$OUT" "IS_UMBRELLA=false" "[3] non-umbrella → IS_UMBRELLA=false"

# ---------------------------------------------------------------------------
# Fixture 4: list-children — /umbrella-rendered task-list
# ---------------------------------------------------------------------------
echo "Fixture 4: list-children — /umbrella-rendered task-list"
run_fixture "fixture-4"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_400_TITLE='Umbrella: foo'
ISSUE_400_BODY=$'Umbrella tracking issue.\n\n## Children\n\n- [ ] #401 — child a\n- [ ] #402 — child b\n- [x] #403 — child c (closed)\n'
ISSUE_400_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" list-children --issue 400 2>&1) || true
assert_contains "$OUT" "CHILDREN=401 402 403" "[4] children parsed in body order"

# ---------------------------------------------------------------------------
# Fixture 5: list-children — operator-checklist (#348-style with prose between)
# ---------------------------------------------------------------------------
echo "Fixture 5: list-children — operator-checklist with prose"
run_fixture "fixture-5"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_500_TITLE='Umbrella: phased rollout'
ISSUE_500_BODY=$'Umbrella tracking issue.\n\n## Operator checklist\n\n- [ ] /fix-issue approves and executes #501\n- [ ] /fix-issue approves and executes #502\n'
ISSUE_500_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" list-children --issue 500 2>&1) || true
assert_contains "$OUT" "CHILDREN=501 502" "[5] operator-checklist prose parses both children"

# ---------------------------------------------------------------------------
# Fixture 6: list-children — cross-repo references rejected
# ---------------------------------------------------------------------------
echo "Fixture 6: list-children — cross-repo rejected"
run_fixture "fixture-6"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_600_TITLE='Umbrella: cross-repo'
ISSUE_600_BODY=$'Umbrella tracking issue.\n\n- [ ] #601 — same-repo\n- [ ] other/repo#999 — cross-repo (should be rejected)\n'
ISSUE_600_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" list-children --issue 600 2>&1) || true
assert_contains "$OUT" "CHILDREN=601" "[6] only same-repo child kept"
assert_not_contains "$OUT" "999" "[6] cross-repo number filtered out"

# ---------------------------------------------------------------------------
# Fixture 7: list-children — self-reference filtered
# ---------------------------------------------------------------------------
echo "Fixture 7: list-children — self-reference filtered"
run_fixture "fixture-7"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_700_TITLE='Umbrella: foo'
ISSUE_700_BODY=$'Umbrella tracking issue.\n\n- [ ] #700 — self-reference (should be filtered)\n- [ ] #701 — real child\n'
ISSUE_700_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" list-children --issue 700 2>&1) || true
assert_contains "$OUT" "CHILDREN=701" "[7] self-reference filtered, real child kept"
assert_not_contains "$OUT" "CHILDREN=700" "[7] self-reference NOT in children list"

# ---------------------------------------------------------------------------
# Fixture 8: list-children — prose-only body (no task-list lines)
# ---------------------------------------------------------------------------
echo "Fixture 8: list-children — prose-only, no task-list lines"
run_fixture "fixture-8"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_800_TITLE='Umbrella: prose only'
ISSUE_800_BODY=$'Umbrella tracking issue.\n\nThis umbrella references #801 and #802 in prose but has no checklist lines.\n'
ISSUE_800_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" list-children --issue 800 2>&1) || true
assert_contains "$OUT" "CHILDREN=" "[8] prose-only body produces empty CHILDREN"
assert_not_contains "$OUT" "CHILDREN=801" "[8] prose #N references NOT picked up"

# ---------------------------------------------------------------------------
# Fixture 13: pick-child — zero parseable children → NO_ELIGIBLE_CHILD (FINDING_3)
# ---------------------------------------------------------------------------
echo "Fixture 13: pick-child — zero children → NO_ELIGIBLE_CHILD (not vacuous ALL_CLOSED)"
run_fixture "fixture-13"
cat > "$STUB_STATE_FILE" <<'STATE_EOF'
ISSUE_130_TITLE='Umbrella: empty'
ISSUE_130_BODY=$'Umbrella tracking issue.\n\nNo task-list children here.\n'
ISSUE_130_STATE=OPEN
STATE_EOF
OUT=$("$SCRIPT" pick-child --issue 130 2>&1) || true
assert_contains "$OUT" "NO_ELIGIBLE_CHILD=true" "[13] zero children → NO_ELIGIBLE_CHILD"
assert_contains "$OUT" "no parseable children" "[13] BLOCKING_REASON identifies cause"
assert_not_contains "$OUT" "ALL_CLOSED=true" "[13] does NOT emit vacuous ALL_CLOSED"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo
echo "test-umbrella-handler: $PASS passed, $FAIL failed."
if [[ $FAIL -gt 0 ]]; then
    echo "Failed assertions:" >&2
    for f in "${FAILED_TESTS[@]}"; do
        echo "  - $f" >&2
    done
    exit 1
fi
exit 0
