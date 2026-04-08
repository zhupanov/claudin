---
name: implement
description: Full end-to-end feature workflow — design, implement, code review, version bump, PR, Slack announce, and cleanup. Pass --merge to additionally run the CI+rebase+merge loop and delete the local branch after merging.
argument-hint: "[--quick] [--auto] [--merge] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Implement Skill

Full end-to-end feature implementation: design, plan review, code, validate, commit, code review, validate, commit, code flow diagram, version bump, PR, CI monitor, Slack announce, and cleanup. With `--merge`: also runs the CI+rebase+merge loop, adds the :merged: emoji, deletes the local branch, and verifies main.

The feature to implement is described by `$ARGUMENTS` after flag stripping.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, save the remainder as `FEATURE_DESCRIPTION` — use this (not raw `$ARGUMENTS`) whenever the human-readable feature description is needed (e.g., PR body, design invocation, commit messages).

- `--quick`: Set a mental flag `quick_mode=true`. When `quick_mode=true`: Step 1 skips `/design` (this skill creates the branch and an inline plan directly), Step 5 skips `/review` (a simplified one-round review with 2 Claude subagents only — no external reviewers, no voting panel), and Step 7a skips the Code Flow Diagram. All other steps (CI wait, Slack, cleanup) run normally. The `--merge` opt-in is independent of `--quick`.
- `--auto`: Set a mental flag `auto_mode=true`. When `auto_mode=true`: (a) forward `--auto` to `/design` invocation in Step 1, suppressing `/design`'s interactive question checkpoints; (b) suppress this skill's own opportunistic questions in Step 2; (c) in Step 12, when merge conflicts require user input for uncertain resolutions, suppress `AskUserQuestion` and use best-effort resolution instead (bailing if confidence is too low). When `--quick` is also set and `/design` is skipped, `--auto` still suppresses Step 2 questions. The default (no `--auto`) enables interactive questions.
- `--merge`: Set a mental flag `merge=true`. When `merge=true`, Steps 12–15 run (CI+rebase+merge loop, :merged: emoji, local cleanup, and main verification). When `merge=false` (default), these steps are skipped — the PR is created and the workflow stops after the initial CI wait, Slack announcement, rejected findings report, final report, and temp cleanup.
- `--no-merge`: **Deprecated** — recognized for backward compatibility but treated as a no-op (the new default already skips merge steps). When this flag is encountered, print: `**ℹ '--no-merge' is now the default and no longer needed; the flag is recognized as a no-op for backward compatibility.**`
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill and will be forwarded to `session-setup.sh` via `--caller-env` and to `/design` via `--session-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).

## Progress Reporting

**Every step MUST print clearly visible status lines** so the user can instantly see where execution is at. Use distinct emoji prefixes:

- Print a **start line** when entering a step: e.g., `🛠️ Step 2 — Implementing feature...`
- Print a **completion line** when done: e.g., `✅ Step 2 — Implementation complete`
- For long-running steps, print **intermediate progress**: e.g., `⏳ Step 12 — CI running (2m elapsed), main unchanged`

Suggested emoji palette (use consistently):
| Step | Emoji | Description |
|------|-------|-------------|
| 0 | 🔧 | Session setup |
| 1 | 📐 | Ensure design plan |
| 🔃 | 🔃 | Rebase onto latest main |
| 2 | 🛠️ | Implementation |
| 3 | 🧹 | Relevant checks (first pass) |
| 4 | 💾 | First commit |
| 5 | 🔍 | Code review |
| 6 | 🧹 | Relevant checks (second pass) |
| 7 | 💾 | Second commit |
| 7a | 🗺️ | Code flow diagram |
| 8 | 🏷️ | Version bump |
| 9 | 🚀 | Create PR |
| 10 | 🔄 | CI monitor (initial wait for green) |
| 11 | 📋 | Slack announcement |
| 12 | 🔁 | CI + rebase + merge loop |
| 13 | ✨ | :merged: emoji |
| 14 | 🧹 | Local cleanup |
| 15 | ✅ | Verify main |
| 16 | 📊 | Rejected code review findings report |
| 17 | 📊 | Final report |
| 18 | 🏁 | Final cleanup + warnings |

## Step 0 — Session Setup

Run the shared session setup script. If `SESSION_ENV_PATH` is non-empty (passed via `--session-env`), include `--caller-env` to reuse already-discovered values:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/session-setup.sh --prefix claude-implement --skip-branch-check [--caller-env "$SESSION_ENV_PATH"]
```

`--skip-branch-check` is required so that the inlined Step 1 user-branch decision logic (`IS_USER_BRANCH=true` paths) is reachable. Without it, `preflight.sh` would refuse to run unless the user is on a clean `main` branch, making Step 1's branch-resume paths dead code.

Only include `--caller-env "$SESSION_ENV_PATH"` if `SESSION_ENV_PATH` is non-empty.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`. Set:
- `IMPLEMENT_TMPDIR` = `SESSION_TMPDIR`
- If `SLACK_OK=false`, print: `**⚠ Slack is not fully configured (<SLACK_MISSING> not set). Slack announcement (Step 11) and :merged: emoji (Step 13) will be skipped.**` Set a mental flag `slack_available=false`.
- If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository name. CI monitoring (Steps 10, 12) and merge (Step 12b) will be skipped.**` Set a mental flag `repo_unavailable=true`.

### Write Session Env for Child Skills

Write the discovered values to `$IMPLEMENT_TMPDIR/session-env.sh` so they can be forwarded to `/design`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/write-session-env.sh --output "$IMPLEMENT_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value>
```

This file will be passed to `/design` via `--session-env` in Step 1.

## Execution Issues Tracking

Throughout execution, log noteworthy issues to `$IMPLEMENT_TMPDIR/execution-issues.md`. This file captures problems worth investigating later but that do not block the current task. **Any step** may append to this file when an issue is encountered.

**When to log** (non-exhaustive):
- Pre-existing code issues discovered but not fixed (outside current task scope)
- Tool invocations that failed or produced unexpected results
- Instances where Claude had to ask for user permission rather than operating autonomously
- External reviewer failures, timeouts, or empty outputs (Cursor, Codex)
- CI failures that required workarounds or transient retries
- Any `⚠` warning printed during execution that does not fall under any of the named categories above

**Entry format**: Append entries grouped by category. If the category header already exists in the file, insert the new bullet at the end of that category's bullet list (before the next category header or end of file). If the category header does not exist yet, add the header and bullet at the end of the file.

```markdown
### <Category>
- **Step <N>**: <description with enough detail for subsequent investigation>
```

**Categories** (use these exact headers — entries within a category are listed chronologically, but categories must not be intermixed):
- `Pre-existing Code Issues` — code problems discovered but not fixed because they were outside the scope of the current task
- `Tool Failures` — any tool invocations that failed or produced unexpected results
- `Permission Prompts` — instances where Claude had to ask for user permission rather than operating autonomously
- `External Reviewer Issues` — failures, timeouts, or empty outputs from Cursor or Codex
- `CI Issues` — CI failures, transient retries, or infrastructure problems
- `Warnings` — `⚠` warnings printed during execution that do not fall under another category (e.g., version bump skipped, design-phase omissions, missing configuration). Do NOT duplicate warnings already logged under a more specific category.

## Step 1 — Ensure Design Plan Exists

First, determine the user's branch prefix by running the branch check script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-branch.sh --check
```

