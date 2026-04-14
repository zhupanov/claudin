---
name: implement
description: "Use when implementing a feature end-to-end: design, implement, code review, version bump, PR, Slack announce, and cleanup. Pass --merge to additionally run the CI+rebase+merge loop and delete the local branch after merging."
argument-hint: "[--quick] [--auto] [--merge] [--debug] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Implement Skill

Full end-to-end feature implementation: design, plan review, code, validate, commit, code review, validate, commit, code flow diagram, version bump, PR, CI monitor, Slack announce, and cleanup. With `--merge`: also runs the CI+rebase+merge loop, adds the :merged: emoji, deletes the local branch, and verifies main.

The feature to implement is described by `$ARGUMENTS` after flag stripping.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, save the remainder as `FEATURE_DESCRIPTION` — use this (not raw `$ARGUMENTS`) whenever the human-readable feature description is needed (e.g., PR body, design invocation, commit messages). **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--quick`: Set a mental flag `quick_mode=true`. Default: `quick_mode=false`. When `quick_mode=true`: Step 1 skips `/design` (this skill creates the branch and an inline plan directly), Step 5 skips `/review` (a simplified one-round review with 2 Claude subagents only — no external reviewers, no voting panel), and Step 7a skips the Code Flow Diagram. All other steps (CI wait, Slack, cleanup) run normally. The `--merge` opt-in is independent of `--quick`.
- `--auto`: Set a mental flag `auto_mode=true`. Default: `auto_mode=false`. When `auto_mode=true`: (a) forward `--auto` to `/design` invocation in Step 1, suppressing `/design`'s interactive question checkpoints; (b) suppress this skill's own opportunistic questions in Step 2; (c) in Step 12, when merge conflicts require user input for uncertain resolutions, suppress `AskUserQuestion` and use best-effort resolution instead (bailing if confidence is too low). When `--quick` is also set and `/design` is skipped, `--auto` still suppresses Step 2 questions.
- `--merge`: Set a mental flag `merge=true`. Default: `merge=false`. When `merge=true`, Steps 12–15 run (CI+rebase+merge loop, :merged: emoji, local cleanup, and main verification). When `merge=false`, these steps are skipped — the PR is created and the workflow stops after the initial CI wait, Slack announcement, rejected findings report, final report, and temp cleanup.
- `--no-merge`: **Deprecated** — recognized for backward compatibility but treated as a no-op (the new default already skips merge steps). When this flag is encountered, print: `**ℹ '--no-merge' is now the default and no longer needed; the flag is recognized as a no-op for backward compatibility.**`
- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. When `debug_mode=true`, forward `--debug` to `/design` (Step 1) and `/review` (Step 5) invocations. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill and will be forwarded to `session-setup.sh` via `--caller-env` and to `/design` via `--session-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is and which parent steps they are inside. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `▸ 2: implementation`
- Print a **completion line** only when it carries informational payload. Only the final step (Step 18) prints an unconditional completion announcement.
- For long-running steps, print **intermediate progress**: e.g., `⏳ 12: CI+merge loop — CI running (2m elapsed), main unchanged`

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | design plan |
| 1.m | update main |
| 1.r | rebase |
| 2 | implementation |
| 3 | checks (1) |
| 4 | commit (impl) |
| 4.r | rebase |
| 5 | code review |
| 6 | checks (2) |
| 7 | commit (review) |
| 7.r | rebase |
| 7a | code flow |
| 7a.r | rebase |
| 8 | version bump |
| 8a | changelog |
| 9 | create PR |
| 10 | CI monitor |
| 11 | slack announce |
| 12 | CI+merge loop |
| 13 | merged emoji |
| 14 | local cleanup |
| 15 | verify main |
| 16 | rejected findings |
| 17 | final report |
| 18 | cleanup |

### Verbosity Control

**When `debug_mode=false` (default):**

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print the designated output categories below.

**Preserved output (NEVER suppressed, regardless of `debug_mode`):** step breadcrumb lines (start `▸`, completion `✅`, skip `⏩`/`⏭️`) — except the three rebase-skip variants listed in Suppressed output below, final completion line (Step 18), all warning/error lines (`**⚠ ...`), structured summaries (voting tallies, competition scoreboards, round summaries, final summaries/reports), architecture diagrams, code flow diagrams, implementation plans (original and revised), dialectic resolutions, accepted/rejected findings lists, out-of-scope observations, PR body sections.

**Suppressed output (only when `debug_mode=false`):** explanatory prose describing what will happen next or what just happened, script paths and command descriptions, rationale for decisions between tool calls, per-reviewer individual completion messages (replaced by status table in child skills), rebase-skip messages (the following three specific variants: `⏩ 1.m: design plan | update main — already at latest`, `⏩ 1.r: design plan | rebase — already pushed`, `⏩ 1.r: design plan | rebase — already at latest main`). Note: non-rebase `⏩` skip messages and rebase outcomes in the Rebase+Re-bump Sub-procedure (Steps 10/12) are NOT suppressed — they carry CI-debugging semantics.

**When `debug_mode=true`:** use descriptive text for `description` parameter on all Bash and Agent tool calls; print full explanatory text between tool calls (current verbose behavior).

**Limitation**: Verbosity suppression is prompt-enforced and best-effort; it may degrade in very long sessions.

## Step 0 — Session Setup

Run the shared session setup script. This handles preflight, temp directory creation, reviewer health probe, and session-env file writing in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-implement --skip-branch-check --check-reviewers [--caller-env "$SESSION_ENV_PATH"] [--skip-codex-probe] [--skip-cursor-probe] --write-session-env "$IMPLEMENT_TMPDIR/session-env.sh"
```

`--skip-branch-check` is required so that the inlined Step 1 user-branch decision logic (`IS_USER_BRANCH=true` paths) is reachable. Without it, `preflight.sh` would refuse to run unless the user is on a clean `main` branch, making Step 1's branch-resume paths dead code.

Only include `--caller-env "$SESSION_ENV_PATH"` if `SESSION_ENV_PATH` is non-empty. If `SESSION_ENV_PATH` provides `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, the script auto-sets the corresponding `--skip-codex-probe` / `--skip-cursor-probe` flag — you do not need to pass these explicitly when using `--caller-env`.

**Note**: `--write-session-env` uses `$IMPLEMENT_TMPDIR` which is `SESSION_TMPDIR` from the script's output. Since the script creates the tmpdir before writing session-env, pass the actual path after parsing `SESSION_TMPDIR` from stdout. In practice, run the script first to get `SESSION_TMPDIR`, set `IMPLEMENT_TMPDIR` = `SESSION_TMPDIR`, then re-invoke `write-session-env.sh` separately if needed. **Alternative**: Omit `--write-session-env` from the initial call and run it as a separate post-step:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$IMPLEMENT_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value> \
  --codex-healthy <value> --cursor-healthy <value>
```

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set:
- `IMPLEMENT_TMPDIR` = `SESSION_TMPDIR`
- If `SLACK_OK=false`, print: `**⚠ Slack is not fully configured (<SLACK_MISSING> not set). Slack announcement (Step 11) and :merged: emoji (Step 13) will be skipped.**` Set a mental flag `slack_available=false`.
- If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository name. CI monitoring (Steps 10, 12) and merge (Step 12b) will be skipped.**` Set a mental flag `repo_unavailable=true`.
- If `CODEX_AVAILABLE=false`: print `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: print `**⚠ Codex installed but not responding (health check failed). Using Claude replacement.**`
- Same for Cursor. Only check `*_HEALTHY` when `*_AVAILABLE=true`.

The session-env file (`$IMPLEMENT_TMPDIR/session-env.sh`) will be passed to `/design` via `--session-env` in Step 1, and to `/review` via `--session-env` in Step 5.

### Cross-Skill Health Propagation

After each child skill returns (`/design` in Step 1, `/review` in Step 5), check for a health status file at `$IMPLEMENT_TMPDIR/session-env.sh.health`. If it exists, read `CODEX_HEALTHY` and `CURSOR_HEALTHY` from it. If either value changed to `false` (a reviewer timed out during the child skill):

1. Read the current values from `$IMPLEMENT_TMPDIR/session-env.sh` (parse `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE` line-by-line, same safe parsing as `session-setup.sh` — do NOT source the file)
2. Re-write the file using `write-session-env.sh` with those preserved values plus the updated health flags

This ensures runtime timeouts propagate across skill boundaries within the `/implement` flow without clobbering existing Slack/repo state.

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
${CLAUDE_PLUGIN_ROOT}/scripts/create-branch.sh --check
```

