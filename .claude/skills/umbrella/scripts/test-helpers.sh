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
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