Parse the output for `CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, and `USER_PREFIX`.

### Ensure local main is fresh before branch creation

**This block runs only when `CURRENT_BRANCH == "main"`.** Detached HEAD also reports `IS_MAIN=true` from `create-branch.sh --check`, but a rebase on detached HEAD would fail (`rebase-push.sh` errors with "Not on a branch"); fall through to the mode-specific branch creation logic below so a new branch can be created from `origin/main`. Also skip this block for `IS_USER_BRANCH=true` (we are not creating a branch from main — the feature branch rebase at the end of Step 1 handles freshness) and for the non-main/non-user-branch warning path (we are on some other branch, and `create-branch.sh --branch` will fetch and create the new branch directly from `origin/main`).

Print: `🔃 Ensuring local main is up to date before branching...`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --no-push
```

`--skip-if-pushed` is intentionally **not** used here: `main` is always on origin, so that flag would always short-circuit. The `SKIPPED_ALREADY_FRESH=true` optimization makes this call cheap (fetch + ancestor check) when local `main` is already at `origin/main`.

If the script exits non-zero, print: `**⚠ Failed to ensure local main is fresh. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_FRESH=true`, print: `⏩ Local main already at latest — no update needed.`
- Otherwise, print: `✅ Local main rebased onto latest origin/main.`

### Quick mode (`quick_mode=true`)

Skip `/design` entirely. Handle branch creation directly, then produce an inline implementation plan.

**Branch handling** (same logic as `/design` Step 1, replicated here since `/design` is skipped):
- If `IS_MAIN=true`: Derive a short kebab-case branch name from the feature description. Create it via `${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-branch.sh --branch <USER_PREFIX>/<branch-name>`.
- If `IS_USER_BRANCH=true`: Verify the branch name (`CURRENT_BRANCH`) aligns with the requested feature. If it appears unrelated (different feature name, unrelated commits), print a warning: `**⚠ Current branch '<branch-name>' may not match the requested feature. Creating a new branch from main.**` and create a new branch. Otherwise, use the existing branch.
- Otherwise (non-main, non-user branch): Print a warning: `**⚠ Currently on branch '<branch-name>' which doesn't match the expected '<USER_PREFIX>/*' pattern. Creating a new branch from main.**` and create a new branch.

**Inline design**: Research the codebase (read relevant files, grep for patterns), then produce a concrete implementation plan under a `## Implementation Plan` header. This plan should include files to modify, approach, and edge cases — the same content `/design` would produce, but without collaborative sketches, plan review, or voting. Print: `⚡ Step 1 — Quick mode: skipped /design, produced inline plan.`

Proceed to Step 2.

### Normal mode (`quick_mode=false`)

**Decision logic**:
- If `IS_USER_BRANCH=true` **AND** a reviewed implementation plan is visible in the conversation context above: The plan was created by a prior `/design` invocation in this session. Proceed to Step 2.
- If `IS_USER_BRANCH=true` but **no** implementation plan is visible in the conversation context: Invoke the `/design` skill with `--session-env $IMPLEMENT_TMPDIR/session-env.sh` prepended to the feature description to create a plan on the current branch. **If `auto_mode=true`, also prepend `--auto`** so `/design` suppresses interactive questions. After `/design` completes, proceed to Step 2.
- If on `main` or empty (detached HEAD) or any non-user branch: No design plan exists yet. Invoke the `/design` skill with `--session-env $IMPLEMENT_TMPDIR/session-env.sh` prepended to the feature description to create a branch and design the plan. **If `auto_mode=true`, also prepend `--auto`** so `/design` suppresses interactive questions. After `/design` completes, proceed to Step 2.

### Capture branch name (`BRANCH_NAME`)

After Step 1's branch resolution (whether quick mode or normal mode, whether a new branch was created or an existing one was reused), capture the resolved branch name into a `BRANCH_NAME` variable:

```bash
git symbolic-ref --short HEAD
```

Save the output as `BRANCH_NAME`. This variable is referenced later by Step 14 (`local-cleanup.sh --branch $BRANCH_NAME`) and by Steps 4, 14, and 18 status messages that mention the development branch. **It is the responsibility of Step 1 to ensure `BRANCH_NAME` accurately reflects the branch where implementation will happen** — re-run `git symbolic-ref --short HEAD` after `/design` returns (in normal mode) since `/design` may have switched branches.

### Rebase onto latest main (before implementation)

**This rebase runs unconditionally in both quick and normal mode** — freshness is beneficial regardless of mode. Both the quick-mode "Proceed to Step 2" and normal-mode "proceed to Step 2" instructions above lead here before entering Step 2.

Print: `🔃 Rebasing onto latest main before starting implementation...`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If the stdout contains `SKIPPED_ALREADY_PUSHED=true`, print: `⏩ Rebase skipped — branch already pushed to origin.`
- Else if the stdout contains `SKIPPED_ALREADY_FRESH=true`, print: `⏩ Rebase skipped — already at latest main.`
- Otherwise, print: `✅ Rebased onto latest main.`

## Step 2 — Implement the Feature

**Opportunistic questions** (`auto_mode=false` only): Before starting edits, if the implementation plan leaves genuinely ambiguous choices (e.g., naming conventions, test strategy, which of two valid approaches to use), batch them into a single `AskUserQuestion` call with 1-4 questions. Only ask when the ambiguity cannot be resolved from the plan, codebase, or CLAUDE.md. When `auto_mode=true`, proceed with best judgment — do not ask. Material answers that change scope or approach should be noted for the "Implementation Deviations" section.

