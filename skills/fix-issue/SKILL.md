---
name: fix-issue
description: "Use when fixing open GitHub issues. Processes one approved issue per invocation: skips issues with open blockers, triages, classifies intent, then either delegates to /implement or follows the issue's instructions inline for research/review tasks."
argument-hint: "[--debug] [--no-slack] [--issue <number-or-url>] [<number-or-url>]"
allowed-tools: Bash, Read, Grep, Glob, Skill
---

# Fix Issue

Process one approved GitHub issue per invocation. Fetches open issues with a `GO` sentinel comment, skips any whose GitHub issue-dependencies list includes an open blocker, triages the remaining candidate against the codebase, classifies **intent** (PR-producing vs. non-PR task) and (for PR work) **complexity**, and either delegates to `/implement` or executes the issue's instructions inline. Non-PR tasks — e.g., "research topic X and summarize findings as issues", "code-review module Y and file issues for each problem" — are followed without `/implement`; any output issues are created via `/issue` and the source issue is closed with a work summary instead of a PR link.

**Single-iteration design**: Each invocation handles at most one issue, then exits. The caller (cron, `/loop`, or manual invocation) is responsible for repeated execution.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Flags**: Parse flags from the start of `$ARGUMENTS`.

- `--debug`: Set `debug_mode=true`. Forward `--debug` to `/implement` in Step 6. Default: `debug_mode=false`.
- `--no-slack`: Set `slack_enabled=false`. Forward `--no-slack` to `/implement` in Step 6a. Default: `slack_enabled=true`. When `slack_enabled=true` (default), the delegated `/implement` run posts to Slack (Step 16a) when Slack env vars are configured; the `NON_PR` path's Step 8 Slack announcement also posts via the shared `scripts/post-issue-slack.sh`. When `slack_enabled=false` (user passed `--no-slack`), no Slack calls are made on either path.
- `--issue <number-or-url>`: **Deprecated** — recognized for backward compatibility. Prefer passing the issue number or URL as a positional argument (e.g., `/fix-issue 42`). When this flag is encountered, print: `**ℹ '--issue' is deprecated; pass the issue number or URL as a positional argument instead (e.g., /fix-issue 42).**`
- **Positional argument** (after flag stripping): If any non-flag text remains in `$ARGUMENTS` after stripping all flags defined above (`--debug`, `--no-slack`, `--issue`), treat it as the issue number or URL. Set `ISSUE_ARG` to this value. When set, Step 1 targets this specific issue instead of scanning for the oldest eligible one. Accepts a bare issue number (e.g., `42`) or a full GitHub issue URL (e.g., `https://github.com/owner/repo/issues/42`). The issue must be open, have `GO` as its last comment, and have no currently-open blocking dependencies (see Step 1 for the degradation note when the dependency endpoint is unavailable). Default: empty (auto-pick mode). If both `--issue` and a positional argument are provided, print: `**⚠ Both --issue and a positional argument were provided. Using the positional argument.**` and use the positional argument.

## Mindset

Before processing each invocation, hold these four questions.

**Is the issue still real?** Codebases move. A two-week-old bug may already be fixed; a "refactor X" request may reference deleted code. Triage (Step 4) is the cheap first-line filter — closing a stale issue with a research-summary comment is always cheaper than drafting a no-op PR.

**What shape of output does the issue want back?** A code change (merged PR) vs. new GitHub issues or a written summary (NON_PR). Classification (Step 5) is a low-variance binary call; most issues are unambiguous. Default to `PR` **only when the issue is genuinely ambiguous** — a mis-classified `NON_PR` may sometimes surface during `/implement`'s `/review` phase (which reviews code changes, not the shape-of-work contract), in which case the operator may need to stop the run. When the issue text explicitly forbids a PR or mandates research/issues as the deliverable, pick `NON_PR` regardless of the default — overriding the stated deliverable is not recoverable downstream. A mis-classified `PR` (picking `NON_PR` for a genuine code-change request) silently skips real work.

