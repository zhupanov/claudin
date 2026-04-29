#!/bin/bash
# Structural regression test for /research skill progressive-disclosure refactor.
# Asserts that the skill's 5-reference symmetric topology survives edits:
#  - skills/research/references/research-phase.md, validation-phase.md,
#    adjudication-phase.md, citation-validation-phase.md, and critique-loop-phase.md
#    all exist
#  - Each appears on a 'MANDATORY — READ ENTIRE FILE' line in skills/research/SKILL.md,
#    and the SAME line also carries reciprocal 'Do NOT load <each-other-reference>'
#    guards naming ALL FOUR other references (line-scoped so a future edit cannot
#    split the MANDATORY and the Do-NOT-load directives into different paragraphs
#    without the harness catching the drift). Order-agnostic: the harness uses
#    per-substring grep loops so minor reordering of unrelated lines does NOT
#    break the check (presence-not-order).
#  - Each references/*.md OPENS WITH the Consumer / Contract / When-to-load header triplet
#    in the first 20 lines (a /research-local tightening layered on top of the cross-skill
#    presence check enforced by scripts/test-references-headers.sh — matches the sibling
#    contract's literal 'opens with' promise)
#  - RESEARCH_PROMPT_BASELINE literal (and by substring `RESEARCH_PROMPT`, all four angle
#    prompt names: RESEARCH_PROMPT_ARCH / _EDGE / _EXT / _SEC) appear in research-phase.md
#    (substring pin for byte-drift detection — `grep -F "RESEARCH_PROMPT"` matches every
#    legal post-#508 identifier, since BASELINE and the four angle names all carry it as a
#    substring)
#  - reviewer XML wrapper tags (<reviewer_research_question>, <reviewer_research_findings>)
#    appear in validation-phase.md (byte pin for prompt-injection hardening)
#  - render-lane-status.sh + lane-status.txt pins (#421)
#  - --scale=quick|standard|deep value-flag surface (#418): flag enum + 4 named angle
#    prompt identifiers + literal quick-mode skip breadcrumb + abort-on-invalid + flag
#    independence statement + ### Standard byte-drift pins on existing filename literals
#  - --substantive-validation flag wiring + STATUS=NOT_SUBSTANTIVE token mapping
#    (#416 Phase 3 of umbrella #413, substantive content validator)
#  - adjudication-phase.md mentions both build-research-adjudication-ballot.sh and
#    run-research-adjudication.sh (byte pin for the ballot-builder + coordinator wiring) (#424)
#  - validation-phase.md '## Finalize Validation' section pins (#534): the revision
#    subagent invocation pattern + revision-raw.txt Write capture (38a), atomic
#    rewrite of research-report.txt via mktemp + mv (38b), and the 5 body markers
#    enumerated in REVISION_PROMPT (38c — FINDING_1's marker contract)
#
# Exit 0 on pass, exit 1 on any assertion failure.
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/research/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/research/references"
RESEARCH_MD="$REFS_DIR/research-phase.md"
VALIDATION_MD="$REFS_DIR/validation-phase.md"
ADJUDICATION_MD="$REFS_DIR/adjudication-phase.md"
CITATION_MD="$REFS_DIR/citation-validation-phase.md"
CRITIQUE_LOOP_MD="$REFS_DIR/critique-loop-phase.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

# Check 1: SKILL.md exists.
[[ -f "$SKILL_MD" ]] || fail "SKILL.md missing: $SKILL_MD"

# Check 2: All five reference files exist.
[[ -f "$RESEARCH_MD" ]]      || fail "references/research-phase.md missing: $RESEARCH_MD"
[[ -f "$VALIDATION_MD" ]]    || fail "references/validation-phase.md missing: $VALIDATION_MD"
[[ -f "$ADJUDICATION_MD" ]]  || fail "references/adjudication-phase.md missing: $ADJUDICATION_MD"
[[ -f "$CITATION_MD" ]]      || fail "references/citation-validation-phase.md missing: $CITATION_MD"
[[ -f "$CRITIQUE_LOOP_MD" ]] || fail "references/critique-loop-phase.md missing: $CRITIQUE_LOOP_MD"

# Check 3: Each reference file is named on a MANDATORY — READ ENTIRE FILE line in SKILL.md
#          AND that same line carries reciprocal 'Do NOT load <each-other>' guards naming
#          ALL FOUR other references. Line-scoped by construction so a future edit that
#          splits the directive across lines fails. Order-agnostic via per-substring grep
#          loops: each MANDATORY line is extracted, then asserted to contain ALL FOUR
#          'Do NOT load <each-other>' substrings (presence-not-order — minor reordering of
#          unrelated lines must NOT break the check).
#
# Procedure per reference X:
#   1. Find the line in SKILL.md that contains 'MANDATORY — READ ENTIRE FILE' AND <X>.
#   2. For each of the OTHER four references Y, assert the line ALSO contains
#      'Do NOT load' followed by <Y> somewhere later on the same line.
check_mandatory_topology() {
    local target="$1"  # filename basename of the reference being asserted
    shift
    local -a others=("$@")  # the other four filenames
    # Find the canonical MANDATORY line: it begins with the literal '**MANDATORY'
    # token and names the target reference EARLIER in the line than any 'Do NOT load'
    # clause. The reference-of-record for the line is the one named between the
    # MANDATORY directive and the first 'Do NOT load' clause.
    local target_re
    target_re=$(printf '%s' "$target" | sed 's/\./\\./g')
    local line
    # shellcheck disable=SC1087
    line=$(grep -E "MANDATORY — READ ENTIRE FILE[^\$]*${target_re}[^\$]*Do NOT load" "$SKILL_MD" \
          | grep -E "MANDATORY — READ ENTIRE FILE.*${target_re}.*Do NOT load" \
          | head -n 1 || true)
    # Filter: only the line where $target appears BEFORE the first 'Do NOT load'
    # token is the reference-of-record line.
    if [[ -n "$line" ]]; then
        local prefix
        prefix="${line%%Do NOT load*}"
        if ! printf '%s' "$prefix" | grep -Fq "$target"; then
            line=""
        fi
    fi
    # If the head-line filter dropped the candidate, do a second pass over ALL
    # MANDATORY lines and pick the one whose pre-'Do NOT load' prefix names $target.
    if [[ -z "$line" ]]; then
        local candidate
        while IFS= read -r candidate; do
            local cand_prefix="${candidate%%Do NOT load*}"
            if printf '%s' "$cand_prefix" | grep -Fq "$target"; then
                line="$candidate"
                break
            fi
        done < <(grep -E "MANDATORY — READ ENTIRE FILE" "$SKILL_MD" || true)
    fi
    [[ -n "$line" ]] \
      || fail "SKILL.md must contain a 'MANDATORY — READ ENTIRE FILE' line naming '$target' as the reference-of-record (before the first 'Do NOT load' clause)"
    local other other_re
    for other in "${others[@]}"; do
        other_re=$(printf '%s' "$other" | sed 's/\./\\./g')
        printf '%s\n' "$line" | grep -qE "Do NOT load.*$other_re" \
          || fail "SKILL.md MANDATORY line for '$target' must also contain a 'Do NOT load $other' clause on the same line (5-reference symmetric topology — #517)"
    done
}

check_mandatory_topology "research-phase.md"            "validation-phase.md"   "adjudication-phase.md" "citation-validation-phase.md" "critique-loop-phase.md"
check_mandatory_topology "validation-phase.md"          "research-phase.md"     "adjudication-phase.md" "citation-validation-phase.md" "critique-loop-phase.md"
check_mandatory_topology "adjudication-phase.md"        "research-phase.md"     "validation-phase.md"   "citation-validation-phase.md" "critique-loop-phase.md"
check_mandatory_topology "citation-validation-phase.md" "research-phase.md"     "validation-phase.md"   "adjudication-phase.md"        "critique-loop-phase.md"
check_mandatory_topology "critique-loop-phase.md"       "research-phase.md"     "validation-phase.md"   "adjudication-phase.md"        "citation-validation-phase.md"

# Check 4: Each references/*.md opens with the Consumer / Contract / When-to-load header
#          triplet in the first 20 lines. The sibling contract says "opens with" — enforce that
#          literally, so future edits cannot bury the triplet mid-file without the harness
#          catching the drift. Patterns are anchored at line-start (same shape as the global
#          scripts/test-references-headers.sh harness) so the /research-local tightening
#          actually layers on top of the cross-skill anchored presence check — a prose line
#          like `see **Consumer**: below` in the head region must NOT satisfy the check.
contract_header_patterns=(
  '^\*\*Consumer\*\*:'
  '^\*\*Contract\*\*:'
  '^\*\*When to load\*\*:'
)
for ref_path in "$RESEARCH_MD" "$VALIDATION_MD" "$ADJUDICATION_MD" "$CITATION_MD" "$CRITIQUE_LOOP_MD"; do
  for pattern in "${contract_header_patterns[@]}"; do
    head -n 20 "$ref_path" | grep -Eq "$pattern" \
      || fail "references/$(basename "$ref_path") must open with anchored header matching '$pattern' in the first 20 lines"
  done
done

# Check 5: RESEARCH_PROMPT_BASELINE literal (substring pin for byte-drift detection).
# `grep -F "RESEARCH_PROMPT"` matches every legal post-#508 identifier, since BASELINE and
# the four angle prompt names (ARCH/EDGE/EXT/SEC) all carry "RESEARCH_PROMPT" as a substring.
grep -Fq "RESEARCH_PROMPT" "$RESEARCH_MD" \
  || fail "references/research-phase.md lacks RESEARCH_PROMPT_BASELINE / RESEARCH_PROMPT_ARCH / _EDGE / _EXT / _SEC identifier"
# Pin the opening 'You are researching a codebase' substring of the prompt body itself
# (still appears in BASELINE and all four angle prompt bodies).
grep -Fq "You are researching a codebase to answer this question" "$RESEARCH_MD" \
  || fail "references/research-phase.md lacks RESEARCH_PROMPT_BASELINE body opening substring 'You are researching a codebase to answer this question'"

# Check 6: Validation reviewer XML wrapper tags (byte pin for prompt-injection hardening).
grep -Fq "<reviewer_research_question>" "$VALIDATION_MD" \
  || fail "references/validation-phase.md lacks '<reviewer_research_question>' XML wrapper tag"
grep -Fq "<reviewer_research_findings>" "$VALIDATION_MD" \
  || fail "references/validation-phase.md lacks '<reviewer_research_findings>' XML wrapper tag"

# Check 7: SKILL.md Step 3 must invoke render-lane-status.sh (the lane-attribution
# formatter added by #421). Without this pin, a future edit could quietly remove
# the helper invocation and the report header would silently regress to the
# pre-#421 collapsed ✅/❌ shape (or to a hard-coded literal).
grep -Fq "render-lane-status.sh" "$SKILL_MD" \
  || fail "SKILL.md must reference render-lane-status.sh in Step 3 (#421 lane attribution)"