Implement the feature following the (reviewed) plan from the `/design` phase. Follow all guidelines in CLAUDE.md:
- Read existing code before modifying
- Match existing style and patterns
- Avoid code duplication — search for reusable code first
- Don't over-engineer

## Step 3 — Relevant Checks (first pass)

Invoke `/relevant-checks` to run validation checks relevant to the modified files. If checks fail, diagnose and fix the issue, then re-invoke `/relevant-checks` to confirm the fix.

## Step 4 — First Commit (implementation)

Stage and commit all changed files using the wrapper script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-commit.sh -m "<descriptive commit message>" <specific-files>
```

The commit message should describe WHAT was implemented and WHY, not HOW.

### Rebase onto latest main (after implementation commit)

Print: `🔃 Rebasing onto latest main after implementation commit...`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If the stdout contains `SKIPPED_ALREADY_PUSHED=true`, print: `⏩ Rebase skipped — branch already pushed to origin.`
- Else if the stdout contains `SKIPPED_ALREADY_FRESH=true`, print: `⏩ Rebase skipped — already at latest main.`
- Otherwise, print: `✅ Rebased onto latest main.`

## Step 5 — Code Review

### Quick mode (`quick_mode=true`)

Skip `/review`. Instead, run a simplified one-round review:

1. Gather the diff using the context script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/gather-branch-context.sh --output-dir "$IMPLEMENT_TMPDIR"
   ```
   Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log.
2. Launch **2 Claude subagent reviewers** (general, deep-analysis) using the same reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/reviewer-templates.md` with these variable bindings: `{REVIEW_TARGET}` = `"code changes"`, `{CONTEXT_BLOCK}` = the commit log + file list + full diff, `{OUTPUT_INSTRUCTION}` = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix"`. **No Codex, no Cursor, no external reviewers. No competition notice** (there is no voting panel in quick mode).
3. Collect findings from all 2 subagents. Deduplicate.
4. **Main agent decides**: Evaluate each finding and unilaterally accept or reject it. No voting panel. Accept findings that identify genuine bugs, logic errors, or important improvements. Reject trivial style nits or speculative concerns.
5. Implement accepted fixes. Run `/relevant-checks` if files changed.
6. **One round only** — no re-review loop.
7. For rejected findings, write them to `$IMPLEMENT_TMPDIR/rejected-findings.md` using the same format as normal mode (see below), so Step 16 and PR body sections work unchanged.

Print: `🔍 Step 5 — Quick mode: simplified review (2 Claude subagents, 1 round, no voting).`

### Normal mode (`quick_mode=false`)

**IMPORTANT: Code review must ALWAYS be invoked via `/review`. Never skip this step regardless of the nature of the changes — whether code, skills, documentation, data files, or configuration. All changes require full review.**

Invoke the `/review` skill. This launches 2 parallel Claude subagent reviewers (general, deep-analysis) plus two Codex and Cursor reviewers (if available), implements their suggestions recursively until clean.

### Track Rejected Code Review Findings

After the code review completes (whether `/review` in normal mode or the simplified review in quick mode), examine the final output. For any **in-scope** findings that were not accepted (not enough YES votes in normal mode — whether rejected or exonerated — or rejected by the main agent in quick mode), append each to `$IMPLEMENT_TMPDIR/rejected-findings.md` using this format. **Do not include non-promoted OOS items** — those are reported separately in the "Out-of-Scope Observations" PR body section:

```markdown
### [Code Review] <Reviewer Name>
**Finding**: <thorough description of the finding — include the specific file(s) and line(s) affected, what the reviewer identified as the issue, and what change they suggested. Must be detailed enough to serve as an actionable TODO item if later prioritized. Do NOT use a terse one-liner — a reader who has never seen the original review must be able to understand the issue and act on it.>
**Reason not implemented**: <complete justification for why this finding was not addressed — include the specific technical reasoning, any relevant context about project conventions or design decisions, and why the current code is acceptable despite the finding. Do NOT abbreviate — preserve all important details from the evaluation.>
```

## Step 6 — Relevant Checks (second pass)

**Conditional**: Check if the code review step (Step 5) actually modified any files (applies in both normal and quick mode):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/implement/scripts/check-review-changes.sh
```

Parse the output for `FILES_CHANGED`. If `FILES_CHANGED=false`, print: `⏩ Step 6 — Skipping second validation — review made no changes.` and skip Steps 6 and 7 (but NOT Step 7a — the Code Flow Diagram step runs unconditionally).

If files **did change**, invoke `/relevant-checks` to ensure review fixes didn't introduce new issues. If checks fail, diagnose and fix, then re-invoke `/relevant-checks`.

## Step 7 — Second Commit (review fixes)

If any files changed during review/checks (Steps 5–6), stage and commit them:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-commit.sh -m "Address code review feedback" <specific-files>
```

If no files changed (review found no issues), skip this commit.

### Rebase onto latest main (after review fixes commit)

**Conditional**: Only run this rebase if `FILES_CHANGED=true` from Step 6's `check-review-changes.sh` output (meaning Step 7 created a commit). If Steps 6–7 were skipped (no review changes), skip this rebase — the pre-Step-8 rebase provides the safety net.

Print: `🔃 Rebasing onto latest main after review fixes commit...`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If the stdout contains `SKIPPED_ALREADY_PUSHED=true`, print: `⏩ Rebase skipped — branch already pushed to origin.`
- Else if the stdout contains `SKIPPED_ALREADY_FRESH=true`, print: `⏩ Rebase skipped — already at latest main.`
- Otherwise, print: `✅ Rebased onto latest main.`

## Step 7a — Code Flow Diagram

Print: `🗺️ Step 7a — Generating code flow diagram...`

**This step runs unconditionally after Step 7** — regardless of whether Steps 6-7 were skipped due to no review changes.

**If `quick_mode=true`**: Print `⏩ Step 7a — Skipped (quick mode).` and proceed to Step 8.

**If `quick_mode=false`**: Generate a mermaid Code Flow Diagram based on the actual committed implementation. The diagram should focus on **runtime behavior** — function call sequences, data flow, or control flow through the implemented code paths. Do NOT duplicate the Architecture Diagram's structural/component view.

Choose the most appropriate mermaid diagram type for the implementation (e.g., `sequenceDiagram`, `flowchart`, `stateDiagram`, `graph`, etc.). The diagram type is flexible — pick whatever best communicates the code flow.

Print the diagram under a `## Code Flow Diagram` header with a mermaid code fence:

```
## Code Flow Diagram

```mermaid
<diagram content>
```
```