**How fragile is the change?** Complexity (Step 5) picks `/implement --quick` (SIMPLE — single-reviewer loop) or the full `/design` + `/review` panel (HARD). Default to HARD — an extra design round on a truly simple issue costs little, while skipping `/design` on a multi-file refactor costs a broken PR.

**Where does a crash leave the issue?** `IN PROGRESS` is a lock, not a status. A Step 2+ crash keeps the issue locked until a human clears the comment. Consult Known Limitations for each recovery path before deviating from the step sequence.

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
| 6 | execute |
| 7 | close issue |
| 8 | slack announce |
| 9 | cleanup |

## Anti-patterns

Each rule states **Why** (the specific consequence of breaking the rule) and **How to apply** (where the invariant is load-bearing). Rules marked **CI-backed: yes** are mechanically enforced by `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` via an `awk` extraction over the `### 6a` block; the remaining rules are editorial invariants that depend on the SKILL.md text being unambiguous.

1. **NEVER run Step 3+ on an unlocked issue.** **Why**: the `IN PROGRESS` lock (Step 2) is how concurrent runners avoid stepping on each other — Step 1's `fetch-eligible-issue.sh` skips candidates whose last comment is `IN PROGRESS`, so posting `IN PROGRESS` claims the issue atomically at the comment-stream tail. Stepping past Step 2 unlocked races every other `/fix-issue` invocation on the same repo. **How to apply**: treat Step 2 as structural; do not re-order the step sequence or skip it under any flag. **CI-backed**: no (editorial invariant).

2. **NEVER drop the `--issue $ISSUE_NUMBER` forward from either Step 6a `/implement` invocation bullet (SIMPLE or HARD).** **Why**: `--issue $ISSUE_NUMBER` causes `/implement` Step 0.5 Branch 2 to adopt the already-locked tracking issue rather than creating a duplicate via Branch 4. Dropping the forward splits tracking onto two different issues, breaks the `Closes #<N>` PR-body recovery on resumed runs, and leaves the `/fix-issue`-side issue locked under `IN PROGRESS` with no auto-close on merge. **How to apply**: keep `--issue $ISSUE_NUMBER` in both SIMPLE and HARD `/implement` invocation bullets in Step 6a. **CI-backed**: yes — assertions (a1) and (a2) in `test-fix-issue-bail-detection.sh`.

3. **NEVER remove the `IMPLEMENT_BAIL_REASON=adopted-issue-closed` literal or its accompanying `/implement bailed: issue #` warning-prefix literal from Step 6a.** **Why**: when `/implement` adopts a tracking issue that was closed externally between lock and execution, it emits the bail token on stdout; Step 6a's branch scans captured output for that exact literal. Dropping either literal from SKILL.md routes Step 6a to the generic-failure branch ("remains locked with IN PROGRESS") instead of the adopted-issue-closed branch that reports the specific externally-closed condition. **How to apply**: preserve both literal strings verbatim inside the `### 6a` block. **CI-backed**: yes — assertions (b) and (c).

4. **NEVER paraphrase the Step 6a adopted-issue-closed directive ``Do NOT call `issue-lifecycle.sh close` ``.** **Why**: when the adopted issue is already closed, a second `issue-lifecycle.sh close` would double-post a DONE comment on top of the externally-written closing comment and run the PR-backfill with an empty `PR_URL` (since `/implement` bailed before producing a PR) — visible doubled noise on the closed issue. The directive is phrased with the specific script name, not a bare "Do NOT call" fragment, because the harness's `awk` window also includes Step 6b (whose "Do NOT call `/implement`" sentence would otherwise mask the deletion). **How to apply**: preserve the full phrase verbatim; if `issue-lifecycle.sh` is ever renamed, update the harness in the same PR. **CI-backed**: yes — assertion (d).

5. **NEVER re-route Step 6a failure branches away from `Skip to Step 9`.** **Why**: both failure branches (adopted-issue-closed and generic-failure) must drop into Step 9 cleanup, not into Step 7 (close issue) or Step 8 (Slack announce). Step 7 would either double-close an already-closed issue or DONE-comment a PR-less task; Step 8 would announce a merged PR that never existed. Step 9 cleanup is the only safe landing — the `IN PROGRESS` comment stays in place on generic failure as the manual-intervention signal. **How to apply**: keep `Skip to Step 9` in both 6a failure-branch bullets. **CI-backed**: yes — assertion (e).

