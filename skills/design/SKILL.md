---
name: design
description: "Use when designing any non-trivial feature, refactor, or architectural change — for design, architecture planning, scope definition, approach validation. 5 parallel sketch agents propose approaches; 3-reviewer voting panel validates via dialectic."
argument-hint: "[--auto] [--debug] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch
---

# Design Skill

Design an implementation plan for a feature and review it with a unified 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). The sketch phase (Step 2a) runs 5 agents in parallel: 1 Claude General sketch (orchestrator) + 2 Cursor slots + 2 Codex slots carrying the four non-general personalities.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

| Flag | Default | Purpose | Load-bearing detail |
|------|---------|---------|---------------------|
| `--auto` | `false` | Skip interactive question checkpoints (1c, 1d, 3.5) | No-op when caller sets `--quick` and `/design` is skipped |
| `--debug` | `false` | Verbose output (see Verbosity Control) | — |
| `--session-env <path>` | empty | Forward discovered session values to `session-setup.sh` | Empty = standalone invocation, full discovery |
| `--step-prefix <prefix>` | empty | Nested-numbering prefix from `/implement` | `::` delimiter splits numeric prefix from breadcrumb path; `"1."` (bare numeric) is backward-compat |
| `--branch-info <values>` | — | Skip redundant branch-state check when called from `/implement` | 4 keys required: `IS_MAIN`/`IS_USER_BRANCH`/`USER_PREFIX`/`CURRENT_BRANCH`; fallback on validation failure to `create-branch.sh --check` |

**MANDATORY — READ ENTIRE FILE before parsing argument flags**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/flags.md` completely. This reference is the single normative source for flag semantics — validation rules, fallback behaviors, `::` delimiter encoding spec, 4-key `--branch-info` requirement, and backward-compat notes. The table above is a non-normative index.

The feature to design is described by the remainder of `$ARGUMENTS` after flags are stripped.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is and which parent steps they are inside. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 1: branch**` (standalone) or `> **🔶 1.1: design plan | branch**` (nested from `/implement`)
- Print a **completion line** only when it carries informational payload. Only the final step (Step 5) prints an unconditional completion announcement.
- When `STEP_NUM_PREFIX` is non-empty, prepend it to step numbers: `{STEP_NUM_PREFIX}{local_step}`. When `STEP_PATH_PREFIX` is non-empty, prepend it to breadcrumb paths: `{STEP_PATH_PREFIX} | {step_short_name}`. **This rule overrides the literal step numbers and names in `Print:` directives and examples throughout this file.** Examples shown below assume standalone mode; when nested, prepend the parent context.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | branch |
| 1c | questions |
| 1d | discussion r1 |
| 2a | sketches |
| 2a.5 | dialectic |
| 2b | full plan |
| 3 | plan review |
| 3.5 | discussion r2 |
| 3b | arch diagram |
| 4 | rejected findings |
| 5 | cleanup |

### Verbosity Control

**When `debug_mode=false` (default):**

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), final completion line (Step 5), all warning/error lines (`**⚠ ...`), structured summaries (voting tallies, scoreboards, round summaries, findings lists, approach synthesis, dialectic resolutions, implementation plans, architecture diagrams), and the compact reviewer status table (see below).

**Compact reviewer status table**: After launching sketch agents (Step 2a) or plan reviewers (Step 3), maintain a mental tracker of each agent's status. Print a compact table after EACH status change:

```
📊 Sketches: | General: ✅ 2m31s | Cursor-Arch: ⏳ | Cursor-Edge: ✅ 3m5s | Codex-Innovation: ❌ 8m3s | Codex-Pragmatic: ⏳ |

or for Step 3 plan review (3-reviewer panel):

📊 Reviewers: | Code: ✅ 2m31s | Codex: ⏳ | Cursor: ✅ 4m12s |
```

Icons: ✅ done (with elapsed time since launch), ⏳ pending/in-progress, ❌ failed/timeout (with elapsed time since launch), ⊘ skipped (unavailable). This replaces individual per-agent completion messages in non-debug mode. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for elapsed time and step start formatting rules.

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls, per-reviewer individual completion messages.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text and BOTH status table and per-agent details.

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Design Mindset

Before invoking `/design`, the orchestrator should internalize these questions. They bias every subsequent choice — sketch synthesis, plan drafting, review-finding acceptance — and are the thinking pattern this skill transfers along with its mechanical procedures.

