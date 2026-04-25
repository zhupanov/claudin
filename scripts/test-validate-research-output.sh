#!/usr/bin/env bash
# test-validate-research-output.sh — Regression test for scripts/validate-research-output.sh.
#
# Cases (per the acceptance criteria in issue #416):
#   1. Happy path: substantive prose with one file:line citation → exit 0
#   2. Empty file → exit 2 (body thin)
#   3. Short-but-cited (50 words + citation) → exit 2 (body thin)
#   4. Long-but-uncited (250 words, no markers) → exit 3 (no marker)
#   5. Adversarial zero-citations (300 words, no markers) → exit 3
#   6. One file:line citation passes (250 words + path/file.go:7) → exit 0
#   7. One fenced code block with >= 1 line passes → exit 0
#   8. One URL passes → exit 0
#   9. --no-require-citations long-but-uncited → exit 0
#   10. --min-words 50 short-but-cited → exit 0
#   11. .pre-commit-config.yaml leading-dot file citation passes → exit 0
#   12. Makefile (extensionless) citation passes → exit 0
#   13. Empty fenced block (no content) does NOT count as a marker → exit 3
#   14. Fence interior excluded from word count (300 words inside ``` only) → exit 2
#   15. Missing file → exit 4
#
# Usage:
#   bash scripts/test-validate-research-output.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — first failure (message to stderr)

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/scripts/validate-research-output.sh"

if [[ ! -x "$HELPER" ]]; then
    echo "FAIL: $HELPER is not executable" >&2
    exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-validate-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

# Run helper, capture exit code and stdout. Args: <label> <expected_exit> [helper-args...] <file>
run_case() {
    local label="$1"; shift
    local expected_exit="$1"; shift
    local actual_exit actual_stdout
    actual_stdout=$("$HELPER" "$@" 2>&1)
    actual_exit=$?
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (exit $actual_exit)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected exit $expected_exit, got $actual_exit; stdout: ${actual_stdout:0:200})")
        echo "  FAIL: $label (expected exit $expected_exit, got $actual_exit)" >&2
        echo "        stdout: ${actual_stdout:0:200}" >&2
    fi
}

# Compose a fixture file with N space-separated word tokens.
make_words() {
    local n="$1" file="$2"
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "lorem%d ", i; printf "\n" }' > "$file"
}

# --- Case 1: happy path (250 words + file:line citation) ---
F1="$TMPROOT/case1-happy.txt"
make_words 250 "$F1"
echo 'See path/to/file.md:42 for context.' >> "$F1"
run_case "case 1: happy path (250 words + file:line)" 0 "$F1"

# --- Case 2: empty file ---
F2="$TMPROOT/case2-empty.txt"
: > "$F2"
run_case "case 2: empty file" 2 "$F2"

# --- Case 3: short-but-cited (50 words + citation) ---
F3="$TMPROOT/case3-short-cited.txt"
make_words 50 "$F3"
echo 'See path/to/file.md:42 for context.' >> "$F3"
run_case "case 3: short-but-cited" 2 "$F3"

# --- Case 4: long-but-uncited (250 words, no markers, --require-citations on) ---
F4="$TMPROOT/case4-long-uncited.txt"
make_words 250 "$F4"
run_case "case 4: long-but-uncited" 3 "$F4"

# --- Case 5: adversarial zero-citations (300 words, no markers) ---
F5="$TMPROOT/case5-adversarial.txt"
make_words 300 "$F5"
run_case "case 5: adversarial zero-citations" 3 "$F5"

# --- Case 6: one file:line citation passes (250 words + .go:7) ---
F6="$TMPROOT/case6-fileline.txt"
make_words 250 "$F6"
echo 'Citation: pkg/server/main.go:7' >> "$F6"
run_case "case 6: one file:line citation" 0 "$F6"

# --- Case 7: one fenced code block with >= 1 line passes ---
F7="$TMPROOT/case7-fence.txt"
make_words 250 "$F7"
{
    echo '```bash'
    echo 'echo hello'
    echo '```'
} >> "$F7"
run_case "case 7: one fenced code block (with content)" 0 "$F7"

# --- Case 8: one URL passes ---
F8="$TMPROOT/case8-url.txt"
make_words 250 "$F8"
echo 'See https://example.com/foo for details.' >> "$F8"
run_case "case 8: one URL" 0 "$F8"

# --- Case 9: --no-require-citations long-but-uncited passes ---
F9="$TMPROOT/case9-no-citations.txt"
make_words 250 "$F9"
run_case "case 9: --no-require-citations long-but-uncited" 0 --no-require-citations "$F9"

# --- Case 10: --min-words 50 short-but-cited passes ---
F10="$TMPROOT/case10-min-words.txt"
make_words 60 "$F10"
echo 'See path/to/file.md:42 for context.' >> "$F10"
run_case "case 10: --min-words 50 short-but-cited" 0 --min-words 50 "$F10"

# --- Case 11: .pre-commit-config.yaml leading-dot file citation passes ---
F11="$TMPROOT/case11-hidden-file.txt"
make_words 250 "$F11"
echo 'See .pre-commit-config.yaml:7 for the hook config.' >> "$F11"
run_case "case 11: leading-dot hidden file citation" 0 "$F11"

# --- Case 12: Makefile extensionless citation passes ---
F12="$TMPROOT/case12-makefile.txt"
make_words 250 "$F12"
echo 'See Makefile:14 for the test-harnesses target.' >> "$F12"
run_case "case 12: Makefile extensionless citation" 0 "$F12"

# --- Case 13: empty fenced block (no content lines) does NOT count ---
F13="$TMPROOT/case13-empty-fence.txt"
make_words 250 "$F13"
{
    echo '```'
    echo '```'
} >> "$F13"
run_case "case 13: empty fenced block does not count" 3 "$F13"

# --- Case 14: fence interior excluded from word count ---
# Wrap 300 words inside a fence; outside the fence is a 5-word header.
# Result: word count outside fence = 5 < 200, so exit 2.
F14="$TMPROOT/case14-fence-strips-body.txt"
{
    echo 'Header line with five words.'
    echo '```'
} > "$F14"
make_words 300 "$TMPROOT/case14-words.txt"
cat "$TMPROOT/case14-words.txt" >> "$F14"
echo '```' >> "$F14"
run_case "case 14: fence interior excluded from word count" 2 "$F14"

# --- Case 15: missing file ---
run_case "case 15: missing file" 4 "$TMPROOT/does-not-exist.txt"

# --- Case 16: usage error (no file argument) ---
run_case "case 16: no file argument" 1

# --- Case 17: unknown flag ---
run_case "case 17: unknown flag" 1 --bogus-flag "$F1"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
exit 0
