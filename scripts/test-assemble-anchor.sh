#!/usr/bin/env bash
# test-assemble-anchor.sh — regression harness for scripts/assemble-anchor.sh.
#
# Covers 10 assertion categories:
#   (a) Empty sections directory → 8 empty marker pairs + first-line marker.
#   (b) Partial fragments → populated where present, empty pairs elsewhere,
#       in SECTION_MARKERS order.
#   (b2) Newline-terminated fragment → exactly one newline before the close
#       marker (regression guard for the pre-fix $(tail -c 1 ...) command-
#       substitution newline-stripping bug).
#   (b3) Fragment without trailing newline → helper inserts newline so the
#       close marker still appears on its own line.
#   (c) Full fragments → all 8 slugs populated.
#   (d) Missing anchor-section-markers.sh helper → FAILED=true / ERROR=missing
#       helper + exit 1.
#   (e) Invalid --issue value (non-integer) → usage error, exit 1.
#   (f) First line of output is always the HTML anchor marker.
#   (g) Non-directory --sections-dir (regular file) → fail-closed with
#       FAILED=true / ERROR=sections-dir exists but is not a directory +
#       exit 2.
#   (h) Unreadable fragment file (chmod 000) → fail-closed with FAILED=true /
#       ERROR=failed to read fragment + exit 2. Skipped when running as root.

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
# (b2) Exact line-shape check: a newline-terminated fragment produces NO
#      extra blank line between content and the close marker.
#      Regression guard for the $(tail -c 1 ...) command-substitution bug
#      (see scripts/assemble-anchor.sh:~130 — newline-stripping on command
#      substitution caused a blank line to be emitted for every populated
#      fragment before the fix).
# --------------------------------------------------------------------------
sections_b2="$tmpdir/sections-b2"
mkdir -p "$sections_b2"
# Fragment ends with exactly one trailing newline (the canonical case).
printf 'line one\nline two\n' > "$sections_b2/plan-goals-test.md"

output_b2="$tmpdir/out-b2.md"
"$ASSEMBLE_ANCHOR" --sections-dir "$sections_b2" --issue 500 --output "$output_b2" > /dev/null

# Build expected output: anchor marker + plan-goals-test populated + 7 empty pairs.
expected_b2="$tmpdir/expected-b2.md"
{
    printf '<!-- larch:implement-anchor v1 issue=500 -->\n'
    printf '<!-- section:plan-goals-test -->\n'
    printf 'line one\nline two\n'
    printf '<!-- section-end:plan-goals-test -->\n'
    for slug in plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics; do
        printf '<!-- section:%s -->\n' "$slug"
        printf '<!-- section-end:%s -->\n' "$slug"
    done
} > "$expected_b2"

if ! diff -q "$output_b2" "$expected_b2" > /dev/null; then
    echo "DIFF (actual vs expected):"
    diff "$output_b2" "$expected_b2" || true
    fail "(b2) newline-terminated fragment produced wrong output structure (extra blank line bug regression?)"
fi
pass "(b2) newline-terminated fragment → exactly one newline before close marker (no extra blank line)"

# --------------------------------------------------------------------------
# (b3) A fragment without a trailing newline still gets a newline inserted
#      before the close marker (edge case — caller forgot final '\n').
# --------------------------------------------------------------------------
sections_b3="$tmpdir/sections-b3"
mkdir -p "$sections_b3"
# Fragment has NO trailing newline.
printf 'no trailing newline here' > "$sections_b3/plan-goals-test.md"

output_b3="$tmpdir/out-b3.md"
"$ASSEMBLE_ANCHOR" --sections-dir "$sections_b3" --issue 501 --output "$output_b3" > /dev/null

# The close marker must still appear on its own line.
grep -qxF '<!-- section-end:plan-goals-test -->' "$output_b3" \
    || fail "(b3) close marker must be on its own line even when fragment lacks trailing newline"
# No 'no trailing newline here<!-- section-end:' concatenation.
if grep -qF 'here<!-- section-end:plan-goals-test -->' "$output_b3"; then
    fail "(b3) fragment content runs into close marker — missing newline insertion"
fi
pass "(b3) fragment without trailing newline → newline inserted before close marker"

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

# --------------------------------------------------------------------------
# (g) Non-directory --sections-dir → fail closed (exit 2).
#     Regression guard: passing a regular file where a directory is expected
#     previously produced an all-empty skeleton (silently). Post-fix: fail
#     closed with FAILED=true + ERROR=sections-dir exists but is not a
#     directory.
# --------------------------------------------------------------------------
bogus_file="$tmpdir/not-a-dir"
printf 'accidentally passed a file\n' > "$bogus_file"

set +e
stdout_g="$("$ASSEMBLE_ANCHOR" --sections-dir "$bogus_file" --issue 1 --output "$tmpdir/out-g.md" 2>&1)"
exit_g=$?
set -e

[ "$exit_g" = "2" ] || fail "(g) expected exit 2 for non-directory --sections-dir, got $exit_g"
grep -qxF 'FAILED=true' <<<"$stdout_g" \
    || fail "(g) expected FAILED=true on stdout, got: $stdout_g"
grep -qE '^ERROR=sections-dir exists but is not a directory' <<<"$stdout_g" \
    || fail "(g) expected 'ERROR=sections-dir exists but is not a directory' on stdout, got: $stdout_g"
pass "(g) non-directory --sections-dir → fail closed with exit 2"

# --------------------------------------------------------------------------
# (h) Unreadable fragment file → fail closed (exit 2).
#     Regression guard: cat failure previously propagated exit but the
#     pre-fix script did not check cat's exit status in the pipeline; post-
#     fix the script fails closed with FAILED=true + ERROR=failed to read
#     fragment. Only runs when the test is executed by a non-root user
#     (root bypasses file permission checks on most platforms).
# --------------------------------------------------------------------------
if [ "$(id -u)" != "0" ]; then
    sections_h="$tmpdir/sections-h"
    mkdir -p "$sections_h"
    printf 'content\n' > "$sections_h/diagrams.md"
    chmod 000 "$sections_h/diagrams.md"

    set +e
    stdout_h="$("$ASSEMBLE_ANCHOR" --sections-dir "$sections_h" --issue 777 --output "$tmpdir/out-h.md" 2>&1)"
    exit_h=$?
    set -e

    chmod 644 "$sections_h/diagrams.md"  # restore so the EXIT trap's rm -rf works
    [ "$exit_h" = "2" ] || fail "(h) expected exit 2 for unreadable fragment, got $exit_h (stdout: $stdout_h)"
    grep -qxF 'FAILED=true' <<<"$stdout_h" \
        || fail "(h) expected FAILED=true on stdout, got: $stdout_h"
    grep -qE '^ERROR=failed to read fragment' <<<"$stdout_h" \
        || fail "(h) expected 'ERROR=failed to read fragment' on stdout, got: $stdout_h"
    pass "(h) unreadable fragment → fail closed with exit 2"
else
    echo "SKIP: (h) unreadable-fragment test (running as root; chmod 000 does not block reads)"
fi

echo ""
echo "All $pass_count assertions passed."