**If diagram generation succeeds**, print: `✅ Step 7a — Code flow diagram generated.`

**If diagram generation fails** (e.g., the implementation is too abstract to diagram meaningfully), print: `**⚠ Step 7a — Code flow diagram generation failed. Proceeding without diagram.**` Log this warning to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `Warnings` category.

### Rebase onto latest main (before version bump)

This rebase runs as a final safety net before the version bump and PR creation, even if a previous rebase just ran. It ensures the branch is as fresh as possible before the version bump becomes the last commit. Exception: if the branch is already on origin (e.g., re-run on an existing PR branch), the `--skip-if-pushed` flag causes this rebase to be skipped — freshness of already-pushed branches is the CI+rebase+merge loop's responsibility (Step 12).

Print: `🔃 Rebasing onto latest main before version bump...`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If the stdout contains `SKIPPED_ALREADY_PUSHED=true`, print: `⏩ Rebase skipped — branch already pushed to origin.`
- Else if the stdout contains `SKIPPED_ALREADY_FRESH=true`, print: `⏩ Rebase skipped — already at latest main.`
- Otherwise, print: `✅ Rebased onto latest main.`

## Step 8 — Version Bump

Check if the repo has a `/bump-version` skill and capture commit count:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/check-bump-version.sh --mode pre
```

Parse the output for `HAS_BUMP` and `COMMITS_BEFORE`.

**If `HAS_BUMP=false`**: Print `**⚠ VERSION BUMP SKIPPED: No /bump-version skill found at .claude/skills/bump-version/SKILL.md. To enable automatic version bumps, create a /bump-version skill in this repo. The skill should determine the current version, classify the bump type, compute the new version, edit the version file, and commit.**` and skip to Step 9.

**If `HAS_BUMP=true`**:

1. Invoke `/bump-version` via the Skill tool.
2. Verify a new commit was created:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
   ```
   Parse for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`. If `VERIFIED=false`, print: `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`

**Important**: There must be exactly ONE version bump per PR, and it must be the LAST commit before creating the PR. Proceed immediately to Step 9 after `/bump-version` returns — no commits may occur between.

## Step 9 — Create PR

### 9a — Prepare PR body

Write the PR body to a temp file at `$IMPLEMENT_TMPDIR/pr-body.md`. The PR body is the single source of truth for all report content — there are no separate report files.

```markdown
## Summary
<1-3 bullet points in past tense describing what was changed and why (e.g., "Refactored X to improve Y", not "Refactor X to improve Y")>

<details><summary>Architecture Diagram</summary>

<the Architecture Diagram (mermaid code fence) from the /design phase's Step 3b output visible in conversation context above. Copy the mermaid code fence as printed. If the Architecture Diagram is not visible in conversation context (e.g., /design was interrupted, context was truncated, or this skill was run in --quick mode without /design), write "Architecture diagram not available.">

</details>

<details><summary>Code Flow Diagram</summary>

<the Code Flow Diagram (mermaid code fence) from Step 7a output above. Copy the mermaid code fence as printed. If the Code Flow Diagram was not generated (generation failed or quick mode), write "Code flow diagram not available.">

</details>

<details><summary>Goal</summary>

<bullet points in infinitive/base-form verb tense capturing the problem statement, user intent, and success criteria — the "why and what," not the "how" (e.g., "Add support for X", not "Added support for X"). Draw from all available conversation context: the original feature description (FEATURE_DESCRIPTION), collaborative sketch synthesis, the final/revised implementation plan, plan review feedback, and any additional human input. Organize as a hierarchical bullet subtree: group minor tasks under their parent major tasks (more than 1 level deep) rather than a flat list. Preserve all substantive details from the original request.>

</details>

<details><summary>Test plan</summary>

<bulleted checklist of testing steps>

</details>

<details><summary>Final Design</summary>

<the revised implementation plan from the /design phase, or the original plan if no revisions were needed. If /design was interrupted or not visible in conversation context, omit this entire <details> block and print: **⚠ Design-phase sections omitted — /design may have been interrupted.**>

</details>

<details><summary>Rejected Plan Review Suggestions</summary>

<rejected plan review findings from the /design phase's Step 4 output visible in conversation context above. If none were rejected, write "All plan review suggestions were implemented." If /design was interrupted and these findings are not visible in context, omit this entire <details> block.>

</details>

<details><summary>Implementation Deviations</summary>

<compare the plan to what was actually implemented. List any deviations, or write "No deviations from the plan." If no plan exists, write "Design phase did not complete — no plan to compare against.">

</details>

<details><summary>Rejected Code Review Suggestions</summary>

<content from $IMPLEMENT_TMPDIR/rejected-findings.md if it exists and is non-empty, otherwise "All code review suggestions were implemented.">

</details>

<details><summary>Plan Review Voting Tally</summary>

<the per-finding vote breakdown and Reviewer Competition Scoreboard from the /design phase's Step 3 voting output visible in conversation context above. Copy the vote breakdown (table or list showing each finding's votes and accepted/rejected result) and the Reviewer Competition Scoreboard as they were printed. If voting was skipped due to insufficient voters, write "Voting was skipped (insufficient voters)." If no findings were raised (all reviewers reported no issues), write "No findings were raised — voting was not needed." If the voting tally is not visible in conversation context (e.g., /design was interrupted or context was truncated), write "Voting tally not available.">

</details>

<details><summary>Code Review Voting Tally (Round 1)</summary>

<the per-finding vote breakdown from the /review phase's Step 3d (round 1 summary) and the Reviewer Competition Scoreboard from Step 4 (Final Summary) visible in conversation context above. Only include round 1 voting results — rounds 2+ findings are auto-accepted without voting and are not part of this section. Copy the vote breakdown (table or list showing each finding's votes and accepted/rejected result) and the Reviewer Competition Scoreboard as they were printed. If voting was skipped due to insufficient voters, write "Voting was skipped (insufficient voters)." If no findings were raised, write "No findings were raised — voting was not needed." If the voting tally is not visible in conversation context, write "Voting tally not available.">

</details>

<details><summary>Out-of-Scope Observations</summary>

<non-promoted out-of-scope observations from both plan review (/design Step 3) and code review (/review Step 3c.1) visible in conversation context above. These are pre-existing issues or concerns beyond the PR's scope that reviewers surfaced for future attention. Copy the non-promoted OOS items as they were listed, including the reviewer attribution and description. If no OOS observations were raised, write "No out-of-scope observations were raised." If the observations are not visible in conversation context, write "Out-of-scope observations not available.">

</details>

