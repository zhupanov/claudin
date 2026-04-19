#!/usr/bin/env bash
# test-parse-input.sh — Regression tests for parse-input.sh.
#
# Covers the two Issue #129 bugs (OOS subheading absorption, generic body
# with OOS-shaped bullets), the Issue #131 bug (OOS `- **Description**:` with
# empty inline value), the Issue #132 bug (nested `### OOS_N:` inside a
# generic body should be absorbed, not flushed), and baseline and boundary
# cases including the #132-review-surfaced bodyless-generic + nested-OOS edge
# case. Wired into `make lint` via the `test-parse-input` target so the harness
# runs in CI on every PR; shellcheck (via pre-commit) lints this file
# automatically. Run manually:
#
#   bash skills/issue/scripts/test-parse-input.sh
#
# Exits 0 on success, 1 on the first failed assertion.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PARSER="$SCRIPT_DIR/parse-input.sh"

if [[ ! -f "$PARSER" ]]; then
    echo "ERROR: parser not found: $PARSER" >&2
    exit 1
fi

TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Portable base64 decode. GNU uses `-d`, BSD/macOS uses `-D`.
b64_decode() {
    if base64 -d </dev/null >/dev/null 2>&1; then
        base64 -d
    else
        base64 -D
    fi
}

PASS_COUNT=0
FAIL_COUNT=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label"
        echo "    expected: $(printf '%q' "$expected")"
        echo "    actual:   $(printf '%q' "$actual")"
        exit 1
    fi
}

assert_absent() {
    local label="$1" key="$2" output="$3"
    if grep -q "^${key}=" <<< "$output"; then
        FAIL_COUNT=$((FAIL_COUNT + 1))
        echo "  FAIL: $label"
        echo "    expected key absent: $key"
        echo "    actual line:         $(grep "^${key}=" <<< "$output")"
        exit 1
    else
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    fi
}

# Extract a key's value from the parser output. Returns the value string.
get_value() {
    local key="$1" output="$2"
    grep "^${key}=" <<< "$output" | head -1 | sed "s/^${key}=//"
}

# Decode ITEM_N_BODY from the parser output and echo the plaintext.
get_body() {
    local n="$1" output="$2"
    get_value "ITEM_${n}_BODY" "$output" | b64_decode
}

run_parser() {
    local input_file="$1"
    bash "$PARSER" --input-file "$input_file"
}

# ---------------------------------------------------------------------------
# Test case 1 — Bug (a): OOS item with `### Notes` subheading in Description
# ---------------------------------------------------------------------------
echo "Case 1: OOS item with ### subheading in Description"
cat > "$TMPDIR_TEST/case1.md" <<'EOF'
### OOS_1: Example bug
- **Description**: First description paragraph.
### Notes
Second paragraph after the subheading.
- **Reviewer**: Codex
- **Vote tally**: YES=3, NO=0
- **Phase**: review
EOF
out1=$(run_parser "$TMPDIR_TEST/case1.md")
assert_eq "case 1 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out1")"
assert_eq "case 1 title" "Example bug" "$(get_value ITEM_1_TITLE "$out1")"
assert_eq "case 1 reviewer" "Codex" "$(get_value ITEM_1_REVIEWER "$out1")"
assert_eq "case 1 vote_tally" "YES=3, NO=0" "$(get_value ITEM_1_VOTE_TALLY "$out1")"
assert_eq "case 1 phase" "review" "$(get_value ITEM_1_PHASE "$out1")"
expected1=$'First description paragraph.\n### Notes\nSecond paragraph after the subheading.'
assert_eq "case 1 body absorbs subheading" "$expected1" "$(get_body 1 "$out1")"

