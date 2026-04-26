#!/bin/bash
# Structural regression test for /implement SKILL.md + references/ topology (closes #234).
# Asserts 13 load-bearing invariants across skills/implement/SKILL.md and the five
# reference docs extracted from it. Complements scripts/test-implement-rebase-macro.sh,
# which owns the Rebase Checkpoint Macro mechanics; this harness owns top-level section
# headings, the MANDATORY ↔ reference-file binding, the focus-area CI-parity check,
# the no-`see Step N below|above` invariant in references/*.md, and (closes #323) the
# three load-bearing marker literals in anchor-comment-template.md plus the ≥3
# `anchor-comment-template.md` reference-count floor and ≥1 `pr-body-template.md`
# floor in SKILL.md (migrated from pr-body-template.md to anchor-comment-template.md
# as of umbrella #348 Phase 3). The cross-skill
# Consumer/Contract/When-to-load header triplet (formerly assertion 8 here, implement-
# scoped) moved to scripts/test-references-headers.sh as of #308 and now applies repo-
# wide to every skills/*/references/*.md. Intentional overlap: assertion (3) (single
# `## Rebase Checkpoint Macro` heading) and assertion (5) (verbosity literals) duplicate
# peer-harness assertions (A) and (D) respectively — accepted duplication per design-
# phase sketch consensus.
#
# Thirteen assertions:
#  (1) Exactly 1 `^## Load-Bearing Invariants$` heading in skills/implement/SKILL.md.
#  (2) Exactly 1 `^## NEVER List$` heading.
#  (3) Exactly 1 `^## Rebase Checkpoint Macro$` heading.
#  (4) At least 5 `MANDATORY — READ ENTIRE FILE` occurrences (floor, not ceiling),
#      AND each of the five expected reference filenames appears on a `MANDATORY —
#      READ ENTIRE FILE` line in SKILL.md (step-to-reference binding from design FINDING_7).
#  (5) Three byte-pinned verbosity-suppressed literal strings present in SKILL.md.
#  (6) CI-parity focus-area enum: at least one line in SKILL.md contains the literal
#      `code-quality / risk-integration / correctness / architecture` AND that same
#      line also contains `security`. Mirrors .github/workflows/ci.yaml L121/L125
#      (agent-sync job's UNQUOTED_FILES check). The single-line same-line pattern
#      prevents a false-pass when the five tokens appear in unrelated prose blocks
#      (e.g., the NEVER List) but the actual Cursor/Codex quick-review prompt strings
#      regress. Design FINDING_2.
#  (7) Five `skills/implement/references/*.md` files exist with expected names.
#  (8) Zero occurrences of `see Step N below` / `see Step N above` patterns inside any
#      references/*.md — progressive-disclosure invariant (references must not
#      back-reference parent SKILL.md step numbers with direction words).
#  (9) Load-bearing marker literals in skills/implement/references/anchor-comment-template.md
#      (closes #323; migrated from pr-body-template.md per umbrella #348 Phase 3):
#      (9a) three byte-pinned marker literals must be present in
#      anchor-comment-template.md (`Accepted OOS (GitHub issues filed)`,
#      `| OOS issues filed |`, `<details><summary>Execution Issues</summary>`) —
#      parsed and written at runtime by the Step 9a.1 OOS issue-filing pipeline
#      (anchor's `oos-issues` + `run-statistics` sections) and the Step 11
#      post-execution anchor refresh (anchor's `execution-issues` section).
#      Renaming or removing any marker silently breaks runtime behavior with no
#      other test failure. (9b) SKILL.md must reference `anchor-comment-template.md`
#      at least 3 times (one MANDATORY pointer at Step 0.5 + one prose binding in
#      Step 9a.1 + one prose binding in Step 11) to guard against a future edit
#      that keeps the MANDATORY pointer but orphans Step 9a.1 or Step 11 from the
#      extracted reference. (9c) SKILL.md must reference `pr-body-template.md` at
#      least 1 time (the MANDATORY pointer at Step 9a) — lower floor than pre-Phase-3
#      since rich report content moved to anchor-comment-template.md.
# (10) Cross-skill bail-token pin (umbrella #348 Phase 4): skills/implement/SKILL.md
#      must contain the literal `IMPLEMENT_BAIL_REASON=adopted-issue-closed`.
#      `/fix-issue` Step 6a scans this token in captured `/implement` output to
#      branch to a specific warning + skip-to-cleanup path; the token literal
#      is simultaneously pinned in skills/fix-issue/SKILL.md by
#      skills/fix-issue/scripts/test-fix-issue-bail-detection.sh. A rename of
#      the token is therefore a dual-repo change caught by CI.
# (11) Phase 5 (umbrella #348) rebase-rebump-subprocedure.md reference set.
#      Sub-procedure step 6 retargeted from PR-body refresh to anchor
#      `version-bump-reasoning` refresh:
#      (11a) references `anchor-comment-template.md` ≥1 (Contract citation).
#      (11b) references `tracking-issue-read.sh --sentinel` ≥1 (Step 6a).
#      (11c) references `assemble-anchor.sh` ≥1 AND `upsert-anchor` ≥1 (Step 6d,e).
#      (11d) zero invocation lines of `${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh`
#            or `${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh` — scoped to
#            invocation patterns to preserve historical/prose mentions (per
#            design FINDING_7). A lingering invocation is a Phase 5 regression.
# (12) Phase 5 single-source-of-truth invariant for SECTION_MARKERS:
#      (12a) tracking-issue-write.sh must reference `anchor-section-markers.sh`
#            (the shared source-of-truth helper).
#      (12b) tracking-issue-write.sh must NOT contain a standalone
#            `SECTION_MARKERS=(` declaration — any re-inline would silently
#            diverge its ordering from assemble-anchor.sh.
# (13) Orchestrator-judgment-bail invariant (closes #553): two byte-pinned
#      anchor literals must be present in skills/implement/SKILL.md so future
#      edits cannot silently delete the rule — the headline of NEVER #7 and the
#      headline of the Step 2 "scope-lock" cue. Mirrors the byte-pin pattern of
#      assertion (5).
#
# Exit 0 on pass, exit 1 on any assertion failure.
# shellcheck disable=SC2016 # single-quoted strings are intentional grep literals
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/implement/SKILL.md"
REFS_DIR="$REPO_ROOT/skills/implement/references"

