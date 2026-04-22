#!/bin/bash
# Structural regression test for /review skill progressive-disclosure invariants
# (closes #306). Asserts that skills/review/SKILL.md + skills/review/references/
# topology survives edits:
#  - Each reference file on disk is named on at least one 'MANDATORY — READ ENTIRE FILE'
#    line in SKILL.md (bidirectional orphan detection via filesystem enumeration).
#  - Baseline expected references (domain-rules.md, voting.md) exist and each is named
#    on a MANDATORY line (explicit baseline binding for clearer diagnostics).
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
# (5) CI-parity focus-area enum check. Mirrors the agent-sync UNQUOTED_FILES
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
  || fail "(5) SKILL.md lacks the unquoted slash-separated focus-area enum ('code-quality / risk-integration / correctness / architecture') — CI's agent-sync UNQUOTED_FILES guard would fail"

while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  line_text="${hit#*:}"
  if ! printf '%s\n' "$line_text" | grep -q 'security'; then
    fail "(5) focus-area enum line lacks 'security' on same line — CI's agent-sync UNQUOTED_FILES guard would fail: $line_text"
  fi
done <<< "$enum_hits"

# ---------------------------------------------------------------------------
# (6) Anti-halt banner substring present in SKILL.md. Intentional overlap with
#     scripts/test-anti-halt-banners.sh (which pins the same substring for
#     every ORCHESTRATORS entry including skills/review/SKILL.md) — single-file
#     fail locality per the test-implement-structure.sh precedent.
# ---------------------------------------------------------------------------
grep -Fq '**Anti-halt continuation reminder.**' "$SKILL_MD" \
  || fail "(6) SKILL.md lacks anti-halt banner substring '**Anti-halt continuation reminder.**'"

# ---------------------------------------------------------------------------
# (7) Micro-reminder substring present in SKILL.md. Uses the canonical narrow
#     token 'Continue after child returns' — matches test-anti-halt-banners.sh
#     MICRO_SIGNATURE, so a future loop-internal variant like
#     '**Continue after child returns (loop-internal).**' still matches.
#     Intentional overlap with test-anti-halt-banners.sh per the note above.
# ---------------------------------------------------------------------------
grep -Fq 'Continue after child returns' "$SKILL_MD" \
  || fail "(7) SKILL.md lacks micro-reminder substring 'Continue after child returns'"

# ---------------------------------------------------------------------------
# (8) Each skills/review/references/*.md opens with '**Consumer**:' and
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
      || fail "(8) references/$(basename "$ref_path") must open with '$hdr' header in the first 20 lines"
  done
done

echo "PASS: test-review-structure.sh — all 8 structural invariants hold"
exit 0