# ---------------------------------------------------------------------------
# Test case 2 — Bug (b) comprehensive: generic body with ALL 4 OOS-shaped bullets
# Includes preceding text + stray `- **Description**:` — the most destructive
# variant because the Description branch overwrites CURRENT_BODY.
# ---------------------------------------------------------------------------
echo "Case 2: generic item body contains OOS-shaped bullets (incl. Description)"
cat > "$TMPDIR_TEST/case2.md" <<'EOF'
### Regular issue title
This is preceding body text that must survive.
- **Description**: stray description bullet that should stay in body
- **Reviewer**: stray reviewer bullet
- **Vote tally**: stray tally bullet
- **Phase**: stray phase bullet
Trailing body text after bullets.
EOF
out2=$(run_parser "$TMPDIR_TEST/case2.md")
assert_eq "case 2 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out2")"
assert_eq "case 2 title" "Regular issue title" "$(get_value ITEM_1_TITLE "$out2")"
expected2=$'This is preceding body text that must survive.\n- **Description**: stray description bullet that should stay in body\n- **Reviewer**: stray reviewer bullet\n- **Vote tally**: stray tally bullet\n- **Phase**: stray phase bullet\nTrailing body text after bullets.'
assert_eq "case 2 body preserves all OOS-shaped bullets + text" "$expected2" "$(get_body 1 "$out2")"
assert_absent "case 2 no ITEM_1_REVIEWER" "ITEM_1_REVIEWER" "$out2"
assert_absent "case 2 no ITEM_1_VOTE_TALLY" "ITEM_1_VOTE_TALLY" "$out2"
assert_absent "case 2 no ITEM_1_PHASE" "ITEM_1_PHASE" "$out2"

# ---------------------------------------------------------------------------
# Test case 3 — Baseline: well-formed OOS item with all 4 fields
# ---------------------------------------------------------------------------
echo "Case 3: well-formed OOS baseline"
cat > "$TMPDIR_TEST/case3.md" <<'EOF'
### OOS_1: Plain OOS item
- **Description**: Simple description.
- **Reviewer**: Code
- **Vote tally**: YES=2, NO=1
- **Phase**: design
EOF
out3=$(run_parser "$TMPDIR_TEST/case3.md")
assert_eq "case 3 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out3")"
assert_eq "case 3 title" "Plain OOS item" "$(get_value ITEM_1_TITLE "$out3")"
assert_eq "case 3 reviewer" "Code" "$(get_value ITEM_1_REVIEWER "$out3")"
assert_eq "case 3 vote tally" "YES=2, NO=1" "$(get_value ITEM_1_VOTE_TALLY "$out3")"
assert_eq "case 3 phase" "design" "$(get_value ITEM_1_PHASE "$out3")"
assert_eq "case 3 body" "Simple description." "$(get_body 1 "$out3")"

# ---------------------------------------------------------------------------
# Test case 4 — Baseline: well-formed generic item
# ---------------------------------------------------------------------------
echo "Case 4: well-formed generic baseline"
cat > "$TMPDIR_TEST/case4.md" <<'EOF'
### Just a generic item
Body paragraph one.

Body paragraph two after blank line.
EOF
out4=$(run_parser "$TMPDIR_TEST/case4.md")
assert_eq "case 4 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out4")"
assert_eq "case 4 title" "Just a generic item" "$(get_value ITEM_1_TITLE "$out4")"
expected4=$'Body paragraph one.\n\nBody paragraph two after blank line.'
assert_eq "case 4 body preserves blank line" "$expected4" "$(get_body 1 "$out4")"
assert_absent "case 4 no ITEM_1_REVIEWER" "ITEM_1_REVIEWER" "$out4"
assert_absent "case 4 no ITEM_1_VOTE_TALLY" "ITEM_1_VOTE_TALLY" "$out4"
assert_absent "case 4 no ITEM_1_PHASE" "ITEM_1_PHASE" "$out4"

# ---------------------------------------------------------------------------
# Test case 5 — Mixed: complete OOS item followed by generic item.
# The OOS structured fields close the body (IN_BODY=false), so the next
# `###` correctly starts a new item.
# ---------------------------------------------------------------------------
echo "Case 5: complete OOS followed by generic item"
cat > "$TMPDIR_TEST/case5.md" <<'EOF'
### OOS_1: First OOS
- **Description**: OOS description.
- **Reviewer**: Cursor
- **Vote tally**: YES=3
- **Phase**: review
### Second generic item
Generic body text.
EOF
out5=$(run_parser "$TMPDIR_TEST/case5.md")
assert_eq "case 5 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out5")"
assert_eq "case 5 item 1 title" "First OOS" "$(get_value ITEM_1_TITLE "$out5")"
assert_eq "case 5 item 1 reviewer" "Cursor" "$(get_value ITEM_1_REVIEWER "$out5")"
assert_eq "case 5 item 1 body" "OOS description." "$(get_body 1 "$out5")"
assert_eq "case 5 item 2 title" "Second generic item" "$(get_value ITEM_2_TITLE "$out5")"
assert_eq "case 5 item 2 body" "Generic body text." "$(get_body 2 "$out5")"
assert_absent "case 5 item 2 has no reviewer" "ITEM_2_REVIEWER" "$out5"

