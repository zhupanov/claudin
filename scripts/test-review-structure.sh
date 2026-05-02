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
#    'references/domain-rules.md' together); voting.md is pinned to the rounds 1-3
#    branch callsite (a single line carries MANDATORY, 'rounds 1-3' (case-insensitive),
#    and 'references/voting.md' together); and the
#    reciprocal rounds-4+ guard (a line carries 'Do NOT load' and
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
#  - Two-mode activation contract pins: a single SKILL.md line carries '--diff' and
#    'positional description' together — pinning the two-mode grammar; SKILL.md
#    contains the verbatim --diff+description mutual-exclusion abort message; SKILL.md
#    contains the verbatim no-args error abort message. Together these pins anchor
#    the mode activation contract so a future edit cannot regress it silently.
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
#     (5b) voting.md pinned to the rounds 1-3 branch: one SKILL.md line contains
#          'MANDATORY — READ ENTIRE FILE', 'rounds 1-3' (case-insensitive),
#          and 'references/voting.md' together.
#
#     (5c) Reciprocal rounds-4+ guard: one SKILL.md line contains 'Do NOT load'
#          and 'references/voting.md' together.
# ---------------------------------------------------------------------------
grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" \
  | grep -E 'Step 3([^0-9A-Za-z]|$)' \
  | grep -Eq 'references/domain-rules\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5a) no single SKILL.md line carries 'MANDATORY — READ ENTIRE FILE', 'Step 3' (boundary-anchored), and 'references/domain-rules.md' together — Step 3 entry callsite pin for domain-rules.md is broken"

grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" \
  | grep -iE 'rounds 1-3' \
  | grep -Eq 'references/voting\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5b) no single SKILL.md line carries 'MANDATORY — READ ENTIRE FILE', 'rounds 1-3' (case-insensitive), and 'references/voting.md' together — rounds-1-3 branch callsite pin for voting.md is broken"

grep 'Do NOT load' "$SKILL_MD" \
  | grep -Eq 'references/voting\.md([^A-Za-z0-9._-]|$)' \
  || fail "(5c) no single SKILL.md line carries 'Do NOT load' and 'references/voting.md' together — reciprocal rounds-4+ guard for voting.md is missing"

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
# (10) Mode activation pin. A single SKILL.md line carries '--diff' AND
#      'positional description' (case-insensitive) together. Anchors the
#      two-mode grammar: --diff vs positional description text. Pattern
#      parallel to (5a)/(5b)/(5c): pipeline threads each token through its
#      own filter stage while preserving line granularity, so a future edit
#      that splits the activation directive across lines fails closed.
# ---------------------------------------------------------------------------
grep -F -- '--diff' "$SKILL_MD" \
  | grep -iq 'positional description' \
  || fail "(10) no single SKILL.md line carries '--diff' and 'positional description' together — mode activation contract pin is broken"

# ---------------------------------------------------------------------------
# (11) Diff+description mutual-exclusion abort message verbatim pin.
#      SKILL.md must contain the exact literal string of the abort message
#      printed when --diff is combined with positional description text.
# ---------------------------------------------------------------------------
grep -Fq '**⚠ --diff cannot be combined with a description. Use --diff alone for branch diff review, or provide a description without --diff. Aborting.**' "$SKILL_MD" \
  || fail "(11) SKILL.md is missing the verbatim --diff+description mutual-exclusion abort message"

# ---------------------------------------------------------------------------
# (12) No-args error abort message verbatim pin. SKILL.md must contain
#      the exact literal string of the abort message printed when neither
#      --diff nor positional description is provided.
# ---------------------------------------------------------------------------
grep -Fq '**⚠ /review requires either --diff (branch diff review) or a description of what to review.' "$SKILL_MD" \
  || fail "(12) SKILL.md is missing the verbatim no-args error abort message"

# ---------------------------------------------------------------------------
# (13) Substantive-validation flag pin (#661). The Step 3a collect-agent-results.sh
#      invocation in SKILL.md must carry both --substantive-validation AND
#      --validation-mode on the SAME line as --timeout 1860, so banner-only
#      reviewer output (e.g., "Authentication required") is rejected as
#      STATUS=NOT_SUBSTANTIVE rather than passing as STATUS=OK. Pipeline matches
#      the (10) pattern: each filter stage threads one literal while preserving
#      line granularity. A future edit that drops either flag, or splits the
#      invocation across multiple lines, fails closed under `set -o pipefail`.
# ---------------------------------------------------------------------------
grep 'collect-agent-results.sh' "$SKILL_MD" \
  | grep -F -- '--timeout 1860' \
  | grep -F -- '--substantive-validation' \
  | grep -Fq -- '--validation-mode' \
  || fail "(13) no single SKILL.md line carries 'collect-agent-results.sh', '--timeout 1860', '--substantive-validation', and '--validation-mode' together — issue #661 substantive-validation contract pin is broken"

