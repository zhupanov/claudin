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

# assert_invalid_depends_on — feed valid JSON whose entry 2 has a non-integer
# depends_on value (e.g. 1.5) and verify the per-entry validator at
# render-batch-input.sh's `bad_deps` jq predicate emits the documented
# `ERROR=pieces.json entry <i> has out-of-range depends_on values:` line and
# exits 1. Closes #647 — without the integer-only tightening, fractional values
# silently pass and leak into PIECE_<i>_DEPENDS_ON=1.5 downstream.
assert_invalid_depends_on() {
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

  if ! grep -q '^ERROR=pieces.json entry 2 has out-of-range depends_on values:' "$stderr_file"; then
    printf '  ❌ %s — stderr missing "out-of-range depends_on values" line. Got: %s\n' \
      "$label" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — exit 1 + out-of-range depends_on line present\n' "$label"
  PASS=$((PASS + 1))
}

# assert_invalid_title — feed valid JSON whose entry 1 has a title containing an
# embedded LF and verify the per-entry validator rejects it with the documented
# `ERROR=pieces.json entry <i> title contains embedded newline` line + exit 1.
# Closes #648 — without the guard, a multi-line title would pass the existing
# non-empty check and later be emitted as `printf 'PIECE_<i>_TITLE=%s\n' "$title"`,
# splitting one logical KV line into multiple physical stdout lines and silently
# breaking the one-KV-per-line grammar that umbrella SKILL.md Step 3B.1 parses.
assert_invalid_title() {
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

  if ! grep -q '^ERROR=pieces.json entry 1 title contains embedded newline$' "$stderr_file"; then
    printf '  ❌ %s — stderr missing "ERROR=pieces.json entry 1 title contains embedded newline" line. Got: %s\n' \
      "$label" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — exit 1 + embedded-newline title line present\n' "$label"
  PASS=$((PASS + 1))
}

# assert_unwritable_tmpdir — feed a valid pieces.json but point --tmpdir at a
# directory whose write bit is cleared, and verify the script rejects it BEFORE
# any redirect under $TMPDIR (which would otherwise produce a raw bash
# "Permission denied" on `2>"$JQ_PARSE_ERR"` or `: > "$OUT"` and break the
# documented `ERROR=... + exit 1` grammar). Mirrors the existing
# render-umbrella-body.sh:28-30 guard. The cleanup must restore the writable
# mode so the outer trap's `rm -rf "$TMP"` succeeds.
assert_unwritable_tmpdir() {
  local label="$1"
  local sub="$TMP/unwritable-sub"
  mkdir -p "$sub"
  local pieces="$sub/pieces.json"
  cat > "$pieces" <<'EOF'
[
  {"title": "First piece", "body": "First body content.", "depends_on": []},
  {"title": "Second piece", "body": "Second body content.", "depends_on": [1]}
]
EOF
  chmod 555 "$sub"
  local stderr_file="$TMP/stderr.txt"
  local exit_code=0
  bash "$SCRIPT" --tmpdir "$sub" --pieces-file "$pieces" >/dev/null 2>"$stderr_file" || exit_code=$?
  chmod 755 "$sub"

  if [[ "$exit_code" -ne 1 ]]; then
    printf '  ❌ %s — expected exit 1, got %d (stderr: %s)\n' \
      "$label" "$exit_code" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  if ! grep -q '^ERROR=tmpdir not writable:' "$stderr_file"; then
    printf '  ❌ %s — stderr missing "ERROR=tmpdir not writable:" line. Got: %s\n' \
      "$label" "$(cat "$stderr_file")"
    FAIL=$((FAIL + 1))
    return
  fi

  printf '  ✅ %s — exit 1 + ERROR=tmpdir not writable: line present\n' "$label"
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

# Fractional depends_on value: per-entry validator must reject non-integer
# numbers so PIECE_<i>_DEPENDS_ON=1.5 cannot leak downstream into DAG
# construction (closes #647).
assert_invalid_depends_on "fractional depends_on" '[{"title":"a","body":"b","depends_on":[]},{"title":"b","body":"c","depends_on":[1.5]}]'

# Embedded LF in title: per-entry validator must reject newline-bearing titles
# so `printf 'PIECE_<i>_TITLE=%s\n' "$title"` cannot split one logical KV
# into multiple physical stdout lines (closes #648). The JSON `\n` escape
# materializes via jq -r as a real LF in the captured shell value.
assert_invalid_title "embedded newline in title" '[{"title":"Multi\nline title","body":"b","depends_on":[]},{"title":"second","body":"c","depends_on":[]}]'

# Unwritable --tmpdir: writability preflight must reject the directory BEFORE
# any redirect under $TMPDIR (`2>"$JQ_PARSE_ERR"`, `: > "$OUT"`) produces a raw
# bash "Permission denied" line that breaks the documented `ERROR=...` grammar
# (closes #687). Same bug class as #645 on `render-umbrella-body.sh`.
assert_unwritable_tmpdir "unwritable tmpdir"

# Valid 2-piece baseline: confirms the new guard doesn't regress the happy path.
assert_valid_baseline "valid 2-piece baseline"

echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