# ---------------------------------------------------------------------------
# Test case 6 — Issue #138: incomplete OOS (Description only, no trailing
# structured fields) followed by a `### <title>` line and a generic body at
# EOF. The pending-heading state defers the absorb decision; when EOF arrives
# without any structured field (Reviewer / Vote tally / Phase) closing the
# OOS, the current OOS is flushed as MALFORMED (with its non-empty body) and
# the pending heading + pending body are emitted as a new generic item. This
# preserves the author's intended second item instead of silently swallowing
# it into the OOS body (the pre-#138 behavior).
# ---------------------------------------------------------------------------
echo "Case 6: incomplete OOS splits cleanly at EOF (issue #138 fix)"
cat > "$TMPDIR_TEST/case6.md" <<'EOF'
### OOS_1: Incomplete OOS
- **Description**: Short description with no trailing fields.
### Would-be generic item
Would-be body.
EOF
out6=$(run_parser "$TMPDIR_TEST/case6.md")
assert_eq "case 6 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out6")"
assert_eq "case 6 item 1 title" "Incomplete OOS" "$(get_value ITEM_1_TITLE "$out6")"
assert_eq "case 6 item 1 malformed" "true" "$(get_value ITEM_1_MALFORMED "$out6")"
assert_eq "case 6 item 1 body preserves description" "Short description with no trailing fields." "$(get_body 1 "$out6")"
assert_eq "case 6 item 2 title" "Would-be generic item" "$(get_value ITEM_2_TITLE "$out6")"
assert_eq "case 6 item 2 body" "Would-be body." "$(get_body 2 "$out6")"
assert_absent "case 6 item 2 has no reviewer" "ITEM_2_REVIEWER" "$out6"
assert_absent "case 6 item 2 has no vote tally" "ITEM_2_VOTE_TALLY" "$out6"
assert_absent "case 6 item 2 has no phase" "ITEM_2_PHASE" "$out6"
assert_absent "case 6 item 2 not malformed" "ITEM_2_MALFORMED" "$out6"

# ---------------------------------------------------------------------------
# Test case 7 — Back-to-back generic items. Tests that flush_item correctly
# resets CURRENT_MODE so the second item is parsed cleanly.
# ---------------------------------------------------------------------------
echo "Case 7: back-to-back generic items"
cat > "$TMPDIR_TEST/case7.md" <<'EOF'
### First generic
Body of first.
### Second generic
Body of second.
EOF
out7=$(run_parser "$TMPDIR_TEST/case7.md")
assert_eq "case 7 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out7")"
assert_eq "case 7 item 1 title" "First generic" "$(get_value ITEM_1_TITLE "$out7")"
assert_eq "case 7 item 1 body" "Body of first." "$(get_body 1 "$out7")"
assert_eq "case 7 item 2 title" "Second generic" "$(get_value ITEM_2_TITLE "$out7")"
assert_eq "case 7 item 2 body" "Body of second." "$(get_body 2 "$out7")"
assert_absent "case 7 item 1 no reviewer" "ITEM_1_REVIEWER" "$out7"
assert_absent "case 7 item 2 no reviewer" "ITEM_2_REVIEWER" "$out7"

