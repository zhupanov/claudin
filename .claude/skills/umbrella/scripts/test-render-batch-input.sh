#!/usr/bin/env bash
# test-render-batch-input.sh — regression harness for /umbrella's render-batch-input.sh.
#
# Pins the malformed-pieces.json gatekeeper contract documented in
# render-batch-input.md and SKILL.md Step 3B.1: malformed JSON MUST surface as
# the stable `ERROR=invalid pieces.json: <reason>` stderr line + exit 1, not as
# a leaked raw `jq` parse error with jq's exit code.
#
# Closes #646 — Codex-surfaced /review finding (2+ YES vote): the umbrella skill
# writes pieces.json as untrusted LLM output and this script normalizes failures
# into a stable grammar; without the guard, a parse error breaks the contract
# at the exact LLM boundary the script is supposed to harden.
#
# Run manually:
#   bash .claude/skills/umbrella/scripts/test-render-batch-input.sh
#
# Wired into `make lint` via the `test-umbrella-render-batch-input` target.

set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SCRIPT="$HERE/render-batch-input.sh"
TMP=$(mktemp -d -t test-umbrella-render-batch-input-XXXXXX)
trap 'rm -rf "$TMP"' EXIT

PASS=0
FAIL=0

if [[ ! -x "$SCRIPT" ]] && [[ ! -f "$SCRIPT" ]]; then
  echo "ERROR: render-batch-input.sh not found at $SCRIPT" >&2
  exit 1
fi

# assert_malformed_json — feed malformed pieces.json and verify the script
# emits the stable ERROR=invalid pieces.json: <reason> grammar on stderr and
# exits 1. Captures stderr, runs the script, asserts on shape.
assert_malformed_json() {
  local label="$1"
  local content="$2"
  local pieces="$TMP/pieces.json"
  printf '%s' "$content" > "$pieces"
  local stderr_file="$TMP/stderr.txt"
  local exit_code=0
  bash "$SCRIPT" --tmpdir "$TMP" --pieces-file "$pieces" >/dev/null 2>"$stderr_file" || exit_code=$?

  if [[ "$exit_code" -ne 1 ]]; then
    printf '  ❌ %s — expected exit 1, got %d (stderr: %s)\n' \
      "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -q '^ERROR=invalid pieces.json:' "$stderr_file"; then
    printf '  ❌ %s — stderr missing "ERROR=invalid pieces.json:" line. Got: %s\n' \
      "$label" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — exit 1 + ERROR=invalid pieces.json: line present\n' "$label"
  PASS=$((PASS + 1))
}

# assert_too_few_entries — feed valid JSON with <2 entries and verify the
# pre-existing "at least 2 entries" error path still fires and is preserved
# alongside the new malformed-JSON guard.
assert_too_few_entries() {
  local label="$1"
  local content="$2"
  local pieces="$TMP/pieces.json"
  printf '%s' "$content" > "$pieces"
  local stderr_file="$TMP/stderr.txt"
  local exit_code=0
  bash "$SCRIPT" --tmpdir "$TMP" --pieces-file "$pieces" >/dev/null 2>"$stderr_file" || exit_code=$?

  if [[ "$exit_code" -ne 1 ]]; then
    printf '  ❌ %s — expected exit 1, got %d (stderr: %s)\n' \
      "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -q '^ERROR=pieces.json must contain at least 2 entries' "$stderr_file"; then
    printf '  ❌ %s — stderr missing existing "at least 2 entries" path. Got: %s\n' \
      "$label" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — pre-existing too-few-entries path preserved\n' "$label"
  PASS=$((PASS + 1))
}

# assert_valid_baseline — feed valid 2-piece pieces.json and verify the script
# succeeds (exit 0), prints BATCH_INPUT_FILE=, and writes the markdown output.
# Confirms the new guard does not regress the happy path.
assert_valid_baseline() {
  local label="$1"
  local pieces="$TMP/pieces.json"
  cat > "$pieces" <<'EOF'
[
  {"title": "First piece", "body": "First body content.", "depends_on": []},
  {"title": "Second piece", "body": "Second body content.", "depends_on": [1]}
]
EOF
  local stdout_file="$TMP/stdout.txt"
  local stderr_file="$TMP/stderr.txt"
  local exit_code=0
  bash "$SCRIPT" --tmpdir "$TMP" --pieces-file "$pieces" >"$stdout_file" 2>"$stderr_file" || exit_code=$?

  if [[ "$exit_code" -ne 0 ]]; then
    printf '  ❌ %s — expected exit 0, got %d (stderr: %s)\n' \
      "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -q '^BATCH_INPUT_FILE=' "$stdout_file"; then
    printf '  ❌ %s — stdout missing BATCH_INPUT_FILE=. Got: %s\n' \
      "$label" "$(cat "$stdout_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -q '^PIECES_TOTAL=2' "$stdout_file"; then
    printf '  ❌ %s — stdout missing PIECES_TOTAL=2. Got: %s\n' \
      "$label" "$(cat "$stdout_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — exit 0 + BATCH_INPUT_FILE / PIECES_TOTAL emitted\n' "$label"
  PASS=$((PASS + 1))
}

echo "test-render-batch-input.sh: malformed-JSON gatekeeper contract"

# Malformed JSON: unclosed array bracket.
assert_malformed_json "unclosed array" '[{"title":"a","body":"b","depends_on":[]}'

# Malformed JSON: trailing comma (invalid JSON).
assert_malformed_json "trailing comma" '[{"title":"a","body":"b","depends_on":[]},]'

# Malformed JSON: completely garbage payload.
assert_malformed_json "garbage payload" 'not-json-at-all {{{'

# Valid JSON of wrong top-level type (object): the type-assert guard must catch
# this before the per-entry loop crashes with a raw jq: error (which would
# break the same contract this harness pins).
assert_malformed_json "top-level object" '{"a":{"title":"x","body":"y","depends_on":[]},"b":{"title":"x","body":"y","depends_on":[]}}'

# Valid JSON of wrong top-level type (string): another type-mismatch case.
assert_malformed_json "top-level string" '"not-an-array"'

# Valid JSON but too few entries (< 2): exercises the pre-existing path.
assert_too_few_entries "single entry" '[{"title":"a","body":"b","depends_on":[]}]'

# Valid 2-piece baseline: confirms the new guard doesn't regress the happy path.
assert_valid_baseline "valid 2-piece baseline"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
