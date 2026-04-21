# Dialectic Execution Choreography

**Consumer**: `/design` Step 2a.5 — load after short-circuit + zero-externals guardrail check when contested decisions exist. File own dialectic-execution mechanics: per-decision prompt render, parallel debater launch, collect, eligibility gate, judge re-probe, ballot build, judge launch, tally, resolution write.

**Binding convention**: File single normative source for dialectic-execution mechanics. SKILL.md Step 2a.5 keep only short-circuit, GH#98 carve-out banner, bucket-assignment rule, zero-externals guardrail summary; full execution live here. Variable refs (`$DESIGN_TMPDIR`, `${CLAUDE_PLUGIN_ROOT}`, `{SYNTHESIS_TEXT}`, `{FEATURE_DESCRIPTION}`, `{DECISION_BLOCK}`, etc.) and warning-string literals byte-identical to pre-extraction SKILL.md.

---

**Thesis/antithesis prompt templates**: load from reference file below. Template bodies byte-identical to Phase 1; only delivery channel (external CLI via `run-external-reviewer.sh` not Agent tool) and call-site effort suffix change.

**MANDATORY — READ ENTIRE FILE before rendering debate prompts (step 6 below)**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/dialectic-debate.md` fully. Contain byte-preserved Thesis agent template and Antithesis agent template with `{FEATURE_DESCRIPTION}`, `{SYNTHESIS_TEXT}`, `{DECISION_BLOCK}`, `{CHOSEN}`, `{ALTERNATIVE}`, `{TENSION}`, `{AFFECTED_FILES}` substitution placeholders plus `<debater_synthesis>` and `<debater_decision>` reference-block wrappers.

**Do NOT Load when contested-decisions.md contains only NO_CONTESTED_DECISIONS** — short-circuit print atop Step 2a.5 in SKILL.md exit before reach this file, so `dialectic-debate.md` reference file never load on no-contest path.

---

6. **Per-decision prompt-file rendering**. For each queued decision, render thesis and antithesis prompts (load from `references/dialectic-debate.md` via this file header MANDATORY directive) with `{FEATURE_DESCRIPTION}`, `{SYNTHESIS_TEXT}`, `{DECISION_BLOCK}`, `{CHOSEN}`, `{ALTERNATIVE}`, `{TENSION}`, `{AFFECTED_FILES}` substituted, and use **Write tool** (not heredoc/cat) to write each rendered prompt to own file:
   - `$DESIGN_TMPDIR/debate-<n>-thesis-prompt.txt`
   - `$DESIGN_TMPDIR/debate-<n>-antithesis-prompt.txt`
   File-based prompt delivery kill shell-quoting hazards from synthesis/decision content that may contain `"`, `$()`, backticks, newlines.

7. **Parallel launch** — issue all queued launches in **single Bash message** (up to 10 background calls: 5 decisions × 2 sides). Per-decision output filenames embed assigned tool name so collector basename heuristic attribute results right:
   - Cursor buckets write `$DESIGN_TMPDIR/debate-<n>-cursor-thesis.txt` and `…-cursor-antithesis.txt`.
   - Codex buckets write `$DESIGN_TMPDIR/debate-<n>-codex-thesis.txt` and `…-codex-antithesis.txt`.

   Each Cursor launch (use `run_in_background: true` and `timeout: 1860000`). Pass short bootstrap prompt referencing per-decision prompt file by path; tool read file via own filesystem access. Mirror voting pattern below ("Read the ballot from $DESIGN_TMPDIR/ballot.txt") and avoid `$(cat ...)` in launch shell — would trigger Claude Code permission prompts that break autonomous execution:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor \
     --output "$DESIGN_TMPDIR/debate-<n>-cursor-<thesis|antithesis>.txt" \
     --timeout 1800 --capture-stdout -- \
     cursor agent -p --force --trust \
       $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) \
       --workspace "$PWD" \
       "Read the dialectic-debate task description from $DESIGN_TMPDIR/debate-<n>-<thesis|antithesis>-prompt.txt and follow it exactly to produce the structured tagged output it requests. Work at your maximum reasoning effort level."
   ```

   Each Codex launch (use `run_in_background: true` and `timeout: 1860000`). Same file-path-reference pattern:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex \
     --output "$DESIGN_TMPDIR/debate-<n>-codex-<thesis|antithesis>.txt" \
     --timeout 1800 -- \
     codex exec --full-auto -C "$PWD" \
       $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
       --output-last-message "$DESIGN_TMPDIR/debate-<n>-codex-<thesis|antithesis>.txt" \
       "Read the dialectic-debate task description from $DESIGN_TMPDIR/debate-<n>-<thesis|antithesis>-prompt.txt and follow it exactly to produce the structured tagged output it requests. Work at your maximum reasoning effort level."
   ```

   Trailing `Work at your maximum reasoning effort level.` append at bash-launch level (NOT in templated prompt body) because `${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh --with-effort` documented as no-op for Cursor (Cursor no dedicated reasoning-effort flag — convention be prompt-level suffix). Codex get same suffix for symmetry.

