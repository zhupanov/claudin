---
name: implement
description: Implement a feature from design through PR creation, CI monitoring, and Slack announcement, with code review and version bump. Monitors CI and fixes failures so the PR is green. Does not merge — use /shazam for the full end-to-end workflow including merge.
argument-hint: "[--quick] [--auto] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Implement Skill

Implement a feature from design through PR creation, CI monitoring, and Slack announcement: code, validate, commit, code review, validate, commit, version bump, PR, CI monitor and fix, Slack announce.

The feature to implement is described by `$ARGUMENTS` after flag stripping.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, save the remainder as `FEATURE_DESCRIPTION` — use this (not raw `$ARGUMENTS`) whenever the human-readable feature description is needed (e.g., PR body, design invocation, commit messages).

- `--quick`: Set a mental flag `quick_mode=true`. When `quick_mode=true`: Step 1 skips `/design` (main agent creates branch and inline plan directly), Step 5 skips `/review` (main agent runs a simplified one-round review with 4 Claude subagents only — no external reviewers, no voting panel), and Step 7a skips the Code Flow Diagram.
- `--auto`: Set a mental flag `auto_mode=true`. When `auto_mode=true`: (a) forward `--auto` to `/design` invocation in Step 1, suppressing `/design`'s interactive question checkpoints; (b) suppress `/implement`'s own opportunistic questions in Step 2. When `--quick` is also set and `/design` is skipped, `--auto` still suppresses `/implement`'s Step 2 questions. The default (no `--auto`) enables interactive questions.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/shazam`) and will be forwarded to `session-setup.sh` via `--caller-env` and to `/design` via `--session-env`. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).
- `--no-merge` (compatibility): Strip it and print: `**Note: The --no-merge flag has moved to /shazam. /implement creates a PR, monitors CI, and posts a Slack announcement but does not merge. Use /shazam <description> for the full workflow including merge.**` Then proceed with the remainder as the feature description.

## Progress Reporting

**Every step MUST print clearly visible status lines** so the user can instantly see where execution is at. Use distinct emoji prefixes:

- Print a **start line** when entering a step: e.g., `🛠️ Step 2 — Implementing feature...`
- Print a **completion line** when done: e.g., `✅ Step 2 — Implementation complete`
- For long-running steps, print **intermediate progress**

Suggested emoji palette (use consistently):
| Step | Emoji | Description |
|------|-------|-------------|
| 0 | 🔧 | Session setup |
| 1 | 📐 | Ensure design plan |
| 2 | 🛠️ | Implementation |
| 3 | 🧹 | Lint (first pass) |
| 4 | 💾 | First commit |
| 5 | 🔍 | Code review |
| 6 | 🧹 | Lint (second pass) |
| 7 | 💾 | Second commit |
| 8 | 🏷️ | Version bump |
| 9 | 🚀 | Create PR |
| 10 | 🔄 | CI monitor and fix |
| 11 | 📋 | Slack announcement |
| 12 | 📊 | Rejected findings report |
| 13 | 🏁 | Cleanup |

## Step 0 — Session Setup

Run the shared session setup script. If `SESSION_ENV_PATH` is non-empty (passed via `--session-env`), include `--caller-env` to reuse already-discovered values:

```bash
$PWD/.claude/scripts/generic/session-setup.sh --prefix claude-impl --skip-branch-check [--caller-env "$SESSION_ENV_PATH"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` if `SESSION_ENV_PATH` is non-empty.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `SLACK_TOKEN_OK`, `REPO`, `REPO_UNAVAILABLE`. Set:
- `IMPL_TMPDIR` = `SESSION_TMPDIR`
- If `SLACK_TOKEN_OK=false`, print: `**⚠ SLACK_BOT_TOKEN is not set. Slack announcement (Step 11) will be skipped.**` Set a mental flag `slack_available=false`.
- If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository name. CI monitoring (Step 10) will be skipped.**` Set a mental flag `repo_unavailable=true`.

### Write Session Env for Child Skills

Write the discovered values to `$IMPL_TMPDIR/session-env.sh` so they can be forwarded to `/design`:

```bash
$PWD/.claude/scripts/generic/write-session-env.sh --output "$IMPL_TMPDIR/session-env.sh" \
  --slack-token-ok <value> --repo <value> --repo-unavailable <value>
