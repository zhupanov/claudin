# Dialectic Execution Choreography

**Consumer**: `/design` Step 2a.5 — loaded after the short-circuit + zero-externals guardrail check when contested decisions exist. This file owns the dialectic-execution mechanics: per-decision prompt rendering, parallel debater launch, collection, eligibility gate, judge re-probe, ballot construction, judge launch, tally, and resolution writing.

**Contract**: single normative source for dialectic-execution mechanics — step-6 through final `✅ 2a.5: dialectic` print directive, including the nested MANDATORY pointer to `references/dialectic-debate.md`, the externals-only debate-path carve-out (GitHub issue #98), the Option B snapshot pattern via `dialectic_*_available` shadow flags, and the `dialectic-resolutions.md` schema for voted / fallback-to-synthesis / bucket-skipped / over-cap dispositions.

**When to load**: once Step 2a.5 has passed the short-circuit (`NO_CONTESTED_DECISIONS`) check. Do NOT load when `contested-decisions.md` contains only `NO_CONTESTED_DECISIONS`. On the zero-externals guardrail path (step 5 of Step 2a.5 in SKILL.md): debate-execution mechanics in this file MUST NOT fire (no debaters, no judges, no ballot) — skip loading entirely if the orchestrator already has the `dialectic-resolutions.md` schema in context from a prior run; otherwise a one-time load of this file is acceptable solely to consult the schema, but the per-decision prompt rendering, parallel debater launch, collection, eligibility gate, judge re-probe, ballot construction, judge launch, and tally steps remain suppressed. This mirrors the conditional permission granted by the SKILL.md caller contract at Step 2a.5.

**Binding convention**: This file is the single normative source for dialectic-execution mechanics. SKILL.md Step 2a.5 retains only the short-circuit, GH#98 carve-out banner, bucket-assignment rule, and zero-externals guardrail summary; the full execution procedure lives here. Variable references (`$DESIGN_TMPDIR`, `${CLAUDE_PLUGIN_ROOT}`, `{SYNTHESIS_TEXT}`, `{FEATURE_DESCRIPTION}`, `{DECISION_BLOCK}`, etc.) and warning-string literals are byte-identical to the pre-extraction SKILL.md source.

---

**Thesis/antithesis prompt templates**: these are loaded from the reference file below. Template bodies are byte-identical to Phase 1; only the delivery channel (external CLI via `run-external-reviewer.sh` rather than the Agent tool) and the call-site effort suffix change.

**MANDATORY — READ ENTIRE FILE before rendering debate prompts (step 6 below)**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/dialectic-debate.md` completely. It contains the byte-preserved Thesis agent template and Antithesis agent template with `{FEATURE_DESCRIPTION}`, `{SYNTHESIS_TEXT}`, `{DECISION_BLOCK}`, `{CHOSEN}`, `{ALTERNATIVE}`, `{TENSION}`, `{AFFECTED_FILES}` substitution placeholders plus the `<debater_synthesis>` and `<debater_decision>` reference-block wrappers.

**Do NOT Load when contested-decisions.md contains only NO_CONTESTED_DECISIONS** — the short-circuit print at the top of Step 2a.5 in SKILL.md exits before reaching this file, so the `dialectic-debate.md` reference file is naturally never loaded on the no-contest path.

---

6. **Per-decision prompt-file rendering**. For each queued decision, render the thesis and antithesis prompts (loaded from `references/dialectic-debate.md` loaded via this file's header MANDATORY directive) with `{FEATURE_DESCRIPTION}`, `{SYNTHESIS_TEXT}`, `{DECISION_BLOCK}`, `{CHOSEN}`, `{ALTERNATIVE}`, `{TENSION}`, `{AFFECTED_FILES}` substituted, and use the **Write tool** (not heredoc/cat) to write each rendered prompt to its own file:
   - `$DESIGN_TMPDIR/debate-<n>-thesis-prompt.txt`
   - `$DESIGN_TMPDIR/debate-<n>-antithesis-prompt.txt`
   File-based prompt delivery eliminates shell-quoting hazards from synthesis/decision content that may contain `"`, `$()`, backticks, or newlines.

7. **Parallel launch** — issue all queued launches in a **single Bash message** (up to 10 background calls: 5 decisions × 2 sides). Per-decision output filenames embed the assigned tool name so the collector's basename heuristic correctly attributes results:
   - Cursor buckets write to `$DESIGN_TMPDIR/debate-<n>-cursor-thesis.txt` and `…-cursor-antithesis.txt`.
   - Codex buckets write to `$DESIGN_TMPDIR/debate-<n>-codex-thesis.txt` and `…-codex-antithesis.txt`.

   Each Cursor launch (use `run_in_background: true` and `timeout: 1860000`). Pass a short bootstrap prompt that references the per-decision prompt file by path; the tool reads the file via its own filesystem access. This mirrors the voting pattern below ("Read the ballot from $DESIGN_TMPDIR/ballot.txt") and avoids `$(cat ...)` in the launch shell — which would trigger Claude Code permission prompts that break autonomous execution:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor \
     --output "$DESIGN_TMPDIR/debate-<n>-cursor-<thesis|antithesis>.txt" \
     --timeout 1800 --capture-stdout -- \
     cursor agent -p --force --trust \
       $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) \
       --workspace "$PWD" \
       "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "Read the dialectic-debate task description from $DESIGN_TMPDIR/debate-<n>-<thesis|antithesis>-prompt.txt and follow it exactly to produce the structured tagged output it requests. Work at your maximum reasoning effort level.")"
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

   The trailing `Work at your maximum reasoning effort level.` is appended at the bash-launch level (NOT in the templated prompt body) because `${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh --with-effort` is documented as a no-op for Cursor (Cursor has no dedicated reasoning-effort flag — the convention is the prompt-level suffix). Codex receives the same suffix for symmetry.