<details><summary>Execution Issues</summary>

<content from $IMPLEMENT_TMPDIR/execution-issues.md if it exists and is non-empty, otherwise "No execution issues encountered.">

</details>

<details><summary>Run Statistics</summary>

| Metric | Value |
|--------|-------|
| Plan review findings | <N> accepted, <N> rejected |
| Code review rounds | <N> |
| Code review findings | <N> accepted, <N> rejected |
| Warnings logged | <N> |
| Pre-existing issues noticed | <N> |
| External reviewers | Cursor: <✅/❌>, Codex: <✅/❌> |

</details>

Generated with [Claude Code](https://claude.com/claude-code)
```

Populate Run Statistics from conversation context: count accepted/rejected findings from /design Step 3 output, count review rounds and findings from /review output, count entries in `execution-issues.md` by category, and note external reviewer availability from /design and /review preflight checks. Note: Run Statistics aggregates (N accepted, N rejected) intentionally coexist with the detailed per-finding tally tables in the voting tally sections — they serve different purposes (quick summary vs. full audit trail).

**Voting tally extraction guidance**: For the Plan Review Voting Tally, extract the per-finding vote breakdown and Reviewer Competition Scoreboard printed during `/design` Step 3's voting output. The vote breakdown may be a table or a list — extract whatever format was printed. The Reviewer Competition Scoreboard follows the format defined in `voting-protocol.md`. For the Code Review Voting Tally, extract the per-finding vote breakdown from `/review` Step 3d (the round 1 summary output) and the Reviewer Competition Scoreboard from `/review` Step 4 (Final Summary). Step 3d prints the per-finding details; Step 4 prints the consolidated scoreboard.

**Quick-mode PR body guidance** (`quick_mode=true`): When populating the PR body in quick mode, use these section-specific rules:
- **Architecture Diagram**: Write "Quick mode — architecture diagram skipped."
- **Code Flow Diagram**: Write "Quick mode — code flow diagram skipped."
- **Final Design**: Use the inline implementation plan produced in Step 1 (not from `/design`).
- **Rejected Plan Review Suggestions**: Write "Quick mode — no plan review was conducted."
- **Plan Review Voting Tally**: Write "Quick mode — no plan review voting."
- **Code Review Voting Tally (Round 1)**: Write "Quick mode — no voting panel. Main agent reviewed findings from 2 Claude subagents."
- **Implementation Deviations**: Compare implementation to the inline plan (same as normal mode).
- **Out-of-Scope Observations**: Write "Quick mode — no out-of-scope observations collected."
- **Run Statistics**: Set "Plan review findings" to "N/A (quick mode)", "External reviewers" to "N/A (quick mode)". Code review findings should reflect the quick review results.

### 9b — Create PR via script

Run the `create-pr.sh` script with a concise title (under 70 chars):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/create-pr.sh --title "<title>" --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
```

Parse the output for `PR_NUMBER`, `PR_URL`, `PR_TITLE`, and `PR_STATUS`. The script handles pushing the branch, detecting existing PRs, and creating new ones with `--assignee @me`. `PR_STATUS` is `created` for new PRs or `existing` for already-open PRs. Save `PR_STATUS` — it is used in Step 11 to decide whether to post to Slack.

**If `create-pr.sh` exits non-zero**, print the error from its output and abort. Do not proceed to Steps 10–18.

**If `PR_STATUS=existing`**: The PR body was not updated by `create-pr.sh`. Update it now:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
```

Print the PR URL when done. Save `PR_NUMBER`, `PR_URL`, and `PR_TITLE` for use in Steps 10–15.

## Step 10 — CI Monitor (initial wait for green)

**If `repo_unavailable=true`**: Print `⏭️ Step 10 — Skipped (repository name could not be determined).` and proceed to Step 11.

Wait for CI to go green so the Slack announcement (Step 11) links to a PR with passing CI. This step does **NOT merge** — Step 12 is the merge-aware loop that handles main advancement and merging.

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION`
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries (reset after rebase, code fix, or different failure)

**Wait for CI** using the `ci-wait.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=merge`**: CI passed and branch is up-to-date. Print `✅ Step 10 — CI passed!` and proceed to Step 11. **Do NOT merge here** — Step 12 handles merging.

   - **`ACTION=already_merged`**: PR was merged externally during CI wait. Print `✅ Step 10 — PR was merged externally.` and proceed to Step 11. (Step 12 will detect `already_merged` again and skip the merge loop.)

   - **`ACTION=rebase`**: Main advanced. Run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh`. On exit 0: increment `rebase_count` and `iteration`, reset `transient_retries`, re-invoke `ci-wait.sh`. On exit 1 (conflicts): run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-rebase-abort.sh`, print warning, and proceed to Step 11 (the merge loop in Step 12 will encounter the same conflict and apply the full Conflict Resolution Procedure with reviewer panel validation). On exit 2: retry once, then proceed to Step 11. On exit 3: proceed to Step 11.

   - **`ACTION=rebase_then_evaluate`**: Run rebase first (same as above), then fall through to evaluate the CI failure.

   - **`ACTION=evaluate_failure`**: Use `FAILED_RUN_ID` to evaluate:
     1. **Transient failure** (runner provisioning, Docker pull rate limit, "hosted runner lost communication", etc.): If `transient_retries < 2`, run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/sleep-seconds.sh 60`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Parse output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Otherwise increment `transient_retries`, re-invoke `ci-wait.sh`. If `transient_retries >= 2`, treat as real failure.
     2. **Real CI failure**: Run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Diagnose the issue, fix it, run `/relevant-checks`, stage and commit using `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-commit.sh -m "Fix CI failure" <fixed-files>`, push. Increment `fix_attempts`. Re-invoke `ci-wait.sh`.

   - **`ACTION=bail`**: Print `BAIL_REASON`. Print `**⚠ Step 10 — CI monitoring bailed. PR may have failing CI.**` and proceed to Step 11.

**Execution issues**: Log any CI failures, transient retries, or bail events to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `CI Issues` category.

After handling any non-terminal action (rebase, evaluate_failure), **re-invoke `ci-wait.sh`** with updated counter values.

## Step 11 — Post Slack Announcement

**If `slack_available=false`**: Print `⏭️ Step 11 — Skipped (Slack not configured).` Set `SLACK_TS` to empty and proceed to the post-execution PR body refresh below.

**If `PR_STATUS=existing`**: Print `⏭️ Step 11 — Skipped (PR already existed, avoiding duplicate Slack post). Run post-pr-announce.sh --pr <PR-NUMBER> manually to post the announcement.` Set `SLACK_TS` to empty and proceed to the post-execution PR body refresh below.

**Otherwise** (`slack_available=true` and `PR_STATUS=created`):

Post the PR to Slack using the shared script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/post-pr-announce.sh --pr <PR-NUMBER>
```

Parse the output for `SLACK_TS=<value>` (emitted by `post-pr-announce.sh` — keep in sync).

**If the script exits non-zero or `SLACK_TS` is empty**: Print `**⚠ Slack announcement failed. Continuing.**` Set `SLACK_TS` to empty. Log the failure to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `Tool Failures` category.

Save `SLACK_TS` for use in Step 13 (the :merged: emoji step).

### Post-execution PR body refresh

**This refresh runs unconditionally after all Step 11 branches converge — including when Slack was skipped (`slack_available=false`) or when `PR_STATUS=existing`. All Step 11 early-exit paths must reach this section before proceeding to Step 12.**

If `$IMPLEMENT_TMPDIR/execution-issues.md` exists and is non-empty, update the PR body to reflect the final execution issues (which may include issues logged during Steps 10–11, after the initial PR body was written):

1. Fetch the current live PR body using the read script (do NOT re-read `$IMPLEMENT_TMPDIR/pr-body.md` — the live body may differ from the local copy):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md` to get the current body text.
2. Replace the entire inner content of the `<details><summary>Execution Issues</summary>...</details>` block with the full current contents of `$IMPLEMENT_TMPDIR/execution-issues.md`, preserving the blank lines after the opening tag and before the closing `</details>` (required for GitHub Markdown rendering). If the `<details><summary>Execution Issues</summary>` block is not found in the fetched body, print `**⚠ Execution Issues block not found in live PR body. Skipping refresh.**` and skip the update.
3. Write the result to `$IMPLEMENT_TMPDIR/pr-body.md`
4. Update the PR:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```

If `execution-issues.md` does not exist or is empty, skip this refresh.

## Step 12 — CI + Rebase + Merge Loop

**If `merge=false`**: Print `⏭️ Step 12 — Skipped (--merge flag not set). PR created but not merged.` and skip to Step 16.

**If `repo_unavailable=true`**: Print `⏭️ Step 12 — Skipped (repository name could not be determined).` and skip to Step 16.

Monitor CI and the main branch **in parallel**. The key optimization: don't wait for CI to finish before checking if main has advanced.

### 12a — Poll Loop

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION` (updated by the script during wait cycles)
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries, managed locally (used only in Step 12c; when this exceeds 2, treat as real failure and increment `fix_attempts`)

**Wait for CI** using the `ci-wait.sh` script, which polls `ci-status.sh` + `ci-decide.sh` internally and prints compact dot-based progress to stderr:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes, matching the script's 1800s default + grace).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=rebase`**: Print a context-specific message based on `CI_STATUS`: if `CI_STATUS=pass`, print `🔄 CI passed but main advanced — rebasing...`; if `CI_STATUS=pending`, print `🔄 Main advanced while CI running — rebasing...` → run `rebase-push.sh` (see rebase handling below) → on success: increment `rebase_count`, increment `iteration`, reset `transient_retries` → re-invoke `ci-wait.sh`.

   - **`ACTION=merge`**: Print `✅ CI passed, main up-to-date — merging!` → proceed to **12b**.

   - **`ACTION=already_merged`**: Print `✅ PR was force-merged externally — skipping CI wait and merge.` → skip **12b** (no merge needed) and proceed directly to Step 13. The PR counts as successfully merged for Steps 13–15.

   - **`ACTION=rebase_then_evaluate`**: Run rebase first (same as `rebase` above), then on success fall through to evaluate the CI failure as in **12c**.

   - **`ACTION=evaluate_failure`**: Evaluate the CI failure → **12c**.

   - **`ACTION=bail`**: Print `BAIL_REASON` and bail out → **12d**.

After handling any non-merge/non-bail action (rebase, evaluate_failure, etc.), **re-invoke `ci-wait.sh`** with updated counter values. The adaptive sleep interval is handled by the caller: sleep 30s before re-invoking after a rebase, sleep 60s after a transient retry rerun.

4. **When rebase is needed** (ACTION=rebase or rebase_then_evaluate), use the `rebase-push.sh` script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh
   ```
   Handle exit codes:
   - **Exit 0**: Rebase and push succeeded.
   - **Exit 1**: Rebase had conflicts (rebase is still in progress). Read `CONFLICT_FILES=` from stdout. Enter the **Conflict Resolution Procedure** below.
   - **Exit 2**: `force-with-lease` push failed. Run the script again once (it fetches + rebases internally). If it fails twice, **bail out** (Step 12d).
   - **Exit 3**: Rebase failed for non-conflict reasons (rebase already aborted). Read `REBASE_ERROR=` from stderr. **Bail out** (Step 12d).

### Conflict Resolution Procedure

When `rebase-push.sh` exits with code 1, the rebase is paused with conflicts. This procedure resolves them intelligently, with user escalation when uncertain and a full reviewer panel to validate the resolution.

**Bail invariant**: Any bail from any phase below must call `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-rebase-abort.sh` before proceeding to Step 12d, since the rebase is in progress throughout all phases.

#### Phase 1 — Conflict Classification and Resolution

For each file in `CONFLICT_FILES`:

1. Run `git ls-files -u` to determine the conflict type per file (check which index stages 1/2/3 exist).
2. **Unsupported conflict types** — If any stage is missing (modify/delete, rename/delete conflicts) or the file is binary (check via `file --mime-type` or absence of text markers), classify as **uncertain**. Do not attempt auto-resolution.
3. **Trivial files** — If the file is `version.go`, `go.sum`, or auto-generated, classify as **trivial** and auto-resolve immediately. Stage with `git add`.
4. **Text conflicts with both sides available** — Read both sides using explicit labels:
   - `git show :2:<file>` → **upstream (main)** version. If this command fails, classify as uncertain.
   - `git show :3:<file>` → **feature branch commit** version. If this command fails, classify as uncertain.
   - Also read the conflict markers in the working tree file for context.
5. **Classify confidence**:
   - **Trivial**: `version.go`, `go.sum`, auto-generated files.
   - **High-confidence**: Changes are in non-overlapping regions (both sides added content in different locations), or the conflict markers show only whitespace, import-order, or formatting differences. Both sides' intent is clear and composable.
   - **Uncertain**: Overlapping semantic changes to the same function/block, any file where correctness cannot be verified without domain knowledge, any file where `:2:` or `:3:` reads failed, any non-text/binary conflict.
6. Auto-resolve trivial and high-confidence files. Stage resolved files with `git add`.
7. **IMPORTANT**: Always use "upstream (main)" and "feature branch commit" labels when describing the two sides of a conflict — never use "ours"/"theirs" which have inverted semantics during rebase and will cause confusion.

#### Phase 2 — User Escalation (for uncertain conflicts)

**If there are no uncertain conflicts**, skip to Phase 3.

- **If `auto_mode=false`**: Call `AskUserQuestion` with the upstream (main) version, the feature branch commit version, and a proposed resolution for each uncertain file, batched into a single call. Use explicit "upstream (main)" and "feature branch commit" labels. Incorporate the user's answer, write the resolved file, and stage with `git add`. If the user indicates the conflict cannot be resolved or asks to abort, run `git rebase --abort` and **bail out** (Step 12d).
- **If `auto_mode=true`**: Attempt best-effort resolution for uncertain conflicts. If confidence is too low for any file (e.g., modify/delete conflict, conflicting business logic with no composable path, one side deleted code the other modified), run `git rebase --abort` and **bail out** (Step 12d).

#### Phase 3 — Reviewer Panel on Conflict Resolution

**If ALL conflicts were trivial** (no high-confidence or uncertain conflicts): Skip Phase 3 entirely. Proceed to Phase 4.

**Otherwise**, run a full reviewer panel to validate the non-trivial conflict resolutions:

**3a. Create temp directory**: Create `$IMPLEMENT_TMPDIR/conflict-review/` for reviewer artifacts. If it already exists (from a prior conflict resolution in this rebase loop), remove it and recreate.

**3b. Check external reviewer availability**: Run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/check-reviewers.sh` to set `codex_available` and `cursor_available` flags. Follow the Binary Check procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md`.

**3c. Prepare review context**: For each non-trivial conflicted file, prepare a per-file conflict context block:
```
### <file-path>
**Conflict type**: <text overlap / import reorder / etc.>
**Upstream (main) version** (relevant section):
<content from git show :2:<file>, focused on the conflicting region>

**Feature branch commit version** (relevant section):
<content from git show :3:<file>, focused on the conflicting region>

**Proposed resolution**:
<the resolved content that was staged>

**Intent**: <one-line description of what each side was trying to do>
```

Also capture `git diff --cached` as supplementary context showing the full staged state.

**3d. Launch reviewers**: Launch 2 Claude subagent reviewers + Codex + Cursor (if available) using the reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/reviewer-templates.md` with:
- `{REVIEW_TARGET}` = `"merge conflict resolution"`
- `{CONTEXT_BLOCK}` = the per-file conflict context blocks from 3c + supplementary `git diff --cached`
- `{OUTPUT_INSTRUCTION}` = `"File path and line number(s)"` + `"What the issue is with the resolution"` + `"Suggested correction"`

Follow `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/external-reviewers.md` for launch order (Cursor first, Codex, then Claude subagents), background execution, sentinel polling via `wait-for-reviewers.sh`, and output validation. Use `$IMPLEMENT_TMPDIR/conflict-review/` as the tmpdir for all reviewer output files, sentinel files, and ballot files.

**3d-ii. Collect and deduplicate**: After all reviewers complete, collect their findings. Parse Claude subagent dual-list outputs (in-scope findings + OOS observations). Read and validate external reviewer outputs per `external-reviewers.md`. Merge all findings, deduplicate (same file + same issue = one finding), assign stable sequential IDs (`FINDING_1`, `FINDING_2`, etc.), and write the ballot to `$IMPLEMENT_TMPDIR/conflict-review/ballot.txt` following the ballot format in `voting-protocol.md`.

**3e. Voting**: Run the voting protocol from `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/voting-protocol.md` with code review voter composition:
- **Voter 1**: Claude General Reviewer subagent (fresh Agent invocation)
- **Voter 2**: Codex (if available) — via `run-external-reviewer.sh`
- **Voter 3**: Cursor (if available) — via `run-external-reviewer.sh`

If fewer than 2 voters are available: skip voting, accept all reviewer findings (per `voting-protocol.md` fallback), implement them, and continue to Phase 4.

If voting **accepts findings** (2+ YES votes): re-resolve the affected files incorporating the accepted suggestions, re-stage, and re-run review (3c through 3e). Allow up to **2 total resolution-review rounds**.

After 2 rounds with unresolved findings still being raised: run `git rebase --abort` and **bail out** (Step 12d).

If the reviewer panel finds no issues or all findings are addressed: proceed to Phase 4.

**3f. Cleanup**: Remove `$IMPLEMENT_TMPDIR/conflict-review/` after Phase 3 completes (on both success and bail paths, before proceeding).

#### Phase 4 — Continue Rebase

Run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --continue` and handle exit codes:
- **Exit 0**: Rebase and push succeeded. Increment `rebase_count` and `iteration`, reset `transient_retries`. Restart the CI wait loop.
- **Exit 1**: A later commit in the rebase conflicted. Loop back to **Phase 1** for the new conflict (the Conflict Resolution Procedure starts again for the new set of `CONFLICT_FILES`).
- **Exit 2**: Push `--force-with-lease` failed. Retry `rebase-push.sh --continue` once. If it fails twice, **bail out** (Step 12d — call `git rebase --abort` first if the rebase is still in progress).
- **Exit 3**: Check the `REBASE_ERROR` output. If it indicates an empty or already-applied commit (e.g., "nothing to commit", "No changes"), run `git rebase --skip` (if `git rebase --skip` itself exits non-zero, run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-rebase-abort.sh` and **bail out** — Step 12d) and then `${CLAUDE_PLUGIN_ROOT}/scripts/larch/rebase-push.sh --continue` again (handle the same exit codes). Otherwise, **bail out** (Step 12d).