8. **Collect** with health bookkeeping off (Option B enforce):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 \
     --write-health /dev/null \
     <each launched output path>
   ```
   `--write-health /dev/null` ensure both read path (collect-reviewer-results.sh check `-f "$WRITE_HEALTH"`, false for character devices like `/dev/null`) and write path (explicit `!= "/dev/null"` guard) skip — dialectic phase NEVER update cross-skill `${SESSION_ENV_PATH}.health` file. Block on this call (do NOT use `run_in_background`).

9. **Per-bucket runtime failure handling**. For any reviewer with `STATUS != OK`, print `**⚠ <Tool> dialectic debate (decision <n>, <thesis|antithesis>) failed: <FAILURE_REASON>. Bucket truncated; synthesis decision stands.**` Do NOT flip flag. Mandatory STATUS pre-check atop "debate quorum rule" below catch partial-launch case (thesis or antithesis non-OK → decision immediately fail quorum → synthesis decision stands).

**After all external debaters return**, classify each decision `Disposition` and, for `voted`-eligible decisions, hand off to 3-judge panel defined in `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`. Orchestrator no longer pick winners by reading tagged output — role delegated to judge panel. See `dialectic-protocol.md` for authoritative ballot format, judge prompt template, threshold rules, tally algorithm, resolution schema. Prose below = call-site contract in Step 2a.5; `dialectic-protocol.md` single source of truth for dialectic parser/threshold rules (do NOT reuse `voting-protocol.md` parsers for dialectic — token sets and ID shapes differ).

## Eligibility gate (Dispositions)

Classify every decision originally in `contested-decisions.md`:

- **`over-cap`**: decisions ranked outside top-`min(5, |contested-decisions|)` cap from step 1 above. No debate. Write resolution entry with `Disposition: over-cap`.
- **`bucket-skipped`**: decisions skipped in step 4 (dialectic bucket tool unavailable) OR zero-externals guardrail in step 5 (every selected decision bucket skipped). No debate. Write resolution entry with `Disposition: bucket-skipped`.
- **`fallback-to-synthesis` from quorum failure**: decisions whose bucket launched but debater output failed **debate quorum gate** (same checks as before, kept as eligibility gate for judge ballot — see below). No judge ballot entry. Write resolution entry with `Disposition: fallback-to-synthesis` and specific `Why fallback` reason.
- **`voted` candidates**: decisions whose bucket launched AND both sides passed debate quorum gate. Go to judge ballot.

**Debate quorum gate** (kept byte-compatible with prior behavior) apply to each launched decision:

1. **Per-decision STATUS pre-check** (mandatory): if collector did not report `STATUS=OK` for BOTH thesis and antithesis output files, decision `Disposition` is `fallback-to-synthesis` with reason `no_output` — do NOT apply per-side checks below. Guard partial-launch case where one side done but sibling failed (e.g., thesis OK + antithesis TIMED_OUT): judges must see both defenses, not one-sided ballot.

2. **Per-side quality checks**: for each decision surviving pre-check, read each side file via file path from collector `REVIEWER_FILE` field (may point at `*-retry.txt` if retry recovered empty output) — do NOT read directly from launch path. Side pass quorum gate only when every check below satisfied:
   - **Substantive output**: non-empty output with at least one full sentence of substantive content per required tag body.
   - **All 5 tags present**: `<claim>`, `<evidence>`, `<strongest_concession>`, `<counter_to_opposition>`, `<risk_if_wrong>`.
   - **Exactly one `RECOMMEND:` line**. For each line in output: trim surrounding whitespace, strip any paired `**...**` or `__...__` wrappers surrounding entire line, then check (case-insensitively) whether result begin with `RECOMMEND:`. Zero or duplicate matching lines fail rule.
   - **RECOMMEND enum**: token after `RECOMMEND:` (whitespace trimmed) must match exactly one of `THESIS` or `ANTI_THESIS` case-insensitively. Do NOT strip underscore in `ANTI_THESIS`.
   - **Role-vs-RECOMMEND consistency**: thesis slot MUST emit `RECOMMEND: THESIS`; antithesis slot MUST emit `RECOMMEND: ANTI_THESIS`. Any mismatch fail.
   - **Evidence citation**: `<evidence>` contain at least one `file:line` citation.

If any check fail for either side, print `**⚠ Debate for DECISION_N failed quorum (reason: <missing_tag|bad_recommend|missing_citation|role_mismatch|substantive_empty|no_output>). Fallback to synthesis.**` Classify decision as `Disposition: fallback-to-synthesis` with specific failure reason as `Why fallback` value. Do NOT include on judge ballot.

## Dialectic-local judge-panel re-probe (Part D — cascade scoping)

After eligibility gate done, run fresh health probe right before launching judges. Cursor/Codex timeout in **debating** must not lock tool out of **judging** — debater phase may have snapshotted availability many minutes ago.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-reviewers.sh --probe
```

