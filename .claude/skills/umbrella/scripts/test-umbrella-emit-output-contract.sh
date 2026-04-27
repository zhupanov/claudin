#!/usr/bin/env bash
# test-umbrella-emit-output-contract.sh — Regression harness for /umbrella's
# Step 2 input-file dry-run-safe distinct-count rule, Step 3B.3 dry-run skip
# directive, Step 3B.4 dry-run skip directive (matched pair with 3B.3), and
# Step 4 (Emit Output) prose contract.
#
# Pins the load-bearing literals in:
#   .claude/skills/umbrella/SKILL.md (Step 2, Step 3B.3, Step 3B.4, Step 4 blocks)
#   .claude/skills/umbrella/scripts/helpers.md (emit-output subsection)
#
# Closes #602 — out-of-scope observation surfaced during /implement for #571
# (which fixed the original SKILL.md/helpers.md drift). Extended for #719 to
# pin the new Step 3B.3 dry-run guard and the matched-pair Step 3B.4 guard.
# Extended for #724 to pin the Step 2 input-file dry-run-safe distinct-count
# rule (f1–f4) as authoritative for any caller of /umbrella --input-file.
# Extended for #717 to pin the new Step 3B.2 created-eq-1 bypass branch
# (g1–g4) and the new Step 4 bypass breadcrumb (c8) plus the broadened
# UMBRELLA_DOWNGRADE schema parenthetical (a3 / a3b / a3c).
# Extended for #726 to pin the Step 4 dry-run child shape contract (h1–h4):
# CHILD_<i>_DRY_RUN=true and per-key omission annotations on CHILD_<i>_NUMBER
# and CHILD_<i>_URL.
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