Parse the output for `CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, and `USER_PREFIX`.

### Ensure local main is fresh before branch creation

**This block runs only when `CURRENT_BRANCH == "main"`.** Detached HEAD also reports `IS_MAIN=true` from `create-branch.sh --check`, but a rebase on detached HEAD would fail (`rebase-push.sh` errors with "Not on a branch"); fall through to the mode-specific branch creation logic below so a new branch can be created from `origin/main`. Also skip this block for `IS_USER_BRANCH=true` (we are not creating a branch from main — the feature branch rebase at the end of Step 1 handles freshness) and for the non-main/non-user-branch warning path (we are on some other branch, and `create-branch.sh --branch` will fetch and create the new branch directly from `origin/main`).

Print: `🔃 1.m: design plan | update main`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push
```

`--skip-if-pushed` is intentionally **not** used here: `main` is always on origin, so that flag would always short-circuit. The `SKIPPED_ALREADY_FRESH=true` optimization makes this call cheap (fetch + ancestor check) when local `main` is already at `origin/main`.

If the script exits non-zero, print: `**⚠ Failed to ensure local main is fresh. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_FRESH=true`: if `debug_mode=true`, print: `⏩ 1.m: design plan | update main — already at latest` Otherwise, silently continue.
- Otherwise, print: `✅ 1.m: design plan | update main — rebased onto latest origin/main`

### Quick mode (`quick_mode=true`)

Skip `/design` entirely. Handle branch creation directly, then produce an inline implementation plan.

**Branch handling** (same logic as `/design` Step 1, replicated here since `/design` is skipped):
- If `IS_MAIN=true`: Derive a short kebab-case branch name from the feature description. Create it via `${CLAUDE_PLUGIN_ROOT}/scripts/create-branch.sh --branch <USER_PREFIX>/<branch-name>`.
- If `IS_USER_BRANCH=true`: Verify the branch name (`CURRENT_BRANCH`) aligns with the requested feature. If it appears unrelated (different feature name, unrelated commits), print a warning: `**⚠ Current branch '<branch-name>' may not match the requested feature. Creating a new branch from main.**` and create a new branch. Otherwise, use the existing branch.
- Otherwise (non-main, non-user branch): Print a warning: `**⚠ Currently on branch '<branch-name>' which doesn't match the expected '<USER_PREFIX>/*' pattern. Creating a new branch from main.**` and create a new branch.

**Inline design**: Research the codebase (read relevant files, grep for patterns), then produce a concrete implementation plan under a `## Implementation Plan` header. This plan should include files to modify, approach, and edge cases — the same content `/design` would produce, but without collaborative sketches, plan review, or voting. Print: `⚡ 1: design plan — quick mode, inline plan`

Proceed to Step 2.

### Normal mode (`quick_mode=false`)

**Decision logic**:
- If `IS_USER_BRANCH=true` **AND** a reviewed implementation plan is visible in the conversation context above: The plan was created by a prior `/design` invocation in this session. Proceed to Step 2.
- If `IS_USER_BRANCH=true` but **no** implementation plan is visible in the conversation context: Invoke the `/design` skill with flags and feature description. **If `auto_mode=true`, also prepend `--auto`**. **If `debug_mode=true`, also prepend `--debug`**. Always prepend `--step-prefix "1.::design plan"` and `--branch-info "IS_MAIN=$IS_MAIN IS_USER_BRANCH=$IS_USER_BRANCH USER_PREFIX=$USER_PREFIX CURRENT_BRANCH=$CURRENT_BRANCH"`. Canonical invocation order: `[--debug] [--auto] --step-prefix "1.::design plan" --branch-info "<values>" --session-env $IMPLEMENT_TMPDIR/session-env.sh <FEATURE_DESCRIPTION>`. After `/design` completes, proceed to Step 2.
- If on `main` or empty (detached HEAD) or any non-user branch: No design plan exists yet. Invoke the `/design` skill with the same flags. **If `auto_mode=true`, also prepend `--auto`**. **If `debug_mode=true`, also prepend `--debug`**. Always prepend `--step-prefix "1.::design plan"` and `--branch-info "IS_MAIN=$IS_MAIN IS_USER_BRANCH=$IS_USER_BRANCH USER_PREFIX=$USER_PREFIX CURRENT_BRANCH=$CURRENT_BRANCH"`. Canonical invocation order: `[--debug] [--auto] --step-prefix "1.::design plan" --branch-info "<values>" --session-env $IMPLEMENT_TMPDIR/session-env.sh <FEATURE_DESCRIPTION>`. After `/design` completes, proceed to Step 2.

### Cross-Skill Health Update (after /design)

After `/design` returns (in normal mode), follow the **Cross-Skill Health Propagation** procedure from Step 0: read `$IMPLEMENT_TMPDIR/session-env.sh.health` if it exists, and re-write `$IMPLEMENT_TMPDIR/session-env.sh` with updated health flags if any reviewer timed out during `/design`.

### Capture branch name (`BRANCH_NAME`)

After Step 1's branch resolution (whether quick mode or normal mode, whether a new branch was created or an existing one was reused), capture the resolved branch name into a `BRANCH_NAME` variable:

```bash
git symbolic-ref --short HEAD
```

Save the output as `BRANCH_NAME`. This variable is referenced later by Step 14 (`local-cleanup.sh --branch $BRANCH_NAME`) and by Steps 4, 14, and 18 status messages that mention the development branch. **It is the responsibility of Step 1 to ensure `BRANCH_NAME` accurately reflects the branch where implementation will happen** — re-run `git symbolic-ref --short HEAD` after `/design` returns (in normal mode) since `/design` may have switched branches.

### Rebase onto latest main (before implementation)

**This rebase runs unconditionally in both quick and normal mode** — freshness is beneficial regardless of mode. Both the quick-mode "Proceed to Step 2" and normal-mode "proceed to Step 2" instructions above lead here before entering Step 2.

Print: `🔃 1.r: design plan | rebase`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_PUSHED=true`: if `debug_mode=true`, print: `⏩ 1.r: design plan | rebase — already pushed` Otherwise, silently continue.
- If stdout contains `SKIPPED_ALREADY_FRESH=true`: if `debug_mode=true`, print: `⏩ 1.r: design plan | rebase — already at latest main` Otherwise, silently continue.
- Otherwise, print: `✅ 1.r: design plan | rebase — rebased onto latest main`

## Step 2 — Implement the Feature

**Opportunistic questions** (`auto_mode=false` only): Before starting edits, if the implementation plan leaves genuinely ambiguous choices (e.g., naming conventions, test strategy, which of two valid approaches to use), batch them into a single `AskUserQuestion` call with 1-4 questions. Only ask when the ambiguity cannot be resolved from the plan, codebase, or CLAUDE.md. When `auto_mode=true`, proceed with best judgment — do not ask. Material answers that change scope or approach should be noted for the "Implementation Deviations" section.

Implement the feature following the (reviewed) plan from the `/design` phase. Follow all guidelines in CLAUDE.md:
- Read existing code before modifying
- Match existing style and patterns
- Avoid code duplication — search for reusable code first
- Don't over-engineer — for each abstraction, helper, or indirection you introduce, ask: is this justified by a concrete current need? If the answer is "it might be useful later," don't add it
- When the project has test infrastructure (look for: test directories, Makefile test targets, package.json test scripts, or a test framework), prefer test-driven development: write a failing test for the expected behavior first, then implement to make it pass. For changes that are purely configuration, documentation, or prompt-text edits, skip TDD

## Step 3 — Relevant Checks (first pass)

Invoke `/relevant-checks` to run validation checks relevant to the modified files. If checks fail, diagnose and fix the issue, then re-invoke `/relevant-checks` to confirm the fix.

## Step 4 — First Commit (implementation)

Stage and commit all changed files using the wrapper script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-commit.sh -m "<descriptive commit message>" <specific-files>
```

The commit message should describe WHAT was implemented and WHY, not HOW.

### Rebase onto latest main (after implementation commit)

Print: `🔃 4.r: commit (impl) | rebase`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_PUSHED=true`: if `debug_mode=true`, print: `⏩ 4.r: commit (impl) | rebase — already pushed` Otherwise, silently continue.
- If stdout contains `SKIPPED_ALREADY_FRESH=true`: if `debug_mode=true`, print: `⏩ 4.r: commit (impl) | rebase — already at latest main` Otherwise, silently continue.
- Otherwise, print: `✅ 4.r: commit (impl) | rebase — rebased onto latest main`

## Step 5 — Code Review

### Quick mode (`quick_mode=true`)

Skip `/review`. Instead, run a simplified one-round review:

1. Gather the diff using the context script:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gather-branch-context.sh --output-dir "$IMPLEMENT_TMPDIR"
   ```
   Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log.