```

This file will be passed to `/design` via `--session-env` in Step 1.

## Execution Issues Tracking

Throughout execution, log noteworthy issues to `$IMPL_TMPDIR/execution-issues.md`. This file captures problems worth investigating later but that do not block the current task. **Any step** may append to this file when an issue is encountered.

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
$PWD/.claude/scripts/generic/create-branch.sh --check
```

Parse the output for `CURRENT_BRANCH`, `IS_MAIN`, `IS_USER_BRANCH`, and `USER_PREFIX`.

### Quick mode (`quick_mode=true`)

Skip `/design` entirely. Handle branch creation directly, then produce an inline implementation plan.

**Branch handling** (same logic as `/design` Step 1, replicated here since `/design` is skipped):
- If `IS_MAIN=true`: Derive a short kebab-case branch name from the feature description. Create it via `$PWD/.claude/scripts/generic/create-branch.sh --branch <USER_PREFIX>/<branch-name>`.
- If `IS_USER_BRANCH=true`: Verify the branch name (`CURRENT_BRANCH`) aligns with the requested feature. If it appears unrelated (different feature name, unrelated commits), print a warning: `**⚠ Current branch '<branch-name>' may not match the requested feature. Creating a new branch from main.**` and create a new branch. Otherwise, use the existing branch.
- Otherwise (non-main, non-user branch): Print a warning: `**⚠ Currently on branch '<branch-name>' which doesn't match the expected '<USER_PREFIX>/*' pattern. Creating a new branch from main.**` and create a new branch.

**Inline design**: Research the codebase (read relevant files, grep for patterns), then produce a concrete implementation plan under a `## Implementation Plan` header. This plan should include files to modify, approach, and edge cases — the same content `/design` would produce, but without collaborative sketches, plan review, or voting. Print: `⚡ Step 1 — Quick mode: skipped /design, produced inline plan.`

Proceed to Step 2.

### Normal mode (`quick_mode=false`)

**Decision logic**:
- If `IS_USER_BRANCH=true` **AND** a reviewed implementation plan is visible in the conversation context above: The plan was created by a prior `/design` invocation in this session. Proceed to Step 2.
- If `IS_USER_BRANCH=true` but **no** implementation plan is visible in the conversation context: Invoke the `/design` skill with `--session-env $IMPL_TMPDIR/session-env.sh` prepended to the feature description to create a plan on the current branch. **If `auto_mode=true`, also prepend `--auto`** so `/design` suppresses interactive questions. After `/design` completes, proceed to Step 2.
- If on `main` or empty (detached HEAD) or any non-user branch: No design plan exists yet. Invoke the `/design` skill with `--session-env $IMPL_TMPDIR/session-env.sh` prepended to the feature description to create a branch and design the plan. **If `auto_mode=true`, also prepend `--auto`** so `/design` suppresses interactive questions. After `/design` completes, proceed to Step 2.

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
$PWD/.claude/scripts/generic/git-commit.sh -m "<descriptive commit message>" <specific-files>
```

The commit message should describe WHAT was implemented and WHY, not HOW.

## Step 5 — Code Review

### Quick mode (`quick_mode=true`)

Skip `/review`. Instead, run a simplified one-round review:

1. Gather the diff using the context script:
   ```bash
   $PWD/.claude/scripts/generic/gather-branch-context.sh --output-dir "$IMPL_TMPDIR"
   ```
   Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log.
2. Launch **4 Claude subagent reviewers** (generic, correctness, risk/integration, architect) using the same reviewer archetypes from `.claude/skills/shared/reviewer-templates.md` with these variable bindings: `{REVIEW_TARGET}` = `"code changes"`, `{CONTEXT_BLOCK}` = the commit log + file list + full diff, `{OUTPUT_INSTRUCTION}` = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix"`. **No Codex, no Cursor, no external reviewers. No competition notice** (there is no voting panel in quick mode).
3. Collect findings from all 4 subagents. Deduplicate.
4. **Main agent decides**: Evaluate each finding and unilaterally accept or reject it. No voting panel. Accept findings that identify genuine bugs, logic errors, or important improvements. Reject trivial style nits or speculative concerns.
5. Implement accepted fixes. Run `/relevant-checks` if files changed.
6. **One round only** — no re-review loop.
7. For rejected findings, write them to `$IMPL_TMPDIR/rejected-findings.md` using the same format as normal mode (see below), so Step 12 and PR body sections work unchanged.

Print: `🔍 Step 5 — Quick mode: simplified review (4 Claude subagents, 1 round, no voting).`

### Normal mode (`quick_mode=false`)