# ---------------------------------------------------------------------------
# Test case 8 — Back-to-back complete OOS items (primary /implement Step 9a.1
# production shape). Sanity check that flush_item correctly resets CURRENT_MODE
# and per-item OOS fields between sequential OOS items.
# ---------------------------------------------------------------------------
echo "Case 8: back-to-back complete OOS items"
cat > "$TMPDIR_TEST/case8.md" <<'EOF'
### OOS_1: First OOS item
- **Description**: Body of first OOS.
- **Reviewer**: Codex
- **Vote tally**: YES=3, NO=0
- **Phase**: review
### OOS_2: Second OOS item
- **Description**: Body of second OOS.
- **Reviewer**: Cursor
- **Vote tally**: YES=2, NO=1
- **Phase**: design
EOF
out8=$(run_parser "$TMPDIR_TEST/case8.md")
assert_eq "case 8 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out8")"
assert_eq "case 8 item 1 title" "First OOS item" "$(get_value ITEM_1_TITLE "$out8")"
assert_eq "case 8 item 1 body" "Body of first OOS." "$(get_body 1 "$out8")"
assert_eq "case 8 item 1 reviewer" "Codex" "$(get_value ITEM_1_REVIEWER "$out8")"
assert_eq "case 8 item 1 vote tally" "YES=3, NO=0" "$(get_value ITEM_1_VOTE_TALLY "$out8")"
assert_eq "case 8 item 1 phase" "review" "$(get_value ITEM_1_PHASE "$out8")"
assert_eq "case 8 item 2 title" "Second OOS item" "$(get_value ITEM_2_TITLE "$out8")"
assert_eq "case 8 item 2 body" "Body of second OOS." "$(get_body 2 "$out8")"
assert_eq "case 8 item 2 reviewer" "Cursor" "$(get_value ITEM_2_REVIEWER "$out8")"
assert_eq "case 8 item 2 vote tally" "YES=2, NO=1" "$(get_value ITEM_2_VOTE_TALLY "$out8")"
assert_eq "case 8 item 2 phase" "design" "$(get_value ITEM_2_PHASE "$out8")"

# ---------------------------------------------------------------------------
# Test case 9 — Issue #131: OOS item where `- **Description**:` has no inline
# value and the body is supplied entirely by continuation lines. Before the
# fix, the `[[:space:]]+(.+)$` regex required non-empty inline content, so
# the Description bullet did not match, IN_BODY stayed false, and all
# continuation lines were silently dropped. With `[[:space:]]*(.*)$` the
# empty inline value matches, IN_BODY flips to true, and continuations are
# captured by the fallback branch.
# ---------------------------------------------------------------------------
echo "Case 9: OOS item with empty inline Description, body from continuations"
cat > "$TMPDIR_TEST/case9.md" <<'EOF'
### OOS_1: Description body from continuations only
- **Description**:
  First continuation line.

  Third line after blank.
- **Reviewer**: Code
- **Vote tally**: YES=3, NO=0
- **Phase**: design
EOF
out9=$(run_parser "$TMPDIR_TEST/case9.md")
assert_eq "case 9 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out9")"
assert_eq "case 9 title" "Description body from continuations only" "$(get_value ITEM_1_TITLE "$out9")"
assert_eq "case 9 reviewer" "Code" "$(get_value ITEM_1_REVIEWER "$out9")"
assert_eq "case 9 vote tally" "YES=3, NO=0" "$(get_value ITEM_1_VOTE_TALLY "$out9")"
assert_eq "case 9 phase" "design" "$(get_value ITEM_1_PHASE "$out9")"
expected9=$'  First continuation line.\n\n  Third line after blank.'
assert_eq "case 9 body captures multi-line continuation" "$expected9" "$(get_body 1 "$out9")"
assert_absent "case 9 not MALFORMED" "ITEM_1_MALFORMED" "$out9"

