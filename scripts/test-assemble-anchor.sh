#!/usr/bin/env bash
# test-assemble-anchor.sh — regression harness for scripts/assemble-anchor.sh.
#
# Covers:
#   (a) Empty sections directory → 8 empty marker pairs + first-line marker.
#   (b) Partial fragments → populated where present, empty pairs elsewhere,
#       in SECTION_MARKERS order.
#   (c) Full fragments → all 8 slugs populated.
#   (d) Missing anchor-section-markers.sh helper → FAILED=true / ERROR=missing
#       helper + exit 1.
#   (e) Invalid --issue value (non-integer) → usage error, exit 1.
#   (f) First line of output is always the HTML anchor marker.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ASSEMBLE_ANCHOR="$SCRIPT_DIR/assemble-anchor.sh"
MARKERS_HELPER="$SCRIPT_DIR/anchor-section-markers.sh"

if [ ! -x "$ASSEMBLE_ANCHOR" ]; then
    echo "FAIL: $ASSEMBLE_ANCHOR not executable" >&2
    exit 1
fi

if [ ! -f "$MARKERS_HELPER" ]; then
    echo "FAIL: $MARKERS_HELPER not found (needed for canonical order reference)" >&2
    exit 1
fi

# shellcheck source=scripts/anchor-section-markers.sh
# shellcheck disable=SC1091
source "$MARKERS_HELPER"

tmpdir="$(mktemp -d -t assemble-anchor-test-XXXXXX)"
trap 'rm -rf "$tmpdir"' EXIT

fail() {
    echo "FAIL: $1" >&2
    exit 1
}

pass_count=0
pass() {
    pass_count=$((pass_count + 1))
    echo "PASS: $1"
}

# --------------------------------------------------------------------------
# (a) Empty sections directory
# --------------------------------------------------------------------------
sections_a="$tmpdir/sections-a"
mkdir -p "$sections_a"
output_a="$tmpdir/out-a.md"

stdout_a="$("$ASSEMBLE_ANCHOR" --sections-dir "$sections_a" --issue 42 --output "$output_a")"

grep -qxF 'ASSEMBLED=true' <<<"$stdout_a" \
    || fail "(a) expected ASSEMBLED=true in stdout, got: $stdout_a"
grep -qxF "OUTPUT=$output_a" <<<"$stdout_a" \
    || fail "(a) expected OUTPUT=$output_a in stdout, got: $stdout_a"

[ -f "$output_a" ] || fail "(a) output file not created"

expected_lines_a=1  # first-line marker
for _ in "${SECTION_MARKERS[@]}"; do
    expected_lines_a=$((expected_lines_a + 2))  # open + close marker pair
done
actual_lines_a=$(wc -l < "$output_a" | tr -d ' ')
[ "$actual_lines_a" = "$expected_lines_a" ] \
    || fail "(a) expected $expected_lines_a lines, got $actual_lines_a; content: $(cat "$output_a")"

head -n 1 "$output_a" | grep -qxF '<!-- larch:implement-anchor v1 issue=42 -->' \
    || fail "(a) first line is not the anchor marker: $(head -n 1 "$output_a")"

# Verify marker pairs in SECTION_MARKERS order, all empty.
line_num=2
for slug in "${SECTION_MARKERS[@]}"; do
    open_line=$(sed -n "${line_num}p" "$output_a")
    close_line=$(sed -n "$((line_num + 1))p" "$output_a")
    [ "$open_line" = "<!-- section:$slug -->" ] \
        || fail "(a) line $line_num: expected '<!-- section:$slug -->', got '$open_line'"
    [ "$close_line" = "<!-- section-end:$slug -->" ] \
        || fail "(a) line $((line_num + 1)): expected '<!-- section-end:$slug -->', got '$close_line'"
    line_num=$((line_num + 2))
done
pass "(a) empty sections directory → 1 anchor marker + 8 empty marker pairs in SECTION_MARKERS order"

# --------------------------------------------------------------------------
# (b) Partial fragments — populate only version-bump-reasoning and diagrams
# --------------------------------------------------------------------------
sections_b="$tmpdir/sections-b"
mkdir -p "$sections_b"
printf 'PATCH — smoke test\nLine 2\n' > "$sections_b/version-bump-reasoning.md"
# shellcheck disable=SC2016
# Single-quoted on purpose — emitting a literal mermaid fenced block.
printf '```mermaid\ngraph TD; A-->B\n```\n' > "$sections_b/diagrams.md"

output_b="$tmpdir/out-b.md"
"$ASSEMBLE_ANCHOR" --sections-dir "$sections_b" --issue 100 --output "$output_b" > /dev/null

grep -qxF '<!-- section:version-bump-reasoning -->' "$output_b" \
    || fail "(b) missing version-bump-reasoning open marker"