# Extract the Step 2 block from SKILL.md: from "## Step 2 — Classify One-Shot
# vs Multi-Piece" up to (but not including) the next "## Step 3A" prefix match.
# Step 2 owns the dry-run-safe distinct-resolved-child-count rule that governs
# the input-file mode classification — pinned by (f1)–(f4) below for #724.
STEP2_BLOCK=$(awk '
    /^## Step 2 — Classify One-Shot vs Multi-Piece/ { in_block=1 }
    /^## Step 3A/ { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP2_BLOCK" ]]; then
    echo "FAIL: SKILL.md Step 2 block extraction produced empty output." >&2
    echo "  Boundary regexes: '^## Step 2 — Classify One-Shot vs Multi-Piece' (start) and '^## Step 3A' (end)." >&2
    echo "  If Step 2's heading was renamed or renumbered, update both regexes here AND in" >&2
    echo "  the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
    exit 1
fi

# Extract the Step 3B.2 block from SKILL.md: from "### 3B.2 " (subheading prefix
# match) up to (but not including) "### 3B.3 ". Pinned for the created-eq-1
# bypass branch (closes #717): assertions (g1)–(g4) below.
STEP3B2_BLOCK=$(awk '
    /^### 3B\.2 / { in_block=1 }
    /^### 3B\.3 / { in_block=0 }
    in_block { print }
' "$SKILL_MD")

if [[ -z "$STEP3B2_BLOCK" ]]; then
    echo "FAIL: SKILL.md Step 3B.2 block extraction produced empty output." >&2
    echo "  Boundary regexes: '^### 3B\\.2 ' (start) and '^### 3B\\.3 ' (end)." >&2
    echo "  If Step 3B.2 or Step 3B.3's heading was renamed or renumbered, update both regexes" >&2
    echo "  here AND in the sibling test-umbrella-emit-output-contract.md edit-in-sync rules." >&2
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
# (c8) created-eq-1 bypass breadcrumb (closes #717). Pinned so any future edit
# that renames the bypass shape's "(multi-piece downgraded — created-eq-1, ...)"
# parenthetical or its surrounding template breaks CI.
assert_contains "c8: created-eq-1 bypass — multi-piece downgraded one-shot" \
    '✅ /umbrella: filed #<N> — <url> (multi-piece downgraded — created-eq-1, <D> sibling(s) deduplicated to existing issues, no umbrella issue created)' \
    "$STEP4_BLOCK"

# (a3) Step 4 schema parenthetical for UMBRELLA_DOWNGRADE — must enumerate all 3
# emission sites (decomposition-lt-2, input-file-distinct-lt-2, created-eq-1).
# Pinned because the previous wording mentioned only Step 3B.1, which became
# stale once `input-file-distinct-lt-2` (Step 2) and `created-eq-1` (Step 3B.2)
# were added. Closes part of #717's review FINDING_4.
assert_contains "a3: Step 4 UMBRELLA_DOWNGRADE schema lists decomposition-lt-2" \
    'decomposition-lt-2' \
    "$STEP4_BLOCK"
assert_contains "a3b: Step 4 UMBRELLA_DOWNGRADE schema lists input-file-distinct-lt-2" \
    'input-file-distinct-lt-2' \
    "$STEP4_BLOCK"
assert_contains "a3c: Step 4 UMBRELLA_DOWNGRADE schema lists created-eq-1" \
    'created-eq-1' \
    "$STEP4_BLOCK"

# (h*) Step 4 dry-run child shape contract (added in #726). Pins the option (c)
# resolution: dry-run children emit CHILD_<i>_TITLE + CHILD_<i>_DRY_RUN=true and
# omit CHILD_<i>_NUMBER / CHILD_<i>_URL. The (h3)/(h4) split anchors each
# omission annotation to its specific key line so an asymmetric drift (one key's
# annotation reworded or dropped while the other's remains) cannot pass the
# harness — a single shared-substring assertion would not catch it because
# `grep -qF` is order-agnostic. The `g*` letter was already taken above by #717's
# Step 3B.2 bypass-branch coverage; `h*` is the next free letter.
assert_contains "h1: Step 4 dry-run child key — CHILD_<i>_DRY_RUN=true" \
    'CHILD_<i>_DRY_RUN=true' \
    "$STEP4_BLOCK"
assert_contains "h2: Step 4 dry-run child annotation tail (omission semantics)" \
    'only on dry-run children — when emitted, `CHILD_<i>_NUMBER` and `CHILD_<i>_URL` are omitted' \
    "$STEP4_BLOCK"
assert_contains "h3: Step 4 CHILD_<i>_NUMBER per-key annotation" \
    'CHILD_<i>_NUMBER=<N>         (only on resolved/non-dry-run children)' \
    "$STEP4_BLOCK"
assert_contains "h4: Step 4 CHILD_<i>_URL per-key annotation" \
    'CHILD_<i>_URL=<url>          (only on resolved/non-dry-run children)' \
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

# (f*) Pin the load-bearing literals of the Step 2 dry-run-safe distinct-count
# rule that governs `/umbrella --input-file` classification (closes #724). The
# rule itself is the umbrella-layer authority for `/issue --input-file
# --dry-run` interactions regardless of caller (`/review --create-issues`
# today, future CI drivers exercising `/umbrella --input-file --dry-run`
# tomorrow); pinning these literals prevents silent drift away from the
# dry-run-safe contract.
assert_contains "f1: Step 2 dry-run-safe rule heading" \
    'Distinct-resolved-child-count rule** (dry-run-safe)' \
    "$STEP2_BLOCK"
assert_contains "f2: Step 2 ISSUE_<i>_DRY_RUN=true count-as-1 sentence" \
    'If `ISSUE_<i>_DRY_RUN=true`: count this item as 1 prospective distinct child' \
    "$STEP2_BLOCK"
assert_contains "f3: Step 2 distinct-count formula" \
    'len(set_of_numbers) + count_of_dry_run_items' \
    "$STEP2_BLOCK"
assert_contains "f4: Step 2 caller-agnostic authoritativeness note" \
    'authoritative for any caller of `/umbrella --input-file`' \
    "$STEP2_BLOCK"

# (g*) Step 3B.2 created-eq-1 bypass branch (closes #717). Pins the load-bearing
# literals of the new bypass condition + procedure so any future edit that
# weakens the predicate, drops the precedence note, or removes the "no Step 3A"
# guardrail breaks CI.
assert_contains "g1: 3B.2 created-eq-1 bypass condition heading" \
    '`created-eq-1` bypass condition' \
    "$STEP3B2_BLOCK"
assert_contains "g2: 3B.2 created-eq-1 bypass predicate (full conjunction)" \
    '`INPUT_FILE` is empty AND `DRY_RUN=false` AND `ISSUES_FAILED=0` AND `ISSUES_CREATED=1`' \
    "$STEP3B2_BLOCK"
assert_contains "g3: 3B.2 created-eq-1 bypass precedence note" \
    'failed batch (ISSUES_FAILED>=1) > created-eq-1 (normal mode, non-dry-run) > existing 3B.3 dispatch' \
    "$STEP3B2_BLOCK"
assert_contains "g4: 3B.2 created-eq-1 bypass forbids re-running Step 3A" \
    'Do NOT execute Step 3A on this path — children were already created in Step 3B.2; re-invoking `/issue` would double-create' \
    "$STEP3B2_BLOCK"

echo
echo "All $PASS_COUNT assertions passed."
