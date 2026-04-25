#!/bin/bash
# test-eval-set-structure.sh — Structural regression harness for the
# /research evaluation set + harness (closes #419).
#
# Asserts:
#   1. skills/research/references/eval-set.md exists.
#   2. eval-set.md opens with the Consumer/Contract/When-to-load triplet
#      in the first 20 lines (mirrors test-research-structure.sh's stricter
#      /research-local layering).
#   3. eval-set.md declares >= 20 entries via `### eval-<N>:` headings.
#   4. All five categories appear at least once: lookup, architecture,
#      external-comparison, risk-assessment, feasibility.
#   5. Every entry has all six required fields: question, category,
#      expected_provenance_count, expected_keywords, notes (the id is in
#      the heading itself).
#   6. At least two entries are flagged ADVERSARIAL in their notes —
#      one targeting fictitious-mechanism, one targeting data-absence.
#   7. eval-baseline.json exists, parses as JSON, and has the required
#      schema keys (version, scale, entries).
#   8. The harness scripts/eval-research.sh contains the Anthropic-blog
#      citation literal — pinned so a future edit cannot drop the source
#      attribution silently.
#   9. The harness self-test (`bash scripts/eval-research.sh --smoke-test`)
#      exits 0 — covers the schema parser end-to-end.
#
# Exit 0 on pass, exit 1 on any failure.
#
# Wired into the Makefile as a STANDALONE `test-eval-set-structure`
# target — NOT a `test-harnesses` prerequisite, mirroring the
# `halt-rate-probe` precedent. The harness it tests (`eval-research.sh`)
# is opt-in operator instrumentation, not a CI gate; this structural
# test runs cheaply (no API cost) and could in principle move into the
# lint path, but is kept standalone for symmetry with the runtime harness.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
EVAL_SET="$REPO_ROOT/skills/research/references/eval-set.md"
EVAL_BASELINE="$REPO_ROOT/skills/research/references/eval-baseline.json"
HARNESS="$REPO_ROOT/scripts/eval-research.sh"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Check 1: eval-set.md exists.
[[ -f "$EVAL_SET" ]] || fail "skills/research/references/eval-set.md missing"

# Check 2: Consumer/Contract/When-to-load triplet anchored in first 20 lines.
header_patterns=(
  '^\*\*Consumer\*\*:'
  '^\*\*Contract\*\*:'
  '^\*\*When to load\*\*:'
)
for pattern in "${header_patterns[@]}"; do
  head -n 20 "$EVAL_SET" | grep -Eq "$pattern" \
    || fail "skills/research/references/eval-set.md must open with anchored header matching '$pattern' in the first 20 lines"
done

# Check 3: >= 20 entries.
entry_count=$(grep -cE '^### eval-[0-9]+:' "$EVAL_SET")
if (( entry_count < 20 )); then
  fail "eval-set.md has $entry_count entries; need at least 20"
fi

# Check 4: All five categories present at least once.
required_categories=(lookup architecture external-comparison risk-assessment feasibility)
for cat in "${required_categories[@]}"; do
  if ! grep -qE "^- \*\*category\*\*:[[:space:]]+${cat}\$" "$EVAL_SET"; then
    fail "eval-set.md missing entries from required category: $cat"
  fi
done

# Check 5: Every entry has all six required fields. Walk entry blocks via awk.
missing_fields=$(awk '
  function check_block() {
    if (id == "") return
    miss = ""
    if (!has_q)    miss = miss "question "
    if (!has_cat)  miss = miss "category "
    if (!has_prov) miss = miss "expected_provenance_count "
    if (!has_kw)   miss = miss "expected_keywords "
    if (!has_n)    miss = miss "notes "
    if (miss != "") printf "%s: missing %s\n", id, miss
  }
  /^### eval-[0-9]+:/ {
    check_block()
    id = $0
    has_q = 0; has_cat = 0; has_prov = 0; has_kw = 0; has_n = 0
    next
  }
  /^- \*\*question\*\*:/                     { has_q = 1 }
  /^- \*\*category\*\*:/                     { has_cat = 1 }
  /^- \*\*expected_provenance_count\*\*:/    { has_prov = 1 }
  /^- \*\*expected_keywords\*\*:/            { has_kw = 1 }
  /^- \*\*notes\*\*:/                        { has_n = 1 }
  END { check_block() }
' "$EVAL_SET")
if [[ -n "$missing_fields" ]]; then
  fail "eval-set.md entries with missing fields:\n$missing_fields"
fi

# Check 6: >= 2 adversarial entries.
adv_count=$(grep -ciE '^- \*\*notes\*\*:.*adversarial' "$EVAL_SET" || printf '0')
if (( adv_count < 2 )); then
  fail "eval-set.md has $adv_count entries flagged ADVERSARIAL in notes; need at least 2"
fi

# Check 7: eval-baseline.json parses and has required keys.
[[ -f "$EVAL_BASELINE" ]] || fail "skills/research/references/eval-baseline.json missing"
if command -v jq >/dev/null 2>&1; then
  jq -e '.version and .scale and (.entries | type == "array")' "$EVAL_BASELINE" >/dev/null 2>&1 \
    || fail "eval-baseline.json missing required keys (version, scale, entries) or not valid JSON"
else
  for key in version scale entries; do
    grep -q "\"$key\"" "$EVAL_BASELINE" \
      || fail "eval-baseline.json missing required key: $key (jq unavailable; using grep fallback)"
  done
fi

# Check 8: Harness contains the Anthropic-blog citation literal.
[[ -f "$HARNESS" ]] || fail "scripts/eval-research.sh missing"
grep -Fq "anthropic.com/engineering/built-multi-agent-research-system" "$HARNESS" \
  || fail "scripts/eval-research.sh missing Anthropic blog citation literal (anthropic.com/engineering/built-multi-agent-research-system)"

# Check 9: Smoke-test invocation. Harness must exit 0 with no API call.
if ! bash "$HARNESS" --smoke-test >/dev/null 2>&1; then
  fail "bash scripts/eval-research.sh --smoke-test exited non-zero (schema parser self-test failed)"
fi

echo "PASS: test-eval-set-structure.sh — eval-set.md and eval-research.sh structural invariants hold"
exit 0
