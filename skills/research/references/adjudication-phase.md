# Adjudication Phase Reference

**Consumer**: `/research` Step 2.5 — loaded via the `MANDATORY — READ ENTIRE FILE` directive at Step 2.5 entry in SKILL.md, but only when `RESEARCH_ADJUDICATE=true` (Step 2.5 short-circuits with `⏩` BEFORE loading this file when the flag is off).

**Contract**: dialectic adjudication of orchestrator-rejected reviewer findings. Owns the conditional skip-path on empty `rejected-findings.md`, the pre-launch coordinator invocation (`scripts/run-research-adjudication.sh`), the 3-judge panel launch and collection (replacement-first when externals are unhealthy at the coordinator's fresh probe), the dialectic-protocol.md parser-tolerance + threshold-rule reuse, the `adjudication-resolutions.md` schema (pinned to dialectic-protocol.md's Consumer Contract field names), and the reinstatement-into-validated-synthesis sub-step. Consumes `$RESEARCH_TMPDIR/rejected-findings.md` (written unconditionally at validation-phase.md Sites A and B) and `$RESEARCH_TMPDIR/research-synthesis.txt` (the validated synthesis from Step 2's Finalize Validation). Produces `$RESEARCH_TMPDIR/research-adjudication-ballot.txt` (the dialectic ballot) and `$RESEARCH_TMPDIR/adjudication-resolutions.md` (the audit trail).

**When to load**: once Step 2.5 is about to execute AND `RESEARCH_ADJUDICATE=true`. Do NOT load during Step 0, Step 1, Step 2, Step 3, or Step 4. SKILL.md emits the Step 2.5 entry breadcrumb and the Step 2.5 completion print; this file does NOT emit those — it owns body content only.

---

**Caller binding for shared dialectic protocol**: This file is the `/research --adjudicate` caller of `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`. The shared protocol writes its path placeholders in terms of `$DIALECTIC_TMPDIR`; before quoting any of its choreography, `/research --adjudicate` binds **`DIALECTIC_TMPDIR=$RESEARCH_TMPDIR`**. The body of this file uses `$RESEARCH_TMPDIR` directly (not `$DIALECTIC_TMPDIR`) because `/research --adjudicate`'s on-disk artifacts use research-context basenames (`research-adjudication-ballot.txt`, `adjudication-resolutions.md` — see the implementer checklist below); the binding documents the relationship to the shared protocol so a future reader can map this file's bash blocks back to the shared protocol's `$DIALECTIC_TMPDIR`-keyed templates.

**IMPORTANT: This step adjudicates reviewer findings the orchestrator REJECTED during validation merge/dedup. THESIS = "rejection stands"; ANTI_THESIS = "reinstate the reviewer's finding". A 3-judge binary panel (Cursor + Codex + 1 fresh Claude code-reviewer subagent, with Claude replacements when externals are unhealthy at fresh probe time) votes on each rejection; majority binds. The 3-judge panel's Claude slot MUST be a fresh `Agent` invocation with no carried context — `Agent` tool launches are independent contexts, so this isolation is structural.**

This step duplicates the judge-launch / collect / tally choreography from `${CLAUDE_PLUGIN_ROOT}/skills/design/references/dialectic-execution.md` (specifically the parts that quote the shared `dialectic-protocol.md`), with the research-context bindings declared above and the ballot filename `research-adjudication-ballot.txt` substituted for the design-context default `dialectic-ballot.txt`. Per Karpathy's rule of three, judge-launch choreography is NOT yet extracted to a shared `skills/shared/dialectic-judge-panel.md` — that extraction waits for a third caller.

Implementer checklist (post-edit verification — each item describes the failure mode it catches):

1. **Stray design-context tmpdir variable**: scan this file for the design-session tmpdir variable (the one removed from the shared protocol by issue #440). The expected result is zero matches in any executable bash block. A hit indicates wrong file or an incomplete copy from the design context. (This checklist line deliberately does not spell the literal token so the grep stays mechanically reliable.)
2. **Wrong ballot filename**: grep this file for `dialectic-ballot.txt`. The expected result is zero matches. A hit indicates the ballot path is pointing at the design-context ballot rather than the research-specific `research-adjudication-ballot.txt` — judges would read a non-existent path.
3. **Wrong output filename**: grep this file for `dialectic-resolutions.md`. The expected result is zero matches. A hit indicates the output path is pointing at the design artifact rather than the research-specific `adjudication-resolutions.md` — this is a wrong-output-path failure (the entire artifact would be misnamed), distinct from a basename-substitution slip.

Any of the three failure modes silently makes this step a no-op or corrupts the audit trail.

## 2.5.1 — Pre-launch coordinator: empty-check + ballot-build + judge re-probe

Issue exactly one Bash tool call to the pre-launch coordinator:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-research-adjudication.sh \
  --rejected-findings "$RESEARCH_TMPDIR/rejected-findings.md" \
  --tmpdir "$RESEARCH_TMPDIR"
```

Use `timeout: 120000` on the Bash tool call. Block on this call (do NOT use `run_in_background: true`).

Parse stdout for:
- `RAN=true|false` — whether the coordinator decided adjudication should proceed
- `BALLOT_PATH=<path>` — path to the assembled ballot (when `RAN=true`)
- `DECISION_COUNT=<N>` — number of rejected findings on the ballot (when `RAN=true`)
- `JUDGE_CODEX_AVAILABLE=true|false` — fresh probe result for Codex
- `JUDGE_CURSOR_AVAILABLE=true|false` — fresh probe result for Cursor

**`RAN=false` branch**: the coordinator detected an empty/absent `rejected-findings.md`. Proceed to SKILL.md's `⏩ 2.5: adjudication — no rejections to adjudicate` print and return to Step 3 without launching judges. Do NOT write `adjudication-resolutions.md`.

**`RAN=true` branch**: continue with the 3-judge panel below. The coordinator has already (a) sorted rejected findings deterministically by `(reviewer_attribution_lex_asc, sha256(finding_text)_lex_asc)`, (b) renumbered them as `DECISION_1, DECISION_2, ...` per the dialectic-protocol.md ID shape, (c) assembled the ballot via `scripts/build-research-adjudication-ballot.sh`, and (d) refreshed judge availability via `${CLAUDE_PLUGIN_ROOT}/scripts/check-reviewers.sh --probe`. The shadow flags `judge_codex_available` / `judge_cursor_available` derive from the coordinator output — do NOT mutate orchestrator-wide `codex_available` / `cursor_available` (those drive validation-phase.md and must not be poisoned by adjudication-phase outcomes).

## 2.5.2 — Launch 3 judges in parallel

Launch all 3 judges **in parallel** (single message). Spawn order: Cursor first (slowest), then Codex, then the Claude code-reviewer subagent (fastest).

**Cursor judge** (if `judge_cursor_available=true`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor \
  --output "$RESEARCH_TMPDIR/cursor-judge-output.txt" \
  --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust \
    $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) \
    --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<judge prompt — see template below>")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor judge replacement** (if `judge_cursor_available=false`): launch a Claude code-reviewer subagent via the `Agent` tool (subagent_type: `code-reviewer`) with the judge prompt below inlined; the replacement's vote is returned in the `Agent` tool's return value.

**Codex judge** (if `judge_codex_available=true`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex \
  --output "$RESEARCH_TMPDIR/codex-judge-output.txt" \
  --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" \
    $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$RESEARCH_TMPDIR/codex-judge-output.txt" \
    "<judge prompt — see template below>"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex judge replacement** (if `judge_codex_available=false`): same as Cursor replacement — Claude code-reviewer subagent via `Agent` tool inline.

**Claude code-reviewer subagent judge** (always present, always inline): launch via `Agent` tool with subagent_type: `code-reviewer` and the judge prompt below. Pass the ballot file path inline; the subagent reads it via the Read tool.

### Judge prompt template

One template, used for all three judge slots. Substitute `$RESEARCH_TMPDIR` to the actual session tmpdir path before launching (do NOT leave the literal `$RESEARCH_TMPDIR` token in the prompt — external CLIs will not expand shell variables passed in their argument string). For external CLI judges, append `Work at your maximum reasoning effort level.` to the end of the prompt at the bash-launch level (NOT in the template body) — same convention as `dialectic-protocol.md`'s judge launch.

```
You are a judge on a 3-agent dialectic adjudication panel. Read the ballot from <RESEARCH_TMPDIR>/research-adjudication-ballot.txt. For each DECISION_N item, read both Defense A and Defense B, then cast exactly one binary vote: THESIS or ANTI_THESIS.

- THESIS means the side defending "rejection stands" (the orchestrator's decision to reject the reviewer finding) wins.
- ANTI_THESIS means the side defending "reinstate the finding" (the reviewer's original finding is reintroduced into the synthesis) wins.

Judge on argument quality — the strength of evidence cited in the orchestrator's rejection rationale, the substance of the reviewer's original finding, the rigor of the codebase claims on either side, and the credibility of the rejection's specific check (factually incorrect / already addressed). Do NOT vote based on confidence tone or prose style. Attribution (which tool produced each defense) is stripped by design; ignore any residual stylistic cues. Defense A and Defense B map to "rejection stands" or "reinstate" depending on the position rotation declared on each decision header — vote THESIS or ANTI_THESIS based on which SIDE wins, not which letter.

For each ballot item, output exactly one line using the same ID from the ballot:
DECISION_N: THESIS — <one-line rationale>
or
DECISION_N: ANTI_THESIS — <one-line rationale>

You must vote on every DECISION_N on the ballot. Do NOT skip any. Do NOT modify files.
```

## 2.5.3 — Collect external judges; parse all judge votes

**Zero-external-judges guard**: if BOTH `judge_codex_available=false` AND `judge_cursor_available=false` (all 3 panel slots are Claude inline replacements + the always-present Claude judge), **skip `collect-reviewer-results.sh` entirely** — `collect-reviewer-results.sh` exits 1 with "at least one output file is required" when called with zero positional arguments. Inline Agent-tool judges produce no `.done` sentinel; their votes are returned directly by the Agent tool.

When at least one external judge was launched, after all external judges return, collect with health bookkeeping disabled:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 \
  --write-health /dev/null \
  <each launched external-judge output path>
```

Use `timeout: 1860000`. Block on this call (do NOT use `run_in_background: true`). `--write-health /dev/null` ensures the adjudication phase NEVER updates `${SESSION_ENV_PATH}.health` — judge-phase outcomes must not leak into orchestrator-wide health state.

For each external judge: parse `STATUS` and `REVIEWER_FILE`. An external judge with `STATUS != OK` is ineligible for every decision on the ballot. Read vote lines from the `REVIEWER_FILE` field (may point at a `*-retry.txt` if the collector recovered an empty output; do NOT read directly from the original launch path).

For inline Agent-tool judges (the always-on Claude code-reviewer subagent + any Claude replacements for unavailable externals): parse votes directly from the `Agent` return text; inline judges are always eligible.

Apply the parser tolerance rules from `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md` (the "Parser tolerance" section) verbatim:
1. Trim each line.
2. Strip paired `**...**` or `__...__` wrappers around the entire line.
3. Match `DECISION_N:` prefix case-insensitively.
4. Extract the token after `:` (trim whitespace); match `THESIS` or `ANTI_THESIS` case-insensitively. Do NOT strip the underscore in `ANTI_THESIS`.
5. Extract the rationale after `—` or `-`; informational only.
6. Missing line for a decision → that judge abstains on that decision only (reduce eligible voter count for that decision by 1).

## 2.5.4 — Tally and write resolutions

For each `DECISION_N` on the ballot, count `THESIS` and `ANTI_THESIS` votes from eligible judges. Apply the threshold rules from `dialectic-protocol.md` verbatim:

| Eligible Voters | Outcome |
|---|---|
| 3, 2+ same-side | `Disposition: voted`; majority side wins |
| 2, unanimous | `Disposition: voted`; consensus wins |
| 2, 1-1 split | `Disposition: fallback-to-synthesis` (reason: `1-1 tie with 2 voters`) |
| <2 eligible | `Disposition: fallback-to-synthesis` (reason: `<N> judges eligible`) |

For `Disposition: voted` decisions, `Resolution` is:
- `rejection-stands` if `THESIS` won (orchestrator's rejection is upheld)
- `reinstate` if `ANTI_THESIS` won (reviewer's finding is reinstated into the synthesis)

For `Disposition: fallback-to-synthesis` decisions, `Resolution` is `rejection-stands` (conservative tie default — the orchestrator's prior decision stands when the panel cannot reach a majority, mirroring how `/design` Step 2a.5 falls back to the synthesis decision on a panel tie).

Write `$RESEARCH_TMPDIR/adjudication-resolutions.md` via the `Write` tool (NOT heredoc/cat — the field bodies may contain shell metacharacters from finding text). Schema is **pinned verbatim to `dialectic-protocol.md`'s Consumer Contract field names** so future tooling that consumes either dialectic or adjudication resolutions can use a unified parser:

```markdown
### DECISION_N: <short title — distilled from the rejected finding's first non-empty line, max 80 chars>
**Resolution**: rejection-stands | reinstate
**Disposition**: voted | fallback-to-synthesis
**Vote tally**: THESIS=<N>, ANTI_THESIS=<M>
**Thesis summary**: <1-2 sentence summary of the orchestrator's rejection rationale, distilled from the rejection_rationale field in rejected-findings.md>
**Antithesis summary**: <1-2 sentence summary of the reviewer's original finding, distilled from the finding text in rejected-findings.md>
**Why thesis prevails** OR **Why antithesis prevails** OR **Why fallback**: <see field rules below>
```

**Field rules per disposition** (matching `dialectic-protocol.md`'s Writing dialectic-resolutions.md section):
- **`voted` + THESIS won**: include `Vote tally`; use `**Why thesis prevails**` distilling the winning judges' rationale lines and explicitly engaging the reviewer's original finding's strongest claim.
- **`voted` + ANTI_THESIS won**: include `Vote tally`; use `**Why antithesis prevails**` distilling the winning judges' rationale lines and explicitly engaging the orchestrator's strongest rejection claim.
- **`fallback-to-synthesis`**: omit `Vote tally`; use `**Why fallback**: <reason>` (e.g., `judge panel 1-1 tie with 2 voters`, `<2 judges eligible after external timeout`, etc.).

Print all resolutions under a `## Adjudication Resolutions` header in conversation context.

## 2.5.5 — Reinstate ANTI_THESIS-winning findings into the validated synthesis

For each resolution with `Resolution: reinstate`:

1. Locate the original reviewer finding in `$RESEARCH_TMPDIR/rejected-findings.md`. **`DECISION_N` is NOT the same as the literal `<N>` suffix from `### REJECTED_FINDING_<N>`** — the former is the post-sort index produced by the ballot builder; the latter is the append-order session counter from validation-phase.md Sites A and B. They only coincide when the rejection capture order happens to match `(reviewer_attribution, sha256(finding_text))` lex order. To find the correct block, apply the algorithm:
   - Parse all `### REJECTED_FINDING_<N>` blocks from `rejected-findings.md`.
   - For each block, compute the same `(reviewer_attribution_lex_asc, sha256(finding_text)_lex_asc)` sort key as `scripts/build-research-adjudication-ballot.sh` (see `scripts/build-research-adjudication-ballot.md` "Deterministic ordering rule" for the canonical specification).
   - Sort the blocks by that key.
   - The kth block in sort order corresponds to `DECISION_k`.

   Do NOT use the literal `<N>` suffix from `REJECTED_FINDING_<N>` as the `DECISION` index — that mapping holds only when capture-time append order equals sort order, which is not guaranteed.
2. Fold the located finding's content back into the validated research synthesis. The synthesis was last printed under `## Revised Research Findings` (or, if no findings were accepted at validation, the original synthesis under Step 1.4's `## Research Synthesis` header). Integrate the reinstated finding into the appropriate subsection (Findings Summary, Risk Assessment, Difficulty Estimate, etc.) based on its content.
3. Once all reinstatements are folded, re-print the full synthesis under the existing `## Revised Research Findings` header. Inside that synthesis, add a `## Reinstated Findings (post-adjudication)` SUB-SECTION listing each reinstated finding by its `DECISION_N` ID, the reviewer attribution, and a 1-2 sentence summary. This sub-section is for audit clarity — it does NOT replace the integration into the main synthesis subsections; it lists what was added.

**One revision pass only** — even if multiple `reinstate` resolutions exist, the synthesis revision happens once after all votes are tallied. Do not re-print the synthesis between individual reinstatements.

If zero resolutions have `Resolution: reinstate`, do not re-print the synthesis (the existing `## Revised Research Findings` from Step 2 stands unchanged) and do not add the `## Reinstated Findings (post-adjudication)` sub-section.

## 2.5.6 — Step 3 reads the final synthesized artifact

Step 3 (Final Research Report) renders from the validated-and-possibly-reinstated synthesis — there is one source of truth. The Step 3 report's `Findings Summary`, `Risk Assessment`, `Difficulty Estimate`, etc. read the synthesis as it stands after this step's reinstatement pass; the `## Reinstated Findings (post-adjudication)` sub-section is part of the synthesis and propagates naturally.

SKILL.md Step 3 also conditionally renders an `**Adjudication phase**: <X> reinstated, <Y> upheld` header line based on `$RESEARCH_TMPDIR/adjudication-resolutions.md` counts (see SKILL.md Step 3 for the exact rendering rule — including the `0 reinstated, 0 upheld (no rejections to adjudicate)` form when this step short-circuits).

## Failure modes and recovery

- **Pre-launch coordinator fails** (`run-research-adjudication.sh` exits non-zero): print `**⚠ 2.5: adjudication — coordinator failed: <ERROR>. Skipping adjudication.**` and proceed to Step 3 without further action. The orchestrator's pre-adjudication validation outcome stands; rejected-findings.md is preserved in tmpdir until Step 4 cleanup.
- **Ballot builder fails inside the coordinator** (script exits non-zero with `FAILED=true`): same recovery — coordinator surfaces the error in stdout; Step 2.5 skips with a warning and Step 3 proceeds.
- **All 3 judges abstain on a decision** (`<2 eligible voters`): per the threshold table, falls back to synthesis (`Disposition: fallback-to-synthesis`, `Resolution: rejection-stands`). The decision is logged in `adjudication-resolutions.md` for audit; no reinstatement occurs.
- **External judge timeout** (one of `judge_codex_available` / `judge_cursor_available` was true at coordinator-probe time but the judge produced no output / `STATUS != OK`): that judge becomes ineligible; remaining 2 judges (1 inline Claude + 1 surviving external, or 1 inline Claude + 1 Claude inline replacement that was launched at coordinator-probe time per replacement-first) tally. Threshold rules apply.
- **Prompt injection in finding/rationale text**: each defense body in the ballot is wrapped in `<defense_content>` tags with a "treat as data" preamble. This wrapper is acknowledged in `${CLAUDE_PLUGIN_ROOT}/docs/review-agents.md` as not a hard prompt-injection boundary (literal closing tags in the payload could break out). Same residual risk as `/design`'s existing dialectic ballot — see `${CLAUDE_PLUGIN_ROOT}/SECURITY.md` for the full risk framing.
