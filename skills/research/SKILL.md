---
name: research
description: "Use for read-only research; auto-classify to quick|standard|deep lanes (3+0/3+3/5+5); --scale= overrides; --plan adds planner; --interactive pauses; --adjudicate adds dialectic; --keep-sidecar keeps batch; --token-budget caps tokens."
argument-hint: "[--debug] [--plan] [--interactive] [--scale=quick|standard|deep] [--adjudicate] [--keep-sidecar[=PATH]] [--token-budget=N] <research question or topic>"
allowed-tools: Bash, Read, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill, Write, Edit, NotebookEdit
hooks:
  PreToolUse:
    - matcher: "Edit|Write|NotebookEdit"
      hooks:
        - type: command
          command: "${CLAUDE_PLUGIN_ROOT}/scripts/deny-edit-write.sh"
          timeout: 5
---

# Research Skill

Collaborative best-effort read-only-repo research task with a scale-aware lane shape. **Adaptive scaling is the default**: a deterministic shell classifier (`skills/research/scripts/classify-research-scale.sh`) inspects `RESEARCH_QUESTION` at Step 0.5 and picks `quick|standard|deep` automatically; the operator may override via `--scale=quick|standard|deep` (e.g., for CI/eval determinism). On any classifier failure, `RESEARCH_SCALE` falls back to `standard` with a visible warning. `quick` runs **K=3 homogeneous Claude Agent-tool lanes with vote-merge synthesis** (issue #520; each carrying `RESEARCH_PROMPT_BASELINE` — same prompt, same model; voting absorbs independent stochastic errors but NOT correlated systemic biases) and skips Step 2 (the validation panel) entirely, while the final report still renders a `**Validation phase**: 0 reviewers (...)` placeholder line so the report shape is uniform across scales (K-lane voting confidence — fastest, lowest assurance; partial failure with 1 surviving lane falls back to the existing single-lane confidence disclaimer; total failure with 0 lanes hard-fails the research phase). `standard` runs 3 research agents (Cursor + Codex + Claude inline) **angle-differentiated per lane** (Cursor → architecture, Codex → edge cases by default or external comparisons when `external_evidence_mode=true`, Claude inline → security) and a 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). `deep` runs 5 research lanes (Claude inline running baseline `RESEARCH_PROMPT_BASELINE`, plus 2 Cursor and 2 Codex slots carrying four diversified angle prompts — architecture / edge cases / external comparisons / security) and a 5-reviewer validation panel (the standard 3 plus 2 extra Claude Code Reviewer subagents with `Code-Sec` / `Code-Arch` lane-local emphasis on the unified Code Reviewer archetype — NOT new agent slugs). Claude Code Reviewer subagent fallbacks preserve the configured lane count when Cursor or Codex is unavailable in standard or deep mode. Produces a structured research report; tracked repo files are not modified by Claude's `Edit | Write | NotebookEdit` tool surface (mechanically enforced by the skill-scoped PreToolUse hook permitting only canonical `/tmp`), while Bash and the external Cursor/Codex reviewers run with full filesystem access and are prompt-enforced only — see the Read-only-repo contract below. May invoke `/issue` via the Skill tool to file research-result issues.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/issue`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the research question. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, save the remainder as `RESEARCH_QUESTION`. Two distinct flag classes:

- **Boolean flags**: default to `false`. Only set to `true` when the `--flag` token is explicitly present in the arguments.
- **Value flags** (separate class — boolean defaults rule does NOT apply): each value flag has its own non-`false` default documented per flag below; only an explicit `--flag=value` token overrides it; malformed forms (unknown value, missing `=`, missing value) abort with an explicit error.

Flags are independent — the presence of one flag must not influence the default value of any other flag. `--debug`, `--scale`, `--adjudicate`, `--keep-sidecar`, `--token-budget`, and `--interactive` are independent and may appear in any order at the start of `$ARGUMENTS`.

- `--debug` (boolean): Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`.
- `--plan` (boolean): Set a mental flag `RESEARCH_PLAN=true`. Enables an optional planner pre-pass before the lane fan-out: a single Claude Agent subagent decomposes `RESEARCH_QUESTION` into 2–4 focused subquestions, each lane researches its assigned subquestion(s), and synthesis is organized by subquestion. Default: `RESEARCH_PLAN=false` (byte-equivalent to pre-#420 behavior). See "Planner pre-pass — scale interaction" below for the `--scale` cross-effect; the planner is bounded (2–4 subquestions, no recursion) and falls back cleanly to single-question mode on any planner failure.
- `--interactive` (boolean): Set a mental flag `RESEARCH_PLAN_INTERACTIVE=true`. Requires `--plan`; pauses after the planner pre-pass (Step 1.1) so the operator can review the 2–4 proposed subquestions before fan-out. Operator types Enter (proceed), `edit` (revise via `$EDITOR` or stdin fallback), or `abort` (exit cleanly). Hard-fails before any planner work when stdin is not a TTY. Deep mode confirms only the subquestion list — the per-lane subq×angle pairing stays mechanical (Step 1.2 unchanged). Default: `RESEARCH_PLAN_INTERACTIVE=false` (byte-equivalent to pre-#522 behavior). See "Planner pre-pass — scale interaction" below for the resolution rule (interaction with `--plan` and `--scale`).
- `--scale=quick|standard|deep` (value, manual override): When the flag is present with a valid value, set a mental flag `RESEARCH_SCALE` to the explicitly-provided value AND set `SCALE_SOURCE=override`. The classifier at Step 0.5 is skipped entirely on this path. When the flag is **omitted**, leave `RESEARCH_SCALE` empty for resolution at Step 0.5 (the adaptive classifier's output becomes the resolved value with `SCALE_SOURCE=auto`, or `standard` with `SCALE_SOURCE=fallback` on classifier failure). Default (omitted): `RESEARCH_SCALE=` (empty — signals classify). Selects the lane shape (1 / 3+3 / 5+5) for the research and validation phases — see "Scale matrix" below. Reject malformed forms with explicit error and abort: `--scale=foo` (unknown value) → print `**⚠ /research: --scale must be one of quick|standard|deep (got: foo). Aborting.**` and exit; `--scale` without `=value` → print `**⚠ /research: --scale requires a value (quick|standard|deep). Aborting.**` and exit; `--scale=` (empty value) → same error as missing value (preserved deliberately — explicit empty-value form is operator error, never a signal to classify; only **fully omitting** `--scale` triggers classification).
- `--adjudicate` (boolean): Set a mental flag `RESEARCH_ADJUDICATE=true`. When set, runs a 3-judge dialectic adjudication after Step 2's Finalize Validation over every reviewer finding the orchestrator rejected during validation merge/dedup — see Step 2.5 below. THESIS = "rejection stands"; ANTI_THESIS = "reinstate the reviewer's finding"; majority binds. Default: `RESEARCH_ADJUDICATE=false` (Step 2.5 short-circuits with `⏩` and behavior is unchanged from prior versions). The `(finding, rejection_rationale)` capture in Step 2 runs unconditionally (regardless of this flag), but writes only to tmpdir scratch — when the flag is off, no extra LLM work, no external-tool launches, and no additional user-visible output is produced. Composes cleanly with `--scale=quick` (which skips Step 2 entirely): when both are set, Step 2.5 short-circuits with `⏩ no rejections to adjudicate (--scale=quick skipped Step 2)` since `rejected-findings.md` is never written.
- `--keep-sidecar` AND `--keep-sidecar=<PATH>` (boolean + value form, NO positional value): Set a mental flag `KEEP_SIDECAR=true`. Set a second mental flag `KEEP_SIDECAR_PATH` per the form variant: bare `--keep-sidecar` → `KEEP_SIDECAR_PATH=` (empty); `--keep-sidecar=<PATH>` → `KEEP_SIDECAR_PATH=<PATH>` (the literal path text after `=`). Step 4 reads `KEEP_SIDECAR_PATH` and falls back to `./research-findings-batch.md` only when it is empty (#510 review FINDING_6 — without an explicit `KEEP_SIDECAR_PATH` binding, the explicit-path form would silently fall back to the default). Step 4 cleanup preserves a `/issue`-batch markdown sidecar of the findings (one `### <title>` block per finding, parseable by `skills/issue/scripts/parse-input.sh`) past the tmpdir cleanup. Default: `KEEP_SIDECAR=false`; the sidecar is generated under `$RESEARCH_TMPDIR` at Step 3 and wiped at Step 4. **Form variants**: bare `--keep-sidecar` preserves to `./research-findings-batch.md`; `--keep-sidecar=<PATH>` preserves to `<PATH>` (must be writable; must NOT resolve under `$RESEARCH_TMPDIR`). Reject malformed forms with explicit error and abort: `--keep-sidecar=` (empty value) → print `**⚠ /research: --keep-sidecar=<path> requires a non-empty value. Aborting.**` and exit; `--keep-sidecar <some-path>` (positional value, NO `=`) → the parser stops at the first non-flag token per the existing flag-grammar contract, so `<some-path>` becomes the start of `RESEARCH_QUESTION` — operators wanting an explicit path MUST use `--keep-sidecar=<PATH>`. **Read-only-repo contract**: this is an opt-in workspace write via Bash `cp` (the prompt-only constrained tier — see "Read-only-repo contract" below); the operator opts in by using the flag. Operators should review the sidecar (and apply redaction if needed) before filing — the sidecar may include security-relevant findings from `/research --scale=deep`'s `Codex-Sec` lane. See `${CLAUDE_PLUGIN_ROOT}/SECURITY.md` § [External reviewer write surface in /research and /loop-review](../../SECURITY.md#external-reviewer-write-surface-in-research-and-loop-review) and `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/render-findings-batch.md` for the helper contract and known limitations.
- `--token-budget=<positive integer>` (value): Set a mental flag `RESEARCH_TOKEN_BUDGET` to the explicit numeric value. Default: `RESEARCH_TOKEN_BUDGET=` (empty — no budget enforcement). When set, between-phase budget gates run after Step 1, Step 2.5, and Step 2.8 — see "Token telemetry and budget enforcement" below. The budget governs **measurable Claude subagent tokens only** (lanes whose `Agent`-tool return carries `<usage>total_tokens: N</usage>`); Claude inline (orchestrator) and external lanes (Cursor/Codex) are unmeasurable and excluded from the cap. Reject malformed forms with explicit error and abort: `--token-budget=foo` (non-integer) → print `**⚠ /research: --token-budget must be a positive integer (got: foo). Aborting.**` and exit; `--token-budget=` (empty value) → print `**⚠ /research: --token-budget=<N> requires a value. Aborting.**` and exit; `--token-budget=0` or negative → print `**⚠ /research: --token-budget must be > 0 (got: <val>). Aborting.**` and exit. See GitHub issue #518 for the umbrella feature.

## Empty-question preflight

After flag parsing completes, validate that `RESEARCH_QUESTION` is non-empty AND not whitespace-only **before any subsequent step** (in particular before Step 0.5 classification and before any heredoc that interpolates `RESEARCH_QUESTION` into a prompt). On empty / whitespace-only `RESEARCH_QUESTION`, print `**⚠ /research: research question is required. Aborting.**` and exit. This abort runs before Step 0 setup so no tmpdir is created on the empty-question path; subsequent steps assume `RESEARCH_QUESTION` is non-empty.

## Adaptive scale classification

Adaptive scaling is the default behavior. When `--scale=` is omitted, Step 0.5 invokes `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/classify-research-scale.sh` with `RESEARCH_QUESTION` as input and resolves `RESEARCH_SCALE` automatically. The classifier is a deterministic shell heuristic — no LLM call — so it costs zero measurable tokens and is reproducible across CI and laptops. Rule set is in three stages with **asymmetric conservatism**: `quick` requires conjunction of multiple positive signals AND no `deep` trigger; `deep` fires on any single trigger; ambiguity → `standard`. Per the design dialectic on issue #513 DECISION_1, this posture deliberately biases auto-classification away from silently downgrading a broad question to a single-lane run; the `--scale=` operator override is the explicit escape hatch when the heuristic mis-classifies.

On any classifier failure (empty input, bad path, missing arg), the orchestrator falls back to `RESEARCH_SCALE=standard` with `SCALE_SOURCE=fallback` and a visible warning. The fallback bucket is `standard` (not `quick` or `deep`) because `standard` is the safest middle option — it preserves the multi-lane validation phase while not over-provisioning a deep run.

See `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` Step 0.5 (Adaptive Scale Classification) for the body and `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/classify-research-scale.md` for the classifier contract (rules, stdout schema, exit codes).

## Token telemetry and budget enforcement

Step 4 always renders a `## Token Spend` section (immediately before `cleanup-tmpdir.sh`) summarizing per-phase Claude subagent token totals. The renderer (`scripts/token-tally.sh report`) globs per-lane sidecar files written by the orchestrator after each `Agent`-tool return. Sidecar schema: `PHASE=research|validation|adjudication`, `LANE=<stable slot name>`, `TOOL=claude`, `TOTAL_TOKENS=<integer or "unknown">`. See `${CLAUDE_PLUGIN_ROOT}/scripts/token-tally.md` for the helper contract.

**Measurable lanes** (sidecar-writing): the `planner` subagent (Step 1.1.a, when `--plan`); pre-launch and runtime-timeout Cursor/Codex fallback subagents in research and validation phases (slot names — standard mode: `Cursor`, `Codex`; deep-mode research-phase angle slots: `Cursor-Arch`, `Cursor-Edge`, `Codex-Ext`, `Codex-Sec`); the always-on Claude `Code` subagent in validation; the deep-mode `Code-Sec` and `Code-Arch` subagents in validation; the always-on Claude judge subagent and any judge replacements in adjudication (slot names reuse `Code`, `Cursor`, `Codex` from validation); the **synthesis subagent** at Step 1.5 (Standard `RESEARCH_PLAN=false`, Standard `RESEARCH_PLAN=true`, Deep `RESEARCH_PLAN=false`, Deep `RESEARCH_PLAN=true`); the **revision subagent** at Step 2 Finalize Validation (when accepted findings exist); and the **critique-loop subagents** at Step 2.8 (`Critique-1`, `Critique-2`, `Revision-Critique-1`, `Revision-Critique-2` — exactly two of each because the loop cap is `RESEARCH_CRITIQUE_MAX=2`; canonical slot-name list lives at `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` 2.8.5; recorded under the existing `validation` phase enum, no new `--phase` value). All these subagents emit `<usage>` blocks like other Agent-tool returns; the orchestrator parses `total_tokens` and writes per-lane sidecars via `token-tally.sh write` after each Agent return — slot names: `Synthesis` (synthesis subagent at Step 1.5; same slot name across all four non-quick branches since the prompt content is the only differentiator), `Revision` (revision subagent at Step 2 Finalize Validation), and the four `Critique-N` / `Revision-Critique-N` slots above (Step 2.8). Inline-fallback synthesis (when the structural validator fails) is unmeasurable — same posture as Claude inline.

**Unmeasurable lanes** (no sidecar): Claude inline (the orchestrator's own activity — no self-introspection); external Cursor/Codex lanes that successfully ran (their runners do not expose token counts); the **classifier** at Step 0.5, which is a deterministic shell script (`classify-research-scale.sh`) — no Agent-tool subagent, no `<usage>` block, no sidecar — keeps `--token-budget` honest by construction (the classifier costs zero measurable tokens).

**Budget enforcement** runs **between phases only**: after Step 1, after Step 2.5, after Step 2.8. On overage, the run aborts before the next phase starts, sets `BUDGET_ABORTED=true`, skips Step 3 entirely (no `## Research Report` rendered), and proceeds to Step 4 to render the partial token report and clean up. The completion line carries the `(aborted: budget exceeded)` suffix. `TOTAL_TOKENS=unknown` sidecars contribute zero to the budget sum (a parser-broken `<usage>` block does not silently fail open — the unknown count is surfaced explicitly in the start-of-run notice and the budget-overage message).

### Cost column (optional)

When the env var `LARCH_TOKEN_RATE_PER_M` is set to a positive number (USD per million tokens), the Step 4 token report includes a `$` cost column. When unset (default), the cost column is omitted entirely. Single combined rate v1: the Anthropic Agent-tool API currently exposes only `total_tokens` (no input/output split), so a single rate suffices. See `${CLAUDE_PLUGIN_ROOT}/docs/configuration-and-permissions.md` for the env-var entry.

## Scale matrix

| `RESEARCH_SCALE` | Step 1 (research) lanes | Step 2 (validation) lanes |
|---|---|---|
| `quick` | 3 (K=3 homogeneous Claude Agent-tool lanes — K-lane voting confidence; same prompt, same model — issue #520) | 0 (Step 2 skipped at SKILL.md gate) |
| `standard` (default) | 3 (Cursor → ARCH + Codex → EDGE/EXT + Claude inline → SEC, angle-differentiated) | 3 (Code + Cursor + Codex) |
| `deep` | 5 (Claude inline + Cursor-Arch + Cursor-Edge + Codex-Ext + Codex-Sec, with named angle prompts) | 5 (Code + Code-Sec + Code-Arch + Cursor + Codex) |

Standard mode keeps the same 3+3 lane count and launch order it has always had; the prompt content carried by each lane is angle-differentiated (Cursor → `RESEARCH_PROMPT_ARCH`; Codex → `RESEARCH_PROMPT_EDGE` by default or `RESEARCH_PROMPT_EXT` when `external_evidence_mode=true`; Claude inline → `RESEARCH_PROMPT_SEC`). Lane-status rendering is unchanged.

## Planner pre-pass — scale interaction

`--plan` is supported with `RESEARCH_SCALE=standard` (the 3-lane shape) and `RESEARCH_SCALE=deep` (the 5-lane shape with named angle prompts). With `RESEARCH_SCALE=quick` (single lane, no fan-out), downgrade `--plan` to `false` with a visible warning at the start of Step 1 — do NOT silently ignore the flag, and do NOT reject the run. **Resolution rule applied AFTER Step 0.5** (so `RESEARCH_SCALE` and `SCALE_SOURCE` are both already resolved by the classifier or by the operator override) and BEFORE Step 1 begins. The warning text branches on `SCALE_SOURCE` so the operator never sees a warning citing a flag they did not type:

- `RESEARCH_PLAN=true` AND `RESEARCH_SCALE=quick` AND `SCALE_SOURCE=override`: print `**⚠ /research: --plan is not applicable to --scale=quick (K homogeneous Claude lanes, no per-angle differentiation → no decomposition benefit). Disabling --plan for this run.**`, set `RESEARCH_PLAN=false`, continue.
- `RESEARCH_PLAN=true` AND `RESEARCH_SCALE=quick` AND `SCALE_SOURCE` ∈ {`auto`, `fallback`}: print `**⚠ /research: --plan is not applicable when adaptive scaling auto-routes to quick (K homogeneous Claude lanes, no per-angle differentiation → no decomposition benefit). Disabling --plan for this run.**`, set `RESEARCH_PLAN=false`, continue.
- `RESEARCH_PLAN=true` AND `RESEARCH_SCALE=standard`: full functionality — Step 1.1 (planner pre-pass) and Step 1.2 (lane assignment) execute, the 3 lanes run with per-lane subquestion suffixes appended to each lane's angle base prompt (Cursor → `RESEARCH_PROMPT_ARCH`; Codex → `RESEARCH_PROMPT_EDGE` by default or `RESEARCH_PROMPT_EXT` when `external_evidence_mode=true`; Claude inline → `RESEARCH_PROMPT_SEC`), Step 1.5 organizes the synthesis by subquestion. See `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` for the procedure. Step 1.1 invokes `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/run-research-planner.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/run-research-planner.md`); the script's offline regression harness is `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-run-research-planner.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-run-research-planner.md`), wired into `make lint`.
- `RESEARCH_PLAN=true` AND `RESEARCH_SCALE=deep`: full functionality — Step 1.1 (planner pre-pass) and Step 1.2 (lane assignment) execute, the 5 deep-mode lanes run with per-lane subquestion suffixes appended to their respective angle base prompts (`RESEARCH_PROMPT_ARCH` / `_EDGE` / `_EXT` / `_SEC` for the 4 external slots; baseline `RESEARCH_PROMPT_BASELINE` for the Claude-inline integrator lane), Step 1.5 organizes the synthesis subquestion-major with a Per-angle highlights sub-section that names the 4 angles by name and a Cross-cutting findings sub-section. See `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` for the procedure (the deep-mode assignment table uses a balanced partial matrix ring rotation; lane k ∈ {1..4} gets `s_{((k-1) mod N)+1}, s_{(k mod N)+1}`; Claude-inline lane 5 unions all subquestions).
- `RESEARCH_PLAN=false` (any scale): default path — no planner, no per-lane suffix, no per-subquestion synthesis. Byte-equivalent to pre-#420 behavior.

### Interactive review — TTY + flag-composition rules

`--interactive` only makes sense alongside an effective planner run, so the resolution rule below applies AFTER the `--scale=quick` plan-disable rule above. Walk in this order BEFORE Step 1 begins:

1. Parse all flags.
2. Apply the `--scale=quick` plan-disable rule (above) — sets `RESEARCH_PLAN=false` if `RESEARCH_SCALE=quick`.
3. Apply the `--interactive` resolution against the post-step-2 `RESEARCH_PLAN` value:
   - `RESEARCH_PLAN_INTERACTIVE=true` AND `--plan` was set originally AND `RESEARCH_PLAN=false` after step 2 (i.e., disabled by `--scale=quick`): print `**⚠ /research: --interactive ignored (--plan was disabled for --scale=quick).**`, set `RESEARCH_PLAN_INTERACTIVE=false`, continue.
   - `RESEARCH_PLAN_INTERACTIVE=true` AND `--plan` was NOT set originally: print `**⚠ /research: --interactive requires --plan. Aborting.**` and exit non-zero.
   - `RESEARCH_PLAN_INTERACTIVE=true` AND `RESEARCH_PLAN=true` AND stdin is NOT a TTY (`! [[ -t 0 ]]`): print `**⚠ /research: --interactive requires a TTY. Run from an attached terminal, or remove --interactive. Aborting.**` and exit non-zero. **This pre-planner check fires BEFORE Step 1.1 invokes the planner subagent** — a CI/automated environment that misconfigured `--interactive` pays exactly one error message, not a wasted planner LLM call.
   - `RESEARCH_PLAN_INTERACTIVE=true` AND `RESEARCH_PLAN=true` AND stdin IS a TTY: continue. Step 1.1.c (Interactive review checkpoint) executes after the planner subagent succeeds; see `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md`.
   - `RESEARCH_PLAN_INTERACTIVE=false`: no-op; default behavior.

The research question is described by `RESEARCH_QUESTION` (not raw `$ARGUMENTS`). Use `RESEARCH_QUESTION` wherever human-readable topic text is needed (e.g., agent prompts, report headers, temp file content).

**Read-only-repo contract (best-effort)**: This skill does not create branches, make commits, or modify tracked repo files via Claude's `Edit | Write | NotebookEdit` tool surface. The contract is enforced as two distinct tiers — only the first is mechanical. See `${CLAUDE_PLUGIN_ROOT}/SECURITY.md` § [External reviewer write surface in /research and /loop-review](../../SECURITY.md#external-reviewer-write-surface-in-research-and-loop-review) for the full residual-risk framing.

- **Mechanically enforced (Claude `Edit | Write | NotebookEdit` surface)**: the skill-scoped PreToolUse hook `${CLAUDE_PLUGIN_ROOT}/scripts/deny-edit-write.sh` matches `Edit|Write|NotebookEdit` and permits the call only when the target `tool_input.file_path` (or `tool_input.notebook_path`) resolves to an absolute path under canonical `/tmp`; any other path denies. The hook is the **sole** mechanical enforcer of the `/tmp`-only policy — `allowed-tools` lists `Edit`, `Write`, `NotebookEdit`, and `Skill` to declare the orchestrator's surface but does NOT confine writes by itself. The hook's matcher does **not** include `Bash` or `Skill` (see Tier 2).

- **Prompt-enforced only (everything else)**:
  - **External reviewers (Cursor, Codex)** launch directly against the working tree (`cursor agent ... --workspace "$PWD"`, `codex exec --full-auto -C "$PWD"`) and have full user-level filesystem access. Their non-modification is requested in the reviewer prompt only — no mechanical guard prevents repo writes if a reviewer ignores the instruction.
  - **Claude's own `Bash` calls** (heredoc writes, `>>` redirects, subprocesses, `git`) are also prompt-only constrained. Existing Bash heredoc writes to `$RESEARCH_TMPDIR` under `/tmp` continue to work unchanged — that placement is by convention, not by the hook.
  - **`Skill` is unscoped** in `allowed-tools` so `/research` may invoke `/issue` via the Skill tool for research-results-to-issues flows; child skills run under their own `allowed-tools` and hooks, not under this one. The Skill tool itself is mechanically permitted; *which* skills it invokes is prompt-narrowed.
  - **`Agent`-tool fallbacks** (Claude subagents launched in degraded mode when Cursor or Codex is unavailable — see `references/research-phase.md` and `references/validation-phase.md`) run as separate subprocesses with their own `allowed-tools` (typically the `code-reviewer` archetype's tools). The `/research` skill-scoped PreToolUse hook does NOT propagate to spawned Agent subagents — fallback subagents' tool-call boundary is governed by their own agent definitions, not by this hook.

- **Residual risk**: even the mechanical hook depends on the running Claude Code version honoring `permissionDecision: "deny"` — a non-honoring host has no fallback. `/tmp` is shared scratch, not session-scoped: another skill in the same session may read this skill's tmpdir, so `/tmp` placement is *not a confidentiality boundary*.

**Known limitation**: concurrent repo changes during a long research run may cause agents to see slightly different snapshots.

## Sub-skill invocation

Invoke `/issue` via the Skill tool when the research brief calls for filing the findings as GitHub issues. Follow the Pattern B conventions in `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` — parse `/issue`'s stdout machine lines (`ISSUES_CREATED`, `ISSUES_FAILED`, `ISSUES_DEDUPLICATED`) and continue with the parent's next step after the child returns. The numbered procedure below specifies the call site and the mechanical post-invocation gate that supplements stdout parsing as defense in depth.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

## Filing findings as issues

A 5-step numbered procedure invoked when the research brief calls for filing findings as GitHub issues. Anchors the `/issue` invocation and its post-return verification at a concrete control-flow site (issue #509 plan review FINDING_11) so harnesses pin the procedure structure, not just generic prose.

Defense in depth: stdout parsing of `ISSUES_*` is the primary post-`/issue` mechanical check; the sentinel-file gate below is a supplemental layer that catches the case where a child silently bailed without emitting counters. Both apply.

1. **Defensive sentinel clear** — before invoking `/issue`, remove any stale sentinel from a prior run that may have reused the same tmpdir:

   ```bash
   rm -f "$RESEARCH_TMPDIR/issue-completed.sentinel"
   ```

2. **Invoke `/issue`** via the Skill tool with `--sentinel-file` pointing to the path above:

   ```
   --sentinel-file $RESEARCH_TMPDIR/issue-completed.sentinel <other-/issue-args>
   ```

   `--sentinel-file` is the narrow per-call flag (NOT a `--session-env` reader; FINDING_10). It accepts a single absolute path. `/issue` writes the sentinel at the end of its Step 7 only when `ISSUES_FAILED=0 AND not dry-run`; the all-dedup case (`ISSUES_CREATED=0`, `ISSUES_FAILED=0`, `ISSUES_DEDUPLICATED>=1`) DOES write the sentinel because it proves execution, not creation count.

3. **Parse `/issue` stdout** for the canonical machine lines:
   - `ISSUES_CREATED=<N>`, `ISSUES_DEDUPLICATED=<N>`, `ISSUES_FAILED=<N>`.
   - Per-item `ISSUE_<i>_NUMBER`/`ISSUE_<i>_URL` for created issues.

   Stdout parsing is the **primary** mechanical check (canonical post-`/issue` pattern per `subskill-invocation.md` "Parsed stdout machine value after /issue").

4. **Mechanical sentinel verification** (defense in depth):

   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$RESEARCH_TMPDIR/issue-completed.sentinel"
   ```

   Parse `VERIFIED=true|false` and `REASON=<token>` from stdout. On `VERIFIED=true`, continue. On `VERIFIED=false`, print the fail-closed warning citing `REASON` and abort:

   ```
   **⚠ /research: /issue did not complete cleanly (VERIFIED=false REASON=<token>) — aborting.**
   ```

5. **Fail-closed-on-any-failure intent** (FINDING_8): when `/issue` reports `ISSUES_FAILED>=1`, the sentinel is suppressed by design and `/research` aborts at step 4. This is intentional — research-result-filing semantics require all items to succeed; partial failure is operator-investigation territory and the operator must inspect per-item `ISSUE_<i>_FAILED=true` lines on stdout to recover. Do NOT add a conditional verify or partial-success branch.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 1: research**`
- Print a **completion line** when done: e.g., `✅ 1: research — synthesis complete, 3 agents (3m12s)`

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 0.5 | classify-scale |
| 1 | research |
| 1.1 | planner |
| 1.1.c | interactive-review |
| 1.2 | lane-assign |
| 2 | validation |
| 2.5 | adjudication |
| 2.7 | citation-validation |
| 2.8 | critique loop |
| 3 | report |
| 4 | cleanup |

(Step 0.5 runs unconditionally on every `/research` invocation — it skips the classifier with a one-line `⏩ manual override` breadcrumb when `--scale=` is set, and otherwise invokes the deterministic shell classifier to resolve `RESEARCH_SCALE`. Step 1.1 and 1.2 are sub-steps of Step 1 that execute only when `RESEARCH_SCALE != quick` AND `RESEARCH_PLAN=true`. Step 1.1.c additionally requires `RESEARCH_PLAN_INTERACTIVE=true`. They are skipped on every other path — single-lane quick mode has no fan-out to assign subquestions to.)

### Verbosity Control

**When `debug_mode=false` (default):**

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (findings, risk assessments, research report sections), and the compact agent status table (see below).

**Compact agent status table**: After launching research agents (Step 1) or validation reviewers (Step 2), maintain a mental tracker of each agent's status. Print a compact table after EACH status change:

```
📊 Agents: | Claude: ✅ 2m31s | Cursor: ⏳ | Codex: ✅ 3m5s |
```

Icons: ✅ done (with elapsed time since launch), ⏳ pending/in-progress, ❌ failed/timeout (with elapsed time since launch), ⊘ skipped (unavailable). This replaces individual per-agent completion messages in non-debug mode. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for elapsed time and step start formatting rules.

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls, per-agent individual completion messages.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text and BOTH status table and per-agent details.

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Step 0 — Session Setup

### 0a — Session Setup and Reviewer Check

Run the shared session setup script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-research --skip-preflight --skip-branch-check --skip-slack-check --skip-repo-check --check-reviewers
```

If the script exits non-zero, print the error and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`, `CODEX_PROBE_ERROR`, `CURSOR_PROBE_ERROR`. Set `RESEARCH_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

Set mental flags `codex_available` and `cursor_available` based on the output, and remember each lane's pre-launch attribution status (one of `ok` / `fallback_binary_missing` / `fallback_probe_failed`) for the Step 0b lane-status init below:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Pre-launch status = `fallback_binary_missing` (no reason). Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Pre-launch status = `fallback_probe_failed` with reason = `CODEX_PROBE_ERROR` (sanitized). Print: `**⚠ Codex installed but not responding (health check failed: <CODEX_PROBE_ERROR>). Using Claude replacement.**` (omit the parenthetical detail when `CODEX_PROBE_ERROR` is empty).
- Else: `codex_available=true`. Pre-launch status = `ok`.
- Same logic for Cursor (using `CURSOR_PROBE_ERROR`).

### 0.5 — Adaptive Scale Classification

Print: `> **🔶 0.5: classify-scale**`

Runs unconditionally on every `/research` invocation. Resolves `RESEARCH_SCALE` to one of `quick|standard|deep` and records `SCALE_SOURCE` ∈ {`override`, `auto`, `fallback`} for downstream warning-text branching. **Must complete before Step 0b** (which skips when `RESEARCH_SCALE=quick`) and before the token-budget start-of-run notice (same skip predicate). With Step 0.5 placed between Step 0a and Step 0b, both downstream consumers see `RESEARCH_SCALE` resolved to a valid bucket value (never empty).

**Skip-on-override branch**:

If `RESEARCH_SCALE` is already non-empty (operator passed `--scale=value` at flag parsing): set `SCALE_SOURCE=override`. Print:

```
⏩ 0.5: classify-scale — manual override --scale=$RESEARCH_SCALE (<elapsed>)
```

Proceed to Step 0b. Do NOT invoke the classifier script.

**Auto-classify branch**:

If `RESEARCH_SCALE` is empty: write `RESEARCH_QUESTION` to `$RESEARCH_TMPDIR/classifier-question.txt` (use `printf '%s' "$RESEARCH_QUESTION" > "$RESEARCH_TMPDIR/classifier-question.txt"` so trailing newlines and shell metacharacters are preserved verbatim). Then invoke the classifier:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/classify-research-scale.sh \
  --question "$RESEARCH_TMPDIR/classifier-question.txt"
```

Capture stdout. The script writes ONLY machine output to stdout (`SCALE=<bucket>` + `REASON=<token>` on success; `REASON=<token>` on failure) and human diagnostics to stderr. See `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/classify-research-scale.md` for the full contract.

**On exit 0** (success): parse `SCALE=<bucket>` from stdout via prefix-strip, save as `RESEARCH_SCALE`. Parse `REASON=<token>` for the breadcrumb. Set `SCALE_SOURCE=auto`. Print:

```
✅ 0.5: classify-scale — auto-classified as $RESEARCH_SCALE (reason: $REASON) (<elapsed>)
```

Proceed to Step 0b.

**On non-zero exit** (validation failure): parse `REASON=<token>` from stdout via prefix-strip. Set `RESEARCH_SCALE=standard` (the safest middle option — preserves multi-lane validation, never silently downgrades broad questions to single-lane). Set `SCALE_SOURCE=fallback`. Print:

```
**⚠ 0.5: classify-scale — fallback to standard ($REASON). (<elapsed>)**
```

Proceed to Step 0b. The fallback is deliberate: a classifier failure must NEVER block a research run.

### 0b — Initialize lane-status record

**Skip this entire sub-step when `RESEARCH_SCALE=quick`.** Quick mode has no external lanes to attribute; Step 3 emits a per-`LANES_SUCCEEDED` research-phase header (issue #520: "3 agents (K-lane voting confidence — no validation pass)" on the `LANES_SUCCEEDED >= 2` vote path; "1 agent (single-lane fallback — K-vote partially failed)" on the `LANES_SUCCEEDED == 1` path; "0 agents (research-phase failed — all K=3 lanes returned empty or failed substantive validation)" on the `LANES_SUCCEEDED == 0` path) and the literal `0 reviewers (validation phase skipped — see synthesis disclaimer)` validation-phase header, without consulting `lane-status.txt` (Step 3 Quick branch sets these literals directly — see the `### Quick (RESEARCH_SCALE=quick)` subsection below).

For `RESEARCH_SCALE=standard` and `RESEARCH_SCALE=deep`, write `$RESEARCH_TMPDIR/lane-status.txt` with the per-tool aggregate pre-launch attribution. The same 8-key schema below covers both standard (1 Cursor + 1 Codex per phase) and deep (per-tool aggregate across 2 Cursor + 2 Codex in research, 1 Cursor + 1 Codex in validation): `RESEARCH_CURSOR_*` reflects the per-tool aggregate over both Cursor research slots in deep mode; same for `RESEARCH_CODEX_*`. Step 1.4 (research-phase) and Step 2 entry / validation-phase render-failure handlers (Cursor / Codex `On non-zero exit` paths) / Step 2.4 (validation-phase) update this file later via surgical phase-local rewrites; Step 3 reads it via `${CLAUDE_PLUGIN_ROOT}/scripts/render-lane-status.sh` for standard mode and `${CLAUDE_PLUGIN_ROOT}/scripts/render-deep-lane-status.sh` for deep mode to render the final-report header (both share the rendering library `render-lane-status-lib.sh`). Quick mode does NOT consult this file — see Step 3 ### Quick.

Sanitize each `*_PROBE_ERROR` value before writing: strip embedded `=` and `|` characters, collapse whitespace runs to single space, trim, truncate to 80 chars. The render script applies the same rules as defense-in-depth, but writer-side sanitization keeps the KV file well-formed.

Use the orchestrator-resolved pre-launch status for each lane (Step 0a determined `ok` / `fallback_binary_missing` / `fallback_probe_failed` per lane). Both Research and Validation rows initialize from the same pre-launch facts; runtime updates come later. Token vocabulary is documented in `${CLAUDE_PLUGIN_ROOT}/scripts/render-lane-status-lib.md` (the canonical token table; both `render-lane-status.sh` and `render-deep-lane-status.sh` source the same library).

The heredoc body uses a **quoted delimiter** (`<<'EOF'`) so that any residual shell metacharacters (dollar sign, backticks, backslashes, double quotes) in a substituted reason value are preserved verbatim instead of being expanded — a defense against hostile content in `*_PROBE_ERROR` from `.diag` files of external tools. The orchestrator literally substitutes the resolved per-lane status and sanitized reason text into the placeholders below before writing the command.

```bash
cat > "$RESEARCH_TMPDIR/lane-status.txt" <<'EOF'
RESEARCH_CURSOR_STATUS=<cursor pre-launch status>
RESEARCH_CURSOR_REASON=<cursor sanitized reason or empty>
RESEARCH_CODEX_STATUS=<codex pre-launch status>
RESEARCH_CODEX_REASON=<codex sanitized reason or empty>
VALIDATION_CURSOR_STATUS=<cursor pre-launch status>
VALIDATION_CURSOR_REASON=<cursor sanitized reason or empty>
VALIDATION_CODEX_STATUS=<codex pre-launch status>
VALIDATION_CODEX_REASON=<codex sanitized reason or empty>
EOF
```

### 0c — Record Research Context

Record the current branch and commit for inclusion in the final report:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-branch-info.sh
```

Parse the output for `HEAD_SHA` and `CURRENT_BRANCH`. If `CURRENT_BRANCH` is empty (detached HEAD), use `"(detached HEAD)"` in the report.

Print: `✅ 0: setup — researching on branch <CURRENT_BRANCH> at <HEAD_SHA> (<elapsed>)`

### Token-budget start-of-run notice

When `RESEARCH_TOKEN_BUDGET` is non-empty, print: `**ℹ --token-budget=$RESEARCH_TOKEN_BUDGET governs measured Claude subagent tokens only; Claude inline + external lanes (Cursor/Codex) are excluded from the cap. Unmeasurable lanes are reported separately.**`. The notice applies to all scales — for `RESEARCH_SCALE=quick` (issue #520), the K=3 homogeneous Claude Agent-tool lanes are measurable (Quick-Lane-1/2/3 sidecars) AND the synthesis subagent is measurable on the `LANES_SUCCEEDED >= 2` path; the budget cap applies to all of these.

Initialize `BUDGET_ABORTED=false` for the remainder of the run.

## Step 1 — Collaborative Research Perspectives

Print: `> **🔶 1: research**`

**MANDATORY — READ ENTIRE FILE** before executing Step 1: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md`. It carries the scale-aware research-lane invariant banner, the four named angle-prompt literals (`RESEARCH_PROMPT_ARCH`, `RESEARCH_PROMPT_EDGE`, `RESEARCH_PROMPT_EXT`, `RESEARCH_PROMPT_SEC`) used by standard mode (3 of 4) and deep mode (all 4), the external-evidence trigger detector and the conditional `RESEARCH_PROMPT_BASELINE` literals (one per `external_evidence_mode` value, used by quick mode and deep-mode's Claude inline lane only), the standard-mode per-lane angle assignment table (Cursor → ARCH; Codex → EDGE by default or EXT when `external_evidence_mode=true`; Claude inline → SEC), the optional Step 1.1 (Planner Pre-Pass) and Step 1.2 (Lane Assignment) gated on `RESEARCH_PLAN=true` AND `RESEARCH_SCALE != quick` (enabled for both standard and deep), the per-scale launch subsections (### Standard / ### Quick / ### Deep) with the Cursor and Codex launch bash blocks and their per-slot Claude fallbacks, the Claude inline-research independence rule, Step 1.4 `COLLECT_ARGS` + zero-externals branch + Runtime Timeout Fallback pointer (including the per-lane suffix rehydration from `lane-assignments.txt` when planner ran — suffix appended to each lane's angle base prompt; deep-mode runtime fallbacks consult the canonical lane→slot→angle mapping in §1.4 Deep), and Step 1.5 synthesis requirements (per-scale: **synthesis is routed to a separate Claude Agent subagent** for the 3 non-quick branches — Standard `RESEARCH_PLAN=false`, Standard `RESEARCH_PLAN=true`, Deep `RESEARCH_PLAN=false`, Deep `RESEARCH_PLAN=true` — to debias the synthesis-of-record from the orchestrator that authored the lane-3 SEC inline research; **the orchestrator owns the reduced-diversity banner via the canonical executable `compute-degraded-banner.sh`** computed before subagent invocation and post-processed (prepended) to the synthesis body before writing `research-report.txt`; **a 4-profile structural marker validator** gates the subagent's output (Standard/false: 5 markers `### Agreements` / `### Divergences` / `### Significance` / `### Architectural patterns` / `### Risks and feasibility`; Standard/true: anchored regex `^### Subquestion [0-9]+:` count == `RESEARCH_PLAN_N` + `### Cross-cutting findings`; Deep/false: 5 markers + 4 angle names; Deep/true: anchored regex Subquestion count + `### Per-angle highlights` + `### Cross-cutting findings` + 4 angle names) — on validator failure the orchestrator falls back to inline synthesis with operator-visible warning (the inline-fallback path applies the same per-profile validator); standard names the angle perspectives and treats angle-driven divergence as expected, sub-sectioned by subquestion when `RESEARCH_PLAN=true` with explicit single-angle-perspective acknowledgment; **quick K=3 homogeneous Claude Agent-tool lanes** (issue #520) — `LANES_SUCCEEDED >= 2` invokes the synthesis subagent with vote-merge framing (5th profile in `test-synthesis-subagent.sh`: Quick-vote — `### Consensus` / `### Divergence` / `### Correlated-error caveat` markers); `LANES_SUCCEEDED == 1` skips the subagent and falls back to single-lane inline synthesis with the existing `Single-lane confidence` disclaimer (6th profile: Quick-fallback); `LANES_SUCCEEDED == 0` hard-fails with no synthesis; deep names the four diversified angles by name in synthesis — and when `RESEARCH_PLAN=true` adds subquestion-major sections + Per-angle highlights + Cross-cutting findings). **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md` at Step 1** — that reference is Step 2's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/adjudication-phase.md` at Step 1** — that reference is Step 2.5's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/citation-validation-phase.md` at Step 1** — that reference is Step 2.7's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` at Step 1** — that reference is Step 2.8's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 1 per the reference file above (phases 1.1 through 1.5; phases 1.1 and 1.2 are gated on `RESEARCH_PLAN=true` AND `RESEARCH_SCALE != quick`), branching by `RESEARCH_SCALE`. SKILL.md is the sole owner of Step 1 entry and completion breadcrumbs; the reference file emits none. On completion, set `LANE_COUNT` from `RESEARCH_SCALE` (`quick` → 3 — K=3 homogeneous Claude Agent-tool lanes per issue #520; `standard` → 3, `deep` → 5) and print: `✅ 1: research — synthesis complete, $LANE_COUNT agents (<elapsed>)` (e.g. "3 agents" for quick or standard, "5 agents" for deep — the count must reflect the actual lane count of the configured scale).

### Budget gate (after Step 1)

When `RESEARCH_TOKEN_BUDGET` is non-empty, run the budget check before Step 2. The exit code is captured via `|| budget_rc=$?` so `set -e` does NOT propagate on exit 2 (which is the budget-overage signal):

```bash
budget_rc=0
budget_out=$("${CLAUDE_PLUGIN_ROOT}/scripts/token-tally.sh" check-budget \
  --budget "$RESEARCH_TOKEN_BUDGET" --dir "$RESEARCH_TMPDIR") || budget_rc=$?
```

If `budget_rc == 2`: print `**⚠ /research: --token-budget=$RESEARCH_TOKEN_BUDGET exceeded after Step 1 ($budget_out). Aborting before Step 2.**`, set `BUDGET_ABORTED=true`, **skip Step 2 / Step 2.5 / Step 3 entirely**, jump directly to Step 4 (which will render the partial token report and clean up). When `RESEARCH_TOKEN_BUDGET` is empty (no budget set), this gate is skipped.

## Step 2 — Findings Validation

Print: `> **🔶 2: validation**`

**Quick-mode skip gate (emitted FIRST, before any reference load — Check 3 of `scripts/test-research-structure.sh` requires the MANDATORY directive line below to remain on a single line carrying both the directive and the reciprocal `Do NOT load` guards, so the skip gate is structured to short-circuit BEFORE that line)**: if `RESEARCH_SCALE=quick`, print `⏩ 2: validation — skipped (--scale=quick) (<elapsed>)` and proceed directly to Step 3 without loading `validation-phase.md`. The single-lane research-report.txt produced at Step 1.5 is the canonical input to Step 3.

**MANDATORY — READ ENTIRE FILE** before executing Step 2: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md`. It carries the scale-aware validation invariant banner, the Cursor and Codex validation-reviewer launch bash blocks with their long prompts and per-slot Claude Code Reviewer subagent fallbacks, the always-on Claude Code Reviewer subagent lane with the research-validation variable bindings (`{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` / `{OUTPUT_INSTRUCTION}`) and research-specific acceptance criteria, the deep-mode 2 extra Claude lanes (`Code-Sec` / `Code-Arch` lane-local emphasis on the unified Code Reviewer archetype, reusing the same `{CONTEXT_BLOCK}` XML wrapper), the process-Claude-findings-immediately rule, Step 2.4 `COLLECT_ARGS` + zero-externals branch + runtime-timeout replacement, the Codex/Cursor negotiation delegation to `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`, the Finalize Validation procedure (where **synthesis revision is routed to a separate Claude Agent subagent** when accepted findings exist — same separation-of-concerns argument as Step 1.5; the revision subagent receives the existing synthesis body + accepted findings under `<accepted_findings>` tags + revision brief; output captured to `$RESEARCH_TMPDIR/revision-raw.txt`; gated by the same per-profile structural validator as Step 1.5; orchestrator atomically rewrites `$RESEARCH_TMPDIR/research-report.txt` with the same envelope shape; inline-revision fallback on validator failure with operator-visible warning), and the **rejection-rationale capture sites A and B** that persist `(finding, rejection_rationale)` records to `$RESEARCH_TMPDIR/rejected-findings.md` for downstream consumption by Step 2.5 (the captures themselves run unconditionally regardless of `RESEARCH_ADJUDICATE`). **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` at Step 2** — that reference is Step 1's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/adjudication-phase.md` at Step 2** — that reference is Step 2.5's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/citation-validation-phase.md` at Step 2** — that reference is Step 2.7's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` at Step 2** — that reference is Step 2.8's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 2 per the reference file above, branching by `RESEARCH_SCALE` (standard launches 3 lanes; deep additionally launches 2 extra Claude lanes for a 5-lane panel). SKILL.md is the sole owner of Step 2 entry and completion breadcrumbs; the reference file emits none. On completion, set `VALIDATION_COUNT` from `RESEARCH_SCALE` (`standard` → 3, `deep` → 5; quick is unreachable here — already short-circuited above) and print one of the two branches depending on the Finalize Validation outcome:
- If all reviewers reported no issues: `✅ 2: validation — all findings validated, no corrections needed ($VALIDATION_COUNT reviewers) (<elapsed>)`
- If any findings were accepted and the synthesis was revised: `✅ 2: validation — corrections applied, <N> findings accepted ($VALIDATION_COUNT reviewers) (<elapsed>)`

### Budget gate (after Step 2)

The post-Step-2 budget gate has been **relocated to fire after Step 2.8** instead of after Step 2 (per #517 dialectic DECISION_4 — single relocated gate, critique-loop tokens count under the existing `validation` phase enum, no new `--phase` value). The post-Step-2.5 budget gate immediately below is still the next opportunity to abort before Step 2.7 + Step 2.8 measurable spend. See "Budget gate (after Step 2.8)" further down for the relocated gate.

## Step 2.5 — Adjudicate Rejections

Print: `> **🔶 2.5: adjudication**`

If `RESEARCH_ADJUDICATE=false`: print `⏩ 2.5: adjudication — skipped (--adjudicate not set) (<elapsed>)` and proceed to Step 2.7 WITHOUT loading `adjudication-phase.md`.

**MANDATORY — READ ENTIRE FILE** before executing Step 2.5: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/adjudication-phase.md`. It carries the conditional skip-path on empty `rejected-findings.md`, the pre-launch coordinator invocation (`scripts/run-research-adjudication.sh`), the 3-judge panel launch and collection (replacement-first when externals unhealthy), the dialectic-protocol.md parser-tolerance + threshold-rule reuse, the `adjudication-resolutions.md` schema (pinned to `dialectic-protocol.md`'s Consumer Contract field names), and the reinstatement-into-validated-synthesis sub-step that revises the report under the existing `## Revised Research Findings` header before Step 3 reads it. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` at Step 2.5** — that reference is Step 1's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md` at Step 2.5** — that reference is Step 2's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/citation-validation-phase.md` at Step 2.5** — that reference is Step 2.7's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` at Step 2.5** — that reference is Step 2.8's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 2.5 per the reference file above. SKILL.md is the sole owner of Step 2.5 entry and completion breadcrumbs; the reference file emits none. On completion, print one of these branches:
- If `rejected-findings.md` was empty/absent: `⏩ 2.5: adjudication — no rejections to adjudicate (<elapsed>)`
- Otherwise: `✅ 2.5: adjudication — <X> reinstated, <Y> upheld (<elapsed>)`

### Budget gate (after Step 2.5)

When `RESEARCH_TOKEN_BUDGET` is non-empty, run the same budget check as the prior gates (capturing exit code via `|| budget_rc=$?`). On `budget_rc == 2`: print `**⚠ /research: --token-budget=$RESEARCH_TOKEN_BUDGET exceeded after Step 2.5 ($budget_out). Aborting before Step 2.7.**`, set `BUDGET_ABORTED=true`, skip Step 2.7 and Step 3, jump to Step 4.

## Step 2.7 — Citation Validation

Print: `> **🔶 2.7: citation-validation**`

**Skip preconditions** (emitted FIRST, before any reference load): if `BUDGET_ABORTED=true` (set by any earlier budget gate), print `⏩ 2.7: citation-validation — skipped (--token-budget aborted upstream) (<elapsed>)` and proceed to Step 4 (Step 3 was already skipped). If `$RESEARCH_TMPDIR/research-report.txt` does not exist OR is zero bytes, print `⏩ 2.7: citation-validation — skipped (no synthesis to validate) (<elapsed>)` and proceed to Step 3 without loading `citation-validation-phase.md`. The empty-synthesis path is reachable when Step 1 inline-fallback synthesis failed and produced no body.

**MANDATORY — READ ENTIRE FILE** before executing Step 2.7: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/citation-validation-phase.md`. It carries the input gate (skip on missing/empty `research-report.txt`), the validator invocation (`${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/validate-citations.sh`), the sidecar schema (3-state ledger PASS/FAIL/UNKNOWN with reason classifier; sorted rows for idempotency), the SSRF defenses recap (HTTPS-only, `--max-redirs 0`, `--noproxy '*'`, RFC1918/IPv6 link-local/RFC6598 hostname pre-rejection, DNS resolved-IP private-range check via `host`→`nslookup` chain, multi-answer rebinding defense, connection-pinning via `--resolve`), the curl flag MUST/MUST-NOT contract (MUST: `--max-redirs 0`, `--max-time`, `--noproxy '*'`, HTTPS URL last; MUST-NOT: `--insecure`, `-k`, `--proxy`, `--socks*`, `--cacert`), DOI validation (syntactic + `HEAD https://doi.org/<doi>`), file:line spot-check semantics (git rev-parse fail-soft → UNKNOWN, realpath canonical-path containment, broken-symlink and out-of-tree-path UNKNOWN reasons, line-out-of-range FAIL), the fail-soft contract (script always exits 0; per-claim failures recorded; advisory-only domain credibility heuristic; never flips PASS to FAIL), the Step 3 splice contract (sidecar appended as `## Citation Validation` section into `research-report-final.md` before the user-visible `cat`), the idempotency rerun rule (deterministic stdout ordering, byte-identical sidecar across consecutive runs against unchanged synthesis), the budget-exhaustion process-group kill semantics (Linux `setsid`; macOS `set -m` + `kill -- -<pgid>`), and the composition rules with `--token-budget` (validator is unmeasurable; no Step 2.7 budget gate) and `--keep-sidecar` (which preserves a different sidecar — `research-findings-batch.md` — and is unrelated to Step 2.7's citation sidecar). **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` at Step 2.7** — that reference is Step 1's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md` at Step 2.7** — that reference is Step 2's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/adjudication-phase.md` at Step 2.7** — that reference is Step 2.5's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` at Step 2.7** — that reference is Step 2.8's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 2.7 per the reference file above. SKILL.md is the sole owner of Step 2.7 entry and completion breadcrumbs; the reference file does NOT emit those. Invoke the validator:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/validate-citations.sh \
  --report "$RESEARCH_TMPDIR/research-report.txt" \
  --output "$RESEARCH_TMPDIR/citation-validation.md" \
  --tmpdir "$RESEARCH_TMPDIR"
```

The script always exits 0 (fail-soft). Parse the last stdout line `SUMMARY=PASS=<n> FAIL=<n> UNKNOWN=<n> TOTAL=<n>` to drive the completion breadcrumb. Print:

```
✅ 2.7: citation-validation — <pass> PASS, <fail> FAIL, <unknown> UNKNOWN (<total> claims) (<elapsed>)
```

Then conditionally print advisory warnings (not errors — fail-soft):

- When `<fail> > 0`: `**⚠ 2.7: citation-validation — <fail> claim(s) FAILED. See ## Citation Validation in the report.**`
- When `<unknown> > 0`: `**ℹ 2.7: citation-validation — <unknown> claim(s) UNKNOWN. Common reasons: HEAD not supported (try GET manually), DNS resolution unavailable, git tree not detected. See ## Citation Validation in the report.**`

The sidecar at `$RESEARCH_TMPDIR/citation-validation.md` is consumed by Step 3 (splice contract: appended as a `## Citation Validation` section to `research-report-final.md` before the user-visible `cat`).

See `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/validate-citations.md` for the full validator contract (argv, exit codes, sidecar schema, SSRF defenses, regex tiers, idempotency rerun semantics, budget-exhaustion process-group kill via `setsid`/`set -m`). The offline regression harness is `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-validate-citations.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-validate-citations.md`), wired into `make lint`.

## Step 2.8 — Critique Loop

Print: `> **🔶 2.8: critique loop**`

**Quick-mode skip gate (emitted FIRST, before any reference load — Check 3 of `scripts/test-research-structure.sh` requires the MANDATORY directive line below to remain on a single line carrying both the directive and the reciprocal `Do NOT load` guards, so the skip gate is structured to short-circuit BEFORE that line)**: if `RESEARCH_SCALE=quick`, print `⏩ 2.8: critique loop — skipped (--scale=quick) (<elapsed>)` and proceed directly to the relocated post-Step-2.8 budget gate without loading `critique-loop-phase.md`. Quick scale has no Step 2 validation findings to feed the critique pass — per /design Round 1 user decision (#517).

**Skip preconditions** (also emitted before any reference load): if `BUDGET_ABORTED=true` (set by any earlier budget gate), print `⏩ 2.8: critique loop — skipped (--token-budget aborted upstream) (<elapsed>)` and proceed to the relocated budget gate (also a no-op when `BUDGET_ABORTED=true`), then to Step 4 (Step 3 was already skipped). If `$RESEARCH_TMPDIR/research-report.txt` is missing or zero-bytes, print `⏩ 2.8: critique loop — skipped (no synthesis to critique) (<elapsed>)` and proceed to Step 3. If `$RESEARCH_TMPDIR/citation-validation.md` is missing (Step 2.7 skipped on its own input gate), print `⏩ 2.8: critique loop — skipped (no citation sidecar) (<elapsed>)` and proceed to Step 3.

**MANDATORY — READ ENTIRE FILE** before executing Step 2.8: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md`. It carries the loop control (cap `RESEARCH_CRITIQUE_MAX=2`, per-iteration critique-pass + categorical-Important gate + refine-pass + citation re-validation), the critique prompt template (reuses `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md` Code Reviewer archetype with `{REVIEW_TARGET}` = `"research synthesis"` and namespaced XML wrappers `<reviewer_research_question>` / `<reviewer_research_findings>` / `<reviewer_citation_validation>` / `<reviewer_adjudication_resolutions>`), the in-scope `**Important**`-finding parser-scope rule (only finding-bullet lines under `## In-Scope Findings`, NOT inside fenced code blocks, NOT under `## Out-of-Scope Observations`), the parser fail-safe defaulting to "continue" on parse failure with operator-visible warning, the refine-subagent contract (reuses Step 2 Finalize Validation revision-subagent contract — same per-profile structural validator, same atomic mktemp+mv rewrite of `research-report.txt`, same inline-revision fallback on validator failure), the canonical slot-name list (`Critique-1`, `Critique-2`, `Revision-Critique-1`, `Revision-Critique-2` — recorded under existing `validation` phase enum per dialectic DECISION_4), the citation-revalidation invariant (overwrites `citation-validation.md` in place per dialectic DECISION_3) plus the per-iteration `✅ 2.8 [iter <iter>]: citation-revalidation — …` breadcrumb the reference owns (canonical one-line template lives in `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` 2.8.6 — mirrors Step 2.7's completion-breadcrumb shape namespaced under `2.8 [iter <iter>]` so each in-loop revalidation result is operator-visible without colliding with the original Step 2.7 output), the byte-equal idle-cycle guard reconciled with the categorical-Important gate (FINDING_4 from plan review — byte-equal exit fires only when zero Important findings; otherwise warning + continue), and the `--adjudicate` composition rule (conditionally include `<reviewer_adjudication_resolutions>` block + don't-relitigate instruction). **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` at Step 2.8** — that reference is Step 1's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md` at Step 2.8** — that reference is Step 2's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/adjudication-phase.md` at Step 2.8** — that reference is Step 2.5's body and loading it now would pollute context with the wrong phase's prompts. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/citation-validation-phase.md` at Step 2.8** — that reference is Step 2.7's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 2.8 per the reference file above. SKILL.md is the sole owner of Step 2.8 entry and completion breadcrumbs; the reference file does NOT emit those, but the reference DOES own intermediate operator prints — notably the per-iteration citation-revalidation breadcrumb in 2.8.6. On completion, print one of these branches:
- If the loop converged before reaching the cap (zero in-scope `**Important**` findings): `✅ 2.8: critique loop — converged at iter <N> (no Important findings) (<elapsed>)`
- If the loop ran to the cap: `✅ 2.8: critique loop — <N> iterations completed (<elapsed>)`
- If the byte-equal idle-cycle guard fired with zero Important findings: `⏩ 2.8: critique loop — refine produced no change at iter <N>; exiting loop (<elapsed>)`

### Budget gate (after Step 2.8) — RELOCATED from after Step 2

When `RESEARCH_TOKEN_BUDGET` is non-empty, run the same budget check as the prior gates (capturing exit code via `|| budget_rc=$?`). On `budget_rc == 2`: print `**⚠ /research: --token-budget=$RESEARCH_TOKEN_BUDGET exceeded after Step 2.8 ($budget_out). Aborting before Step 3.**`, set `BUDGET_ABORTED=true`, skip Step 3, jump to Step 4. This is the relocated post-Step-2 gate (per #517 dialectic DECISION_4): critique-loop subagent tokens count under the existing `validation` phase enum (slot names `Critique-1`/`Critique-2`/`Revision-Critique-1`/`Revision-Critique-2` per `${CLAUDE_PLUGIN_ROOT}/skills/research/references/critique-loop-phase.md` 2.8.5), and the relocation ensures all measurable validation + critique-loop spend is bounded by a single check before Step 3 renders the final report.

## Step 3 — Final Research Report

Print: `> **🔶 3: report**`

Render the per-lane attribution headers per `RESEARCH_SCALE`. Standard and deep both consult `$RESEARCH_TMPDIR/lane-status.txt` via per-mode helpers (`render-lane-status.sh` and `render-deep-lane-status.sh` respectively, sharing `render-lane-status-lib.sh` for token rendering and reason sanitization). Quick emits literal headers without consulting `lane-status.txt`. The standard branch uses `render-lane-status.sh` with the unchanged 8-key schema (lane-status rendering is unaffected by the angle-prompt differentiation in Step 1.3); the deep branch derives headers from the same 8-key schema's per-phase slices, eliminating the cross-phase contamination bug fixed by #451.

### Standard (RESEARCH_SCALE=standard, default)

Render the per-lane attribution headers from `$RESEARCH_TMPDIR/lane-status.txt`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/render-lane-status.sh --input "$RESEARCH_TMPDIR/lane-status.txt"
```

Parse the two output lines via prefix-strip (NOT `cut -d=`, since rendered values can contain `=` characters):
- `RESEARCH_HEADER="${line#RESEARCH_HEADER=}"` for the line beginning with `RESEARCH_HEADER=`
- `VALIDATION_HEADER="${line#VALIDATION_HEADER=}"` for the line beginning with `VALIDATION_HEADER=`

If the helper exits non-zero (e.g., `lane-status.txt` is missing — should not happen since Step 0b always writes it), substitute the placeholder line `_Lane attribution unavailable._` for both header rows and log to terminal: `**⚠ 3: report — render-lane-status failed; lane attribution unavailable.**`.

### Quick (RESEARCH_SCALE=quick)

Skip `render-lane-status.sh` (Step 0b did not write `lane-status.txt` for quick mode — issue #520 preserves this rule). Read the K-vote state via `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/quick-vote-state.sh read --dir "$RESEARCH_TMPDIR"` and parse `LANES_SUCCEEDED=<N>` from stdout. Emit literal headers branching on `N`:

- `LANES_SUCCEEDED >= 2`: `RESEARCH_HEADER="3 agents (K-lane voting confidence — no validation pass)"` (vote path).
- `LANES_SUCCEEDED == 1`: `RESEARCH_HEADER="1 agent (single-lane fallback — K-vote partially failed)"` (single-lane fallback path).
- `LANES_SUCCEEDED == 0`: `RESEARCH_HEADER="0 agents (research-phase failed — all K=3 lanes returned empty or failed substantive validation)"` (no-lane hard-fail path).

In all three cases:
- `VALIDATION_HEADER="0 reviewers (validation phase skipped — see synthesis disclaimer)"`

The validation-phase line is still rendered (with the 0-reviewers literal) so the report template's structure is preserved. The synthesis itself must already carry the appropriate disclaimer per `research-phase.md` Step 1.5 Quick #### sub-subsections (vote path → `K-lane voting confidence` text from `quick-disclaimer.txt`; single-lane fallback path → `Single-lane confidence` text from `quick-disclaimer-fallback.txt`; no-lane hard-fail path → in-line "research phase failed" message, no disclaimer file).

### Deep (RESEARCH_SCALE=deep)

Render the per-lane attribution headers from `$RESEARCH_TMPDIR/lane-status.txt` via the deep-mode renderer:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/render-deep-lane-status.sh --input "$RESEARCH_TMPDIR/lane-status.txt"
```

Parse the two output lines via prefix-strip (NOT `cut -d=`, since rendered values can contain `=` characters):
- `RESEARCH_HEADER="${line#RESEARCH_HEADER=}"` for the line beginning with `RESEARCH_HEADER=`
- `VALIDATION_HEADER="${line#VALIDATION_HEADER=}"` for the line beginning with `VALIDATION_HEADER=`

`render-deep-lane-status.sh` reads the same 8-key schema as standard (`RESEARCH_CURSOR_*`, `RESEARCH_CODEX_*`, `VALIDATION_CURSOR_*`, `VALIDATION_CODEX_*`) and emits the deep-mode 5+5 shape: `5 agents (Claude inline, Cursor-Arch: <r>, Cursor-Edge: <r>, Codex-Ext: <r>, Codex-Sec: <r>)` and `5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: <r>, Codex: <r>)`. Both Cursor research slots (Arch + Edge) share the per-tool aggregate `RESEARCH_CURSOR_*` token (matching the aggregate semantics in Step 0b); same for Codex research slots and `RESEARCH_CODEX_*`. The three Claude validation lanes (Code, Code-Sec, Code-Arch) have no fallback path and are hard-coded `✅`. Fallback-reason vocabulary (binary missing / probe failed / runtime timeout / runtime failed) is the same canonical set as standard, sourced from `render-lane-status-lib.sh`.

If the helper exits non-zero (e.g., `lane-status.txt` is missing — should not happen since Step 0b always writes it), substitute the placeholder line `_Lane attribution unavailable._` for both header rows and log to terminal: `**⚠ 3: report — render-deep-lane-status failed; lane attribution unavailable.**`.

Print the final research report under a `## Research Report` header with the following structure (substituting the rendered values for `<RESEARCH_HEADER>` and `<VALIDATION_HEADER>`):

```markdown
## Research Report

**Research question**: <RESEARCH_QUESTION>
**Codebase context**: Branch `<CURRENT_BRANCH>`, commit `<HEAD_SHA>`
**Research phase**: <RESEARCH_HEADER>
**Validation phase**: <VALIDATION_HEADER>
<ADJUDICATION_HEADER>

### Findings Summary
<synthesized and validated findings, organized by topic>

### Risk Assessment
<Low/Medium/High with rationale, or N/A if not applicable to this research question>

### Difficulty Estimate
<S/M/L/XL with rationale, or N/A if not applicable>

### Feasibility Verdict
<assessment of feasibility with rationale, or N/A if not applicable>

### Key Files and Areas
<list of the most relevant files/modules/areas identified during research>

### Open Questions
<any unresolved questions or areas that need further investigation>
```

Example rendered headers (one degraded research lane, one degraded validation lane):

```markdown
**Research phase**: 3 agents (Cursor: ✅, Codex: Claude-fallback (runtime timeout))
**Validation phase**: 3 reviewers (Code: ✅, Cursor: Claude-fallback (binary missing), Codex: ✅)
```

When any external research lane ran as a Claude-fallback (`N_FALLBACK >= 1` per the §1.5 banner preamble in `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md`), Step 1.5 also prepends a reduced-diversity banner under `## Research Synthesis` — visible to readers and persisted in `research-report.txt` so Step 2 reviewers see it. The banner is computed by the canonical executable helper `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/compute-degraded-banner.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/compute-degraded-banner.md`); the orchestrator forks the helper with `(lane-status.txt path, scale)` and prepends the helper's stdout to the synthesis subagent's body before writing `research-report.txt`. The banner contract is guarded by an offline regression harness (`${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-degraded-path-banner.sh`, contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-degraded-path-banner.md`) wired into `make lint`. The synthesis-subagent contract introduced by issue #507 (Step 1.5 routes synthesis to a separate Claude Agent subagent in non-quick branches; issue #520 extends this to the Quick `LANES_SUCCEEDED >= 2` vote path) is structurally pinned by `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-synthesis-subagent.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-synthesis-subagent.md`), also wired into `make lint`. Issue #520's K-vote state helper is `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/quick-vote-state.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/quick-vote-state.md`); its offline regression harness is `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-quick-vote-state.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-quick-vote-state.md`), wired into `make lint` via the `test-quick-vote-state` target. Example degraded-path preview (standard scale, Codex tool fell back):

```markdown
## Research Synthesis

**⚠ Reduced lane diversity: 1 of 2 external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**

[Then the usual agree / diverge / significance / architectural patterns / risks content follows...]
```

Quick mode does NOT carry this `Reduced lane diversity` banner — it has its own per-path disclaimer (issue #520): vote path → `**K-lane voting confidence — no validation pass; correlated-error risk: all K lanes are Claude (same model, same prompt — voting catches independent stochastic errors only).**` from `quick-disclaimer.txt`; single-lane fallback path (`LANES_SUCCEEDED == 1`) → `**Single-lane confidence — no validation pass.**` from `quick-disclaimer-fallback.txt`; partial-degradation banner (`LANES_SUCCEEDED == 2`) → `**⚠ K-lane voting partially degraded — 2 of 3 lanes succeeded.**` (intentionally distinct wording from `Reduced lane diversity` to satisfy `test-research-structure.sh` Check 21e).

If risk assessment, difficulty estimate, or feasibility verdict are not applicable to the nature of the research question (e.g., a pure "how does X work?" question), mark them as **N/A** with a brief explanation.

**Adjudication header**: substitute the `<ADJUDICATION_HEADER>` placeholder per `RESEARCH_ADJUDICATE`:
- `RESEARCH_ADJUDICATE=false`: replace the placeholder line with an empty line (no header rendered).
- `RESEARCH_ADJUDICATE=true` AND Step 2.5 ran: render `**Adjudication phase**: <X> reinstated, <Y> upheld` where `<X>` is the count of `Disposition: voted` resolutions whose `Resolution: reinstate` (ANTI_THESIS won) and `<Y>` is the count of resolutions whose `Resolution: rejection-stands` (THESIS won) plus any `Disposition: fallback-to-synthesis` (rejection stands by default). Both counts come from `$RESEARCH_TMPDIR/adjudication-resolutions.md` (parse before Step 4 cleanup).
- `RESEARCH_ADJUDICATE=true` AND Step 2.5 short-circuited (no rejections to adjudicate): render `**Adjudication phase**: 0 reinstated, 0 upheld (no rejections to adjudicate)`.

### Step 3 final-report write + sidecar generation

Single authoritative emission: write the full templated report block (header lines + every section above, with substituted values) to `$RESEARCH_TMPDIR/research-report-final.md` first, **append the Step 2.7 citation-validation sidecar** when present, then `cat` the file for user-visible output. This avoids drift between two emission paths (FINDING_8 from issue #510's design review).

The orchestrator writes the rendered report block (matching the template above with `## Research Report` header, `**Research question**:` / `**Codebase context**:` / `**Research phase**:` / `**Validation phase**:` / adjudication header lines, and the six `### ...` sections — Findings Summary, Risk Assessment, Difficulty Estimate, Feasibility Verdict, Key Files and Areas, Open Questions) to `$RESEARCH_TMPDIR/research-report-final.md` via Bash, with substituted values inline. Wrap the write in an explicit `if … ; then … ; fi` guard so a `cat >` failure (disk full, permission, etc.) does NOT abort the orchestrator block under `set -euo pipefail` — the cleanup at Step 4 must still run (FINDING_1). On write failure, set a mental flag `SKIP_SIDECAR=true` and emit a warning. Also write the research question to `$RESEARCH_TMPDIR/research-question.txt` so the helper can embed it in the audit-context line.

**Citation-validation splice** (Step 2.7 → Step 3 contract): after `research-report-final.md` is written successfully AND `SKIP_SIDECAR != true`, append the citation-validation sidecar to it when present. The sidecar already opens with the `## Citation Validation` header so no extra header is added; a single blank line separates the report block from the spliced section. On a missing/empty sidecar (Step 2.7 was skipped per its input gate), the splice is a no-op — no warning is printed because the Step 2.7 skip breadcrumb already informed the operator:

```bash
if [[ "$SKIP_SIDECAR" != "true" ]] && [[ -s "$RESEARCH_TMPDIR/citation-validation.md" ]]; then
  printf '\n' >> "$RESEARCH_TMPDIR/research-report-final.md"
  cat "$RESEARCH_TMPDIR/citation-validation.md" >> "$RESEARCH_TMPDIR/research-report-final.md"
fi
```

The append happens BEFORE the `render-findings-batch.sh` invocation below (so the helper's report-walk does not see the citation-validation block — it parses for findings only) AND BEFORE the user-visible `cat`.

**Mental flag init**: initialize `SKIP_SIDECAR=false` at the top of Step 3 before the guarded write block above (#510 review FINDING_4 — under `set -u`, the `[[ "$SKIP_SIDECAR" != "true" ]]` check below would error on unset).

After the write succeeds, invoke the helper to generate the sidecar. Source the Quick-mode disclaimer from the canonical file `${CLAUDE_PLUGIN_ROOT}/skills/research/data/quick-disclaimer.txt` only when `RESEARCH_SCALE=quick` (#510 design FINDING_4). The empty-array safe expansion `${ARR[@]+"${ARR[@]}"}` (quotes inside the `+` alternative — #510 review FINDING_1) is REQUIRED so a multi-element array does not collapse into one fused positional argument when the disclaimer text contains spaces:

```bash
if [[ "$SKIP_SIDECAR" != "true" ]]; then
  QUICK_DISCLAIMER_ARGS=()
  if [[ "$RESEARCH_SCALE" == "quick" ]]; then
    # Pick disclaimer file based on K-vote state (issue #520):
    # - LANES_SUCCEEDED >= 2: K-vote disclaimer (quick-disclaimer.txt).
    # - LANES_SUCCEEDED == 1: single-lane fallback disclaimer (quick-disclaimer-fallback.txt).
    # - LANES_SUCCEEDED == 0: no disclaimer (the inline "research-phase failed" message stands alone).
    QUICK_VOTE_STATE=$("${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/quick-vote-state.sh" read --dir "$RESEARCH_TMPDIR")
    QUICK_LANES_SUCCEEDED="${QUICK_VOTE_STATE#LANES_SUCCEEDED=}"
    QUICK_DISCLAIMER_FILE=""
    case "$QUICK_LANES_SUCCEEDED" in
      2|3) QUICK_DISCLAIMER_FILE="${CLAUDE_PLUGIN_ROOT}/skills/research/data/quick-disclaimer.txt" ;;
      1)   QUICK_DISCLAIMER_FILE="${CLAUDE_PLUGIN_ROOT}/skills/research/data/quick-disclaimer-fallback.txt" ;;
      *)   QUICK_DISCLAIMER_FILE="" ;;
    esac
    if [[ -n "$QUICK_DISCLAIMER_FILE" ]] && [[ -s "$QUICK_DISCLAIMER_FILE" ]]; then
      QUICK_DISCLAIMER=$(cat "$QUICK_DISCLAIMER_FILE")
      QUICK_DISCLAIMER_ARGS=(--quick-disclaimer "$QUICK_DISCLAIMER")
    fi
  fi
  if ! ${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/render-findings-batch.sh \
    --report "$RESEARCH_TMPDIR/research-report-final.md" \
    --output "$RESEARCH_TMPDIR/research-findings-batch.md" \
    --research-question-file "$RESEARCH_TMPDIR/research-question.txt" \
    --branch "$CURRENT_BRANCH" --commit "$HEAD_SHA" \
    ${QUICK_DISCLAIMER_ARGS[@]+"${QUICK_DISCLAIMER_ARGS[@]}"}; then
    echo "**⚠ 3: report — render-findings-batch helper exited non-zero (likely empty findings — see warning above). Continuing.**"
  fi
fi
```

Helper exit 3 (empty findings) is non-fatal — the helper writes an empty sidecar and prints a warning to stderr. Exits 1 / 2 indicate operator/orchestrator bugs and are also logged but non-fatal here. See `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/render-findings-batch.md` for the full contract; the offline regression harness is `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-render-findings-batch.sh` (contract in sibling `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/test-render-findings-batch.md`), wired into `make lint`.

Finally print the report for user visibility, gated on a successful write (#510 review FINDING_3 — under `set -euo pipefail` an unconditional `cat` of a missing file would abort the orchestrator block, contradicting FINDING_1's no-abort intent):

```bash
if [[ "$SKIP_SIDECAR" != "true" ]] && [[ -s "$RESEARCH_TMPDIR/research-report-final.md" ]]; then
  cat "$RESEARCH_TMPDIR/research-report-final.md"
fi
```

Print: `✅ 3: report — complete (<elapsed>)`

## Step 4 — Cleanup and Final Warnings

### Budget-abort prelude (when `BUDGET_ABORTED=true`)

If `BUDGET_ABORTED=true` (set by any of the budget gates after Steps 1, 2.5, or 2.8), Step 3 was skipped — no `## Research Report` was rendered. Print: `**Step 3 skipped (aborted: --token-budget exceeded). Partial telemetry follows.**` so the operator sees the cause clearly.

### Token Spend report (always)

Render the `## Token Spend` section before `cleanup-tmpdir.sh` so sidecars under `$RESEARCH_TMPDIR` are still readable. The script owns the full section (header + body) — SKILL.md just executes it and prints the stdout:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/token-tally.sh report \
  --dir "$RESEARCH_TMPDIR" \
  --scale "$RESEARCH_SCALE" \
  --adjudicate "$RESEARCH_ADJUDICATE" \
  --planner "$RESEARCH_PLAN" \
  --budget-aborted "$BUDGET_ABORTED"
```

The script is a no-op-safe call: when no sidecars exist (e.g., quick mode with no measurable lanes), it prints a `_(no measurements available)_` placeholder; if `$RESEARCH_TMPDIR` was already removed, it prints `_(token telemetry unavailable)_`. Either path exits 0 — the report block is always emitted, even on degraded paths. See `${CLAUDE_PLUGIN_ROOT}/scripts/token-tally.md` for the full contract.

### Preserve sidecar (when `KEEP_SIDECAR=true`)

If `KEEP_SIDECAR=true`, copy the generated sidecar to the operator-controlled destination BEFORE invoking `cleanup-tmpdir.sh`. The implementation uses Bash `cp` (the prompt-only constrained tier of the read-only-repo contract — see "Read-only-repo contract" above). Default destination is `./research-findings-batch.md`; an explicit `--keep-sidecar=<PATH>` form sets the destination from the flag.

Path validation (BEFORE the `cp`):

1. The destination must NOT resolve under `$RESEARCH_TMPDIR`. Use `realpath` when available; fall back to a string-prefix check on `cd "$(dirname …)" && pwd` resolution. The `realpath`-based path is the security-stronger tier (defends against symlink/hardlink escapes); the fallback is best-effort. Maintainers MUST NOT remove the `realpath` branch (FINDING_11).
2. The destination's parent directory must exist and be writable.

If validation fails, print `**⚠ 4: cleanup — --keep-sidecar destination rejected: <reason>. Sidecar will be cleaned up with the tmpdir.**` and SKIP the `cp`; do NOT abort.

If the helper at Step 3 produced a zero-byte sidecar (empty findings — exit 3), the operator-surface message changes (FINDING_10):

```bash
if [[ "$KEEP_SIDECAR" == "true" ]]; then
  SIDECAR="$RESEARCH_TMPDIR/research-findings-batch.md"
  DEST="${KEEP_SIDECAR_PATH:-./research-findings-batch.md}"
  # Validate DEST per the rules above; assign DEST_OK=true/false.
  if [[ "$DEST_OK" == "true" ]]; then
    if cp "$SIDECAR" "$DEST"; then
      if [[ -s "$DEST" ]]; then
        echo "**📋 Sidecar preserved at $DEST. Run: /issue --input-file $DEST --label research --dry-run** (then escalate to /issue --go after review)"
      else
        echo "**📋 Sidecar preserved at $DEST, but it is empty (no findings extracted).**"
      fi
    else
      echo "**⚠ 4: cleanup — cp to $DEST failed; sidecar will be cleaned up with the tmpdir.**"
    fi
  fi
fi
```

The advertisement uses `--dry-run` (NOT `--go`) so the operator manually escalates to `--go` after reviewing the sidecar (FINDING_7) — the sidecar may include security-relevant findings from `/research --scale=deep`'s `Codex-Sec` lane.

### Cleanup tmpdir

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$RESEARCH_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier steps (Step 0b binary checks, Step 1 research-phase failures/timeouts, or Step 2 validation failures) so they are visible at the end of the workflow. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`
- `**⚠ Cursor research timed out / produced empty output**`
- `**⚠ Codex research timed out / produced empty output**`

Print: `✅ 4: cleanup — research complete! (<elapsed>)` — when `BUDGET_ABORTED=true`, append the suffix `(aborted: budget exceeded)` so the completion line reads `✅ 4: cleanup — research complete! (<elapsed>) (aborted: budget exceeded)`.
