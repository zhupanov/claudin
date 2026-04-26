#!/bin/bash
# Structural regression test for /review skill progressive-disclosure invariants
# (closes #306, hardened in #318). Asserts that skills/review/SKILL.md +
# skills/review/references/ topology survives edits:
#  - Each reference file on disk is named on at least one 'MANDATORY — READ ENTIRE FILE'
#    line in SKILL.md (bidirectional orphan detection via filesystem enumeration).
#  - Baseline expected references (domain-rules.md, voting.md) exist and each is named
#    on a MANDATORY line (explicit baseline binding for clearer diagnostics).
#  - Line-scoped callsite pins (#318, parallel to test-research-structure.sh's
#    reciprocal Do-NOT-load pins): domain-rules.md is pinned to the Step 3 entry
#    callsite (a single SKILL.md line carries MANDATORY, 'Step 3', and
#    'references/domain-rules.md' together); voting.md is pinned to the round-1
#    branch callsite (a single line carries MANDATORY, 'round 1' (case-insensitive,
#    matching 'In round 1' too), and 'references/voting.md' together); and the
#    reciprocal rounds-2+ guard (a line carries 'Do NOT load' and
#    'references/voting.md' together). Pattern parallel to test-research-structure.sh
#    so a future edit cannot move voting.md's MANDATORY to Step 3 entry or drop the
#    Do-NOT-load guard without the harness catching the drift.
#  - SKILL.md's Cursor/Codex quick-review prompt lines carry the focus-area enum
#    'code-quality / risk-integration / correctness / architecture' AND every such line
#    also contains 'security' on the same line. Mirrors the agent-sync UNQUOTED_FILES
#    loop in .github/workflows/ci.yaml so make lint and CI fail together.
#  - SKILL.md carries the anti-halt banner substring and at least one micro-reminder
#    occurrence. Intentional overlap with scripts/test-anti-halt-banners.sh for
#    single-file fail locality — matches the test-implement-structure.sh precedent
#    of pinning per-skill invariants even when a global harness also covers them.
#  - Each references/*.md opens with '**Consumer**:' and '**Binding convention**:'
#    header lines in the first 20 lines. /review deliberately uses this 2-line header
#    schema, NOT the /implement Consumer/Contract/When-to-load triplet.
#  - Three-way slice-mode activation contract pins (#637, parallel to assertions 5a/5b/5c):
#    a single SKILL.md line carries 'Slice mode', '--slice', '--slice-file', AND
#    'positional' (case-insensitive on 'positional') together — pinning the activation
#    sentence that defines slice mode as enabled by --slice OR --slice-file OR positional
#    text after --create-issues; SKILL.md contains the verbatim empty-positional abort
#    message ('--create-issues requires a slice description (--slice <text>, --slice-file
#    <path>, or trailing positional text)'); SKILL.md contains the verbatim
#    positional-vs-slice-flag mutual-exclusion abort message ('Positional slice text
#    cannot be combined with --slice or --slice-file'). Together these three pins anchor
#    the contracts introduced by PR #638 so a future edit cannot regress them silently.
#
# Exit 0 on pass, exit 1 on any assertion failure.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/review/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/review/references"

expected_refs=(
  "domain-rules.md"
  "voting.md"
)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# ---------------------------------------------------------------------------
# (1) SKILL.md and references/ directory exist.
# ---------------------------------------------------------------------------
[[ -f "$SKILL_MD" ]] || fail "(1) skills/review/SKILL.md missing: $SKILL_MD"
[[ -d "$REFS_DIR" ]] || fail "(1) skills/review/references/ missing: $REFS_DIR"

# ---------------------------------------------------------------------------
# (2) Each expected baseline reference file exists.
# ---------------------------------------------------------------------------
for ref in "${expected_refs[@]}"; do
  [[ -f "$REFS_DIR/$ref" ]] \
    || fail "(2) expected reference file missing: skills/review/references/$ref"
done

