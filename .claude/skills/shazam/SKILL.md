---
name: shazam
description: Full end-to-end feature workflow — design, implement, PR, Slack announce, CI+rebase+merge, and cleanup.
argument-hint: "[--quick] [--auto] [--no-merge] [--session-env <path>] <feature description>"
allowed-tools: AskUserQuestion, Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Shazam Skill

Full end-to-end feature implementation: design, plan review, code, validate, commit, code review, validate, commit, version bump, PR, Slack announce (via /implement), CI+rebase+merge, cleanup.

The feature to implement is described by `$ARGUMENTS`.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as the feature description. Flags may appear in any order; stop at the first non-flag token.

- `--quick`: Set a mental flag `quick_mode=true`. Forward this flag to `/implement` in Step 1. When `quick_mode=true`, `/implement` skips `/design` (produces an inline plan) and simplifies code review to one round with 4 Claude subagents only (no external reviewers, no voting panel). All other steps (CI, merge, Slack, cleanup) run normally.
- `--auto`: Set a mental flag `auto_mode=true`. Forward this flag to `/implement` in Step 1. When `auto_mode=true`, `/implement` and `/design` suppress interactive clarifying questions and run non-interactively. The default (no `--auto`) enables interactive questions in `/design` (before sketches and after plan review) and `/implement` (before implementation). Other than forwarding to `/implement`, `/shazam` does not behave differently with `--auto`.
- `--no-merge`: Set a mental flag `no_merge=true`. When `no_merge=true`, Steps 2–5 are skipped (CI monitoring, :merged: emoji, local cleanup, and main verification). Steps 6–7 (report, cleanup) still run.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill and will be forwarded to `session-setup.sh` via `--caller-env` and to child skills. If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full discovery).

## Progress Reporting

**Every step MUST print clearly visible status lines** so the user can instantly see where execution is at. Use distinct emoji prefixes:

- Print a **start line** when entering a step: e.g., `🚀 Step 1 — Invoking /implement...`
- Print a **completion line** when done: e.g., `✅ Step 2 — PR #123 merged!`
- For long-running steps, print **intermediate progress**: e.g., `⏳ Step 2 — CI running (2m elapsed), main unchanged`

Suggested emoji palette (use consistently):
| Step | Emoji | Description |
|------|-------|-------------|
| 0 | 🔧 | Session setup |
| 1 | ⚡ | Design + implement + Slack (via /implement) |
| 2 | 🔄 | CI + rebase + merge loop |
| 3 | ✨ | :merged: emoji |
| 4 | 🧹 | Local cleanup |
| 5 | ✅ | Verify main |
| 6 | 📊 | Final report |
| 7 | 🏁 | Final cleanup + warnings |

## Step 0 — Session Setup

Run the shared session setup script. If `SESSION_ENV_PATH` is non-empty (passed via `--session-env`), include `--caller-env` to reuse already-discovered values:

```bash
$PWD/.claude/scripts/generic/session-setup.sh --prefix claude-shazam [--caller-env "$SESSION_ENV_PATH"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` if `SESSION_ENV_PATH` is non-empty.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `SLACK_TOKEN_OK`, `REPO`, `REPO_UNAVAILABLE`. Set:
- `SHAZAM_TMPDIR` = `SESSION_TMPDIR`
- If `SLACK_TOKEN_OK=false`, print: `**⚠ CLAUDIN_SLACK_BOT_TOKEN is not set. :merged: emoji (Step 3) will be skipped.**` Set a mental flag `slack_available=false`.
- If `REPO_UNAVAILABLE=true`, print `**❌ Could not determine repository name. Cannot proceed with CI/merge steps.**` Set a mental flag `repo_unavailable=true`.

### Write Session Env for Child Skills

Write the discovered values to `$SHAZAM_TMPDIR/session-env.sh` so they can be forwarded to `/implement`:

```bash
$PWD/.claude/scripts/generic/write-session-env.sh --output "$SHAZAM_TMPDIR/session-env.sh" \
  --slack-token-ok <value> --repo <value> --repo-unavailable <value>
```

This file will be passed to `/implement` via `--session-env` in Step 1.

## Step 1 — Design and Implement

**CRITICAL: You MUST invoke `/implement` using the Skill tool for the initial implementation, version bump, PR creation, and Slack announcement. Do NOT bypass `/implement` by directly editing files, staging commits, or opening PRs yourself. In normal mode, all quality gates (design, plan review, code review) are mandatory. In `--quick` mode, `/design` is skipped and code review is simplified — but `/implement` must still be invoked.**

