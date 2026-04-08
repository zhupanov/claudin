---
name: research
description: Collaborative read-only research using 5 research agents (3 Claude + Cursor + Codex) then 5 validation reviewers (2 Claude + 2 Codex + Cursor). Produces findings summary, risk assessment, difficulty estimates, and feasibility verdict without modifying the repo.
argument-hint: "<research question or topic>"
allowed-tools: Bash, Read, Grep, Glob, Agent, Task, WebFetch, WebSearch
---

# Research Skill

Collaborative read-only research task using 5 research agents (3 Claude subagents + Codex + Cursor) and 5 validation reviewers (2 Claude subagents + 2 Codex + Cursor). Produces a structured research report without modifying the repository.

The research question is described by `$ARGUMENTS`.

**Read-only contract**: This skill does NOT create branches, modify files, or make commits. All scratch artifacts are written to `/tmp` via Bash. The `allowed-tools` frontmatter omits `Edit`, `Write`, and `Skill` — the orchestrating agent cannot use those tools. External reviewers (Codex, Cursor) are instructed not to modify files, but this is a behavioral constraint (prompt-enforced), not mechanically enforced. Known limitation: concurrent repo changes during a long research run may cause agents to see slightly different snapshots.

## Progress Reporting

**Every step MUST print clearly visible status lines** so the user can instantly see where execution is at. Use distinct emoji prefixes:

- Print a **start line** when entering a step: e.g., `🔬 Step 1 — Launching research perspectives...`
- Print a **completion line** when done: e.g., `✅ Step 1 — Research synthesis complete (5 agents).`

Suggested emoji palette (use consistently):
| Step | Emoji | Description |
|------|-------|-------------|
| 0 | 🔧 | Session setup |
| 1 | 🔬 | Collaborative research perspectives |
| 2 | 🔍 | Findings validation |
| 3 | 📊 | Final research report |
| 4 | 🏁 | Cleanup |

## Step 0 — Session Setup

### 0a — Create Temp Directory

Create a session-scoped temporary directory:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-session-tmpdir.sh --prefix claude-research
```

Parse the output for `SESSION_TMPDIR`. Set `RESEARCH_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

### 0b — Quick External Reviewer Check

Read and follow the **Binary Check** section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`.

### 0c — Record Research Context

Record the current branch and commit for inclusion in the final report:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-branch-info.sh
```

Parse the output for `HEAD_SHA` and `CURRENT_BRANCH`. If `CURRENT_BRANCH` is empty (detached HEAD), use `"(detached HEAD)"` in the report.

Print: `🔧 Step 0 — Setup complete. Researching on branch <CURRENT_BRANCH> at commit <HEAD_SHA>.`

## Step 1 — Collaborative Research Perspectives

**IMPORTANT: The collaborative research phase MUST ALWAYS run with all 5 agents (using Claude replacements when external tools are unavailable). Never skip or abbreviate this phase regardless of how simple the research question appears. Multiple independent perspectives surface insights that a single agent would miss.**

A diverge-then-converge phase where 5 agents independently explore the codebase from different research perspectives before synthesizing findings.

The 5 research agents always include these 3 Claude subagents plus Cursor and Codex (or Claude replacements when unavailable):

1. **Claude (General Research)** — the orchestrating agent's own research, covering the main findings, relevant code areas, and key observations
2. **Claude (Architecture/Patterns)** — emphasizes structural patterns, design decisions, code organization, reuse opportunities, and how the codebase addresses the research question architecturally
3. **Claude (Risk/Feasibility)** — emphasizes risks, constraints, feasibility concerns, potential obstacles, and difficulty assessment

Plus 2 external agents (or Claude replacements):

4. **Cursor** (if available) — or **Claude (Alternative Perspectives)** replacement: questions assumptions, explores unconventional angles, and surfaces insights that the other agents might overlook
5. **Codex** (if available) — or **Claude (Edge-cases/Gaps)** replacement: focuses on what might be missing, edge cases, gaps in the codebase, failure modes, and boundary conditions relevant to the research question

Print `🔬 Step 1 — Running collaborative research phase.` and proceed to 1.2.

### 1.2 — Launch Research Perspectives in Parallel