# Check 8: Both phase references must mention lane-status.txt — the on-disk
# KV record they update via surgical phase-local rewrites. Without these pins,
# the orchestrator-side update logic could be silently dropped, leaving the
# render helper to emit stale Step 0b values for runtime-fallback lanes.
grep -Fq "lane-status.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must mention lane-status.txt (#421 RESEARCH_* slice update)"
grep -Fq "lane-status.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must mention lane-status.txt (#421 VALIDATION_* slice update + Step 2 entry propagation)"

# Check 9 (#418): SKILL.md documents the --scale=quick|standard|deep value flag.
# Pin the literal triple so a future edit cannot silently rename or drop a value
# from the enum. Use `-e --` so grep does not interpret the leading '--' as flags.
grep -Fq -e "--scale=quick|standard|deep" "$SKILL_MD" \
  || fail "SKILL.md must document the --scale=quick|standard|deep value flag (#418)"

# Check 10 (#418): research-phase.md defines all four named angle prompts as
# explicit identifiers. These are the data-bearing literals that distinguish
# deep mode from standard mode; their absence means deep mode lost its
# diversified-angle architecture.
for prompt in RESEARCH_PROMPT_ARCH RESEARCH_PROMPT_EDGE RESEARCH_PROMPT_EXT RESEARCH_PROMPT_SEC; do
  grep -Fq "$prompt" "$RESEARCH_MD" \
    || fail "references/research-phase.md must define the named angle prompt '$prompt' (#418 deep mode)"
done

# Check 11 (#418): SKILL.md documents the exact quick-mode skip breadcrumb.
# Pin the literal so the gate cannot silently drop or rephrase the visible
# user signal that validation was intentionally skipped.
grep -Fq -e "⏩ 2: validation — skipped (--scale=quick)" "$SKILL_MD" \
  || fail "SKILL.md must contain the literal quick-mode skip breadcrumb '⏩ 2: validation — skipped (--scale=quick)' (#418)"

# Check 12 (#418, #460): SKILL.md documents abort-on-invalid-value for --scale.
# Pin the full composite error sentence as a single literal so the check
# cannot pass spuriously if only one of two unrelated substrings appears
# (#460: an unrelated `Aborting` elsewhere would otherwise satisfy the prior
# two-grep AND).
grep -Fq -e "must be one of quick|standard|deep (got: foo). Aborting." "$SKILL_MD" \
  || fail "SKILL.md must document abort-on-invalid for --scale (composite literal 'must be one of quick|standard|deep (got: foo). Aborting.' required) (#418, #460)"

# Check 13 (#418 + #424 + #510 + #518 + #522 + #531): SKILL.md flag-independence
# statement is structurally consistent with the flag-bullet block.
#
# Replaces a former 5-flag literal substring pin (which would silently pass on
# any future flag addition that updated the bullet block but not the
# independence statement — issue #531). The new check derives the expected
# "independent" flag set from the flag bullets and asserts set-equality with
# the backticked --flag tokens on the line containing "Flags are independent".
#
# Anchors:
#   - independence statement: a single line in SKILL.md beginning with
#     "Flags are independent" (must occur exactly once).
#   - bullet-block window: from the line AFTER the independence statement
#     until the next ^## H2 heading (currently "## Token telemetry and
#     budget enforcement"). The window is NOT fence-aware — the flag block
#     contains no code fences today; if a future bullet introduces fenced
#     content mentioning "cross-effect", the bullet will be classified as
#     coupled (per the documented contract in scripts/test-research-structure.md).
#   - bullets: lines matching ^- at column 1 inside the window; one bullet
#     record runs from one ^- line until the next ^- line OR end-of-window.
#
# Per-bullet classification:
#   - leading flag: the FIRST backticked span on the bullet's first line
#     (`grep -oE '^- `[^`]+`'`), then strip from `=` or `<` onward via sed
#     to yield the canonical --<name>. Handles value flags
#     (`--scale=quick|standard|deep` -> --scale, `--token-budget=<positive
#     integer>` -> --token-budget) and compound bullets (`--keep-sidecar`
#     AND `--keep-sidecar=<PATH>` -> --keep-sidecar via the FIRST backticked
#     token).
#   - independent vs coupled: case-sensitive substring "cross-effect" in
#     the bullet body marks the flag as coupled (today only --plan, whose
#     bullet documents a --scale cross-effect). All other flags are
#     classified as independent and MUST appear on the independence line.
#
# Two-sided set-equality with separate failure modes naming specific flags:
#   - MISSING: an independent flag absent from the independence line.
#   - STALE: a flag listed on the independence line that is not an
#     independent bullet (either no bullet, or the bullet is coupled).
#
# All sort/comm invocations use LC_ALL=C for deterministic ordering across
# macOS and Linux.
# `|| true` keeps a no-match grep from aborting the script under
# `set -euo pipefail` before the explicit count check below can fail with
# the targeted Check 13 diagnostic.
INDEP_LINES=$(grep -nE '^Flags are independent' "$SKILL_MD" | cut -d: -f1 || true)
INDEP_LINE_COUNT=$(printf '%s' "$INDEP_LINES" | grep -c . || true)
[[ "$INDEP_LINE_COUNT" == "1" ]] \
  || fail "Check 13: SKILL.md must contain exactly one line beginning with 'Flags are independent' (found $INDEP_LINE_COUNT) (#531)"
INDEP_LINE=$INDEP_LINES
INDEP_LINE_TEXT=$(awk -v ln="$INDEP_LINE" 'NR == ln { print; exit }' "$SKILL_MD")

# Extract bullet-block window starting AFTER the independence line, terminating
# on the next ^## H2 heading.
BULLET_WINDOW=$(awk -v start="$INDEP_LINE" 'NR > start && /^## /{exit} NR > start {print}' "$SKILL_MD")

# Slice the window into per-bullet records (one record per ^- bullet).
EXPECTED_INDEP=""
STALE_FROM_BULLETS=""  # Bullets whose canonical flag is coupled (informational; subset of "not independent").
BULLET_COUNT=0
CURRENT_FIRST_LINE=""
CURRENT_BODY=""
process_bullet() {
  local first_line="$1"
  local body="$2"
  [[ -z "$first_line" ]] && return 0
  BULLET_COUNT=$((BULLET_COUNT + 1))
  local leading_token canonical
  # shellcheck disable=SC2016 # backticks are literal markdown — single quotes are correct here
  # `|| true` keeps a no-match grep from aborting the script under
  # `set -euo pipefail` before the explicit emptiness check below can fail
  # with the targeted Check 13 diagnostic.
  leading_token=$(printf '%s\n' "$first_line" | grep -oE '^- `[^`]+`' | head -n 1 || true)
  [[ -n "$leading_token" ]] \
    || fail "Check 13: SKILL.md flag-block bullet has no parseable leading backticked --<flag> token: $first_line (#531)"
  # shellcheck disable=SC2016 # backticks are literal markdown — single quotes are correct here
  canonical=$(printf '%s\n' "$leading_token" | sed -E 's/^- `(--[a-z][a-z0-9-]*)([=<].*)?`.*$/\1/')
  if [[ ! "$canonical" =~ ^--[a-z][a-z0-9-]*$ ]]; then
    fail "Check 13: SKILL.md flag-block bullet leading token '$leading_token' did not canonicalize to a --<name> (got: '$canonical') (#531)"
  fi
  if printf '%s' "$body" | grep -Fq "cross-effect"; then
    STALE_FROM_BULLETS+="$canonical"$'\n'
  else
    EXPECTED_INDEP+="$canonical"$'\n'
  fi
}
while IFS= read -r line; do
  if [[ "$line" =~ ^-\  ]]; then
    process_bullet "$CURRENT_FIRST_LINE" "$CURRENT_BODY"
    CURRENT_FIRST_LINE="$line"
    CURRENT_BODY="$line"$'\n'
  else
    if [[ -n "$CURRENT_FIRST_LINE" ]]; then
      CURRENT_BODY+="$line"$'\n'
    fi
  fi
done <<< "$BULLET_WINDOW"
process_bullet "$CURRENT_FIRST_LINE" "$CURRENT_BODY"

# Sanity floor: at least 4 bullets must be extracted. Catches catastrophic
# extraction failures (anchor missing, window collapsed). Today's SKILL.md has
# 6 flag bullets; floor at 4 leaves headroom for future trimming while still
# detecting parser regressions. Documented as part of the product contract.
[[ "$BULLET_COUNT" -ge 4 ]] \
  || fail "Check 13: SKILL.md flag-block extraction yielded fewer than 4 bullets (got: $BULLET_COUNT) — Check 13 anchors are likely broken or the flag block has been consolidated below the documented contract floor (#531)"

EXPECTED_SORTED=$(printf '%s' "$EXPECTED_INDEP" | grep -v '^$' | LC_ALL=C sort -u || true)
# shellcheck disable=SC2016 # backticks are literal markdown — single quotes are correct here
ACTUAL_SORTED=$(printf '%s' "$INDEP_LINE_TEXT" | grep -oE '`--[a-z][a-z0-9-]*`' | tr -d '`' | LC_ALL=C sort -u || true)