Invoke the `/implement` skill with `--session-env $SHAZAM_TMPDIR/session-env.sh` prepended to the feature description. **If `quick_mode=true`, also prepend `--quick`** so `/implement` runs in quick mode. **If `auto_mode=true`, also prepend `--auto`** so `/implement` and `/design` suppress interactive questions. This will:
- Create a branch and design the plan (via `/design` in normal mode, or inline in `--quick` mode)
- Implement the feature, validate, commit
- Code review (full `/review` in normal mode, or simplified 1-round review in `--quick` mode), validate, commit
- Version bump, create PR
- Monitor CI and fix failures (does not merge)
- Post Slack announcement

After `/implement` completes, extract the PR number, URL, title, and Slack timestamp from its output. Look for the lines (emitted by `/implement` Step 9 and Step 11 — keep in sync):
```
PR_NUMBER=<N>
PR_URL=<url>
PR_TITLE=<title>
```
```
SLACK_TS=<value>
```

Note: `SLACK_TS` may appear many lines after `PR_URL` — scan the full `/implement` output for all four values.

If `PR_NUMBER` or `PR_URL` cannot be extracted from `/implement`'s output, print an error: `**❌ Could not extract PR number/URL from /implement output. Cannot proceed with CI/merge steps.**` and skip to Step 6.

If `SLACK_TS` is empty or cannot be extracted, set `SLACK_TS` to empty. Step 3 will be skipped when `SLACK_TS` is empty.

Also note the branch name from the conversation context.

## Step 2 — CI + Rebase + Merge Loop

**If `no_merge=true`**: Print `⏭️ Step 2 — Skipped (--no-merge flag set). PR created but not merged.` and skip to Step 6.

**If `repo_unavailable=true`**: Print `⏭️ Step 2 — Skipped (repository name could not be determined).` and skip to Step 6.

Monitor CI and the main branch **in parallel**. The key optimization: don't wait for CI to finish before checking if main has advanced.

### 2a — Poll Loop

Track these counters (all start at 0):
- `iteration` — passed to `ci-wait.sh`, returned as `ITERATION` (updated by the script during wait cycles)
- `rebase_count` — incremented after each successful rebase
- `fix_attempts` — incremented after each real CI fix attempt
- `transient_retries` — consecutive transient CI retries, managed locally (used only in Step 2c; when this exceeds 2, treat as real failure and increment `fix_attempts`)

**Wait for CI** using the `ci-wait.sh` script, which polls `ci-status.sh` + `ci-decide.sh` internally and prints compact dot-based progress to stderr:

```bash
$PWD/.claude/scripts/generic/ci-wait.sh --pr <PR-NUMBER> --repo $REPO \
  --rebase-count "$rebase_count" --fix-attempts "$fix_attempts" --iteration "$iteration"
```