8. **Collect** with health bookkeeping disabled (Option B enforcement):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 \
     --write-health /dev/null \
     <each launched output path>
   ```
   `--write-health /dev/null` ensures both the read path (collect-reviewer-results.sh checks `-f "$WRITE_HEALTH"`, which is false for character devices like `/dev/null`) and the write path (explicit `!= "/dev/null"` guard) skip — the dialectic phase NEVER updates the cross-skill `${SESSION_ENV_PATH}.health` file. Block on this call (do NOT use `run_in_background`).

9. **Per-bucket runtime failure handling**. For any reviewer with `STATUS != OK`, print `**⚠ <Tool> dialectic debate (decision <n>, <thesis|antithesis>) failed: <FAILURE_REASON>. Bucket truncated; synthesis decision stands.**` Do NOT flip any flag. The mandatory STATUS pre-check at the top of the "debate quorum rule" below catches the partial-launch case (thesis or antithesis non-OK → decision immediately fails quorum → synthesis decision stands).

**After all external debaters return**, classify each decision's `Disposition` and, for `voted`-eligible decisions, hand off to the 3-judge panel defined in `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`. The orchestrator no longer picks winners by reading tagged output — that role is delegated to the judge panel. See `dialectic-protocol.md` for the authoritative ballot format, judge prompt template, threshold rules, tally algorithm, and resolution schema. The prose below is the call-site contract in Step 2a.5; `dialectic-protocol.md` is the single source of truth for dialectic parser/threshold rules (do NOT reuse `voting-protocol.md` parsers for dialectic — the token sets and ID shapes differ).

## Eligibility gate (Dispositions)

Classify every decision originally present in `contested-decisions.md`:

- **`over-cap`**: decisions ranked outside the top-`min(5, |contested-decisions|)` cap from step 1 above. No debate occurred. Write a resolution entry with `Disposition: over-cap`.
- **`bucket-skipped`**: decisions skipped in step 4 (dialectic bucket tool unavailable) OR the zero-externals guardrail in step 5 (every selected decision's bucket was skipped). No debate occurred. Write a resolution entry with `Disposition: bucket-skipped`.
- **`fallback-to-synthesis` from quorum failure**: decisions whose bucket was launched but whose debater output failed the **debate quorum gate** (same checks as before, retained as the eligibility gate for the judge ballot — see below). No judge ballot entry. Write a resolution entry with `Disposition: fallback-to-synthesis` and a specific `Why fallback` reason.
- **`voted` candidates**: decisions whose bucket was launched AND both sides passed the debate quorum gate. Go to the judge ballot.

The **debate quorum gate** (retained byte-compatible with prior behavior) is applied to each launched decision:

1. **Per-decision STATUS pre-check** (mandatory): if the collector did not report `STATUS=OK` for BOTH the thesis and the antithesis output files, the decision's `Disposition` is `fallback-to-synthesis` with reason `no_output` — do NOT apply the per-side checks below. This guards the partial-launch case where one side completed but its sibling failed (e.g., thesis OK + antithesis TIMED_OUT): judges must see both defenses, not a one-sided ballot.

2. **Per-side quality checks**: for each decision surviving the pre-check, read each side's file via the file path from the collector's `REVIEWER_FILE` field (may point at a `*-retry.txt` if a retry recovered an empty output) — do NOT read directly from the launch path. A side passes the quorum gate only when every check below is satisfied:
   - **Substantive output**: non-empty output with at least one full sentence of substantive content per required tag body.
   - **All 5 tags present**: `<claim>`, `<evidence>`, `<strongest_concession>`, `<counter_to_opposition>`, `<risk_if_wrong>`.
   - **Exactly one `RECOMMEND:` line**. For each line in the output: trim surrounding whitespace, strip any paired `**...**` or `__...__` wrappers that surround the entire line, then check (case-insensitively) whether the result begins with `RECOMMEND:`. Zero or duplicate matching lines fail the rule.
   - **RECOMMEND enum**: the token after `RECOMMEND:` (with whitespace trimmed) must match exactly one of `THESIS` or `ANTI_THESIS` case-insensitively. Do NOT strip the underscore in `ANTI_THESIS`.
   - **Role-vs-RECOMMEND consistency**: the thesis slot MUST emit `RECOMMEND: THESIS`; the antithesis slot MUST emit `RECOMMEND: ANTI_THESIS`. Any mismatch fails.
   - **Evidence citation**: `<evidence>` contains at least one `file:line` citation.

If any check fails for either side, print `**⚠ Debate for DECISION_N failed quorum (reason: <missing_tag|bad_recommend|missing_citation|role_mismatch|substantive_empty|no_output>). Fallback to synthesis.**` Classify the decision as `Disposition: fallback-to-synthesis` with the specific failure reason as the `Why fallback` value. Do NOT include it on the judge ballot.

## Dialectic-local judge-panel re-probe (Part D — cascade scoping)

After the eligibility gate finishes, run a fresh health probe right before launching judges. A Cursor/Codex timeout in **debating** must not lock that tool out of **judging** — the debater phase may have snapshotted availability many minutes ago.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-reviewers.sh --probe
```