6. **NEVER allow the NON_PR path (Step 6b) to modify working-tree files.** **Why**: `NON_PR` tasks are defined by producing GitHub issues, research summaries, or comment output rather than code changes. Writing to the working tree on this path opens a cascade of unanswered questions: what to commit, what branch to use, whether to push, whether to create a PR — none of which the NON_PR workflow addresses. The invariant is editorial (the runtime does not block edits) and depends on the SKILL.md text making the rule unambiguous. **How to apply**: keep the "Do NOT call `/implement`. Do NOT modify files in the working tree" sentence inside Step 6b (in SKILL.md, not only in the reference). `--input-file` markdown for `/issue` batch mode lives under `$FIX_ISSUE_TMPDIR` per `skills/fix-issue/references/non-pr-execution.md`. **CI-backed**: no (editorial invariant).

## Step 0 — Setup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-fix-issue --skip-branch-check
```

Parse output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`. Set `FIX_ISSUE_TMPDIR` = `SESSION_TMPDIR`.

If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository. GitHub issue access requires a valid repo. Aborting.**` and skip to Step 9.

If `SLACK_OK=true`, set `slack_available=true`. **Do NOT make a separate Bash call to resolve Slack env vars.** When Slack tokens are needed (Steps 4 and 8), use inline shell expansion: `"${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}"` and `"${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"`.

If `SLACK_OK=false`, print (only when `slack_enabled=true`) `**⚠ Slack not configured ($SLACK_MISSING). Slack announcements will be skipped.**` Set `slack_available=false`. When `slack_enabled=false` (user passed `--no-slack`), suppress the warning.

Write session-env for forwarding to `/implement`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$FIX_ISSUE_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value> \
  --codex-healthy true --cursor-healthy true
```

## Step 1 — Fetch Eligible Issue

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/fetch-eligible-issue.sh ["$ISSUE_ARG"]
```

Only include `"$ISSUE_ARG"` as a positional argument if `ISSUE_ARG` is non-empty (the user provided an issue number/URL via positional argument or the deprecated `--issue` flag).

Candidates are required to be open, have `GO` as their last comment, not be locked by a prior `IN PROGRESS` comment, and **have no currently-open blocking dependencies** from either of two sources: (1) GitHub's native issue-dependencies feature, queried via `repos/{owner}/{repo}/issues/{N}/dependencies/blocked_by`, and (2) prose-stated dependencies in the issue body and every comment body, matched against the conservative case-insensitive keyword set `Depends on #N`, `Blocked by #N`, `Blocked on #N`, `Requires #N`, `Needs #N` (each keyword followed by whitespace + `#<digits>`; emphasis wrappers like `**#150**` are tolerated, link-target forms like `[#150](url)` and cross-repo `owner/repo#N` are deliberately NOT matched). An issue whose listed blockers are all closed is eligible; an issue with even one open blocker (from either source) is skipped in auto-pick mode and reported as ineligible in explicit `--issue` mode. If either dependency check fails at any boundary (API unavailability, parser error, transient `gh` failure), it degrades silently to "no blockers known from that source" so API availability never hard-blocks the automation. Prose parsing is implemented by `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/parse-prose-blockers.sh`, guarded by the offline regression harness `test-parse-prose-blockers.sh` (run via `make lint`).

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

**MANDATORY — READ ENTIRE FILE** before beginning triage: `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/references/triage-classification.md`. Contains the triage check list, the not-material closure flow detail (rationale composition with research summary), and the Step 5 classification detail that shares the same file. **Do NOT load** outside Steps 4 and 5 — this file is not consumed anywhere else. **Do NOT load** when Step 1's `fetch-eligible-issue.sh` returned exit 1 (no approved issues) or exit 2+ (error) — Steps 4 and 5 do not run on those paths.

