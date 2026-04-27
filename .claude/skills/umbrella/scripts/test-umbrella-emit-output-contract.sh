#!/usr/bin/env bash
# test-umbrella-emit-output-contract.sh — Regression harness for /umbrella's
# Step 3B.3 dry-run skip directive, Step 3B.4 dry-run skip directive (matched
# pair with 3B.3), and Step 4 (Emit Output) prose contract.
#
# Pins the load-bearing literals in:
#   .claude/skills/umbrella/SKILL.md (Step 3B.3, Step 3B.4, Step 4 blocks)
#   .claude/skills/umbrella/scripts/helpers.md (emit-output subsection)
#
# Closes #602 — out-of-scope observation surfaced during /implement for #571
# (which fixed the original SKILL.md/helpers.md drift). Extended for #719 to
# pin the new Step 3B.3 dry-run guard and the matched-pair Step 3B.4 guard.
# The intent is a cheap CI guard against regression of the same drift;
# test-helpers.sh explicitly leaves emit-output out of scope (see
# test-helpers.md "Out of scope").
#
# This is a *structural* test (literal-substring assertions on awk-extracted
# blocks), not a runtime conformance test of `helpers.sh emit-output` (which
# remains exercised indirectly via SKILL.md integration). Pattern matches
# skills/fix-issue/scripts/test-fix-issue-bail-detection.sh.
#
# Wired into `make lint` via the `test-umbrella-emit-output-contract` Makefile
# target (parallel to test-umbrella-helpers and test-umbrella-parse-args).
#
# Run manually:
#   bash .claude/skills/umbrella/scripts/test-umbrella-emit-output-contract.sh
#
# Exits 0 on success, 1 on the first failed assertion.

# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals
set -euo pipefail

HERE=$(cd "$(dirname "$0")" && pwd)
SKILL_MD="$(cd "$HERE/.." && pwd)/SKILL.md"
HELPERS_MD="$HERE/helpers.md"

if [[ ! -f "$SKILL_MD" ]]; then
    echo "ERROR: SKILL.md not found: $SKILL_MD" >&2
    exit 1
fi
if [[ ! -f "$HELPERS_MD" ]]; then
    echo "ERROR: helpers.md not found: $HELPERS_MD" >&2
    exit 1
fi