2. Launch **2 Claude subagent reviewers** (general, deep-analysis) using the same reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md` with these variable bindings: `{REVIEW_TARGET}` = `"code changes"`, `{CONTEXT_BLOCK}` = the commit log + file list + full diff, `{OUTPUT_INSTRUCTION}` = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix"`. **No Codex, no Cursor, no external reviewers. No competition notice** (there is no voting panel in quick mode).
3. Collect findings from all 2 subagents. Deduplicate.
4. **Main agent decides**: Evaluate each finding and unilaterally accept or reject it. No voting panel. Accept findings that identify genuine bugs, logic errors, or important improvements. Reject trivial style nits or speculative concerns. Also reject findings whose proposed fix would introduce more complexity than the issue warrants (disproportionate fix).
5. Implement accepted fixes. Run `/relevant-checks` if files changed.
6. **One round only** — no re-review loop.
7. For rejected findings, write them to `$IMPLEMENT_TMPDIR/rejected-findings.md` using the same format as normal mode (see below), so Step 16 and PR body sections work unchanged.

Print: `▸ 5: code review — quick mode (2 Claude subagents, 1 round, no voting)`

### Normal mode (`quick_mode=false`)

**IMPORTANT: Code review must ALWAYS be invoked via `/review`. Never skip this step regardless of the nature of the changes — whether code, skills, documentation, data files, or configuration. All changes require full review.**

Invoke the `/review` skill with `--session-env $IMPLEMENT_TMPDIR/session-env.sh` to forward reviewer health state. Always prepend `--step-prefix "5.::code review"`. **If `debug_mode=true`, also prepend `--debug`.** Canonical invocation order: `[--debug] --step-prefix "5.::code review" --session-env $IMPLEMENT_TMPDIR/session-env.sh`. This launches 2 parallel Claude subagent reviewers (general, deep-analysis) plus two Codex and Cursor reviewers (if available and healthy), implements their suggestions recursively until clean.

After `/review` returns, follow the **Cross-Skill Health Propagation** procedure from Step 0 to read the health status file and update `session-env.sh` if any reviewer timed out during the review.

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

Parse the output for `FILES_CHANGED`. If `FILES_CHANGED=false`, print: `⏩ 6: checks (2) — skipped, no review changes` and skip Steps 6 and 7 (but NOT Step 7a — the Code Flow Diagram step runs unconditionally).

If files **did change**, invoke `/relevant-checks` to ensure review fixes didn't introduce new issues. If checks fail, diagnose and fix, then re-invoke `/relevant-checks`.

## Step 7 — Second Commit (review fixes)

If any files changed during review/checks (Steps 5–6), stage and commit them:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-commit.sh -m "Address code review feedback" <specific-files>
```

If no files changed (review found no issues), skip this commit.

### Rebase onto latest main (after review fixes commit)

**Conditional**: Only run this rebase if `FILES_CHANGED=true` from Step 6's `check-review-changes.sh` output (meaning Step 7 created a commit). If Steps 6–7 were skipped (no review changes), skip this rebase — the pre-Step-8 rebase provides the safety net.

Print: `🔃 7.r: commit (review) | rebase`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_PUSHED=true`: if `debug_mode=true`, print: `⏩ 7.r: commit (review) | rebase — already pushed` Otherwise, silently continue.
- If stdout contains `SKIPPED_ALREADY_FRESH=true`: if `debug_mode=true`, print: `⏩ 7.r: commit (review) | rebase — already at latest main` Otherwise, silently continue.
- Otherwise, print: `✅ 7.r: commit (review) | rebase — rebased onto latest main`

## Step 7a — Code Flow Diagram

Print: `▸ 7a: code flow`

**This step runs unconditionally after Step 7** — regardless of whether Steps 6-7 were skipped due to no review changes.

**If `quick_mode=true`**: Print `⏩ 7a: code flow — skipped (quick mode)` and proceed to Step 8.

**If `quick_mode=false`**: Generate a mermaid Code Flow Diagram based on the actual committed implementation. The diagram should focus on **runtime behavior** — function call sequences, data flow, or control flow through the implemented code paths. Do NOT duplicate the Architecture Diagram's structural/component view.

Choose the most appropriate mermaid diagram type for the implementation (e.g., `sequenceDiagram`, `flowchart`, `stateDiagram`, `graph`, etc.). The diagram type is flexible — pick whatever best communicates the code flow.

Print the diagram under a `## Code Flow Diagram` header with a mermaid code fence:

```
## Code Flow Diagram

```mermaid
<diagram content>
```
```

**If diagram generation succeeds**, print: `✅ 7a: code flow — diagram generated`

**If diagram generation fails** (e.g., the implementation is too abstract to diagram meaningfully), print: `**⚠ 7a: code flow — generation failed, proceeding without diagram**` Log this warning to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `Warnings` category.

### Rebase onto latest main (before version bump)

This rebase runs as a final safety net before the version bump and PR creation, even if a previous rebase just ran. It ensures the branch is as fresh as possible before the version bump becomes the last commit. Exception: if the branch is already on origin (e.g., re-run on an existing PR branch), the `--skip-if-pushed` flag causes this rebase to be skipped — freshness of already-pushed branches is the CI+rebase+merge loop's responsibility (Step 12).

Print: `🔃 7a.r: code flow | rebase`

Run:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push --skip-if-pushed
```

If the script exits non-zero, print: `**⚠ Rebase onto main failed. Bailing to cleanup.**` and skip to Step 18.

If successful:
- If stdout contains `SKIPPED_ALREADY_PUSHED=true`: if `debug_mode=true`, print: `⏩ 7a.r: code flow | rebase — already pushed` Otherwise, silently continue.
- If stdout contains `SKIPPED_ALREADY_FRESH=true`: if `debug_mode=true`, print: `⏩ 7a.r: code flow | rebase — already at latest main` Otherwise, silently continue.
- Otherwise, print: `✅ 7a.r: code flow | rebase — rebased onto latest main`

## Step 8 — Version Bump

Check if the repo has a `/bump-version` skill and capture commit count:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode pre
```

Parse the output for `HAS_BUMP` and `COMMITS_BEFORE`.

**If `HAS_BUMP=false`**: Print `**⚠ VERSION BUMP SKIPPED: No /bump-version skill found at .claude/skills/bump-version/SKILL.md. To enable automatic version bumps, create a /bump-version skill in this repo. The skill should determine the current version, classify the bump type, compute the new version, edit the version file, and commit.**` and skip to Step 9.

**If `HAS_BUMP=true`**:

1. Invoke `/bump-version` via the Skill tool.
2. Verify a new commit was created:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
   ```
   Parse for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`. If `VERIFIED=false`, print: `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`

**Important**: At PR creation time there must be exactly ONE version bump commit as HEAD. Proceed immediately to Step 8a after `/bump-version` returns. No additional commits may occur between Step 8a and Step 9. Note: after PR creation, Steps 10 and 12's rebase handlers may repeatedly drop and recreate this bump commit as main advances (via the shared **Rebase + Re-bump Sub-procedure** — see before Step 10). The branch history between PR creation and merge may therefore temporarily contain zero or multiple bump commits; the invariant that matters is "the terminal bump commit on HEAD must be based on latest `origin/main` at merge time", enforced strictly by Step 12 and best-effort by Step 10.

## Step 8a — CHANGELOG Update

**Conditional**: Skip Step 8a entirely and proceed to Step 9 if either condition is true:
- `CHANGELOG.md` does not exist in the project root (check via the Read tool — if Read returns an error, the file does not exist). Print `⏩ 8a: changelog — skipped (no CHANGELOG.md)`
- Step 8 was skipped (`HAS_BUMP=false`). Print `⏩ 8a: changelog — skipped (no version bump)`

**If `CHANGELOG.md` exists AND Step 8 produced a version bump**:

