#!/usr/bin/env bash
# test-helpers.sh — regression harness for /umbrella's helpers.sh subcommands.
# Currently covers `check-cycle` (pure logic, no network).
# Run manually: bash .claude/skills/umbrella/scripts/test-helpers.sh
# Wire into make lint via a `test-umbrella-helpers` target alongside existing test-* harnesses.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
HELPERS="$HERE/helpers.sh"
TMP=$(mktemp -d -t test-umbrella-helpers-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

assert_cycle() {
  local label="$1"
  local edges_content="$2"
  local candidate="$3"
  local expected="$4"
  local edges_file="$TMP/edges.tsv"
  printf '%s' "$edges_content" > "$edges_file"
  local out
  out=$(bash "$HELPERS" check-cycle --existing-edges "$edges_file" --candidate "$candidate" 2>&1 || true)
  local got
  got=$(printf '%s' "$out" | sed -n 's/^CYCLE=//p')
  if [ "$got" = "$expected" ]; then
    printf '  ✅ %s — CYCLE=%s\n' "$label" "$got"
    PASS=$((PASS + 1))
  else
    printf '  ❌ %s — expected CYCLE=%s, got "%s" (full output: %s)\n' "$label" "$expected" "$got" "$out"
    FAIL=$((FAIL + 1))
  fi
}

assert_error() {
  local label="$1"
  shift
  local out
  if out=$(bash "$HELPERS" "$@" 2>&1); then
    printf '  ❌ %s — expected non-zero exit, got success: %s\n' "$label" "$out"
    FAIL=$((FAIL + 1))
  else
    printf '  ✅ %s — error path triggered\n' "$label"
    PASS=$((PASS + 1))
  fi
}

echo "test-helpers.sh: check-cycle subcommand"

# Empty graph, simple candidate — never a cycle.
assert_cycle "empty graph"            ""                                "1:2" "false"
# Self-loop is always a cycle.
assert_cycle "self-loop"              ""                                "5:5" "true"
# Single edge graph, candidate creates 2-cycle.
assert_cycle "2-cycle from new edge"  $'1\t2\n'                         "2:1" "true"
# Single edge graph, candidate is independent.
assert_cycle "independent candidate"  $'1\t2\n'                         "3:4" "false"
# Linear chain 1->2->3, candidate 3->1 closes a 3-cycle.
assert_cycle "3-cycle close"          $'1\t2\n2\t3\n'                   "3:1" "true"
# Chain 1->2->3, candidate 1->3 (parallel forward edge) — still a DAG.
assert_cycle "parallel forward edge"  $'1\t2\n2\t3\n'                   "1:3" "false"
# Diamond 1->2,1->3,2->4,3->4. Candidate 4->1 closes a cycle.
assert_cycle "diamond cycle close"    $'1\t2\n1\t3\n2\t4\n3\t4\n'       "4:1" "true"
# Diamond 1->2,1->3,2->4,3->4. Candidate 2->3 — still a DAG.
assert_cycle "diamond cross-edge"     $'1\t2\n1\t3\n2\t4\n3\t4\n'       "2:3" "false"
# Disconnected graph — candidate spanning components is fine.
assert_cycle "disconnected ok"        $'1\t2\n10\t20\n'                 "1:10" "false"

# Error cases.
assert_error "missing --existing-edges" check-cycle --candidate "1:2"
assert_error "missing --candidate"      check-cycle --existing-edges "$TMP/edges.tsv"
# Provide an existing file for the next checks so we hit the candidate validation, not the file check.
: > "$TMP/edges.tsv"
assert_error "non-numeric candidate"    check-cycle --existing-edges "$TMP/edges.tsv" --candidate "a:b"
assert_error "malformed candidate"      check-cycle --existing-edges "$TMP/edges.tsv" --candidate "1-2"

echo ""
echo "test-helpers.sh: wire-dag subcommand (PATH-stub gh, no network)"

# Set up an isolated $PATH-prepended stub directory and a gh stub script that
# dispatches on argv pattern. Each test sets STUB_POST_RESPONSE, STUB_POST_RC,
# and STUB_BLOCKER_ID via env vars and invokes wire-dag against a tiny fixture.
STUB_BIN="$TMP/bin"
mkdir -p "$STUB_BIN"
GH_STUB="$STUB_BIN/gh"

cat > "$GH_STUB" <<'STUB'
#!/usr/bin/env bash
# PATH-stub gh — dispatches on argv pattern, returns canned responses for
# wire-dag tests. Behavior is controlled by env vars set by the test harness:
#   STUB_PROBE_RC               — exit code for the umbrella probe (default: 0)
#   STUB_BLOCKER_ID             — value to print for blocker-id lookup
#   STUB_BLOCKER_ID_RC          — exit code for blocker-id lookup (default: 0)
#   STUB_POST_RESPONSE          — full -i blob to print on stdout for the POST
#   STUB_POST_RC                — exit code for the POST (default: 0)
#   STUB_EXISTING_BLOCKERS      — legacy global default for blocked_by lookups
#                                 (used when STUB_BLOCKED_BY_<N> is unset)
#   STUB_BLOCKED_BY_<N>         — per-node response for the blocked_by lookup of
#                                 issue number N (issue #718). Empty string is
#                                 a distinct response from "unset"; unset falls
#                                 through to STUB_EXISTING_BLOCKERS.
#   STUB_BLOCKED_BY_<N>_RC      — per-node exit code for the blocked_by lookup
#                                 (default: 0). Non-zero simulates a transient
#                                 gh failure for that node.
#   STUB_LIST_COMMENTS_RESPONSE — newline-separated comment bodies returned by
#                                 the back-link comment-existence probe (issue
#                                 #716). Default empty string → no existing
#                                 back-link comment, post is expected.
#   STUB_LIST_COMMENTS_RC       — exit code for the comment-list probe (default
#                                 0). Non-zero simulates a transient gh
#                                 failure; helpers.sh fails open and posts.
set -e
# Resolve the request URL by scanning args (handles `gh api -i URL` from the
# new probe (issue #728) where the URL is at $3, AND the legacy
# `gh api URL ...` shape where the URL is at $2).
_stub_url=""
for arg in "$@"; do
  case "$arg" in
    /repos/*/issues/*) _stub_url="$arg" ;;
  esac
done
case "$1 $_stub_url" in
  "api /repos/"*"/issues/"*"/comments")
    # Back-link comment-existence probe (issue #716). Placed BEFORE the
    # generic /issues/<N> arm so the case-statement first-match order does
    # not shadow this dispatch with the blocker-id-lookup arm.
    printf '%s' "${STUB_LIST_COMMENTS_RESPONSE:-}"
    exit "${STUB_LIST_COMMENTS_RC:-0}"
    ;;
  "api /repos/"*"/issues/"*"/dependencies/blocked_by")
    # Could be: probe (--silent or -i), existing-edges (--jq), native check (--jq with select),
    # or per-edge POST (-X POST -i).
    has_post=0
    has_dash_i=0
    has_jq=0
    for arg in "$@"; do
      [ "$arg" = "POST" ] && has_post=1
      [ "$arg" = "-i" ] && has_dash_i=1
      [ "$arg" = "--jq" ] && has_jq=1
    done
    if [ "$has_post" = "1" ] && [ "$has_dash_i" = "1" ]; then
      printf '%s' "${STUB_POST_RESPONSE:-}"
      exit "${STUB_POST_RC:-0}"
    elif [ "$has_jq" = "1" ]; then
      # Distinguish existing-edges lookup from native-check by argv flavor.
      for arg in "$@"; do
        if [ "$arg" = ".[].number" ]; then
          # Per-node dispatch (issue #718): extract issue number from the URL
          # path and look up STUB_BLOCKED_BY_<N>. Falls through to legacy
          # STUB_EXISTING_BLOCKERS when the per-node var is unset.
          node="${2#*/issues/}"
          node="${node%/dependencies/blocked_by}"
          rc_var="STUB_BLOCKED_BY_${node}_RC"
          if declare -p "$rc_var" >/dev/null 2>&1; then
            eval "rc=\${$rc_var}"
            [ "$rc" -ne 0 ] && exit "$rc"
          fi
          var_name="STUB_BLOCKED_BY_${node}"
          if declare -p "$var_name" >/dev/null 2>&1; then
            eval "value=\${$var_name}"
            # Convert space-separated multi-blocker lists to newline-separated
            # so production --jq '.[].number' output shape matches.
            printf '%s' "$value" | tr ' ' '\n'
          else
            printf '%s' "${STUB_EXISTING_BLOCKERS:-}"
          fi
          exit 0
        fi
      done
      # The legacy "native check" arm (jq with select) is dead since #716 —
      # helpers.sh wire-dag's back-link loop no longer calls
      # /dependencies/blocked_by --jq ".[] | select(.number == ${UMBRELLA})".
      # Kept as an explicit "unreachable" branch returning empty so any
      # accidental future reintroduction of the call is easy to diagnose
      # (the assertion surface is empty rather than wedged-on-old-state).
      printf ''
      exit 0
    else
      # Probe path (no POST, no --jq). After issue #728 the production probe
      # uses `gh api -i` (status-aware classifier with retry). Behavior:
      #   - If PROBE_CALL_COUNT_FILE is set, increment it and use per-attempt
      #     STUB_PROBE_RESPONSE_<N> / STUB_PROBE_RC_<N>. This lets tests
      #     simulate "first 5xx, retry 200 OK" sequencing.
      #   - Else, fall back to STUB_PROBE_RESPONSE / STUB_PROBE_RC (single-shot).
      #   - Default fallback: emit a 200 OK HTTP response so probe succeeds in
      #     tests that don't explicitly configure a response (preserves the
      #     pre-#728 "STUB_PROBE_RC=0 → probe ok" backward-compat shorthand).
      attempt=1
      if [ -n "${PROBE_CALL_COUNT_FILE:-}" ]; then
        prev=0
        if [ -f "$PROBE_CALL_COUNT_FILE" ]; then
          prev=$(cat "$PROBE_CALL_COUNT_FILE")
        fi
        attempt=$((prev + 1))
        echo "$attempt" > "$PROBE_CALL_COUNT_FILE"
      fi
      resp_var="STUB_PROBE_RESPONSE_${attempt}"
      rc_var="STUB_PROBE_RC_${attempt}"
      if declare -p "$resp_var" >/dev/null 2>&1; then
        eval "probe_resp=\${$resp_var}"
        if declare -p "$rc_var" >/dev/null 2>&1; then
          eval "probe_rc=\${$rc_var}"
        else
          probe_rc=0
        fi
      elif [ -n "${STUB_PROBE_RESPONSE:-}" ]; then
        probe_resp="$STUB_PROBE_RESPONSE"
        probe_rc="${STUB_PROBE_RC:-0}"
      elif [ "${STUB_PROBE_RC:-0}" != "0" ]; then
        # Legacy backward-compat path: non-zero RC + no body. Production probe
        # interprets this as empty status_code → retry → empty → PROBE_FAILED=1.
        probe_resp=""
        probe_rc="$STUB_PROBE_RC"
      else
        # Default success — 200 OK so existing tests with STUB_PROBE_RC=0
        # continue to see api_available=true on the new status-aware probe.
        probe_resp=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n[]\n'
        probe_rc=0
      fi
      printf '%s' "$probe_resp"
      exit "$probe_rc"
    fi
    ;;
  "api /repos/"*"/issues/"*)
    # Blocker-id lookup: gh api /repos/$REPO/issues/$N --jq .id
    printf '%s' "${STUB_BLOCKER_ID:-}"
    exit "${STUB_BLOCKER_ID_RC:-0}"
    ;;
  "issue comment")
    # Back-link comment posting — always succeed silently. When STUB_COMMENT_LOG
    # is set, record one line per invocation so tests can assert call count.
    if [ -n "${STUB_COMMENT_LOG:-}" ]; then
      printf 'comment-call\n' >> "$STUB_COMMENT_LOG"
    fi
    exit 0
    ;;
  *)
    echo "stub gh: unrecognized argv: $*" >&2
    exit 99
    ;;