**IMPORTANT: Code review must ALWAYS be invoked via `/review`. Never skip this step regardless of the nature of the changes — whether code, skills, documentation, data files, or configuration. All changes require full review.**

Invoke the `/review` skill. This launches 4 parallel Claude subagent reviewers (generic, correctness, risk/integration, architect) plus Codex and Cursor reviewers (if available), implements their suggestions recursively until clean.

### Track Rejected Code Review Findings

After the code review completes (whether `/review` in normal mode or the simplified review in quick mode), examine the final output. For any **in-scope** findings that were not accepted (not enough YES votes in normal mode — whether rejected or exonerated — or rejected by the main agent in quick mode), append each to `$IMPL_TMPDIR/rejected-findings.md` using this format. **Do not include non-promoted OOS items** — those are reported separately in the "Out-of-Scope Observations" PR body section:

```markdown
### [Code Review] <Reviewer Name>
**Finding**: <thorough description of the finding — include the specific file(s) and line(s) affected, what the reviewer identified as the issue, and what change they suggested. Must be detailed enough to serve as an actionable TODO item if later prioritized. Do NOT use a terse one-liner — a reader who has never seen the original review must be able to understand the issue and act on it.>
**Reason not implemented**: <complete justification for why this finding was not addressed — include the specific technical reasoning, any relevant context about project conventions or design decisions, and why the current code is acceptable despite the finding. Do NOT abbreviate — preserve all important details from the evaluation.>
```

## Step 6 — Relevant Checks (second pass)

**Conditional**: Check if the code review step (Step 5) actually modified any files (applies in both normal and quick mode):

```bash
$PWD/.claude/skills/implement/scripts/check-review-changes.sh
```

Parse the output for `FILES_CHANGED`. If `FILES_CHANGED=false`, print: `⏩ Step 6 — Skipping second validation — review made no changes.` and skip Steps 6 and 7 (but NOT Step 7a — the Code Flow Diagram step runs unconditionally).

If files **did change**, invoke `/relevant-checks` to ensure review fixes didn't introduce new issues. If checks fail, diagnose and fix, then re-invoke `/relevant-checks`.

## Step 7 — Second Commit (review fixes)

If any files changed during review/checks (Steps 5–6), stage and commit them:

```bash
$PWD/.claude/scripts/generic/git-commit.sh -m "Address code review feedback" <specific-files>
```

If no files changed (review found no issues), skip this commit.

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

**If diagram generation fails** (e.g., the implementation is too abstract to diagram meaningfully), print: `**⚠ Step 7a — Code flow diagram generation failed. Proceeding without diagram.**` Log this warning to `$IMPL_TMPDIR/execution-issues.md` under the `Warnings` category.

## Step 8 — Version Bump

Check if the repo has a `/bump-version` skill and capture commit count:

```bash
$PWD/.claude/scripts/generic/check-bump-version.sh --mode pre
```

Parse the output for `HAS_BUMP` and `COMMITS_BEFORE`.

**If `HAS_BUMP=false`**: Print `**⚠ VERSION BUMP SKIPPED: No /bump-version skill found at .claude/skills/bump-version/SKILL.md. To enable automatic version bumps, create a /bump-version skill in this repo. The skill should determine the current version, classify the bump type, compute the new version, edit the version file, and commit. Use /skill-creator for guidance.**` and skip to Step 9.

**If `HAS_BUMP=true`**:

1. Invoke `/bump-version` via the Skill tool.
2. Verify a new commit was created:
   ```bash
   $PWD/.claude/scripts/generic/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
   ```
   Parse for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`. If `VERIFIED=false`, print: `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`

**Important**: There must be exactly ONE version bump per PR, and it must be the LAST commit before creating the PR. Proceed immediately to Step 9 after `/bump-version` returns — no commits may occur between.

## Step 9 — Create PR

### 9a — Prepare PR body

Write the PR body to a temp file at `$IMPL_TMPDIR/pr-body.md`. The PR body is the single source of truth for all report content — there are no separate report files.

```markdown
## Summary
<1-3 bullet points in past tense describing what was changed and why (e.g., "Refactored X to improve Y", not "Refactor X to improve Y")>

<details><summary>Architecture Diagram</summary>

<the Architecture Diagram (mermaid code fence) from the /design phase's Step 3b output visible in conversation context above. Copy the mermaid code fence as printed. If the Architecture Diagram is not visible in conversation context (e.g., /design was interrupted, context was truncated, or /implement was run standalone without /design), write "Architecture diagram not available.">

</details>

<details><summary>Code Flow Diagram</summary>