1. Read the current `CHANGELOG.md`.
2. Read the `NEW_VERSION` from the `/bump-version` output (saved in Step 8).
3. Compose a brief changelog entry using the Summary bullets from the implementation (the same 1-3 bullet points used in Step 9a's PR body `## Summary` section). Use today's date. Format:

   ```markdown
   ## [X.Y.Z] - YYYY-MM-DD

   ### Changed

   - <bullet point 1>
   - <bullet point 2>
   ```

   Use the appropriate Keep a Changelog category header (`Added`, `Changed`, `Fixed`, `Removed`) based on the nature of the changes. Multiple categories are fine if the PR spans them.

4. Insert the new section immediately after the file's header block (after the `and this project adheres to [Semantic Versioning]` line, before the first existing `## [` section). If there is an `## [Unreleased]` section, insert after it.
5. Stage `CHANGELOG.md` and amend the bump commit:

   ```bash
   git add CHANGELOG.md
   git commit --amend --no-edit
   ```

   This keeps the bump commit as the single HEAD commit containing both the version bump and the changelog update.

Print: `✅ 8a: changelog — updated for v<NEW_VERSION>`

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

<details><summary>Version Bump Reasoning</summary>

<content of $IMPLEMENT_TMPDIR/bump-version-reasoning.md if it exists and is non-empty, otherwise "No version bump reasoning available (skill may have skipped via BUMP_TYPE=NONE, or /bump-version was not invoked).">

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
- **Version Bump Reasoning**: Populate from `$IMPLEMENT_TMPDIR/bump-version-reasoning.md` as in normal mode (the `/bump-version` skill writes this file when Step 8 runs, and this is mode-agnostic).
- **Rejected Plan Review Suggestions**: Write "Quick mode — no plan review was conducted."
- **Plan Review Voting Tally**: Write "Quick mode — no plan review voting."
- **Code Review Voting Tally (Round 1)**: Write "Quick mode — no voting panel. Main agent reviewed findings from 2 Claude subagents."
- **Implementation Deviations**: Compare implementation to the inline plan (same as normal mode).
- **Out-of-Scope Observations**: Write "Quick mode — no out-of-scope observations collected."
- **Run Statistics**: Set "Plan review findings" to "N/A (quick mode)", "External reviewers" to "N/A (quick mode)". Code review findings should reflect the quick review results.

### 9b — Create PR via script

Run the `create-pr.sh` script with a concise title (under 70 chars):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/create-pr.sh --title "<title>" --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
```

Parse the output for `PR_NUMBER`, `PR_URL`, `PR_TITLE`, and `PR_STATUS`. The script handles pushing the branch, detecting existing PRs, and creating new ones with `--assignee @me`. `PR_STATUS` is `created` for new PRs or `existing` for already-open PRs. Save `PR_STATUS` — it is used in Step 11 to decide whether to post to Slack.

**If `create-pr.sh` exits non-zero**, print the error from its output and abort. Do not proceed to Steps 10–18.

**If `PR_STATUS=existing`**: The PR body was not updated by `create-pr.sh`. Update it now:
```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
```

Print the PR URL when done. Save `PR_NUMBER`, `PR_URL`, and `PR_TITLE` for use in Steps 10–15.

## Rebase + Re-bump Sub-procedure (shared by Steps 10 and 12)

After the initial version bump in Step 8, every subsequent rebase of the feature branch onto latest `origin/main` must be followed by a fresh `/bump-version` run so the merged state reflects the version in latest main **at merge time**, not at PR-creation time. This sub-procedure consolidates the drop/rebase/fast-forward/bump/push/refresh sequence so that Steps 10 and 12 can invoke it from multiple places without duplication.

### Inputs
- `rebase_already_done` — if `true`, steps 1–2 are skipped (the rebase has already happened and been pushed by the caller, e.g., Step 12 Phase 4's `rebase-push.sh --continue`). If `false`, the sub-procedure performs the rebase itself.
- `caller_kind` — one of: `step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`, `step10_rebase`, `step10_rebase_then_evaluate`. Determines:
  1. **Post-return control flow** (re-invoke `ci-wait.sh`, fall through to 12c, fall through to Step 10's evaluate_failure handler, etc.)
  2. **Failure semantics** — grouped into two caller families:
     - **step12 family** (`step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`): any hard failure below bails to **Step 12d**. Step 12 is the last-chance enforcement point for the version bump freshness invariant, so it must not silently proceed to merge.
     - **step10 family** (`step10_rebase`, `step10_rebase_then_evaluate`): any hard failure below logs a warning and **breaks out of Step 10's loop to Step 11**, matching Step 10's existing "never block the pipeline" philosophy. Step 12 will re-run this sub-procedure under strict semantics before merging, so Step 10 failures degrade gracefully.
  3. **Conflict fallback path** — `step12_*` falls back to a full `rebase-push.sh` + the Conflict Resolution Procedure (Phase 1–4) when `--no-push` exit 1 happens; `step10_*` logs a warning and breaks out of Step 10 to Step 11 (Step 10 has no Phase 1–4).

### Happy path (`rebase_already_done=false`)

1. **Drop existing bump commit**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/drop-bump-commit.sh
   ```
   Parse `DROPPED`. If `DROPPED=false`, log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Warnings`: `Step <N> — drop-bump-commit.sh reported DROPPED=false before rebase; HEAD was not a bump commit (CI fix commit may have landed on top, worktree was dirty, or the commit touched files other than .claude-plugin/plugin.json). Re-bump will still run but branch history may temporarily contain two bump commits and the rebase may encounter a plugin.json conflict routed through Phase 1–3.` Continue to step 2. (The guard in `drop-bump-commit.sh` is defense-in-depth — the sub-procedure does not treat `DROPPED=false` as a hard failure.)

2. **Rebase without pushing**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push
   ```
   - **Exit 0** (rebase clean, branch is local-only fresh — may include `SKIPPED_ALREADY_FRESH=true`): proceed to step 3.
   - **Exit 1** (conflict; `--no-push` has already called `git rebase --abort`, so no rebase is in progress — the two invocations are independent, any fallback call restarts a fresh fetch + rebase):
     - **step12 family**: **fall back to full `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh`** (without `--no-push`). Enumerate all four exit codes of the fallback call:
       - **Fallback exit 0**: rebase succeeded cleanly AND the branch was force-pushed by the fallback call. Proceed to step 3. Note: `rebase_already_done` is NOT set here — that flag only gates sub-procedure steps 1–2 at entry, and by this point those steps have already executed. Step 5's push will land the new bump commit on top of the fallback's push (the intended double-push for the conflict-fallback path, necessarily two pushes because the fallback call couldn't avoid pushing).
       - **Fallback exit 1**: conflict; rebase is in progress. Enter the **Conflict Resolution Procedure** (Phase 1–4, defined in Step 12 below). **Phase 4's `rebase-push.sh --continue` exit-0 handler (at the end of Step 12's Conflict Resolution Procedure) itself dispatches the sub-procedure with `rebase_already_done=true, caller_kind=step12_phase4`** — i.e., the post-conflict re-bump is owned entirely by Phase 4. **Control transfer is terminal**: the moment Phase 1 is entered, the current (fallback) sub-procedure invocation is conceptually suspended and its remaining steps 3–7 are NOT executed. All further action for this rebase (Phase 2, Phase 3, Phase 4, and the sub-procedure dispatched by Phase 4's exit-0 handler) runs under Phase 4's ownership. When Phase 4 completes (success or bail), it returns control directly to Step 12's outer loop via its own caller-return path — it does NOT return back into the current invocation. Do NOT continue executing steps 3–7 of the current invocation, regardless of whether Phase 4 succeeds or bails.
       - **Fallback exit 2**: `force-with-lease` push failure after a successful rebase. The rebase is complete locally but the branch has NOT been pushed. Do NOT skip steps 3–4: proceed to step 3 (fast-forward local main), then step 4 (re-bump), then step 5 (which will try to push the re-bumped branch and apply its own fetch + compare + retry + bail recovery on any subsequent push failure). Setting `rebase_already_done` is NOT appropriate here because step 5 still needs to push. This is the only way to guarantee the freshness invariant is enforced — skipping straight to step 5's recovery would push a rebased-but-unbumped branch, silently violating the invariant.
       - **Fallback exit 3**: non-conflict rebase failure; rebase already aborted. Read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase conflict, deferring to Step 12. Proceeding to Step 11.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. **Break out of Step 10's loop and proceed to Step 11.**
   - **Exit 3** (non-conflict rebase failure in `--no-push` mode; rebase already aborted):
     - **step12 family**: read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase failed: $REBASE_ERROR. Proceeding to Step 11.**` Log to `CI Issues`. Break to Step 11.

3. **Fast-forward local `main` to `origin/main`**:
   `rebase-push.sh` refreshes `origin/main` via `git fetch`, but local `main` is not automatically updated. `classify-bump.sh` prefers local `main` for its `merge-base` computation, so without this step `BASE` could point to an older commit than the one the branch was just rebased onto, causing the classifier's diff to include commits that belong to main (not the feature).
   ```bash
   if git rev-parse --verify main >/dev/null 2>&1; then
     git branch -f main origin/main
   fi
   ```
   This is safe because Step 10 and Step 12's rebase loops always run on a feature branch, never on `main`. If the local `main` ref does not exist, silently skip — `classify-bump.sh` has an `origin/main` fallback.

4. **Re-bump**:
   Follow the same sequence as Step 8, with caller-family-specific error handling:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode pre
   ```
   Parse `HAS_BUMP` and `COMMITS_BEFORE`.
   - **If `HAS_BUMP=false`**:
     - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version not found, cannot re-bump. Bailing to 12d.**` Bail to 12d.
     - **step10 family**: Print `**⚠ 10: CI monitor — /bump-version not found, skipping re-bump. Proceeding to Step 11.**` Log to `Warnings`. Skip ahead to step 5 — the push still needs to happen because the rebase in step 2 rewrote branch history, and that rewritten history must be force-pushed so the remote PR branch reflects the new base (there is just no new bump commit stacked on top). Then fall through to step 6 (PR body refresh — nothing new to refresh) and step 7 (return to caller).
   - **If `HAS_BUMP=true`**: Invoke `/bump-version` via the Skill tool. If the skill invocation itself fails (returns an error, or bails internally):
     - **step12 family**: hard failure — bail to 12d.
     - **step10 family**: log warning and break out of Step 10 to Step 11.
     After the skill returns successfully, run the post-verification:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
     ```
     Parse `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`. Use the commit-count delta (not the skill's prose output) to detect the outcome — this is the reliable structured signal:

     - **`VERIFIED=true`** (a new commit was created — the common case): proceed to step 5.

     - **`VERIFIED=false` AND `COMMITS_AFTER == COMMITS_BEFORE`** (zero new commits — `/bump-version` ran a `BUMP_TYPE=NONE` no-op path, because `classify-bump.sh` detected HEAD is already a bump commit). This normally happens when `drop-bump-commit.sh` reported `DROPPED=false` (e.g., Guard 4 refused the drop because the bump commit touched files beyond `.claude-plugin/plugin.json`) and the stale bump commit survived the rebase unchanged. **Note**: this condition is also reached in the degenerate case where `count_commits()` in `check-bump-version.sh` returned `0` for both pre and post calls because neither local `main` nor `origin/main` exists — in that case, a `WARN: ... neither local 'main' nor 'origin/main' exists` line will have been printed to stderr. Before acting on the bail, check the stderr output of the most recent `check-bump-version.sh` calls for that WARN to determine the true root cause. Caller-family handling:
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — /bump-version created 0 new commits after rebase (BUMP_TYPE=NONE or missing main ref). Cannot verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues` (including the relevant stderr excerpt if the WARN was seen). Rationale: Step 12 is the last-chance enforcement point for the version bump freshness invariant. Either a stale bump commit classified against an older base or a missing base ref means we cannot guarantee the merged version is correct; we must fail loudly rather than silently merge a potentially-wrong version.
       - **step10 family**: log warning `**⚠ 10: CI monitor — /bump-version created 0 new commits (BUMP_TYPE=NONE or missing main ref). Proceeding to Step 11. Step 12 will re-attempt.**` to `Warnings`, then proceed directly to step 5 (the rebased history still needs to be force-pushed). Step 10 can afford to be permissive here because Step 12 re-runs the sub-procedure under strict semantics and will bail then if the drop still cannot happen.

     - **`VERIFIED=false` AND `COMMITS_AFTER != COMMITS_BEFORE`** (unexpected state — `/bump-version` created more than one commit, or somehow decreased the count):
       - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version created wrong commit count (expected $EXPECTED, got $COMMITS_AFTER). Bailing to 12d.**` Bail to 12d.
       - **step10 family**: log warning and break to Step 11.

   **Rationale**: Step 8's permissive warnings are safe because Step 8 is pre-PR — no merge can happen based on a missing bump. Step 12 is pre-merge — missing bump means stale merge. Step 10 is post-PR but pre-merge (Step 12 does the merge) — any bump failure in Step 10 is recoverable by Step 12's mandatory re-bump, so Step 10 can afford to be permissive. **Step 12 is the last-chance enforcement point; Step 10 is best-effort optimization that improves freshness during the Slack-wait phase.**

4a. **Re-apply CHANGELOG update** (mirrors Step 8a):
   If `CHANGELOG.md` exists in the project root (check via Read tool) and a new bump commit was created (`VERIFIED=true` from step 4), update the CHANGELOG entry to reflect the new version from the re-bump. Follow the same logic as Step 8a: read `CHANGELOG.md`, compose an entry with the `NEW_VERSION` from the re-bump and the same Summary bullets, insert it (or replace the existing entry for the prior version if present), stage, and amend the bump commit via `git add CHANGELOG.md && git commit --amend --no-edit`. If CHANGELOG.md does not exist or the bump was skipped, skip this sub-step silently. **This is best-effort and non-blocking** — failure to update CHANGELOG does not affect the bump or push.

5. **Push with recovery**:
   ```bash
   git push --force-with-lease
   ```
   If push exits 0: proceed to step 6. If push fails:
   a. Refresh the local tracking ref for the feature branch:
      ```bash
      BRANCH=$(git symbolic-ref --short HEAD)
      git fetch origin "$BRANCH"
      ```
   b. Compare `git rev-parse HEAD` with `git rev-parse "origin/$BRANCH"`. If equal, the push actually landed (rare race where the remote accepted but the client did not recognize it). Proceed to step 6.
   c. If they differ, the remote feature branch has something we don't. Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`: `Step <N> — force-with-lease push failed; local and remote feature branches diverge after re-bump.` Sleep 5s and retry the push ONCE:
      ```bash
      ${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 5
      git push --force-with-lease
      ```
      If the retry succeeds, proceed to step 6. If it fails again:
      - **step12 family**: bail to 12d with error `12: CI+merge loop — re-bump push failed twice, remote diverged. Manual intervention required.`
      - **step10 family**: print `**⚠ 10: CI monitor — re-bump push failed twice. Proceeding to Step 11 (may be stale).**` Log to `CI Issues`. Break to Step 11.

   **Critical (step12 family only)**: Do NOT simply "log and return to caller" on push failure. That would let the merge loop proceed to `ACTION=merge` on a remote branch that does NOT contain the fresh bump commit, violating the feature's core invariant. `ci-wait.sh` and `merge-pr.sh` operate on remote PR state only; they cannot see unpushed local commits.

6. **Refresh PR body Version Bump Reasoning block**:
   If `$IMPLEMENT_TMPDIR/bump-version-reasoning.md` exists and is non-empty:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md`, replace the entire inner content of the `<details><summary>Version Bump Reasoning</summary>...</details>` block with the current contents of `$IMPLEMENT_TMPDIR/bump-version-reasoning.md` (preserving blank lines after the opening tag and before the closing `</details>` for GitHub Markdown rendering). Write the result to `$IMPLEMENT_TMPDIR/pr-body.md` (same file Step 11 writes to, so subsequent refreshes operate on the fresh canonical copy). Then:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```
   If the `<details><summary>Version Bump Reasoning</summary>` marker is not found in the fetched body, print `**⚠ Step <N> — Version Bump Reasoning block not found in live PR body. Skipping refresh.**` and skip the update. Log to `Warnings`. **PR body refresh failure is NOT a hard failure** — the bump is already pushed and the merge will be correct; the stale body is documentation-only.

7. **Return to caller based on `caller_kind`**:
   - **`step12_rebase`** (from 12a `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30` (give GitHub CI time to register the force-push before polling again), then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_phase4`** (from Phase 4 exit-0): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_rebase_then_evaluate`** (from 12a `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to 12c** to evaluate the CI failure. Do NOT re-invoke `ci-wait.sh` and do NOT sleep — 12c handles its own timing.
   - **`step10_rebase`** (from Step 10 `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 10.
   - **`step10_rebase_then_evaluate`** (from Step 10 `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to Step 10's `ACTION=evaluate_failure` handler**. Do NOT re-invoke `ci-wait.sh` and do NOT sleep.

### Phase 4 caller path (`rebase_already_done=true`, `caller_kind=step12_phase4`)

Phase 4 enters the sub-procedure AFTER `rebase-push.sh --continue` has already pushed the resolved rebase. **Skip steps 1–2 entirely.** Still run steps 3 (fast-forward local main), 4 (re-bump with step12 hard-failure semantics), 5 (push with recovery), 6 (PR body refresh), 7 (return with `step12_phase4`). This path necessarily double-pushes (Phase 4 pushed the rebase, then step 5 pushes the new bump), but the Conflict Resolution Procedure is rare enough that the second push cost is acceptable.

## Step 10 — CI Monitor (initial wait for green)

**If `repo_unavailable=true`**: Print `⏭️ 10: CI monitor — skipped (repo unavailable)` and proceed to Step 11.

Wait for CI to go green so the Slack announcement (Step 11) links to a PR with passing CI. This step does **NOT merge** — Step 12 is the merge-aware loop that handles main advancement and merging.

**Best-effort re-bump during CI wait**: Step 10's rebase handler invokes the same **Rebase + Re-bump Sub-procedure** (defined just before this step) that Step 12 uses, with step10-family semantics: hard failures degrade gracefully (log warning, break out of Step 10 to Step 11) rather than bailing to 12d. This keeps the PR's version fresh during the Slack-wait phase while ensuring Step 10 never blocks the pipeline — Step 12 remains the last-chance enforcement point for the version bump freshness invariant.

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION`
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries (reset after rebase, code fix, or different failure)

**Wait for CI** using the `ci-wait.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=merge`**: CI passed and branch is up-to-date. Print `✅ 10: CI monitor — CI passed!` and proceed to Step 11. **Do NOT merge here** — Step 12 handles merging.

   - **`ACTION=already_merged`**: PR was merged externally during CI wait. Print `✅ 10: CI monitor — PR merged externally` and proceed to Step 11. (Step 12 will detect `already_merged` again and skip the merge loop.)

   - **`ACTION=rebase`**: Main advanced. Invoke the **Rebase + Re-bump Sub-procedure** (defined before this step) with `rebase_already_done=false`, `caller_kind=step10_rebase`. The sub-procedure handles drop-before-rebase, rebase, fast-forward local main, re-bump via `/bump-version`, push with recovery, and PR body refresh. On sub-procedure success, counter updates and `ci-wait.sh` re-invocation happen inside the sub-procedure's step 7. On sub-procedure failure (rebase conflict, re-bump failure, or push failure), the sub-procedure logs a warning and breaks out of Step 10 to Step 11 — it does NOT bail to 12d (Step 12 will re-run the sub-procedure under strict semantics).

   - **`ACTION=rebase_then_evaluate`**: Invoke the **Rebase + Re-bump Sub-procedure** with `rebase_already_done=false`, `caller_kind=step10_rebase_then_evaluate`. On sub-procedure success, fall through to the `ACTION=evaluate_failure` handler below. On sub-procedure failure, break to Step 11.

   - **`ACTION=evaluate_failure`**: Use `FAILED_RUN_ID` to evaluate:
     1. **Transient failure** (runner provisioning, Docker pull rate limit, "hosted runner lost communication", etc.): If `transient_retries < 2`, run `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 60`, then run `${CLAUDE_PLUGIN_ROOT}/scripts/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Parse output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Otherwise increment `transient_retries`, re-invoke `ci-wait.sh`. If `transient_retries >= 2`, treat as real failure.
     2. **Real CI failure**: Run `${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Diagnose the issue, fix it, run `/relevant-checks`, stage and commit using `${CLAUDE_PLUGIN_ROOT}/scripts/git-commit.sh -m "Fix CI failure" <fixed-files>`, push. Increment `fix_attempts`. Re-invoke `ci-wait.sh`.

   - **`ACTION=bail`**: Print `BAIL_REASON`. Print `**⚠ 10: CI monitor — bailed, PR may have failing CI**` and proceed to Step 11.

**Execution issues**: Log any CI failures, transient retries, or bail events to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `CI Issues` category.

After handling any non-terminal/non-rebase action (e.g., `evaluate_failure`), **re-invoke `ci-wait.sh`** with updated counter values. The `rebase` and `rebase_then_evaluate` paths handle their own post-return control flow inside the sub-procedure's step 7 — do NOT re-invoke `ci-wait.sh` from here for those paths. The adaptive sleep interval is handled by the caller: sleep 60s after a transient retry rerun before re-invoking `ci-wait.sh`.

## Step 11 — Post Slack Announcement

**If `slack_available=false`**: Print `⏭️ 11: slack announce — skipped (Slack not configured)` Set `SLACK_TS` to empty and proceed to the post-execution PR body refresh below.

**If `PR_STATUS=existing`**: Print `⏭️ 11: slack announce — skipped (PR already existed, run post-pr-announce.sh manually)` Set `SLACK_TS` to empty and proceed to the post-execution PR body refresh below.

**Otherwise** (`slack_available=true` and `PR_STATUS=created`):

Post the PR to Slack using the shared script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/post-pr-announce.sh --pr <PR-NUMBER>
```

Parse the output for `SLACK_TS=<value>` (emitted by `post-pr-announce.sh` — keep in sync).

**If the script exits non-zero or `SLACK_TS` is empty**: Print `**⚠ Slack announcement failed. Continuing.**` Set `SLACK_TS` to empty. Log the failure to `$IMPLEMENT_TMPDIR/execution-issues.md` under the `Tool Failures` category.

Save `SLACK_TS` for use in Step 13 (the :merged: emoji step).

### Post-execution PR body refresh

**This refresh runs unconditionally after all Step 11 branches converge — including when Slack was skipped (`slack_available=false`) or when `PR_STATUS=existing`. All Step 11 early-exit paths must reach this section before proceeding to Step 12.**

If `$IMPLEMENT_TMPDIR/execution-issues.md` exists and is non-empty, update the PR body to reflect the final execution issues (which may include issues logged during Steps 10–11, after the initial PR body was written):

1. Fetch the current live PR body using the read script (do NOT re-read `$IMPLEMENT_TMPDIR/pr-body.md` — the live body may differ from the local copy):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md` to get the current body text.
2. Replace the entire inner content of the `<details><summary>Execution Issues</summary>...</details>` block with the full current contents of `$IMPLEMENT_TMPDIR/execution-issues.md`, preserving the blank lines after the opening tag and before the closing `</details>` (required for GitHub Markdown rendering). If the `<details><summary>Execution Issues</summary>` block is not found in the fetched body, print `**⚠ Execution Issues block not found in live PR body. Skipping refresh.**` and skip the update.
3. Write the result to `$IMPLEMENT_TMPDIR/pr-body.md`
4. Update the PR:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```

If `execution-issues.md` does not exist or is empty, skip this refresh.

## Step 12 — CI + Rebase + Merge Loop

**If `merge=false`**: Print `⏭️ 12: CI+merge loop — skipped (--merge not set)` and skip to Step 16.

**If `repo_unavailable=true`**: Print `⏭️ 12: CI+merge loop — skipped (repo unavailable)` and skip to Step 16.

Monitor CI and the main branch **in parallel**. The key optimization: don't wait for CI to finish before checking if main has advanced.

**Version bump freshness invariant**: Every successful rebase in this loop is followed by a fresh `/bump-version` run against the new base, so the merged state reflects the version in latest `origin/main` at merge time — not at PR-creation time. This is handled by the **Rebase + Re-bump Sub-procedure** (defined before Step 10 above, shared with Step 10), invoked from 12a's rebase handlers and Phase 4's `--continue` exit-0 path. If re-bumping fails in any way that would leave the branch without a verified fresh bump commit, Step 12 bails to 12d rather than letting the merge loop proceed to a stale merge. (Step 10 uses the same sub-procedure but with best-effort semantics — Step 12 is the last-chance enforcement point.)

### 12a — Poll Loop

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION` (updated by the script during wait cycles)
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries, managed locally (used only in Step 12c; when this exceeds 2, treat as real failure and increment `fix_attempts`)

**Wait for CI** using the `ci-wait.sh` script, which polls `ci-status.sh` + `ci-decide.sh` internally and prints compact dot-based progress to stderr:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes, matching the script's 1800s default + grace).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=rebase`**: Print a context-specific message based on `CI_STATUS`: if `CI_STATUS=pass`, print `🔃 12: CI+merge loop — CI passed, main advanced, rebasing + re-bumping`; if `CI_STATUS=pending`, print `🔃 12: CI+merge loop — main advanced, rebasing + re-bumping` → invoke the **Rebase + Re-bump Sub-procedure** (defined before Step 10) with `rebase_already_done=false`, `caller_kind=step12_rebase`. The sub-procedure handles drop-before-rebase, rebase (with Phase 1–4 fallback on conflict), fast-forward local main, `/bump-version`, push with recovery, and PR body refresh. On successful return, counter updates (`rebase_count`, `iteration`, `transient_retries` reset) and `ci-wait.sh` re-invocation happen inside the sub-procedure's step 7. On hard failure, the sub-procedure bails to 12d directly.

   - **`ACTION=merge`**: Print `✅ 12: CI+merge loop — CI passed, main up-to-date, merging!` → proceed to **12b**.

   - **`ACTION=already_merged`**: Print `✅ PR was force-merged externally — skipping CI wait and merge.` → skip **12b** (no merge needed) and proceed directly to Step 13. The PR counts as successfully merged for Steps 13–15.

   - **`ACTION=rebase_then_evaluate`**: Invoke the **Rebase + Re-bump Sub-procedure** with `rebase_already_done=false`, `caller_kind=step12_rebase_then_evaluate`. On successful return (counter updates already done inside the sub-procedure), **fall through to 12c** to evaluate the CI failure. Do NOT re-invoke `ci-wait.sh` from the caller — the sub-procedure's `caller_kind=step12_rebase_then_evaluate` branch skips the re-invocation for this path. On hard failure, the sub-procedure bails to 12d.

   - **`ACTION=evaluate_failure`**: Evaluate the CI failure → **12c**.

   - **`ACTION=bail`**: Print `BAIL_REASON` and bail out → **12d**.

After handling any non-merge/non-bail/non-rebase action (e.g., `evaluate_failure`), **re-invoke `ci-wait.sh`** with updated counter values. The `rebase` and `rebase_then_evaluate` paths handle their own post-return control flow inside the sub-procedure's step 7: `rebase` sleeps 30s and re-invokes `ci-wait.sh` internally; `rebase_then_evaluate` falls through to 12c without sleeping. The remaining sleep interval handled by the caller: sleep 60s after a transient retry rerun.

### Conflict Resolution Procedure

When `rebase-push.sh` exits with code 1, the rebase is paused with conflicts. This procedure resolves them intelligently, with user escalation when uncertain and a full reviewer panel to validate the resolution.

**Bail invariant**: Any bail from any phase below must call `${CLAUDE_PLUGIN_ROOT}/scripts/git-rebase-abort.sh` before proceeding to Step 12d, since the rebase is in progress throughout all phases.

#### Phase 1 — Conflict Classification and Resolution

For each file in `CONFLICT_FILES`:

1. Run `git ls-files -u` to determine the conflict type per file (check which index stages 1/2/3 exist).
2. **Unsupported conflict types** — If any stage is missing (modify/delete, rename/delete conflicts) or the file is binary (check via `file --mime-type` or absence of text markers), classify as **uncertain**. Do not attempt auto-resolution.
3. **Trivial files** — If the file is `version.go`, `go.sum`, `.claude-plugin/plugin.json`, or auto-generated, classify as **trivial** and auto-resolve immediately. Stage with `git add`. For `.claude-plugin/plugin.json` specifically, resolve to the **upstream (main) version** (run `git checkout --ours -- .claude-plugin/plugin.json` — during rebase, `--ours` refers to the base being rebased onto, i.e., upstream main), because the Rebase + Re-bump Sub-procedure will overwrite `plugin.json` with a fresh bump in its step 4 after the rebase completes. See the note below.
4. **Text conflicts with both sides available** — Read both sides using explicit labels:
   - `git show :2:<file>` → **upstream (main)** version. If this command fails, classify as uncertain.
   - `git show :3:<file>` → **feature branch commit** version. If this command fails, classify as uncertain.
   - Also read the conflict markers in the working tree file for context.
5. **Classify confidence**:
   - **Trivial**: `version.go`, `go.sum`, `.claude-plugin/plugin.json`, auto-generated files.
   - **High-confidence**: Changes are in non-overlapping regions (both sides added content in different locations), or the conflict markers show only whitespace, import-order, or formatting differences. Both sides' intent is clear and composable.
   - **Uncertain**: Overlapping semantic changes to the same function/block, any file where correctness cannot be verified without domain knowledge, any file where `:2:` or `:3:` reads failed, any non-text/binary conflict.
6. Auto-resolve trivial and high-confidence files. Stage resolved files with `git add`.
7. **IMPORTANT**: Always use "upstream (main)" and "feature branch commit" labels when describing the two sides of a conflict — never use "ours"/"theirs" which have inverted semantics during rebase and will cause confusion.

**Note on `.claude-plugin/plugin.json` conflicts**: Under normal operation, the Rebase + Re-bump Sub-procedure drops the bump commit before rebasing, so `.claude-plugin/plugin.json` should not appear in `CONFLICT_FILES`. However, when `drop-bump-commit.sh` reported `DROPPED=false` (a CI fix commit landed on top of the bump, the worktree was dirty, or the commit touched more than `plugin.json`), the stale bump remains mid-stack and WILL conflict on `plugin.json` during rebase. The trivial-files rule above handles this case by auto-resolving to the upstream (main) version — safe because sub-procedure step 4 will overwrite `plugin.json` with a fresh `/bump-version` commit after the rebase completes.

#### Phase 2 — User Escalation (for uncertain conflicts)

**If there are no uncertain conflicts**, skip to Phase 3.

- **If `auto_mode=false`**: Call `AskUserQuestion` with the upstream (main) version, the feature branch commit version, and a proposed resolution for each uncertain file, batched into a single call. Use explicit "upstream (main)" and "feature branch commit" labels. Incorporate the user's answer, write the resolved file, and stage with `git add`. If the user indicates the conflict cannot be resolved or asks to abort, run `git rebase --abort` and **bail out** (Step 12d).
- **If `auto_mode=true`**: Attempt best-effort resolution for uncertain conflicts. If confidence is too low for any file (e.g., modify/delete conflict, conflicting business logic with no composable path, one side deleted code the other modified), run `git rebase --abort` and **bail out** (Step 12d).

#### Phase 3 — Reviewer Panel on Conflict Resolution

**If ALL conflicts were trivial** (no high-confidence or uncertain conflicts): Skip Phase 3 entirely. Proceed to Phase 4.

**Otherwise**, run a full reviewer panel to validate the non-trivial conflict resolutions:

**3a. Create temp directory**: Create `$IMPLEMENT_TMPDIR/conflict-review/` for reviewer artifacts. If it already exists (from a prior conflict resolution in this rebase loop), remove it and recreate.

**3b. Check external reviewer availability**: Follow the **Binary Check and Health Probe** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`. Honor any `CODEX_HEALTHY=false` / `CURSOR_HEALTHY=false` state from the session-env (reviewers already known to be unhealthy should not be re-probed or used).

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

**3d. Launch reviewers**: Launch 2 Claude subagent reviewers + Codex + Cursor (if available) using the reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md` with:
- `{REVIEW_TARGET}` = `"merge conflict resolution"`
- `{CONTEXT_BLOCK}` = the per-file conflict context blocks from 3c + supplementary `git diff --cached`
- `{OUTPUT_INSTRUCTION}` = `"File path and line number(s)"` + `"What the issue is with the resolution"` + `"Suggested correction"`

Follow `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md` for launch order (Cursor first, Codex, then Claude subagents), background execution, sentinel polling via `wait-for-reviewers.sh`, and output validation. Use `$IMPLEMENT_TMPDIR/conflict-review/` as the tmpdir for all reviewer output files, sentinel files, and ballot files.

**3d-ii. Collect and deduplicate**: After all reviewers complete, collect their findings. Parse Claude subagent dual-list outputs (in-scope findings + OOS observations). Read and validate external reviewer outputs per `external-reviewers.md`. Merge all findings, deduplicate (same file + same issue = one finding), assign stable sequential IDs (`FINDING_1`, `FINDING_2`, etc.), and write the ballot to `$IMPLEMENT_TMPDIR/conflict-review/ballot.txt` following the ballot format in `voting-protocol.md`.

**3e. Voting**: Run the voting protocol from `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md` with code review voter composition:
- **Voter 1**: Claude General Reviewer subagent (fresh Agent invocation)
- **Voter 2**: Codex (if available) — via `run-external-reviewer.sh`
- **Voter 3**: Cursor (if available) — via `run-external-reviewer.sh`

If fewer than 2 voters are available: skip voting, accept all reviewer findings (per `voting-protocol.md` fallback), implement them, and continue to Phase 4.

If voting **accepts findings** (2+ YES votes): re-resolve the affected files incorporating the accepted suggestions, re-stage, and re-run review (3c through 3e). Allow up to **2 total resolution-review rounds**.

After 2 rounds with unresolved findings still being raised: run `git rebase --abort` and **bail out** (Step 12d).

If the reviewer panel finds no issues or all findings are addressed: proceed to Phase 4.

**3f. Cleanup**: Remove `$IMPLEMENT_TMPDIR/conflict-review/` after Phase 3 completes (on both success and bail paths, before proceeding).

#### Phase 4 — Continue Rebase

Run `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --continue` and handle exit codes:
- **Exit 0**: Rebase and push succeeded. Invoke the **Rebase + Re-bump Sub-procedure** (defined before Step 10) with `rebase_already_done=true`, `caller_kind=step12_phase4`. The sub-procedure performs fast-forward of local main, re-bump via `/bump-version` (with step12 hard-failure semantics), push of the new bump commit with recovery, and PR body refresh. Counter updates and `ci-wait.sh` re-invocation are handled inside the sub-procedure's step 7. If the sub-procedure bails to 12d on hard failure, Phase 4's exit-0 handler also bails to 12d.
- **Exit 1**: A later commit in the rebase conflicted. Loop back to **Phase 1** for the new conflict (the Conflict Resolution Procedure starts again for the new set of `CONFLICT_FILES`).
- **Exit 2**: Push `--force-with-lease` failed. Retry `rebase-push.sh --continue` once. If it fails twice, **bail out** (Step 12d — call `git rebase --abort` first if the rebase is still in progress).
- **Exit 3**: Check the `REBASE_ERROR` output. If it indicates an empty or already-applied commit (e.g., "nothing to commit", "No changes"), run `git rebase --skip` (if `git rebase --skip` itself exits non-zero, run `${CLAUDE_PLUGIN_ROOT}/scripts/git-rebase-abort.sh` and **bail out** — Step 12d) and then `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --continue` again (handle the same exit codes). Otherwise, **bail out** (Step 12d).

### 12b — Merge

When CI passes and the branch is up-to-date with main, use the `merge-pr.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/merge-pr.sh --pr <PR-NUMBER> --repo $REPO
```

Parse the output for `MERGE_RESULT` and `ERROR`. Handle each result:

- **`MERGE_RESULT=merged`**: Print `✅ 12: CI+merge loop — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=admin_merged`**: Print `**⚠ Merged with --admin (review overridden).** ✅ 12: CI+merge loop — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=main_advanced`**: Go back to **12a** (the next iteration will detect the branch is behind and rebase).
- **`MERGE_RESULT=ci_not_ready`**: Go back to **12a** (CI may need more time or a rerun).
- **`MERGE_RESULT=admin_failed`**: Bail out (Step 12d) with the `ERROR` message.
- **`MERGE_RESULT=error`**: Bail out (Step 12d) with the `ERROR` message.

**CRITICAL: The `--admin` safety invariant is enforced inside `merge-pr.sh` — it re-verifies CI and branch freshness before attempting `--admin`. See the script's header for the full invariant. This is the canonical `--admin` implementation.**

Save the expected commit title for verification in Step 15: `<PR_TITLE> (#<PR_NUMBER>)` (using the `PR_TITLE` saved in Step 9).

### 12c — Evaluate CI Failure

Use `FAILED_RUN_ID` from the `ci-status.sh` output. If `FAILED_RUN_ID` is empty, use `${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-checks.sh --pr <PR-NUMBER> --repo $REPO` to identify the failed check and its run URL manually.

1. **Transient/infrastructure failure** (GitHub API timeout, runner provisioning failure, flaky network, `RUNNER_TEMP` errors, Docker pull rate limit, "The hosted runner lost communication", etc.):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 60
   ${CLAUDE_PLUGIN_ROOT}/scripts/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Parse the output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Allow up to **2 consecutive transient retries** before treating as a real failure. The counter resets after a successful rebase, code fix, or a CI run that fails for a different (non-transient) reason. Go back to **12a**.

2. **Real CI failure** — Diagnose and fix:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Analyze the logs. Fix the issue, run `/relevant-checks`, commit, push. Go back to **12a**.

### 12d — Bail Out

**Bail out** if any of these are true:
- You've already attempted **3 fix iterations** without progress (same or new errors each time).
- The failure is **fundamentally incompatible** with the codebase or CI.
- The fix would require **reverting the core feature** to pass CI.

When bailing out:
1. If a rebase is in progress (exit 1 from `rebase-push.sh`), run `${CLAUDE_PLUGIN_ROOT}/scripts/git-rebase-abort.sh` first.
2. Clearly explain what failed, what you attempted, and suggest manual steps.

**Do NOT skip Steps 14, 16, 17, and 18** when bailing — still clean up and print the review report. **Skip Steps 13 and 15** since the PR was not merged.

## Step 13 — Add :merged: Emoji to Slack Post

**If `merge=false`**: Skip this step.

**If `slack_available=false`**: Print `⏭️ 13: merged emoji — skipped (Slack not configured)` and proceed to Step 14.

**Only if the PR was successfully merged in Step 12b or force-merged externally** (not bailed in 12d).

**Only if `SLACK_TS` from Step 11 is non-empty** (Slack announcement succeeded).

Add the :merged: emoji using the shared script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/post-merged-emoji.sh --slack-ts "$SLACK_TS"
```

**If the script exits non-zero**, print `**⚠ Failed to add :merged: emoji to Slack post. Continuing.**` and proceed to Step 14. **Do not abort.**

## Step 14 — Local Cleanup

**If `merge=false`**: Print `⏭️ 14: local cleanup — skipped (--merge not set), still on $BRANCH_NAME` and skip to Step 16.

**If the PR was successfully merged (Step 12b or force-merged externally)**:

Switch back to main, pull the merged changes, and delete the development branch:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/local-cleanup.sh --branch "$BRANCH_NAME"
```

Parse the output for `CLEANUP_SUCCESS`, `CURRENT_BRANCH`, and `BRANCH_DELETED`. If `CLEANUP_SUCCESS=true`, print: `✅ 14: local cleanup — switched to main, deleted $BRANCH_NAME`. If `CLEANUP_SUCCESS=false`, print: `**⚠ 14: local cleanup — partially failed, branch: <CURRENT_BRANCH>, deleted: <BRANCH_DELETED>**`

**If Step 12 bailed out (PR was NOT merged)**:

Do NOT switch branches or delete the local branch. The user will need the branch to continue manually.

Print: `⚠ 14: local cleanup — skipped (PR not merged), still on $BRANCH_NAME`

`$BRANCH_NAME` is the variable captured at the end of Step 1 (after branch resolution by `/design` or quick-mode branch creation).

## Step 15 — Verify Main

**If `merge=false`**: Skip this step.

**Only if the PR was successfully merged (Step 12b or force-merged externally)** (skip if bailed out).

Confirm the last commit on main is the expected squash-merged commit using the `verify-main.sh` script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify-main.sh --expected-title "<PR_TITLE> (#<PR_NUMBER>)"
```

Parse the output for `VERIFIED`, `COMMIT_HASH`, and `COMMIT_MESSAGE`. Print the result:

- If `VERIFIED=true`: `✅ 15: verify main — at <COMMIT_HASH> "<COMMIT_MESSAGE>"`
- If `VERIFIED=false`: `**⚠ 15: verify main — unexpected HEAD: <COMMIT_HASH> "<COMMIT_MESSAGE>". Expected: "<PR_TITLE> (#<PR_NUMBER>)"**`

## Step 16 — Rejected Code Review Findings Report

Print a report of all code review suggestions that were **not** implemented.

1. Check if `$IMPLEMENT_TMPDIR/rejected-findings.md` exists and is non-empty.
2. If it has content, print it under a `## Unimplemented Code Review Suggestions` header, formatted clearly with the reviewer name, the suggestion, and the reason for each.
3. If the file doesn't exist or is empty, print: `✅ 16: rejected findings — all suggestions implemented`

## Step 17 — Final Report

**If `quick_mode=true`**: Print: `✅ 17: final report — quick mode (/design skipped, 2 subagent review)`

**If `quick_mode=false`**: Print a summary noting that:
- Plan review findings were reported by the `/design` phase (visible in conversation above)
- Code review findings were reported by the `/review` phase (visible in conversation above)

If both phases reported all suggestions implemented, print: `✅ 17: final report — all suggestions implemented (plan + code review)`

## Step 18 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$IMPLEMENT_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier in the workflow (from `/design` or `/review` phases) so they are visible at the end. **If `quick_mode=true`**, there are no external reviewer warnings to repeat (no external reviewers were used). For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`

If `merge=false`, remind: `**Note: --merge was not set. PR was created but not merged. Merge manually when ready.**`

Print: `✅ 18: cleanup — implement complete!`