esac
STUB
chmod +x "$GH_STUB"

assert_wire_dag() {
  local label="$1" expect_pattern="$2" expect_stderr_lines="$3"
  local out_file="$TMP/wire-out.$$"
  local err_file="$TMP/wire-err.$$"
  local children="$TMP/children.tsv"
  local edges="$TMP/edges.tsv"
  printf '20\tsome-child\thttp://x\n' > "$children"
  printf '10\t20\n' > "$edges"
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$children" --edges-file "$edges" \
    --repo o/r > "$out_file" 2> "$err_file" || true
  if ! grep -qE "$expect_pattern" "$out_file"; then
    printf '  ❌ %s — stdout did not match /%s/\n     stdout:\n' "$label" "$expect_pattern"
    sed 's/^/       /' "$out_file"
    printf '     stderr:\n'
    sed 's/^/       /' "$err_file"
    FAIL=$((FAIL + 1))
    return
  fi
  local got_stderr_lines
  got_stderr_lines=$(grep -c '⚠ /umbrella: wire-dag edge' "$err_file" || true)
  if [ "$got_stderr_lines" != "$expect_stderr_lines" ]; then
    printf '  ❌ %s — expected %s wire-dag-edge stderr line(s), got %s\n     stderr:\n' "$label" "$expect_stderr_lines" "$got_stderr_lines"
    sed 's/^/       /' "$err_file"
    FAIL=$((FAIL + 1))
    return
  fi
  printf '  ✅ %s\n' "$label"
  PASS=$((PASS + 1))
  rm -f "$out_file" "$err_file"
}

# Default stub state: probe ok, blocker-id resolves, no existing edges, no
# existing back-link comment on any child (per #716 — comments-listing default
# returns empty, so the back-link idempotency check finds nothing and posts).
export STUB_PROBE_RC=0
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_EXISTING_BLOCKERS=""
export STUB_LIST_COMMENTS_RESPONSE=""
export STUB_LIST_COMMENTS_RC=0

# (a) 200 OK → EDGES_ADDED, no warning.
export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
export STUB_POST_RC=0
assert_wire_dag "200 OK → EDGES_ADDED" 'EDGES_ADDED=1' 0

