---
name: fix-issue
description: "Use when fixing open GitHub issues. Processes one approved issue per invocation: skips issues with open blockers, triages, classifies intent, then either delegates to /implement or follows the issue's instructions inline for research/review tasks."
argument-hint: "[--debug] [--issue <number-or-url>] [<number-or-url>]"
allowed-tools: Bash, Read, Grep, Glob, Skill
---

# Fix Issue

Process one approved GitHub issue per invocation. Fetch open issues with `GO` sentinel comment, skip any whose GitHub issue-dependencies list has open blocker, triage remaining candidate vs codebase, classify **intent** (PR-producing vs non-PR) and (for PR work) **complexity**, then delegate to `/implement` or run issue instructions inline. Non-PR task — e.g. "research topic X and summarize findings as issues", "code-review module Y and file issues for each problem" — follow without `/implement`; output issues go via `/issue`, source issue close with work summary instead of PR link.

**Single-iteration design**: Each invoke handles at most one issue, then exit. Caller (cron, `/loop`, manual) do repeat.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) return, IMMEDIATELY continue this skill's NEXT numbered step — do NOT end turn on child cleanup output. Rule strictly subordinate to explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). Normal sequential `proceed to Step N+1` = default continuation this rule reinforces, NOT exception. Every `/relevant-checks` invocation anywhere in this file covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for canonical rule.

**Flags**: Parse flags from start of `$ARGUMENTS`.

- `--debug`: Set `debug_mode=true`. Forward `--debug` to `/implement` in Step 6. Default: `debug_mode=false`.
- `--issue <number-or-url>`: **Deprecated** — kept for backward compat. Prefer pass issue number or URL as positional arg (e.g., `/fix-issue 42`). When flag seen, print: `**ℹ '--issue' is deprecated; pass the issue number or URL as a positional argument instead (e.g., /fix-issue 42).**`
- **Positional argument** (after flag stripping): If any non-flag text remain in `$ARGUMENTS` after stripping `--debug` and `--issue`, treat as issue number or URL. Set `ISSUE_ARG` to this value. When set, Step 1 target this specific issue instead of scanning oldest eligible. Accept bare issue number (e.g., `42`) or full GitHub issue URL (e.g., `https://github.com/owner/repo/issues/42`). Issue must be open, have `GO` as last comment, no currently-open blocking deps (see Step 1 for degradation note when dep endpoint unavailable). Default: empty (auto-pick mode). If both `--issue` and positional arg given, print: `**⚠ Both --issue and a positional argument were provided. Using the positional argument.**` and use positional arg.

## Progress Reporting

Follow formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:

| Step | Short Name |
|------|-----------|
| 0 | setup |
| 1 | fetch issue |
| 2 | lock |
| 3 | read details |
| 4 | triage |
| 5 | classify |
| 6 | execute |
| 7 | close issue |
| 8 | slack announce |
| 9 | cleanup |

## Step 0 — Setup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-fix-issue --skip-branch-check
```

Parse output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`. Set `FIX_ISSUE_TMPDIR` = `SESSION_TMPDIR`.

If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository. GitHub issue access requires a valid repo. Aborting.**` and skip to Step 9.

If `SLACK_OK=true`, set `slack_available=true`. **Do NOT make separate Bash call to resolve Slack env vars.** When Slack tokens needed (Steps 4 and 8), use inline shell expansion: `"${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}"` and `"${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"`.

If `SLACK_OK=false`, print `**⚠ Slack not configured ($SLACK_MISSING). Slack announcements will be skipped.**` Set `slack_available=false`.

Write session-env for forward to `/implement`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$FIX_ISSUE_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value> \
  --codex-healthy true --cursor-healthy true
```

