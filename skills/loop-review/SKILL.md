---
name: loop-review
description: "Use when a comprehensive quality sweep or systematic code review is needed. Partitions the repo into slices, reviews each with a 3-reviewer panel, implements fixes via /implement, and logs deferred suggestions."
argument-hint: "[--debug] [partition criteria]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Loop Review

Systematically review the entire codebase by partitioning into slices, reviewing each with a 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor), implementing improvements via `/implement`, and tracking deferred suggestions in a checked-in document.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as partition criteria. Flags may appear in any order; stop at the first non-flag token. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`. When `debug_mode=true`, propagate `--debug` to all `/implement` invocations.

**This skill runs fully autonomously** — never ask for user confirmation. Make all implement/defer decisions based on the classification criteria in Step 3d. All sub-skills (`/implement`, `/review`, `/design`, `/relevant-checks`) also run autonomously. **Always pass `--auto --merge` when invoking `/implement`** (plus `--debug` if `debug_mode=true`) — `--auto` suppresses interactive question checkpoints in `/design`, and `--merge` opts into the CI+rebase+merge loop that loop-review's batched flow depends on (without `--merge`, `/implement` stops after PR creation and would break loop-review's merge-and-return-to-main expectation).

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 3: implement/defer — slice: scripts/...**`
- Print a **completion line** when done: e.g., `✅ 3: implement/defer — 3 findings implemented, 1 deferred (5m22s)`

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | partition |
| 2 | review slice |
| 3 | implement/defer |
| 4 | deferred commit |
| 5 | summary |
| 6 | cleanup |

### Verbosity Control

**When `debug_mode=false` (default):**

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (slice results, findings lists, deferred items, final report).

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text (current verbose behavior).

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Step 0 — Session Setup

### 0a — Session Setup, Preflight, and Reviewer Check

Run the shared session setup script. This handles preflight (must be on clean `main`), temp directory creation, and reviewer health probe in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-loop-review --skip-slack-check --skip-repo-check --check-reviewers
```

Note: Neither `--skip-preflight` nor `--skip-branch-check` is passed — this ensures full preflight with branch check, which enforces the on-main requirement.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `LR_TMPDIR` = `SESSION_TMPDIR`.

Set `codex_available` and `cursor_available` flags for the entire session:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Append `**⚠ Codex not available (binary not found).**` to `$LR_TMPDIR/warnings.md`.
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Append `**⚠ Codex installed but not responding. Using Claude replacement.**` to `$LR_TMPDIR/warnings.md`.
- Else: `codex_available=true`
- Same logic for Cursor.

### 0b — Initialize Tracking Files

Initialize tracking files for the slice review loop:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/init-session-files.sh --dir "$LR_TMPDIR"
```

## Step 1 — Partition the Repository

After flag stripping in the Flags section above, save the remainder of `$ARGUMENTS` as `PARTITION_CRITERIA`. Use `PARTITION_CRITERIA` (not raw `$ARGUMENTS`) for all partition logic below.

### Custom criteria (if `PARTITION_CRITERIA` is non-empty)

Parse `PARTITION_CRITERIA` as the partition strategy:

- `by directory` — same as default below
- `by module` — one slice per logical module: group related source files, handlers, and tests together based on the project's module/package structure (e.g., one slice per package in Go, one per module directory in Python, one per feature directory in TypeScript)
- Explicit paths (space-separated) — use those directories as slices
- Any other text — interpret as a natural-language description of how to partition and apply it

### Default: From partition config or auto-discovery

If `PARTITION_CRITERIA` is empty:

1. **Check for `.claude/loop-review-partitions.json`**: If this file exists, read it. It contains an array of `{"name": "<slice name>", "paths": ["<path>", ...]}` objects. Use these as the slices.