<the Code Flow Diagram (mermaid code fence) from Step 7a output above. Copy the mermaid code fence as printed. If the Code Flow Diagram was not generated (generation failed), write "Code flow diagram not available.">

</details>

<details><summary>Goal</summary>

<bullet points in infinitive/base-form verb tense capturing the problem statement, user intent, and success criteria — the "why and what," not the "how" (e.g., "Add support for X", not "Added support for X"). Draw from all available conversation context: the original feature description ($ARGUMENTS), collaborative sketch synthesis, the final/revised implementation plan, plan review feedback, and any additional human input. Organize as a hierarchical bullet subtree: group minor tasks under their parent major tasks (more than 1 level deep) rather than a flat list. Preserve all substantive details from the original request.>

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

<content from $IMPL_TMPDIR/rejected-findings.md if it exists and is non-empty, otherwise "All code review suggestions were implemented.">

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

<content from $IMPL_TMPDIR/execution-issues.md if it exists and is non-empty, otherwise "No execution issues encountered.">

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
- **Code Review Voting Tally (Round 1)**: Write "Quick mode — no voting panel. Main agent reviewed findings from 4 Claude subagents."
- **Implementation Deviations**: Compare implementation to the inline plan (same as normal mode).
- **Out-of-Scope Observations**: Write "Quick mode — no out-of-scope observations collected."
- **Run Statistics**: Set "Plan review findings" to "N/A (quick mode)", "External reviewers" to "N/A (quick mode)". Code review findings should reflect the quick review results.

### 9b — Create PR via script

Run the `create-pr.sh` script with a concise title (under 70 chars):

```bash
$PWD/.claude/scripts/generic/create-pr.sh --title "<title>" --body-file "$IMPL_TMPDIR/pr-body.md"
```

Parse the output for `PR_NUMBER`, `PR_URL`, `PR_TITLE`, and `PR_STATUS`. The script handles pushing the branch, detecting existing PRs, and creating new ones with `--assignee @me`. `PR_STATUS` is `created` for new PRs or `existing` for already-open PRs. Save `PR_STATUS` — it is used in Step 11 to decide whether to post to Slack.

**If `create-pr.sh` exits non-zero**, print the error from its output and abort. Do not proceed to Steps 11–13.

**If `PR_STATUS=existing`**: The PR body was not updated by `create-pr.sh`. Update it now:
```bash
$PWD/.claude/scripts/generic/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPL_TMPDIR/pr-body.md"
```

Print the PR URL when done. Then print the PR number, URL, and title in a machine-parseable format (consumed by `/shazam` Step 1 — keep in sync):

```
PR_NUMBER=<N>
PR_URL=<url>
PR_TITLE=<title>
```

## Step 10 — CI Monitor and Fix

**If `repo_unavailable=true`**: Print `⏭️ Step 10 — Skipped (repository name could not be determined).` and proceed to Step 11.

Monitor CI and fix failures so the PR is green when `/implement` exits. This step does **NOT merge** — merging remains `/shazam`'s responsibility.

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION`
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries (reset after rebase, code fix, or different failure)

**Wait for CI** using the `ci-wait.sh` script:

```bash
$PWD/.claude/scripts/generic/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=merge`**: CI passed and branch is up-to-date. Print `✅ Step 10 — CI passed!` and proceed to Step 11. **Do NOT merge.**

   - **`ACTION=already_merged`**: PR was merged externally during CI wait. Print `✅ Step 10 — PR was merged externally.` and proceed to Step 11.

   - **`ACTION=rebase`**: Main advanced. Run `$PWD/.claude/scripts/generic/rebase-push.sh`. On exit 0: increment `rebase_count` and `iteration`, reset `transient_retries`, re-invoke `ci-wait.sh`. On exit 1 (conflicts): run `$PWD/.claude/scripts/generic/git-rebase-abort.sh`, print warning, and proceed to Step 11 (bail). On exit 2: retry once, then bail. On exit 3: bail.

   - **`ACTION=rebase_then_evaluate`**: Run rebase first (same as above), then fall through to evaluate the CI failure.

   - **`ACTION=evaluate_failure`**: Use `FAILED_RUN_ID` to evaluate:
     1. **Transient failure** (runner provisioning, Docker pull rate limit, "hosted runner lost communication", etc.): If `transient_retries < 2`, run `$PWD/.claude/scripts/generic/sleep-seconds.sh 60`, then run `$PWD/.claude/scripts/generic/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Parse output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Otherwise increment `transient_retries`, re-invoke `ci-wait.sh`. If `transient_retries >= 2`, treat as real failure.
     2. **Real CI failure**: Run `$PWD/.claude/scripts/generic/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO`. Diagnose the issue, fix it, run `/relevant-checks`, stage and commit using `$PWD/.claude/scripts/generic/git-commit.sh -m "Fix CI failure" <fixed-files>`, push. Increment `fix_attempts`. Re-invoke `ci-wait.sh`.

   - **`ACTION=bail`**: Print `BAIL_REASON`. Print `**⚠ Step 10 — CI monitoring bailed. PR may have failing CI.**` and proceed to Step 11.

