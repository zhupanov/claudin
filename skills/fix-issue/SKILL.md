---
name: fix-issue
description: "Use when fixing open GitHub issues. Processes one approved issue per invocation: triages, classifies complexity, and delegates to /implement."
argument-hint: "[--debug] [--issue <number-or-url>]"
allowed-tools: Bash, Read, Grep, Glob, Skill
---

# Fix Issue

Process one approved GitHub issue per invocation. Fetches open issues with a `GO` sentinel comment, triages against the codebase, classifies complexity, and delegates to `/implement`.

**Single-iteration design**: Each invocation handles at most one issue, then exits. The caller (cron, `/loop`, or manual invocation) is responsible for repeated execution.

**Flags**: Parse flags from the start of `$ARGUMENTS`.

- `--debug`: Set `debug_mode=true`. Forward `--debug` to `/implement` in Step 6. Default: `debug_mode=false`.
- `--issue <number-or-url>`: Set `ISSUE_ARG` to the provided value. When set, Step 1 targets this specific issue instead of scanning for the oldest eligible one. Accepts a bare issue number (e.g., `42`) or a full GitHub issue URL (e.g., `https://github.com/owner/repo/issues/42`). The issue must be open and have `GO` as its last comment. Default: empty (auto-pick mode).

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:

| Step | Short Name |
|------|-----------|
| 0 | setup |
| 1 | fetch issue |
| 2 | lock |
| 3 | read details |
| 4 | triage |
| 5 | classify |
| 6 | implement |
| 7 | close issue |
| 8 | slack announce |
| 9 | cleanup |

## Step 0 — Setup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-fix-issue --skip-branch-check
```

Parse output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`. Set `FIX_ISSUE_TMPDIR` = `SESSION_TMPDIR`.

If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository. GitHub issue access requires a valid repo. Aborting.**` and skip to Step 9.

If `SLACK_OK=true`, set `slack_available=true`. **Do NOT make a separate Bash call to resolve Slack env vars.** When Slack tokens are needed (Steps 4 and 8), use inline shell expansion: `"${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}"` and `"${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"`.

If `SLACK_OK=false`, print `**⚠ Slack not configured ($SLACK_MISSING). Slack announcements will be skipped.**` Set `slack_available=false`.

Write session-env for forwarding to `/implement`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$FIX_ISSUE_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value> \
  --codex-healthy true --cursor-healthy true
```

## Step 1 — Fetch Eligible Issue

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/fetch-eligible-issue.sh [--issue "$ISSUE_ARG"]
```

Only include `--issue "$ISSUE_ARG"` if `ISSUE_ARG` is non-empty (the user provided `--issue`).

Handle exit codes:

- **Exit 0**: Parse `ISSUE_NUMBER` and `ISSUE_TITLE`. Print `> **🔶 1: fetch issue — found #$ISSUE_NUMBER: $ISSUE_TITLE**`
- **Exit 1**: Print `✅ 1: fetch issue — no approved issues found (<elapsed>)`. Skip to Step 9.
- **Exit 2+**: Parse `ERROR` from stdout. Print `**⚠ 1: fetch issue — error: $ERROR (<elapsed>)**`. Skip to Step 9.

## Step 2 — Lock Issue

Lock immediately after finding an eligible issue to prevent race conditions with concurrent runs.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh comment \
  --issue $ISSUE_NUMBER --body "IN PROGRESS" --lock
```

Parse output for `LOCK_ACQUIRED`. If `LOCK_ACQUIRED=false`, print `**⚠ 2: lock — failed ($ERROR). Another run may have claimed this issue. (<elapsed>)**` Skip to Step 9.

If `LOCK_ACQUIRED=true`, print `✅ 2: lock — issue #$ISSUE_NUMBER locked (<elapsed>)`.

## Step 3 — Read Issue Details

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/get-issue-details.sh \
  --issue $ISSUE_NUMBER --output "$FIX_ISSUE_TMPDIR/issue-details.txt"