**Critical sequencing**: You MUST launch all external research Bash tool calls (with `run_in_background: true`) AND all Claude subagent research BEFORE producing your own inline research. External reviewers take significantly longer than Claude — launching them first maximizes parallelism.

**Spawn order**: Cursor first (slowest), then Codex, then Claude subagents, then your own research (fastest). Issue all Bash and Agent tool calls in a single message.

**Cursor research** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool cursor --output "$RESEARCH_TMPDIR/cursor-research-output.txt" --timeout 900 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Explore the codebase to understand the relevant architecture and code. Write 2-3 paragraphs covering: (1) Your key findings and observations relevant to the research question, (2) Which files/modules/areas are most relevant and why, (3) Any risks, constraints, or feasibility concerns you identify. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Cursor replacement** (if `cursor_available` is false): Launch a Claude subagent (Alternative Perspectives) via the Agent tool instead:

Prompt: `"You are an Alternative Perspectives researcher. Investigate this research question: <RESEARCH_QUESTION>. Your role is to question assumptions, explore unconventional angles, and surface insights that others might overlook. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Your key findings, especially any that challenge conventional thinking, (2) Which files/modules/areas are most relevant and why, (3) Alternative interpretations or angles worth considering. Do NOT modify files."`

**Codex research** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-research-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$RESEARCH_TMPDIR/codex-research-output.txt" \
    "You are researching a codebase to answer this question: <RESEARCH_QUESTION>. Explore the codebase to understand the relevant architecture and code. Write 2-3 paragraphs covering: (1) Your key findings and observations relevant to the research question, (2) Which files/modules/areas are most relevant and why, (3) Any risks, constraints, or feasibility concerns you identify. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Codex replacement** (if `codex_available` is false): Launch a Claude subagent (Edge-cases/Gaps) via the Agent tool instead:

Prompt: `"You are an Edge-case/Gaps analyst. Investigate this research question: <RESEARCH_QUESTION>. Your role is to focus on what might be missing, edge cases, gaps in the codebase, failure modes, and boundary conditions relevant to the question. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Your key findings, especially gaps or missing pieces, (2) Which files/modules/areas are most relevant and why — call out any fragile or incomplete areas, (3) Edge cases and boundary conditions that are relevant to the question. Do NOT modify files."`

**Claude subagent (Architecture/Patterns)**: Launch via the Agent tool:

Prompt: `"You are an Architecture/Patterns researcher. Investigate this research question: <RESEARCH_QUESTION>. Your role is to emphasize structural patterns, design decisions, code organization, and how the codebase addresses the topic architecturally. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Your key findings about architectural patterns and design decisions relevant to the question, (2) Which files/modules/areas are most relevant and why — note any patterns, abstractions, or reuse opportunities, (3) How the current architecture supports or constrains what the research question is asking about. Do NOT modify files."`

**Claude subagent (Risk/Feasibility)**: Launch via the Agent tool:

Prompt: `"You are a Risk/Feasibility researcher. Investigate this research question: <RESEARCH_QUESTION>. Your role is to emphasize risks, constraints, feasibility concerns, potential obstacles, and difficulty assessment. Explore the codebase via Read/Grep/Glob tools. Write 2-3 paragraphs covering: (1) Your key findings about risks and feasibility relevant to the question, (2) Which files/modules/areas are most relevant and why — flag high-risk or constrained areas, (3) Your assessment of difficulty and feasibility, including any blockers or prerequisites. Do NOT modify files."`

**Claude research (General)**: Only after all external and subagent launches are issued, produce your own 2-3 paragraph research inline covering the same three areas: (1) key findings and observations, (2) relevant files/modules/areas, (3) risks and feasibility. Print it under a `### Claude Research (General)` header. Write this **before** reading any external or subagent outputs to preserve independence.

### 1.3 — Wait and Validate Research Outputs

Wait for external research sentinels using `wait-for-reviewers.sh`. Only include paths for external reviewers that were actually launched (not Claude replacements — those return via Agent tool):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/wait-for-reviewers.sh --timeout 960 "$RESEARCH_TMPDIR/cursor-research-output.txt.done" "$RESEARCH_TMPDIR/codex-research-output.txt.done"
```

Use `timeout: 960000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Only include sentinel paths for external reviewers that were actually launched.

