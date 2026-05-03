#!/bin/bash
# Structural regression test for /implement Rebase Checkpoint Macro refactor (closes #232).
# Asserts that skills/implement/SKILL.md preserves the macro's structural invariants:
#  (A) Exactly one `## Rebase Checkpoint Macro` header.
#  (B) Four canonical Call-site registry rows present (1.r/4.r/7.r/7a.r with their short-names).
#  (C) Exactly four `Apply the Rebase Checkpoint Macro with ...` invocation lines matching canonical pairs.
#  (E) Step 7.r section retains `FILES_CHANGED=true` prose above the macro invocation.
#  (F) Macro header line number is BETWEEN `### Verbosity Control` and `## Step 0`.
#  (G) Macro section body contains the rebase-push.sh invocation and the bail-on-failure line.
#  (H) Exactly 1 `rebase-push.sh --no-push --skip-if-pushed` occurrence (only the macro M2 uses
#      that flag combo; Step 1.m, Step 8b, and the Rebase + Re-bump Sub-procedure use `--no-push`
#      alone). Also asserts the 7.r Apply invocation is inside the Step 7 slice and that all
#      three `--no-push`-only call sites (Step 1.m + Step 8b + Sub-procedure) remain.
#
# Exit 0 on pass, exit 1 on any assertion failure.
# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals — backticks and ${...} must not expand
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/implement/SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$SKILL_MD" ]] || fail "skills/implement/SKILL.md missing: $SKILL_MD"

# ---------------------------------------------------------------------------
# (A) Exactly one `## Rebase Checkpoint Macro` header.
# ---------------------------------------------------------------------------
macro_header_count=$(grep -c '^## Rebase Checkpoint Macro$' "$SKILL_MD" || true)
[[ "$macro_header_count" == "1" ]] \
  || fail "(A) expected exactly one '## Rebase Checkpoint Macro' header, found $macro_header_count"

macro_header_line=$(grep -n '^## Rebase Checkpoint Macro$' "$SKILL_MD" | head -1 | cut -d: -f1)

