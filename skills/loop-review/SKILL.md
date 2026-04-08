---
name: loop-review
description: Systematic code review of entire repository by partitioning into slices, reviewing each with specialized subagents, implementing improvements via /implement, and logging deferred suggestions. Use when the user wants a comprehensive quality sweep, systematic code review, or iterative improvement pass across the whole codebase.
argument-hint: "[partition criteria]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Loop Review

Systematically review the entire codebase by partitioning into slices, reviewing each with specialized code reviewers (2 Claude subagents + 2 Codex + Cursor), implementing improvements via `/implement`, and tracking deferred suggestions in a checked-in document.

**This skill runs fully autonomously** — never ask for user confirmation. Make all implement/defer decisions based on the classification criteria in Step 3d. All sub-skills (`/implement`, `/review`, `/design`, `/relevant-checks`) also run autonomously. **Always pass `--auto --merge` when invoking `/implement`** — `--auto` suppresses interactive question checkpoints in `/design`, and `--merge` opts into the CI+rebase+merge loop that loop-review's batched flow depends on (without `--merge`, `/implement` stops after PR creation and would break loop-review's merge-and-return-to-main expectation).

## Step 0 — Session Setup

### 0a — Preflight

Ensure you are on the `main` branch with a clean working tree and the latest code:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/preflight.sh
```

If it exits non-zero, print the `PREFLIGHT_ERROR` from stdout and abort.

### 0b — Create Session and Tracking Files

Create a session-scoped temp directory:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-session-tmpdir.sh --prefix claude-loop-review
```

Parse the output for `SESSION_TMPDIR`. Set `LR_TMPDIR` = `SESSION_TMPDIR`. Initialize tracking files:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/init-session-files.sh --dir "$LR_TMPDIR"
```

### 0c — Quick External Reviewer Check

Read and follow the **Binary Check** section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`.

Set `codex_available` and `cursor_available` flags for the entire session. If either is unavailable, append the warning to `$LR_TMPDIR/warnings.md`.

## Step 1 — Partition the Repository

### Custom criteria (if `$ARGUMENTS` is non-empty)

Parse `$ARGUMENTS` as the partition strategy:

- `by directory` — same as default below
- `by CLI command` — one slice per CLI command: for each `cli/cmd/<command>.go`, the slice includes that file + its corresponding `handler_<command>.go` in `server/pkg/coordinator/` + any related workflow in `server/pkg/workflows/` + relevant types/validation in `shared/`
- Explicit paths (space-separated) — use those directories as slices
- Any other text — interpret as a natural-language description of how to partition and apply it

### Default: From partition config or auto-discovery

If `$ARGUMENTS` is empty:

1. **Check for `.claude/loop-review-partitions.json`**: If this file exists, read it. It contains an array of `{"name": "<slice name>", "paths": ["<path>", ...]}` objects. Use these as the slices.

2. **Auto-discovery fallback**: If no partition config exists, auto-discover slices by finding directories at depth 1–2 from the repo root that contain source files (`.go`, `.py`, `.ts`, `.rs`, `.sh`). Group them into slices, one per top-level directory. Add a final "Skills & documentation" slice for `.claude/skills/` and top-level `.md` files. Cap at 10 slices; merge smaller directories into an "other" bucket.

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

Use Glob to collect relevant source files in the slice (`.go`, `.md`, `.yaml`, `.sh`). Exclude `*_test.go` from review targets (but tests serve as context for reviewers).

Write the full file list to `$LR_TMPDIR/slice-N-files.txt` (one path per line) for external reviewers to read.

**Sub-slicing (>50 files):** If the slice has more than 50 files, split the file list into sub-slices of ≤50 files each. For each sub-slice, launch 2 Claude subagents (Step 3c) with only that sub-slice's files as `{FILE_LIST}`. External reviewers always receive the full slice file list (one invocation per slice regardless of sub-slicing). After all sub-slices and external reviewers complete, merge all Claude findings from all sub-slices with external reviewer findings before proceeding to Step 3d.

### 3c — Launch up to 5 review subagents in parallel

Launch ALL available reviewers in a **single message**. **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then 2 Codex (second slowest), then 2 Claude subagents (fastest). External reviewers are launched once per slice even when sub-slicing. Claude subagents use the current sub-slice's `{FILE_LIST}` if sub-slicing, or the full file list otherwise. Each must **only report findings — never edit files**.

**Cursor Reviewer (if `cursor_available`):**

Run Cursor **first** in the parallel message (it takes the longest):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool cursor --output "$LR_TMPDIR/cursor-output-slice-N.txt" --timeout 900 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Combine 4 review perspectives: (1) Quality: bugs, logic errors, dead code, duplication, missing error handling. (2) Correctness: off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: broken contracts, thread safety, deployment risks, CI gaps. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Codex-General Reviewer (if `codex_available`):**