### 12b — Merge

When CI passes and the branch is up-to-date with main, use the `merge-pr.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/merge-pr.sh --pr <PR-NUMBER> --repo $REPO
```

Parse the output for `MERGE_RESULT` and `ERROR`. Handle each result:

- **`MERGE_RESULT=merged`**: Print `✅ Step 12 — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=admin_merged`**: Print `**⚠ Merged with --admin (review requirement overridden).** ✅ Step 12 — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=main_advanced`**: Go back to **12a** (the next iteration will detect the branch is behind and rebase).
- **`MERGE_RESULT=ci_not_ready`**: Go back to **12a** (CI may need more time or a rerun).
- **`MERGE_RESULT=admin_failed`**: Bail out (Step 12d) with the `ERROR` message.
- **`MERGE_RESULT=error`**: Bail out (Step 12d) with the `ERROR` message.

**CRITICAL: The `--admin` safety invariant is enforced inside `merge-pr.sh` — it re-verifies CI and branch freshness before attempting `--admin`. See the script's header for the full invariant. (Keep in sync with the same `--admin` fallback in `/admin-upgrade-clients` Sub-Step 7 and `/admin-add-user` Step 10.)**

Save the expected commit title for verification in Step 15: `<PR_TITLE> (#<PR_NUMBER>)` (using the `PR_TITLE` saved in Step 9).