Use `timeout: 1860000` on the Bash tool call (31 minutes, matching the script's 1800s default + grace).

Parse the output for: `ACTION`, `CI_STATUS`, `BEHIND_COUNT`, `FAILED_RUN_ID`, `BAIL_REASON`, `ITERATION`, `ELAPSED`. Update `iteration` from the returned `ITERATION` value.

**Execute the action** returned by `ci-wait.sh`:

   - **`ACTION=rebase`**: Print a context-specific message based on `CI_STATUS`: if `CI_STATUS=pass`, print `🔄 CI passed but main advanced — rebasing...`; if `CI_STATUS=pending`, print `🔄 Main advanced while CI running — rebasing...` → run `rebase-push.sh` (see rebase handling below) → on success: increment `rebase_count`, increment `iteration`, reset `transient_retries` → re-invoke `ci-wait.sh`.

   - **`ACTION=merge`**: Print `✅ CI passed, main up-to-date — merging!` → proceed to **2b**.

   - **`ACTION=already_merged`**: Print `✅ PR was force-merged externally — skipping CI wait and merge.` → skip **2b** (no merge needed) and proceed directly to Step 3. The PR counts as successfully merged for Steps 3–5.

   - **`ACTION=rebase_then_evaluate`**: Run rebase first (same as `rebase` above), then on success fall through to evaluate the CI failure as in **2c**.

   - **`ACTION=evaluate_failure`**: Evaluate the CI failure → **2c**.

   - **`ACTION=bail`**: Print `BAIL_REASON` and bail out → **2d**.

After handling any non-merge/non-bail action (rebase, evaluate_failure, etc.), **re-invoke `ci-wait.sh`** with updated counter values. The adaptive sleep interval is handled by the caller: sleep 30s before re-invoking after a rebase, sleep 60s after a transient retry rerun.

4. **When rebase is needed** (ACTION=rebase or rebase_then_evaluate), use the `rebase-push.sh` script:
   ```bash
   $PWD/.claude/scripts/generic/rebase-push.sh
   ```
   Handle exit codes:
   - **Exit 0**: Rebase and push succeeded.
   - **Exit 1**: Rebase had conflicts (rebase is still in progress). Read `CONFLICT_FILES=` from stdout. If all conflicted files are trivial (`version.go`, `go.sum`, auto-generated), resolve them manually, stage the resolved files with `git add`, then run `$PWD/.claude/scripts/generic/rebase-push.sh --continue` to continue the rebase and push. Handle the same exit codes (0/1/2/3) from the `--continue` invocation. Restart the loop on success. If any non-trivial files are conflicted, run `git rebase --abort` and **bail out** (Step 2d).
   - **Exit 2**: `force-with-lease` push failed. Run the script again once (it fetches + rebases internally). If it fails twice, **bail out**.
   - **Exit 3**: Rebase failed for non-conflict reasons (rebase already aborted). Read `REBASE_ERROR=` from stderr. **Bail out** (Step 2d).

### 2b — Merge

When CI passes and the branch is up-to-date with main, use the `merge-pr.sh` script:

```bash
$PWD/.claude/scripts/generic/merge-pr.sh --pr <PR-NUMBER> --repo $REPO
```

Parse the output for `MERGE_RESULT` and `ERROR`. Handle each result:

- **`MERGE_RESULT=merged`**: Print `✅ Step 2 — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=admin_merged`**: Print `**⚠ Merged with --admin (review requirement overridden).** ✅ Step 2 — PR #<NUMBER> merged!` and continue.
- **`MERGE_RESULT=main_advanced`**: Go back to **2a** (the next iteration will detect the branch is behind and rebase).
- **`MERGE_RESULT=ci_not_ready`**: Go back to **2a** (CI may need more time or a rerun).
- **`MERGE_RESULT=admin_failed`**: Bail out (Step 2d) with the `ERROR` message.
- **`MERGE_RESULT=error`**: Bail out (Step 2d) with the `ERROR` message.

**CRITICAL: The `--admin` safety invariant is enforced inside `merge-pr.sh` — it re-verifies CI and branch freshness before attempting `--admin`. See the script's header for the full invariant. (Keep in sync with the same `--admin` fallback in `/admin-upgrade-clients` Sub-Step 7 and `/admin-add-user` Step 10.)**

Save the expected commit title for verification in Step 5: `<PR_TITLE> (#<PR_NUMBER>)` (using the `PR_TITLE` extracted from `/implement` output in Step 1).

### 2c — Evaluate CI Failure

Use `FAILED_RUN_ID` from the `ci-status.sh` output. If `FAILED_RUN_ID` is empty, use `$PWD/.claude/scripts/generic/gh-pr-checks.sh --pr <PR-NUMBER> --repo $REPO` to identify the failed check and its run URL manually.

1. **Transient/infrastructure failure** (GitHub API timeout, runner provisioning failure, flaky network, `RUNNER_TEMP` errors, Docker pull rate limit, "The hosted runner lost communication", etc.):
   ```bash
   $PWD/.claude/scripts/generic/sleep-seconds.sh 60
   $PWD/.claude/scripts/generic/ci-rerun-failed.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Parse the output for `RERUN_SUBMITTED` and `ERROR`. If `RERUN_SUBMITTED=false`, print the `ERROR` and treat as a real CI failure (fall through to diagnosis). Allow up to **2 consecutive transient retries** before treating as a real failure. The counter resets after a successful rebase, code fix, or a CI run that fails for a different (non-transient) reason. Go back to **2a**.

2. **Real CI failure** — Diagnose and fix:
   ```bash
   $PWD/.claude/scripts/generic/gh-run-logs.sh --run-id <FAILED_RUN_ID> --repo $REPO
   ```
   Analyze the logs. Fix the issue, run `/relevant-checks`, commit, push. Go back to **2a**.

### 2d — Bail Out

**Bail out** if any of these are true:
- You've already attempted **3 fix iterations** without progress (same or new errors each time).
- The failure is **fundamentally incompatible** with the codebase or CI.
- The fix would require **reverting the core feature** to pass CI.

When bailing out:
1. If a rebase is in progress (exit 1 from `rebase-push.sh`), run `$PWD/.claude/scripts/generic/git-rebase-abort.sh` first.
2. Clearly explain what failed, what you attempted, and suggest manual steps.

**Do NOT skip Steps 4, 6, and 7** when bailing — still clean up and print the review report. **Skip Steps 3 and 5** since the PR was not merged.

## Step 3 — Add :merged: Emoji to Slack Post

**If `no_merge=true`**: Skip this step.

**If `slack_available=false`**: Print `⏭️ Step 3 — Skipped (CLAUDIN_SLACK_BOT_TOKEN not set).` and proceed to Step 4.

**Only if the PR was successfully merged in Step 2b or force-merged externally** (not bailed in 2d).

**Only if `SLACK_TS` from Step 1 is non-empty** (Slack announcement succeeded).

Add the :merged: emoji using the shared script:

```bash
$PWD/.claude/scripts/generic/post-merged-emoji.sh --slack-ts "$SLACK_TS"
```

**If the script exits non-zero**, print `**⚠ Failed to add :merged: emoji to Slack post. Continuing.**` and proceed to Step 4. **Do not abort.**

## Step 4 — Local Cleanup

**If `no_merge=true`**: Print `⏩ Step 4 — Skipped (--no-merge). You are still on branch <branch-name>.` and skip to Step 6.

**If the PR was successfully merged (Step 2b or force-merged externally)**:

Switch back to main, pull the merged changes, and delete the development branch:

```bash
$PWD/.claude/scripts/generic/local-cleanup.sh --branch <branch-name>
```

Parse the output for `CLEANUP_SUCCESS`, `CURRENT_BRANCH`, and `BRANCH_DELETED`. If `CLEANUP_SUCCESS=true`, print: `🧹 Step 4 — Switched to main, deleted local branch <branch-name>`. If `CLEANUP_SUCCESS=false`, print: `**⚠ Step 4 — Cleanup partially failed. Current branch: <CURRENT_BRANCH>, branch deleted: <BRANCH_DELETED>.**`

**If Step 2 bailed out (PR was NOT merged)**:

Do NOT switch branches or delete the local branch. The user will need the branch to continue manually.

Print: `⚠️ Step 4 — Skipped cleanup (PR not merged). You are still on branch <branch-name>.`

## Step 5 — Verify Main

**If `no_merge=true`**: Skip this step.

**Only if the PR was successfully merged (Step 2b or force-merged externally)** (skip if bailed out).

Confirm the last commit on main is the expected squash-merged commit using the `verify-main.sh` script:

```bash
$PWD/.claude/scripts/generic/verify-main.sh --expected-title "<PR_TITLE> (#<PR_NUMBER>)"
```

Parse the output for `VERIFIED`, `COMMIT_HASH`, and `COMMIT_MESSAGE`. Print the result:

- If `VERIFIED=true`: `✅ Step 5 — Verified: main is at <COMMIT_HASH> "<COMMIT_MESSAGE>"`
- If `VERIFIED=false`: `**⚠ Step 5 — Unexpected HEAD on main: <COMMIT_HASH> "<COMMIT_MESSAGE>". Expected: "<PR_TITLE> (#<PR_NUMBER>)". Another merge may have landed simultaneously.**`

## Step 6 — Final Report

**If `quick_mode=true`**: Print: `📊 Step 6 — Quick mode: /design was skipped, code review was simplified (4 Claude subagents, 1 round, no voting).`

**If `quick_mode=false`**: Print a summary noting that:
- Plan review findings were reported by the `/design` phase (visible in conversation above)
- Code review findings were reported by the `/implement` phase (visible in conversation above)

If both phases reported all suggestions implemented, print: `📊 Step 6 — All review suggestions were implemented across both plan review and code review.`

## Step 7 — Cleanup and Final Warnings

Remove the session temp directory and all files within it:

```bash
$PWD/.claude/scripts/generic/cleanup-tmpdir.sh --dir "$SHAZAM_TMPDIR"
```

**Repeat any external reviewer warnings** from earlier in the workflow (from `/design` or `/review` phases) so they are visible at the end. **If `quick_mode=true`**, there are no external reviewer warnings to repeat (no external reviewers were used). For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review failed: <reason>**`

If `no_merge=true`, remind: `**Note: --no-merge was set. PR was created but not merged. Merge manually when ready.**`

Print: `🏁 Step 7 — Shazam complete!`