**Execution issues**: Log any CI failures, transient retries, or bail events to `$IMPL_TMPDIR/execution-issues.md` under the `CI Issues` category (see Execution Issues Tracking section above).

After handling any non-terminal action (rebase, evaluate_failure), **re-invoke `ci-wait.sh`** with updated counter values.

## Step 11 — Post Slack Announcement

**If `slack_available=false`**: Print `⏭️ Step 11 — Skipped (SLACK_BOT_TOKEN not set).` Print `SLACK_TS=` and proceed to the post-execution PR body refresh below.

**If `PR_STATUS=existing`**: Print `⏭️ Step 11 — Skipped (PR already existed, avoiding duplicate Slack post). Run post-pr-announce.sh --pr <PR-NUMBER> manually to post the announcement.` Print `SLACK_TS=` and proceed to the post-execution PR body refresh below.

**Otherwise** (`slack_available=true` and `PR_STATUS=created`):

Post the PR to Slack using the shared script:

```bash
$PWD/.claude/scripts/generic/post-pr-announce.sh --pr <PR-NUMBER>
```

Parse the output for `SLACK_TS=<value>` (emitted by `post-pr-announce.sh` — keep in sync).

**If the script exits non-zero or `SLACK_TS` is empty**: Print `**⚠ Slack announcement failed. Continuing.**` Set `SLACK_TS` to empty. Log the failure to `$IMPL_TMPDIR/execution-issues.md` under the `Tool Failures` category.

Print the Slack timestamp in a machine-parseable format (consumed by `/shazam` Step 1 — keep in sync). Always output this line, even when empty:

```
SLACK_TS=<value>
```

### Post-execution PR body refresh

**This refresh runs unconditionally after all Step 11 branches converge — including when Slack was skipped (`slack_available=false`) or when `PR_STATUS=existing`. All Step 11 early-exit paths must reach this section before proceeding to Step 12.**

If `$IMPL_TMPDIR/execution-issues.md` exists and is non-empty, update the PR body to reflect the final execution issues (which may include issues logged during Steps 10–11, after the initial PR body was written):

1. Fetch the current live PR body using the read script (do NOT re-read `$IMPL_TMPDIR/pr-body.md` — the live body may differ from the local copy):
   ```bash
   $PWD/.claude/scripts/generic/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPL_TMPDIR/live-body.md"
   ```
   Read `$IMPL_TMPDIR/live-body.md` to get the current body text.
2. Replace the entire inner content of the `<details><summary>Execution Issues</summary>...</details>` block with the full current contents of `$IMPL_TMPDIR/execution-issues.md`, preserving the blank lines after the opening tag and before the closing `</details>` (required for GitHub Markdown rendering). If the `<details><summary>Execution Issues</summary>` block is not found in the fetched body, print `**⚠ Execution Issues block not found in live PR body. Skipping refresh.**` and skip the update.
3. Write the result to `$IMPL_TMPDIR/pr-body.md`
4. Update the PR:
   ```bash
   $PWD/.claude/scripts/generic/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPL_TMPDIR/pr-body.md"
   ```

If `execution-issues.md` does not exist or is empty, skip this refresh.

## Step 12 — Rejected Code Review Findings Report

Print a report of all review suggestions that were **not** implemented.

1. Check if `$IMPL_TMPDIR/rejected-findings.md` exists and is non-empty.
2. If it has content, print it under a `## Unimplemented Code Review Suggestions` header, formatted clearly with the reviewer name, the suggestion, and the reason for each.
3. If the file doesn't exist or is empty, print: `📊 Step 12 — All code review suggestions were implemented.`

## Step 13 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
$PWD/.claude/scripts/generic/cleanup-tmpdir.sh --dir "$IMPL_TMPDIR"
```

Print: `🏁 Step 13 — Implementation complete! PR created but not merged.`