### 12c — Evaluate CI Failure

Use `FAILED_RUN_ID` from the `ci-status.sh` output. If `FAILED_RUN_ID` is empty, use `${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-pr-checks.sh --pr <PR-NUMBER> --repo $REPO` to identify the failed check and its run URL manually.

1. **Transient/infrastructure failure** (GitHub API timeout, runner provisioning failure, flaky network, `RUNNER_TEMP` errors, Docker pull rate limit, "The hosted runner lost communication", etc.):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/sleep-seconds.sh 60
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Parse the output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Allow up to **2 consecutive transient retries** before treating as a real failure. The counter resets after a successful rebase, code fix, or a CI run that fails for a different (non-transient) reason. Go back to **12a**.

2. **Real CI failure** — Diagnose and fix:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Analyze the logs. Fix the issue, run `/relevant-checks`, commit, push. Go back to **12a**.

### 12d — Bail Out

**Bail out** if any of these are true:
- You've already attempted **3 fix iterations** without progress (same or new errors each time).
- The failure is **fundamentally incompatible** with the codebase or CI.
- The fix would require **reverting the core feature** to pass CI.

When bailing out:
1. If a rebase is in progress (exit 1 from `rebase-push.sh`), run `${CLAUDE_PLUGIN_ROOT}/scripts/larch/git-rebase-abort.sh` first.
2. Clearly explain what failed, what you attempted, and suggest manual steps.

