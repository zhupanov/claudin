#!/bin/bash
# Cross-skill references/*.md header-triplet regression guard (closes #308)
# plus Contract-field line-range rejection (closes #322).
#
# Scans every `skills/*/references/*.md` and asserts each file contains the
# Consumer / Contract / When-to-load header triplet required by the
# progressive-disclosure reference contract, AND that the Contract paragraph
# carries no `L\d+-\d+` line-range citation — the stale-citation drift
# pattern v5.2.7 eradicated and #322 tracked as a regression guard.
#
# Header match is ANCHORED (line-start) to avoid false-passing on prose or
# code-fenced examples that happen to mention `**Consumer**:` inside a body
# paragraph or a literal-text block. The three required patterns are:
#   ^\*\*Consumer\*\*:
#   ^\*\*Contract\*\*:
#   ^\*\*When to load\*\*:
#
# Glob is deliberately flat: `skills/*/references/*.md`. Nested paths such as
# `skills/<skill>/references/<subdir>/*.md` are NOT scanned; see the sibling
# contract `scripts/test-references-headers.md` for the scope rule. The flat
# glob mirrors the legacy assertion (8) scope that formerly lived in
# `scripts/test-implement-structure.sh` (pre-#308, implement-only) but now
# applies repo-wide.
#
# Relationship to sibling harnesses:
#   - `scripts/test-implement-structure.sh` owns /implement-specific topology
#     (top-level headings, MANDATORY binding, CI-parity enum, no-`see Step N
#     below|above` invariant) — no longer owns the Consumer/Contract/When-to-
#     load triplet as of #308.
#   - `scripts/test-research-structure.sh` retains a STRICTER /research-local
#     check that the triplet appears in the first 20 lines (opens-with), on
#     top of the global presence check enforced here.
#
# Exits 0 on pass, 1 on any assertion failure. Fails closed on empty glob.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILLS_DIR="$REPO_ROOT/skills"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -d "$SKILLS_DIR" ]] || fail "skills/ directory missing: $SKILLS_DIR"

# Collect every skills/*/references/*.md via flat glob (no nested descent).
shopt -s nullglob
ref_files=( "$SKILLS_DIR"/*/references/*.md )
shopt -u nullglob

(( ${#ref_files[@]} > 0 )) \
  || fail "no skills/*/references/*.md files found — harness would silently pass without this guard"

# Required headers, matched at line-start (anchored) to avoid false-positives
# on prose or fenced-code examples. Patterns are grep -E (ERE) with '*'
# escaped literally.
header_patterns=(
  '^\*\*Consumer\*\*:'
  '^\*\*Contract\*\*:'
  '^\*\*When to load\*\*:'
)

for ref_path in "${ref_files[@]}"; do
  # Path relative to the repo root for cleaner failure messages.
  rel_path="${ref_path#"$REPO_ROOT"/}"
  for pattern in "${header_patterns[@]}"; do
    grep -Eq "$pattern" "$ref_path" \
      || fail "$rel_path lacks required anchored header matching '$pattern'"
  done

  # Contract-field line-range rejection (closes #322). Stale `L<digits>-<digits>`
  # citations inside Contract paragraphs drift silently when source-of-truth
  # files are edited later; v5.2.7 replaced such citations across the 4
  # implement/references/*.md files with range-free descriptions, and this
  # guard prevents regression. See scripts/test-references-headers.md for the
  # full contract. Both ASCII hyphen and en-dash are matched because GitHub
  # markdown rendering occasionally substitutes the latter.
  contract_block=$(awk '/^\*\*Contract\*\*:/{flag=1} flag{print} flag && /^$/{exit}' "$ref_path")
  if [[ -n "$contract_block" ]]; then
    stale_hit=$(grep -En 'L[0-9]+[-–][0-9]+' <<< "$contract_block" || true)
    if [[ -n "$stale_hit" ]]; then
      fail "$rel_path: Contract field contains stale line-range citation — $stale_hit (closes #322: use range-free descriptions)"
    fi
  fi
done

echo "PASS: test-references-headers.sh — triplet + no-stale-line-range verified across ${#ref_files[@]} skills/*/references/*.md files"
exit 0
