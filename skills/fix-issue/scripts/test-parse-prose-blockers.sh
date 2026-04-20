#!/usr/bin/env bash
# test-parse-prose-blockers.sh — Regression tests for parse-prose-blockers.sh.
#
# Exercises the conservative keyword set, case-insensitivity, emphasis-wrapper
# tolerance (the motivating #152-style formatting), word boundaries on the
# numeric side, and the full set of NON-match fixtures that enforce the
# "same-repo, no link targets, no cross-repo" parser scope. Wired into
# `make lint` via the `test-parse-prose-blockers` target; also referenced in
# `agent-lint.toml`'s exclude list (Makefile-only harness pattern).
#
# Run manually:
#   bash skills/fix-issue/scripts/test-parse-prose-blockers.sh
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SCRIPT_DIR/parse-prose-blockers.sh"

if [[ ! -x "$PARSER" ]]; then
    echo "ERROR: parser not found or not executable: $PARSER" >&2
    exit 1
fi

PASS_COUNT=0
FAIL_COUNT=0

# Run parser with a given input string; emit its stdout.
run_parser() {
    local input="$1"
    printf '%s' "$input" | "$PARSER"
}

# Assert that the parser output equals the expected value (literal comparison
# after joining output lines with spaces so fixtures read naturally).
assert_eq() {
    local label="$1" expected="$2" input="$3"
    local actual
    actual=$(run_parser "$input" | tr '\n' ' ' | sed 's/ *$//')
    if [[ "$expected" == "$actual" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label"
        echo "    input:    $(printf '%q' "$input")"
        echo "    expected: $(printf '%q' "$expected")"
        echo "    actual:   $(printf '%q' "$actual")"
        exit 1
    fi
}

# Assert empty stdout + exit 0 (the fail-open / no-match contract).
assert_empty() {
    local label="$1" input="$2"
    local actual exit_code
    actual=$(run_parser "$input")
    exit_code=$?
    if [[ -z "$actual" && $exit_code -eq 0 ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label"
        echo "    input:    $(printf '%q' "$input")"
        echo "    expected: empty stdout, exit 0"
        echo "    actual:   $(printf '%q' "$actual"), exit $exit_code"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Matching cases — the five keyword phrases must be recognized.
# ---------------------------------------------------------------------------
echo "Matching cases: keyword variants"
assert_eq "Depends on #N"         "150" "Depends on #150"
assert_eq "Blocked by #N"         "150" "Blocked by #150"
assert_eq "Blocked on #N"         "150" "Blocked on #150"
assert_eq "Requires #N"           "150" "Requires #150"
assert_eq "Needs #N"              "150" "Needs #150"

echo "Matching cases: case-insensitive"
assert_eq "DEPENDS ON (uppercase)" "150" "DEPENDS ON #150"
assert_eq "depends on (lowercase)" "150" "depends on #150"
assert_eq "Depends On (title)"     "150" "Depends On #150"
assert_eq "BLOCKED BY (uppercase)" "150" "BLOCKED BY #150"

echo "Matching cases: emphasis wrappers (motivating #152-style formatting)"
# Issue #152's body uses: "Depends on **#150 (bypass fix) only**"
# This test pins the exact motivating case.
assert_eq "bold wrapper around number (#152 motivating case)" "150" \
    "Depends on **#150 (bypass fix) only**."
assert_eq "double-asterisk wrapper"  "150" "Depends on **#150**"
assert_eq "single-asterisk wrapper"  "150" "Depends on *#150*"
assert_eq "underscore wrapper"       "150" "Depends on _#150_"
assert_eq "double-underscore wrap"   "150" "Depends on __#150__"

echo "Matching cases: keyword wrapped with emphasis"
# Keyword-wrapping is handled naturally: whitespace still sits between the
# closing `**` and the `#N`, so the post-strip text matches.
assert_eq "keyword bold-wrapped"     "150" "**Depends on** #150"
assert_eq "keyword underscore-wrap"  "150" "_Depends on_ #150"

echo "Matching cases: multiple references"
assert_eq "two keywords on same line"           "150 151" \
    "Depends on #150 and Blocked by #151"
assert_eq "three keywords across lines"         "100 200 300" \
    $'Depends on #100\nBlocked by #200\nRequires #300'
assert_eq "duplicate reference deduplicated"    "150" \
    "Depends on #150 and also Blocked by #150"
assert_eq "numeric sort (not lexicographic)"    "7 42 150" \
    "Depends on #150, Blocked by #42, Needs #7"

echo "Matching cases: numeric boundaries"
# Greedy [0-9]+ must match all digits; #12 must not be extracted from #1234.
assert_eq "long issue number"        "12345" "Depends on #12345"
assert_eq "trailing punctuation"     "150"   "Depends on #150."
assert_eq "trailing paren"           "150"   "Depends on #150 (fix)"

# ---------------------------------------------------------------------------
# NON-matching cases — enforce parser scope boundaries.
# ---------------------------------------------------------------------------
echo "NON-matching cases: missing keyword"
assert_empty "bare #N with no keyword"              "See #150 for details"
assert_empty "narrative 'issue #N'"                 "This is similar to issue #150"
assert_empty "fixes (commit-close keyword)"         "Fixes #150"
assert_empty "closes (commit-close keyword)"        "Closes #150"
assert_empty "resolves (commit-close keyword)"      "Resolves #150"

echo "NON-matching cases: link-target forms (same-repo invariant)"
# Link brackets `[` are preserved during normalization so link-target forms
# remain NON-matches. The parser cannot tell whether a link target points at
# the current repo, so we reject link-target references at parser scope.
assert_empty "number wrapped in link brackets"      "Depends on [#150](https://example.com/issue/150)"

echo "Matching cases: link-text containing full 'keyword + #N' pattern"
# When the author writes `[Depends on #150](url)`, the link *text* contains
# the full "Depends on #150" pattern. The regex operates on plain text and
# matches this — which is correct: the author is declaring a same-repo
# dependency in the displayed text regardless of the link URL. This pins
# that behavior so a future regex tweak cannot accidentally suppress it.
assert_eq "keyword+#N inside link text"             "150" \
    "See [Depends on #150](https://example.com/foo)"

echo "NON-matching cases: cross-repo references"
assert_empty "owner/repo#N shorthand"               "Depends on owner/repo#150"
assert_empty "owner/repo between keyword and #"     "Blocked by some-org/some-repo#42"

echo "NON-matching cases: URL forms"
assert_empty "full GitHub URL"                      "Depends on https://github.com/owner/repo/issues/150"
assert_empty "URL with anchor"                      "Blocked by https://github.com/owner/repo/pull/168#pullrequestreview-42"

echo "NON-matching cases: missing whitespace / strict-spacing"
# The [[:space:]]+ boundary is strict; no-space typos silently do not match.
# This is an accepted false-negative mode per Known Limitations.
assert_empty "no space between keyword and #"       "Depends on#150"
assert_empty "no space (other keyword)"             "Blocked by#150"

echo "NON-matching cases: empty / whitespace-only input"
assert_empty "empty input"                          ""
assert_empty "single newline"                       $'\n'
assert_empty "whitespace-only input"                "   \t\n  "

echo "NON-matching cases: structural false-positive guards"
# "#" without digits must not produce spurious output.
assert_empty "keyword followed by # with no digits" "Depends on # and other text"
assert_empty "keyword followed by only text"        "Depends on the previous implementation"

# ---------------------------------------------------------------------------
# Robustness cases — exotic inputs that must not crash.
# ---------------------------------------------------------------------------
echo "Robustness cases"
# Unicode characters should pass through without crashing the shell pipeline.
assert_eq "unicode preamble before keyword"         "150" "日本語 Depends on #150"
# Very long line should not hang or crash.
long_text=""
for i in {1..50}; do long_text+="filler text $i word "; done
long_text+="Depends on #150"
assert_eq "long line with keyword at end"           "150" "$long_text"

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo ""
echo "PASSED: $PASS_COUNT"
echo "FAILED: $FAIL_COUNT"

if [ "$FAIL_COUNT" -gt 0 ]; then
    exit 1
fi
exit 0