**Validate research outputs**: For research outputs, the validation criteria differ from the standard review validation in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`: instead of checking for numbered findings or `NO_ISSUES_FOUND`, check that the output is non-empty and contains at least one paragraph of substantive prose. Use `$RESEARCH_TMPDIR/cursor-research-output.txt` and `$RESEARCH_TMPDIR/codex-research-output.txt` as the output files. If an output is empty despite exit code 0, retry once with a `-retry` suffix per the shared procedure in `external-reviewers.md`.

### 1.4 — Synthesis

Read all 5 research outputs (Claude General + Architecture/Patterns + Risk/Feasibility + Cursor or replacement + Codex or replacement). Produce a synthesis that:

1. Identifies where the perspectives **agree** on key findings
2. Identifies where they **diverge** and makes a reasoned assessment on each contested point
3. Notes which insights from each perspective are most significant
4. Highlights any **Architecture/Patterns** observations about the codebase
5. Highlights any **Risk/Feasibility** concerns or constraints

Print the synthesis under a `## Research Synthesis` header. Write the synthesis to `$RESEARCH_TMPDIR/research-report.txt` via Bash so it can be used by Step 2. The file should contain:
- The original research question
- The branch and commit being researched
- The synthesized findings

Print: `✅ Step 1 — Research synthesis complete (5 agents).`

## Step 2 — Findings Validation

**IMPORTANT: Findings validation MUST ALWAYS run with all available reviewers (2 Claude subagents + 2 Codex instances and Cursor if available). Never skip or abbreviate this step regardless of how straightforward the findings appear. Reviewers validate against the actual codebase state, catching inaccuracies or omissions that the research phase may have missed.**

Launch **all reviewers in parallel** (in a single message). **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then both Codex instances, then Claude subagents (fastest). Each reviewer receives the research report and the original question. Each must **only report findings** — never edit files.

### External Reviewer Setup (if `codex_available` or `cursor_available`)

The research report is already written to `$RESEARCH_TMPDIR/research-report.txt` from Step 1.4, so both Codex and Cursor can read it.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool cursor --output "$RESEARCH_TMPDIR/cursor-validation-output.txt" --timeout 900 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "Review the research findings in $RESEARCH_TMPDIR/research-report.txt for accuracy and completeness. Read the report, then explore the codebase to verify claims. Combine 4 perspectives: (1) General: Are findings accurate? Is anything important missing? Are conclusions well-supported by evidence? (2) Correctness: Are specific code references correct? Are there factual errors about the codebase? (3) Risk/Completeness: Are risks properly identified? Are there blind spots or omissions? (4) Architecture: Are architectural observations accurate? Are there structural patterns that were missed? Return numbered findings with perspective, concern, and suggested correction. If the research is accurate and complete, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Codex-General Reviewer (if `codex_available`)

Run Codex-General **second** in the parallel message:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-general-validation-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$RESEARCH_TMPDIR/codex-general-validation-output.txt" \
    "Review the research findings in $RESEARCH_TMPDIR/research-report.txt for accuracy and completeness. Read the report, then explore the codebase to verify claims. Focus on 2 perspectives: (1) General: Are findings accurate? Is anything important missing? Are conclusions well-supported by evidence? (2) Risk/Completeness: Are risks properly identified? Are there blind spots or omissions? Return numbered findings with perspective, concern, and suggested correction. If the research is accurate and complete, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Codex-Deep-Analysis Reviewer (if `codex_available`)

Run Codex-Deep-Analysis **third** in the parallel message:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "$RESEARCH_TMPDIR/codex-deep-validation-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$RESEARCH_TMPDIR/codex-deep-validation-output.txt" \
    "Review the research findings in $RESEARCH_TMPDIR/research-report.txt for accuracy and completeness. Read the report, then explore the codebase to verify claims. Focus on 2 perspectives: (1) Correctness: Are specific code references correct? Are there factual errors about the codebase? (2) Architecture: Are architectural observations accurate? Are there structural patterns that were missed? Return numbered findings with perspective, concern, and suggested correction. If the research is accurate and complete, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Claude Subagents (2 reviewers)