Decide whether the issue is still material against the codebase (see the reference for the check list and the triage-targets rule for investigation/review-only issues).

**If the issue is no longer material** (already fixed, invalid, or no longer relevant): compose a detailed explanation with a research summary per the reference, then:

1. Close with the explanation as the comment:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
     --issue $ISSUE_NUMBER --comment "Closing: <detailed explanation with research summary>"
   ```
2. If `slack_enabled=true` AND `slack_available=true`, post Slack notification via the shared script (carries the closure reason as `--detail`):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/post-issue-slack.sh \
     --issue-number "$ISSUE_NUMBER" --status closed --repo "$REPO" \
     --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
     --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
     --detail "<one-sentence reason>"
   ```
   On non-zero exit, log to `Tool Failures` and continue. Do not abort.
3. Print `✅ 4: triage — issue #$ISSUE_NUMBER closed, not material (<elapsed>)`. Skip to Step 9.

**If the issue is still actual**, print `✅ 4: triage — issue is active, proceeding (<elapsed>)` and continue.

## Step 5 — Classify Intent and Complexity

Print `> **🔶 5: classify**`

The reference loaded at Step 4 (`skills/fix-issue/references/triage-classification.md`) owns the decision rules for both dimensions — do not re-load it here.

- **Intent** (`PR` vs `NON_PR`): does this issue prescribe work whose natural output is a pull request, or something else (new issues, a written report)? Default to `PR` only when the issue is genuinely ambiguous; when the issue text explicitly forbids a PR or mandates research/issues as the deliverable, pick `NON_PR` regardless of the default.
- **Complexity** (only when `INTENT=PR`): `SIMPLE` (isolated fix in ≤2 files with no architectural decisions) vs `HARD` (everything else). Default to `HARD` when uncertain. Leave `COMPLEXITY` unset when `INTENT=NON_PR`.

Set `INTENT` and (when `INTENT=PR`) `COMPLEXITY` per those rules using the issue details and Step 4's codebase exploration.

Print `✅ 5: classify — INTENT=$INTENT [COMPLEXITY=$COMPLEXITY] (<elapsed>)` (omit the `COMPLEXITY=` segment when `INTENT=NON_PR`).

## Step 6 — Execute

Print `> **🔶 6: execute**`

Branch on `INTENT` from Step 5.

### 6a — `INTENT=PR` path (delegate to `/implement`)

Compose the feature description from the issue content: use the issue title as the primary description, with key details from the issue body and comments as context.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Invoke `/implement` via the Skill tool. Forwarding `--issue $ISSUE_NUMBER` makes `/implement` adopt the queue issue as its tracking issue (Phase 3 Branch 2 adoption), so the two skills converge on the same tracking issue and `/fix-issue` avoids a duplicate tracking-issue on its path:

- **SIMPLE**: `/implement --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh --issue $ISSUE_NUMBER [--no-slack if !slack_enabled] [--debug if debug_mode] <feature description>`
- **HARD**: `/implement --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh --issue $ISSUE_NUMBER [--no-slack if !slack_enabled] [--debug if debug_mode] <feature description>`

After `/implement` completes, capture the PR URL and PR number from its output. Save as `PR_URL` and `PR_NUMBER`.

> **Continue after child returns (success path only).** If `/implement` succeeded and `PR_URL` / `PR_NUMBER` are captured, your next user-facing output MUST be the Step 7 breadcrumb (`> **🔶 7: close issue**`) — do NOT write a summary, status recap, or "returning to caller" message first. If `/implement` failed or bailed, ignore this directive and follow the failure-path branch below. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

If `/implement` exits non-zero, branch on whether the captured output (stdout + transcript surface) contains the literal token `IMPLEMENT_BAIL_REASON=adopted-issue-closed` (emitted by `/implement` Step 0.5 Branch 2 when the adopted tracking issue is closed):