# (b) 404 with feature-missing body → EDGES_SKIPPED_API_UNAVAILABLE, no warning.
export STUB_POST_RESPONSE=$'HTTP/2 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"The dependencies feature is not found on this repository","status":"404"}\n'
export STUB_POST_RC=22
assert_wire_dag "404 feature-missing → EDGES_SKIPPED_API_UNAVAILABLE" 'EDGES_SKIPPED_API_UNAVAILABLE=1' 0

# (c) 404 with ambiguous body (issue not found, not feature missing) → EDGES_FAILED, one warning.
export STUB_POST_RESPONSE=$'HTTP/2 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"Issue 99999 not found","status":"404"}\n'
export STUB_POST_RC=22
assert_wire_dag "404 ambiguous → EDGES_FAILED" 'EDGES_FAILED=1' 1

# (d) 429 rate-limit → EDGES_FAILED, one warning.
export STUB_POST_RESPONSE=$'HTTP/2 429 Too Many Requests\r\nRetry-After: 60\r\n\r\n{"message":"API rate limit exceeded"}\n'
export STUB_POST_RC=22
assert_wire_dag "429 rate-limit → EDGES_FAILED" 'EDGES_FAILED=1' 1

# (e) 403 permission denied → EDGES_FAILED, one warning.
export STUB_POST_RESPONSE=$'HTTP/2 403 Forbidden\r\n\r\n{"message":"Resource not accessible by integration"}\n'
export STUB_POST_RC=22
assert_wire_dag "403 forbidden → EDGES_FAILED" 'EDGES_FAILED=1' 1

# (f) 5xx server error → EDGES_FAILED, one warning.
export STUB_POST_RESPONSE=$'HTTP/2 502 Bad Gateway\r\n\r\n{"message":"Bad Gateway"}\n'
export STUB_POST_RC=22
assert_wire_dag "502 → EDGES_FAILED" 'EDGES_FAILED=1' 1

# (g) 422 already-exists → EDGES_SKIPPED_EXISTING (idempotent).
export STUB_POST_RESPONSE=$'HTTP/2 422 Unprocessable Entity\r\n\r\n{"message":"Validation failed: dependency already exists"}\n'
export STUB_POST_RC=22
assert_wire_dag "422 already-exists → EDGES_SKIPPED_EXISTING" 'EDGES_SKIPPED_EXISTING=1' 0

# (h) 422 non-idempotent (some other validation error) → EDGES_FAILED.
export STUB_POST_RESPONSE=$'HTTP/2 422 Unprocessable Entity\r\n\r\n{"message":"Validation failed: invalid request body"}\n'
export STUB_POST_RC=22
assert_wire_dag "422 non-idempotent → EDGES_FAILED" 'EDGES_FAILED=1' 1

# (i) Probe failure → existing repo-wide path (all proposed edges → EDGES_SKIPPED_API_UNAVAILABLE).
# Counter behavior is unchanged after issue #728; the new PROBE_FAILED=1 stdout
# line and the new "wire-dag probe failed" stderr warning are pinned in the
# probe-classification suite below — this assertion only checks the legacy
# counter and the absence of per-edge "wire-dag edge" stderr lines.
export STUB_PROBE_RC=22
export STUB_POST_RESPONSE=""
export STUB_POST_RC=0
assert_wire_dag "probe failure → repo-wide skip" 'EDGES_SKIPPED_API_UNAVAILABLE=1' 0
# (i.1) The same probe-failure run now also emits PROBE_FAILED=1 (issue #728).
{
  i1_children="$TMP/children-i1.tsv"
  i1_edges="$TMP/edges-i1.tsv"
  i1_out="$TMP/wire-out-i1"
  printf '20\tsome-child\thttp://x\n' > "$i1_children"
  printf '10\t20\n' > "$i1_edges"
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$i1_children" --edges-file "$i1_edges" \
    --repo o/r > "$i1_out" 2>/dev/null || true
  if grep -qE '^PROBE_FAILED=1$' "$i1_out"; then
    printf '  ✅ probe failure → PROBE_FAILED=1 (#728)\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ probe failure expected PROBE_FAILED=1 (#728)\n     stdout:\n'
    sed 's/^/       /' "$i1_out"
    FAIL=$((FAIL + 1))
  fi
}
export STUB_PROBE_RC=0

# (j) Dry-run → stdout includes EDGES_FAILED=0.
DRY_OUT=$(PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
  --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
  --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
  --repo o/r --dry-run 2>&1) || true
if printf '%s\n' "$DRY_OUT" | grep -qE '^EDGES_FAILED=0$'; then
  printf '  ✅ dry-run includes EDGES_FAILED=0\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ dry-run did not include EDGES_FAILED=0\n     stdout:\n'
  printf '%s\n' "$DRY_OUT" | sed 's/^/       /'
  FAIL=$((FAIL + 1))
fi

# (k) Stub returns non-zero on POST while still emitting -i blob (proves set +e/-e wrapper).
export STUB_POST_RESPONSE=$'HTTP/2 503 Service Unavailable\r\n\r\n{"message":"down"}\n'
export STUB_POST_RC=99
assert_wire_dag "non-zero gh exit + -i blob → classifier still routes" 'EDGES_FAILED=1' 1
export STUB_POST_RC=0

# (l) Blocker-id lookup failure → EDGES_FAILED with id-lookup tag.
export STUB_BLOCKER_ID=""
export STUB_BLOCKER_ID_RC=22
export STUB_POST_RESPONSE=""
assert_wire_dag "blocker-id lookup failure → EDGES_FAILED" 'EDGES_FAILED=1' 1
# Verify the warning carries the id-lookup tag.
LAST_ERR=$(PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
  --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
  --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
  --repo o/r 2>&1 1>/dev/null || true)
if printf '%s' "$LAST_ERR" | grep -q 'id-lookup'; then
  printf '  ✅ blocker-id lookup failure carries id-lookup tag in warning\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ blocker-id lookup failure missing id-lookup tag\n     stderr:\n'
  printf '%s\n' "$LAST_ERR" | sed 's/^/       /'
  FAIL=$((FAIL + 1))
fi
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0

echo ""
echo "test-helpers.sh: check-cycle non-child-intermediary regression (issue #718)"

# Pure check-cycle pin: a cycle that closes through a non-child intermediary
# is detectable by the awk BFS as long as the TSV captures the relevant edges.
# Existing edges 10->30 and 30->20; candidate 20->10 closes the cycle through
# the intermediate node 30. This pins the awk invariant the wire-dag fix
# relies on for the issue #718 repro.
assert_cycle "non-child intermediary cycle (#718)" $'10\t30\n30\t20\n' "20:10" "true"

echo ""
echo "test-helpers.sh: wire-dag transitive-closure regressions (issue #718)"

# Reset stub to clean state. Crucially, clear STUB_EXISTING_BLOCKERS so the
# per-node fall-through doesn't accidentally inject phantom edges from earlier
# tests' global default.
unset STUB_EXISTING_BLOCKERS
export STUB_PROBE_RC=0
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
export STUB_POST_RC=0