Launch both Claude subagents **last** in the same message (they finish fastest).

Use the two reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/reviewer-templates.md`, filling in the variables for **research validation**:

- **`{REVIEW_TARGET}`** = `"research findings"`
- **`{CONTEXT_BLOCK}`**:
  ```
  ## Research question
  {RESEARCH_QUESTION}

  ## Research findings to validate
  {SYNTHESIZED_FINDINGS}
  ```
- **`{OUTPUT_INSTRUCTION}`** = `"What the concern is (inaccuracy, omission, or unsupported claim)"` + `"Suggested correction or addition"`

**Research-specific acceptance criteria**: Accept a finding unless it is factually incorrect (misreads the codebase, references wrong file/line) or is already addressed in the synthesis. For research validation, "factually incorrect" means the finding misidentifies code, misattributes behavior, or contradicts something verifiable by reading source files.

### Monitoring External Reviewers

Follow the **Monitoring External Reviewers** and **Validating External Reviewer Output** sections in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`, using `$RESEARCH_TMPDIR/codex-general-validation-output.txt`, `$RESEARCH_TMPDIR/codex-deep-validation-output.txt`, and `$RESEARCH_TMPDIR/cursor-validation-output.txt` as the output files.

### After all reviewers return

**Process Claude findings immediately** — do not wait for external reviewers before starting:

1. Collect and deduplicate findings from the two Claude subagents right away.

### 2.4 — Wait and Validate External Reviewers

After processing Claude findings, wait for external reviewer sentinels using `wait-for-reviewers.sh`. Only include paths for external reviewers that were actually launched:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/wait-for-reviewers.sh --timeout 960 "$RESEARCH_TMPDIR/cursor-validation-output.txt.done" "$RESEARCH_TMPDIR/codex-general-validation-output.txt.done" "$RESEARCH_TMPDIR/codex-deep-validation-output.txt.done"
```

Use `timeout: 960000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block.

2. Read each reviewer's exit code from its sentinel file, then validate its output per the shared procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`.
3. Merge external reviewer findings into the already-processed Claude findings.

### Codex and Cursor Negotiation (in parallel)

If any external reviewers produced findings, negotiate with each independently. With 2 Codex instances (Codex-General and Codex-Deep-Analysis), negotiate with each separately using distinct prompt/output file paths (e.g., `codex-general-negotiation-prompt.txt` / `codex-general-negotiation-output.txt` and `codex-deep-negotiation-prompt.txt` / `codex-deep-negotiation-output.txt`). Run all negotiations **in parallel** when multiple external reviewers produced findings. Use the **Negotiation Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`, using `$RESEARCH_TMPDIR` as the tmpdir. Merge accepted/rejected outcomes after all complete.

### Finalize Validation

If any findings were accepted (from Claude subagents, Codex, or Cursor):
1. Print them under a `## Validation Findings` header.
2. Revise the research synthesis to incorporate corrections and additions.
3. Print the revised synthesis under a `## Revised Research Findings` header.

If all reviewers report no issues, print: `✅ Step 2 — All findings validated. No corrections needed.`

## Step 3 — Final Research Report

Print the final research report under a `## Research Report` header with the following structure:

```markdown
## Research Report

**Research question**: <the original $ARGUMENTS>
**Codebase context**: Branch `<CURRENT_BRANCH>`, commit `<HEAD_SHA>`
**Research phase**: <N> agents (Cursor: ✅/❌, Codex: ✅/❌)
**Validation phase**: <N> reviewers (Cursor: ✅/❌, Codex: ✅/❌)

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

If risk assessment, difficulty estimate, or feasibility verdict are not applicable to the nature of the research question (e.g., a pure "how does X work?" question), mark them as **N/A** with a brief explanation.

Print: `📊 Step 3 — Research report complete.`

## Step 4 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/cleanup-tmpdir.sh --dir "$RESEARCH_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier steps (Step 0b binary checks, Step 1 research-phase failures/timeouts, or Step 2 validation failures) so they are visible at the end of the workflow. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`
- `**⚠ Cursor research timed out / produced empty output**`
- `**⚠ Codex research timed out / produced empty output**`

Print: `🏁 Step 4 — Research complete!`