expected_refs=(
  "anchor-comment-template.md"
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
# (4) MANDATORY — READ ENTIRE FILE: at least 5 occurrences AND each expected
#     reference filename appears on a MANDATORY line (step-to-reference binding).
# ---------------------------------------------------------------------------
# Use `|| true` to keep set -e + pipefail from aborting before the fail() diagnostic
# when there are zero matches (grep -o exits 1 on no match, which propagates via pipefail).
occurrences=$(grep -o 'MANDATORY — READ ENTIRE FILE' "$SKILL_MD" 2>/dev/null | wc -l | tr -d ' ' || true)
if ! [[ "$occurrences" =~ ^[0-9]+$ ]] || (( occurrences < 5 )); then
  fail "(4) expected at least 5 'MANDATORY — READ ENTIRE FILE' occurrences in SKILL.md, found ${occurrences:-0}"
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
# (7) Five expected references/*.md files exist.
# ---------------------------------------------------------------------------
for ref in "${expected_refs[@]}"; do
  [[ -f "$REFS_DIR/$ref" ]] \
    || fail "(7) expected reference file missing: skills/implement/references/$ref"
done

# ---------------------------------------------------------------------------
# (8) Zero 'see Step N below' / 'see Step N above' patterns in any references/*.md.
#     Pattern is narrow: requires both a step number AND a direction word (below|above).
#     Permits legitimate cross-refs like 'see Step 8' with no direction word.
#     Case-insensitive: catches sentence-initial 'See Step 8 below' variants.
#     The step-number token is `[0-9][0-9a-z.]*` so bare digits (`8`), letter-suffix
#     forms (`9a`), and dotted substep forms (`9a.1`, `3c.2`) are all caught — matching
#     /implement's dotted substep numbering (closes #253).
#     Scans every *.md under references/ (not just the five expected refs) so new
#     reference files added in the future are covered automatically — the contract
#     documented in the header and scripts/test-implement-structure.md (sibling contract) covers "references/*.md" generally.
#     Cross-skill Consumer/Contract/When-to-load header-triplet invariant lives in
#     scripts/test-references-headers.sh as of #308, not here.
# ---------------------------------------------------------------------------
shopt -s nullglob
ref_files=( "$REFS_DIR"/*.md )
shopt -u nullglob
[[ "${#ref_files[@]}" -gt 0 ]] \
  || fail "(8) no .md files found under $REFS_DIR — cannot validate the 'see Step N below|above' invariant"

match_files=""
for ref_path in "${ref_files[@]}"; do
  if grep -qiE 'see Step [0-9][0-9a-z.]* (below|above)' "$ref_path"; then
    match_files="$match_files $(basename "$ref_path")"
  fi
done
if [[ -n "$match_files" ]]; then
  fail "(8) found forbidden 'see Step N below|above' patterns (case-insensitive) in:$match_files"
fi

# ---------------------------------------------------------------------------
# (9a) Three load-bearing marker literals must appear at least once in
#      skills/implement/references/anchor-comment-template.md (migrated from
#      pr-body-template.md per umbrella #348 Phase 3). Step 9a.1 (OOS
#      issue-filing pipeline) parses and rewrites the OOS placeholder and the
#      Run Statistics OOS cell in the anchor's `oos-issues` + `run-statistics`
#      sections; Step 11 (post-execution anchor refresh) locates and rewrites
#      the Execution Issues details block in the anchor's `execution-issues`
#      section. A future rename or removal in anchor-comment-template.md
#      silently breaks runtime behavior with no other test failure. Use
#      fixed-string matching since the literals contain regex metachars.
# ---------------------------------------------------------------------------
ANCHOR_TEMPLATE="$REFS_DIR/anchor-comment-template.md"
anchor_markers=(
  'Accepted OOS (GitHub issues filed)'
  '| OOS issues filed |'
  '<details><summary>Execution Issues</summary>'
)
for marker in "${anchor_markers[@]}"; do
  grep -Fq "$marker" "$ANCHOR_TEMPLATE" \
    || fail "(9a) anchor-comment-template.md lost load-bearing marker literal: $marker"
done

# ---------------------------------------------------------------------------
# (9b) skills/implement/SKILL.md must reference `anchor-comment-template.md`
#      at least 3 times — one MANDATORY pointer at Step 0.5 + one prose
#      binding in Step 9a.1 + one prose binding in Step 11's post-execution
#      anchor refresh. Assertion (4) already checks the MANDATORY line exists;
#      this guards against a future edit that keeps the MANDATORY pointer but
#      orphans Step 9a.1 or Step 11 from the extracted reference (both steps
#      delegate their procedure to anchor-comment-template.md sections).
#      Use fixed-string matching so the `.` in the filename is literal.
# ---------------------------------------------------------------------------
anchor_refs=$(grep -cF 'anchor-comment-template.md' "$SKILL_MD" || true)
if ! [[ "$anchor_refs" =~ ^[0-9]+$ ]] || (( anchor_refs < 3 )); then
  fail "(9b) expected at least 3 references to 'anchor-comment-template.md' in SKILL.md (Step 0.5 MANDATORY + Step 9a.1 binding + Step 11 binding), found ${anchor_refs:-0}"
fi

# ---------------------------------------------------------------------------
# (9c) skills/implement/SKILL.md must reference `pr-body-template.md` at
#      least 1 time — the MANDATORY pointer at Step 9a. Lower floor than
#      pre-Phase-3 (was >=3) since rich report content moved to
#      anchor-comment-template.md. Use fixed-string matching.
# ---------------------------------------------------------------------------
pr_body_refs=$(grep -cF 'pr-body-template.md' "$SKILL_MD" || true)
if ! [[ "$pr_body_refs" =~ ^[0-9]+$ ]] || (( pr_body_refs < 1 )); then
  fail "(9c) expected at least 1 reference to 'pr-body-template.md' in SKILL.md (Step 9a MANDATORY pointer), found ${pr_body_refs:-0}"
fi

# ---------------------------------------------------------------------------
# (10) Cross-skill bail-token pin (umbrella #348 Phase 4): SKILL.md must
#      contain the literal `IMPLEMENT_BAIL_REASON=adopted-issue-closed`.
#      `/implement` Step 0.5 Branch 2 emits this token on stdout when the
#      adopted tracking issue is CLOSED; `/fix-issue` Step 6a greps captured
#      output for it. Paired assertion on the consumer side lives in
#      skills/fix-issue/scripts/test-fix-issue-bail-detection.sh. Use
#      fixed-string matching since the literal contains `=`.
# ---------------------------------------------------------------------------
grep -Fq 'IMPLEMENT_BAIL_REASON=adopted-issue-closed' "$SKILL_MD" \
  || fail "(10) skills/implement/SKILL.md must contain the cross-skill bail token literal 'IMPLEMENT_BAIL_REASON=adopted-issue-closed'"

# ---------------------------------------------------------------------------
# (11) Phase 5 (umbrella #348) rebase-rebump-subprocedure.md reference set.
#      Sub-procedure step 6 retargeted from PR-body refresh to anchor
#      `version-bump-reasoning` refresh (via tracking-issue sentinel read +
#      assemble-anchor.sh + upsert-anchor). Assertions:
#      (11a) references anchor-comment-template.md ≥1 (Contract citation).
#      (11b) references `tracking-issue-read.sh --sentinel` ≥1 (Step 6a).
#      (11c) references `assemble-anchor.sh` ≥1 AND `upsert-anchor` ≥1 (Step 6d,e).
#      (11d) zero invocation lines of `gh-pr-body-read.sh` or `gh-pr-body-update.sh`
#            — scoped to invocation patterns (the literal
#            `${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-{read,update}.sh`) to
#            preserve historical/prose mentions if any remain (per design
#            FINDING_7). A lingering invocation is a Phase 5 regression.
# ---------------------------------------------------------------------------
REBASE_SUBPROC="$REFS_DIR/rebase-rebump-subprocedure.md"
[[ -f "$REBASE_SUBPROC" ]] || fail "(11) rebase-rebump-subprocedure.md missing: $REBASE_SUBPROC"

anchor_template_refs=$(grep -cF 'anchor-comment-template.md' "$REBASE_SUBPROC" || true)
if ! [[ "$anchor_template_refs" =~ ^[0-9]+$ ]] || (( anchor_template_refs < 1 )); then
  fail "(11a) expected at least 1 reference to 'anchor-comment-template.md' in rebase-rebump-subprocedure.md (Contract citation), found ${anchor_template_refs:-0}"
fi

sentinel_refs=$(grep -cF 'tracking-issue-read.sh --sentinel' "$REBASE_SUBPROC" || true)
if ! [[ "$sentinel_refs" =~ ^[0-9]+$ ]] || (( sentinel_refs < 1 )); then
  fail "(11b) expected at least 1 reference to 'tracking-issue-read.sh --sentinel' in rebase-rebump-subprocedure.md (Step 6a), found ${sentinel_refs:-0}"
fi

assemble_refs=$(grep -cF 'assemble-anchor.sh' "$REBASE_SUBPROC" || true)
if ! [[ "$assemble_refs" =~ ^[0-9]+$ ]] || (( assemble_refs < 1 )); then
  fail "(11c-1) expected at least 1 reference to 'assemble-anchor.sh' in rebase-rebump-subprocedure.md (Step 6d), found ${assemble_refs:-0}"
fi

upsert_refs=$(grep -cF 'upsert-anchor' "$REBASE_SUBPROC" || true)
if ! [[ "$upsert_refs" =~ ^[0-9]+$ ]] || (( upsert_refs < 1 )); then
  fail "(11c-2) expected at least 1 reference to 'upsert-anchor' in rebase-rebump-subprocedure.md (Step 6e), found ${upsert_refs:-0}"
fi

# (11d) No remaining invocation patterns. Match the literal
# `${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh` or `…/gh-pr-body-update.sh`
# only — historical prose mentions (e.g., "replaced the old gh-pr-body-*.sh")
# are allowed.
gh_pr_body_read_invocations=$(grep -cF '${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh' "$REBASE_SUBPROC" || true)
if ! [[ "$gh_pr_body_read_invocations" =~ ^[0-9]+$ ]] || (( gh_pr_body_read_invocations > 0 )); then
  fail "(11d-1) rebase-rebump-subprocedure.md still invokes 'gh-pr-body-read.sh' (found ${gh_pr_body_read_invocations:-0}); Phase 5 retargeted to assemble-anchor.sh + upsert-anchor"
fi
gh_pr_body_update_invocations=$(grep -cF '${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh' "$REBASE_SUBPROC" || true)
if ! [[ "$gh_pr_body_update_invocations" =~ ^[0-9]+$ ]] || (( gh_pr_body_update_invocations > 0 )); then
  fail "(11d-2) rebase-rebump-subprocedure.md still invokes 'gh-pr-body-update.sh' (found ${gh_pr_body_update_invocations:-0}); Phase 5 retargeted to assemble-anchor.sh + upsert-anchor"
fi

# ---------------------------------------------------------------------------
# (12) Phase 5 single-source-of-truth invariant for SECTION_MARKERS.
#      tracking-issue-write.sh must source anchor-section-markers.sh and
#      must NOT contain a standalone `SECTION_MARKERS=(` declaration
#      (the old inline declaration was removed; any re-inline would silently
#      diverge tracking-issue-write.sh's ordering from assemble-anchor.sh).
# ---------------------------------------------------------------------------
TRACKING_WRITE_SH="$REPO_ROOT/scripts/tracking-issue-write.sh"
[[ -f "$TRACKING_WRITE_SH" ]] || fail "(12) tracking-issue-write.sh missing: $TRACKING_WRITE_SH"

markers_sourced=$(grep -cF 'anchor-section-markers.sh' "$TRACKING_WRITE_SH" || true)
if ! [[ "$markers_sourced" =~ ^[0-9]+$ ]] || (( markers_sourced < 1 )); then
  fail "(12a) tracking-issue-write.sh must reference 'anchor-section-markers.sh' (source-of-truth helper); found ${markers_sourced:-0}"
fi

inline_markers=$(grep -cE '^[[:space:]]*SECTION_MARKERS=\(' "$TRACKING_WRITE_SH" || true)
if ! [[ "$inline_markers" =~ ^[0-9]+$ ]] || (( inline_markers > 0 )); then
  fail "(12b) tracking-issue-write.sh must NOT contain a standalone 'SECTION_MARKERS=(' declaration (now lives in anchor-section-markers.sh); found ${inline_markers:-0}"
fi

# ---------------------------------------------------------------------------
# (13) Orchestrator-judgment-bail invariant (closes #553): two byte-pinned
#      anchor literals must be present in skills/implement/SKILL.md so future
#      edits cannot silently delete the rule. The two literals are the
#      headline of NEVER #7 and the headline of the Step 2 "scope-lock" cue.
#      Both literals are byte-unique within SKILL.md by construction (each is
#      a distinctive headline), so the whole-file fixed-string check is
#      sufficient — this assertion guards against deletion, not against
#      relocation. Mirrors the pattern of assertion (5)'s verbosity literal
#      list.
# ---------------------------------------------------------------------------
never7_literals=(
  'NEVER bail mid-run on orchestrator-judgment "scope" or "capacity" concerns without a mechanical justification.'
  '**No mid-run scope re-litigation.**'
)
for lit in "${never7_literals[@]}"; do
  grep -Fq "$lit" "$SKILL_MD" \
    || fail "(13) SKILL.md lost orchestrator-judgment-bail invariant literal: $lit"
done

echo "PASS: test-implement-structure.sh — all 13 structural invariants hold"
exit 0
