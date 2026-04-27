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
#   STUB_NATIVE_CHECK_RESPONSE  — value to print for the native blocked_by check (back-link branch)
set -e
case "$1 $2" in
  "api /repos/"*"/issues/"*"/dependencies/blocked_by")
    # Could be: probe (--silent), existing-edges (--jq), native check (--jq with select),
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
      # Native check (jq with select).
      printf '%s' "${STUB_NATIVE_CHECK_RESPONSE:-}"
      exit 0
    else
      # Probe (--silent).
      exit "${STUB_PROBE_RC:-0}"
    fi
    ;;
  "api /repos/"*"/issues/"*)
    # Blocker-id lookup: gh api /repos/$REPO/issues/$N --jq .id
    printf '%s' "${STUB_BLOCKER_ID:-}"
    exit "${STUB_BLOCKER_ID_RC:-0}"
    ;;
  "issue comment")
    # Back-link comment posting — always succeed silently.
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

# Default stub state: probe ok, blocker-id resolves, no existing edges, no native umbrella relationship.
export STUB_PROBE_RC=0
export STUB_BLOCKER_ID=999001
export STUB_BLOCKER_ID_RC=0
export STUB_EXISTING_BLOCKERS=""
export STUB_NATIVE_CHECK_RESPONSE=""

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
export STUB_PROBE_RC=22
export STUB_POST_RESPONSE=""
export STUB_POST_RC=0
assert_wire_dag "probe failure → repo-wide skip" 'EDGES_SKIPPED_API_UNAVAILABLE=1' 0
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
export STUB_NATIVE_CHECK_RESPONSE=""
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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