# (m) Non-child-intermediary cycle: candidate 21->20 (child_B blocks child_A).
#     Existing graph: 50 blocks 21 (so 21's blocked_by includes 50),
#                     20 blocks 50 (so 50's blocked_by includes 20).
#     BFS seed: {20, 21} from CHILDREN_FILE; EDGES_FILE adds {21, 20} (already in).
#     Dequeue 20: STUB_BLOCKED_BY_20="" → no rows.
#     Dequeue 21: STUB_BLOCKED_BY_21="50" → row "50\t21". Enqueue 50.
#     Dequeue 50: STUB_BLOCKED_BY_50="20" → row "20\t50". 20 already seen.
#     Final TSV: 50\t21, 20\t50.
#     check-cycle from 20 (cand_blocked) follows edges[20]=50, edges[50]=21
#     reaches 21 (cand_blocker) → CYCLE=true. Assert EDGES_REJECTED_CYCLE=1.
{
  m_children="$TMP/children-m.tsv"
  m_edges="$TMP/edges-m.tsv"
  m_out="$TMP/wire-out-m"
  m_err="$TMP/wire-err-m"
  printf '20\tchild_A\thttp://x\n21\tchild_B\thttp://x\n' > "$m_children"
  printf '21\t20\n' > "$m_edges"
  unset STUB_BLOCKED_BY_20
  unset STUB_BLOCKED_BY_21
  unset STUB_BLOCKED_BY_50
  export STUB_BLOCKED_BY_20=""
  export STUB_BLOCKED_BY_21="50"
  export STUB_BLOCKED_BY_50="20"
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$m_children" --edges-file "$m_edges" \
    --repo o/r > "$m_out" 2> "$m_err" || true
  if grep -qE 'EDGES_REJECTED_CYCLE=1' "$m_out" && grep -qE 'EDGES_ADDED=0' "$m_out"; then
    printf '  ✅ non-child intermediary cycle rejected (#718)\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ non-child intermediary cycle not rejected\n     stdout:\n'
    sed 's/^/       /' "$m_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$m_err"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_21 STUB_BLOCKED_BY_50
}

# (m2) EDGES_FILE-only seeding regression: the cycle-closing intermediary is
#      reachable ONLY via an EDGES_FILE endpoint that is NOT in CHILDREN_FILE.
#      CHILDREN_FILE contains only the blocked endpoint (20); the proposed-edge
#      blocker (21) appears only in EDGES_FILE and seeds the BFS via the
#      EDGES_FILE-specific seeding loop at helpers.sh:290-299. STUB_BLOCKED_BY
#      maps reproduce the same cycle as test (m): 21 blocked-by 50, 50
#      blocked-by 20. Without the EDGES_FILE seeding, the BFS would never
#      enqueue 21 and would miss the cycle. Pins the EDGES_FILE seeding branch
#      specifically (FINDING_6 from the design-phase #718 review).
{
  m2_children="$TMP/children-m2.tsv"
  m2_edges="$TMP/edges-m2.tsv"
  m2_out="$TMP/wire-out-m2"
  m2_err="$TMP/wire-err-m2"
  printf '20\tonly_child\thttp://x\n' > "$m2_children"
  printf '21\t20\n' > "$m2_edges"
  unset STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_21 STUB_BLOCKED_BY_50
  export STUB_BLOCKED_BY_20=""
  export STUB_BLOCKED_BY_21="50"
  export STUB_BLOCKED_BY_50="20"
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$m2_children" --edges-file "$m2_edges" \
    --repo o/r > "$m2_out" 2> "$m2_err" || true
  if grep -qE 'EDGES_REJECTED_CYCLE=1' "$m2_out" && grep -qE 'EDGES_ADDED=0' "$m2_out"; then
    printf '  ✅ EDGES_FILE-only seeding closes cycle (#718 FINDING_6)\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ EDGES_FILE-only seeding did not close cycle\n     stdout:\n'
    sed 's/^/       /' "$m2_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$m2_err"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_21 STUB_BLOCKED_BY_50
}

# (n) Bound exhaustion: tiny cap forces _wd_traversal_truncated=1, then the
#     per-edge cycle-check loop routes the candidate to EDGES_FAILED with
#     reason "bound-exhausted" (DECISION_1, voted 3-0).
{
  n_children="$TMP/children-n.tsv"
  n_edges="$TMP/edges-n.tsv"
  n_out="$TMP/wire-out-n"
  n_err="$TMP/wire-err-n"
  printf '20\tsome-child\thttp://x\n' > "$n_children"
  printf '10\t20\n' > "$n_edges"
  unset STUB_BLOCKED_BY_10 STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_100
  # Cap=2 with seeds {10, 20}: after dequeuing 20 and discovering blocker 100,
  # distinct_count=3 > cap=2 → truncate.
  export WIRE_DAG_TRAVERSAL_NODE_CAP=2
  export STUB_BLOCKED_BY_20="100"
  export STUB_BLOCKED_BY_10=""
  export STUB_BLOCKED_BY_100="200"
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$n_children" --edges-file "$n_edges" \
    --repo o/r > "$n_out" 2> "$n_err" || true
  ok=1
  grep -qE 'EDGES_FAILED=1' "$n_out" || ok=0
  grep -q 'wire-dag traversal cap reached' "$n_err" || ok=0
  grep -q 'wire-dag edge 10->20 failed (HTTP bound-exhausted)' "$n_err" || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ bound exhaustion → EDGES_FAILED with bound-exhausted reason\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ bound exhaustion did not fail closed correctly\n     stdout:\n'
    sed 's/^/       /' "$n_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$n_err"
    FAIL=$((FAIL + 1))
  fi
  unset WIRE_DAG_TRAVERSAL_NODE_CAP STUB_BLOCKED_BY_10 STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_100
}

# (o) Transient gh failure on a single node's blocked_by lookup: cached as
#     _GH_FAIL_, one-time stderr warning emitted, treated as "no edges" for
#     the rest of the run. EDGES_FAILED does NOT increment for the lookup
#     failure (residual fail-open per FINDING_5 EXONERATE — preserves the
#     existing individual-API-blip fail-open posture).
{
  o_children="$TMP/children-o.tsv"
  o_edges="$TMP/edges-o.tsv"
  o_out="$TMP/wire-out-o"
  o_err="$TMP/wire-err-o"
  printf '20\tsome-child\thttp://x\n' > "$o_children"
  printf '10\t20\n' > "$o_edges"
  unset STUB_BLOCKED_BY_10 STUB_BLOCKED_BY_20
  export STUB_BLOCKED_BY_20_RC=22
  export STUB_BLOCKED_BY_10=""
  export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
  export STUB_POST_RC=0
  PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$o_children" --edges-file "$o_edges" \
    --repo o/r > "$o_out" 2> "$o_err" || true
  ok=1
  grep -qE 'EDGES_ADDED=1' "$o_out" || ok=0
  grep -qE 'EDGES_FAILED=0' "$o_out" || ok=0
  grep -q 'wire-dag blocked_by lookup failed for #20' "$o_err" || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ transient blocked_by lookup failure → fail-open with one-time warning\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ transient lookup failure did not behave as expected\n     stdout:\n'
    sed 's/^/       /' "$o_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$o_err"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_BLOCKED_BY_20_RC STUB_BLOCKED_BY_10
}

