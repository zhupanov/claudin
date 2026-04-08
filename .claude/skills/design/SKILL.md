---
name: design
description: Design an implementation plan with collaborative multi-reviewer review. 5 agents independently propose approaches before the full plan, then 5 reviewers validate the plan.
argument-hint: "[--auto] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch
---

# Design Skill

Design an implementation plan for a feature and review it with multiple specialized reviewers (2 Claude subagents + 2 Codex instances + Cursor).

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token.

- `--auto`: Set a mental flag `auto_mode=true`. When `auto_mode=true`, all interactive question checkpoints (Steps 1c and 3a) are skipped — the skill runs fully autonomously without user interaction. When `--quick` is set in the caller and `/design` is skipped entirely, `--auto` has no effect.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) and will be forwarded to `session-setup.sh` via `--caller-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).

The feature to design is described by the remainder of `$ARGUMENTS` after flags are stripped.

## Progress Reporting

**Every step MUST print clearly visible status lines** so the user can instantly see where execution is at. Use distinct emoji prefixes:

- Print a **start line** when entering a step: e.g., `🔀 Step 1 — Creating branch...`
- Print a **completion line** when done: e.g., `✅ Step 1 — Branch created: <user-prefix>/foo-bar`

Suggested emoji palette (use consistently):
| Step | Emoji | Description |
|------|-------|-------------|
| 0 | 🔧 | Session setup |
| 1 | 🔀 | Branch creation |
| 1c | ❓ | Clarifying questions |
| 2a | 🤝 | Collaborative sketches |
| 2b | 📐 | Full plan design |
| 3 | 🔍 | Plan review |
| 3a | ✅ | Post-review confirmation |
| 3b | 🗺️ | Architecture diagram |
| 4 | 📊 | Rejected findings report |
| 5 | 🏁 | Cleanup |

## Step 0 — Session Setup

### 0a — Preflight and Temp Directory

Run the shared session setup script. Since `/design` does not need Slack or repo checks, pass `--skip-slack-check` and `--skip-repo-check`. If `SESSION_ENV_PATH` is non-empty (passed via `--session-env`), include `--caller-env`:

```bash
$PWD/.claude/scripts/generic/larch/session-setup.sh --prefix claude-design --skip-branch-check --skip-slack-check --skip-repo-check [--caller-env "$SESSION_ENV_PATH"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` if `SESSION_ENV_PATH` is non-empty. This is behavior-preserving: `/design` today has no Slack or repo steps, and the skip flags ensure the script skips them.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`. Set `DESIGN_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

### 0b — Quick External Reviewer Check

Read and follow the **Binary Check** section in `.claude/skills/shared/larch/external-reviewers.md`.

## Step 1 — Create Branch

### 1a — Check current branch state

Run the `create-branch.sh` script in check mode to get the current branch state:

```bash
$PWD/.claude/scripts/generic/larch/create-branch.sh --check
```

Parse the output for `CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, and `USER_PREFIX`.

### 1b — Decide action

**Decision logic** (using the script output):
- If `IS_MAIN=true`: Derive a short kebab-case branch name from the feature description (e.g., "add user auth" → `<USER_PREFIX>/add-user-auth`). Keep it under 50 characters. Then create it:
  ```bash
  $PWD/.claude/scripts/generic/larch/create-branch.sh --branch <USER_PREFIX>/<branch-name>
  ```

- If `IS_USER_BRANCH=true`: Verify the branch name (`CURRENT_BRANCH`) aligns with the requested feature. If it appears unrelated (different feature name, unrelated commits), print a warning: `**⚠ Current branch '<branch-name>' may not match the requested feature. Creating a new branch from main.**` and create a new branch as above. Otherwise, skip branch creation. Print: `🔀 Step 1 — Using existing branch: <branch-name>`

- Otherwise (non-main, non-user branch): Print a warning: `**⚠ Currently on branch '<branch-name>' which doesn't match the expected '<USER_PREFIX>/*' pattern. Creating a new branch from main.**` Then derive a name and create as above.

## Step 1c — Clarifying Questions

Print: `❓ Step 1c — Clarifying questions...`

**If `auto_mode=true`**: Print `⏩ Step 1c — Skipped (auto mode).` and proceed to Step 2a.

**If `auto_mode=false`**: Before launching the expensive collaborative sketch phase, use `AskUserQuestion` to clarify any ambiguities in the feature description. This is the highest-value question point — answers here reshape what the sketch agents explore.

Consider asking about:
- **Scope boundaries**: What is explicitly in-scope vs. out-of-scope? Are there related changes the user does NOT want?
- **Key decisions**: When there are meaningful alternatives (e.g., different architectural approaches, different file organization), present the options and ask which direction to take.
- **Unclear requirements**: Any aspect of the feature description that is vague, could be interpreted multiple ways, or has implicit assumptions.

**Guidelines**:
- Only ask questions when there is genuine ambiguity — do NOT ask trivially answerable questions or re-confirm what is already clear.
- Batch questions into a single `AskUserQuestion` call with 1-4 questions rather than multiple sequential calls.
- If the feature description is clear and unambiguous, print `✅ Step 1c — No clarifying questions needed.` and proceed to Step 2a.

After the user responds, incorporate their answers into your understanding of the feature for all subsequent steps.

Print: `✅ Step 1c — Questions resolved.`

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

Print `🤝 Step 2a — Running collaborative sketch phase.` and proceed to 2a.2.

### 2a.2 — Launch Sketches in Parallel

**Critical sequencing**: You MUST launch all external sketch Bash tool calls (with `run_in_background: true`) AND all Claude subagent sketches BEFORE producing your own inline sketch. External reviewers take significantly longer than Claude — launching them first maximizes parallelism.

**Spawn order**: Cursor first (slowest), then Codex, then Claude subagents, then your own sketch (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor sketch** (if `cursor_available`):

```bash
$PWD/.claude/scripts/generic/larch/run-external-reviewer.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-sketch-output.txt" --timeout 600 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "You are looking at a codebase and need to propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Explore the codebase to understand the relevant architecture, then write 2-3 paragraphs covering: (1) Key architectural decisions and the approach you would take, (2) Which files/modules to modify and why, (3) Main tradeoffs you would consider. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 660000` on the Bash tool call.

**Cursor replacement** (if `cursor_available` is false): Launch a Claude subagent (Innovation/Exploration) via the Agent tool instead:

Prompt: `"You are an Innovation/Exploration architect. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to question assumptions, suggest creative alternatives, and propose unconventional solutions that others might not consider. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize any novel approaches or alternatives to the obvious path, (2) Which files/modules to modify and why, (3) Main tradeoffs including any 'crazy but might work' ideas worth considering. Do NOT modify files."`

**Codex sketch** (if `codex_available`):

```bash
$PWD/.claude/scripts/generic/larch/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-sketch-output.txt" --timeout 600 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$DESIGN_TMPDIR/codex-sketch-output.txt" \
    "You are looking at a codebase and need to propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Explore the codebase to understand the relevant architecture, then write 2-3 paragraphs covering: (1) Key architectural decisions and the approach you would take, (2) Which files/modules to modify and why, (3) Main tradeoffs you would consider. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 660000` on the Bash tool call.

**Codex replacement** (if `codex_available` is false): Launch a Claude subagent (Edge-cases/Failure-modes) via the Agent tool instead:

Prompt: `"You are an Edge-case/Failure-mode analyst. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to focus on what can go wrong: boundary conditions, error handling, failure recovery, race conditions, and silent data corruption. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize defensive design and failure handling, (2) Which files/modules to modify and why — call out any fragile areas, (3) Main risks and failure modes, with mitigations for each. Do NOT modify files."`

**Claude subagent (Architecture/Standards)**: Launch via the Agent tool:

Prompt: `"You are an Architecture/Standards architect. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to emphasize maintainability, engineering standards, separation of concerns, and reuse of existing libraries (including open-source). Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize clean design, proper layering, and whether existing libraries or patterns can be reused, (2) Which files/modules to modify and why — flag any violations of single-responsibility or layer boundaries, (3) Main tradeoffs around long-term maintainability vs. short-term convenience. Do NOT modify files."`

**Claude subagent (Pragmatism/Safety)**: Launch via the Agent tool:

Prompt: `"You are a Pragmatism/Safety engineer. Propose a high-level implementation approach for this feature: <FEATURE_DESCRIPTION>. Your role is to minimize the scope of changes, avoid unnecessary complexity, and ensure existing features are not broken. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Key architectural decisions — emphasize the smallest possible change set that achieves the goal, (2) Which files/modules to modify and why — flag any changes that touch high-risk or widely-used code paths, (3) Main risks to existing functionality and how to mitigate regressions. Do NOT modify files."`

**Claude sketch (General)**: Only after all external and subagent launches are issued, produce your own 2-3 paragraph sketch inline covering the same three areas: (1) key architectural decisions, (2) files/modules to modify, (3) main tradeoffs. Print it under a `### Claude Sketch` header. Write this **before** reading any external or subagent outputs to preserve independence.

### 2a.3 — Wait and Validate Sketches

Wait for external sketch sentinels using `wait-for-reviewers.sh`. Only include paths for external reviewers that were actually launched (not Claude replacements — those return via Agent tool):

```bash
$PWD/.claude/scripts/generic/larch/wait-for-reviewers.sh --timeout 660 "$DESIGN_TMPDIR/cursor-sketch-output.txt.done" "$DESIGN_TMPDIR/codex-sketch-output.txt.done"
```

Use `timeout: 660000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Only include sentinel paths for external reviewers that were actually launched — omit any path whose reviewer was replaced by a Claude subagent.

Note: This is a separate `wait-for-reviewers.sh` call from the one in Step 3. Both are permitted because they operate on completely distinct sentinel file sets (`*-sketch-output.txt.done` vs `*-plan-output.txt.done`).

**Validate sketch outputs**: Follow the **Validating External Reviewer Output** section in `.claude/skills/shared/larch/external-reviewers.md`, using `$DESIGN_TMPDIR/cursor-sketch-output.txt` and `$DESIGN_TMPDIR/codex-sketch-output.txt` as the output files. For sketches, a valid output is non-empty and contains substantive architectural content (at least a paragraph). If a sketch is empty despite exit code 0, retry once with a `-retry` suffix per the shared procedure.

### 2a.4 — Synthesis

Read all 5 sketches (Claude General + Architecture/Standards + Pragmatism/Safety + Cursor or replacement + Codex or replacement). Produce a synthesis that:

1. Identifies where the approaches **agree** (likely the majority)
2. Identifies where they **diverge** and makes a reasoned call on each contested point with justification
3. Notes which ideas from each sketch are being incorporated into the full plan
4. Highlights any **Architecture/Standards** concerns that should be addressed in the plan
5. Highlights any **Pragmatism/Safety** warnings about regression risk or unnecessary complexity

Print the synthesis under an `## Approach Synthesis` header. Write the synthesis to `$DESIGN_TMPDIR/approach-synthesis.txt` so it can be referenced by Step 2b.

Print: `✅ Step 2a — Sketch synthesis complete (5 agents).`

## Step 2b — Design the Implementation Plan

Before writing any code, create a concrete implementation plan. Research the codebase (read relevant files, grep for patterns, understand existing architecture). See CLAUDE.md for project-specific development references and conventions.

Read `$DESIGN_TMPDIR/approach-synthesis.txt` from Step 2a and incorporate the synthesis into the plan. The synthesis should inform architectural decisions, file selection, and tradeoff resolutions.

Produce a plan that includes:

- **Files to modify/create**: List each file with a brief description of what changes.
- **Approach**: Describe the implementation strategy, key decisions, and any trade-offs.
- **Edge cases**: Note important input/boundary conditions and how they'll be handled.
- **Failure modes** (for non-trivial changes): The 3 most likely architectural/systemic failure paths, earliest warning signals, and simplest mitigations. May be omitted for purely cosmetic or documentation-only changes.
- **Testing strategy**: What tests will be added or modified.

Print the plan to the user under a `## Implementation Plan` header so reviewers can see it.

## Step 3 — Plan Review

**IMPORTANT: Plan review MUST ALWAYS run with all available reviewers (2 Claude subagents + 2 Codex instances and Cursor if available). Never skip or abbreviate this step regardless of how straightforward the plan appears — even when all sketch agents agreed, the plan is short, or the change seems trivial. Reviewers validate against the actual codebase state, catching issues that sketch-phase reasoning alone cannot detect.**

Launch **all reviewers in parallel** (in a single message). **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then both Codex instances, then Claude subagents (fastest). Each reviewer receives the plan text and the feature description. Each must **only report findings** — never edit files.

### External Reviewer Setup (if `codex_available` or `cursor_available`)

Before launching external reviewers, write the implementation plan to `$DESIGN_TMPDIR/plan.txt` so both Codex instances and Cursor can read it.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the codebase itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
$PWD/.claude/scripts/generic/larch/run-external-reviewer.sh --tool cursor --output "$DESIGN_TMPDIR/cursor-plan-output.txt" --timeout 900 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Combine 4 perspectives: (1) General: logical flaws, code reuse, test coverage, backward compat, pattern consistency. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Codex Reviewers (if `codex_available`) — 2 instances

Run both Codex instances **second** in the parallel message (after Cursor). Each Codex instance has full repo access and will examine the codebase itself, but focuses on different perspectives.

**Codex-General** — focuses on general code quality and risk/integration perspectives:

```bash
$PWD/.claude/scripts/generic/larch/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-general-plan-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$DESIGN_TMPDIR/codex-general-plan-output.txt" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Focus on general code quality and risk/integration perspectives: (1) General: logical flaws, code reuse, test coverage, backward compat, pattern consistency. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Codex-Deep-Analysis** — focuses on correctness and architecture perspectives:

```bash
$PWD/.claude/scripts/generic/larch/run-external-reviewer.sh --tool codex --output "$DESIGN_TMPDIR/codex-deep-plan-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$DESIGN_TMPDIR/codex-deep-plan-output.txt" \
    "Review the implementation plan in $DESIGN_TMPDIR/plan.txt for this project. Read the plan file, then explore the codebase to validate the plan. Focus on correctness and architecture perspectives: (1) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (2) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, concern, and suggested revision. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Claude Subagents (2 reviewers)

Launch both Claude subagents **last** in the same message (they finish fastest).

Use the two reviewer archetypes from `.claude/skills/shared/larch/reviewer-templates.md`, filling in the variables for **plan review**:

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

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Deep Analysis Reviewer, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Concerns that are valid but not actionable in this PR may still be exonerated rather than penalized. Out-of-scope observations (pre-existing issues, items beyond PR scope) can never cost you points — surface them freely.

### Monitoring External Reviewers

Follow the **Monitoring External Reviewers** and **Validating External Reviewer Output** sections in `.claude/skills/shared/larch/external-reviewers.md`, using `$DESIGN_TMPDIR/codex-general-plan-output.txt`, `$DESIGN_TMPDIR/codex-deep-plan-output.txt`, and `$DESIGN_TMPDIR/cursor-plan-output.txt` as the output files.

### After all reviewers return

**Process Claude findings immediately** — do not wait for external reviewers before starting:

1. Collect findings from the two Claude subagents right away. Claude subagents produce **dual-list output** (per `reviewer-templates.md`): "In-Scope Findings" and "Out-of-Scope Observations". Parse both lists from each subagent.
2. **Then** poll for external reviewer sentinel files (only for reviewers that were actually launched: `$DESIGN_TMPDIR/cursor-plan-output.txt.done`, `$DESIGN_TMPDIR/codex-general-plan-output.txt.done`, and/or `$DESIGN_TMPDIR/codex-deep-plan-output.txt.done`). Read each reviewer's exit code from its sentinel file, then validate its output per the shared procedure. External reviewers (Codex, Cursor) produce single-list output — treat their entire output as in-scope findings.
3. Merge external reviewer in-scope findings into the Claude in-scope findings.
4. Deduplicate in-scope findings separately. Assign each a stable sequential ID (`FINDING_1`, `FINDING_2`, etc.) and note which reviewer(s) proposed each.
5. Deduplicate out-of-scope observations separately. Assign each an `OOS_` prefixed ID (`OOS_1`, `OOS_2`, etc.). If the same issue appears in both in-scope and OOS from different reviewers, merge under the in-scope finding (in-scope takes precedence).

If **all reviewers** report no in-scope issues and no out-of-scope observations, skip voting and proceed to Step 3b (Architecture Diagram).

### Voting Panel (replaces negotiation)

After deduplication, submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `.claude/skills/shared/larch/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section — voters can promote OOS items to in-scope by voting YES. For plan review:

- **Voter 1**: Claude Deep Analysis reviewer subagent — fresh Agent tool invocation with the voting prompt. Instruct: `"You are a senior architect and correctness specialist on a voting panel. You will vote YES, NO, or EXONERATE on proposed modifications to an implementation plan. Be scrupulous — only vote YES for findings that are correct, important, and worth revising the plan for. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot

For Codex and Cursor voters, instruct each: `"You are a senior engineer on a voting panel deciding which proposed plan modifications should be accepted."`

If fewer than 2 voters are available (both Codex and Cursor unavailable), follow the Voting Protocol's fallback: skip voting, accept all findings, and print the insufficient-voters warning.

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$DESIGN_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $DESIGN_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

Launch all available voters **in parallel** (Cursor first, then Codex, then Claude subagent). Wait for external voter sentinels using `wait-for-reviewers.sh` per the Voting Protocol, then parse voter outputs.

**Tally votes**: Apply the threshold rules from the Voting Protocol based on eligible voters per finding (2+ YES with 3 voters, unanimous 2/2 with 2 voters, skip if <2 eligible). Print the vote breakdown per finding.

**Competition scoring**: Compute and print the **Reviewer Competition Scoreboard** per the Voting Protocol's scoring rules (+1 for accepted, 0 for neutral/exonerated, -1 for rejected — see `voting-protocol.md` for the full outcome matrix). Print the scoreboard table.

### Finalize Plan Review

If any in-scope findings or promoted OOS items were **accepted by vote** (2+ YES votes):
1. Print them under a `## Plan Review Findings (Voted In)` header with vote counts. Include any promoted OOS items (labelled as `[PROMOTED FROM OUT-OF-SCOPE]`).
2. Revise the implementation plan to address each accepted finding and promoted OOS item.
3. Print the revised plan under a `## Revised Implementation Plan` header.

Print any non-promoted OOS items under a `## Out-of-Scope Observations` header for visibility. These are not implemented but are recorded for future attention.

If voting rejects all in-scope findings and no OOS items are promoted, print: `**ℹ Voting panel rejected all findings. Plan unchanged.**` and proceed to Step 3b (Architecture Diagram).

### Track Rejected Plan Review Findings

For any **in-scope** findings that were **not accepted by vote** (fewer than 2 YES votes — whether rejected or exonerated) during plan review (from any reviewer — Claude subagents, Codex, or Cursor), append each to `$DESIGN_TMPDIR/rejected-findings.md` using this format. **Do not include non-promoted OOS items** — those are reported separately in the "Out-of-Scope Observations" PR body section per `voting-protocol.md`:

```markdown
### [Plan Review] <Reviewer Name>
**Finding**: <thorough description of the finding — include what aspect of the plan the reviewer questioned, the specific concern raised, and what revision they suggested. Must be detailed enough to serve as an actionable TODO item if later prioritized. Do NOT use a terse one-liner — a reader who has never seen the original review must be able to understand the concern and act on it.>
**Reason not implemented**: <complete justification for why this finding was not accepted — include the specific technical reasoning, any relevant context about project conventions or design decisions, and why the current plan is acceptable despite the finding. Do NOT abbreviate — preserve all important details from the evaluation.>
```

If no findings were rejected, do not create the file yet.

## Step 3a — Post-Review Confirmation

Print: `✅ Step 3a — Post-review confirmation...`

**If `auto_mode=true`**: Print `⏩ Step 3a — Skipped (auto mode).` and proceed to Step 3b.

**If the plan was NOT revised by reviewers** (voting rejected all findings or was skipped): Print `⏩ Step 3a — Skipped (plan unchanged by review).` and proceed to Step 3b.

**If `auto_mode=false` AND the plan was revised by reviewers**: Use `AskUserQuestion` to confirm the revised plan addresses the user's original intent. Present a brief summary of what changed and ask the user to approve or reject.

**This step is strictly approval-only** — the user confirms the revised plan is acceptable to proceed with implementation. No substantive plan changes are accepted at this point — the reviewed/voted plan is the canonical artifact. If the user rejects the plan, print a warning and proceed anyway (the plan has already been reviewed and voted on; the user can adjust during implementation or in a follow-up PR).

Print: `✅ Step 3a — Plan confirmed.`

## Step 3b — Architecture Diagram

Print: `🗺️ Step 3b — Generating architecture diagram...`

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

**If diagram generation succeeds**, print: `✅ Step 3b — Architecture diagram generated.`

**If diagram generation fails** (e.g., the feature is too abstract to diagram meaningfully), print: `**⚠ Step 3b — Architecture diagram generation failed. Proceeding without diagram.**`

## Step 4 — Rejected Plan Review Findings Report

Print any rejected plan review findings:

1. Check if `$DESIGN_TMPDIR/rejected-findings.md` exists and is non-empty.
2. If it has content, print it under a `## Unimplemented Plan Review Suggestions` header, formatted clearly with the reviewer name, the suggestion, and the reason for each.
3. If the file doesn't exist or is empty, print: `📊 Step 4 — All plan review suggestions were implemented.`

## Step 5 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
$PWD/.claude/scripts/generic/larch/cleanup-tmpdir.sh --dir "$DESIGN_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier steps (Step 0b binary checks, Step 2a sketch-phase failures/timeouts, Step 3 runtime failures, or Step 3b diagram generation failure) so they are visible at the end of the workflow. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`
- `**⚠ Cursor sketch timed out / produced empty output**`
- `**⚠ Codex sketch timed out / produced empty output**`
- `**⚠ Step 3b — Architecture diagram generation failed. Proceeding without diagram.**`

Print: `🏁 Step 5 — Design complete! The implementation plan is ready. Run /implement to proceed with implementation.`