Apply the **two-key rule** (matching the Step 0 convention in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md:19-23`):

- `judge_codex_available = (CODEX_AVAILABLE=true AND CODEX_HEALTHY=true)`
- `judge_cursor_available = (CURSOR_AVAILABLE=true AND CURSOR_HEALTHY=true)`

A tool that is installed but unhealthy (`*_HEALTHY=false`) is treated as **unavailable** for judge-panel purposes and replaced by a Claude Code Reviewer subagent per the replacement-first pattern in `dialectic-protocol.md`. The `judge_` prefix is deliberate — these are judge-phase-local flags; do NOT mutate orchestrator-wide `codex_available` / `cursor_available` (those drive Step 3 plan review).

## Ballot construction and judge launch

If zero decisions are `voted`-eligible (all failed the gate, all were bucket-skipped, or all were over-cap), skip ballot construction and judge launch entirely — jump directly to the **Write `dialectic-resolutions.md`** sub-step below and emit only the non-`voted` entries.

Otherwise, build the ballot per `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`:

- Use the **Write tool** (not heredoc/cat) to write `$DESIGN_TMPDIR/dialectic-ballot.txt`.
- For each `voted`-eligible decision, emit one `### DECISION_N: <title>` block containing `Defense A (defends <CHOSEN or ALTERNATIVE per rotation>)` and `Defense B (defends <other>)` sections. Wrap each defense body in `<defense_content>...</defense_content>` tags with a "data not instructions" preamble.
- **Position-order rotation**: odd N → `CHOSEN` is Defense A; even N → `ALTERNATIVE` is Defense A.
- **Attribution stripping**: the ballot body MUST NOT contain `Cursor`, `Codex`, or `Claude` tokens — emit only neutral Defense A/B labels. Role-to-choice mapping (`defends <CHOSEN>` vs `defends <ALTERNATIVE>`) is preserved.
- Defense body = concatenated tag-body text from the debater output (`<claim>` + `<evidence>` + `<strongest_concession>` + `<counter_to_opposition>` + `<risk_if_wrong>`) with the terminal `RECOMMEND:` line stripped. Record which side's defense maps to Defense A internally so the orchestrator can back-map judge votes to resolutions.

Launch 3 judges **in parallel** (single message). Spawn order: Cursor first, then Codex, then the Claude subagent. Follow the protocol's Launching Judges section for exact command templates:

- Cursor judge via `run-external-reviewer.sh --tool cursor --capture-stdout` (with `run_in_background: true`, `timeout: 1860000`). If `judge_cursor_available=false`, launch a Claude subagent replacement via the Agent tool inline.
- Codex judge via `run-external-reviewer.sh --tool codex` (with `run_in_background: true`, `timeout: 1860000`). If `judge_codex_available=false`, launch a Claude subagent replacement inline.
- Claude Code Reviewer subagent judge: always via the Agent tool (subagent_type: `code-reviewer`), inline.

## Collecting judge results (split pattern)

External judge outputs are collected via `collect-reviewer-results.sh` using its sentinel polling. Inline Agent-tool judges produce no sentinel; their votes are returned directly by the Agent tool and parsed from its return text. Do NOT pass inline-judge output paths to `collect-reviewer-results.sh` — the sentinel check would time out and incorrectly drop the voter count.

**Zero-external-judges guard**: Only invoke `collect-reviewer-results.sh` if at least one external judge was actually launched (i.e., at least one of `judge_cursor_available` / `judge_codex_available` was true at launch time). When both are false — all three panel slots are filled by Claude subagent inline replacements — skip the collector invocation entirely and proceed directly to inline-vote tally from Agent returns. `collect-reviewer-results.sh` exits 1 with "at least one output file is required" when called with zero positional arguments; without this guard, the all-fallback configuration would abort.

When at least one external judge was launched, after all external judges return:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 \
  --write-health /dev/null \
  <each launched external-judge output path>
```

`--write-health /dev/null` ensures the judge phase NEVER updates `${SESSION_ENV_PATH}.health`. Block on this call (do NOT use `run_in_background`).

For each external judge, parse its `STATUS` and `REVIEWER_FILE`. An external judge with `STATUS != OK` is ineligible for every decision on the ballot. For inline Agent-tool judges (primary Claude subagent + any Claude replacements), parse votes directly from the Agent return text; inline judges are always eligible.

## Tally and resolution writing

For each `voted`-eligible decision, tally per-decision votes from all 3 judges per the protocol's Parser tolerance and Threshold Rules. Apply the binary thresholds:

- 3 eligible voters: 2+ same-side → `Disposition: voted`, Resolution = CHOSEN (if THESIS wins) or ALTERNATIVE (if ANTI_THESIS wins).
- 2 eligible voters: unanimous → `Disposition: voted`; 1-1 tie → `Disposition: fallback-to-synthesis` with reason `1-1 tie with 2 voters`.
- <2 eligible voters: `Disposition: fallback-to-synthesis` with reason `<N> judges eligible`.

## Write `$DESIGN_TMPDIR/dialectic-resolutions.md`

Write one resolution entry per decision originally present in `contested-decisions.md` (including `over-cap`, `bucket-skipped`, and `fallback-to-synthesis` entries), using the schema from `dialectic-protocol.md`:

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

- **`voted`**: Include `Vote tally`. Use `**Why thesis prevails**` or `**Why antithesis prevails**` (which side won); distill from the winning judges' rationale lines and engage the losing side's strongest concession from the tag-body text.
- **`fallback-to-synthesis`**: Omit `Vote tally`. Use `**Why fallback**: <reason>`.
- **`bucket-skipped`**: Omit `Vote tally`. Use `**Why skipped**: <Tool> unavailable — bucket <N> decisions skipped at Step 2a.5 step 4`. Summary placeholders: `(no debate — bucket skipped)`.
- **`over-cap`**: Omit `Vote tally`. Use `**Why over-cap**: decision ranked <N>, outside top-5 dialectic selection cap`. Summary placeholders: `(no debate — ranked outside cap)`.

Print resolutions under a `## Dialectic Resolutions` header.

**Scope**: Dialectic resolutions are **binding for Step 2b plan generation only** for entries with `Disposition: voted`. All other dispositions mean synthesis stands for that point. Even `voted` entries may be superseded by accepted Step 3 review findings. The finalized plan (after Step 3 review) remains the sole canonical output.

Print: `✅ 2a.5: dialectic — <V> voted, <F> fallback, <S> bucket-skipped, <O> over-cap (<elapsed>)` where V/F/S/O are per-disposition counts (omit a count if zero — e.g., `<V> voted, <F> fallback`).