# ---------------------------------------------------------------------------
# Test case 10 — Issue #132: generic item whose body contains `### OOS_N: ...`
# as literal prose. The OOS heading branch must honor the same mode-guard as
# the plain `### <title>` branch — inside an active generic body, absorb the
# line as body continuation rather than flushing and starting a new OOS item.
# ---------------------------------------------------------------------------
echo "Case 10: generic body contains literal ### OOS_N: ... prose (issue #132)"
cat > "$TMPDIR_TEST/case10.md" <<'EOF'
### Regular issue with nested OOS-shaped heading
Preceding body text.
### OOS_42: nested example
Trailing body text after the nested heading.
EOF
out10=$(run_parser "$TMPDIR_TEST/case10.md")
assert_eq "case 10 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out10")"
assert_eq "case 10 title" "Regular issue with nested OOS-shaped heading" "$(get_value ITEM_1_TITLE "$out10")"
expected10=$'Preceding body text.\n### OOS_42: nested example\nTrailing body text after the nested heading.'
assert_eq "case 10 body absorbs nested OOS_N heading" "$expected10" "$(get_body 1 "$out10")"
assert_absent "case 10 no ITEM_2_TITLE" "ITEM_2_TITLE" "$out10"
assert_absent "case 10 no ITEM_1_REVIEWER" "ITEM_1_REVIEWER" "$out10"
assert_absent "case 10 no ITEM_1_VOTE_TALLY" "ITEM_1_VOTE_TALLY" "$out10"
assert_absent "case 10 no ITEM_1_PHASE" "ITEM_1_PHASE" "$out10"

# ---------------------------------------------------------------------------
# Test case 11 — Edge case surfaced during #132 review: a generic title with
# NO body lines, immediately followed by `### OOS_N: ...`. The generic branch
# sets IN_BODY=true eagerly (before any body content), so a naive mode-guard
# would absorb the OOS line into the still-empty generic body. The refined
# guard requires CURRENT_BODY non-empty, so this degenerate input flushes the
# malformed generic item and lets the OOS line start a new OOS item —
# matching pre-#132 behavior for this shape and keeping the #132 absorb path
# symmetric with the OOS→generic direction (where IN_BODY=true always
# implies non-empty CURRENT_BODY via the Description field).
# ---------------------------------------------------------------------------
echo "Case 11: generic title with no body, immediately followed by ### OOS_N:"
cat > "$TMPDIR_TEST/case11.md" <<'EOF'
### Bodyless generic title
### OOS_1: Real OOS item
- **Description**: Real OOS description.
- **Reviewer**: Codex
- **Vote tally**: YES=3
- **Phase**: review
EOF
out11=$(run_parser "$TMPDIR_TEST/case11.md")
assert_eq "case 11 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out11")"
assert_eq "case 11 item 1 title" "Bodyless generic title" "$(get_value ITEM_1_TITLE "$out11")"
assert_eq "case 11 item 1 malformed" "true" "$(get_value ITEM_1_MALFORMED "$out11")"
assert_eq "case 11 item 2 title" "Real OOS item" "$(get_value ITEM_2_TITLE "$out11")"
assert_eq "case 11 item 2 body" "Real OOS description." "$(get_body 2 "$out11")"
assert_eq "case 11 item 2 reviewer" "Codex" "$(get_value ITEM_2_REVIEWER "$out11")"
assert_eq "case 11 item 2 vote tally" "YES=3" "$(get_value ITEM_2_VOTE_TALLY "$out11")"
assert_eq "case 11 item 2 phase" "review" "$(get_value ITEM_2_PHASE "$out11")"