echo ""
echo "test-helpers.sh: wire-dag back-link comment-existence idempotency (issue #716)"

# Reset stub for the back-link suite. Children: just #20. EDGES_FILE empty
# (no DAG wiring in scope; we are exercising the back-link branch only).
unset STUB_BLOCKED_BY_20 STUB_BLOCKED_BY_10
export STUB_PROBE_RC=0
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_EXISTING_BLOCKERS=""
export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
export STUB_POST_RC=0

# (q) Comment exists matching the umbrella prefix → BACKLINKS_SKIPPED_EXISTING=1,
#     zero `gh issue comment` invocations recorded in STUB_COMMENT_LOG.
{
  q_children="$TMP/children-q.tsv"
  q_edges="$TMP/edges-q.tsv"
  q_out="$TMP/wire-out-q"
  q_err="$TMP/wire-err-q"
  q_comment_log="$TMP/comment-log-q.txt"
  : > "$q_comment_log"
  printf '20\tsome-child\thttp://x\n' > "$q_children"
  : > "$q_edges"   # no DAG edges — back-link branch only
  # Stub returns one matching body (other unrelated comments interleaved to
  # exercise the substring-grep tolerance).
  export STUB_LIST_COMMENTS_RESPONSE=$'unrelated comment\nPart of umbrella #1 — Some title\nanother comment\n'
  export STUB_LIST_COMMENTS_RC=0
  PATH="$STUB_BIN:$PATH" STUB_COMMENT_LOG="$q_comment_log" \
    bash "$HELPERS" wire-dag \
      --tmpdir "$TMP" --umbrella 1 --umbrella-title "Some title" \
      --children-file "$q_children" --edges-file "$q_edges" \
      --repo o/r > "$q_out" 2> "$q_err" || true
  ok=1
  grep -qE 'BACKLINKS_SKIPPED_EXISTING=1' "$q_out" || ok=0
  grep -qE 'BACKLINKS_POSTED=0' "$q_out" || ok=0
  comment_calls=$(wc -l < "$q_comment_log" | tr -d ' ')
  [ "$comment_calls" = "0" ] || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ existing back-link comment → BACKLINKS_SKIPPED_EXISTING=1, zero posts\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ existing back-link did not skip comment\n     stdout:\n'
    sed 's/^/       /' "$q_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$q_err"
    printf '     comment log lines: %s\n' "$comment_calls"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_LIST_COMMENTS_RESPONSE STUB_COMMENT_LOG
}

# (r) No matching comment → BACKLINKS_POSTED=1, exactly one `gh issue comment`
#     invocation recorded in STUB_COMMENT_LOG.
{
  r_children="$TMP/children-r.tsv"
  r_edges="$TMP/edges-r.tsv"
  r_out="$TMP/wire-out-r"
  r_err="$TMP/wire-err-r"
  r_comment_log="$TMP/comment-log-r.txt"
  : > "$r_comment_log"
  printf '20\tsome-child\thttp://x\n' > "$r_children"
  : > "$r_edges"
  # Stub returns comments that do NOT contain the umbrella back-link prefix.
  export STUB_LIST_COMMENTS_RESPONSE=$'unrelated\nanother\nnope\n'
  export STUB_LIST_COMMENTS_RC=0
  PATH="$STUB_BIN:$PATH" STUB_COMMENT_LOG="$r_comment_log" \
    bash "$HELPERS" wire-dag \
      --tmpdir "$TMP" --umbrella 1 --umbrella-title "Some title" \
      --children-file "$r_children" --edges-file "$r_edges" \
      --repo o/r > "$r_out" 2> "$r_err" || true
  ok=1
  grep -qE 'BACKLINKS_SKIPPED_EXISTING=0' "$r_out" || ok=0
  grep -qE 'BACKLINKS_POSTED=1' "$r_out" || ok=0
  comment_calls=$(wc -l < "$r_comment_log" | tr -d ' ')
  [ "$comment_calls" = "1" ] || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ no matching back-link → BACKLINKS_POSTED=1, exactly one post\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ no-match scenario did not post exactly one back-link\n     stdout:\n'
    sed 's/^/       /' "$r_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$r_err"
    printf '     comment log lines: %s\n' "$comment_calls"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_LIST_COMMENTS_RESPONSE STUB_COMMENT_LOG
}

# (s) Numeric prefix-collision guard: comment for umbrella #12 is present
#     while we look up #1. The trailing ` — ` separator in the marker
#     prevents the prefix-collision (without it, `Part of umbrella #1` would
#     false-match `Part of umbrella #12`). Assert post happens.
{
  s_children="$TMP/children-s.tsv"
  s_edges="$TMP/edges-s.tsv"
  s_out="$TMP/wire-out-s"
  s_err="$TMP/wire-err-s"
  s_comment_log="$TMP/comment-log-s.txt"
  : > "$s_comment_log"
  printf '20\tsome-child\thttp://x\n' > "$s_children"
  : > "$s_edges"
  # Stub returns a comment for umbrella #12 (a sibling, not us).
  export STUB_LIST_COMMENTS_RESPONSE=$'Part of umbrella #12 — Other title\n'
  export STUB_LIST_COMMENTS_RC=0
  PATH="$STUB_BIN:$PATH" STUB_COMMENT_LOG="$s_comment_log" \
    bash "$HELPERS" wire-dag \
      --tmpdir "$TMP" --umbrella 1 --umbrella-title "Some title" \
      --children-file "$s_children" --edges-file "$s_edges" \
      --repo o/r > "$s_out" 2> "$s_err" || true
  ok=1
  grep -qE 'BACKLINKS_SKIPPED_EXISTING=0' "$s_out" || ok=0
  grep -qE 'BACKLINKS_POSTED=1' "$s_out" || ok=0
  comment_calls=$(wc -l < "$s_comment_log" | tr -d ' ')
  [ "$comment_calls" = "1" ] || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ #12 prefix does not false-match #1 (separator-anchored grep)\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ prefix collision was not prevented\n     stdout:\n'
    sed 's/^/       /' "$s_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$s_err"
    printf '     comment log lines: %s\n' "$comment_calls"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_LIST_COMMENTS_RESPONSE STUB_COMMENT_LOG
}

