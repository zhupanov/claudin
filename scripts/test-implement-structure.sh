#!/bin/bash
# Structural regression test for /implement SKILL.md + references/ topology (closes #234).
# Asserts 9 load-bearing invariants across skills/implement/SKILL.md and the four
# reference docs extracted from it. Complements scripts/test-implement-rebase-macro.sh,
# which owns the Rebase Checkpoint Macro mechanics; this harness owns top-level section
# headings, the MANDATORY ↔ reference-file binding, the focus-area CI-parity check,
# reference-file contract headers, and the no-`see Step N below|above` invariant in
# references/*.md. Intentional overlap: assertion (3) (single `## Rebase Checkpoint Macro`
# heading) and assertion (5) (verbosity literals) duplicate peer-harness assertions (A)
# and (D) respectively — accepted duplication per design-phase sketch consensus.
#
# Nine assertions:
#  (1) Exactly 1 `^## Load-Bearing Invariants$` heading in skills/implement/SKILL.md.
#  (2) Exactly 1 `^## NEVER List$` heading.
#  (3) Exactly 1 `^## Rebase Checkpoint Macro$` heading.
#  (4) At least 4 `MANDATORY — READ ENTIRE FILE` occurrences (floor, not ceiling),
#      AND each of the four expected reference filenames appears on a `MANDATORY —
#      READ ENTIRE FILE` line in SKILL.md (step-to-reference binding from design FINDING_7).
#  (5) Three byte-pinned verbosity-suppressed literal strings present in SKILL.md.
#  (6) CI-parity focus-area enum: at least one line in SKILL.md contains the literal
#      `code-quality / risk-integration / correctness / architecture` AND that same
#      line also contains `security`. Mirrors .github/workflows/ci.yaml L121/L125
#      (agent-sync job's UNQUOTED_FILES check). The single-line same-line pattern
#      prevents a false-pass when the five tokens appear in unrelated prose blocks
#      (e.g., the NEVER List) but the actual Cursor/Codex quick-review prompt strings
#      regress. Design FINDING_2.
#  (7) Four `skills/implement/references/*.md` files exist with expected names.
#  (8) Each reference/*.md contains `**Consumer**:`, `**Contract**:`, `**When to load**:`
#      header lines.
#  (9) Zero occurrences of `see Step N below` / `see Step N above` patterns inside any
#      references/*.md — progressive-disclosure invariant (references must not
#      back-reference parent SKILL.md step numbers with direction words).
#
# Exit 0 on pass, exit 1 on any assertion failure.
# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/implement/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/implement/references"

expected_refs=(
  "bump-verification.md"
  "conflict-resolution.md"
  "pr-body-template.md"
  "rebase-rebump-subprocedure.md"
)

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$SKILL_MD" ]] || fail "skills/implement/SKILL.md missing: $SKILL_MD"
[[ -d "$REFS_DIR" ]] || fail "skills/implement/references/ missing: $REFS_DIR"

# ---------------------------------------------------------------------------
# (1) Exactly one `^## Load-Bearing Invariants$` heading.
# ---------------------------------------------------------------------------
count=$(grep -c '^## Load-Bearing Invariants$' "$SKILL_MD" || true)
[[ "$count" == "1" ]] \
  || fail "(1) expected exactly 1 '^## Load-Bearing Invariants$' heading in SKILL.md, found $count"

# ---------------------------------------------------------------------------
# (2) Exactly one `^## NEVER List$` heading.
# ---------------------------------------------------------------------------
count=$(grep -c '^## NEVER List$' "$SKILL_MD" || true)
[[ "$count" == "1" ]] \
  || fail "(2) expected exactly 1 '^## NEVER List$' heading in SKILL.md, found $count"

# ---------------------------------------------------------------------------
# (3) Exactly one `^## Rebase Checkpoint Macro$` heading.
# ---------------------------------------------------------------------------
count=$(grep -c '^## Rebase Checkpoint Macro$' "$SKILL_MD" || true)
[[ "$count" == "1" ]] \
  || fail "(3) expected exactly 1 '^## Rebase Checkpoint Macro$' heading in SKILL.md, found $count"