grep -qxF 'PATCH — smoke test' "$output_b" \
    || fail "(b) missing version-bump-reasoning content"
grep -qxF '<!-- section:diagrams -->' "$output_b" \
    || fail "(b) missing diagrams open marker"
grep -qxF '```mermaid' "$output_b" \
    || fail "(b) missing diagrams mermaid fence"

# Verify the order: diagrams (index 3) must appear before version-bump-reasoning (index 4).
diagrams_line=$(grep -n '<!-- section:diagrams -->' "$output_b" | head -n 1 | cut -d: -f1)
vbr_line=$(grep -n '<!-- section:version-bump-reasoning -->' "$output_b" | head -n 1 | cut -d: -f1)
[ "$diagrams_line" -lt "$vbr_line" ] \
    || fail "(b) expected diagrams ($diagrams_line) before version-bump-reasoning ($vbr_line)"

# Verify empty slugs still emit marker pairs (e.g., plan-goals-test).
grep -qxF '<!-- section:plan-goals-test -->' "$output_b" \
    || fail "(b) missing plan-goals-test open marker (empty fragment case)"
grep -qxF '<!-- section-end:plan-goals-test -->' "$output_b" \
    || fail "(b) missing plan-goals-test close marker (empty fragment case)"

pass "(b) partial fragments → populated content in order, empty pairs for missing slugs"

# --------------------------------------------------------------------------
# (c) Full fragments — all 8 slugs populated
# --------------------------------------------------------------------------
sections_c="$tmpdir/sections-c"
mkdir -p "$sections_c"
for slug in "${SECTION_MARKERS[@]}"; do
    printf 'fragment content for %s\n' "$slug" > "$sections_c/$slug.md"
done

output_c="$tmpdir/out-c.md"
"$ASSEMBLE_ANCHOR" --sections-dir "$sections_c" --issue 7 --output "$output_c" > /dev/null

for slug in "${SECTION_MARKERS[@]}"; do
    grep -qxF "fragment content for $slug" "$output_c" \
        || fail "(c) missing content for slug '$slug' in output"
done
pass "(c) full fragments → all 8 slugs populated"

# --------------------------------------------------------------------------
# (d) Missing anchor-section-markers.sh helper
# --------------------------------------------------------------------------
fake_tree="$tmpdir/fake"
mkdir -p "$fake_tree"
cp "$ASSEMBLE_ANCHOR" "$fake_tree/assemble-anchor.sh"
chmod +x "$fake_tree/assemble-anchor.sh"
# Deliberately do NOT copy anchor-section-markers.sh.

output_d="$tmpdir/out-d.md"
set +e
stdout_d="$("$fake_tree/assemble-anchor.sh" --sections-dir "$sections_a" --issue 1 --output "$output_d" 2>&1)"
exit_d=$?
set -e

[ "$exit_d" = "1" ] || fail "(d) expected exit 1, got $exit_d"
grep -qxF 'FAILED=true' <<<"$stdout_d" \
    || fail "(d) expected FAILED=true on stdout, got: $stdout_d"
grep -qE '^ERROR=missing helper:' <<<"$stdout_d" \
    || fail "(d) expected 'ERROR=missing helper:' on stdout, got: $stdout_d"
pass "(d) missing anchor-section-markers.sh → FAILED=true + ERROR=missing helper + exit 1"

# --------------------------------------------------------------------------
# (e) Invalid --issue value
# --------------------------------------------------------------------------
set +e
stdout_e="$("$ASSEMBLE_ANCHOR" --sections-dir "$sections_a" --issue not-a-number --output "$tmpdir/out-e.md" 2>&1)"
exit_e=$?
set -e

[ "$exit_e" = "1" ] || fail "(e) expected exit 1, got $exit_e"
grep -qxF 'FAILED=true' <<<"$stdout_e" \
    || fail "(e) expected FAILED=true on stdout, got: $stdout_e"
grep -qE '^ERROR=usage: invalid value for --issue' <<<"$stdout_e" \
    || fail "(e) expected 'ERROR=usage: invalid value for --issue' on stdout, got: $stdout_e"
pass "(e) invalid --issue value → usage error, exit 1"

# --------------------------------------------------------------------------
# (f) First-line marker exactness
# --------------------------------------------------------------------------
sections_f="$tmpdir/sections-f"
mkdir -p "$sections_f"
output_f="$tmpdir/out-f.md"
"$ASSEMBLE_ANCHOR" --sections-dir "$sections_f" --issue 999 --output "$output_f" > /dev/null

first_line="$(head -n 1 "$output_f")"
[ "$first_line" = '<!-- larch:implement-anchor v1 issue=999 -->' ] \
    || fail "(f) expected first line '<!-- larch:implement-anchor v1 issue=999 -->', got '$first_line'"
pass "(f) first-line HTML anchor marker exactness"

echo ""
echo "All $pass_count assertions passed."