**Do NOT skip Steps 14, 16, 17, and 18** when bailing — still clean up and print the review report. **Skip Steps 13 and 15** since the PR was not merged.

## Step 13 — Add :merged: Emoji to Slack Post

**If `merge=false`**: Skip this step.

**If `slack_available=false`**: Print `⏭️ Step 13 — Skipped (Slack not configured).` and proceed to Step 14.

**Only if the PR was successfully merged in Step 12b or force-merged externally** (not bailed in 12d).

**Only if `SLACK_TS` from Step 11 is non-empty** (Slack announcement succeeded).

Add the :merged: emoji using the shared script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/post-merged-emoji.sh --slack-ts "$SLACK_TS"
```

**If the script exits non-zero**, print `**⚠ Failed to add :merged: emoji to Slack post. Continuing.**` and proceed to Step 14. **Do not abort.**

## Step 14 — Local Cleanup

**If `merge=false`**: Print `⏩ Step 14 — Skipped (--merge not set). You are still on branch $BRANCH_NAME.` and skip to Step 16.

**If the PR was successfully merged (Step 12b or force-merged externally)**:

Switch back to main, pull the merged changes, and delete the development branch:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/local-cleanup.sh --branch "$BRANCH_NAME"
```

Parse the output for `CLEANUP_SUCCESS`, `CURRENT_BRANCH`, and `BRANCH_DELETED`. If `CLEANUP_SUCCESS=true`, print: `🧹 Step 14 — Switched to main, deleted local branch $BRANCH_NAME`. If `CLEANUP_SUCCESS=false`, print: `**⚠ Step 14 — Cleanup partially failed. Current branch: <CURRENT_BRANCH>, branch deleted: <BRANCH_DELETED>.**`

**If Step 12 bailed out (PR was NOT merged)**:

Do NOT switch branches or delete the local branch. The user will need the branch to continue manually.

Print: `⚠️ Step 14 — Skipped cleanup (PR not merged). You are still on branch $BRANCH_NAME.`

`$BRANCH_NAME` is the variable captured at the end of Step 1 (after branch resolution by `/design` or quick-mode branch creation).

## Step 15 — Verify Main

**If `merge=false`**: Skip this step.

**Only if the PR was successfully merged (Step 12b or force-merged externally)** (skip if bailed out).

Confirm the last commit on main is the expected squash-merged commit using the `verify-main.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/verify-main.sh --expected-title "<PR_TITLE> (#<PR_NUMBER>)"
```

Parse the output for `VERIFIED`, `COMMIT_HASH`, and `COMMIT_MESSAGE`. Print the result:

- If `VERIFIED=true`: `✅ Step 15 — Verified: main is at <COMMIT_HASH> "<COMMIT_MESSAGE>"`
- If `VERIFIED=false`: `**⚠ Step 15 — Unexpected HEAD on main: <COMMIT_HASH> "<COMMIT_MESSAGE>". Expected: "<PR_TITLE> (#<PR_NUMBER>)". Another merge may have landed simultaneously.**`

## Step 16 — Rejected Code Review Findings Report

Print a report of all code review suggestions that were **not** implemented.

1. Check if `$IMPLEMENT_TMPDIR/rejected-findings.md` exists and is non-empty.
2. If it has content, print it under a `## Unimplemented Code Review Suggestions` header, formatted clearly with the reviewer name, the suggestion, and the reason for each.
3. If the file doesn't exist or is empty, print: `📊 Step 16 — All code review suggestions were implemented.`

## Step 17 — Final Report

**If `quick_mode=true`**: Print: `📊 Step 17 — Quick mode: /design was skipped, code review was simplified (2 Claude subagents, 1 round, no voting).`

**If `quick_mode=false`**: Print a summary noting that:
- Plan review findings were reported by the `/design` phase (visible in conversation above)
- Code review findings were reported by the `/review` phase (visible in conversation above)

If both phases reported all suggestions implemented, print: `📊 Step 17 — All review suggestions were implemented across both plan review and code review.`

## Step 18 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/cleanup-tmpdir.sh --dir "$IMPLEMENT_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier in the workflow (from `/design` or `/review` phases) so they are visible at the end. **If `quick_mode=true`**, there are no external reviewer warnings to repeat (no external reviewers were used). For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`

If `merge=false`, remind: `**Note: --merge was not set. PR was created but not merged. Merge manually when ready.**`

Print: `🏁 Step 18 — Implement complete!`