# ---------------------------------------------------------------------------
# (3) Every skills/review/references/*.md file on disk is named on at least one
#     'MANDATORY — READ ENTIRE FILE' line in SKILL.md (bidirectional orphan
#     detection). Match 'references/<basename>' followed by a boundary
#     character (end of line, whitespace, or a non-filename token like ` ` ) ,
#     so neither a name-containing-name case (e.g. 'references/my-voting.md'
#     covering 'voting.md') nor a suffix/extension case (e.g.
#     'references/foo.md.bak' covering 'foo.md') can false-pass. The
#     filename-char class is [A-Za-z0-9._-]; any character outside it counts
#     as a boundary.
# ---------------------------------------------------------------------------
# Use `|| true` so grep's exit-1 on zero matches does not abort before fail().
mandatory_lines=$(grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" || true)
[[ -n "$mandatory_lines" ]] \
  || fail "(3) SKILL.md contains zero 'MANDATORY — READ ENTIRE FILE' lines"

shopt -s nullglob
ref_files=( "$REFS_DIR"/*.md )
shopt -u nullglob
[[ "${#ref_files[@]}" -gt 0 ]] \
  || fail "(3) no .md files found under $REFS_DIR — cannot validate orphan-reference invariant"

# Escape regex metacharacters in the basename (e.g., '.' in '*.md') so grep -E
# treats them literally. The only metachar expected in reference filenames is
# '.', but escape the full set defensively.
escape_regex() {
  printf '%s' "$1" | sed 's/[][\.*^$+?(){}|\\/-]/\\&/g'
}

for ref_path in "${ref_files[@]}"; do
  ref_basename=$(basename "$ref_path")
  escaped=$(escape_regex "$ref_basename")
  # Require 'references/<basename>' followed by end-of-line or a non-filename
  # character (anything outside [A-Za-z0-9._-]) so 'references/foo.md.bak' does
  # NOT satisfy the check for 'foo.md'.
  printf '%s\n' "$mandatory_lines" | grep -Eq "references/${escaped}([^A-Za-z0-9._-]|$)" \
    || fail "(3) no 'MANDATORY — READ ENTIRE FILE' line in SKILL.md references 'references/$ref_basename' — orphan reference under skills/review/references/"
done

# ---------------------------------------------------------------------------
# (4) Each baseline expected reference appears on at least one MANDATORY line
#     in SKILL.md. Logically implied by (3) once the filesystem matches the
#     baseline, but kept as a distinct check for clearer diagnostics if the
#     baseline pair specifically regresses. Uses the same path-token boundary
#     match as (3).
# ---------------------------------------------------------------------------
for ref in "${expected_refs[@]}"; do
  escaped=$(escape_regex "$ref")
  printf '%s\n' "$mandatory_lines" | grep -Eq "references/${escaped}([^A-Za-z0-9._-]|$)" \
    || fail "(4) no 'MANDATORY — READ ENTIRE FILE' line in SKILL.md references 'references/$ref' — baseline step-to-reference binding broken"
done

# ---------------------------------------------------------------------------
# (5) Line-scoped callsite pins for MANDATORY references (#318). Pattern parallel
#     to test-research-structure.sh's reciprocal Do-NOT-load pins: each assertion
#     checks that a SINGLE line in SKILL.md carries all the required tokens
#     together. Line-scoped by construction — the grep pipeline threads each
#     token through its own filter stage while preserving line granularity, so a
#     future edit that splits the directive across lines fails. Under
#     `set -o pipefail` a zero-match in any stage fails the pipeline and the
#     `||` short-circuit triggers fail(). Boundary match on the reference path
#     (character outside [A-Za-z0-9._-] or end-of-line) mirrors checks (3) and
#     (4) so 'references/voting.md.bak' can NOT satisfy the pin for 'voting.md'.
#
#     (5a) domain-rules.md pinned to the Step 3 entry callsite: one SKILL.md
#          line contains 'MANDATORY — READ ENTIRE FILE', 'Step 3' (with a
#          word-char boundary so 'Step 3a'/'Step 30'/'Step 3f' do NOT
#          false-pass), and 'references/domain-rules.md' together.
#
#     (5b) voting.md pinned to the round-1 branch: one SKILL.md line contains
#          'MANDATORY — READ ENTIRE FILE', 'round 1' (case-insensitive — matches
#          both 'round 1' and 'In round 1'; same word-char boundary so
#          'round 10'/'round 11' do NOT false-pass), and 'references/voting.md'
#          together.
#
#     (5c) Reciprocal rounds-2+ guard: one SKILL.md line contains 'Do NOT load'
#          and 'references/voting.md' together.
# ---------------------------------------------------------------------------
grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" \
  | grep -E 'Step 3([^0-9A-Za-z]|$)' \
  | grep -Eq 'references/domain-rules\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5a) no single SKILL.md line carries 'MANDATORY — READ ENTIRE FILE', 'Step 3' (boundary-anchored), and 'references/domain-rules.md' together — Step 3 entry callsite pin for domain-rules.md is broken"

grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" \
  | grep -iE 'round 1([^0-9A-Za-z]|$)' \
  | grep -Eq 'references/voting\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5b) no single SKILL.md line carries 'MANDATORY — READ ENTIRE FILE', 'round 1' (case-insensitive, boundary-anchored), and 'references/voting.md' together — round-1 branch callsite pin for voting.md is broken"

grep 'Do NOT load' "$SKILL_MD" \
  | grep -Eq 'references/voting\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5c) no single SKILL.md line carries 'Do NOT load' and 'references/voting.md' together — reciprocal rounds-2+ guard for voting.md is missing"

# ---------------------------------------------------------------------------
# (6) CI-parity focus-area enum check. Mirrors the agent-sync UNQUOTED_FILES
#     loop in .github/workflows/ci.yaml (referenced by name, not line number):
#     the loop greps every unquoted-prompt file for
#       'code-quality / risk-integration / correctness / architecture'
#     and fails if any matching line lacks 'security' on the same line.
#     Per-line enforcement (not first-match-only) so a future enum line without
#     'security' cannot pass the harness while CI fails. Matches
#     test-implement-structure.sh assertion 6.
# ---------------------------------------------------------------------------
enum_hits=$(grep -n 'code-quality / risk-integration / correctness / architecture' "$SKILL_MD" || true)
[[ -n "$enum_hits" ]] \
  || fail "(6) SKILL.md lacks the unquoted slash-separated focus-area enum ('code-quality / risk-integration / correctness / architecture') — CI's agent-sync UNQUOTED_FILES guard would fail"

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  line_text="${hit#*:}"
  if ! printf '%s\n' "$line_text" | grep -q 'security'; then
    fail "(6) focus-area enum line lacks 'security' on same line — CI's agent-sync UNQUOTED_FILES guard would fail: $line_text"
  fi
done <<< "$enum_hits"

# ---------------------------------------------------------------------------
# (7) Anti-halt banner substring present in SKILL.md. Intentional overlap with
#     scripts/test-anti-halt-banners.sh (which pins the same substring for
#     every ORCHESTRATORS entry including skills/review/SKILL.md) — single-file
#     fail locality per the test-implement-structure.sh precedent.
# ---------------------------------------------------------------------------
grep -Fq '**Anti-halt continuation reminder.**' "$SKILL_MD" \
  || fail "(7) SKILL.md lacks anti-halt banner substring '**Anti-halt continuation reminder.**'"

# ---------------------------------------------------------------------------
# (8) Micro-reminder substring present in SKILL.md. Uses the canonical narrow
#     token 'Continue after child returns' — matches test-anti-halt-banners.sh
#     MICRO_SIGNATURE, so a future loop-internal variant like
#     '**Continue after child returns (loop-internal).**' still matches.
#     Intentional overlap with test-anti-halt-banners.sh per the note above.
# ---------------------------------------------------------------------------
grep -Fq 'Continue after child returns' "$SKILL_MD" \
  || fail "(8) SKILL.md lacks micro-reminder substring 'Continue after child returns'"

# ---------------------------------------------------------------------------
# (9) Each skills/review/references/*.md opens with '**Consumer**:' and
#     '**Binding convention**:' header lines in the first 20 lines. /review's
#     deliberate 2-line header schema, NOT the /implement Consumer/Contract/
#     When-to-load triplet. Peer pattern from test-research-structure.sh (head
#     -n 20) so a future edit cannot bury the headers mid-file without the
#     harness catching the drift.
# ---------------------------------------------------------------------------
review_header_lines=(
  '**Consumer**:'
  '**Binding convention**:'
)
for ref_path in "${ref_files[@]}"; do
  for hdr in "${review_header_lines[@]}"; do
    head -n 20 "$ref_path" | grep -Fq "$hdr" \
      || fail "(9) references/$(basename "$ref_path") must open with '$hdr' header in the first 20 lines"
  done
done

# ---------------------------------------------------------------------------
# (10) Three-way slice-mode activation pin (#637). A SINGLE line in SKILL.md must
#      carry 'Slice mode', '--slice', '--slice-file', AND 'positional' together
#      (case-insensitive on 'positional' since prose/heading variants like
#      'Positional' may appear). Anchors the activation sentence that defines
#      slice mode as enabled by --slice OR --slice-file OR positional text after
#      --create-issues. Pattern parallel to (5a)/(5b)/(5c): pipeline threads each
#      token through its own filter stage while preserving line granularity, so a
#      future edit that splits the activation directive across lines fails closed.
#      Under `set -o pipefail` a zero-match in any stage fails the pipeline and the
#      `||` short-circuit triggers fail().
# ---------------------------------------------------------------------------
grep 'Slice mode' "$SKILL_MD" \
  | grep -F -- '--slice' \
  | grep -F -- '--slice-file' \
  | grep -iq 'positional' \
  || fail "(10) no single SKILL.md line carries 'Slice mode', '--slice', '--slice-file', and 'positional' together — three-way slice-mode activation contract pin is broken"

# ---------------------------------------------------------------------------
# (11) Empty-positional abort message verbatim pin (#637). SKILL.md must contain
#      the exact literal string of the abort message printed when --create-issues
#      is set without --slice, --slice-file, or trailing positional text. Verbatim
#      grep -F so any wording drift fails closed — the abort message is a
#      user-facing contract that downstream tooling may depend on.
# ---------------------------------------------------------------------------
grep -Fq '**⚠ --create-issues requires a slice description (--slice <text>, --slice-file <path>, or trailing positional text). Aborting.**' "$SKILL_MD" \
  || fail "(11) SKILL.md is missing the verbatim empty-positional abort message — the contract introduced by PR #638 has regressed"

# ---------------------------------------------------------------------------
# (12) Positional-vs-slice-flag mutual-exclusion abort message verbatim pin (#637).
#      SKILL.md must contain the exact literal string of the abort message printed
#      when positional slice text is combined with --slice or --slice-file.
#      Verbatim grep -F same rationale as (11).
# ---------------------------------------------------------------------------
grep -Fq '**⚠ Positional slice text cannot be combined with --slice or --slice-file. Aborting.**' "$SKILL_MD" \
  || fail "(12) SKILL.md is missing the verbatim positional-vs-slice-flag mutual-exclusion abort message — the contract introduced by PR #638 has regressed"

# ---------------------------------------------------------------------------
# (13) Substantive-validation flag pin (#661). The Step 3a collect-reviewer-results.sh
#      invocation in SKILL.md must carry both --substantive-validation AND
#      --validation-mode on the SAME line as --timeout 1860, so banner-only
#      reviewer output (e.g., "Authentication required") is rejected as
#      STATUS=NOT_SUBSTANTIVE rather than passing as STATUS=OK. Pipeline matches
#      the (10) pattern: each filter stage threads one literal while preserving
#      line granularity. A future edit that drops either flag, or splits the
#      invocation across multiple lines, fails closed under `set -o pipefail`.
# ---------------------------------------------------------------------------
grep 'collect-reviewer-results.sh' "$SKILL_MD" \
  | grep -F -- '--timeout 1860' \
  | grep -F -- '--substantive-validation' \
  | grep -Fq -- '--validation-mode' \
  || fail "(13) no single SKILL.md line carries 'collect-reviewer-results.sh', '--timeout 1860', '--substantive-validation', and '--validation-mode' together — issue #661 substantive-validation contract pin is broken"

# ---------------------------------------------------------------------------
# (14) Cursor slice-mode prompt carries the dual-list contract (#659).
#      Pipeline-threaded grep: a single SKILL.md line must contain
#      'cursor-wrap-prompt.sh' (anchors to the Cursor slice-mode prompt line —
#      line 178 carries `cursor agent` as a Bash backslash-continuation, but the
#      prompt body itself sits on the next line which is uniquely anchored by
#      the `cursor-wrap-prompt.sh` invocation), 'slice-files.txt' (anchors to
#      slice mode), the OOS-marking sentence, AND the two canonical section
#      headers '### In-Scope Findings' and '### Out-of-Scope Observations'
#      together. Pattern parallel to (5a)/(5b)/(5c)/(10): pipeline-threaded so a
#      future edit that splits the directive across lines fails closed; under
#      `set -o pipefail` a zero-match in any stage fails the pipeline and the
#      `||` short-circuit triggers fail() — naturally avoids the vacuous-pass
#      risk of a `while read` loop without a non-empty guard.
# ---------------------------------------------------------------------------
grep 'cursor-wrap-prompt.sh' "$SKILL_MD" \
  | grep -F 'slice-files.txt' \
  | grep -F 'Mark any finding about a file NOT in slice-files.txt as OOS' \
  | grep -F '### In-Scope Findings' \
  | grep -Fq '### Out-of-Scope Observations' \
  || fail "(14) no single SKILL.md line carries 'cursor-wrap-prompt.sh', 'slice-files.txt', the OOS-marking sentence, '### In-Scope Findings', AND '### Out-of-Scope Observations' together — Cursor slice-mode dual-list contract is broken"

# ---------------------------------------------------------------------------
# (15) ALL slice-mode external-reviewer prompts carry the dual-list contract (#659).
#      Both the Cursor slice-mode prompt (with the `cursor-wrap-prompt.sh`
#      wrapper) and the Codex slice-mode prompt (a bare double-quoted positional
#      argument to `codex exec` that has no tool-specific literal on its own
#      line) carry the OOS-marking sentence as their unique signature in
#      `SKILL.md`. Verify that EVERY line carrying the OOS-marking sentence also
#      carries both section header literals — catches the Codex slice prompt
#      that assertion (14) cannot anchor by tool name. Non-emptiness guard plus
#      per-line check matches assertion (6)'s pattern; the count check
#      additionally pins exactly two such lines (Cursor + Codex), failing if a
#      future edit removes one prompt or accidentally adds a third.
# ---------------------------------------------------------------------------
oos_mark_lines=$(grep -F 'Mark any finding about a file NOT in slice-files.txt as OOS' "$SKILL_MD" || true)
[[ -n "$oos_mark_lines" ]] \
  || fail "(15) SKILL.md contains zero lines with the OOS-marking sentence 'Mark any finding about a file NOT in slice-files.txt as OOS' — Cursor and Codex slice-mode prompts have both regressed"

oos_mark_count=$(printf '%s\n' "$oos_mark_lines" | grep -c .)
[[ "$oos_mark_count" -eq 2 ]] \
  || fail "(15) SKILL.md has $oos_mark_count lines with the OOS-marking sentence — expected exactly 2 (one Cursor slice prompt + one Codex slice prompt). A line was removed, duplicated, or added."

while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  if ! printf '%s\n' "$line" | grep -F '### In-Scope Findings' | grep -Fq '### Out-of-Scope Observations'; then
    fail "(15) a slice-mode prompt line carries the OOS-marking sentence but is missing '### In-Scope Findings' and/or '### Out-of-Scope Observations' — slice-mode dual-list contract is broken on this line: $line"
  fi
done <<< "$oos_mark_lines"

# ---------------------------------------------------------------------------
# (16) Step 3a slice-mode external-reviewer parsing carries dual-list contract (#659).
#      A single SKILL.md line carries 'In slice mode', 'dual-list output',
#      '### In-Scope Findings', AND '### Out-of-Scope Observations' together —
#      pinning the parser-side mode-conditional wording in Step 3a item 2.
# ---------------------------------------------------------------------------
grep 'In slice mode' "$SKILL_MD" \
  | grep -F 'dual-list output' \
  | grep -F '### In-Scope Findings' \
  | grep -Fq '### Out-of-Scope Observations' \
  || fail "(16) no single SKILL.md line carries 'In slice mode', 'dual-list output', '### In-Scope Findings', AND '### Out-of-Scope Observations' together — Step 3a slice-mode dual-list parsing contract is broken"

# ---------------------------------------------------------------------------
# (17) Step 3a diff-mode external-reviewer single-list preservation (#659).
#      A single SKILL.md line carries 'In diff mode', 'single-list output', AND
#      'entire output' together — pinning Step 3a item 2's diff-mode preservation
#      so a future blanket rewrite cannot flatten the slice/diff modes.
# ---------------------------------------------------------------------------
grep 'In diff mode' "$SKILL_MD" \
  | grep -F 'single-list output' \
  | grep -Fq 'entire output' \
  || fail "(17) no single SKILL.md line carries 'In diff mode', 'single-list output', AND 'entire output' together — Step 3a diff-mode single-list preservation is broken"

echo "PASS: test-review-structure.sh — all 17 structural invariants hold"
exit 0