- **Bail detected** (token present): the adopted issue was closed externally after `/fix-issue` locked it. Print `**⚠ 6: execute — /implement bailed: issue #$ISSUE_NUMBER was closed externally after /fix-issue locked it. Cannot recover automatically. (<elapsed>)**`. Do NOT call `issue-lifecycle.sh close` — the issue is already closed and there is no successful run to pair with a DONE comment / PR backfill. Skip to Step 9 cleanup.
- **Generic failure** (token absent): print `**⚠ 6: execute — /implement failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS. (<elapsed>)**`. Skip to Step 9. The IN PROGRESS comment serves as an indicator that manual intervention is needed.

### 6b — `INTENT=NON_PR` path (follow instructions inline)

**MANDATORY — READ ENTIRE FILE** before executing the NON_PR path: `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/references/non-pr-execution.md`. Contains the common NON_PR patterns (research, code-review, other investigative/planning tasks), the `WORK_SUMMARY` running-summary discipline that becomes Step 7b's closing comment and Step 8b's Slack message, and the failure fallback. **Do NOT load** when `INTENT=PR` — Step 6a delegates to `/implement` and never consumes this file. **Do NOT load** in any step other than 6.

Read the issue details from Step 3 and execute the instructions directly using Read, Grep, Glob, and Bash. Do NOT call `/implement`. Do NOT modify files in the working tree — `NON_PR` tasks deliver their output as new GitHub issues, a written summary comment, or both.

> **Continue after child returns.** When any child Skill (`/issue`, `/research`, ...) returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Maintain a running `WORK_SUMMARY` per the reference — it becomes the closing comment in Step 7 and the Slack message in Step 8. Keep `PR_URL` and `PR_NUMBER` unset on this path.

