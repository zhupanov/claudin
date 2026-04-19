#!/usr/bin/env bash
# test-parse-input.sh — Regression tests for parse-input.sh.
#
# Covers the two Issue #129 bugs (OOS subheading absorption, generic body
# with OOS-shaped bullets) plus baseline and boundary cases. Not wired into
# any automated test runner; shellcheck (via pre-commit) lints this file
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
# Test case 6 — Documented absorb behavior: incomplete OOS (Description only,
# no trailing structured fields) followed by a `### ` line. Per design, the
# trailing `### ` is absorbed as body continuation because IN_BODY=true and
# CURRENT_MODE=oos. This is a known limitation of the incomplete-OOS shape
# and is documented in the parser header.
# ---------------------------------------------------------------------------
echo "Case 6: incomplete OOS absorbs following ### line (documented behavior)"
cat > "$TMPDIR_TEST/case6.md" <<'EOF'
### OOS_1: Incomplete OOS
- **Description**: Short description with no trailing fields.
### Would-be generic item
Would-be body.
EOF
out6=$(run_parser "$TMPDIR_TEST/case6.md")
assert_eq "case 6 items total" "ITEMS_TOTAL=1" "$(grep '^ITEMS_TOTAL=' <<< "$out6")"
assert_eq "case 6 title" "Incomplete OOS" "$(get_value ITEM_1_TITLE "$out6")"
expected6=$'Short description with no trailing fields.\n### Would-be generic item\nWould-be body.'
assert_eq "case 6 body absorbs the would-be-generic heading + body" "$expected6" "$(get_body 1 "$out6")"

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
echo ""
echo "Summary: $PASS_COUNT passed, $FAIL_COUNT failed"
if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi
exit 0