# ---------------------------------------------------------------------------
# Test case 12 — Edge case surfaced during #132 review round 5: a generic
# title followed ONLY by whitespace-only continuation lines, then `### OOS_N:`.
# The absorb guard requires at least one non-whitespace character in
# CURRENT_BODY, so whitespace-only prefixes do not qualify as "meaningful
# body." The guard fails and the OOS line starts a real OOS item via the
# else branch — matching pre-#132 behavior for this degenerate input shape.
# Note: ITEM_1 is NOT flagged MALFORMED — `emit_item` uses the stricter
# `[[ -z "$body" ]]` predicate, so a whitespace-only body is emitted as a
# normal item with a whitespace-only body. The asymmetry is deliberate: the
# absorb rule wants "meaningful content" while the MALFORMED rule only
# rejects truly-empty titles-without-bodies (mirrors case 11's missing-body
# shape). Case 12 therefore asserts the two-item split but explicitly
# locks in ITEM_1 being emitted (with whitespace body, no MALFORMED flag).
# ---------------------------------------------------------------------------
echo "Case 12: generic title with only whitespace body, then ### OOS_N:"
# Use printf to ensure the middle line contains only spaces without the
# HEREDOC truncating trailing whitespace.
printf '### Whitespace-only body generic\n   \n### OOS_1: Real OOS item\n- **Description**: Real OOS description.\n- **Reviewer**: Cursor\n- **Vote tally**: YES=2\n- **Phase**: design\n' > "$TMPDIR_TEST/case12.md"
out12=$(run_parser "$TMPDIR_TEST/case12.md")
assert_eq "case 12 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out12")"
assert_eq "case 12 item 1 title" "Whitespace-only body generic" "$(get_value ITEM_1_TITLE "$out12")"
assert_absent "case 12 item 1 not malformed" "ITEM_1_MALFORMED" "$out12"
assert_eq "case 12 item 1 body is whitespace" "   " "$(get_body 1 "$out12")"
assert_eq "case 12 item 2 title" "Real OOS item" "$(get_value ITEM_2_TITLE "$out12")"
assert_eq "case 12 item 2 body" "Real OOS description." "$(get_body 2 "$out12")"
assert_eq "case 12 item 2 reviewer" "Cursor" "$(get_value ITEM_2_REVIEWER "$out12")"
assert_eq "case 12 item 2 vote tally" "YES=2" "$(get_value ITEM_2_VOTE_TALLY "$out12")"
assert_eq "case 12 item 2 phase" "design" "$(get_value ITEM_2_PHASE "$out12")"

# ---------------------------------------------------------------------------
# Test case 13 — Issue #138 regression lock + multi-subheading support:
# OOS with two sequential `### <subheading>` lines inside its Description,
# then a full structured-field close. Under the pending-heading scheme, the
# first `### Subheading 1` starts pending state; `Para 2.` accumulates into
# PENDING_BODY; `### Subheading 2` arrives while pending-active → it appends
# to PENDING_BODY (does NOT trigger rule-2 resolution — only `### OOS_N:` or
# EOF trigger that). `Para 3.` accumulates too. When `- **Reviewer**:` fires,
# rule-1 fold-back merges PENDING_HEADING + PENDING_BODY back into
# CURRENT_BODY before the field assignment. Locks in both (a) the #129
# subheading-absorption fix and (b) multi-subheading accumulation.
# ---------------------------------------------------------------------------
echo "Case 13: OOS with multiple subheadings before structured close (issue #138)"
cat > "$TMPDIR_TEST/case13.md" <<'EOF'
### OOS_1: Example with multiple subheadings
- **Description**: Para 1.
### Subheading 1
Para 2.
### Subheading 2
Para 3.
- **Reviewer**: Codex
- **Vote tally**: YES=3, NO=0
- **Phase**: review
EOF
out13=$(run_parser "$TMPDIR_TEST/case13.md")
assert_eq "case 13 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out13")"
assert_eq "case 13 title" "Example with multiple subheadings" "$(get_value ITEM_1_TITLE "$out13")"
expected13=$'Para 1.\n### Subheading 1\nPara 2.\n### Subheading 2\nPara 3.'
assert_eq "case 13 body absorbs both subheadings and all paragraphs" "$expected13" "$(get_body 1 "$out13")"
assert_eq "case 13 reviewer" "Codex" "$(get_value ITEM_1_REVIEWER "$out13")"
assert_eq "case 13 vote tally" "YES=3, NO=0" "$(get_value ITEM_1_VOTE_TALLY "$out13")"
assert_eq "case 13 phase" "review" "$(get_value ITEM_1_PHASE "$out13")"
assert_absent "case 13 not malformed" "ITEM_1_MALFORMED" "$out13"

