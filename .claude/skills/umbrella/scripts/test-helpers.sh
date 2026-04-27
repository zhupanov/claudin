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
#   STUB_EXISTING_BLOCKERS      — value to print for existing-edges lookup (per child)
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
          printf '%s' "${STUB_EXISTING_BLOCKERS:-}"
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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