2. **Auto-discovery fallback**: If no partition config exists, auto-discover slices by finding directories at depth 1–2 from the repo root that contain source files (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`). Group them into slices, one per top-level directory. Add a final "Skills & documentation" slice for `.claude/skills/` and top-level `.md` files. Cap at 10 slices; merge smaller directories into an "other" bucket.

Print the partition plan with file counts per slice.

## Step 2 — Initialize Deferred Suggestions Document

If `LOOP_REVIEW_DEFERRED.md` does not exist at the repo root, create it locally (do NOT commit yet — it will be committed as part of the first `/implement` PR):

```markdown
# Loop Review — Deferred Suggestions

Review suggestions that were identified but deferred, with explanations for each omission.
```

## Step 3 — Slice Review Loop

Process slices with **batched implementation**. Review slices sequentially, but accumulate IMPLEMENT findings across up to 3 slices before invoking `/implement`. This reduces the number of CI/merge cycles from N to roughly N/3.

For each slice (using `N` as the 1-based slice index):

### 3a — Announce

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Reviewing Slice N/M: <name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 3b — Gather file list

Use Glob to collect relevant source files in the slice (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`, `.md`, `.yaml`, `.yml`, `.json`). Exclude test files (e.g., `*_test.go`, `*_test.py`, `*.test.ts`, `*.spec.js`) from review targets (but tests serve as context for reviewers).

Write the full file list to `$LR_TMPDIR/slice-N-files.txt` (one path per line) for external reviewers to read.

**Sub-slicing (>50 files):** If the slice has more than 50 files, split the file list into sub-slices of ≤50 files each. For each sub-slice, launch 1 Claude Code Reviewer subagent lane with only that sub-slice's files as `{FILE_LIST}`. External reviewers always receive the full slice file list (one invocation per slice regardless of sub-slicing). After all sub-slices and external reviewers complete, merge all Claude findings from all sub-slices with external reviewer findings before proceeding to Step 3d.

### 3c — Launch 3 review subagents in parallel

Launch **all 3 reviewer lanes** in a **single message**. When external tools are unavailable, launch Claude Code Reviewer subagent fallbacks instead so the total reviewer count always remains 3. **Spawn order matters for parallelism** — launch the slowest reviewer first: Cursor (slowest), then Codex, then the Claude Code Reviewer subagent (fastest). External reviewers are launched once per slice even when sub-slicing. The Claude subagent lane uses the current sub-slice's `{FILE_LIST}` if sub-slicing, or the full file list otherwise. Each must **only report findings — never edit files**.

**Cursor Reviewer (if `cursor_available`):**

Run Cursor **first** in the parallel message (it takes the longest):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$LR_TMPDIR/cursor-output-slice-N.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Combine 4 review perspectives: (1) Quality: bugs, logic errors, dead code, duplication, missing error handling. (2) Correctness: off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: broken contracts, thread safety, deployment risks, CI gaps. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor fallback** (if `cursor_available` is false): Launch a Claude Code Reviewer subagent (subagent_type: `code-reviewer`) via the Agent tool instead. Use the unified Code Reviewer checklist. Bind `{FILE_LIST}` to the **current sub-slice** file list when sub-slicing; otherwise use the full slice file list. Drop the `"Work at your maximum reasoning effort"` suffix (Claude uses session-default effort).

**Codex Reviewer (if `codex_available`):**

Run Codex **second** in the parallel message (after Cursor):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$LR_TMPDIR/codex-output-slice-N.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$LR_TMPDIR/codex-output-slice-N.txt" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Walk four focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Tag each finding with its focus area. Return numbered findings with focus-area tag, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex fallback** (if `codex_available` is false): Launch **1 Claude Code Reviewer subagent** via the Agent tool (`subagent_type: code-reviewer`) with the same slice-review context. Bind `{FILE_LIST}` to the **current sub-slice** file list when sub-slicing (>50 files per slice), matching the always-on Claude lane's sub-slicing rule; otherwise use the full slice file list. Reserve `slice-N-files.txt` (the full slice) for actual external reviewers. Attribute as `Code`.

**Claude Code Reviewer subagent (1 reviewer, always-on — launched last in the same parallel message, finishes fastest):**