- **What is the smallest change that achieves the goal?** Resist adding abstractions, flags, or layers the feature description did not ask for. Every additional moving part is a new failure mode.
- **Where is anchoring risk highest?** The first plausible approach locks architectural direction unless the sketch phase forces alternatives. Do NOT skip Step 2a (anti-pattern rule #1).
- **What hidden constraints must this preserve?** Canonical sources, CI invariants, downstream parsers, contract tokens, byte-preserved reference files. Identify them before edits, not during plan review.
- **Which tradeoffs should surface to the user versus be quietly chosen?** Scope and hard-constraint decisions surface via Round 1 discussion; architectural preferences belong to the sketch phase — not to the user.
- **Which anti-patterns in the NEVER list below apply to this specific feature?** Re-read the Anti-patterns section for every non-trivial feature; muscle memory for the six rules is the expert delta this skill aims to transfer.

## Anti-patterns

Consolidated NEVER rules collected from the procedural steps below. Each rule states the WHY so edits can respect the original constraint. Inline step-local mentions remain where they carry load-bearing context.

1. **NEVER skip Step 2a** (the 5-agent sketch phase). **Why:** anchoring bias locks architectural direction before alternatives are considered. **How to apply:** always run all 5 sketch slots, even when the feature seems trivial; Claude fallbacks preserve the 5-agent count when externals are unavailable.

2. **NEVER substitute a Claude subagent into a dialectic debate bucket.** **Why:** the debate path is externals-only (Cursor/Codex) because model-specific writing style could encode tool identity into adversarial arguments; the judge path uses the repo-wide replacement-first pattern because judges merely adjudicate pre-authored defenses. See GitHub issue #98. **How to apply:** Step 2a.5 skips debate buckets whose assigned tool is unavailable — do NOT reassign to Claude. Judge-panel slots (after debate) DO use Claude replacements per `dialectic-protocol.md`.

3. **NEVER mutate orchestrator-wide `codex_available` / `cursor_available` inside Step 2a.5.** **Why:** Step 3 plan-review panel integrity depends on the Option B snapshot pattern — a debate-phase timeout must not lock a tool out of later plan review. **How to apply:** use the `dialectic_*_available` shadow flags inside Step 2a.5 and the `judge_*_available` shadow flags inside the judge re-probe; never touch the top-level flags.

4. **NEVER pass `--caller-env` or `--write-health` to `session-setup.sh` when `SESSION_ENV_PATH` is empty.** **Why:** standalone `/design` invocations have no parent `/implement` to consume the session-env or health artifacts. **How to apply:** branch on `SESSION_ENV_PATH` non-empty in Step 0; omit both flags when standalone.

5. **NEVER call `collect-reviewer-results.sh` with zero positional arguments.** **Why:** it exits 1 with "at least one output file is required". This is the zero-externals failure mode when every external slot has fallen back to a Claude subagent. **How to apply:** guard each collector call with an explicit check that at least one external slot was launched; the dialectic zero-externals guardrail (Step 2a.5 step 5) and the Step 3 collector both require this.

6. **NEVER conflate the two timeout families.** **Why:** sketch-phase timeouts (sketches are shorter) differ from plan-review + dialectic timeouts (longer, deeper reasoning). **How to apply:** use `timeout: 1260000` (Bash tool) / `--timeout 1260` (collector) / `--timeout 1200` (reviewer script) for sketch-phase launches and sketch collection; use `timeout: 1860000` / `--timeout 1860` / `--timeout 1800` for plan-review launches, dialectic debaters, and dialectic judges.

## Step 0 — Session Setup

Run the shared session setup script. This handles preflight, temp directory creation, reviewer health probe, and health status file in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-design --skip-branch-check --skip-slack-check --skip-repo-check --check-reviewers [--caller-env "$SESSION_ENV_PATH"] [--skip-codex-probe] [--skip-cursor-probe] [--write-health "${SESSION_ENV_PATH}.health"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` and `--write-health "${SESSION_ENV_PATH}.health"` if `SESSION_ENV_PATH` is non-empty. If `SESSION_ENV_PATH` provides `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, the script auto-sets the corresponding `--skip-codex-probe` / `--skip-cursor-probe` flag — you do not need to pass these explicitly when using `--caller-env`.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `DESIGN_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

Set mental flags `codex_available` and `cursor_available` based on the output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed). Using Claude replacement.**`
- Else: `codex_available=true`
- Same logic for Cursor.

The `--write-health` flag writes the health status file for cross-skill propagation. It will be updated by `collect-reviewer-results.sh --write-health` during runtime if any reviewer times out.

## Step 1 — Create Branch

### 1a — Check current branch state

**If `branch_info_supplied=true`** (via `--branch-info`): Use the values parsed from the flag (`CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, `USER_PREFIX`). Skip the `create-branch.sh --check` call.

**Otherwise** (standalone invocation or validation failed): Run the `create-branch.sh` script in check mode:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/create-branch.sh --check
```

Parse the output for `CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, and `USER_PREFIX`.

### 1b — Decide action

**Decision logic** (using the script output):
- If `IS_MAIN=true`: Derive a short kebab-case branch name from the feature description (e.g., "add user auth" → `<USER_PREFIX>/add-user-auth`). Keep it under 50 characters. Then create it:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/create-branch.sh --branch <USER_PREFIX>/<branch-name>
  ```

- If `IS_USER_BRANCH=true`: Verify the branch name (`CURRENT_BRANCH`) aligns with the requested feature. If it appears unrelated (different feature name, unrelated commits), print a warning: `**⚠ Current branch '<branch-name>' may not match the requested feature. Creating a new branch from main.**` and create a new branch as above. Otherwise, skip branch creation. Print: `> **🔶 1: branch — using existing: <branch-name>**`

- Otherwise (non-main, non-user branch): Print a warning: `**⚠ Currently on branch '<branch-name>' which doesn't match the expected '<USER_PREFIX>/*' pattern. Creating a new branch from main.**` Then derive a name and create as above.

## Step 1c — Clarifying Questions

Print: `> **🔶 1c: questions**`

**If `auto_mode=true`**: Print `⏩ 1c: questions — skipped (auto mode) (<elapsed>)` and proceed to Step 1d.

**If `auto_mode=false`**: **MANDATORY — READ ENTIRE FILE**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion-rounds.md` completely. Execute the Step 1c body in that file. **Do NOT load `discussion-rounds.md` when `auto_mode=true`** — the short-circuit above exits first.

## Step 1d — Design Discussion (Round 1)

Print: `> **🔶 1d: discussion r1**`

**If `auto_mode=true`**: Print `⏩ 1d: discussion r1 — skipped (auto mode) (<elapsed>)` and proceed to Step 2a.

**If `auto_mode=false`**: Execute the Step 1d body in `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion-rounds.md`. If already loaded at Step 1c, no need to re-load; otherwise **MANDATORY — READ ENTIRE FILE**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion-rounds.md` completely.

## Step 2a — Collaborative Approach Sketches

**IMPORTANT: The collaborative sketch phase MUST ALWAYS run with all 5 sketch agents (using Claude replacements when external tools are unavailable). Never skip or abbreviate this phase regardless of how simple, obvious, or documentation-only the feature appears. The sketch synthesis is required architectural input for the implementation plan — skipping it causes anchoring bias where a single perspective locks in the direction before alternatives are considered.**

A diverge-then-converge phase where 5 agents independently produce short architectural sketches before writing the full plan. This surfaces different perspectives early — when they can still influence architectural direction — rather than waiting for review when the plan is already anchored.

The 5 sketch agents are **1 Claude subagent + 2 Cursor + 2 Codex**, with per-slot Claude fallback when an external tool is unavailable:

1. **Claude (General)** — the orchestrating agent's own inline sketch, covering key decisions, files, and tradeoffs.
2. **Cursor slot 1 — Architecture/Standards** — or **Claude (Architecture/Standards)** fallback: emphasizes maintainability, engineering standards, separation of concerns, and reuse of existing libraries (including open-source).
3. **Cursor slot 2 — Edge-cases/Failure-modes** — or **Claude (Edge-cases/Failure-modes)** fallback: focuses on what can go wrong, boundary conditions, error handling, and failure recovery.
4. **Codex slot 1 — Innovation/Exploration** — or **Claude (Innovation/Exploration)** fallback: proposes creative alternative approaches, questions assumptions, and suggests unconventional solutions.
5. **Codex slot 2 — Pragmatism/Safety** — or **Claude (Pragmatism/Safety)** fallback: emphasizes minimizing changes, avoiding regressions, and not breaking existing features.

When both Cursor slots fall back to Claude, they still invoke the two distinct Cursor-slot personality prompts (Architecture/Standards + Edge-cases/Failure-modes). Same for both Codex slots (Innovation/Exploration + Pragmatism/Safety).

Print `> **🔶 2a: sketches**` and proceed to 2a.2.

### 2a.2 — Launch Sketches in Parallel

Five sketch agents run in parallel: Claude General (orchestrator inline) + 2 Cursor slots (Architecture/Standards, Edge-cases/Failure-modes) + 2 Codex slots (Innovation/Exploration, Pragmatism/Safety), with per-slot Claude Agent-tool fallback when an external tool is unavailable so the 5-agent count is preserved.

**MANDATORY — READ ENTIRE FILE (load FIRST)**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/sketch-prompts.md` completely. It defines `ARCH_PROMPT`, `EDGE_PROMPT`, `INNOVATION_PROMPT`, `PRAGMATIC_PROMPT` — the four personality-prompt bodies substituted into the launch shell blocks via the `<ARCH_PROMPT>`, `<EDGE_PROMPT>`, `<INNOVATION_PROMPT>`, `<PRAGMATIC_PROMPT>` token names.

**MANDATORY — READ ENTIRE FILE (load SECOND, after sketch-prompts.md)**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/sketch-launch.md` completely. It contains the byte-preserved launch shell blocks for the four external slots (consuming the tokens resolved above), the spawn-order rule, the per-slot `run_in_background: true` / `timeout: 1260000` requirements, the per-slot Claude fallback notes, and the Claude General sketch independence rule.

Execute the launches per `sketch-launch.md` — all external and fallback launches issued before the Claude General sketch, in a single message, Cursor slots first, then Codex slots, then any Claude fallbacks, then the General sketch last.

### 2a.3 — Wait and Validate Sketches

Collect and validate external sketch outputs using the shared collection script. Pass the output paths for whichever external slots were actually launched (omit any slot where the tool was unavailable and a Claude subagent fallback is returning via Agent tool instead):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1260 \
  "$DESIGN_TMPDIR/cursor-sketch-arch-output.txt" \
  "$DESIGN_TMPDIR/cursor-sketch-edge-output.txt" \
  "$DESIGN_TMPDIR/codex-sketch-innovation-output.txt" \
  "$DESIGN_TMPDIR/codex-sketch-pragmatic-output.txt"
```

Use `timeout: 1260000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Only include output paths for slots that were actually launched as external reviewers — omit any slot whose tool was unavailable (its fallback comes back via the Agent tool).

Note: This is a separate `collect-reviewer-results.sh` call from the one in Step 3. Both are permitted because they operate on completely distinct output file sets (`*-sketch-*-output.txt` vs `*-plan-output.txt`).

Parse the structured output for each reviewer's `STATUS`, `REVIEWER_FILE`, and `HEALTHY`. For sketches, a valid output is non-empty and contains substantive architectural content (at least a paragraph). If a reviewer's `STATUS` is not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md` (set `*_available=false` for all subsequent steps).

### 2a.4 — Synthesis

Read all 5 sketches (Claude General + Cursor slot 1 Architecture/Standards + Cursor slot 2 Edge-cases/Failure-modes + Codex slot 1 Innovation/Exploration + Codex slot 2 Pragmatism/Safety — or their Claude fallbacks if an external tool was unavailable). Produce a synthesis that:

1. Identifies where the approaches **agree** (likely the majority)
2. Identifies where they **diverge** and makes a reasoned call on each contested point with justification
3. Notes which ideas from each sketch are being incorporated into the full plan
4. Highlights any **Architecture/Standards** concerns (sourced from Cursor slot 1) that should be addressed in the plan
5. Highlights any **Pragmatism/Safety** warnings (sourced from Codex slot 2) about regression risk or unnecessary complexity
6. Surfaces any **Edge-case/Failure-mode** risks (sourced from Cursor slot 2) that should be addressed in the plan's Failure modes section
7. Notes any **Innovation/Exploration** alternatives (sourced from Codex slot 1) worth preserving as options even when not chosen
8. Lists contested decisions as a structured markdown list in `$DESIGN_TMPDIR/contested-decisions.md`. Use this schema:

   ```markdown
   ### DECISION_1: <short title>
   - **Chosen**: <the synthesis choice>
   - **Alternative**: <the strongest alternative>
   - **Tension**: <why this is contested — which sketches diverged and why>
   - **Impact**: High/Medium/Low
   - **Affected files**: <comma-separated list of files/modules impacted by this decision>
   ```

   List decisions in priority order: High impact first, then by degree of sketch disagreement (more agents on different sides = higher priority), then by order of appearance in the synthesis. If no sketches diverged (all 5 agreed on all points), write exactly `NO_CONTESTED_DECISIONS` as the entire file content.

Print the synthesis under an `## Approach Synthesis` header. Write the synthesis to `$DESIGN_TMPDIR/approach-synthesis.txt` so it can be referenced by Step 2b.

### 2a.5 — Dialectic Resolution of Contested Decisions

Print: `> **🔶 2a.5: dialectic**`

Read `$DESIGN_TMPDIR/contested-decisions.md`. If the file contains only `NO_CONTESTED_DECISIONS` (ignoring leading/trailing whitespace and newlines), print `⏩ 2a.5: dialectic — no contested decisions (<elapsed>)` and proceed to Step 2b.

**Intentional divergence from the repo-wide replacement-first fallback architecture (debate phase only)**. The **debate** phase (steps 1-9 below) deliberately diverges from the "Voter Composition" rule in `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md` and from the Cursor/Codex fallback rules in the "Step 3 — Plan Review" section below: when an assigned debater tool is unavailable, the bucket is **skipped entirely** — Claude subagents are NEVER substituted into the dialectic **debate** path. Likewise, the "Runtime Timeout Fallback" procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md` flips orchestrator-wide `*_available` for all subsequent session steps; in this phase, runtime failures affect ONLY this phase's bookkeeping and never mutate the orchestrator-wide flags. Do NOT "fix" this carve-out back to global-flip + Claude-replacement behavior for debaters — see GitHub issue #98 for the rationale.

This divergence applies **only to debate execution**, not to **judge adjudication**. The post-debate judge panel (see `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`) uses the repo-wide **replacement-first** pattern: when Cursor or Codex is unavailable for judging, a Claude Code Reviewer subagent replaces that slot so the panel always remains at 3 judges. Judges merely adjudicate between pre-authored defenses; the "no Claude substitution" rule is specific to adversarial debate where model-specific writing style could encode tool identity.

Otherwise, read `$DESIGN_TMPDIR/approach-synthesis.txt` — this provides `{SYNTHESIS_TEXT}` for the prompt templates below. Then apply the following protocol:

1. **Cap = `min(5, |contested-decisions|)`** — select that many decisions from the file (they are already in priority order from Step 2a.4).

2. **Initialize dialectic-scoped shadow flags** at the top of this step:
   - `dialectic_codex_available = codex_available` (snapshot at entry)
   - `dialectic_cursor_available = cursor_available` (snapshot at entry)
   The orchestrator-wide `codex_available` / `cursor_available` flags are NEVER mutated during this step. This preserves Step 3's plan-review panel integrity by construction (Option B).

3. **Deterministic per-decision bucket assignment** (1-based indexing):
   - Decision 1, 3, 5 → **Cursor** bucket (uses `dialectic_cursor_available`).
   - Decision 2, 4 → **Codex** bucket (uses `dialectic_codex_available`).
   - Both thesis and antithesis for a single decision use the same tool (bucket homogeneity).

4. **Per-bucket pre-launch availability check**. For each selected decision, check the assigned tool's `dialectic_*_available` flag:
   - If `false`: print `**⚠ <Tool> unavailable — dialectic skipped for bucket <N> decisions (indices: <comma-list>). Step 2a.4 synthesis decisions stand.**`, skip that decision, and continue. Do NOT fall back to a Claude Agent-tool subagent. Do NOT reassign the decision to the surviving tool. Do NOT abort this step.
   - If `true`: queue both the thesis and antithesis launch for that decision.

5. **Zero-externals guardrail**. If after iterating all selected decisions, zero buckets are queued, print no further launches, do NOT call `collect-reviewer-results.sh` at all, skip the judge phase entirely. The `dialectic-resolutions.md` file IS still written — it contains only `Disposition: bucket-skipped` entries (one per selected decision) plus any `Disposition: over-cap` entries for decisions ranked outside the top-5 cap — so Step 2b and Step 3.5 parse a uniform schema regardless of dialectic outcome. On this path, follow the second `Do NOT load` variant below.

**MANDATORY — READ ENTIRE FILE before rendering debate prompts (step 6)**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/dialectic-execution.md` completely. It contains the byte-preserved execution choreography: per-decision prompt rendering, parallel debater launch, collection, the eligibility gate (Dispositions), the debate quorum gate, the dialectic-local judge-panel re-probe, ballot construction, judge launch, tally, and the `Write dialectic-resolutions.md` sub-step. The first directive inside that file is a nested MANDATORY pointing to `references/dialectic-debate.md` — the template-body file that holds the Thesis/Antithesis prompt substitution placeholders (`{FEATURE_DESCRIPTION}`, `{SYNTHESIS_TEXT}`, `{DECISION_BLOCK}`, `{CHOSEN}`, `{ALTERNATIVE}`, `{TENSION}`, `{AFFECTED_FILES}` plus the `<debater_synthesis>` / `<debater_decision>` reference-block wrappers).

**Do NOT load `dialectic-execution.md` when `contested-decisions.md` contains only `NO_CONTESTED_DECISIONS`** — the short-circuit print at the top of Step 2a.5 exits before reaching this point, so the reference file is naturally never loaded on the no-contest path.

**Do NOT load `dialectic-execution.md` when the zero-externals guardrail fired (zero buckets queued in step 5 above)** — instead, jump directly to the final sub-step of `dialectic-execution.md` conceptually (emit only `bucket-skipped` / `over-cap` entries into `dialectic-resolutions.md`) without loading the full execution procedure. The dialectic-resolutions schema for these entries is documented in the **Write `$DESIGN_TMPDIR/dialectic-resolutions.md`** section of `dialectic-execution.md`; if the orchestrator already has the schema in context from a prior run, skip the load entirely. Otherwise, a one-time load of `dialectic-execution.md` is acceptable but the debate-execution mechanics inside it MUST NOT fire (no debaters, no judges, no ballot).

Execute steps 6 through the final `✅ 2a.5: dialectic — …` print directive as documented in `${CLAUDE_PLUGIN_ROOT}/skills/design/references/dialectic-execution.md` (loaded via the MANDATORY directive above). That file is the single normative source for dialectic-execution mechanics. The final `Write $DESIGN_TMPDIR/dialectic-resolutions.md` sub-step (including the per-disposition field rules) lives inside that reference; print the `## Dialectic Resolutions` header at the end and the `✅ 2a.5: dialectic — <V> voted, <F> fallback, <S> bucket-skipped, <O> over-cap (<elapsed>)` print directive (omit a count if zero).

## Step 2b — Design the Implementation Plan

Before writing any code, create a concrete implementation plan. Research the codebase (read relevant files, grep for patterns, understand existing architecture). See CLAUDE.md for project-specific development references and conventions.

Read `$DESIGN_TMPDIR/approach-synthesis.txt` from Step 2a and incorporate the synthesis into the plan. The synthesis should inform architectural decisions, file selection, and tradeoff resolutions.

Also read `$DESIGN_TMPDIR/discussion-round1.md` if it exists and is non-empty. Incorporate the scope boundaries and hard constraints established during the design discussion into the plan — these define what is in-scope, what must not break, and what the user explicitly does not want.

Also read `$DESIGN_TMPDIR/dialectic-resolutions.md` if it exists and is non-empty. Parse the structured fields defined in `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md` (Resolution, Disposition, Vote tally, Thesis summary, Antithesis summary, Why field). **Branch on `Disposition`**:

- **`Disposition: voted`**: the plan **must** follow the `Resolution` direction and explicitly note how the antithesis concern (from `Antithesis summary`) was addressed, referencing the `Why thesis prevails` / `Why antithesis prevails` justification. These resolutions are binding for Step 2b — do not override them.
- **`Disposition: fallback-to-synthesis`**: the synthesis decision stands (Resolution is the synthesis choice = `CHOSEN`). Note the `Why fallback` reason briefly (judge panel tie, quorum failure, etc.) but do NOT fabricate antithesis-engagement prose — no antithesis was heard with sufficient rigor to engage.
- **`Disposition: bucket-skipped`**: the synthesis decision stands. Note that debate was skipped (`Why skipped` reason) but do NOT fabricate antithesis-engagement prose — no debate occurred.
- **`Disposition: over-cap`**: the synthesis decision stands. Note that this decision was outside the dialectic cap (`Why over-cap` reason) but do NOT fabricate antithesis-engagement prose.

(Note: Step 3 plan review may subsequently revise the plan based on accepted review findings, which supersede dialectic resolutions.)

Produce a plan that includes:

- **Files to modify/create**: List each file with a brief description of what changes.
- **Approach**: Describe the implementation strategy, key decisions, and any trade-offs.
- **Edge cases**: Note important input/boundary conditions and how they'll be handled.
- **Failure modes** (for non-trivial changes): The 3 most likely architectural/systemic failure paths, earliest warning signals, and simplest mitigations. May be omitted for purely cosmetic or documentation-only changes.
- **Testing strategy**: What tests will be added or modified.

Print the plan to the user under a `## Implementation Plan` header so reviewers can see it.

## Step 3 — Plan Review

**IMPORTANT: Plan review MUST ALWAYS run with all 3 reviewers (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Never skip or abbreviate this step regardless of how straightforward the plan appears — even when all sketch agents agreed, the plan is short, or the change seems trivial. Reviewers validate against the actual codebase state, catching issues that sketch-phase reasoning alone cannot detect.**

**MANDATORY — READ ENTIRE FILE before launching reviewers**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/plan-review.md` completely. The reference is the normative source for the reviewer-prompt content and post-launch procedures: the byte-preserved Competition notice blockquote (appended to EACH reviewer prompt), the Claude Code Reviewer subagent archetype (`{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` with XML-wrap literal-delimiter instruction / `{OUTPUT_INSTRUCTION}`), the voter-1 / voter-2 / voter-3 detailed quoted prompts, the ballot file handling paragraph, the Collecting External Reviewer Results 5-step procedure, the Voting Panel launch-order + threshold + Competition scoring rules, the Finalize Plan Review 4-step procedure plus OOS artifact write rule, the Track Rejected Plan Review Findings rule, and the accepted `FINDING_N` template, accepted `oos-accepted-design.md` format, and rejected-findings template. Step 3 control flow that remains inline in SKILL.md below (not in plan-review.md): the 3-reviewer "MUST ALWAYS run" IMPORTANT banner, the overall parallel-launch + spawn-order rule, `### External Reviewer Setup` (writing `$DESIGN_TMPDIR/plan.txt` + the focus-area enum summary line), and the two external reviewer launch Bash blocks (Cursor + Codex) which must stay inline because CI greps SKILL.md for the focus-area enum they carry. The Competition notice must be in context before any reviewer launch below — reading this file now guarantees that.

Launch **all 3 reviewers in parallel** (in a single message). When an external tool is unavailable, launch a Claude subagent fallback so the total reviewer count always remains 3. **Spawn order matters for parallelism** — launch the slowest reviewer first: Cursor, then Codex, then the Claude subagent. Each reviewer receives the plan text and the feature description. Each must **only report findings** — never edit files.

### External Reviewer Setup (if `codex_available` or `cursor_available`)

Before launching external reviewers, write the implementation plan to `$DESIGN_TMPDIR/plan.txt` so Codex and Cursor can read it.

Each reviewer walks five focus areas: code-quality / risk-integration / correctness / architecture / security.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the codebase itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-plan-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Walk five focus areas: (1) Code Quality: logical flaws, code reuse, test coverage, backward compat, style consistency. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level.")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor fallback** (if `cursor_available` is false): Launch a Claude Code Reviewer subagent via the Agent tool (subagent_type: `code-reviewer`) with the same plan-review context. This fallback ensures the total reviewer count remains 3 regardless of external tool availability.

### Codex Reviewer (if `codex_available`)

Run Codex **second** in the parallel message (after Cursor). Codex has full repo access and will examine the codebase itself.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-plan-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$DESIGN_TMPDIR/codex-plan-output.txt" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Walk five focus areas: (1) Code Quality: logical flaws, code reuse, test coverage, backward compat, style consistency. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex fallback** (if `codex_available` is false): Launch a Claude Code Reviewer subagent via the Agent tool (subagent_type: `code-reviewer`) with the same plan-review context. This fallback ensures the total reviewer count remains 3 regardless of external tool availability.

### Claude Code Reviewer Subagent (1 reviewer)

Launch the Claude subagent **last** in the same message (it finishes fastest). Use the Code Reviewer archetype from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md`, filled per the archetype block in `plan-review.md` (`{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` / `{OUTPUT_INSTRUCTION}`), with the Competition notice from `plan-review.md` appended. Invoke via Agent tool with `subagent_type: code-reviewer`.

### Collecting, Voting, Finalize, Track Rejected

Follow `plan-review.md` (loaded via the MANDATORY at the top of Step 3) for: Collecting External Reviewer Results (process Claude findings immediately, then `collect-reviewer-results.sh` for externals, dedup in-scope and OOS separately, merge Claude attribution), Voting Panel launch-order + threshold + Competition scoring, Finalize Plan Review (accepted findings revise plan, write `$DESIGN_TMPDIR/accepted-plan-findings.md`, write accepted OOS to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-design.md` when `SESSION_ENV_PATH` is non-empty, print non-accepted OOS under `## Out-of-Scope Observations`), and Track Rejected Plan Review Findings (append to `$DESIGN_TMPDIR/rejected-findings.md`, in-scope only).

If **all reviewers** report no in-scope issues and no out-of-scope observations, skip voting and proceed to Step 3.5 if `auto_mode=false`, or Step 3b if `auto_mode=true`.

## Step 3.5 — Design Discussion (Round 2)

Print: `> **🔶 3.5: discussion r2**`

**If `auto_mode=true`**: Print `⏩ 3.5: discussion r2 — skipped (auto mode) (<elapsed>)` and proceed to Step 3b. **Do NOT load `discussion-rounds.md` when `auto_mode=true`.**

**If `auto_mode=false`**: Execute the Step 3.5 body in `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion-rounds.md`. If already loaded at Step 1c, no need to re-load; otherwise **MANDATORY — READ ENTIRE FILE**: Read `${CLAUDE_PLUGIN_ROOT}/skills/design/references/discussion-rounds.md` completely. The body defines Inputs, Behavior (still-contested criteria including close 2-1 voted, fallback-to-synthesis, bucket-skipped, over-cap), Short-circuit, Output schema, Cap, and Terse-answer rules.

## Step 3b — Architecture Diagram

Print: `> **🔶 3b: arch diagram**`

**This step runs on ALL paths through Step 3** — whether voting produced revisions, rejected all findings, or was skipped entirely because all reviewers reported no issues. It always executes before Step 4.

Generate a mermaid Architecture Diagram that represents the high-level system/component structure of the feature based on the finalized implementation plan (revised or original). The diagram should focus on **modules, boundaries, and their relationships** — not runtime behavior or code flow.

Choose the most appropriate mermaid diagram type for the feature (e.g., `graph TD`, `flowchart`, `C4Context`, `classDiagram`, etc.). The diagram type is flexible — pick whatever best communicates the architecture.

Print the diagram under a `## Architecture Diagram` header with a mermaid code fence, so it is visible in conversation context for `/implement` to extract later when building the PR body:

```
## Architecture Diagram

```mermaid
<diagram content>
```
```

**If diagram generation succeeds**, print: `✅ 3b: arch diagram — generated (<elapsed>)`

**If diagram generation fails** (e.g., the feature is too abstract to diagram meaningfully), print: `**⚠ 3b: arch diagram — generation failed, proceeding without diagram (<elapsed>)**`

## Step 4 — Rejected Plan Review Findings Report

Print any rejected plan review findings:

1. Check if `$DESIGN_TMPDIR/rejected-findings.md` exists and is non-empty.
2. If it has content, print it under a `## Unimplemented Plan Review Suggestions` header, formatted clearly with the reviewer name, the suggestion, and the reason for each.
3. If the file doesn't exist or is empty, print: `✅ 4: rejected findings — all suggestions implemented (<elapsed>)`

## Step 5 — Cleanup and Final Warnings

### 5a — Update Health Status File

Health status file updates are now handled automatically by `collect-reviewer-results.sh --write-health` during reviewer collection (Steps 2a.3 and 3). No additional cleanup-time write is needed unless a reviewer was marked unhealthy outside of a `collect-reviewer-results.sh` call (e.g., via a manual timeout detection). If `SESSION_ENV_PATH` is non-empty and any reviewer was marked unhealthy during this session that was NOT already written by `collect-reviewer-results.sh`, re-write the health status file at `${SESSION_ENV_PATH}.health` with the final health state before cleanup.

### 5b — Remove Temp Directory

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$DESIGN_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier steps (Step 0b binary checks, Step 2a sketch-phase failures/timeouts, Step 3 runtime failures, or Step 3b diagram generation failure) so they are visible at the end of the workflow. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`
- `**⚠ Cursor sketch timed out / produced empty output**`
- `**⚠ Codex sketch timed out / produced empty output**`
- `**⚠ 3b: arch diagram — generation failed, proceeding without diagram (<elapsed>)**`

If `STEP_NUM_PREFIX` is empty (standalone mode): Print: `✅ 5: cleanup — design complete! (<elapsed>)`
If `STEP_NUM_PREFIX` is non-empty (orchestrated mode): skip this final print — the parent orchestrator handles overall progress.