MISSING=$(LC_ALL=C comm -23 <(printf '%s\n' "$EXPECTED_SORTED") <(printf '%s\n' "$ACTUAL_SORTED") | grep -v '^$' || true)
STALE=$(LC_ALL=C comm -13 <(printf '%s\n' "$EXPECTED_SORTED") <(printf '%s\n' "$ACTUAL_SORTED") | grep -v '^$' || true)
EXPECTED_DISPLAY=$(printf '%s' "$EXPECTED_SORTED" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
ACTUAL_DISPLAY=$(printf '%s' "$ACTUAL_SORTED" | tr '\n' ' ' | sed 's/[[:space:]]*$//')

if [[ -n "$MISSING" ]]; then
  MISSING_DISPLAY=$(printf '%s' "$MISSING" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fail "Check 13: SKILL.md independence statement is missing flag(s): $MISSING_DISPLAY. Expected (from bullets): $EXPECTED_DISPLAY. Actual (from independence line): $ACTUAL_DISPLAY. Add the missing flag(s) to the line beginning 'Flags are independent', OR mark the bullet(s) as coupled by adding the literal phrase 'cross-effect' to the bullet body. (#531)"
fi

if [[ -n "$STALE" ]]; then
  STALE_DISPLAY=$(printf '%s' "$STALE" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
  fail "Check 13: SKILL.md independence statement contains stale or non-independent flag(s): $STALE_DISPLAY. Expected (from bullets): $EXPECTED_DISPLAY. Actual (from independence line): $ACTUAL_DISPLAY. Remove the stale flag(s) from the line, OR add a corresponding flag bullet without the 'cross-effect' sentinel. (#531)"
fi

# Check 13b (#522): SKILL.md documents the --interactive boolean flag with its
# pre-planner TTY check. Pin the flag literal in argument-hint, the flag-spec
# bullet, and the resolution rule's TTY error literal so future SKILL.md edits
# cannot silently drop the flag or weaken the TTY guard.
grep -Fq -e "[--interactive]" "$SKILL_MD" \
  || fail "SKILL.md argument-hint must contain the '[--interactive]' bracketed flag (#522)"
grep -Fq -e "RESEARCH_PLAN_INTERACTIVE=true" "$SKILL_MD" \
  || fail "SKILL.md must document the 'RESEARCH_PLAN_INTERACTIVE=true' mental flag set by --interactive (#522)"
grep -Fq -e "--interactive requires a TTY" "$SKILL_MD" \
  || fail "SKILL.md must contain the literal '--interactive requires a TTY' pre-planner TTY-guard error (#522)"
grep -Fq -e "--interactive requires --plan" "$SKILL_MD" \
  || fail "SKILL.md must contain the literal '--interactive requires --plan' usage error (#522)"

# Check 14 (#418): research-phase.md ### Standard subsection contains a stable
# byte-drift pin (the existing standard-mode cursor research output filename
# literal). Without this guard, an editor could change the standard branch's
# bash block content and the harness would not catch the drift.
grep -Fq "cursor-research-output.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must contain the standard-mode 'cursor-research-output.txt' filename literal (#418 byte-drift guard)"
grep -Fq "codex-research-output.txt" "$RESEARCH_MD" \
  || fail "references/research-phase.md must contain the standard-mode 'codex-research-output.txt' filename literal (#418 byte-drift guard)"

# Check 15 (#418): validation-phase.md ### Standard byte-drift pin (existing
# Cursor/Codex validation output filenames must remain in the file for the
# standard validation branch).
grep -Fq "cursor-validation-output.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must contain the standard-mode 'cursor-validation-output.txt' filename literal (#418 byte-drift guard)"
grep -Fq "codex-validation-output.txt" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must contain the standard-mode 'codex-validation-output.txt' filename literal (#418 byte-drift guard)"

# Check 16 (#416 + #446): Both phase references must invoke collect-agent-results.sh
# with --substantive-validation (Phase 3 of umbrella #413). Without these pins,
# a future edit could silently drop the flag and revert /research to the
# pre-Phase-3 "non-empty is enough" check, allowing thin/uncited lane outputs
# to slip through to synthesis.
#
# research-phase.md has TWO scale-specific COLLECTION blocks (### Standard and
# ### Deep) inside the `## 1.4 — Wait and Validate Research Outputs` section.
# The flag must be present in BOTH — #446 documented a regression where the
# Deep block dropped the flag while the Standard block retained it, and a
# single whole-file grep silently passed because Standard satisfied it.
#
# To prevent that class of cross-section leakage, pin the flag per-section
# in two stages: (a) narrow extraction to the Step 1.4 window so the
# per-scale `### Standard` / `### Deep` subsection headers under Step 1.3
# (Launch Research Perspectives) cannot smuggle a satisfying invocation
# into the wrong block; (b) within Step 1.4, scope to the per-scale
# subsection by stopping at the next `###` heading so the Standard and
# Deep blocks cannot substitute for each other either.
#
# The grep pattern anchors on the literal bash-invocation prefix
# `${CLAUDE_PLUGIN_ROOT}/scripts/` so prose paragraphs that happen to
# mention both `collect-agent-results.sh` and `--substantive-validation`
# on the same line do NOT satisfy the pin — only the actual command line
# in the bash code fence can.
INVOCATION_PIN='\$\{CLAUDE_PLUGIN_ROOT\}/scripts/collect-agent-results\.sh.*--substantive-validation'
SECTION_1_4=$(awk '/^## 1\.4 /{f=1; next} f && /^## /{f=0} f' "$RESEARCH_MD")
[[ -n "$SECTION_1_4" ]] \
  || fail "references/research-phase.md must contain a '## 1.4 ' section (Wait and Validate Research Outputs) — Check 16 cannot anchor without it"
echo "$SECTION_1_4" \
  | awk '/^### Standard \(RESEARCH_SCALE=standard,? ?(default)?\)/{f=1; next} f && /^###/{f=0} f' \
  | grep -Eq "$INVOCATION_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Standard collection block must invoke collect-agent-results.sh with --substantive-validation (#416 Phase 3)"
echo "$SECTION_1_4" \
  | awk '/^### Deep \(RESEARCH_SCALE=deep\)/{f=1; next} f && /^###/{f=0} f' \
  | grep -Eq "$INVOCATION_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Deep collection block must invoke collect-agent-results.sh with --substantive-validation (#416 Phase 3 + #446)"
# validation-phase.md has a single (scale-agnostic) collection block, so the
# whole-file pin remains correct here. Reuse the invocation-anchored pattern
# for the same anti-prose hardening.
grep -Eq "$INVOCATION_PIN" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must invoke collect-agent-results.sh with --substantive-validation (#416 Phase 3)"

# Check 17 (#416): Both phase references must map STATUS=NOT_SUBSTANTIVE in the
# lane-status update bullet so the new collector status flows into the correct
# render token (fallback_runtime_failed). The pre-existing bullet only listed
# FAILED/EMPTY_OUTPUT; without this pin a future edit could drop NOT_SUBSTANTIVE
# silently and the render helper would emit (unknown) for it.
grep -Fq "NOT_SUBSTANTIVE" "$RESEARCH_MD" \
  || fail "references/research-phase.md must map STATUS=NOT_SUBSTANTIVE in lane-status token bullet (#416 Phase 3)"
grep -Fq "NOT_SUBSTANTIVE" "$VALIDATION_MD" \
  || fail "references/validation-phase.md must map STATUS=NOT_SUBSTANTIVE in lane-status token bullet (#416 Phase 3)"

# Check 18 (#424): adjudication-phase.md must reference both the ballot builder
# and the pre-launch coordinator. Without these pins, a future edit could silently
# drop the wiring and Step 2.5 would have no helper invocation, making the
# adjudication step a no-op even when --adjudicate is on.
grep -Fq "build-research-adjudication-ballot.sh" "$ADJUDICATION_MD" \
  || fail "references/adjudication-phase.md must reference scripts/build-research-adjudication-ballot.sh (#424)"
grep -Fq "run-research-adjudication.sh" "$ADJUDICATION_MD" \
  || fail "references/adjudication-phase.md must reference scripts/run-research-adjudication.sh (#424)"

# Section-scoped extractor for the Step 3 ### Deep subsection (used by both
# Check 19 and Check 20). The extractor toggles a code-fence state on bare
# ``` lines so that headings (`^### ...`, `^## ...`) inside fenced markdown
# template blocks do NOT terminate the section prematurely (#451 review
# FINDING_7). The section ends on the next H2 heading outside a fence — the
# Deep subsection is the last H3 under Step 3, so the next H2 (or EOF)
# bounds it cleanly.
extract_deep_section() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    in_deep && !in_fence && /^## / { in_deep = 0 }
    in_deep && !in_fence { print }
    /^### Deep \(RESEARCH_SCALE=deep\)/ { in_deep = 1 }
  ' "$SKILL_MD"
}

DEEP_SECTION=$(extract_deep_section)
[[ -n "$DEEP_SECTION" ]] \
  || fail "SKILL.md must contain a '### Deep (RESEARCH_SCALE=deep)' subsection — Checks 19/20 cannot anchor without it (#451)"

# Check 19 (#451 + review FINDING_6): SKILL.md Step 3 ### Deep subsection
# (NOT just any prose elsewhere in SKILL.md) must invoke the deep-mode
# renderer so the per-phase attribution slices in `lane-status.txt` are the
# source of truth for deep headers (the bug #451 fixed: previously the deep
# branch derived headers from session-wide cursor_available/codex_available
# flags). Step 0b prose now ALSO mentions the deep helper, so a whole-file
# grep would falsely pass even if the actual Step 3 Deep invocation
# regressed — section-scoping closes that hole.
echo "$DEEP_SECTION" | grep -Fq "render-deep-lane-status.sh" \
  || fail "SKILL.md Step 3 ### Deep subsection must invoke render-deep-lane-status.sh (#451 deep-mode lane attribution; #451 review FINDING_6 closed Step 0b loophole)"

# Check 20 (#451 + review FINDING_7): SKILL.md Step 3 ### Deep subsection
# must NOT derive headers from session-wide cursor_available / codex_available
# flags — that pattern is the pre-fix bug. The check is section-scoped via
# the awk extractor above (which handles fenced code blocks). The negative
# regex covers BOTH cursor_available and codex_available so a Codex-only
# reintroduction of the same bug class also fails.
if echo "$DEEP_SECTION" | grep -qE 'session-wide.*cursor_available|cursor_available.*throughout the run|orchestrator tracks the session-wide.*cursor_available|session-wide.*codex_available|codex_available.*throughout the run|orchestrator tracks the session-wide.*codex_available|tracks the session-wide.*cursor_available.*codex_available|tracks the session-wide.*codex_available.*cursor_available'; then
  fail "SKILL.md Step 3 ### Deep subsection must not derive headers from session-wide cursor_available/codex_available flags (#451 — use render-deep-lane-status.sh + lane-status.txt slices instead)"
fi

# Check 21 (#506): degraded-path reduced-diversity banner contract.
# When any external research lane (Cursor or Codex) ran as a Claude-fallback,
# Step 1.5 prepends a banner to ## Research Synthesis and to research-report.txt.
# The banner contract lives in research-phase.md §1.5; this check pins it
# section by section so cross-section leakage is impossible.
#
# Section extractor for the §1.5 banner preamble (between '## 1.5 — Synthesis'
# and '### Standard (RESEARCH_SCALE=standard'). Mirrors the per-section awk
# extraction pattern used by Check 16 above.
SECTION_15_PREAMBLE=$(awk '/^## 1\.5 — Synthesis/{f=1} f && /^### Standard \(RESEARCH_SCALE=standard/{exit} f' "$RESEARCH_MD")
[[ -n "$SECTION_15_PREAMBLE" ]] \
  || fail "references/research-phase.md must contain a '## 1.5 — Synthesis' preamble window terminated by '### Standard (RESEARCH_SCALE=standard' — Checks 21a-21e cannot anchor without it (#506)"

BANNER_LITERAL='**⚠ Reduced lane diversity: <N_FALLBACK> of <LANE_TOTAL> external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

# Check 21a (#506 + #507): §1.5 banner preamble + canonical executable.
# - The banner literal AND the formula literals exist on a 5-surface
#   edit-in-sync contract per #507. The banner literal stays in
#   research-phase.md §1.5 preamble (documentation pin) AND in
#   compute-degraded-banner.sh (canonical executable pin). The per-scale
#   formula literals moved to compute-degraded-banner.sh under #507 (the
#   helper is now the canonical executable; research-phase.md preamble
#   carries them for documentation only).
# - Without these pins, a future edit could silently weaken or relocate
#   the contract.
echo "$SECTION_15_PREAMBLE" | grep -Fq "$BANNER_LITERAL" \
  || fail "references/research-phase.md §1.5 banner preamble must contain the byte-exact banner literal (#506 Check 21a)"
echo "$SECTION_15_PREAMBLE" | grep -Fq 'N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)' \
  || fail "references/research-phase.md §1.5 banner preamble must contain the standard-mode N_FALLBACK formula literal for documentation (#506 + #507 Check 21a)"
echo "$SECTION_15_PREAMBLE" | grep -Fq '2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)' \
  || fail "references/research-phase.md §1.5 banner preamble must contain the deep-mode N_FALLBACK formula literal with 2* multiplier for documentation (#506 + #507 Check 21a)"
echo "$SECTION_15_PREAMBLE" | grep -Fq "lane-status.txt" \
  || fail "references/research-phase.md §1.5 banner preamble must reference lane-status.txt (the source of truth for fallback status) (#506 Check 21a)"
echo "$SECTION_15_PREAMBLE" | grep -Fq "research-report.txt" \
  || fail "references/research-phase.md §1.5 banner preamble must mention research-report.txt (BOTH-outputs contract) (#506 Check 21a)"

# Check 21a-helper (#507): the canonical executable compute-degraded-banner.sh
# MUST exist, be executable, and contain the banner template + per-scale
# formula literals (canonical executable pin — moved from research-phase.md
# under #507 per dialectic D1 resolution).
HELPER_SCRIPT="$REPO_ROOT/skills/research/scripts/compute-degraded-banner.sh"
[[ -f "$HELPER_SCRIPT" ]] \
  || fail "skills/research/scripts/compute-degraded-banner.sh must exist (#507 Check 21a-helper — canonical executable home for the banner formula)"
[[ -x "$HELPER_SCRIPT" ]] \
  || fail "skills/research/scripts/compute-degraded-banner.sh must be executable (chmod +x) (#507 Check 21a-helper)"
if [[ -f "$HELPER_SCRIPT" ]]; then
  grep -Fq "$BANNER_LITERAL" "$HELPER_SCRIPT" \
    || fail "skills/research/scripts/compute-degraded-banner.sh must contain the byte-exact BANNER_TEMPLATE constant matching the prose literal (#507 Check 21a-helper — 5-surface edit-in-sync rule)"
  grep -Fq 'N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)' "$HELPER_SCRIPT" \
    || fail "skills/research/scripts/compute-degraded-banner.sh must document the standard-mode N_FALLBACK formula literal in comments (#507 Check 21a-helper)"
  grep -Fq '2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)' "$HELPER_SCRIPT" \
    || fail "skills/research/scripts/compute-degraded-banner.sh must document the deep-mode N_FALLBACK formula literal with 2* multiplier in comments (#507 Check 21a-helper)"
fi

# Check 21a-helper-fork (#507): research-phase.md §1.5 preamble must reference
# the fork pattern that loads the helper at runtime — the orchestrator's
# runtime banner computation is a fork of compute-degraded-banner.sh, NOT a
# source-and-run pattern.
echo "$SECTION_15_PREAMBLE" | grep -Fq "compute-degraded-banner.sh" \
  || fail "references/research-phase.md §1.5 banner preamble must reference compute-degraded-banner.sh (the canonical executable; #507 Check 21a-helper-fork)"

# Section extractors for the three branches that apply the banner. The
# extractors bound each subsection to its own scope so a banner reference
# that is present in one branch cannot satisfy the check for another.
#
# CRITICAL: research-phase.md has THREE pairs of `### Quick (RESEARCH_SCALE=quick)`
# and `### Deep (RESEARCH_SCALE=deep)` headings — one pair each in §1.3 (Launch
# Research Perspectives), §1.4 (Wait and Validate), and §1.5 (Synthesis). A
# whole-file awk scan keyed only on the heading would concatenate all three
# pairs, allowing cross-section leakage.
#
# Mitigation: first slice the §1.5 window (from `## 1.5 — Synthesis` to the
# next `## ` heading, or EOF), then run the per-subsection extractors against
# THAT window so each pattern can match at most one §1.5 subsection.
SECTION_15_FULL=$(awk '
  /^## 1\.5 — Synthesis/{f=1; next}
  f && /^## /{f=0}
  f
' "$RESEARCH_MD")
[[ -n "$SECTION_15_FULL" ]] \
  || fail "references/research-phase.md must contain a '## 1.5 — Synthesis' section terminated by the next '## ' heading — Checks 21b-21e cannot anchor without it (#506)"

SECTION_15_STANDARD_FALSE=$(echo "$SECTION_15_FULL" | awk '
  /^#### When `RESEARCH_PLAN=false`/{f=1; next}
  f && /^#### /{f=0}
  f && /^### /{f=0}
  f
')
SECTION_15_STANDARD_TRUE=$(echo "$SECTION_15_FULL" | awk '
  /^#### When `RESEARCH_PLAN=true`/{f=1; next}
  f && /^#### /{f=0}
  f && /^### /{f=0}
  f
')
SECTION_15_DEEP=$(echo "$SECTION_15_FULL" | awk '
  /^### Deep \(RESEARCH_SCALE=deep\)/{f=1; next}
  f && /^### /{f=0}
  f
')
SECTION_15_QUICK=$(echo "$SECTION_15_FULL" | awk '
  /^### Quick \(RESEARCH_SCALE=quick\)/{f=1; next}
  f && /^### /{f=0}
  f
')

[[ -n "$SECTION_15_STANDARD_FALSE" ]] \
  || fail "references/research-phase.md must contain a '#### When \`RESEARCH_PLAN=false\`' subsection — Check 21b cannot anchor (#506)"
[[ -n "$SECTION_15_STANDARD_TRUE" ]] \
  || fail "references/research-phase.md must contain a '#### When \`RESEARCH_PLAN=true\`' subsection — Check 21c cannot anchor (#506)"
[[ -n "$SECTION_15_DEEP" ]] \
  || fail "references/research-phase.md must contain a '### Deep (RESEARCH_SCALE=deep)' subsection — Check 21d cannot anchor (#506)"
[[ -n "$SECTION_15_QUICK" ]] \
  || fail "references/research-phase.md must contain a '### Quick (RESEARCH_SCALE=quick)' subsection — Check 21e cannot anchor (#506)"

# Check 21b (#506): Standard RESEARCH_PLAN=false branch must reference the
# banner preamble. Anchor on the literal "Reduced-diversity banner preamble"
# phrase (the preamble's own subsection name) so the reference is unambiguous.
echo "$SECTION_15_STANDARD_FALSE" | grep -Fq "Reduced-diversity banner preamble" \
  || fail "references/research-phase.md §1.5 '#### When \`RESEARCH_PLAN=false\`' must reference the 'Reduced-diversity banner preamble' (#506 Check 21b)"

# Check 21c (#506): Standard RESEARCH_PLAN=true branch must reference the preamble.
echo "$SECTION_15_STANDARD_TRUE" | grep -Fq "Reduced-diversity banner preamble" \
  || fail "references/research-phase.md §1.5 '#### When \`RESEARCH_PLAN=true\`' must reference the 'Reduced-diversity banner preamble' (#506 Check 21c)"

# Check 21d (#506): Deep branch must reference the preamble.
echo "$SECTION_15_DEEP" | grep -Fq "Reduced-diversity banner preamble" \
  || fail "references/research-phase.md §1.5 '### Deep (RESEARCH_SCALE=deep)' must reference the 'Reduced-diversity banner preamble' (#506 Check 21d)"

# Check 21e (#506 + #520): Quick branch must NOT contain the Reduced-lane-diversity
# banner literal or trigger language. Quick mode has its own per-path disclaimers
# (issue #520: K-lane voting confidence on the vote path, Single-lane confidence
# on the single-lane fallback path); accidentally adding the Reduced-diversity
# banner there would be a regression.
if echo "$SECTION_15_QUICK" | grep -Fq "Reduced lane diversity"; then
  fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must NOT contain the reduced-diversity banner — Quick mode carries its own per-path disclaimers (#506 + #520 Check 21e negative)"
fi
if echo "$SECTION_15_QUICK" | grep -Fq "Reduced-diversity banner preamble"; then
  fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must NOT reference the reduced-diversity banner preamble (#506 Check 21e negative)"
fi

# Check 21e positive (split — issue #520):
# Vote path positive: Quick branch must reference 'K-lane voting confidence'
# (the new K-vote disclaimer text).
echo "$SECTION_15_QUICK" | grep -Fq "K-lane voting confidence" \
  || fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must reference 'K-lane voting confidence' framing on the vote path (#520 Check 21e vote-path positive)"

# Fallback path positive: Quick branch must retain 'Single-lane confidence'
# in the LANES_SUCCEEDED == 1 fallback sub-subsection.
echo "$SECTION_15_QUICK" | grep -Fq "Single-lane confidence" \
  || fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must retain the 'Single-lane confidence' disclaimer on the LANES_SUCCEEDED == 1 fallback path (#520 Check 21e fallback-path positive)"

# Quick branch must reference the fallback file path (not just the disclaimer text).
echo "$SECTION_15_QUICK" | grep -Fq "quick-disclaimer-fallback.txt" \
  || fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must reference 'quick-disclaimer-fallback.txt' on the LANES_SUCCEEDED == 1 fallback path (#520 Check 21e fallback-file positive)"

# Quick branch must NOT contain "independent reviewers" — failure-mode
# mitigation against overstating K-lane voting as cross-tool diversity.
if echo "$SECTION_15_QUICK" | grep -Fq "independent reviewers"; then
  fail "references/research-phase.md §1.5 '### Quick (RESEARCH_SCALE=quick)' must NOT contain 'independent reviewers' — overstates K-lane voting as cross-tool diversity (#520 Check 21e negative)"
fi

# Check 22 (#506): SKILL.md Step 3 must contain the byte-stable banner phrase
# in its degraded-path preview. SKILL.md is the operator-facing example surface
# and is on the four-way edit-in-sync list (research-phase.md preamble,
# test-research-structure.sh, test-degraded-path-banner.sh, SKILL.md).
# Without this pin, a future change to the banner template would not fail CI
# from SKILL.md drift — operators would see a stale example.
#
# Pin a sentinel phrase that appears in the banner (any of: "Reduced lane
# diversity", "external research lanes ran as Claude-fallback", "model-family
# heterogeneity claim does not hold"). Pin one phrase to keep the check tight
# without over-constraining the prose around the example.
grep -Fq "Reduced lane diversity" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must contain the 'Reduced lane diversity' banner phrase (degraded-path preview) — keep in sync with research-phase.md §1.5 banner preamble (#506 Check 22)"
grep -Fq "model-family heterogeneity claim does not hold" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must contain the 'model-family heterogeneity claim does not hold' banner phrase — keep in sync with research-phase.md §1.5 banner preamble (#506 Check 22)"

# Section-scoped extractor for the new ## Filing findings as issues numbered
# procedure (added by issue #509 — pins the post-/issue mechanical-check
# control-flow site at a concrete numbered procedure rather than generic prose;
# FINDING_11 from the plan-review panel). The section spans from the H2
# heading until the next H2 — fence-aware to mirror extract_deep_section's
# semantics: bare ``` toggles a fence state so headings inside fenced markdown
# template blocks do not terminate extraction.
extract_filing_section() {
  awk '
    /^```/ { in_fence = !in_fence; next }
    in_filing && !in_fence && /^## / { in_filing = 0 }
    in_filing && !in_fence { print }
    /^## Filing findings as issues/ { in_filing = 1 }
  ' "$SKILL_MD"
}

FILING_SECTION=$(extract_filing_section)
[[ -n "$FILING_SECTION" ]] \
  || fail "SKILL.md must contain a '## Filing findings as issues' H2 section — Checks 23-26 cannot anchor without it (#509)"

# Check 23 (#509 FINDING_11): the Filing-findings-as-issues procedure must
# include the defensive `rm -f` of the sentinel path. Without this pin,
# stale-sentinel false-positive recovery from a reused tmpdir is silently
# regressed. Single-quoted intentionally — pinning the literal `$RESEARCH_TMPDIR`
# token in SKILL.md prose (intentional — shellcheck SC2016 disabled).
# shellcheck disable=SC2016
echo "$FILING_SECTION" | grep -Fq 'rm -f "$RESEARCH_TMPDIR/issue-completed.sentinel"' \
  || fail "SKILL.md '## Filing findings as issues' must contain defensive 'rm -f \"\$RESEARCH_TMPDIR/issue-completed.sentinel\"' (#509 FINDING_4 + path-skew prevention)"

# Check 24 (#509 FINDING_11): the procedure must invoke /issue with the narrow
# --sentinel-file flag (not --session-env, per FINDING_10) carrying the
# specific sentinel path. The flag is the parent→child path single-source.
# Single-quoted intentionally — pinning the literal `$RESEARCH_TMPDIR` token.
# shellcheck disable=SC2016
echo "$FILING_SECTION" | grep -Fq -- '--sentinel-file $RESEARCH_TMPDIR/issue-completed.sentinel' \
  || fail "SKILL.md '## Filing findings as issues' must reference '--sentinel-file \$RESEARCH_TMPDIR/issue-completed.sentinel' (#509 FINDING_10 narrow flag)"

# Check 25 (#509 FINDING_11): the procedure must invoke verify-skill-called.sh
# with --sentinel-file post-/issue-return. This is the mechanical sentinel
# gate — without it, /research has only stdout parsing as defense.
echo "$FILING_SECTION" | grep -Fq -e "verify-skill-called.sh --sentinel-file" \
  || fail "SKILL.md '## Filing findings as issues' must invoke verify-skill-called.sh --sentinel-file (#509 dialectic DECISION_1 + FINDING_11)"

# Check 26 (#509 FINDING_8): the procedure must explicitly document the
# fail-closed-on-any-failure intent so future contributors do not silently
# soften the gate. Pin the literal "fail-closed" + "research-result-filing"
# phrase pair on the same section to detect drift.
echo "$FILING_SECTION" | grep -Fq "fail-closed" \
  || fail "SKILL.md '## Filing findings as issues' must use the literal 'fail-closed' (#509 FINDING_8 intent doc)"
echo "$FILING_SECTION" | grep -Fq "research-result-filing" \
  || fail "SKILL.md '## Filing findings as issues' must mention 'research-result-filing' semantics (#509 FINDING_8 intent doc)"

# Check 27 (#510): SKILL.md Step 3 must invoke render-findings-batch.sh after
# writing the rendered final report (single-authoritative-write pattern from
# #510 design FINDING_8). The grep is whole-file because the helper invocation
# block is in the new "### Step 3 final-report write + sidecar generation"
# subsection, anchored by name to make the check readable.
grep -Fq "render-findings-batch.sh" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must invoke render-findings-batch.sh (#510)"

# Check 28 (#510): SKILL.md must document --keep-sidecar in the Flags section
# (boolean form) AND --keep-sidecar=<path> (value form). The positional form
# (--keep-sidecar <path>) is intentionally NOT supported per #510 design
# FINDING_6.
grep -Fq -- "--keep-sidecar" "$SKILL_MD" \
  || fail "SKILL.md must document --keep-sidecar flag (#510)"
grep -Fq -- "--keep-sidecar=<PATH>" "$SKILL_MD" \
  || fail "SKILL.md must document --keep-sidecar=<PATH> value form (#510)"

# Check 29 (#510): SKILL.md Step 3 sources the canonical Quick disclaimer from
# the data file; research-phase.md Quick branch references the same data file
# path. This pin asserts the single-source-of-truth contract from #510 design
# FINDING_4 — without both references in sync, the sidecar's per-item
# disclaimer can diverge from the synthesis prose.
DISCLAIMER_PATH="skills/research/data/quick-disclaimer.txt"
grep -Fq "$DISCLAIMER_PATH" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must reference $DISCLAIMER_PATH (#510)"
grep -Fq "$DISCLAIMER_PATH" "$REPO_ROOT/skills/research/references/research-phase.md" \
  || fail "research-phase.md Quick branch must reference $DISCLAIMER_PATH (#510)"

# Check 30 (#510): the canonical Quick disclaimer file must exist and be
# non-empty.
if [[ ! -s "$REPO_ROOT/$DISCLAIMER_PATH" ]]; then
  fail "$DISCLAIMER_PATH must exist and be non-empty (#510)"
fi

# Check 30b (#520): the Quick disclaimer fallback file must exist and be
# non-empty (used when LANES_SUCCEEDED == 1).
DISCLAIMER_FALLBACK_PATH="skills/research/data/quick-disclaimer-fallback.txt"
if [[ ! -s "$REPO_ROOT/$DISCLAIMER_FALLBACK_PATH" ]]; then
  fail "$DISCLAIMER_FALLBACK_PATH must exist and be non-empty (#520)"
fi

# Check 29b (#520): SKILL.md Step 3 AND research-phase.md Quick branch must both
# reference the fallback disclaimer file path (parallel to Check 29 for the
# canonical disclaimer). Without both references in sync, the two-file system
# can desync silently.
grep -Fq "$DISCLAIMER_FALLBACK_PATH" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must reference $DISCLAIMER_FALLBACK_PATH (#520 Check 29b)"
grep -Fq "$DISCLAIMER_FALLBACK_PATH" "$REPO_ROOT/skills/research/references/research-phase.md" \
  || fail "research-phase.md Quick branch must reference $DISCLAIMER_FALLBACK_PATH (#520 Check 29b)"

# Check 30c (#520): the K-vote state helper must exist and be executable.
QUICK_VOTE_STATE_PATH="skills/research/scripts/quick-vote-state.sh"
if [[ ! -x "$REPO_ROOT/$QUICK_VOTE_STATE_PATH" ]]; then
  fail "$QUICK_VOTE_STATE_PATH must exist and be executable (#520)"
fi

# Check 30d (#520): the K-vote state helper's sibling .md must exist and be
# non-empty (per project edit-in-sync convention).
if [[ ! -s "$REPO_ROOT/skills/research/scripts/quick-vote-state.md" ]]; then
  fail "skills/research/scripts/quick-vote-state.md must exist and be non-empty (#520)"
fi

# Check 30e (#520): research-phase.md Quick branch must reference the K-vote
# state helper (write at Step 1.4 / read at Step 1.5).
echo "$SECTION_15_QUICK" | grep -Fq "quick-vote-state.sh" \
  || fail "research-phase.md §1.5 Quick must reference quick-vote-state.sh helper (#520)"

# Check 30f (#520): SKILL.md Step 3 must reference the K-vote state helper to
# pick the right disclaimer file.
grep -Fq "quick-vote-state.sh" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must reference quick-vote-state.sh to pick the disclaimer file (#520)"

# Check 31 (#510): SKILL.md Step 3 writes research-report-final.md before
# invoking the helper (single-authoritative-write per #510 FINDING_8).
grep -Fq "research-report-final.md" "$SKILL_MD" \
  || fail "SKILL.md Step 3 must write research-report-final.md (#510 FINDING_8)"

# Check 32 (#510): SKILL.md Step 4 contains a KEEP_SIDECAR cp branch. The
# pin guards against accidental removal of the preserve-or-cleanup ordering
# that ensures cp runs BEFORE cleanup-tmpdir.sh.
if ! awk '/^## Step 4 — Cleanup/,0' "$SKILL_MD" | grep -Fq "KEEP_SIDECAR"; then
  fail "SKILL.md Step 4 must reference KEEP_SIDECAR for the preserve branch (#510)"
fi

# ---------------------------------------------------------------------------
# Checks 33-37 (#519 — lift --plan + --scale=deep restriction; support 2D
# subq×angle coverage). These pins guard the deep-mode planner support against
# regression: (a) the previous "is not yet supported" disable warning must NOT
# return; (b) the new deep + RESEARCH_PLAN=true sub-branch in §1.5 Deep must
# carry the agreed structure (subquestion-major + Per-angle highlights +
# Cross-cutting findings); (c) the §1.4 Deep runtime-fallback prose must name
# all four angle-prompt literals so the angle-specific rehydration contract is
# pinned at the prose layer; (d) the §1.2 deep-mode lane-assignment table must
# carry 5 lane columns. Section-scoped extraction follows the same pattern as
# Checks 21b-21e to avoid whole-file false-positives.
# ---------------------------------------------------------------------------

# Check 33 (#519): the previous "is not yet supported" warning must NOT exist
# in SKILL.md anymore. Catches accidental re-introduction of the deep-mode
# disable rule.
if grep -Fq "is not yet supported" "$SKILL_MD"; then
  fail "SKILL.md must NOT contain 'is not yet supported' (#519 — the deep-mode --plan disable rule was lifted)"
fi

# Check 34 (#519): SKILL.md must contain the deep-mode entry of the resolution
# rule. Pinning the literal 'AND `RESEARCH_SCALE=deep`: full functionality'
# fragment anchors that line 49's deep-mode entry remains the supported path
# (NOT the previous "is not yet supported" disable). Combined with Check 33
# this guards both directions of the gate change.
# shellcheck disable=SC2016
grep -Fq 'AND `RESEARCH_SCALE=deep`: full functionality' "$SKILL_MD" \
  || fail "SKILL.md must contain the deep-mode '\`RESEARCH_PLAN=true\` AND \`RESEARCH_SCALE=deep\`: full functionality' resolution-rule entry (#519 Check 34 — was disabled before, now supported)"

# Extract the §1.5 Deep + RESEARCH_PLAN=true sub-branch from the existing
# SECTION_15_DEEP window. Pattern: from the second `#### When `RESEARCH_PLAN=true``
# heading inside SECTION_15_DEEP to either the next `#### ` heading or the next
# `### ` heading. SECTION_15_DEEP itself was extracted earlier and stops at the
# next `### ` so we cannot leak past Deep.
SECTION_15_DEEP_PLAN_TRUE=$(echo "$SECTION_15_DEEP" | awk '
  /^#### When `RESEARCH_PLAN=true`/{f=1; next}
  f && /^#### /{f=0}
  f && /^### /{f=0}
  f
')

[[ -n "$SECTION_15_DEEP_PLAN_TRUE" ]] \
  || fail "references/research-phase.md §1.5 Deep must contain a '#### When \`RESEARCH_PLAN=true\`' sub-branch (#519 Check 35 anchor missing)"

# Check 35 (#519): the §1.5 Deep + RESEARCH_PLAN=true sub-branch must carry the
# agreed three-section structure. Section-scoped extraction (above) means a
# whole-file grep cannot be satisfied by the existing standard-mode
# RESEARCH_PLAN=true branch headers. Substring matches (not line-start
# anchored) — the prose describes the runtime sub-section names inline within
# bullets, not as actual H3 headings of this prose document.
echo "$SECTION_15_DEEP_PLAN_TRUE" | grep -Fq '### Subquestion' \
  || fail "references/research-phase.md §1.5 Deep '#### When \`RESEARCH_PLAN=true\`' must mention '### Subquestion' sub-sections (#519 Check 35)"
echo "$SECTION_15_DEEP_PLAN_TRUE" | grep -Fq '### Per-angle highlights' \
  || fail "references/research-phase.md §1.5 Deep '#### When \`RESEARCH_PLAN=true\`' must mention '### Per-angle highlights' sub-section (#519 Check 35)"
echo "$SECTION_15_DEEP_PLAN_TRUE" | grep -Fq '### Cross-cutting findings' \
  || fail "references/research-phase.md §1.5 Deep '#### When \`RESEARCH_PLAN=true\`' must mention '### Cross-cutting findings' sub-section (#519 Check 35)"

# Extract the §1.4 Deep section to anchor Check 36. The §1.4 section header is
# '## 1.4 — Wait and Validate Research Outputs'; we further narrow to its
# `### Deep` subsection.
SECTION_14_FULL=$(awk '
  /^## 1\.4 — Wait and Validate Research Outputs/{f=1; next}
  f && /^## /{f=0}
  f
' "$RESEARCH_MD")
[[ -n "$SECTION_14_FULL" ]] \
  || fail "references/research-phase.md must contain a '## 1.4 — Wait and Validate Research Outputs' section — Check 36 cannot anchor (#519)"

SECTION_14_DEEP=$(echo "$SECTION_14_FULL" | awk '
  /^### Deep \(RESEARCH_SCALE=deep\)/{f=1; next}
  f && /^### /{f=0}
  f
')
[[ -n "$SECTION_14_DEEP" ]] \
  || fail "references/research-phase.md §1.4 must contain a '### Deep (RESEARCH_SCALE=deep)' subsection — Check 36 cannot anchor (#519)"

# Check 36 (#519): §1.4 Deep runtime-fallback prose must explicitly name all
# four angle-prompt literals so the angle-specific rehydration contract is
# pinned. A generic 'RESEARCH_PROMPT' fallback would silently erase the
# angle-diversity claim.
echo "$SECTION_14_DEEP" | grep -Fq "RESEARCH_PROMPT_ARCH" \
  || fail "references/research-phase.md §1.4 Deep must name 'RESEARCH_PROMPT_ARCH' for runtime-fallback rehydration (#519 Check 36)"
echo "$SECTION_14_DEEP" | grep -Fq "RESEARCH_PROMPT_EDGE" \
  || fail "references/research-phase.md §1.4 Deep must name 'RESEARCH_PROMPT_EDGE' for runtime-fallback rehydration (#519 Check 36)"
echo "$SECTION_14_DEEP" | grep -Fq "RESEARCH_PROMPT_EXT" \
  || fail "references/research-phase.md §1.4 Deep must name 'RESEARCH_PROMPT_EXT' for runtime-fallback rehydration (#519 Check 36)"
echo "$SECTION_14_DEEP" | grep -Fq "RESEARCH_PROMPT_SEC" \
  || fail "references/research-phase.md §1.4 Deep must name 'RESEARCH_PROMPT_SEC' for runtime-fallback rehydration (#519 Check 36)"

# Check 37 (#519): the §1.2 deep-mode lane-assignment table must carry 5 lane
# columns. Extract the §1.2 — Lane Assignment section, then narrow to the
# '#### Deep (RESEARCH_SCALE=deep)' subsection (under §1.2.a — Compute per-lane
# subquestions). Assert the table contains 'Lane 5 (Claude inline)' which is
# unique to the 5-lane shape.
SECTION_12_FULL=$(awk '
  /^## 1\.2 — Lane Assignment/{f=1; next}
  f && /^## /{f=0}
  f
' "$RESEARCH_MD")
[[ -n "$SECTION_12_FULL" ]] \
  || fail "references/research-phase.md must contain a '## 1.2 — Lane Assignment' section — Check 37 cannot anchor (#519)"

SECTION_12_DEEP=$(echo "$SECTION_12_FULL" | awk '
  /^#### Deep \(RESEARCH_SCALE=deep\)/{f=1; next}
  f && /^#### /{f=0}
  f && /^### /{f=0}
  f && /^## /{f=0}
  f
')
[[ -n "$SECTION_12_DEEP" ]] \
  || fail "references/research-phase.md §1.2 must contain a '#### Deep (RESEARCH_SCALE=deep)' subsection — Check 37 cannot anchor (#519)"

echo "$SECTION_12_DEEP" | grep -Fq "Lane 5 (Claude inline)" \
  || fail "references/research-phase.md §1.2 Deep table must contain 'Lane 5 (Claude inline)' column (#519 Check 37 — confirms 5-lane shape)"

# Checks 38a-38c (#534): structural pins for validation-phase.md '## Finalize
# Validation' section. After PR #507's refactor introduced a separate revision
# subagent, this section became a load-bearing contract surface with no
# structural assertion — future edits could silently drop or reshape the
# revision-subagent invocation, the atomic rewrite of research-report.txt, or
# the 5-marker body contract from the originating Step 1.5 branch.
#
# Slice the '## Finalize Validation' window first so per-pin greps cannot leak
# across to other sections. The section is the last '## ' heading in the file,
# so the awk terminator falls through to EOF naturally.
SECTION_FINALIZE_VALIDATION=$(awk '
  /^## Finalize Validation/{f=1; next}
  f && /^## /{f=0}
  f
' "$VALIDATION_MD")
[[ -n "$SECTION_FINALIZE_VALIDATION" ]] \
  || fail "references/validation-phase.md must contain a '## Finalize Validation' section — Checks 38a-38c cannot anchor (#534)"

# Check 38a (#534): the revision subagent invocation pattern. Pin both the
# canonical "Route the synthesis-revision step" sentence (the directive that
# mandates the separate-subagent shape) and the 'revision-raw.txt' Write
# capture filename literal (the on-disk handoff path between subagent and
# orchestrator).
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "Route the synthesis-revision step to a separate Claude Agent subagent" \
  || fail "references/validation-phase.md '## Finalize Validation' must mandate routing the synthesis-revision step to a separate Claude Agent subagent (#534 Check 38a)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "revision-raw.txt" \
  || fail "references/validation-phase.md '## Finalize Validation' must capture the revision subagent's response to 'revision-raw.txt' via the Write tool (#534 Check 38a)"

# Check 38b (#534): atomic rewrite of research-report.txt. Pin the 'Atomically
# rewrite' directive plus the research-report.txt filename plus the mktemp +
# mv literals that document the atomic-write technique.
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "Atomically rewrite" \
  || fail "references/validation-phase.md '## Finalize Validation' must mandate atomic rewrite of the research report (#534 Check 38b)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "research-report.txt" \
  || fail "references/validation-phase.md '## Finalize Validation' must name 'research-report.txt' as the rewrite target (#534 Check 38b)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "mktemp" \
  || fail "references/validation-phase.md '## Finalize Validation' must specify 'mktemp' as part of the atomic-rewrite technique (#534 Check 38b)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "mv" \
  || fail "references/validation-phase.md '## Finalize Validation' must specify 'mv' as part of the atomic-rewrite technique (#534 Check 38b)"

# Check 38c (#534): the 5 body markers from the originating Step 1.5 branch
# (FINDING_1 marker contract — Standard RESEARCH_PLAN=false profile). The
# REVISION_PROMPT enumerates them so the revision subagent preserves the same
# marker structure as the original synthesis. Pin each marker independently so
# a subset deletion fails CI individually.
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "### Agreements" \
  || fail "references/validation-phase.md '## Finalize Validation' REVISION_PROMPT must enumerate the '### Agreements' body marker (#534 Check 38c)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "### Divergences" \
  || fail "references/validation-phase.md '## Finalize Validation' REVISION_PROMPT must enumerate the '### Divergences' body marker (#534 Check 38c)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "### Significance" \
  || fail "references/validation-phase.md '## Finalize Validation' REVISION_PROMPT must enumerate the '### Significance' body marker (#534 Check 38c)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "### Architectural patterns" \
  || fail "references/validation-phase.md '## Finalize Validation' REVISION_PROMPT must enumerate the '### Architectural patterns' body marker (#534 Check 38c)"
echo "$SECTION_FINALIZE_VALIDATION" | grep -Fq "### Risks and feasibility" \
  || fail "references/validation-phase.md '## Finalize Validation' REVISION_PROMPT must enumerate the '### Risks and feasibility' body marker (#534 Check 38c)"

# Check 39 (#516): Step 2.7 — Citation Validation block presence in SKILL.md.
# Pin the literal section header AND the validator script invocation AND the
# completion-line breadcrumb format. The block lives between Step 2.5's budget
# gate and Step 3 — see SKILL.md.
grep -Fq "## Step 2.7 — Citation Validation" "$SKILL_MD" \
  || fail "SKILL.md must contain the '## Step 2.7 — Citation Validation' section header (#516)"
grep -Fq "validate-citations.sh" "$SKILL_MD" \
  || fail "SKILL.md must invoke skills/research/scripts/validate-citations.sh in Step 2.7 (#516)"
grep -Fq "citation-validation —" "$SKILL_MD" \
  || fail "SKILL.md Step 2.7 must use the 'citation-validation' short-name in completion-line breadcrumbs (#516)"

# Check 40 (#516): Step Name Registry must list 2.7 with the citation-validation
# short name. Per-substring grep loop (presence-not-order) — minor reordering
# of unrelated rows must not break the check.
STEP_REGISTRY_HITS=$(grep -E '^\| 2\.7 \|' "$SKILL_MD" | grep -c 'citation-validation' || true)
[[ "$STEP_REGISTRY_HITS" -ge 1 ]] \
  || fail "SKILL.md Step Name Registry must contain a row for Step 2.7 with the 'citation-validation' short name (#516 Check 40)"

# Check 41 (#516): Step 3 splice contract — the citation-validation sidecar
# must be appended to research-report-final.md before the user-visible cat.
# Pin (a) the sidecar filename literal, (b) an append-redirect (`>>`) into
# research-report-final.md somewhere in SKILL.md (Step 3 owns this).
grep -Fq "citation-validation.md" "$SKILL_MD" \
  || fail "SKILL.md must reference the citation-validation.md sidecar in Step 3's splice block (#516 Check 41)"
# shellcheck disable=SC2016
grep -Eq '>> "\$RESEARCH_TMPDIR/research-report-final\.md"' "$SKILL_MD" \
  || fail "SKILL.md Step 3 must append the citation-validation sidecar to research-report-final.md via '>>' (#516 Check 41)"

# Check 42 (#516): the citation-validation reference file body pins.
# The reference owns the validator-invocation contract recap and the SSRF
# defenses recap. Pin the script filename + the curl-flag MUST literals.
grep -Fq "validate-citations.sh" "$CITATION_MD" \
  || fail "references/citation-validation-phase.md must reference validate-citations.sh (#516 Check 42)"
grep -Fq -- "--max-redirs 0" "$CITATION_MD" \
  || fail "references/citation-validation-phase.md must document the '--max-redirs 0' SSRF guard (#516 Check 42)"
grep -Fq -- "--noproxy" "$CITATION_MD" \
  || fail "references/citation-validation-phase.md must document the '--noproxy' SSRF guard (#516 Check 42)"

# Check 43 (#516): the validate-citations.sh script + sibling .md exist and the
# script is executable. Without these pins, a future edit could quietly remove
# either surface and Step 2.7 would be a no-op.
VALIDATE_CITATIONS_SCRIPT="$REPO_ROOT/skills/research/scripts/validate-citations.sh"
VALIDATE_CITATIONS_MD="$REPO_ROOT/skills/research/scripts/validate-citations.md"
[[ -f "$VALIDATE_CITATIONS_SCRIPT" ]] \
  || fail "skills/research/scripts/validate-citations.sh must exist (#516 Check 43)"
[[ -x "$VALIDATE_CITATIONS_SCRIPT" ]] \
  || fail "skills/research/scripts/validate-citations.sh must be executable (#516 Check 43)"
[[ -f "$VALIDATE_CITATIONS_MD" ]] \
  || fail "skills/research/scripts/validate-citations.md sibling contract must exist (#516 Check 43)"

# Check 44 (#516): file-line-regex-lib.sh shared library + sibling .md exist.
# Source-only library replacing the inlined regex tier rules in
# validate-research-output.sh and powering the file:line claim extractor in
# validate-citations.sh.
FILELINELIB_SCRIPT="$REPO_ROOT/scripts/file-line-regex-lib.sh"
FILELINELIB_MD="$REPO_ROOT/scripts/file-line-regex-lib.md"
[[ -f "$FILELINELIB_SCRIPT" ]] \
  || fail "scripts/file-line-regex-lib.sh must exist (#516 Check 44)"
[[ -f "$FILELINELIB_MD" ]] \
  || fail "scripts/file-line-regex-lib.md sibling contract must exist (#516 Check 44)"
# The library MUST be source-only (no `set -e`, no top-level `exit`).
grep -Eq '^set -[euo]+pipefail' "$FILELINELIB_SCRIPT" \
  && fail "scripts/file-line-regex-lib.sh must NOT set strict mode (it is a source-only library) (#516 Check 44)"
grep -Eq '^[[:space:]]*exit[[:space:]]+[0-9]' "$FILELINELIB_SCRIPT" \
  && fail "scripts/file-line-regex-lib.sh must NOT contain top-level 'exit' calls (it is a source-only library) (#516 Check 44)"

# Check 45 (#516): validate-research-output.sh sources the shared library.
# Without this pin, the refactor could be silently reverted (regex inlined
# again) and the two consumers would drift on tier rules.
grep -Fq 'file-line-regex-lib.sh' "$REPO_ROOT/scripts/validate-research-output.sh" \
  || fail "scripts/validate-research-output.sh must source scripts/file-line-regex-lib.sh (#516 Check 45)"

# Check 46 (#517): Step 2.8 — Critique Loop section header present in SKILL.md.
grep -Fq "## Step 2.8 — Critique Loop" "$SKILL_MD" \
  || fail "SKILL.md must contain a '## Step 2.8 — Critique Loop' section header (#517 Check 46)"

# Check 47 (#517): SKILL.md Step 2.8 must register the new step in the Step Name
# Registry table with short name 'critique loop'.
grep -Fq "| 2.8 | critique loop |" "$SKILL_MD" \
  || fail "SKILL.md Step Name Registry must list '2.8 | critique loop' row (#517 Check 47)"

# Check 48 (#517): the post-Step-2 budget gate is RELOCATED to fire after Step 2.8
# (single gate, count critique tokens under existing 'validation' phase enum per
# dialectic DECISION_4). The relocated abort message must read 'Aborting before
# Step 3' and must NOT carry the stale 'Aborting before Step 2.5' literal at the
# relocated site. Pin both the new literal AND the absence of the old literal in
# any 'after Step 2.8' context.
grep -Fq "exceeded after Step 2.8" "$SKILL_MD" \
  || fail "SKILL.md must contain the relocated post-Step-2.8 budget-gate abort message literal 'exceeded after Step 2.8' (#517 Check 48)"
grep -Fq "Aborting before Step 3" "$SKILL_MD" \
  || fail "SKILL.md must contain the relocated post-Step-2.8 abort message literal 'Aborting before Step 3' (#517 Check 48)"
# The old gate's abort message (post-Step-2 → Step 2.5) must NOT survive the
# relocation. Failing this assertion means the relocation was incomplete — both
# the old and new gates were left in place.
grep -Fq "exceeded after Step 2 (" "$SKILL_MD" \
  && fail "SKILL.md must NOT carry the stale post-Step-2 abort message 'exceeded after Step 2 (' after relocation to post-Step-2.8 (#517 Check 48)"

# Check 49 (#517): SKILL.md Step 2.8 must carry a quick-mode skip directive.
# Quick scale skips Step 2.8 entirely (no validation findings to feed the
# critique pass — per /design Round 1 user decision).
grep -Fq "2.8: critique loop — skipped (--scale=quick)" "$SKILL_MD" \
  || fail "SKILL.md Step 2.8 must carry the quick-mode skip breadcrumb literal '2.8: critique loop — skipped (--scale=quick)' (#517 Check 49)"

# Check 50 (#564, supersedes #517 Check 50): SKILL.md "Measurable lanes" paragraph
# must enumerate every canonical token-tally slot name written by /research code
# paths via `token-tally.sh write --lane <slot>`. Paragraph-scoped (anchor-bounded
# by **Measurable lanes** opener and **Unmeasurable lanes** terminator) so future
# drift in unrelated SKILL.md sections cannot silently satisfy the assertion.
# Slot literals are checked as backtick-quoted forms (`<slot>`) to disambiguate
# prefix overlaps (e.g., `Code` substring of `Code-Arch`).
#
# Canonical slot names live in:
#   - skills/research/references/research-phase.md    (planner, Cursor, Codex,
#                                                       Cursor-Arch, Cursor-Edge,
#                                                       Codex-Ext, Codex-Sec, Synthesis)
#   - skills/research/references/validation-phase.md  (Code, Code-Sec, Code-Arch,
#                                                       Cursor, Codex, Revision)
#   - skills/research/references/adjudication-phase.md (Code, Cursor, Codex — judges)
#   - skills/research/references/critique-loop-phase.md (Critique-1, Critique-2,
#                                                       Revision-Critique-1,
#                                                       Revision-Critique-2)
# When a new measurable lane is added in code paths, update both the SKILL.md
# "Measurable lanes" paragraph AND the canonical_slots array below.
MEASURABLE_OPEN_LINES=$(grep -c '^\*\*Measurable lanes\*\*' "$SKILL_MD" || true)
[[ "$MEASURABLE_OPEN_LINES" == "1" ]] \
  || fail "SKILL.md must contain exactly one '**Measurable lanes**' opener line; found $MEASURABLE_OPEN_LINES (#564 Check 50)"
UNMEASURABLE_OPEN_LINES=$(grep -c '^\*\*Unmeasurable lanes\*\*' "$SKILL_MD" || true)
[[ "$UNMEASURABLE_OPEN_LINES" == "1" ]] \
  || fail "SKILL.md must contain exactly one '**Unmeasurable lanes**' terminator line; found $UNMEASURABLE_OPEN_LINES (#564 Check 50)"

MEASURABLE_LANES_PARAGRAPH=$(awk '
  /^\*\*Measurable lanes\*\*/ { in_block=1 }
  in_block && /^\*\*Unmeasurable lanes\*\*/ { exit }
  in_block { print }
' "$SKILL_MD")
[[ -n "$MEASURABLE_LANES_PARAGRAPH" ]] \
  || fail "SKILL.md 'Measurable lanes' paragraph extraction yielded empty content (#564 Check 50)"

canonical_slots=(
  planner
  Synthesis
  Revision
  Code
  Code-Sec
  Code-Arch
  Cursor
  Codex
  Cursor-Arch
  Cursor-Edge
  Codex-Ext
  Codex-Sec
  Critique-1
  Critique-2
  Revision-Critique-1
  Revision-Critique-2
)
for slot in "${canonical_slots[@]}"; do
  grep -Fq "\`$slot\`" <<<"$MEASURABLE_LANES_PARAGRAPH" \
    || fail "SKILL.md 'Measurable lanes' paragraph must enumerate canonical slot \`$slot\` (backtick-quoted) (#564 Check 50)"
done

# Check 51 (#517): the new critique-loop-phase.md must carry namespaced XML
# wrapper tag literals for the critique CONTEXT_BLOCK (FINDING_3 from plan
# review; mirrors the namespacing convention pinned by Check 6 for
# validation-phase.md). Using bare tag names like '<citation_validation>' would
# invite content-driven prompt-injection (a synthesis or sidecar containing a
# literal closing tag could terminate the block early).
grep -Fq "<reviewer_citation_validation>" "$CRITIQUE_LOOP_MD" \
  || fail "references/critique-loop-phase.md must carry the namespaced '<reviewer_citation_validation>' XML wrapper tag literal (#517 Check 51)"
grep -Fq "<reviewer_adjudication_resolutions>" "$CRITIQUE_LOOP_MD" \
  || fail "references/critique-loop-phase.md must carry the namespaced '<reviewer_adjudication_resolutions>' XML wrapper tag literal (#517 Check 51)"
grep -Fq "<reviewer_critique_findings>" "$CRITIQUE_LOOP_MD" \
  || fail "references/critique-loop-phase.md must carry the namespaced '<reviewer_critique_findings>' XML wrapper tag literal (#517 Check 51)"

# Check 52 (#543): research-phase.md Step 1.4 Quick subsection must invoke
# validate-research-output.sh per lane and document the truncation exclusion
# mechanism (`: > "$LANE_FILE"`) so validator-failed lanes are removed from the
# synthesis input. Without these pins, a future edit could silently drop the
# substantive gate or the truncation step, allowing thin/uncited K=3 lane
# outputs to slip through to the synthesis subagent (which lists all 3 lane
# paths in SYNTHESIS_PROMPT_QUICK_VOTE and only omits files whose content is
# "empty or unreadable" — substantively-failed but non-empty files would
# otherwise be merged).
#
# Pattern: same windowing as Check 16 — narrow to the `## 1.4` section first,
# then to the `### Quick (RESEARCH_SCALE=quick)` subsection. The literal
# `### Quick (RESEARCH_SCALE=quick)` appears 3x in research-phase.md (Step
# 1.3 Quick, Step 1.4 Quick, Step 1.5 Quick) so windowing on `## 1.4 ` first
# is required to avoid cross-section leakage.
# shellcheck disable=SC2016 # literal '$' chars in patterns; do not expand
QUICK_VALIDATOR_PIN='\$\{CLAUDE_PLUGIN_ROOT\}/scripts/validate-research-output\.sh'
# shellcheck disable=SC2016 # literal '$LANE_FILE' shell-syntax substring; do not expand
QUICK_TRUNCATE_PIN=': > "$LANE_FILE"'
# shellcheck disable=SC2016 # literal '$k' shell-syntax substring; do not expand
QUICK_BREADCRUMB_PIN='lane \$k: NOT_SUBSTANTIVE'
SECTION_1_4_QUICK=$(echo "$SECTION_1_4" \
  | awk '/^### Quick \(RESEARCH_SCALE=quick\)/{f=1; next} f && /^###/{f=0} f')
[[ -n "$SECTION_1_4_QUICK" ]] \
  || fail "references/research-phase.md must contain a '### Quick (RESEARCH_SCALE=quick)' subsection inside Step 1.4 — Check 52 cannot anchor without it (#543)"
echo "$SECTION_1_4_QUICK" | grep -Eq "$QUICK_VALIDATOR_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Quick subsection must invoke validate-research-output.sh per lane (#543 Check 52)"
echo "$SECTION_1_4_QUICK" | grep -Fq "$QUICK_TRUNCATE_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Quick subsection must document the truncation exclusion mechanism (': > \"\$LANE_FILE\"') so validator-failed lanes are excluded from synthesis (#543 Check 52)"
echo "$SECTION_1_4_QUICK" | grep -Eq "$QUICK_BREADCRUMB_PIN" \
  || fail "references/research-phase.md Step 1.4 ### Quick subsection must document the per-lane breadcrumb shape ('lane \$k: NOT_SUBSTANTIVE') (#543 Check 52)"

# Check 53 (#671 / supersedes #665): the two phase reference files
# 'adjudication-phase.md' and 'citation-validation-phase.md' must use the
# canonical tmpdir artifact name 'research-report.txt' AND must NOT carry
# the historical 'research-synthesis.txt' name (#665 — silent doc-drift
# regression where adjudication-phase.md referenced a nonexistent artifact).
# The .txt suffix scoping prevents false positives on legitimate prose like
# '## Research Synthesis' section headers or 'research-synthesis critique'
# mentions elsewhere in the doc tree.
for ref_file in "$ADJUDICATION_MD" "$CITATION_MD"; do
  if grep -Fq "research-synthesis.txt" "$ref_file"; then
    fail "$(basename "$ref_file") must NOT carry the historical artifact name 'research-synthesis.txt' — use 'research-report.txt' (#671 Check 53 / supersedes #665)"
  fi
  grep -Fq "research-report.txt" "$ref_file" \
    || fail "$(basename "$ref_file") must reference the canonical tmpdir artifact 'research-report.txt' at least once (#671 Check 53 / positive pin)"
done

# Check 54a (#671 / supersedes #666): the two skip preconditions in
# citation-validation-phase.md § 2.7.1 must be evaluated in the order
# 'Budget-abort gate (evaluated FIRST → proceed to Step 4)' BEFORE
# 'Empty-synthesis gate (evaluated SECOND → proceed to Step 3)' — matching
# SKILL.md Step 2.7's 'emitted FIRST' wording. #666 was a silent inversion
# of this order. Section-scoped via awk windowing (parallel to Check 32 /
# Check 52). Singleton anchor sanity guards against duplicated headings
# silently picking the wrong window (parallel to Check 50).
CITATION_271_HEADING_COUNT=$(grep -c "^### 2\.7\.1 — Skip preconditions" "$CITATION_MD" || true)
[[ "$CITATION_271_HEADING_COUNT" == "1" ]] \
  || fail "references/citation-validation-phase.md must contain exactly one heading matching prefix '### 2.7.1 — Skip preconditions' (actual on-disk heading: '### 2.7.1 — Skip preconditions (input gate)'); found $CITATION_271_HEADING_COUNT (#671 Check 54a)"

SECTION_271=$(awk '
  /^### 2\.7\.1 — Skip preconditions/ { f=1; next }
  f && /^###/ { exit }
  f { print }
' "$CITATION_MD")
[[ -n "$SECTION_271" ]] \
  || fail "references/citation-validation-phase.md § 2.7.1 section extraction yielded empty content (#671 Check 54a)"

CITATION_BUDGET_COUNT=$(echo "$SECTION_271" | grep -cF "Budget-abort gate (evaluated FIRST" || true)
CITATION_EMPTY_COUNT=$(echo "$SECTION_271"  | grep -cF "Empty-synthesis gate (evaluated SECOND" || true)
[[ "$CITATION_BUDGET_COUNT" == "1" ]] \
  || fail "references/citation-validation-phase.md § 2.7.1 must contain exactly one 'Budget-abort gate (evaluated FIRST' anchor; found $CITATION_BUDGET_COUNT (#671 Check 54a / supersedes #666)"
[[ "$CITATION_EMPTY_COUNT" == "1" ]] \
  || fail "references/citation-validation-phase.md § 2.7.1 must contain exactly one 'Empty-synthesis gate (evaluated SECOND' anchor; found $CITATION_EMPTY_COUNT (#671 Check 54a / supersedes #666)"

CITATION_BUDGET_LINENO=$(echo "$SECTION_271" | grep -nF "Budget-abort gate (evaluated FIRST" | head -n 1 | cut -d: -f1)
CITATION_EMPTY_LINENO=$(echo "$SECTION_271"  | grep -nF "Empty-synthesis gate (evaluated SECOND" | head -n 1 | cut -d: -f1)
[[ "$CITATION_BUDGET_LINENO" -lt "$CITATION_EMPTY_LINENO" ]] \
  || fail "references/citation-validation-phase.md § 2.7.1: Budget-abort gate (line $CITATION_BUDGET_LINENO) must precede Empty-synthesis gate (line $CITATION_EMPTY_LINENO) — matches SKILL.md Step 2.7 'emitted FIRST' wording (#671 Check 54a / supersedes #666)"

# Check 54b (#671 / supersedes #666 — SKILL.md side): SKILL.md Step 2.7's
# 'Skip preconditions' paragraph must order the budget-abort skip breadcrumb
# BEFORE the empty-synthesis skip breadcrumb. Anchored on the unique
# '**Skip preconditions** (emitted FIRST' opener — Step 2.8 uses '(also
# emitted', so this anchor disambiguates Step 2.7 from Step 2.8.
# Paragraph-scoped (paragraph boundary = next blank line) so the check is
# resilient to a future reformat from single-line to multi-line layout —
# parallel to Check 54a's section-scoped pattern. Compares byte-offsets of
# the two unique skip-breadcrumb literals via bash parameter expansion
# (no awk -v shell-string-escape hazard).
SKILL_271_ANCHOR_COUNT=$(grep -cF "**Skip preconditions** (emitted FIRST" "$SKILL_MD" || true)
[[ "$SKILL_271_ANCHOR_COUNT" == "1" ]] \
  || fail "SKILL.md must contain exactly one '**Skip preconditions** (emitted FIRST' line (the canonical Step 2.7 skip-preconditions opener); found $SKILL_271_ANCHOR_COUNT (#671 Check 54b)"

SKILL_271_PARA=$(awk '
  /^\*\*Skip preconditions\*\* \(emitted FIRST/ { f=1 }
  f && /^$/ { exit }
  f { print }
' "$SKILL_MD")
[[ -n "$SKILL_271_PARA" ]] \
  || fail "SKILL.md Step 2.7 'Skip preconditions' paragraph extraction yielded empty content (#671 Check 54b)"

SKILL_271_BUDGET_BC="2.7: citation-validation — skipped (--token-budget aborted upstream)"
SKILL_271_EMPTY_BC="2.7: citation-validation — skipped (no synthesis to validate)"

SKILL_271_BUDGET_BC_COUNT=$(echo "$SKILL_271_PARA" | grep -cF "$SKILL_271_BUDGET_BC" || true)
SKILL_271_EMPTY_BC_COUNT=$(echo "$SKILL_271_PARA"  | grep -cF "$SKILL_271_EMPTY_BC" || true)
[[ "$SKILL_271_BUDGET_BC_COUNT" == "1" ]] \
  || fail "SKILL.md Step 2.7 'Skip preconditions' paragraph must contain exactly one budget-abort breadcrumb '$SKILL_271_BUDGET_BC'; found $SKILL_271_BUDGET_BC_COUNT (#671 Check 54b / supersedes #666)"
[[ "$SKILL_271_EMPTY_BC_COUNT" == "1" ]] \
  || fail "SKILL.md Step 2.7 'Skip preconditions' paragraph must contain exactly one empty-synthesis breadcrumb '$SKILL_271_EMPTY_BC'; found $SKILL_271_EMPTY_BC_COUNT (#671 Check 54b / supersedes #666)"

# Compute byte offsets via bash parameter expansion (no awk -v shell-string
# escape hazard). ${var%%"pattern"*} returns the prefix before the first
# occurrence of the literal pattern (when quoted); ${#prefix} is the
# byte-offset of the pattern's start.
PRE_BUDGET="${SKILL_271_PARA%%"$SKILL_271_BUDGET_BC"*}"
PRE_EMPTY="${SKILL_271_PARA%%"$SKILL_271_EMPTY_BC"*}"
[[ "${#PRE_BUDGET}" -lt "${#PRE_EMPTY}" ]] \
  || fail "SKILL.md Step 2.7 'Skip preconditions' paragraph: budget-abort breadcrumb (offset ${#PRE_BUDGET}) must precede empty-synthesis breadcrumb (offset ${#PRE_EMPTY}) — emitted-FIRST/empty-second ordering (#671 Check 54b / supersedes #666)"

echo "PASS: test-research-structure.sh — all 54 structural invariants hold"
exit 0