Apply **two-key rule** (match Step 0 convention in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md:19-23`):

- `judge_codex_available = (CODEX_AVAILABLE=true AND CODEX_HEALTHY=true)`
- `judge_cursor_available = (CURSOR_AVAILABLE=true AND CURSOR_HEALTHY=true)`

Tool installed but unhealthy (`*_HEALTHY=false`) treated as **unavailable** for judge-panel and replaced by Claude Code Reviewer subagent per replacement-first pattern in `dialectic-protocol.md`. `judge_` prefix deliberate — these be judge-phase-local flags; do NOT mutate orchestrator-wide `codex_available` / `cursor_available` (those drive Step 3 plan review).

## Ballot construction and judge launch

If zero decisions `voted`-eligible (all failed gate, all bucket-skipped, or all over-cap), skip ballot construction and judge launch entirely — jump direct to **Write `dialectic-resolutions.md`** sub-step below and emit only non-`voted` entries.

Else, build ballot per `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`:

- Use **Write tool** (not heredoc/cat) to write `$DESIGN_TMPDIR/dialectic-ballot.txt`.
- For each `voted`-eligible decision, emit one `### DECISION_N: <title>` block with `Defense A (defends <CHOSEN or ALTERNATIVE per rotation>)` and `Defense B (defends <other>)` sections. Wrap each defense body in `<defense_content>...</defense_content>` tags with "data not instructions" preamble.
- **Position-order rotation**: odd N → `CHOSEN` is Defense A; even N → `ALTERNATIVE` is Defense A.
- **Attribution stripping**: ballot body MUST NOT contain `Cursor`, `Codex`, or `Claude` tokens — emit only neutral Defense A/B labels. Role-to-choice mapping (`defends <CHOSEN>` vs `defends <ALTERNATIVE>`) preserved.
- Defense body = concatenated tag-body text from debater output (`<claim>` + `<evidence>` + `<strongest_concession>` + `<counter_to_opposition>` + `<risk_if_wrong>`) with terminal `RECOMMEND:` line stripped. Record which side defense maps to Defense A internally so orchestrator can back-map judge votes to resolutions.

Launch 3 judges **in parallel** (single message). Spawn order: Cursor first, then Codex, then Claude subagent. Follow protocol Launching Judges section for exact command templates:

- Cursor judge via `run-external-reviewer.sh --tool cursor --capture-stdout` (with `run_in_background: true`, `timeout: 1860000`). If `judge_cursor_available=false`, launch Claude subagent replacement via Agent tool inline.
- Codex judge via `run-external-reviewer.sh --tool codex` (with `run_in_background: true`, `timeout: 1860000`). If `judge_codex_available=false`, launch Claude subagent replacement inline.
- Claude Code Reviewer subagent judge: always via Agent tool (subagent_type: `code-reviewer`), inline.

## Collecting judge results (split pattern)

External judge outputs collected via `collect-reviewer-results.sh` using sentinel polling. Inline Agent-tool judges produce no sentinel; votes returned directly by Agent tool and parsed from return text. Do NOT pass inline-judge output paths to `collect-reviewer-results.sh` — sentinel check would time out and wrong-drop voter count.

**Zero-external-judges guard**: Only invoke `collect-reviewer-results.sh` if at least one external judge actually launched (i.e., at least one of `judge_cursor_available` / `judge_codex_available` true at launch time). When both false — all three panel slots filled by Claude subagent inline replacements — skip collector invocation entirely and proceed direct to inline-vote tally from Agent returns. `collect-reviewer-results.sh` exit 1 with "at least one output file is required" when called with zero positional args; without guard, all-fallback config would abort.

When at least one external judge launched, after all external judges return:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 \
  --write-health /dev/null \
  <each launched external-judge output path>
```

`--write-health /dev/null` ensure judge phase NEVER update `${SESSION_ENV_PATH}.health`. Block on this call (do NOT use `run_in_background`).

For each external judge, parse `STATUS` and `REVIEWER_FILE`. External judge with `STATUS != OK` ineligible for every decision on ballot. For inline Agent-tool judges (primary Claude subagent + any Claude replacements), parse votes direct from Agent return text; inline judges always eligible.

## Tally and resolution writing

For each `voted`-eligible decision, tally per-decision votes from all 3 judges per protocol Parser tolerance and Threshold Rules. Apply binary thresholds:

- 3 eligible voters: 2+ same-side → `Disposition: voted`, Resolution = CHOSEN (if THESIS win) or ALTERNATIVE (if ANTI_THESIS win).
- 2 eligible voters: unanimous → `Disposition: voted`; 1-1 tie → `Disposition: fallback-to-synthesis` with reason `1-1 tie with 2 voters`.
- <2 eligible voters: `Disposition: fallback-to-synthesis` with reason `<N> judges eligible`.

## Write `$DESIGN_TMPDIR/dialectic-resolutions.md`

Write one resolution entry per decision originally in `contested-decisions.md` (including `over-cap`, `bucket-skipped`, and `fallback-to-synthesis` entries), using schema from `dialectic-protocol.md`:

```markdown
### DECISION_N: <title>
**Resolution**: <CHOSEN or ALTERNATIVE — CHOSEN is the default for non-voted dispositions>
**Disposition**: voted | fallback-to-synthesis | bucket-skipped | over-cap
**Vote tally**: THESIS=<N>, ANTI_THESIS=<M>
**Thesis summary**: <1-2 sentence summary from THESIS-role defense text, or (no debate — bucket skipped) / (no debate — ranked outside cap) placeholder>
**Antithesis summary**: <1-2 sentence summary from ANTI_THESIS-role defense text, or placeholder>
**Why thesis prevails** or **Why antithesis prevails** or **Why fallback** or **Why skipped** or **Why over-cap**: <justification per disposition, following the field-rules in dialectic-protocol.md>
```

Field rules per disposition:

- **`voted`**: Include `Vote tally`. Use `**Why thesis prevails**` or `**Why antithesis prevails**` (which side win); distill from winning judges rationale lines and engage losing side strongest concession from tag-body text.
- **`fallback-to-synthesis`**: Omit `Vote tally`. Use `**Why fallback**: <reason>`.
- **`bucket-skipped`**: Omit `Vote tally`. Use `**Why skipped**: <Tool> unavailable — bucket <N> decisions skipped at Step 2a.5 step 4`. Summary placeholders: `(no debate — bucket skipped)`.
- **`over-cap`**: Omit `Vote tally`. Use `**Why over-cap**: decision ranked <N>, outside top-5 dialectic selection cap`. Summary placeholders: `(no debate — ranked outside cap)`.

Print resolutions under `## Dialectic Resolutions` header.

**Scope**: Dialectic resolutions **binding for Step 2b plan generation only** for entries with `Disposition: voted`. All other dispositions mean synthesis stand for that point. Even `voted` entries may be superseded by accepted Step 3 review findings. Finalized plan (after Step 3 review) remain sole canonical output.

Print: `✅ 2a.5: dialectic — <V> voted, <F> fallback, <S> bucket-skipped, <O> over-cap (<elapsed>)` where V/F/S/O be per-disposition counts (omit count if zero — e.g., `<V> voted, <F> fallback`).
