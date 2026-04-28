#!/usr/bin/env bash
# test-validate-pieces-json.sh — regression harness for validate-pieces-json.sh
# Wired into CI via: make test-validate-pieces-json
# See test-validate-pieces-json.md for the full contract.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
VALIDATOR="$SCRIPT_DIR/validate-pieces-json.sh"
TMPDIR_TEST=$(mktemp -d -t test-validate-pieces-json-XXXXXX)
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0

assert_exit() {
  local desc="$1" expected_exit="$2" expected_err_substr="$3"
  shift 3
  local actual_exit=0 stderr_out
  stderr_out=$("$@" 2>&1 >/dev/null) || actual_exit=$?
  if [ "$actual_exit" -ne "$expected_exit" ]; then
    echo "FAIL: $desc — expected exit $expected_exit, got $actual_exit"
    echo "  stderr: $stderr_out"
    FAIL=$((FAIL + 1))
    return
  fi
  if [ -n "$expected_err_substr" ] && [[ "$stderr_out" != *"$expected_err_substr"* ]]; then
    echo "FAIL: $desc — stderr missing '$expected_err_substr'"
    echo "  stderr: $stderr_out"
    FAIL=$((FAIL + 1))
    return
  fi
  PASS=$((PASS + 1))
}

# --- Valid inputs ---

cat > "$TMPDIR_TEST/valid-2.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": []},
  {"title": "c", "body": "d", "depends_on": [1]}
]
EOF

assert_exit "valid 2-entry pieces.json" 0 "" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-2.json" --count 2

cat > "$TMPDIR_TEST/valid-3.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": []},
  {"title": "c", "body": "d", "depends_on": [1]},
  {"title": "e", "body": "f", "depends_on": [1, 2]}
]
EOF

assert_exit "valid 3-entry pieces.json" 0 "" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-3.json" --count 3

cat > "$TMPDIR_TEST/valid-no-deps.json" << 'EOF'
[
  {"title": "a", "body": "b"},
  {"title": "c", "body": "d"}
]
EOF

assert_exit "valid pieces.json with missing depends_on (defaults to [])" 0 "" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-no-deps.json" --count 2

# --- Invalid inputs ---

assert_exit "missing --pieces-file" 1 "ERROR=--pieces-file is required" \
  bash "$VALIDATOR" --count 2

assert_exit "missing --count" 1 "ERROR=--count is required" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-2.json"

assert_exit "non-integer --count" 1 "ERROR=--count must be a non-negative integer" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-2.json" --count abc

assert_exit "file not found" 1 "ERROR=pieces-json file not found" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/nonexistent.json" --count 2

echo "not json" > "$TMPDIR_TEST/invalid-json.txt"
assert_exit "non-JSON file" 1 "ERROR=invalid pieces-json" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/invalid-json.txt" --count 1

echo '{"a": 1}' > "$TMPDIR_TEST/not-array.json"
assert_exit "non-array JSON" 1 "ERROR=invalid pieces-json: top-level value must be a JSON array" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/not-array.json" --count 1

assert_exit "count mismatch (expect 3, got 2)" 1 "ERROR=pieces-json length mismatch" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-2.json" --count 3

cat > "$TMPDIR_TEST/bad-deps-type.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": "not-array"},
  {"title": "c", "body": "d", "depends_on": [1]}
]
EOF

assert_exit "depends_on is string not array" 1 "ERROR=pieces-json entry 1 field 'depends_on' must be an array" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/bad-deps-type.json" --count 2

cat > "$TMPDIR_TEST/forward-ref.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": [2]},
  {"title": "c", "body": "d", "depends_on": []}
]
EOF

assert_exit "forward reference (entry 1 depends on entry 2)" 1 "ERROR=pieces-json entry 1 has out-of-range depends_on" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/forward-ref.json" --count 2

cat > "$TMPDIR_TEST/self-ref.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": []},
  {"title": "c", "body": "d", "depends_on": [2]}
]
EOF

assert_exit "self-reference (entry 2 depends on itself)" 1 "ERROR=pieces-json entry 2 has out-of-range depends_on" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/self-ref.json" --count 2

cat > "$TMPDIR_TEST/zero-ref.json" << 'EOF'
[
  {"title": "a", "body": "b", "depends_on": [0]},
  {"title": "c", "body": "d", "depends_on": [1]}
]
EOF

assert_exit "zero-based reference (must be 1-based)" 1 "ERROR=pieces-json entry 1 has out-of-range depends_on" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/zero-ref.json" --count 2

assert_exit "unknown argument" 1 "ERROR=Unknown argument" \
  bash "$VALIDATOR" --pieces-file "$TMPDIR_TEST/valid-2.json" --count 2 --extra

# --- Summary ---

echo ""
echo "test-validate-pieces-json: $PASS passed, $FAIL failed"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