## Step 1 — Fetch Eligible Issue

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/fetch-eligible-issue.sh ["$ISSUE_ARG"]
```

Only include `"$ISSUE_ARG"` as positional arg if `ISSUE_ARG` non-empty (user gave issue number/URL via positional arg or deprecated `--issue` flag).

Candidates must be open, have `GO` as last comment, not locked by prior `IN PROGRESS` comment, and **have no currently-open blocking deps** from either of two sources: (1) GitHub native issue-dependencies feature, queried via `repos/{owner}/{repo}/issues/{N}/dependencies/blocked_by`, and (2) prose-stated deps in issue body and every comment body, matched vs conservative case-insensitive keyword set `Depends on #N`, `Blocked by #N`, `Blocked on #N`, `Requires #N`, `Needs #N` (each keyword followed by whitespace + `#<digits>`; emphasis wrappers like `**#150**` tolerated, link-target forms like `[#150](url)` and cross-repo `owner/repo#N` deliberately NOT matched). Issue whose listed blockers all closed = eligible; issue with even one open blocker (from either source) skipped in auto-pick mode, reported ineligible in explicit `--issue` mode. If either dep check fail at any boundary (API unavail, parser error, transient `gh` failure), degrade silent to "no blockers known from that source" so API availability never hard-block automation. Prose parsing done by `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/parse-prose-blockers.sh`, guarded by offline regression harness `test-parse-prose-blockers.sh` (run via `make lint`).

Handle exit codes:

- **Exit 0**: Parse `ISSUE_NUMBER` and `ISSUE_TITLE`. Print `> **🔶 1: fetch issue — found #$ISSUE_NUMBER: $ISSUE_TITLE**`
- **Exit 1**: Print `✅ 1: fetch issue — no approved issues found (<elapsed>)`. Skip to Step 9.
- **Exit 2+**: Parse `ERROR` from stdout. Print `**⚠ 1: fetch issue — error: $ERROR (<elapsed>)**`. Skip to Step 9.

## Step 2 — Lock Issue

Lock immediately after find eligible issue to prevent race with concurrent runs.

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

Read `$FIX_ISSUE_TMPDIR/issue-details.txt` for full issue content.

## Step 4 — Triage

Print `> **🔶 4: triage**`

Read issue details from Step 3. Explore codebase via Read, Grep, Glob to decide if issue still actual — i.e. describes real problem still need fixing.

Check for:

- Issue already fixed by recent commits?
- Code/feature issue references still present?
- Issue valid bug/feature request, or filed in error?
- For investigation/review-only issues (deliverable = research findings or new issues, not code changes): is **task itself** still relevant — targets, scope, constraints still meaningful — rather than "is referenced bug still in code"?

**If issue no longer material** (already fixed, invalid, no longer relevant):

1. Compose detailed explanation of why issue no longer material. Include research summary: which files checked, which recent commits examined, what evidence led to conclusion. Explanation written into issue body so anyone review closed issue understand rationale without re-investigate.
2. Close with comment holding detailed explanation:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
     --issue $ISSUE_NUMBER --comment "Closing: <detailed explanation with research summary>"
   ```
3. If `slack_available=true`, post Slack notify:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/post-issue-slack.sh \
     --issue $ISSUE_NUMBER --title "$ISSUE_TITLE" \
     --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
     --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
     --message "Issue #$ISSUE_NUMBER ($ISSUE_TITLE) closed — <one-sentence reason>"
   ```
4. Print `✅ 4: triage — issue #$ISSUE_NUMBER closed, not material (<elapsed>)`. Skip to Step 9.

**If issue still actual**, print `✅ 4: triage — issue is active, proceeding (<elapsed>)` and continue.

## Step 5 — Classify Intent and Complexity

Print `> **🔶 5: classify**`

From issue details and codebase exploration in Step 4, decide two independent dimensions:

### Intent — does this issue prescribe work that should produce a pull request?

- **PR**: Issue prescribe code change — bug fix, refactor, new feature, doc edit, prompt/skill edit, config change, test addition, etc. — natural output = PR vs current repo.
- **NON_PR**: Issue prescribe investigative or review task whose natural output = something other than PR: new GitHub issues summarizing research findings, new GitHub issues flagging code-review problems, written report, similar. Typical signals: issue body contain phrases like "research and summarize", "investigate and report", "code-review this module and file issues", "do not create a PR", or otherwise make clear deliverable = issues/reports not code changes.