If the work cannot be completed (e.g., `/issue` fails repeatedly, the issue's instructions are infeasible, or required external access is unavailable), print `**⚠ 6: execute — non-PR task failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS. (<elapsed>)**` and skip to Step 9. The IN PROGRESS comment serves as an indicator that manual intervention is needed — same recovery semantics as the `/implement` failure path.

## Step 7 — Close Issue

Print `> **🔶 7: close issue**`

`issue-lifecycle.sh close` is **idempotent**: if the issue was auto-closed externally before Step 7 runs (e.g., GitHub's `Closes #<N>` PR-merge auto-close from a `/implement --merge` invocation), the call still succeeds cheaply — the DONE comment and `--pr-url` body backfill still run, only the `gh issue close` call is skipped. The stdout contract (`CLOSED=true` on success) is identical across the open and already-closed paths, so this step does not need to branch on whether the issue was already closed (stderr carries a diagnostic `INFO` or `WARNING` signal when relevant). See `skills/fix-issue/scripts/issue-lifecycle.md` for the full contract including probe-failure fallback and partial-success semantics.

Branch on `INTENT`.

### 7a — `INTENT=PR`

Update the issue body with the PR link and close with a DONE comment (single call):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --pr-url "$PR_URL" --comment "DONE"
```

### 7b — `INTENT=NON_PR`

Close the issue with `WORK_SUMMARY` as the closing comment (no `--pr-url`, no body update):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --comment "$WORK_SUMMARY"
```

Print `✅ 7: close issue — #$ISSUE_NUMBER closed (<elapsed>)`

## Step 8 — Slack Announce (NON_PR path only)

The PR path's Slack announcement is handled by the child `/implement` at its Step 16a — this skill does NOT post again to avoid duplication. This step runs only for `INTENT=NON_PR`.

If `INTENT=PR`, print `⏭️ 8: slack announce — skipped (PR path — /implement posted at Step 16a) (<elapsed>)` and proceed to Step 9.

If `slack_enabled=false` (user passed `--no-slack`), print `⏭️ 8: slack announce — skipped (--no-slack) (<elapsed>)` and proceed to Step 9.

If `slack_available=false`, print `⏭️ 8: slack announce — skipped (Slack not configured) (<elapsed>)` and proceed to Step 9.

### 8b — `INTENT=NON_PR`

Post a Slack message summarizing the non-PR work via the shared script. Compose the `--detail` value from `WORK_SUMMARY` — a one-sentence summary is ideal (e.g., "research complete, filed #123 and #124" or "code review complete, filed 5 issues"):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/post-issue-slack.sh \
  --issue-number "$ISSUE_NUMBER" --status closed --repo "$REPO" \
  --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
  --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
  --detail "<one-sentence summary from WORK_SUMMARY>"
```

If the script exits non-zero, print `**⚠ 8: slack announce — failed. Continuing.**` and log to `Tool Failures`.

Print `✅ 8: slack announce — posted (<elapsed>)`

## Step 9 — Cleanup

**This step ALWAYS runs**, regardless of the outcome of prior steps (success, failure, early exit, or abort).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$FIX_ISSUE_TMPDIR"
```

Print `✅ 9: cleanup — fix-issue complete! (<elapsed>)`

## Known Limitations

- **Stale IN PROGRESS lock**: Step 2 deletes the `GO` comment and posts `IN PROGRESS` (so the `GO` sentinel no longer remains after locking). If the skill crashes after Step 2 completes, the issue's last comment is `IN PROGRESS` — recovery: manually delete the `IN PROGRESS` comment and re-add `GO`. If it crashes mid-Step-2 (between deleting `GO` and posting `IN PROGRESS`), the issue has neither sentinel — recovery: manually re-add `GO`.
- **Single-runner assumption**: The comment-based locking (Step 2) includes duplicate detection but is not fully atomic. For reliable operation, run one instance of `/fix-issue` at a time per repository.
- **Dependency check degrades silently on API failure**: The blocked-by check (Step 1) treats unreachable or erroring dependency-API responses as "no blockers known" to avoid hard-blocking the automation. If GitHub's issue-dependencies endpoint is returning 5xx or an unexpected payload, a blocked issue could temporarily be eligible. The GO sentinel still applies, so the blast radius is limited to whatever the reviewer intended to allow via `GO`.
- **Prose-dependency check shares the same fail-open posture**: A parser regression, body/comment fetch failure, or per-reference state lookup failure all degrade to "no prose blockers known" for that candidate. The offline harness (`test-parse-prose-blockers.sh`, run via `make lint`) is the primary guard against parser regressions.
- **Prose-dep check uses a strict keyword grammar**: The five recognized phrases (`Depends on`, `Blocked by`, `Blocked on`, `Requires`, `Needs`) must be immediately followed by whitespace + `#<digits>`. Typos like `Depends on#150` (no space), cross-repo references (`owner/repo#150`), URL forms (`https://github.com/…/150`), and bare `#150` mentions are deliberately NOT matched. Emphasis wrappers (`**#150**`, `_#150_`) ARE matched. Link-target wrappers (`[#150](url)`) are NOT matched, so link targets can never smuggle cross-repo references through the parser.
- **Short-circuit when native blockers exist — user-visible messages may omit prose blockers**: When an issue has BOTH native and prose open blockers, the prose path is short-circuited for rate-limit efficiency. The skip/error message will list only the native blocker numbers. Closing all listed native blockers and re-running `/fix-issue` will surface any remaining prose blockers on the next run.
- **External close while `/fix-issue` holds IN PROGRESS**: `/implement`'s Step 0.5 detects a closed adopted issue and bails with `IMPLEMENT_BAIL_REASON=adopted-issue-closed`; `/fix-issue` Step 6a reports the condition but does not unlock, since a closed issue cannot be re-locked. Recovery: re-open the issue manually and re-trigger via a new `GO` comment.
- **Bail-token detection depends on output preservation**: the adopted-issue-closed branch in Step 6a scans the captured `/implement` output for the exact literal `IMPLEMENT_BAIL_REASON=adopted-issue-closed`. If the runtime summarizes the child skill's output and the literal token is lost, Step 6a falls through to the generic-failure branch and prints the "remains locked with IN PROGRESS" message — misleading for an externally-closed issue, but operator recovery is identical (re-open, re-add `GO`). The harness at `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` guards against accidental removal of the token literal from this SKILL.md, but cannot guarantee runtime preservation of the token.