```

Read `$FIX_ISSUE_TMPDIR/issue-details.txt` to get the full issue content.

## Step 4 — Triage

Print `> **🔶 4: triage**`

Read the issue details from Step 3. Explore the codebase using Read, Grep, and Glob to determine if the issue is still actual — that is, whether it describes a real problem that still needs fixing.

Check for:

- Has the issue already been fixed by recent commits?
- Is the code/feature the issue references still present?
- Is the issue a valid bug/feature request, or was it filed in error?

**If the issue is no longer material** (already fixed, invalid, or no longer relevant):

1. Compose a detailed explanation of why the issue is no longer material. Include a summary of the research performed: which files were checked, what recent commits were examined, and what evidence led to the conclusion. This explanation is written into the issue body so that anyone reviewing the closed issue can understand the rationale without re-investigating.
2. Close with comment containing the detailed explanation:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
     --issue $ISSUE_NUMBER --comment "Closing: <detailed explanation with research summary>"
   ```
3. If `slack_available=true`, post Slack notification:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/post-issue-slack.sh \
     --issue $ISSUE_NUMBER --title "$ISSUE_TITLE" \
     --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
     --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
     --message "Issue #$ISSUE_NUMBER ($ISSUE_TITLE) closed — <one-sentence reason>"
   ```
4. Print `✅ 4: triage — issue #$ISSUE_NUMBER closed, not material (<elapsed>)`. Skip to Step 9.

**If the issue is still actual**, print `✅ 4: triage — issue is active, proceeding (<elapsed>)` and continue.

## Step 5 — Classify Complexity

Print `> **🔶 5: classify**`

Based on the issue details and codebase exploration from Step 4, classify the issue:

- **SIMPLE**: Isolated fix in 2 or fewer files. Obvious solution with no architectural decisions needed. Examples: typo fix, small bug with clear root cause, config change.
- **HARD**: Everything else. Multi-file changes, new features, architectural decisions, unclear root cause, or any uncertainty.

**Default to HARD when uncertain.** A HARD classification uses the full `/design` + `/review` pipeline, which is safer for non-trivial changes.

Print `✅ 5: classify — $CLASSIFICATION (<elapsed>)`

## Step 6 — Implement

Print `> **🔶 6: implement**`

Compose the feature description from the issue content: use the issue title as the primary description, with key details from the issue body and comments as context.

Invoke `/implement` via the Skill tool:

- **SIMPLE**: `/implement --auto --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh [--debug if debug_mode] <feature description>`
- **HARD**: `/implement --auto --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh [--debug if debug_mode] <feature description>`

After `/implement` completes, capture the PR URL and PR number from its output. Save as `PR_URL` and `PR_NUMBER`.

If `/implement` fails or bails, print `**⚠ 6: implement — failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS. (<elapsed>)**` Skip to Step 9. The IN PROGRESS comment serves as an indicator that manual intervention is needed.

## Step 7 — Close Issue

Print `> **🔶 7: close issue**`

Update the issue body with PR link and close with DONE comment (single call):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --pr-url "$PR_URL" --comment "DONE"
```

Print `✅ 7: close issue — #$ISSUE_NUMBER closed (<elapsed>)`

## Step 8 — Slack Announce

If `slack_available=false`, print `⏭️ 8: slack announce — skipped (Slack not configured) (<elapsed>)` and proceed to Step 9.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/post-issue-slack.sh \
  --issue $ISSUE_NUMBER --title "$ISSUE_TITLE" --pr-url "$PR_URL" \
  --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
  --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"
```

If the script exits non-zero, print `**⚠ 8: slack announce — failed. Continuing.**`

Print `✅ 8: slack announce — posted (<elapsed>)`

## Step 9 — Cleanup

**This step ALWAYS runs**, regardless of the outcome of prior steps (success, failure, early exit, or abort).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$FIX_ISSUE_TMPDIR"
```

Print `✅ 9: cleanup — fix-issue complete! (<elapsed>)`

## Known Limitations

- **Stale IN PROGRESS lock**: If the skill crashes after Step 2, the issue remains locked with `IN PROGRESS` as the last comment. Recovery: manually delete the `IN PROGRESS` comment and re-add `GO` to re-enable the issue for automated processing.
- **Single-runner assumption**: The comment-based locking (Step 2) includes duplicate detection but is not fully atomic. For reliable operation, run one instance of `/fix-issue` at a time per repository.
