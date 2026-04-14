---
name: design
description: "Use when designing an implementation plan with collaborative multi-reviewer review. 5 agents propose approaches, then 5 reviewers validate the plan."
argument-hint: "[--auto] [--debug] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch
---

# Design Skill

Design an implementation plan for a feature and review it with multiple specialized reviewers (2 Claude subagents + 2 Codex instances + Cursor).

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--auto`: Set a mental flag `auto_mode=true`. Default: `auto_mode=false`. When `auto_mode=true`, all interactive question checkpoints (Steps 1c, 1d, 3.5, and 3a) are skipped — the skill runs fully autonomously without user interaction. When `--quick` is set in the caller and `/design` is skipped entirely, `--auto` has no effect.
- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) and will be forwarded to `session-setup.sh` via `--caller-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).
- `--step-prefix <prefix>`: Encodes both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for the full encoding spec. Examples: `"1.::design plan"` (numeric `1.`, path `design plan`), `"1."` (numeric only, backward compat). Parse into `STEP_NUM_PREFIX` (before `::`) and `STEP_PATH_PREFIX` (after `::`, or empty if `::` absent). Default: empty (standalone numbering). This is an internal orchestration flag used when `/design` is invoked from `/implement`.
- `--branch-info <values>`: Set `branch_info_supplied=true` and parse `IS_MAIN`, `IS_USER_BRANCH`, `USER_PREFIX`, `CURRENT_BRANCH` from the space-separated `KEY=VALUE` pairs. All 4 keys are required. Values are safe for space-splitting (`USER_PREFIX` is sanitized by `create-branch.sh`'s `derive_user_prefix()`, `CURRENT_BRANCH` cannot contain spaces). **Validation**: If any of the 4 keys is missing, print `**⚠ --branch-info is incomplete. Falling back to create-branch.sh --check.**` and run the script as fallback. **Fallback**: When `--branch-info` is absent (standalone invocation), run `create-branch.sh --check` as usual. This is an internal orchestration flag used when `/design` is invoked from `/implement` to skip the redundant branch-state check.

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
| 3a | confirmation |
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
📊 Reviewers: | General: ✅ 2m31s | Arch: ⏳ | Pragmatic: ✅ 3m5s | Cursor: ❌ 8m3s | Codex: ⏳ |
```

Icons: ✅ done (with elapsed time since launch), ⏳ pending/in-progress, ❌ failed/timeout (with elapsed time since launch), ⊘ skipped (unavailable). This replaces individual per-agent completion messages in non-debug mode. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for elapsed time and step start formatting rules.

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls, per-reviewer individual completion messages.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text and BOTH status table and per-agent details.

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

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

**If `auto_mode=false`**: Before launching the expensive collaborative sketch phase, use `AskUserQuestion` to clarify any ambiguities in the feature description. This is the highest-value question point — answers here reshape what the sketch agents explore.

Consider asking about:
- **Scope boundaries**: What is explicitly in-scope vs. out-of-scope? Are there related changes the user does NOT want?
- **Key decisions**: When there are meaningful alternatives (e.g., different architectural approaches, different file organization), present the options and ask which direction to take.
- **Unclear requirements**: Any aspect of the feature description that is vague, could be interpreted multiple ways, or has implicit assumptions.

**Guidelines**:
- Only ask questions when there is genuine ambiguity — do NOT ask trivially answerable questions or re-confirm what is already clear.
- Batch questions into a single `AskUserQuestion` call with 1-4 questions rather than multiple sequential calls.
- If the feature description is clear and unambiguous, print `✅ 1c: questions — no clarifying questions needed (<elapsed>)` and proceed to Step 1d.

After the user responds, incorporate their answers into your understanding of the feature for all subsequent steps.

## Step 1d — Design Discussion (Round 1)

Print: `> **🔶 1d: discussion r1**`

**If `auto_mode=true`**: Print `⏩ 1d: discussion r1 — skipped (auto mode) (<elapsed>)` and proceed to Step 2a.

**If `auto_mode=false`**: Before launching the expensive collaborative sketch phase, stress-test the feature's scope and requirements by walking through the decision tree one question at a time. This is a deeper, sequential interrogation that resolves dependencies between decisions — each answer may reshape subsequent questions.

### Behavior

The orchestrator identifies key **scope and requirements decisions** from the feature description by exploring the codebase (Read/Grep/Glob). It builds a mental decision tree covering:
- **Scope boundaries**: What is explicitly in-scope vs. out-of-scope?
- **Hard constraints**: What must not break? What existing behavior must be preserved?
- **Non-goals**: What does the user explicitly NOT want?
- **Must-have requirements**: What is the minimum viable outcome?

Then walk each branch one question at a time via sequential `AskUserQuestion` calls, providing a **recommended answer** for each question. If a question can be answered by exploring the codebase, do so and report the finding instead of asking the user.

**Explicit prohibition**: Do NOT ask about implementation approach, architectural preferences, library choices, or file organization. Those decisions belong to the sketch phase (Step 2a). Round 1 is strictly requirements/scope clarification.

### Short-circuit

If the feature is straightforward with fewer than 2 scope decision branches, print `⏩ 1d: discussion r1 — no scope decisions require discussion (<elapsed>)` and proceed to Step 2a.

### Output

Write resolved decisions to `$DESIGN_TMPDIR/discussion-round1.md` using a simple Q&A format:

```markdown
### Decision 1: <short title>
- **Question**: <the question asked>
- **Resolution**: <the answer — from user or codebase>
- **Source**: user / codebase
```

This file captures scope boundaries and hard constraints only — NOT architectural preferences.

### Cap

At most **7 `AskUserQuestion` calls** in this step. If more than 7 decision branches remain after 7 questions, print: `⏩ Remaining scope questions deferred to implementation.` and proceed.

### Terse answers

If the user gives a terse or non-responsive answer (e.g., "I don't know", "your recommendation is fine", "sure"), accept the recommended answer and move on without re-asking.

Print: `✅ 1d: discussion r1 — <N> decisions resolved (<elapsed>)`

## Step 2a — Collaborative Approach Sketches

**IMPORTANT: The collaborative sketch phase MUST ALWAYS run with all 5 sketch agents (using Claude replacements when external tools are unavailable). Never skip or abbreviate this phase regardless of how simple, obvious, or documentation-only the feature appears. The sketch synthesis is required architectural input for the implementation plan — skipping it causes anchoring bias where a single perspective locks in the direction before alternatives are considered.**

A diverge-then-converge phase where 5 agents independently produce short architectural sketches before writing the full plan. This surfaces different perspectives early — when they can still influence architectural direction — rather than waiting for review when the plan is already anchored.

The 5 sketch agents always include these 3 Claude subagents plus Cursor and Codex (or Claude replacements when unavailable):

1. **Claude (General)** — the orchestrating agent's own sketch, covering key decisions, files, and tradeoffs
2. **Claude (Architecture/Standards)** — emphasizes maintainability, engineering standards, separation of concerns, and reuse of existing libraries (including open-source)
3. **Claude (Pragmatism/Safety)** — emphasizes minimizing changes, avoiding regressions, and not breaking existing features

Plus 2 external agents (or Claude replacements):

4. **Cursor** (if available) — or **Claude (Innovation/Exploration)** replacement: proposes creative alternative approaches, questions assumptions, and suggests unconventional solutions
5. **Codex** (if available) — or **Claude (Edge-cases/Failure-modes)** replacement: focuses on what can go wrong, boundary conditions, error handling, and failure recovery

Print `> **🔶 2a: sketches**` and proceed to 2a.2.

### 2a.2 — Launch Sketches in Parallel

**Critical sequencing**: You MUST launch all external sketch Bash tool calls (with `run_in_background: true`) AND all Claude subagent sketches BEFORE producing your own inline sketch. External reviewers take significantly longer than Claude — launching them first maximizes parallelism.

**Spawn order**: Cursor first (slowest), then Codex, then Claude subagents, then your own sketch (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor sketch** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "You are looking at a codebase and need to propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Explore the codebase to understand the relevant architecture, then write 2-3 paragraphs covering: (1) Key architectural decisions and the approach you would take, (2) Which files/modules to modify and why, (3) Main tradeoffs you would consider. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Cursor replacement** (if `cursor_available` is false): Launch a Claude subagent (Innovation/Exploration) via the Agent tool instead:

Prompt: `"You are an Innovation/Exploration architect. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to question assumptions, suggest creative alternatives, and propose unconventional solutions that others might not consider. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize any novel approaches or alternatives to the obvious path, (2) Which files/modules to modify and why, (3) Main tradeoffs including any 'crazy but might work' ideas worth considering. Do NOT modify files."`

**Codex sketch** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-output.txt" \
    "You are looking at a codebase and need to propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Explore the codebase to understand the relevant architecture, then write 2-3 paragraphs covering: (1) Key architectural decisions and the approach you would take, (2) Which files/modules to modify and why, (3) Main tradeoffs you would consider. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1260000` on the Bash tool call.

**Codex replacement** (if `codex_available` is false): Launch a Claude subagent (Edge-cases/Failure-modes) via the Agent tool instead:

Prompt: `"You are an Edge-case/Failure-mode analyst. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to focus on what can go wrong: boundary conditions, error handling, failure recovery, race conditions, and silent data corruption. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize defensive design and failure handling, (2) Which files/modules to modify and why — call out any fragile areas, (3) Main risks and failure modes, with mitigations for each. Do NOT modify files."`

**Claude subagent (Architecture/Standards)**: Launch via the Agent tool:

Prompt: `"You are an Architecture/Standards architect. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to emphasize maintainability, engineering standards, separation of concerns, and reuse of existing libraries (including open-source). Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize clean design, proper layering, and whether existing libraries or patterns can be reused, (2) Which files/modules to modify and why — flag any violations of single-responsibility or layer boundaries, (3) Main tradeoffs around long-term maintainability vs. short-term convenience. Do NOT modify files."`

**Claude subagent (Pragmatism/Safety)**: Launch via the Agent tool:

Prompt: `"You are a Pragmatism/Safety engineer. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to minimize the scope of changes, avoid unnecessary complexity, and ensure existing features are not broken. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize the smallest possible change set that achieves the goal, (2) Which files/modules to modify and why — flag any changes that touch high-risk or widely-used code paths, (3) Main risks to existing functionality and how to mitigate regressions. Do NOT modify files."`

**Claude sketch (General)**: Only after all external and subagent launches are issued, produce your own 2-3 paragraph sketch inline covering the same three areas: (1) key architectural decisions, (2) files/modules to modify, (3) main tradeoffs. Print it under a `### Claude Sketch` header. Write this **before** reading any external or subagent outputs to preserve independence.

### 2a.3 — Wait and Validate Sketches

Collect and validate external sketch outputs using the shared collection script. Only include output paths for external reviewers that were actually launched (not Claude replacements — those return via Agent tool):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1260 "$DESIGN_TMPDIR/cursor-sketch-output.txt" "$DESIGN_TMPDIR/codex-sketch-output.txt"
```

Use `timeout: 1260000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Only include output paths for external reviewers that were actually launched — omit any path whose reviewer was replaced by a Claude subagent.

Note: This is a separate `collect-reviewer-results.sh` call from the one in Step 3. Both are permitted because they operate on completely distinct output file sets (`*-sketch-output.txt` vs `*-plan-output.txt`).

Parse the structured output for each reviewer's `STATUS`, `REVIEWER_FILE`, and `HEALTHY`. For sketches, a valid output is non-empty and contains substantive architectural content (at least a paragraph). If a reviewer's `STATUS` is not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md` (set `*_available=false` for all subsequent steps).

### 2a.4 — Synthesis

Read all 5 sketches (Claude General + Architecture/Standards + Pragmatism/Safety + Cursor or replacement + Codex or replacement). Produce a synthesis that:

1. Identifies where the approaches **agree** (likely the majority)
2. Identifies where they **diverge** and makes a reasoned call on each contested point with justification
3. Notes which ideas from each sketch are being incorporated into the full plan
4. Highlights any **Architecture/Standards** concerns that should be addressed in the plan
5. Highlights any **Pragmatism/Safety** warnings about regression risk or unnecessary complexity
6. Lists contested decisions as a structured markdown list in `$DESIGN_TMPDIR/contested-decisions.md`. Use this schema:

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

Otherwise, read `$DESIGN_TMPDIR/approach-synthesis.txt` — this provides `{SYNTHESIS_TEXT}` for the agent prompts below. Select up to the first 3 decisions from the file (they are already in priority order from Step 2a.4). For each selected decision, launch a **thesis agent** and an **antithesis agent** as Claude subagents via the Agent tool. **All thesis+antithesis pairs across all decisions must be issued in a single Agent fan-out message** (up to 6 Agent tool calls in one message) to maximize parallelism.

**Thesis agent prompt template**:
```
You are defending this architectural decision for the feature: {FEATURE_DESCRIPTION}.

The synthesis of 5 independent sketches chose {CHOSEN} over {ALTERNATIVE} because: {TENSION}.

Your role: argue why {CHOSEN} is the right call given the codebase, requirements, and constraints. Reference specific evidence from the synthesis and the codebase (via Read/Grep/Glob tools, focusing on: {AFFECTED_FILES}). Write 1-2 focused paragraphs.

## Synthesis
{SYNTHESIS_TEXT}

## Contested Decision
{DECISION_BLOCK}
```

**Antithesis agent prompt template**:
```
You are challenging this architectural decision for the feature: {FEATURE_DESCRIPTION}.

The synthesis of 5 independent sketches chose {CHOSEN} over {ALTERNATIVE}.

Your role: argue why {ALTERNATIVE} would be better, surface risks in {CHOSEN}, poke at hidden assumptions, and present the most compelling case for switching. In particular, challenge whether the chosen approach is justified by concrete current requirements or is speculative, and whether a simpler alternative would achieve the same goal with less complexity. These proportionality questions should be your primary weapon for making the case for {ALTERNATIVE}. Reference specific evidence from the synthesis and the codebase (via Read/Grep/Glob tools, focusing on: {AFFECTED_FILES}). Write 1-2 focused paragraphs.

## Synthesis
{SYNTHESIS_TEXT}

## Contested Decision
{DECISION_BLOCK}
```

**After all agents return**, apply the **debate quorum rule** for each decision:
- If **both** thesis and antithesis produced substantive output (non-empty, at least one paragraph each), the orchestrator writes a **binding resolution** for that decision.
- If **either side** failed, returned empty output, or produced malformed/non-substantive content, print `**⚠ Debate for DECISION_N failed (missing <thesis/antithesis> output). Falling back to synthesis decision.**` and do NOT write a binding resolution for that decision. The Step 2a.4 synthesis call stands for that point.

Write all successful resolutions to `$DESIGN_TMPDIR/dialectic-resolutions.md` using this format:

```markdown
### DECISION_1: <title>
**Resolution**: <the final binding decision — must be one of the two options: either the chosen or the alternative>
**Thesis summary**: <1-2 sentence summary of the thesis agent's key argument>
**Antithesis summary**: <1-2 sentence summary of the antithesis agent's key argument>
**Why thesis prevails** / **Why antithesis prevails**: <explicit justification that directly addresses the losing side's strongest argument — must not dismiss the counterargument without engaging it>
```

Print resolutions under a `## Dialectic Resolutions` header.

**Scope**: Dialectic resolutions are **binding for Step 2b plan generation only**. They may be superseded later by accepted Step 3 review findings. The finalized plan (after Step 3 review) remains the sole canonical output.

Print: `✅ 2a.5: dialectic — <N> decisions resolved (<elapsed>)` (where N is the count of decisions that passed the quorum rule).

## Step 2b — Design the Implementation Plan

Before writing any code, create a concrete implementation plan. Research the codebase (read relevant files, grep for patterns, understand existing architecture). See CLAUDE.md for project-specific development references and conventions.

Read `$DESIGN_TMPDIR/approach-synthesis.txt` from Step 2a and incorporate the synthesis into the plan. The synthesis should inform architectural decisions, file selection, and tradeoff resolutions.

Also read `$DESIGN_TMPDIR/discussion-round1.md` if it exists and is non-empty. Incorporate the scope boundaries and hard constraints established during the design discussion into the plan — these define what is in-scope, what must not break, and what the user explicitly does not want.

Also read `$DESIGN_TMPDIR/dialectic-resolutions.md` if it exists and is non-empty. For each resolved decision, the plan **must** follow the resolution direction and explicitly note how the antithesis concern was addressed. These resolutions are binding for Step 2b — do not override them. (Note: Step 3 plan review may subsequently revise the plan based on accepted review findings, which supersede dialectic resolutions.)

Produce a plan that includes:

- **Files to modify/create**: List each file with a brief description of what changes.
- **Approach**: Describe the implementation strategy, key decisions, and any trade-offs.
- **Edge cases**: Note important input/boundary conditions and how they'll be handled.
- **Failure modes** (for non-trivial changes): The 3 most likely architectural/systemic failure paths, earliest warning signals, and simplest mitigations. May be omitted for purely cosmetic or documentation-only changes.
- **Testing strategy**: What tests will be added or modified.

Print the plan to the user under a `## Implementation Plan` header so reviewers can see it.

## Step 3 — Plan Review

**IMPORTANT: Plan review MUST ALWAYS run with all available reviewers (2 Claude subagents + 2 Codex instances and Cursor if available). Never skip or abbreviate this step regardless of how straightforward the plan appears — even when all sketch agents agreed, the plan is short, or the change seems trivial. Reviewers validate against the actual codebase state, catching issues that sketch-phase reasoning alone cannot detect.**

Launch **all 5 reviewers in parallel** (in a single message). When external tools are unavailable, launch Claude replacement subagents instead so the total reviewer count always remains 5. **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then both Codex instances, then Claude subagents (fastest). Each reviewer receives the plan text and the feature description. Each must **only report findings** — never edit files.

### External Reviewer Setup (if `codex_available` or `cursor_available`)

Before launching external reviewers, write the implementation plan to `$DESIGN_TMPDIR/plan.txt` so both Codex instances and Cursor can read it.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the codebase itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-plan-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Combine 4 perspectives: (1) General: logical flaws, code reuse, test coverage, backward compat, pattern consistency. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor replacement** (if `cursor_available` is false): Launch a Claude subagent (Risk/Integration) via the Agent tool instead. This replacement ensures the total reviewer count remains 5 regardless of external tool availability.

Prompt: `"You are a Risk/Integration plan reviewer. Review the implementation plan provided below for this project. Explore the codebase via Read/Grep/Glob tools to validate the plan against the actual codebase state. Combine 4 perspectives: (1) General: logical flaws, code reuse, test coverage, backward compat, pattern consistency. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with concern and suggested revision) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT modify files. <include {CONTEXT_BLOCK} and competition notice>"`

### Codex Reviewers (if `codex_available`) — 2 instances

Run both Codex instances **second** in the parallel message (after Cursor). Each Codex instance has full repo access and will examine the codebase itself, but focuses on different perspectives.

**Codex-General** — focuses on general code quality and risk/integration perspectives:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-general-plan-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$DESIGN_TMPDIR/codex-general-plan-output.txt" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Focus on general code quality and risk/integration perspectives: (1) General: logical flaws, code reuse, test coverage, backward compat, pattern consistency. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex-Deep-Analysis** — focuses on correctness and architecture perspectives:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-deep-plan-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$DESIGN_TMPDIR/codex-deep-plan-output.txt" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Focus on correctness and architecture perspectives: (1) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (2) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex replacements** (if `codex_available` is false): Launch 2 Claude subagents to replace the 2 Codex instances. These replacements ensure the total reviewer count remains 5 regardless of external tool availability.

**Claude (Codex-General replacement)**: Launch via Agent tool with prompt: `"You are a code quality and risk/integration plan reviewer. Review the implementation plan provided below for this project. Explore the codebase via Read/Grep/Glob tools. Focus on general code quality and risk/integration: logical flaws, code reuse, test coverage, backward compat, pattern consistency, breaking changes, side effects, deployment risks, regressions, CI. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with concern and suggested revision) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT modify files. <include {CONTEXT_BLOCK} and competition notice>"`

**Claude (Codex-Deep-Analysis replacement)**: Launch via Agent tool with prompt: `"You are a deep correctness and architecture plan reviewer. Review the implementation plan provided below for this project. Explore the codebase via Read/Grep/Glob tools. Focus on correctness and architecture: logic errors, off-by-one, nil handling, type mismatches, races, error paths, separation of concerns, contract boundaries, invariants, semantic boundaries. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with concern and suggested revision) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT modify files. <include {CONTEXT_BLOCK} and competition notice>"`

### Claude Subagents (2 reviewers)

Launch both Claude subagents **last** in the same message (they finish fastest).

Use the two reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md`, filling in the variables for **plan review**:

- **`{REVIEW_TARGET}`** = `"an implementation plan"`
- **`{CONTEXT_BLOCK}`**:
  ```
  ## Feature to implement
  {FEATURE_DESCRIPTION}

  ## Proposed implementation plan
  {PLAN}
  ```
- **`{OUTPUT_INSTRUCTION}`** = `"What the concern is"` + `"Suggested revision to the plan"`

Additionally, append the following competition context to each reviewer's prompt (both Claude subagents and external reviewers):

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Deep Analysis Reviewer, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Concerns that are valid but not actionable in this PR may still be exonerated rather than penalized. Out-of-scope observations use the same scoring as in-scope findings: OOS items that receive 2+ YES votes earn +1 point and will be filed as GitHub issues. OOS items with 0 YES and 0 EXONERATE cost -1 point. OOS items with exactly 1 YES or with 1+ EXONERATE earn 0 points.

### Collecting External Reviewer Results

**Process Claude findings immediately** — do not wait for external reviewers before starting:

1. Collect findings from the two Claude subagents right away. Claude subagents produce **dual-list output** (per `reviewer-templates.md`): "In-Scope Findings" and "Out-of-Scope Observations". Parse both lists from each subagent.
2. **Then** collect and validate external reviewer outputs using the shared collection script. Only include output paths for reviewers that were actually launched:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 [--write-health "${SESSION_ENV_PATH}.health"] "$DESIGN_TMPDIR/cursor-plan-output.txt" "$DESIGN_TMPDIR/codex-general-plan-output.txt" "$DESIGN_TMPDIR/codex-deep-plan-output.txt"
   ```
   Only include `--write-health` if `SESSION_ENV_PATH` is non-empty. Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`. Read valid output files. External reviewers (Codex, Cursor) produce single-list output — treat their entire output as in-scope findings.
3. Merge external reviewer in-scope findings into the Claude in-scope findings.
4. Deduplicate in-scope findings separately. Assign each a stable sequential ID (`FINDING_1`, `FINDING_2`, etc.) and note which reviewer(s) proposed each.
5. Deduplicate out-of-scope observations separately. Assign each an `OOS_` prefixed ID (`OOS_1`, `OOS_2`, etc.). If the same issue appears in both in-scope and OOS from different reviewers, merge under the in-scope finding (in-scope takes precedence).

If **all reviewers** report no in-scope issues and no out-of-scope observations, skip voting and proceed to Step 3.5 (Design Discussion Round 2) if `auto_mode=false`, or Step 3a (Post-Review Confirmation) if `auto_mode=true`.

### Voting Panel (replaces negotiation)

After deduplication, submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section — voters decide whether each OOS item deserves a GitHub issue (YES = file issue, not implement). For plan review:

- **Voter 1**: Claude Deep Analysis reviewer subagent — fresh Agent tool invocation with the voting prompt. Instruct: `"You are a senior architect and correctness specialist on a voting panel. You will vote YES, NO, or EXONERATE on proposed modifications to an implementation plan. Be scrupulous — only vote YES for findings that are correct, important, and worth revising the plan for. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot. If `codex_available` is false, launch a Claude subagent voter instead per the Voting Protocol.
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot. If `cursor_available` is false, launch a Claude subagent voter instead per the Voting Protocol.

For Codex, Cursor, and their Claude replacement voters, instruct each: `"You are a senior engineer on a voting panel deciding which proposed plan modifications should be accepted. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$DESIGN_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $DESIGN_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

Launch all available voters **in parallel** (Cursor first, then Codex, then Claude subagent). Wait for external voter sentinels using `wait-for-reviewers.sh` per the Voting Protocol, then parse voter outputs.

**Tally votes**: Apply the threshold rules from the Voting Protocol based on eligible voters per finding (2+ YES with 3 voters, unanimous 2/2 with 2 voters, skip if <2 eligible). Print the vote breakdown per finding.

**Competition scoring**: Compute and print the **Reviewer Competition Scoreboard** per the Voting Protocol's scoring rules (+1 for accepted, 0 for neutral/exonerated, -1 for rejected — see `voting-protocol.md` for the full outcome matrix). Print the scoreboard table.

### Finalize Plan Review

If any in-scope findings were **accepted by vote** (2+ YES votes):
1. Print them under a `## Plan Review Findings (Voted In)` header with vote counts.
2. Revise the implementation plan to address each accepted in-scope finding.
3. Print the revised plan under a `## Revised Implementation Plan` header.
4. Write the accepted in-scope findings to `$DESIGN_TMPDIR/accepted-plan-findings.md` so Step 3.5 (Design Discussion Round 2) has a stable artifact to read. **Only include in-scope `FINDING_*` items — do not include OOS items.** Use the format:
   ```markdown
   ### FINDING_N: <title>
   - **Concern**: <what was raised>
   - **Resolution**: <how the plan was revised>
   ```

**OOS items accepted by vote** (2+ YES): These are accepted for GitHub issue filing, NOT for plan revision. **Only when `SESSION_ENV_PATH` is non-empty**: write accepted OOS items to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-design.md` using the format:
```markdown
### OOS_N: <short title>
- **Description**: <full description of the observation>
- **Reviewer**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE counts>
- **Phase**: design
```
When `SESSION_ENV_PATH` is empty (standalone invocation), skip the OOS artifact write — there is no parent `/implement` to consume it.

Print any non-accepted OOS items under a `## Out-of-Scope Observations` header for visibility. These are not filed as issues but are recorded for future attention.

If voting rejects all in-scope findings, print: `**ℹ Voting panel rejected all in-scope findings. Plan unchanged.**` (OOS items accepted for issue filing are processed separately by `/implement`.) Proceed to Step 3.5 (Design Discussion Round 2) if `auto_mode=false`, or Step 3a (Post-Review Confirmation) if `auto_mode=true`.

### Track Rejected Plan Review Findings

For any **in-scope** findings that were **not accepted by vote** (fewer than 2 YES votes — whether rejected or exonerated) during plan review (from any reviewer — Claude subagents, Codex, or Cursor), append each to `$DESIGN_TMPDIR/rejected-findings.md` using this format. **Do not include OOS items** — those follow a separate pipeline (accepted OOS → GitHub issues via `/implement`, non-accepted OOS → PR body observations):

```markdown
### [Plan Review] <Reviewer Name>
**Finding**: <thorough description of the finding — include what aspect of the plan the reviewer questioned, the specific concern raised, and what revision they suggested. Must be detailed enough to serve as an actionable TODO item if later prioritized. Do NOT use a terse one-liner — a reader who has never seen the original review must be able to understand the concern and act on it.>
**Reason not implemented**: <complete justification for why this finding was not accepted — include the specific technical reasoning, any relevant context about project conventions or design decisions, and why the current plan is acceptable despite the finding. Do NOT abbreviate — preserve all important details from the evaluation.>
```

If no findings were rejected, do not create the file yet.

## Step 3.5 — Design Discussion (Round 2)

Print: `> **🔶 3.5: discussion r2**`

**If `auto_mode=true`**: Print `⏩ 3.5: discussion r2 — skipped (auto mode) (<elapsed>)` and proceed to Step 3a.

**If `auto_mode=false`**: After the plan has been reviewed and revised, stress-test the remaining design decisions that were either (a) not covered in Round 1, or (b) deemed suboptimal by reviewers, or (c) introduced by the plan itself (decisions that didn't exist at the feature-description stage).

### Inputs

Read the following artifacts:
- `$DESIGN_TMPDIR/discussion-round1.md` — If it exists and is non-empty, use it to identify decisions already covered in Round 1 (avoid re-asking). **If it does not exist or is empty** (Round 1 short-circuited or was skipped), treat all candidate decisions as uncovered by Round 1 and proceed normally.
- `$DESIGN_TMPDIR/accepted-plan-findings.md` — If it exists and is non-empty, use it to identify decisions that reviewers challenged as suboptimal or that required plan revision.
- `$DESIGN_TMPDIR/contested-decisions.md` — Decisions that sketch agents disagreed on.
- `$DESIGN_TMPDIR/dialectic-resolutions.md` — How contested decisions were resolved.

Also reference the revised (or original) implementation plan from Step 3's output visible in conversation context above.

### Behavior

Identify decisions in the implementation plan that meet any of these criteria:
1. **Not covered in Round 1** — decisions that emerged from the plan design, not from the original feature description.
2. **Challenged by reviewers** — decisions that appear in `accepted-plan-findings.md` (reviewers found them suboptimal and the plan was revised).
3. **Still contested** — decisions from `contested-decisions.md` where the dialectic resolution was close or the antithesis had strong arguments.

Walk each uncovered branch one question at a time via sequential `AskUserQuestion` calls, providing a **recommended answer** for each question. If a question can be answered by exploring the codebase, do so and report the finding instead of asking the user.

Unlike Round 1, Round 2 MAY ask about architectural decisions and implementation approach — the sketch phase has already provided divergent perspectives, so anchoring is no longer a concern at this stage.

### Short-circuit

If all plan decisions are already covered by Round 1, no reviewer findings challenged them, and no decisions from `contested-decisions.md` have a close or inconclusive dialectic resolution, print `⏩ 3.5: discussion r2 — no additional decisions require discussion (<elapsed>)` and proceed to Step 3a.

### Output

Write resolved decisions to `$DESIGN_TMPDIR/discussion-round2.md` using the same format as Round 1:

```markdown
### Decision 1: <short title>
- **Question**: <the question asked>
- **Resolution**: <the answer — from user or codebase>
- **Source**: user / codebase
```

**Auto-revise**: Update the implementation plan in-place based on answers. Print the revised plan only if substantive changes were made.

### Cap

At most **7 `AskUserQuestion` calls** in this step. If more than 7 decision branches remain, print: `⏩ Remaining design questions deferred to implementation.` and proceed.

### Terse answers

If the user gives a terse or non-responsive answer, accept the recommended answer and move on without re-asking.

Print: `✅ 3.5: discussion r2 — <N> decisions resolved (<elapsed>)`

## Step 3a — Post-Review Confirmation

Print: `> **🔶 3a: confirmation**`

**If `auto_mode=true`**: Print `⏩ 3a: confirmation — skipped (auto mode) (<elapsed>)` and proceed to Step 3b.

**If the plan was NOT revised** (voting rejected all findings or was skipped, AND Step 3.5 discussion made no changes): Print `⏩ 3a: confirmation — skipped (plan unchanged) (<elapsed>)` and proceed to Step 3b.

**If `auto_mode=false` AND the plan was revised** (by reviewers or Step 3.5 discussion): Use `AskUserQuestion` to confirm the revised plan addresses the user's original intent. Present a brief summary of what changed and ask the user to approve or reject.

**This step is strictly approval-only** — the user confirms the revised plan is acceptable to proceed with implementation. No substantive plan changes are accepted at this point — the reviewed/voted plan is the canonical artifact. If the user rejects the plan, print a warning and proceed anyway (the plan has already been reviewed and voted on; the user can adjust during implementation or in a follow-up PR).

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
