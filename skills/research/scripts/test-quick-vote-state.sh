#!/usr/bin/env bash
# Regression harness for quick-vote-state.sh.
# Contract: skills/research/scripts/test-quick-vote-state.md
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
HELPER="$REPO_ROOT/skills/research/scripts/quick-vote-state.sh"

pass_count=0
fail_count=0

fail() {
  printf '  ✗ %s\n' "$1" >&2
  fail_count=$((fail_count + 1))
}

pass() {
  printf '  ✓ %s\n' "$1"
  pass_count=$((pass_count + 1))
}

[[ -x "$HELPER" ]] || { echo "FATAL: $HELPER not executable" >&2; exit 1; }

# Use a per-run temp dir
TEST_DIR="$(mktemp -d -t test-quick-vote-state.XXXXXX)"
trap 'rm -rf "$TEST_DIR"' EXIT

echo "=== quick-vote-state.sh round-trip tests ==="

# Round-trip for each valid value
for n in 0 1 2 3; do
  d="$TEST_DIR/round-$n"
  mkdir -p "$d"
  out=$("$HELPER" write --dir "$d" --succeeded "$n" 2>&1)
  if echo "$out" | grep -qE "^LANES_SUCCEEDED=$n$"; then
    pass "write --succeeded $n stdout has LANES_SUCCEEDED=$n"
  else
    fail "write --succeeded $n stdout missing LANES_SUCCEEDED=$n: $out"
  fi
  out=$("$HELPER" read --dir "$d" 2>&1)
  if [[ "$out" == "LANES_SUCCEEDED=$n" ]]; then
    pass "read after write $n → LANES_SUCCEEDED=$n"
  else
    fail "read after write $n got: $out"
  fi
done

# Missing file → defensive default LANES_SUCCEEDED=0
d="$TEST_DIR/missing"
mkdir -p "$d"
out=$("$HELPER" read --dir "$d" 2>&1)
if [[ "$out" == "LANES_SUCCEEDED=0" ]]; then
  pass "read with missing file → LANES_SUCCEEDED=0"
else
  fail "read with missing file got: $out"
fi

# Corrupt content → defensive default LANES_SUCCEEDED=0
d="$TEST_DIR/corrupt"
mkdir -p "$d"
echo "LANES_SUCCEEDED=99" > "$d/quick-vote-state.txt"
out=$("$HELPER" read --dir "$d" 2>&1)
if [[ "$out" == "LANES_SUCCEEDED=0" ]]; then
  pass "read with out-of-range value → LANES_SUCCEEDED=0"
else
  fail "read with out-of-range value got: $out"
fi

# Garbage content → defensive default
d="$TEST_DIR/garbage"
mkdir -p "$d"
echo "RANDOM_GARBAGE" > "$d/quick-vote-state.txt"
out=$("$HELPER" read --dir "$d" 2>&1)
if [[ "$out" == "LANES_SUCCEEDED=0" ]]; then
  pass "read with no LANES_SUCCEEDED line → LANES_SUCCEEDED=0"
else
  fail "read with no LANES_SUCCEEDED line got: $out"
fi

# Empty file → defensive default
d="$TEST_DIR/empty"
mkdir -p "$d"
: > "$d/quick-vote-state.txt"
out=$("$HELPER" read --dir "$d" 2>&1)
if [[ "$out" == "LANES_SUCCEEDED=0" ]]; then
  pass "read with empty file → LANES_SUCCEEDED=0"
else
  fail "read with empty file got: $out"
fi

# Bad --succeeded value → exit 2
d="$TEST_DIR/bad-arg"
mkdir -p "$d"
if "$HELPER" write --dir "$d" --succeeded 99 >/dev/null 2>&1; then
  fail "write --succeeded 99 should exit non-zero"
else
  pass "write --succeeded 99 exits non-zero"
fi

# Missing --dir → exit 2
if "$HELPER" read >/dev/null 2>&1; then
  fail "read without --dir should exit non-zero"
else
  pass "read without --dir exits non-zero"
fi

# Unknown subcommand → exit 2
if "$HELPER" frobnicate --dir "$TEST_DIR" >/dev/null 2>&1; then
  fail "unknown subcommand should exit non-zero"
else
  pass "unknown subcommand exits non-zero"
fi

# Atomic write: tmp file should not linger
d="$TEST_DIR/atomic"
mkdir -p "$d"
"$HELPER" write --dir "$d" --succeeded 3 >/dev/null
LINGERING=$(find "$d" -name "quick-vote-state.*.tmp" 2>/dev/null | wc -l | tr -d ' ')
if [[ "$LINGERING" == "0" ]]; then
  pass "atomic write leaves no .tmp files"
else
  fail "atomic write left $LINGERING .tmp files"
fi

echo ""
echo "=== Results: $pass_count passed, $fail_count failed ==="

if [[ "$fail_count" -gt 0 ]]; then
  exit 1
fi
exit 0