Invoke `subagent_type: code-reviewer` using the unified checklist from `skills/shared/reviewer-templates.md`. The `code-reviewer` archetype walks five focus areas: code quality, risk/integration, correctness, architecture, and security. Prompt body:

> Review EXISTING code for this project. Files: {FILE_LIST}. Read each file. Walk the unified 5-focus-area checklist (code quality, risk/integration, correctness, architecture, security). Tag each finding with its focus area. Quality gate: for each finding, verify the proposed fix is justified by a concrete need and proportionate to the issue. Return numbered findings: file:line, issue, specific fix. If none: "No issues found." Do NOT edit files.

**Collecting External Reviewer Results:**

Build the argument list from only the externals that were actually launched:

```
COLLECT_ARGS=()
[[ "$cursor_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/cursor-output-slice-N.txt")
[[ "$codex_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/codex-output-slice-N.txt")
```

**Zero-externals branch**: If BOTH Cursor and Codex are unavailable for this slice (`COLLECT_ARGS` is empty — the 3 lanes are the always-on Claude lane plus 2 Claude fallback lanes), **skip `collect-reviewer-results.sh` entirely** and **skip all external negotiation** below. Merge the 3 Claude findings and proceed to Step 3d.

Otherwise, invoke the collection script with only the launched paths:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 "${COLLECT_ARGS[@]}"
```

Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`: **immediately launch the matching single Claude Code Reviewer subagent fallback** for the current slice before proceeding to Step 3d (so this slice still has 3 lanes), then **flip that reviewer's availability flag to false** for all remaining slices (prevents repeated failures). Also append a detailed warning to `$LR_TMPDIR/warnings.md`.

### 3d — Collect, negotiate, deduplicate, and classify findings

**After ALL reviewers return** (the always-on Claude Code Reviewer subagent lane AND any launched external reviewers or their runtime-fallback Claude replacements), proceed:

**1. Collect** all findings from the Claude Code Reviewer subagent lane and validated external reviewer output (and any runtime-fallback Claude findings).

**2. Negotiate** with external reviewers (if they produced findings):

Follow the **Negotiation Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`, using `$LR_TMPDIR` as the tmpdir, with `max_rounds=1`. Use `codex-negotiation-prompt.txt` / `codex-negotiation-output.txt` for the single Codex negotiation track and `cursor-negotiation-prompt.txt` / `cursor-negotiation-output.txt` for the Cursor negotiation track. Run both negotiations in parallel when both externals produced findings. Accept findings unless factually incorrect or contradicting CLAUDE.md.

Note: "accepted" in the negotiation sense means the finding is valid — it may still be classified as DEFER below.

**3. Deduplicate** — merge findings from all reviewers (if two reviewers flag the same issue, keep the more specific suggestion).

**4. Classify each finding:**

**→ IMPLEMENT** if ALL conditions are met:
- Has a specific, actionable fix (not vague)
- Touches ≤ 3 files
- Does NOT require major refactoring or API contract changes
- Low risk of breaking existing tests or callers
- Provides meaningful functional improvement (not purely cosmetic)

**→ DEFER** if ANY condition is met:
- Requires major refactoring (> 3 files or architectural change)
- High risk of breaking existing callers, tests, or deployments
- Purely cosmetic (formatting, naming that doesn't affect clarity)
- Requires coordination with external systems or teams
- Unclear benefit relative to effort
- Would conflict with other in-flight changes

Print the classification: `📋 Slice N: X findings (Y to implement, Z to defer)`

### 3e — Zero findings

If all reviewers found nothing: `✅ Slice N: <name> — Clean (<elapsed>)`. Continue to next slice.

### 3f — All findings deferred

If every finding is DEFER: append to `$LR_TMPDIR/deferred-accumulated.md` in this format:

```markdown
## <slice name>

1. **[file:line]** — <issue description>
   **Why deferred:** <explanation>