# (t) Fail-open posture: STUB_LIST_COMMENTS_RC non-zero simulates a transient
#     gh failure on the comments-list probe. helpers.sh should treat the probe
#     as having found nothing and post the back-link comment.
{
  t_children="$TMP/children-t.tsv"
  t_edges="$TMP/edges-t.tsv"
  t_out="$TMP/wire-out-t"
  t_err="$TMP/wire-err-t"
  t_comment_log="$TMP/comment-log-t.txt"
  : > "$t_comment_log"
  printf '20\tsome-child\thttp://x\n' > "$t_children"
  : > "$t_edges"
  export STUB_LIST_COMMENTS_RESPONSE=""
  export STUB_LIST_COMMENTS_RC=22
  PATH="$STUB_BIN:$PATH" STUB_COMMENT_LOG="$t_comment_log" \
    bash "$HELPERS" wire-dag \
      --tmpdir "$TMP" --umbrella 1 --umbrella-title "Some title" \
      --children-file "$t_children" --edges-file "$t_edges" \
      --repo o/r > "$t_out" 2> "$t_err" || true
  ok=1
  grep -qE 'BACKLINKS_SKIPPED_EXISTING=0' "$t_out" || ok=0
  grep -qE 'BACKLINKS_POSTED=1' "$t_out" || ok=0
  comment_calls=$(wc -l < "$t_comment_log" | tr -d ' ')
  [ "$comment_calls" = "1" ] || ok=0
  if [ "$ok" = "1" ]; then
    printf '  ✅ comments-list transient failure (RC=22) → fail-open, posts back-link\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ fail-open posture not honored\n     stdout:\n'
    sed 's/^/       /' "$t_out"
    printf '     stderr:\n'
    sed 's/^/       /' "$t_err"
    printf '     comment log lines: %s\n' "$comment_calls"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_LIST_COMMENTS_RESPONSE STUB_LIST_COMMENTS_RC STUB_COMMENT_LOG
}

echo ""
echo "test-helpers.sh: wire-dag --no-backlinks subcommand (created-eq-1 bypass; closes #717)"

# Reset stub state for the --no-backlinks suite — fresh probe-ok, blocker-id
# resolves, no existing edges, 200 OK on per-edge POST.
export STUB_PROBE_RC=0
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
export STUB_POST_RC=0

# (m) --no-backlinks probes the FIRST CHILD, not the (empty) umbrella.
# Set UMBRELLA_PROBE_TARGET_FILE to capture the probe URL helpers.sh emits.
PROBE_TARGET_FILE="$TMP/probe-target.txt"
COMMENT_LOG="$TMP/comment-log.txt"
: > "$COMMENT_LOG"
rm -f "$PROBE_TARGET_FILE"
printf '20\tsome-child\thttp://x\n' > "$TMP/children.tsv"
printf '10\t20\n' > "$TMP/edges.tsv"
PATH="$STUB_BIN:$PATH" UMBRELLA_PROBE_TARGET_FILE="$PROBE_TARGET_FILE" STUB_COMMENT_LOG="$COMMENT_LOG" \
  bash "$HELPERS" wire-dag --no-backlinks \
    --tmpdir "$TMP" --umbrella '' --umbrella-title "" \
    --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
    --repo o/r > "$TMP/wire-out.nbl" 2> "$TMP/wire-err.nbl" || true
if [ -s "$PROBE_TARGET_FILE" ] && grep -q '/issues/20/dependencies/blocked_by' "$PROBE_TARGET_FILE" \
     && ! grep -q '/issues/1/dependencies/blocked_by' "$PROBE_TARGET_FILE"; then
  printf '  ✅ --no-backlinks probes first child (not umbrella)\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ --no-backlinks should probe first child URL\n     probe-target.txt:\n'
  if [ -e "$PROBE_TARGET_FILE" ]; then sed 's/^/       /' "$PROBE_TARGET_FILE"; else echo "       (file missing)"; fi
  FAIL=$((FAIL + 1))
fi

# (n) --no-backlinks issues ZERO `gh issue comment` calls — entire back-link loop is skipped.
COMMENT_COUNT=$(wc -l < "$COMMENT_LOG" | tr -d ' ')
if [ "$COMMENT_COUNT" = "0" ]; then
  printf '  ✅ --no-backlinks posts zero back-link comments\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ --no-backlinks unexpectedly posted %s comment(s); expected 0\n' "$COMMENT_COUNT"
  FAIL=$((FAIL + 1))
fi

# (o) Split into two scenarios after issue #728's three-way probe classification:
# (o.1) --no-backlinks + feature-missing probe → legacy "Back-links suppressed (--no-backlinks)" warning.
# (o.2) --no-backlinks + transient probe failure → new "wire-dag probe failed" warning, legacy SUPPRESSED.

# (o.1) Feature-missing 404 (fingerprinted body) → PROBE_FAILED=0, legacy warning fires.
export STUB_PROBE_RESPONSE_1=$'HTTP/2 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"The dependencies feature is not found on this repository","status":"404"}\n'
export STUB_PROBE_RC_1=22
: > "$COMMENT_LOG"
rm -f "$PROBE_TARGET_FILE"
rm -f "$TMP/probe-call-count.o1"
PATH="$STUB_BIN:$PATH" UMBRELLA_PROBE_TARGET_FILE="$PROBE_TARGET_FILE" \
  STUB_COMMENT_LOG="$COMMENT_LOG" PROBE_CALL_COUNT_FILE="$TMP/probe-call-count.o1" \
  bash "$HELPERS" wire-dag --no-backlinks \
    --tmpdir "$TMP" --umbrella '' --umbrella-title "" \
    --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
    --repo o/r > "$TMP/wire-out.nbl-fmiss" 2> "$TMP/wire-err.nbl-fmiss" || true
if grep -q 'Back-links suppressed (--no-backlinks)' "$TMP/wire-err.nbl-fmiss" \
     && ! grep -q 'Back-links posted via comments' "$TMP/wire-err.nbl-fmiss" \
     && grep -qE '^PROBE_FAILED=0$' "$TMP/wire-out.nbl-fmiss"; then
  printf '  ✅ --no-backlinks + feature-missing → legacy mode-aware stderr + PROBE_FAILED=0\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ --no-backlinks + feature-missing expected legacy stderr + PROBE_FAILED=0\n     stdout:\n'
  sed 's/^/       /' "$TMP/wire-out.nbl-fmiss"
  printf '     stderr:\n'
  sed 's/^/       /' "$TMP/wire-err.nbl-fmiss"
  FAIL=$((FAIL + 1))
fi
unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RC_1

# (o.2) Transient probe failure: 5xx on both attempts → PROBE_FAILED=1, new warning fires, legacy SUPPRESSED.
export STUB_PROBE_RESPONSE_1=$'HTTP/2 502 Bad Gateway\r\n\r\n{"message":"Bad Gateway"}\n'
export STUB_PROBE_RC_1=22
export STUB_PROBE_RESPONSE_2=$'HTTP/2 502 Bad Gateway\r\n\r\n{"message":"Bad Gateway"}\n'
export STUB_PROBE_RC_2=22
: > "$COMMENT_LOG"
rm -f "$PROBE_TARGET_FILE"
rm -f "$TMP/probe-call-count.o2"
PATH="$STUB_BIN:$PATH" UMBRELLA_PROBE_TARGET_FILE="$PROBE_TARGET_FILE" \
  STUB_COMMENT_LOG="$COMMENT_LOG" PROBE_CALL_COUNT_FILE="$TMP/probe-call-count.o2" \
  bash "$HELPERS" wire-dag --no-backlinks \
    --tmpdir "$TMP" --umbrella '' --umbrella-title "" \
    --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
    --repo o/r > "$TMP/wire-out.nbl-pfail" 2> "$TMP/wire-err.nbl-pfail" || true