# ---------------------------------------------------------------------------
# (14) Specialist prompt rendering is wired (#659).
#      Assertion (14) checks that SKILL.md references render-specialist-prompt.sh
#      and that the script accepts --mode for diff/description mode handling.
# ---------------------------------------------------------------------------
grep -Fq 'render-specialist-prompt.sh' "$SKILL_MD" \
  || fail "(14) SKILL.md does not reference 'render-specialist-prompt.sh' — specialist prompt rendering is not wired"
grep -Fq -- '--mode' "$REPO_ROOT/scripts/render-specialist-prompt.sh" \
  || fail "(14) scripts/render-specialist-prompt.sh does not accept '--mode' — diff/description mode handling is missing"

# ---------------------------------------------------------------------------
# (15) Slice-mode OOS marking is handled by scripts/render-specialist-prompt.sh
#      (for specialist reviewers) and by the agent file output format section
#      (for all reviewers). OOS anchor language lives in the render script's
#      description preamble, not inline in SKILL.md. The dual-list contract (In-Scope
#      Findings + Out-of-Scope Observations) is enforced by the specialist agent
#      files' Output format section and by test-render-specialist-prompt.sh.
#      This assertion verifies that scripts/render-specialist-prompt.sh exists
#      and the 5 specialist agent files exist with the dual-list output headers.
# ---------------------------------------------------------------------------
RENDERER="$REPO_ROOT/scripts/render-specialist-prompt.sh"
[[ -f "$RENDERER" ]] \
  || fail "(15) scripts/render-specialist-prompt.sh does not exist — specialist prompt rendering is broken"
for specialist in reviewer-structure reviewer-correctness reviewer-testing reviewer-security reviewer-edge-cases; do
  agent_file="$REPO_ROOT/agents/${specialist}.md"
  [[ -f "$agent_file" ]] \
    || fail "(15) agents/${specialist}.md does not exist — specialist agent definition is missing"
  grep -Fq '### In-Scope Findings' "$agent_file" \
    || fail "(15) agents/${specialist}.md is missing '### In-Scope Findings' section header — dual-list output contract is broken"
  grep -Fq '### Out-of-Scope Observations' "$agent_file" \
    || fail "(15) agents/${specialist}.md is missing '### Out-of-Scope Observations' section header — dual-list output contract is broken"
done

# ---------------------------------------------------------------------------
# (16) Step 3a description-mode external-reviewer parsing carries dual-list contract (#659).
#      A single SKILL.md line carries 'In description mode', 'dual-list output',
#      '### In-Scope Findings', AND '### Out-of-Scope Observations' together —
#      pinning the parser-side mode-conditional wording in Step 3a item 2.
# ---------------------------------------------------------------------------
grep 'In description mode' "$SKILL_MD" \
  | grep -F 'dual-list output' \
  | grep -F '### In-Scope Findings' \
  | grep -Fq '### Out-of-Scope Observations' \
  || fail "(16) no single SKILL.md line carries 'In description mode', 'dual-list output', '### In-Scope Findings', AND '### Out-of-Scope Observations' together — Step 3a description-mode dual-list parsing contract is broken"

# ---------------------------------------------------------------------------
# (17) Step 3a diff-mode external-reviewer single-list preservation (#659).
#      A single SKILL.md line carries 'In diff mode', 'single-list output', AND
#      'entire output' together — pinning Step 3a item 2's diff-mode preservation
#      so a future blanket rewrite cannot flatten the description/diff modes.
# ---------------------------------------------------------------------------
grep 'In diff mode' "$SKILL_MD" \
  | grep -F 'single-list output' \
  | grep -Fq 'entire output' \
  || fail "(17) no single SKILL.md line carries 'In diff mode', 'single-list output', AND 'entire output' together — Step 3a diff-mode single-list preservation is broken"

# ---------------------------------------------------------------------------
# (18) Step 4b pieces.json composition contract (#778). A single SKILL.md line
#      carries '--pieces-json' — pinning the /umbrella invocation's pieces.json
#      forwarding. This is the structural anchor for the inter-finding
#      dependency edge pipeline: /review composes pieces.json from file-overlap
#      metadata and forwards it via --pieces-json to /umbrella.
# ---------------------------------------------------------------------------
grep -Fq -- '--pieces-json' "$SKILL_MD" \
  || fail "(18) SKILL.md lacks '--pieces-json' — Step 4b pieces.json composition contract (#778) is broken"

echo "PASS: test-review-structure.sh — all 18 structural invariants hold"
exit 0