```

Update defer counter. Print summary. Continue to next slice.

### 3g — Accumulate or flush implementation batch

Track accumulated IMPLEMENT findings in `$LR_TMPDIR/impl-accumulated.md`. After classifying this slice's findings:

1. Append this slice's IMPLEMENT findings to `$LR_TMPDIR/impl-accumulated.md` (with slice name header).
2. Append this slice's DEFER findings to `$LR_TMPDIR/deferred-accumulated.md`.

**Flush condition**: Invoke `/implement` when **any** of these are true:
- 3 slices worth of IMPLEMENT findings have accumulated
- This is the last slice
- Accumulated IMPLEMENT findings touch more than 10 distinct files (risk of conflicts grows)

**When flushing — invoke /implement:**

Build a task description combining all accumulated IMPLEMENT findings and invoke `/implement` via the Skill tool. **Always prepend `--auto --merge`** (plus `--debug` if `debug_mode=true`) — `--auto` suppresses interactive questions, `--merge` opts into the CI+rebase+merge loop (since `/implement`'s default is now to stop after PR creation). **The `--debug` flag MUST appear before the non-flag word "Implement"** which terminates flag parsing:

```
[--debug] --auto --merge Implement code review findings from loop-review (slices: <slice names>):

## Changes to implement

1. <file:line> — <issue> → <specific fix>
2. ...

## Also: update LOOP_REVIEW_DEFERRED.md

Append the following deferred items:

<accumulated deferred items>
```

**After /implement completes and merges:**
- Clear `$LR_TMPDIR/impl-accumulated.md` and `$LR_TMPDIR/deferred-accumulated.md` (items now committed)
- Increment PR count, update implemented/deferred counters
- Verify you're on `main` with latest: `git checkout main && git pull origin main`

**After /implement fails or bails:**
- Keep accumulated items for next flush
- Log the failure but continue to next slice
- Ensure you're back on main: `git checkout main`

**When NOT flushing**: Print `📦 Slice N findings accumulated (batch X/3). Continuing to next slice.` and proceed.

### 3h — Continue

Move to next slice. Go back to 3a.

## Step 4 — Final Deferred Commit

If there are uncommitted deferred items in `$LR_TMPDIR/deferred-accumulated.md` (because no /implement ran for those slices, or the last /implement failed):

**Lightweight path** (deferred-only updates don't need full /implement):

1. Create a branch: `git checkout -b $USER_PREFIX/loop-review-deferred`
2. Update `LOOP_REVIEW_DEFERRED.md` with the accumulated deferred items
3. Commit: `${CLAUDE_PLUGIN_ROOT}/scripts/git-commit.sh -m "Update LOOP_REVIEW_DEFERRED.md with deferred review suggestions" LOOP_REVIEW_DEFERRED.md`
4. Create PR via `${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh`
5. Post to Slack: `${CLAUDE_PLUGIN_ROOT}/scripts/post-pr-announce.sh --pr <PR_NUMBER>` — parse `SLACK_TS` from output
6. Monitor CI and merge (same loop as the `/implement` CI + Rebase + Merge Loop section)
7. Add :merged: emoji: `${CLAUDE_PLUGIN_ROOT}/scripts/post-merged-emoji.sh --slack-ts "$SLACK_TS"`
8. Cleanup: `${CLAUDE_PLUGIN_ROOT}/scripts/local-cleanup.sh --branch $USER_PREFIX/loop-review-deferred`

If no remaining items, skip this step.

## Step 5 — Final Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Loop Review Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Slices reviewed: M/M
PRs created and merged: X
Total findings: Y (Z implemented, W deferred)

Per-slice breakdown:
  <slice name>: N findings (A impl, B defer)
  ...

Deferred suggestions: see LOOP_REVIEW_DEFERRED.md
```

**Repeat any external reviewer warnings** accumulated in `$LR_TMPDIR/warnings.md` so they are visible at the end. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review timed out on slice 3**`

## Step 6 — Cleanup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$LR_TMPDIR"
```