# Extract the Step 4 block from SKILL.md: from "## Step 4 — Emit Output" up to
# (but not including) the next "## Step 5" prefix match. The end pattern is a
# prefix match (not the full heading) deliberately — it tolerates Step 5
# subtitle changes while still bounding the block.
STEP4_BLOCK=$(awk '
    /^## Step 4 — Emit Output/ { in_block=1 }
    /^## Step 5/ { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP4_BLOCK" ]]; then
    echo "FAIL: SKILL.md Step 4 block extraction produced empty output." >&2
    echo "  Boundary regexes: '^## Step 4 — Emit Output' (start) and '^## Step 5' (end)." >&2
    echo "  If Step 4's heading was renamed or renumbered, update both regexes here AND in" >&2
    echo "  the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
    exit 1
fi

# Extract the Step 3B.3 block from SKILL.md: from "### 3B.3 " (subheading prefix
# match — tolerates subtitle changes) up to (but not including) "### 3B.4 ".
STEP3B3_BLOCK=$(awk '
    /^### 3B\.3 / { in_block=1 }
    /^### 3B\.4 / { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP3B3_BLOCK" ]]; then
    echo "FAIL: SKILL.md Step 3B.3 block extraction produced empty output." >&2
    echo "  Boundary regexes: '^### 3B\\.3 ' (start) and '^### 3B\\.4 ' (end)." >&2
    echo "  If Step 3B.3 or Step 3B.4's heading was renamed or renumbered, update both regexes" >&2
    echo "  here AND in the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
    exit 1
fi

# Extract the Step 3B.4 block from SKILL.md: from "### 3B.4 " up to (but not
# including) "## Step 4 — Emit Output" (full heading anchor).
STEP3B4_BLOCK=$(awk '
    /^### 3B\.4 / { in_block=1 }
    /^## Step 4 — Emit Output/ { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP3B4_BLOCK" ]]; then
    echo "FAIL: SKILL.md Step 3B.4 block extraction produced empty output." >&2
    echo "  Boundary regexes: '^### 3B\\.4 ' (start) and '^## Step 4 — Emit Output' (end)." >&2
    echo "  If Step 3B.4 or Step 4's heading was renamed or renumbered, update both regexes" >&2
    echo "  here AND in the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
    exit 1
fi

# Extract the emit-output subsection from helpers.md: from "## `emit-output ..."
# up to (but not including) the first "### " heading (today: ### Edit-in-sync
# rules). The first-### end pattern is acceptable for now because emit-output
# has no internal ### headings on disk; if a future ### is added inside the
# section, this end pattern would truncate early — see sibling .md.
EMIT_OUTPUT_BLOCK=$(awk '
    /^## .emit-output/ { in_block=1 }
    /^### / { in_block=0 }
    in_block { print }
' "$HELPERS_MD")

if [[ -z "$EMIT_OUTPUT_BLOCK" ]]; then
    echo "FAIL: helpers.md emit-output block extraction produced empty output." >&2
    echo "  Boundary regexes: '^## .emit-output' (start) and '^### ' (end)." >&2
    echo "  If the emit-output subcommand heading was renamed, update both regexes here AND" >&2
    echo "  in the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
    exit 1
fi

PASS_COUNT=0

# Assertion helper — literal-substring presence check on a named block.
# Usage: assert_contains <label> <literal> <block_content>
# The block content is passed by value as the third positional argument so the
# helper has no implicit dependency on a shared variable name.
assert_contains() {
    local label="$1" literal="$2" block="$3"
    if grep -qF -- "$literal" <<<"$block"; then
        PASS_COUNT=$((PASS_COUNT + 1))
        echo "  PASS: $label"
    else
        echo "  FAIL: $label" >&2
        echo "    missing literal: $literal" >&2
        exit 1
    fi
}

echo "Running test-umbrella-emit-output-contract against:"
echo "  SKILL.md    = $SKILL_MD"
echo "  helpers.md  = $HELPERS_MD"
echo

# (a*) Step 4 prose attributes the human summary breadcrumb to the orchestrator
# (the LLM running this skill), NOT to the emit-output helper script.
assert_contains "a1: orchestrator-attribution sentence" \
    'the orchestrator (the LLM running this skill) MUST print exactly one human summary breadcrumb' \
    "$STEP4_BLOCK"
assert_contains "a2: single-emission-point invariant" \
    'Step 4 is the single emission point for this summary' \
    "$STEP4_BLOCK"

# (c*) The canonical breadcrumb shape templates remain present in SKILL.md
# Step 4. The issue spec lists four conceptual templates (one-shot success /
# dedup / failed; multi-piece success — including dry-run and partial-failure
# variants); on disk these expand to eight concrete breadcrumb literals
# (c6 and c6b are two literals for one conceptual partial case — fallback and
# UMBRELLA_FAILURE_REASON-parenthetical respectively). Pinning each concrete
# literal guards against silent shape deletion.
assert_contains "c1: one-shot filed" \
    '✅ /umbrella: filed #<N> — <url>' \
    "$STEP4_BLOCK"
assert_contains "c2: one-shot dedup'd" \
    "ℹ /umbrella: dedup'd to #<N> — <url>" \
    "$STEP4_BLOCK"
assert_contains "c3: one-shot failed" \
    '**⚠ /umbrella: failed — <error>**' \
    "$STEP4_BLOCK"
assert_contains "c4: multi-piece success" \
    '✅ /umbrella: filed umbrella #<M> with <N> children, <E> dependency edge(s), <B> back-link(s) — <umbrella-url>' \
    "$STEP4_BLOCK"
assert_contains "c5: multi-piece dry-run" \
    'ℹ /umbrella: dry-run — would file umbrella with <N> children' \
    "$STEP4_BLOCK"
assert_contains "c6: multi-piece partial — fallback (no UMBRELLA_FAILURE_REASON)" \
    '**⚠ /umbrella: <N> children created but umbrella creation failed. Children remain unlinked.**' \
    "$STEP4_BLOCK"
# (c6b) The parenthetical variant of the multi-piece partial breadcrumb, rendered
# when emit-output's `output.kv` carries `UMBRELLA_FAILURE_REASON`. SKILL.md Step 4
# documents both shapes for the same partial case (with-reason / fallback). The
# fallback is pinned by c6; without c6b, a future edit could remove or reword
# only the parenthetical variant unnoticed.
assert_contains "c6b: multi-piece partial — with UMBRELLA_FAILURE_REASON parenthetical" \
    '**⚠ /umbrella: <N> children created but umbrella creation failed (<UMBRELLA_FAILURE_REASON>). Children remain unlinked.**' \
    "$STEP4_BLOCK"
assert_contains "c7: multi-piece children-batch-failed (umbrella never attempted)" \
    '**⚠ /umbrella: /issue batch reported <F> failure(s); refusing to create a half-populated umbrella. <N> children remain unlinked.**' \
    "$STEP4_BLOCK"

# (b*) helpers.md emit-output subsection scopes stderr to validation errors
# only and explicitly defers the human breadcrumb to the orchestrator.
assert_contains "b1: emit-output stderr discipline" \
    'stderr is reserved for parse/validation/usage errors only' \
    "$EMIT_OUTPUT_BLOCK"
assert_contains "b2: emit-output non-emission of breadcrumb" \
    'the human summary breadcrumb is emitted by the orchestrator at SKILL.md Step 4 (single emission point), not by this script' \
    "$EMIT_OUTPUT_BLOCK"
# (b3) The wire-dag carve-out — guards against accidental over-broad scoping
# (e.g., a future PR removing the "wire-dag stderr unaffected" clause and
# inadvertently constraining wire-dag's stderr behavior). The literal includes
# the on-disk Markdown backticks around `wire-dag`.
# shellcheck disable=SC2016 # backticks are part of the on-disk markdown literal
assert_contains "b3: wire-dag stderr carve-out" \
    '`wire-dag`'"'"'s documented stderr warning behavior above is unaffected' \
    "$EMIT_OUTPUT_BLOCK"

# (d*) Step 3B.3 dry-run skip directive — pins the new dry-run guard added by
# issue #719. The shared "Skip this entire sub-step when DRY_RUN=true" prefix
# pattern is mirrored from Step 3B.4; pinning it in BOTH 3B.3 and 3B.4 (e1
# below) prevents the two parallel gates from drifting apart silently.
assert_contains "d1: 3B.3 dry-run skip directive prefix" \
    'Skip this entire sub-step when `DRY_RUN=true`' \
    "$STEP3B3_BLOCK"
assert_contains "d2: 3B.3 dry-run skip-line breadcrumb (folded — subsumes 3B.4 on dry-run path)" \
    '⏭️ /umbrella: umbrella body + umbrella create + dependency wiring + back-links skipped (--dry-run)' \
    "$STEP3B3_BLOCK"
assert_contains "d3: 3B.3 dry-run output.kv contract — UMBRELLA_NUMBER and UMBRELLA_URL omitted" \
    '`UMBRELLA_NUMBER` and `UMBRELLA_URL` **omitted** from `output.kv`' \
    "$STEP3B3_BLOCK"

# (e*) Step 3B.4 dry-run skip directive — the existing pre-#719 guard. Pinning
# the shared prefix here AND in 3B.3 (d1 above) is the matched-pair invariant
# the harness enforces so the two gates cannot drift apart.
assert_contains "e1: 3B.4 dry-run skip directive prefix (matched pair with d1)" \
    'Skip this entire sub-step when `DRY_RUN=true`' \
    "$STEP3B4_BLOCK"
assert_contains "e2: 3B.4 dry-run skip-line breadcrumb (existing pre-#719 wiring/back-links wording)" \
    '⏭️ /umbrella: dependency wiring + back-links skipped (--dry-run)' \
    "$STEP3B4_BLOCK"

echo
echo "All $PASS_COUNT assertions passed."