Run Codex-General **second** in the parallel message:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "$LR_TMPDIR/codex-general-output-slice-N.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$LR_TMPDIR/codex-general-output-slice-N.txt" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Focus on: quality, bugs, risk, integration, CI. Return numbered findings with file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Codex-Deep-Analysis Reviewer (if `codex_available`):**

Run Codex-Deep-Analysis **third** in the parallel message:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "$LR_TMPDIR/codex-deep-output-slice-N.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$LR_TMPDIR/codex-deep-output-slice-N.txt" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Focus on: correctness, architecture, invariants, contracts. Return numbered findings with file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

**Claude Subagents (2 reviewers, launched last — they finish fastest):**

**Reviewer A — General:**
> Review EXISTING code for this project. Files: {FILE_LIST}. Read each file. Look for: (1) Bugs — logic errors, incorrect conditions, broken control flow. (2) Dead code, unnecessary complexity, duplication. (3) Missing or incorrect error handling. (4) Breaking changes, backward compatibility issues. (5) Thread safety, deployment risks, CI coverage gaps, module interaction issues. Return numbered findings: file:line, issue, specific fix. If none: "No issues found." Do NOT edit files.

**Reviewer B — Deep Analysis:**
> Review EXISTING code for correctness and architecture. Files: {FILE_LIST}. Read each file. Focus on: off-by-one errors, nil/zero-value handling, race conditions, incorrect return values, type mismatches, math errors, error path gaps. Also check: single responsibility violations, implicit contracts between components, unchecked invariants, layer boundary violations, semantic boundary issues. Return numbered findings: file:line, issue, specific fix. If none: "No issues found." Do NOT edit files.

**Monitoring External Reviewers:**

If any external reviewer was launched, follow the **Monitoring External Reviewers** and **Validating External Reviewer Output** sections in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`, using `$LR_TMPDIR/codex-general-output-slice-N.txt`, `$LR_TMPDIR/codex-deep-output-slice-N.txt`, and `$LR_TMPDIR/cursor-output-slice-N.txt` as the output files. Poll for sentinel files: `$LR_TMPDIR/cursor-output-slice-N.txt.done`, `$LR_TMPDIR/codex-general-output-slice-N.txt.done`, and `$LR_TMPDIR/codex-deep-output-slice-N.txt.done`. Only monitor reviewers that were actually launched.

**Critical**: Do NOT read Cursor's output file until `$LR_TMPDIR/cursor-output-slice-N.txt.done` exists. Cursor buffers all stdout — the file is empty (0 bytes) until the process exits. The `.done` sentinel file is the reliable completion signal.

If validation fails (empty output after retry, timeout, or non-zero exit), append a detailed warning (including exit code and elapsed time) to `$LR_TMPDIR/warnings.md`, proceed without that reviewer's findings, and **flip that reviewer's availability flag to false** so it is skipped for all remaining slices (prevents repeated failures).

### 3d — Collect, negotiate, deduplicate, and classify findings

**After ALL reviewers return** (2 Claude subagents AND any launched external reviewers), proceed:

**1. Collect** all findings from Claude subagents and validated external reviewer output.

**2. Negotiate** with external reviewers (if they produced findings):

Follow the **Negotiation Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`, using `$LR_TMPDIR` as the tmpdir, with `max_rounds=1`. With 2 Codex instances (Codex-General and Codex-Deep-Analysis), negotiate with each separately using distinct prompt/output file paths (e.g., `codex-general-negotiation-prompt.txt` / `codex-general-negotiation-output.txt` and `codex-deep-negotiation-prompt.txt` / `codex-deep-negotiation-output.txt`). Accept findings unless factually incorrect or contradicting CLAUDE.md.

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

If all reviewers found nothing: `✅ Slice N: <name> — Clean`. Continue to next slice.

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

Build a task description combining all accumulated IMPLEMENT findings and invoke `/implement` via the Skill tool. **Always prepend `--auto --merge`** — `--auto` suppresses interactive questions, `--merge` opts into the CI+rebase+merge loop (since `/implement`'s default is now to stop after PR creation):

```
--auto --merge Implement code review findings from loop-review (slices: <slice names>):

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
3. Commit: `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-commit.sh -m "Update LOOP_REVIEW_DEFERRED.md with deferred review suggestions" LOOP_REVIEW_DEFERRED.md`
4. Create PR via `${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-pr.sh`
5. Post to Slack: `${CLAUDE_PLUGIN_ROOT}/scripts/larch/post-pr-announce.sh --pr <PR_NUMBER>` — parse `SLACK_TS` from output
6. Monitor CI and merge (same loop as the `/implement` CI + Rebase + Merge Loop section)
7. Add :merged: emoji: `${CLAUDE_PLUGIN_ROOT}/scripts/larch/post-merged-emoji.sh --slack-ts "$SLACK_TS"`
8. Cleanup: `${CLAUDE_PLUGIN_ROOT}/scripts/larch/local-cleanup.sh --branch $USER_PREFIX/loop-review-deferred`

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
${CLAUDE_PLUGIN_ROOT}/scripts/larch/cleanup-tmpdir.sh --dir "$LR_TMPDIR"
```
