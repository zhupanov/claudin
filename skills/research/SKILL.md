---
name: research
description: "Use when read-only-repo research is needed. 3 research agents + 3-reviewer validation panel (Claude + Codex + Cursor) produce findings, risk assessment, difficulty, feasibility. /tmp scratch writes only; may invoke /issue to file result issues."
argument-hint: "[--debug] <research question or topic>"
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

Collaborative read-only-repo research task using 3 research agents (Claude inline + Cursor + Codex, uniformly briefed) and a 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant when Cursor or Codex is unavailable. Produces a structured research report without modifying tracked repo files. Scratch writes are permitted under canonical `/tmp` only (enforced by the skill-scoped PreToolUse hook); may invoke `/issue` via the Skill tool to file research-result issues.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/issue`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the research question. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, save the remainder as `RESEARCH_QUESTION`. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`.

The research question is described by `RESEARCH_QUESTION` (not raw `$ARGUMENTS`). Use `RESEARCH_QUESTION` wherever human-readable topic text is needed (e.g., agent prompts, report headers, temp file content).

**Read-only-repo contract**: This skill does NOT create branches, modify tracked repo files, or make commits. The contract is enforced mechanically by the skill-scoped PreToolUse hook `${CLAUDE_PLUGIN_ROOT}/scripts/deny-edit-write.sh`, which matches `Edit|Write|NotebookEdit` and permits the call only when the target `tool_input.file_path` (or `tool_input.notebook_path`) resolves to an absolute path under canonical `/tmp`; any other path denies. The `allowed-tools` frontmatter lists `Edit`, `Write`, `NotebookEdit`, and `Skill` — it declares the orchestrator's surface but does NOT confine writes to `/tmp`; the hook is the sole mechanical enforcer of the `/tmp`-only policy. Residual risk: if a Claude Code version does not honor hook `permissionDecision: "deny"`, no mechanical fallback prevents repo writes — see `SECURITY.md` for the full risk framing. `Skill` is permitted so the orchestrator may invoke `/issue` via the Skill tool for research-results-to-issues flows; child skills run under their own `allowed-tools` and hooks, not under this one. External reviewers (Codex, Cursor) are instructed not to modify files, but this is a behavioral constraint (prompt-enforced), not mechanically enforced. Known limitation: concurrent repo changes during a long research run may cause agents to see slightly different snapshots. Existing Bash heredoc writes to `$RESEARCH_TMPDIR` under `/tmp` continue to work unchanged.

## Sub-skill invocation

Invoke `/issue` via the Skill tool when the research brief calls for filing the findings as GitHub issues. Follow the Pattern B conventions in `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` — pass `--session-env`, parse `/issue`'s stdout machine lines, and continue with the parent's next step after the child returns.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 1: research**`
- Print a **completion line** when done: e.g., `✅ 1: research — synthesis complete, 3 agents (3m12s)`

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | research |
| 2 | validation |
| 3 | report |
| 4 | cleanup |

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

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `RESEARCH_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

Set mental flags `codex_available` and `cursor_available` based on the output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed). Using Claude replacement.**`
- Else: `codex_available=true`
- Same logic for Cursor.

### 0c — Record Research Context

Record the current branch and commit for inclusion in the final report:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-branch-info.sh
```

Parse the output for `HEAD_SHA` and `CURRENT_BRANCH`. If `CURRENT_BRANCH` is empty (detached HEAD), use `"(detached HEAD)"` in the report.

Print: `✅ 0: setup — researching on branch <CURRENT_BRANCH> at <HEAD_SHA> (<elapsed>)`

## Step 1 — Collaborative Research Perspectives

Print: `> **🔶 1: research**`

**MANDATORY — READ ENTIRE FILE** before executing Step 1: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md`. It carries the 3-lane research invariant banner, the `RESEARCH_PROMPT` literal, the Cursor and Codex launch bash blocks with their per-slot Claude fallbacks, the Claude inline-research independence rule, Step 1.3 `COLLECT_ARGS` + zero-externals branch + Runtime Timeout Fallback pointer, and Step 1.4 synthesis requirements. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md` at Step 1** — that reference is Step 2's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 1 per the reference file above (phases 1.2, 1.3, 1.4). SKILL.md is the sole owner of Step 1 entry and completion breadcrumbs; the reference file emits none. On completion, print: `✅ 1: research — synthesis complete, 3 agents (<elapsed>)`

## Step 2 — Findings Validation

Print: `> **🔶 2: validation**`

**MANDATORY — READ ENTIRE FILE** before executing Step 2: `${CLAUDE_PLUGIN_ROOT}/skills/research/references/validation-phase.md`. It carries the 3-lane validation invariant banner, the Cursor and Codex validation-reviewer launch bash blocks with their long prompts and per-slot Claude Code Reviewer subagent fallbacks, the always-on Claude Code Reviewer subagent lane with the research-validation variable bindings (`{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` / `{OUTPUT_INSTRUCTION}`) and research-specific acceptance criteria, the process-Claude-findings-immediately rule, Step 2.4 `COLLECT_ARGS` + zero-externals branch + runtime-timeout replacement, the Codex/Cursor negotiation delegation to `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`, and the Finalize Validation procedure. **Do NOT load `${CLAUDE_PLUGIN_ROOT}/skills/research/references/research-phase.md` at Step 2** — that reference is Step 1's body and loading it now would pollute context with the wrong phase's prompts.

Execute Step 2 per the reference file above. SKILL.md is the sole owner of Step 2 entry and completion breadcrumbs; the reference file emits none. On completion, if all reviewers report no issues, print: `✅ 2: validation — all findings validated, no corrections needed (<elapsed>)`

## Step 3 — Final Research Report

Print: `> **🔶 3: report**`

Print the final research report under a `## Research Report` header with the following structure:

```markdown
## Research Report

**Research question**: <RESEARCH_QUESTION>
**Codebase context**: Branch `<CURRENT_BRANCH>`, commit `<HEAD_SHA>`
**Research phase**: <N> agents (Cursor: ✅/❌, Codex: ✅/❌)
**Validation phase**: <N> reviewers (Code: ✅, Cursor: ✅/❌, Codex: ✅/❌)

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

Print: `✅ 3: report — complete (<elapsed>)`

## Step 4 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$RESEARCH_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier steps (Step 0b binary checks, Step 1 research-phase failures/timeouts, or Step 2 validation failures) so they are visible at the end of the workflow. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`
- `**⚠ Cursor research timed out / produced empty output**`
- `**⚠ Codex research timed out / produced empty output**`

Print: `✅ 4: cleanup — research complete! (<elapsed>)`