# ---------------------------------------------------------------------------
# (F) Placement: macro header between ### Verbosity Control and ## Step 0.
# ---------------------------------------------------------------------------
verbosity_line=$(grep -n '^### Verbosity Control$' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
[[ -n "$verbosity_line" ]] || fail "(F) SKILL.md lacks '### Verbosity Control' header"

step0_line=$(grep -n '^## Step 0' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
[[ -n "$step0_line" ]] || fail "(F) SKILL.md lacks '## Step 0' heading"

if (( macro_header_line <= verbosity_line )); then
  fail "(F) macro header (line $macro_header_line) must appear AFTER '### Verbosity Control' (line $verbosity_line)"
fi
if (( macro_header_line >= step0_line )); then
  fail "(F) macro header (line $macro_header_line) must appear BEFORE '## Step 0' (line $step0_line)"
fi

# ---------------------------------------------------------------------------
# Compute macro section line range: from macro_header_line to the next top-level
# '## ' heading (Step 0). Inclusive start, exclusive end.
# ---------------------------------------------------------------------------
macro_section_start=$macro_header_line
macro_section_end=$step0_line

# ---------------------------------------------------------------------------
# (B) Call-site registry: four canonical rows present in macro section.
# ---------------------------------------------------------------------------
registry_rows=(
  '| 1.r  | `1.r`           | `design plan`    |'
  '| 4.r  | `4.r`           | `commit (impl)`  |'
  '| 7.r  | `7.r`           | `commit (review)`|'
  '| 7a.r | `7a.r`          | `code flow`      |'
)
for row in "${registry_rows[@]}"; do
  sed -n "${macro_section_start},${macro_section_end}p" "$SKILL_MD" | grep -Fq "$row" \
    || fail "(B) macro Call-site registry missing row: $row"
done

# ---------------------------------------------------------------------------
# (C) Exactly four `Apply the Rebase Checkpoint Macro ...` invocation lines in
# the entire SKILL.md body, each matching a canonical pair. Count and verify.
# ---------------------------------------------------------------------------
invocation_count=$(grep -cE '^Apply the Rebase Checkpoint Macro with ' "$SKILL_MD" || true)
[[ "$invocation_count" == "4" ]] \
  || fail "(C) expected exactly 4 'Apply the Rebase Checkpoint Macro with ...' invocations, found $invocation_count"

canonical_invocations=(
  'Apply the Rebase Checkpoint Macro with `<step-prefix>=1.r` and `<short-name>=design plan`.'
  'Apply the Rebase Checkpoint Macro with `<step-prefix>=4.r` and `<short-name>=commit (impl)`.'
  'Apply the Rebase Checkpoint Macro with `<step-prefix>=7.r` and `<short-name>=commit (review)`.'
  'Apply the Rebase Checkpoint Macro with `<step-prefix>=7a.r` and `<short-name>=code flow`.'
)
for inv in "${canonical_invocations[@]}"; do
  grep -Fq "$inv" "$SKILL_MD" \
    || fail "(C) missing canonical invocation: $inv"
done

# ---------------------------------------------------------------------------
# (E) Step 7.r section retains `FILES_CHANGED=true` prose above the invocation.
#     The 7.r macro invocation must appear within the Step 7 slice, AFTER a
#     line containing 'FILES_CHANGED=true' (same slice), and BEFORE '## Step 7a'.
# ---------------------------------------------------------------------------
step7_header_line=$(grep -n '^## Step 7 —' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
[[ -n "$step7_header_line" ]] || fail "(E) SKILL.md lacks '## Step 7 —' heading"

step7a_header_line=$(grep -n '^## Step 7a' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
[[ -n "$step7a_header_line" ]] || fail "(E) SKILL.md lacks '## Step 7a' heading"

# Find the 7.r invocation line (should be exactly one in the 7.r slice).
invoke_7r_line=$(grep -nF 'Apply the Rebase Checkpoint Macro with `<step-prefix>=7.r`' "$SKILL_MD" | head -1 | cut -d: -f1 || true)
[[ -n "$invoke_7r_line" ]] || fail "(E) 7.r macro invocation not found"

if (( invoke_7r_line <= step7_header_line )); then
  fail "(E) 7.r invocation (line $invoke_7r_line) must be AFTER '## Step 7 —' (line $step7_header_line)"
fi
if (( invoke_7r_line >= step7a_header_line )); then
  fail "(E) 7.r invocation (line $invoke_7r_line) must be BEFORE '## Step 7a' (line $step7a_header_line)"
fi

# Find a line containing FILES_CHANGED=true within the Step 7 slice that is ABOVE the 7.r invocation.
files_changed_line=$(sed -n "${step7_header_line},$((invoke_7r_line - 1))p" "$SKILL_MD" | grep -n 'FILES_CHANGED=true' | head -1 | cut -d: -f1 || true)
[[ -n "$files_changed_line" ]] \
  || fail "(E) Step 7.r: 'FILES_CHANGED=true' guard prose must appear above the 7.r macro invocation"

# ---------------------------------------------------------------------------
# (G) Macro section body contains rebase-push.sh invocation and bail line.
# ---------------------------------------------------------------------------
sed -n "${macro_section_start},${macro_section_end}p" "$SKILL_MD" | grep -Fq '${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed' \
  || fail "(G) macro body lacks 'rebase-push.sh --no-push --skip-if-pushed' invocation"
sed -n "${macro_section_start},${macro_section_end}p" "$SKILL_MD" | grep -Fq '**⚠ Rebase onto main failed. Bailing to cleanup.**' \
  || fail "(G) macro body lacks '**⚠ Rebase onto main failed. Bailing to cleanup.**' bail line"

# ---------------------------------------------------------------------------
# (H) Exactly 1 occurrence of 'rebase-push.sh --no-push --skip-if-pushed' (macro M2 only).
#     Before the refactor, the four blocks at 1.r/4.r/7.r/7a.r each had this exact flag combo.
#     After the refactor, only the macro has it — so a residual inline block would push the
#     count to 2+ and fail this assertion. Step 1.m, Step 8b, and Sub-procedure use
#     `--no-push` alone (see the secondary sanity check below for the three-site count).
# ---------------------------------------------------------------------------
rebase_push_skip_count=$(grep -cF '${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed' "$SKILL_MD" || true)
[[ "$rebase_push_skip_count" == "1" ]] \
  || fail "(H) expected exactly 1 'rebase-push.sh --no-push --skip-if-pushed' occurrence (macro M2 only), found $rebase_push_skip_count — residual inline rebase block may have survived the refactor"

# Sanity check: all three non-macro --no-push call sites must still exist:
#   - Step 1.m in SKILL.md (pre-Step-1 main freshness)
#   - Step 8b in SKILL.md (pre-PR-creation freshness, issue #818)
#   - Rebase + Re-bump Sub-procedure in references/rebase-rebump-subprocedure.md
# Count lines ending with 'rebase-push.sh --no-push' across both files (indentation tolerated;
# --skip-if-pushed excluded because its lines do NOT end with --no-push). Expect exactly 3 —
# one per call site. This catches accidental removal of ANY site.
SUBPROC_MD="$REPO_ROOT/skills/implement/references/rebase-rebump-subprocedure.md"
[[ -f "$SUBPROC_MD" ]] || fail "(H) references/rebase-rebump-subprocedure.md missing: $SUBPROC_MD"
no_push_only_count=$(grep -chE 'rebase-push\.sh --no-push$' "$SKILL_MD" "$SUBPROC_MD" | awk '{s+=$1} END {print s+0}')
[[ "$no_push_only_count" == "3" ]] \
  || fail "(H) expected exactly 3 'rebase-push.sh --no-push' (without --skip-if-pushed) call sites across SKILL.md (Step 1.m + Step 8b) + references/rebase-rebump-subprocedure.md, found $no_push_only_count — Step 1.m, Step 8b, or Rebase + Re-bump Sub-procedure was accidentally altered"

echo "PASS: test-implement-rebase-macro.sh — all 7 structural invariants hold (A, B, C, E, F, G, H)"
exit 0