**Default to `PR` when uncertain.** `PR` path = pre-existing behavior; misclassify borderline `NON_PR` as `PR` recoverable (`/implement` `/review` phase surface mismatch) while misclassify `PR` as `NON_PR` could silent skip real work.

### Complexity (only eval when `INTENT=PR`)

- **SIMPLE**: Isolated fix in 2 or fewer files. Obvious solution, no architectural decisions needed. Examples: typo fix, small bug with clear root cause, config change.
- **HARD**: Everything else. Multi-file changes, new features, architectural decisions, unclear root cause, any uncertainty.

**Default to HARD when uncertain.** HARD use full `/design` + `/review` pipeline, safer for non-trivial changes.

When `INTENT=NON_PR`, complexity not meaningful — leave `COMPLEXITY` unset, skip SIMPLE/HARD step.

Print `✅ 5: classify — INTENT=$INTENT [COMPLEXITY=$COMPLEXITY] (<elapsed>)` (omit `COMPLEXITY=` segment when `INTENT=NON_PR`).

## Step 6 — Execute

Print `> **🔶 6: execute**`

Branch on `INTENT` from Step 5.

### 6a — `INTENT=PR` path (delegate to `/implement`)

Compose feature description from issue content: use issue title as primary description, with key details from issue body and comments as context.

> **Continue after child returns.** When child Skill return, run NEXT step of this skill — do NOT end turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Invoke `/implement` via Skill tool:

- **SIMPLE**: `/implement --auto --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh [--debug if debug_mode] <feature description>`
- **HARD**: `/implement --auto --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh [--debug if debug_mode] <feature description>`

After `/implement` finish, capture PR URL and PR number from its output. Save as `PR_URL` and `PR_NUMBER`.

If `/implement` fail or bail, print `**⚠ 6: execute — /implement failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS. (<elapsed>)**` Skip to Step 9. IN PROGRESS comment = signal manual intervention needed.

### 6b — `INTENT=NON_PR` path (follow instructions inline)

Read issue details from Step 3 and run instructions directly via Read, Grep, Glob, Bash. Do NOT call `/implement`. Do NOT modify files in working tree — `NON_PR` tasks deliver output as new GitHub issues, written summary comment, or both.

Common `NON_PR` patterns:

- **Research task** — investigate requested topic in-codebase via Read/Grep/Glob; when scope warrant collab read-only research panel, invoke `/research` via Skill tool. Create one or more summary issues via `/issue` (invoked via Skill tool) if issue body ask it.
- **Code-review task** — examine requested area, file one issue per problem found. Invoke `/issue` via Skill tool in batch mode (`--input-file` with markdown file listing findings) to file all findings in single pass with semantic dup detection. Write `--input-file` markdown to path under `$FIX_ISSUE_TMPDIR` (never inside repo working tree) so "no working-tree edits" rule above hold.
- **Other investigative or planning tasks** — follow body instructions literally; when ambiguous, prefer interpretation that produce actionable output (issues, documented findings) over interpretation that produce code changes.

> **Continue after child returns.** When any child Skill (`/issue`, `/research`, ...) return, run NEXT step of this skill — do NOT end turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

As work proceed, keep running `WORK_SUMMARY` — concise markdown summary of what done and output artifacts (links to issues created, key findings, etc.). This summary become closing comment in Step 7 and Slack message in Step 8. Keep `PR_URL` and `PR_NUMBER` unset on this path.

If work cannot finish (e.g., `/issue` fail repeat, issue instructions infeasible, required external access unavail), print `**⚠ 6: execute — non-PR task failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS. (<elapsed>)**` and skip to Step 9. IN PROGRESS comment = signal manual intervention needed — same recovery semantics as `/implement` failure path.

## Step 7 — Close Issue

Print `> **🔶 7: close issue**`

Branch on `INTENT`.

### 7a — `INTENT=PR`