if grep -q 'wire-dag probe failed (HTTP 502)' "$TMP/wire-err.nbl-pfail" \
     && ! grep -q 'Back-links suppressed (--no-backlinks)' "$TMP/wire-err.nbl-pfail" \
     && ! grep -q 'Back-links posted via comments' "$TMP/wire-err.nbl-pfail" \
     && grep -qE '^PROBE_FAILED=1$' "$TMP/wire-out.nbl-pfail"; then
  printf '  ✅ --no-backlinks + transient probe-fail → new probe-failed stderr + PROBE_FAILED=1\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ --no-backlinks + transient probe-fail expected new stderr + PROBE_FAILED=1\n     stdout:\n'
  sed 's/^/       /' "$TMP/wire-out.nbl-pfail"
  printf '     stderr:\n'
  sed 's/^/       /' "$TMP/wire-err.nbl-pfail"
  FAIL=$((FAIL + 1))
fi
# Verify the probe was actually attempted twice (retry on 5xx).
if [ -f "$TMP/probe-call-count.o2" ] && [ "$(cat "$TMP/probe-call-count.o2")" = "2" ]; then
  printf '  ✅ --no-backlinks + 5xx → probe retried exactly once (2 attempts)\n'
  PASS=$((PASS + 1))
else
  printf '  ❌ --no-backlinks + 5xx expected 2 probe attempts, got %s\n' \
    "$(cat "$TMP/probe-call-count.o2" 2>/dev/null || echo 'missing')"
  FAIL=$((FAIL + 1))
fi
unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RC_1 STUB_PROBE_RESPONSE_2 STUB_PROBE_RC_2
unset STUB_COMMENT_LOG

# (p) --umbrella '' WITHOUT --no-backlinks must error.
if bash "$HELPERS" wire-dag --tmpdir "$TMP" --umbrella '' \
     --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
     --repo o/r > "$TMP/wire-out.bad" 2> "$TMP/wire-err.bad"; then
  printf '  ❌ empty --umbrella without --no-backlinks should fail; got success\n'
  FAIL=$((FAIL + 1))
else
  if grep -q 'use --no-backlinks to omit it on the created-eq-1 bypass path' "$TMP/wire-err.bad"; then
    printf '  ✅ empty --umbrella without --no-backlinks errors with helpful message\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ expected helpful error message; got:\n'
    sed 's/^/       /' "$TMP/wire-err.bad"
    FAIL=$((FAIL + 1))
  fi
fi

echo ""
echo "test-helpers.sh: wire-dag probe classification (issue #728)"

# Reset stub state for the probe-classification suite.
unset STUB_PROBE_RESPONSE STUB_PROBE_RC
unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RESPONSE_2 STUB_PROBE_RC_1 STUB_PROBE_RC_2
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_EXISTING_BLOCKERS=""
export STUB_NATIVE_CHECK_RESPONSE=""
export STUB_POST_RESPONSE=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n{}\n'
export STUB_POST_RC=0

# t_probe_404_feature_missing — fingerprinted 404 → api_available=false,
# PROBE_FAILED=0, repo-wide "API not available" stderr fires.
run_probe_test() {
  local label="$1" probe_response_1="$2" probe_rc_1="$3" probe_response_2="$4" probe_rc_2="$5"
  local expect_probe_failed="$6" expect_legacy_warning="$7" expect_new_warning="$8" expect_calls="$9"
  local children="$TMP/children-pt.tsv"
  local edges="$TMP/edges-pt.tsv"
  local out_file="$TMP/wire-out-pt"
  local err_file="$TMP/wire-err-pt"
  local count_file="$TMP/probe-call-count-pt"
  printf '20\tsome-child\thttp://x\n' > "$children"
  printf '10\t20\n' > "$edges"
  rm -f "$count_file"
  unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RESPONSE_2 STUB_PROBE_RC_1 STUB_PROBE_RC_2
  export STUB_PROBE_RESPONSE_1="$probe_response_1"
  export STUB_PROBE_RC_1="$probe_rc_1"
  if [ -n "$probe_response_2" ] || [ -n "$probe_rc_2" ]; then
    export STUB_PROBE_RESPONSE_2="$probe_response_2"
    export STUB_PROBE_RC_2="$probe_rc_2"
  fi
  PATH="$STUB_BIN:$PATH" PROBE_CALL_COUNT_FILE="$count_file" \
    bash "$HELPERS" wire-dag \
      --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
      --children-file "$children" --edges-file "$edges" \
      --repo o/r > "$out_file" 2> "$err_file" || true
  local ok=1
  if ! grep -qE "^PROBE_FAILED=${expect_probe_failed}$" "$out_file"; then ok=0; fi
  if [ "$expect_legacy_warning" = "yes" ]; then
    grep -q 'GitHub blocked-by dependency API not available' "$err_file" || ok=0
  else
    grep -q 'GitHub blocked-by dependency API not available' "$err_file" && ok=0
  fi
  if [ "$expect_new_warning" = "yes" ]; then
    grep -q 'wire-dag probe failed (HTTP' "$err_file" || ok=0
  else
    grep -q 'wire-dag probe failed (HTTP' "$err_file" && ok=0
  fi
  local got_calls
  got_calls=$(cat "$count_file" 2>/dev/null || echo 0)
  if [ "$got_calls" != "$expect_calls" ]; then ok=0; fi
  if [ "$ok" = "1" ]; then
    printf '  ✅ %s\n' "$label"
    PASS=$((PASS + 1))
  else
    printf '  ❌ %s — PROBE_FAILED=%s expected, got %s; legacy=%s new=%s calls=%s/%s\n     stdout:\n' \
      "$label" "$expect_probe_failed" \
      "$(grep -oE '^PROBE_FAILED=[0-9]+$' "$out_file" || echo NONE)" \
      "$(grep -q 'API not available' "$err_file" && echo seen || echo absent)" \
      "$(grep -q 'wire-dag probe failed' "$err_file" && echo seen || echo absent)" \
      "$got_calls" "$expect_calls"
    sed 's/^/       /' "$out_file"
    printf '     stderr:\n'
    sed 's/^/       /' "$err_file"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RESPONSE_2 STUB_PROBE_RC_1 STUB_PROBE_RC_2
}

# Canonical fixture bodies.
PROBE_BODY_FEATURE_MISSING_404=$'HTTP/2 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"The dependencies feature is not found on this repository","status":"404"}\n'
PROBE_BODY_AMBIGUOUS_404=$'HTTP/2 404 Not Found\r\nContent-Type: application/json\r\n\r\n{"message":"Issue 99999 not found","status":"404"}\n'
PROBE_BODY_502=$'HTTP/2 502 Bad Gateway\r\n\r\n{"message":"Bad Gateway"}\n'
PROBE_BODY_200=$'HTTP/2 200 OK\r\nContent-Type: application/json\r\n\r\n[]\n'
PROBE_BODY_403=$'HTTP/2 403 Forbidden\r\n\r\n{"message":"Resource not accessible by integration"}\n'
PROBE_BODY_429=$'HTTP/2 429 Too Many Requests\r\nRetry-After: 60\r\n\r\n{"message":"API rate limit exceeded"}\n'