# ---------------------------------------------------------------------------
# (4) MANDATORY — READ ENTIRE FILE: at least 4 occurrences AND each expected
#     reference filename appears on a MANDATORY line (step-to-reference binding).
# ---------------------------------------------------------------------------
# Use `|| true` to keep set -e + pipefail from aborting before the fail() diagnostic
# when there are zero matches (grep -o exits 1 on no match, which propagates via pipefail).
occurrences=$(grep -o 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" 2>/dev/null | wc -l | tr -d ' ' || true)
if ! [[ "$occurrences" =~ ^[0-9]+$ ]] || (( occurrences < 4 )); then
  fail "(4) expected at least 4 'MANDATORY — READ ENTIRE FILE' occurrences in SKILL.md, found ${occurrences:-0}"
fi

# Step-to-reference binding: each expected reference filename must appear on a
# MANDATORY line in SKILL.md. Isolate MANDATORY lines first, then do a fixed-string
# match against the filename so `.` in the filename is treated literally (not as ERE
# "any character", which would false-pass on corrupted pointers like `pr-body-templateXmd`).
mandatory_lines=$(grep 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" || true)
for ref in "${expected_refs[@]}"; do
  printf '%s\n' "$mandatory_lines" | grep -Fq "$ref" \
    || fail "(4) no 'MANDATORY — READ ENTIRE FILE' line in SKILL.md references '$ref' — step-to-reference binding broken"
done

# ---------------------------------------------------------------------------
# (5) Three byte-pinned verbosity-suppressed literal strings.
# ---------------------------------------------------------------------------
verbosity_literals=(
  '⏩ 1.m: design plan | update main — already at latest'
  '⏩ 1.r: design plan | rebase — already pushed'
  '⏩ 1.r: design plan | rebase — already at latest main'
)
for lit in "${verbosity_literals[@]}"; do
  grep -Fq "$lit" "$SKILL_MD" \
    || fail "(5) SKILL.md lost byte-pinned verbosity literal: $lit"
done

# ---------------------------------------------------------------------------
# (6) CI-parity focus-area enum check.
#     .github/workflows/ci.yaml L121/L125 (agent-sync job's UNQUOTED_FILES loop):
#       grep -n 'code-quality / risk-integration / correctness / architecture' "$f"
#       then checks that each matching line also contains 'security'.
#     Mirror that here: at least one line must match the enum AND contain 'security'.
# ---------------------------------------------------------------------------
enum_hits=$(grep -n 'code-quality / risk-integration / correctness / architecture' "$SKILL_MD" || true)
[[ -n "$enum_hits" ]] \
  || fail "(6) SKILL.md lacks the unquoted slash-separated focus-area enum ('code-quality / risk-integration / correctness / architecture') — CI's agent-sync guard would fail"

# Mirror CI's per-line enforcement: fail immediately on ANY enum line that lacks
# 'security'. The CI loop at .github/workflows/ci.yaml L122-129 iterates every hit
# and fails if any lacks 'security'. A simple "first match wins" here would silently
# allow a future enum line without 'security' to pass the harness while CI fails.
while IFS= read -r hit; do
  [[ -z "$hit" ]] && continue
  line_text="${hit#*:}"
  if ! printf '%s\n' "$line_text" | grep -q 'security'; then
    fail "(6) focus-area enum line lacks 'security' on same line — CI's agent-sync guard would fail: $line_text"
  fi
done <<< "$enum_hits"

# ---------------------------------------------------------------------------
# (7) Four expected references/*.md files exist.
# ---------------------------------------------------------------------------
for ref in "${expected_refs[@]}"; do
  [[ -f "$REFS_DIR/$ref" ]] \
    || fail "(7) expected reference file missing: skills/implement/references/$ref"
done

# ---------------------------------------------------------------------------
# (8) Each reference/*.md contains the Consumer/Contract/When-to-load header triplet.
# ---------------------------------------------------------------------------
contract_headers=(
  '**Consumer**:'
  '**Contract**:'
  '**When to load**:'
)
for ref in "${expected_refs[@]}"; do
  for hdr in "${contract_headers[@]}"; do
    grep -Fq "$hdr" "$REFS_DIR/$ref" \
      || fail "(8) references/$ref lacks '$hdr' header"
  done
done

# ---------------------------------------------------------------------------
# (9) Zero 'see Step N below' / 'see Step N above' patterns in any references/*.md.
#     Pattern is narrow: requires both a step number AND a direction word (below|above).
#     Permits legitimate cross-refs like 'see Step 8' with no direction word.
#     Case-insensitive: catches sentence-initial 'See Step 8 below' variants.
#     The step-number token is `[0-9][0-9a-z.]*` so bare digits (`8`), letter-suffix
#     forms (`9a`), and dotted substep forms (`9a.1`, `3c.2`) are all caught — matching
#     /implement's dotted substep numbering (closes #253).
#     Scans every *.md under references/ (not just the four expected refs) so new
#     reference files added in the future are covered automatically — the contract
#     documented in the header and AGENTS.md says "references/*.md" generally.
# ---------------------------------------------------------------------------
shopt -s nullglob
ref_files=( "$REFS_DIR"/*.md )
shopt -u nullglob
[[ "${#ref_files[@]}" -gt 0 ]] \
  || fail "(9) no .md files found under $REFS_DIR — cannot validate the 'see Step N below|above' invariant"

match_files=""
for ref_path in "${ref_files[@]}"; do
  if grep -qiE 'see Step [0-9][0-9a-z.]* (below|above)' "$ref_path"; then
    match_files="$match_files $(basename "$ref_path")"
  fi
done
if [[ -n "$match_files" ]]; then
  fail "(9) found forbidden 'see Step N below|above' patterns (case-insensitive) in:$match_files"
fi

echo "PASS: test-implement-structure.sh — all 9 structural invariants hold"
exit 0