Update issue body with PR link and close with DONE comment (single call):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --pr-url "$PR_URL" --comment "DONE"
```

### 7b — `INTENT=NON_PR`

Close issue with `WORK_SUMMARY` as closing comment (no `--pr-url`, no body update):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --comment "$WORK_SUMMARY"
```

Print `✅ 7: close issue — #$ISSUE_NUMBER closed (<elapsed>)`

## Step 8 — Slack Announce

If `slack_available=false`, print `⏭️ 8: slack announce — skipped (Slack not configured) (<elapsed>)` and go to Step 9.

Branch on `INTENT`.

### 8a — `INTENT=PR`

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/post-issue-slack.sh \
  --issue $ISSUE_NUMBER --title "$ISSUE_TITLE" --pr-url "$PR_URL" \
  --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
  --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"
```

### 8b — `INTENT=NON_PR`

Post free-form Slack message summarize non-PR work (no PR URL). Compose `--message` value from `WORK_SUMMARY` — one-sentence summary ideal (e.g., "research complete, filed #123 and #124" or "code review complete, filed 5 issues"):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/post-issue-slack.sh \
  --issue $ISSUE_NUMBER --title "$ISSUE_TITLE" \
  --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
  --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
  --message "Issue #$ISSUE_NUMBER ($ISSUE_TITLE) closed — <one-sentence summary from WORK_SUMMARY>"
```

### After the branch

If script exit non-zero, print `**⚠ 8: slack announce — failed. Continuing.**`

Print `✅ 8: slack announce — posted (<elapsed>)`

## Step 9 — Cleanup

**This step ALWAYS runs**, regardless of outcome of prior steps (success, failure, early exit, abort).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$FIX_ISSUE_TMPDIR"
```

Print `✅ 9: cleanup — fix-issue complete! (<elapsed>)`

## Known Limitations

- **Stale IN PROGRESS lock**: Step 2 delete `GO` comment and post `IN PROGRESS` (so `GO` sentinel no longer remains after lock). If skill crash after Step 2 finish, issue last comment = `IN PROGRESS` — recovery: manually delete `IN PROGRESS` comment and re-add `GO`. If crash mid-Step-2 (between delete `GO` and post `IN PROGRESS`), issue has neither sentinel — recovery: manually re-add `GO`.
- **Single-runner assumption**: Comment-based lock (Step 2) include dup detection but not fully atomic. For reliable operation, run one instance of `/fix-issue` at a time per repo.
- **Dependency check degrades silently on API failure**: Blocked-by check (Step 1) treat unreachable or erroring dep-API responses as "no blockers known" to avoid hard-block automation. If GitHub issue-deps endpoint return 5xx or unexpected payload, blocked issue could temporarily be eligible. GO sentinel still apply, so blast radius limited to whatever reviewer intended to allow via `GO`.
- **Prose-dep check shares same fail-open posture**: Parser regression, body/comment fetch fail, or per-reference state lookup fail all degrade to "no prose blockers known" for that candidate. Offline harness (`test-parse-prose-blockers.sh`, run via `make lint`) = primary guard vs parser regressions.
- **Prose-dep check uses strict keyword grammar**: Five recognized phrases (`Depends on`, `Blocked by`, `Blocked on`, `Requires`, `Needs`) must be immediately followed by whitespace + `#<digits>`. Typos like `Depends on#150` (no space), cross-repo refs (`owner/repo#150`), URL forms (`https://github.com/…/150`), bare `#150` mentions deliberately NOT matched. Emphasis wrappers (`**#150**`, `_#150_`) ARE matched. Link-target wrappers (`[#150](url)`) NOT matched, so link targets never smuggle cross-repo refs through parser.
- **Short-circuit when native blockers exist — user-visible messages may omit prose blockers**: When issue has BOTH native and prose open blockers, prose path short-circuited for rate-limit efficiency. Skip/error message list only native blocker numbers. Close all listed native blockers and re-run `/fix-issue` will surface any remaining prose blockers on next run.