# t_probe_404_feature_missing
run_probe_test "probe 404 feature-missing → PROBE_FAILED=0, legacy warning fires (1 attempt)" \
  "$PROBE_BODY_FEATURE_MISSING_404" 22 "" "" 0 yes no 1

# t_probe_5xx_then_200 — first 502, retry 200 OK → api_available=true, PROBE_FAILED=0, no warning.
run_probe_test "probe 502 then 200 → PROBE_FAILED=0, no warning, 2 attempts" \
  "$PROBE_BODY_502" 22 "$PROBE_BODY_200" 0 0 no no 2

# t_probe_5xx_twice — 502 on both attempts → PROBE_FAILED=1, new warning, no legacy warning.
run_probe_test "probe 502 twice → PROBE_FAILED=1, new probe-failed warning, 2 attempts" \
  "$PROBE_BODY_502" 22 "$PROBE_BODY_502" 22 1 no yes 2

# t_probe_no_status_then_no_status — empty body, non-zero rc, both attempts → PROBE_FAILED=1.
run_probe_test "probe empty-status twice → PROBE_FAILED=1, new warning, 2 attempts" \
  "" 22 "" 22 1 no yes 2

# t_probe_403_no_retry — 403 on first attempt → PROBE_FAILED=1, exactly 1 attempt (no retry).
run_probe_test "probe 403 → PROBE_FAILED=1, no retry (1 attempt)" \
  "$PROBE_BODY_403" 22 "" "" 1 no yes 1

# t_probe_429_no_retry — 429 (any) → PROBE_FAILED=1, exactly 1 attempt (no retry per DECISION_1 simplification).
run_probe_test "probe 429 → PROBE_FAILED=1, no retry (1 attempt)" \
  "$PROBE_BODY_429" 22 "" "" 1 no yes 1

# t_probe_ambiguous_404 — 404 without fingerprint body → PROBE_FAILED=1.
run_probe_test "probe 404 ambiguous → PROBE_FAILED=1, new warning, 1 attempt" \
  "$PROBE_BODY_AMBIGUOUS_404" 22 "" "" 1 no yes 1

# t_probe_5xx_then_404_feature_missing — first 502, retry fingerprinted 404 → PROBE_FAILED=0, legacy warning.
run_probe_test "probe 502 then feature-missing 404 → PROBE_FAILED=0, legacy warning, 2 attempts" \
  "$PROBE_BODY_502" 22 "$PROBE_BODY_FEATURE_MISSING_404" 22 0 yes no 2

unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RESPONSE_2 STUB_PROBE_RC_1 STUB_PROBE_RC_2

# t_probe_no_backlinks_first_child_404_ambiguous — --no-backlinks first-child probe gets
# a stale-child 404 (non-fingerprint) → PROBE_FAILED=1 (operational, not feature-off).
{
  pchildren="$TMP/children-pt-nbl.tsv"
  pedges="$TMP/edges-pt-nbl.tsv"
  pout="$TMP/wire-out-pt-nbl"
  perr="$TMP/wire-err-pt-nbl"
  pcount="$TMP/probe-call-count-pt-nbl"
  printf '20\tsome-child\thttp://x\n' > "$pchildren"
  printf '10\t20\n' > "$pedges"
  rm -f "$pcount"
  export STUB_PROBE_RESPONSE_1="$PROBE_BODY_AMBIGUOUS_404"
  export STUB_PROBE_RC_1=22
  PATH="$STUB_BIN:$PATH" PROBE_CALL_COUNT_FILE="$pcount" \
    bash "$HELPERS" wire-dag --no-backlinks \
      --tmpdir "$TMP" --umbrella '' --umbrella-title "" \
      --children-file "$pchildren" --edges-file "$pedges" \
      --repo o/r > "$pout" 2> "$perr" || true
  if grep -qE '^PROBE_FAILED=1$' "$pout" \
       && grep -q 'wire-dag probe failed (HTTP 404)' "$perr" \
       && [ "$(cat "$pcount" 2>/dev/null || echo 0)" = "1" ]; then
    printf '  ✅ --no-backlinks ambiguous-404 first-child → PROBE_FAILED=1 (stale child not feature-off)\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ --no-backlinks ambiguous-404 first-child unexpected behavior\n     stdout:\n'
    sed 's/^/       /' "$pout"
    printf '     stderr:\n'
    sed 's/^/       /' "$perr"
    FAIL=$((FAIL + 1))
  fi
  unset STUB_PROBE_RESPONSE_1 STUB_PROBE_RC_1
}

# t_probe_empty_target — --no-backlinks with empty CHILDREN_FILE → no probe attempted,
# api_available=false, PROBE_FAILED=0, no probe stderr.
{
  pchildren="$TMP/children-pt-empty.tsv"
  pedges="$TMP/edges-pt-empty.tsv"
  pout="$TMP/wire-out-pt-empty"
  perr="$TMP/wire-err-pt-empty"
  pcount="$TMP/probe-call-count-pt-empty"
  : > "$pchildren"
  : > "$pedges"
  rm -f "$pcount"
  PATH="$STUB_BIN:$PATH" PROBE_CALL_COUNT_FILE="$pcount" \
    bash "$HELPERS" wire-dag --no-backlinks \
      --tmpdir "$TMP" --umbrella '' --umbrella-title "" \
      --children-file "$pchildren" --edges-file "$pedges" \
      --repo o/r > "$pout" 2> "$perr" || true
  if grep -qE '^PROBE_FAILED=0$' "$pout" \
       && ! grep -q 'wire-dag probe failed' "$perr" \
       && { [ ! -f "$pcount" ] || [ "$(cat "$pcount" 2>/dev/null || echo 0)" = "0" ]; }; then
    printf '  ✅ --no-backlinks empty CHILDREN_FILE → no probe attempted, PROBE_FAILED=0\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ --no-backlinks empty CHILDREN_FILE unexpected behavior\n     stdout:\n'
    sed 's/^/       /' "$pout"
    printf '     stderr:\n'
    sed 's/^/       /' "$perr"
    FAIL=$((FAIL + 1))
  fi
}

# t_probe_dry_run_includes_probe_failed — dry-run output must include PROBE_FAILED=0
# (initialized before DRY_RUN early-exit so set -u cannot trip the printf).
{
  printf '20\tsome-child\thttp://x\n' > "$TMP/children.tsv"
  printf '10\t20\n' > "$TMP/edges.tsv"
  DRY_OUT=$(PATH="$STUB_BIN:$PATH" bash "$HELPERS" wire-dag \
    --tmpdir "$TMP" --umbrella 1 --umbrella-title "T" \
    --children-file "$TMP/children.tsv" --edges-file "$TMP/edges.tsv" \
    --repo o/r --dry-run 2>&1) || true
  if printf '%s\n' "$DRY_OUT" | grep -qE '^PROBE_FAILED=0$'; then
    printf '  ✅ dry-run includes PROBE_FAILED=0\n'
    PASS=$((PASS + 1))
  else
    printf '  ❌ dry-run did not include PROBE_FAILED=0\n     stdout:\n'
    printf '%s\n' "$DRY_OUT" | sed 's/^/       /'
    FAIL=$((FAIL + 1))
  fi
}

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