# ---------------------------------------------------------------------------
# Test case 14 — Issue #138 EOF resolution: incomplete OOS + ambiguous heading
# + body at EOF with no trailing structured field. Similar to case 6 but
# checks the EOF resolution path in isolation (no following OOS_N: to force
# resolution; only EOF). The pending-heading and pending-body both populate;
# EOF in flush_item emits current OOS as MALFORMED (with its non-empty body)
# then emits pending pair as a new generic item.
# ---------------------------------------------------------------------------
echo "Case 14: incomplete OOS at EOF with pending body (issue #138 EOF path)"
cat > "$TMPDIR_TEST/case14.md" <<'EOF'
### OOS_1: Incomplete OOS at EOF
- **Description**: Only a description.
### Notes with no closing fields
Some body text.
EOF
out14=$(run_parser "$TMPDIR_TEST/case14.md")
assert_eq "case 14 items total" "ITEMS_TOTAL=2" "$(grep '^ITEMS_TOTAL=' <<< "$out14")"
assert_eq "case 14 item 1 title" "Incomplete OOS at EOF" "$(get_value ITEM_1_TITLE "$out14")"
assert_eq "case 14 item 1 malformed" "true" "$(get_value ITEM_1_MALFORMED "$out14")"
assert_eq "case 14 item 1 body" "Only a description." "$(get_body 1 "$out14")"
assert_eq "case 14 item 2 title" "Notes with no closing fields" "$(get_value ITEM_2_TITLE "$out14")"
assert_eq "case 14 item 2 body" "Some body text." "$(get_body 2 "$out14")"
assert_absent "case 14 item 2 has no reviewer" "ITEM_2_REVIEWER" "$out14"
assert_absent "case 14 item 2 has no vote tally" "ITEM_2_VOTE_TALLY" "$out14"
assert_absent "case 14 item 2 has no phase" "ITEM_2_PHASE" "$out14"
assert_absent "case 14 item 2 not malformed" "ITEM_2_MALFORMED" "$out14"

# ---------------------------------------------------------------------------
# Test case 15 — Issue #138 mid-stream OOS_N resolution: incomplete OOS +
# ambiguous heading + pending body + a new `### OOS_N:` heading + its full
# structured-field tail. The `### OOS_2:` line arrives while pending-active
# → rule-2 split fires in the OOS heading branch preamble: flush current
# OOS_1 as MALFORMED, emit pending pair as generic, then process
# `### OOS_2:` normally as a new OOS item. Result: three items total —
# OOS_1 (MALFORMED), a generic item from the pending pair, and a well-formed
# OOS_2.
# ---------------------------------------------------------------------------
echo "Case 15: incomplete OOS + pending generic + next OOS_N (issue #138 mid-stream)"
cat > "$TMPDIR_TEST/case15.md" <<'EOF'
### OOS_1: Incomplete first OOS
- **Description**: Only a description.
### Notes pending
Some pending body.
### OOS_2: Well-formed second OOS
- **Description**: Second body.
- **Reviewer**: Cursor
- **Vote tally**: YES=2
- **Phase**: design
EOF
out15=$(run_parser "$TMPDIR_TEST/case15.md")
assert_eq "case 15 items total" "ITEMS_TOTAL=3" "$(grep '^ITEMS_TOTAL=' <<< "$out15")"
assert_eq "case 15 item 1 title" "Incomplete first OOS" "$(get_value ITEM_1_TITLE "$out15")"
assert_eq "case 15 item 1 malformed" "true" "$(get_value ITEM_1_MALFORMED "$out15")"
assert_eq "case 15 item 1 body" "Only a description." "$(get_body 1 "$out15")"
assert_eq "case 15 item 2 title" "Notes pending" "$(get_value ITEM_2_TITLE "$out15")"
assert_eq "case 15 item 2 body" "Some pending body." "$(get_body 2 "$out15")"
assert_absent "case 15 item 2 has no reviewer" "ITEM_2_REVIEWER" "$out15"
assert_absent "case 15 item 2 not malformed" "ITEM_2_MALFORMED" "$out15"
assert_eq "case 15 item 3 title" "Well-formed second OOS" "$(get_value ITEM_3_TITLE "$out15")"
assert_eq "case 15 item 3 body" "Second body." "$(get_body 3 "$out15")"
assert_eq "case 15 item 3 reviewer" "Cursor" "$(get_value ITEM_3_REVIEWER "$out15")"
assert_eq "case 15 item 3 vote tally" "YES=2" "$(get_value ITEM_3_VOTE_TALLY "$out15")"
assert_eq "case 15 item 3 phase" "design" "$(get_value ITEM_3_PHASE "$out15")"
assert_absent "case 15 item 3 not malformed" "ITEM_3_MALFORMED" "$out15"

# ---------------------------------------------------------------------------
echo ""
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
