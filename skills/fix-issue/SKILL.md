---
name: fix-issue
description: "Use when fixing open GitHub issues. Processes one approved issue per invocation: skips issues with open blockers, triages, classifies intent, then either delegates to /implement or follows the issue's instructions inline for research/review tasks."
argument-hint: "[--debug] [--no-slack] [--no-admin-fallback] [--issue <number-or-url>] [<number-or-url>]"
allowed-tools: Bash, Read, Grep, Glob, Skill
---

# Fix Issue

Process one approved GitHub issue per invocation. Fetches open issues with a `GO` sentinel comment, skips any whose GitHub issue-dependencies list includes an open blocker, triages the remaining candidate against the codebase, classifies **intent** (PR-producing vs. non-PR task) and (for PR work) **complexity**, and either delegates to `/implement` or executes the issue's instructions inline. Non-PR tasks — e.g., "research topic X and summarize findings as issues", "code-review module Y and file issues for each problem" — are followed without `/implement`; any output issues are created via `/issue` and the source issue is closed with a work summary instead of a PR link.

**Single-iteration design**: Each invocation handles at most one issue, then exits. The caller (cron, `/loop`, or manual invocation) is responsible for repeated execution.

**Anti-halt continuation reminder.** After every child tool call returns — both child `Skill` tool calls (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) AND child Bash tool calls into the canonical `/fix-issue` script set (`issue-lifecycle.sh`, `tracking-issue-write.sh`, `post-issue-slack.sh`, `cleanup-tmpdir.sh`, `find-lock-issue.sh`, `session-setup.sh`, `write-session-env.sh`, `get-issue-details.sh`) — IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The Bash-tool-call coverage is unique to this `/fix-issue` skill. The terminal Step 6 → Step 7 → Step 8 sequence has no intervening Skill tool calls. Step 6 always invokes `issue-lifecycle.sh close` (and additionally invokes `tracking-issue-write.sh rename` on the NON_PR sub-branch 6b); Step 8 invokes `cleanup-tmpdir.sh` when a temp dir was created (otherwise it is prose-only); on the PR path Step 7 is itself a prose-only skip with no Bash call at all. The same Skill-free **close/announce/cleanup tail** pattern recurs in Step 3's not-material closure flow (close + best-effort rename + Slack + skip-to-cleanup) and in the Step 6b → Step 7b → Step 8 NON_PR close path. Step 5b's NON_PR body is separate from this tail pattern: it may call `/issue` (covered by the Skill-tool reminder above) and run additional Bash (covered by the same Bash-tool reminder above, applied to its full scope as stated next). The enumerated script list is the always-covered minimum scope; the rule applies equally to **any** Bash tool call invoked as part of a `/fix-issue` step's primary work — including Step 5b's inline `gh` queries, shell `test` invocations, and ad-hoc Bash. The Read / Grep / Glob tools are first-class Claude Code tools, not Bash subprocesses — their returns are not directly governed by this Bash extension, but the same continuation discipline applies: do not treat a tool return inside `/fix-issue`'s step sequence as a turn boundary — continue to the next sequenced step unless this file's explicit control-flow directives (`skip to Step N`, `bail to cleanup`, etc.) tell you otherwise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule — note that the shared file remains scoped to `Skill` tool calls only; the broader Bash-call coverage in the paragraph above is `/fix-issue`-local and does NOT propagate to other skills.

**Flags**: Parse flags from the start of `$ARGUMENTS`.

- `--debug`: Set `debug_mode=true`. Forward `--debug` to `/implement` in Step 5. Default: `debug_mode=false`.
- `--no-slack`: Set `slack_enabled=false`. Forward `--no-slack` to `/implement` in Step 5a. Default: `slack_enabled=true`. When `slack_enabled=true` (default), the delegated `/implement` run posts to Slack (Step 16a) when Slack env vars are configured; the `NON_PR` path's Step 7 Slack announcement also posts via the shared `scripts/post-issue-slack.sh`. When `slack_enabled=false` (user passed `--no-slack`), no Slack calls are made on either path.
- `--no-admin-fallback`: Set `no_admin_fallback=true`. Forward `--no-admin-fallback` to `/implement` in Step 5a (both SIMPLE and HARD bullets). Default: `no_admin_fallback=false`. When `true`, the delegated `/implement` run instructs `merge-pr.sh` to emit `MERGE_RESULT=policy_denied` instead of retrying with `--admin` once the admin-eligible gate (CI good + branch fresh) is reached, and the run bails to Step 12d with a documented reason. See `skills/implement/SKILL.md` `--no-admin-fallback` for the full semantics. Default behavior unchanged.
- `--issue <number-or-url>`: **Deprecated** — recognized for backward compatibility. Prefer passing the issue number or URL as a positional argument (e.g., `/fix-issue 42`). When this flag is encountered, print: `**ℹ '--issue' is deprecated; pass the issue number or URL as a positional argument instead (e.g., /fix-issue 42).**`
- **Positional argument** (after flag stripping): If any non-flag text remains in `$ARGUMENTS` after stripping all flags defined above (`--debug`, `--no-slack`, `--no-admin-fallback`, `--issue`), treat it as the issue number or URL. Set `ISSUE_ARG` to this value. When set, Step 0 targets this specific issue instead of scanning for an eligible candidate (auto-pick prefers issues with the whole word `urgent` anywhere in the title — case-insensitive, word-boundary; "non-urgent" does NOT match — and falls back to oldest-first within each tier). Accepts a bare issue number (e.g., `42`) or a full GitHub issue URL (e.g., `https://github.com/owner/repo/issues/42`). The issue must be open, have `GO` as its last comment, and have no currently-open blocking dependencies (see Step 0 for the degradation note when the dependency endpoint is unavailable). Default: empty (auto-pick mode). If both `--issue` and a positional argument are provided, print: `**⚠ Both --issue and a positional argument were provided. Using the positional argument.**` and use the positional argument.

## Mindset

Before processing each invocation, hold these four questions.

**Is the issue still real?** Codebases move. A two-week-old bug may already be fixed; a "refactor X" request may reference deleted code. Triage (Step 3) is the cheap first-line filter — closing a stale issue with a research-summary comment is always cheaper than drafting a no-op PR.

**What shape of output does the issue want back?** A code change (merged PR) vs. new GitHub issues or a written summary (NON_PR). Classification (Step 4) is a low-variance binary call; most issues are unambiguous. Default to `PR` **only when the issue is genuinely ambiguous** — a mis-classified `NON_PR` may sometimes surface during `/implement`'s `/review` phase (which reviews code changes, not the shape-of-work contract), in which case the operator may need to stop the run. When the issue text explicitly forbids a PR or mandates research/issues as the deliverable, pick `NON_PR` regardless of the default — overriding the stated deliverable is not recoverable downstream. A mis-classified `PR` (picking `NON_PR` for a genuine code-change request) silently skips real work.

**How fragile is the change?** Complexity (Step 4) picks `/implement --quick` (SIMPLE — single-reviewer loop) or the full `/design` + `/review` panel (HARD). Default to HARD — an extra design round on a truly simple issue costs little, while skipping `/design` on a multi-file refactor costs a broken PR.

**Where does a crash leave the issue?** `IN PROGRESS` is a lock, not a status. Once Step 0 reports `LOCK_ACQUIRED=true`, any later crash leaves `IN PROGRESS` as the last comment AND the title prefixed with `[IN PROGRESS]` until a human clears them; a crash mid-Step-0 (after `GO` is deleted, before `IN PROGRESS` posts) can leave the issue with neither sentinel. Consult Known Limitations for each recovery path before deviating from the step sequence.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:

| Step | Short Name |
|------|-----------|
| 0 | find & lock |
| 1 | setup |
| 2 | read details |
| 3 | triage |
| 4 | classify |
| 5 | execute |
| 6 | close issue |
| 7 | slack announce |
| 8 | cleanup |

## Anti-patterns

Each rule states **Why** (the specific consequence of breaking the rule) and **How to apply** (where the invariant is load-bearing). Rules marked **CI-backed: yes** are mechanically enforced by `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` via an `awk` extraction over the `### 5a` block (under Step 5 — Execute); the remaining rules are editorial invariants that depend on the SKILL.md text being unambiguous.

1. **NEVER run Step 1+ on an unlocked issue.** **Why**: the `IN PROGRESS` lock acquired at Step 0 is how concurrent runners avoid stepping on each other — `find-lock-issue.sh` skips candidates whose last comment is `IN PROGRESS`, so posting `IN PROGRESS` installs the lock at the comment-stream tail (same tail semantics the find filter reads) AND prepends `[IN PROGRESS]` to the title so the visual lifecycle reflects the active run immediately. Duplicate detection is best-effort, not fully atomic — see Known Limitations "Single-runner assumption". Stepping past Step 0 unlocked races every other `/fix-issue` invocation on the same repo. **How to apply**: treat Step 0 as structural; do not re-order the step sequence or skip it under any flag. **CI-backed**: no (editorial invariant).

2. **NEVER drop the `--issue $ISSUE_NUMBER` forward from either Step 5a `/implement` invocation bullet (SIMPLE or HARD).** **Why**: `--issue $ISSUE_NUMBER` causes `/implement` Step 0.5 Branch 2 to adopt the already-locked tracking issue rather than creating a duplicate via Branch 4. Dropping the forward splits tracking onto two different issues, breaks the `Closes #<N>` PR-body recovery on resumed runs, and leaves the `/fix-issue`-side issue locked under `IN PROGRESS` with no auto-close on merge. **How to apply**: keep `--issue $ISSUE_NUMBER` in both SIMPLE and HARD `/implement` invocation bullets in Step 5a. **CI-backed**: yes — assertions (a1) and (a2) in `test-fix-issue-bail-detection.sh`.

3. **NEVER remove the `IMPLEMENT_BAIL_REASON=adopted-issue-closed` literal or its accompanying `/implement bailed: issue #` warning-prefix literal from Step 5a.** **Why**: when `/implement` adopts a tracking issue that was closed externally between lock and execution, it emits the bail token on stdout; Step 5a's branch scans captured output for that exact literal. Dropping either literal from SKILL.md routes Step 5a to the generic-failure branch ("remains locked with IN PROGRESS") instead of the adopted-issue-closed branch that reports the specific externally-closed condition. **How to apply**: preserve both literal strings verbatim inside the `### 5a` block. **CI-backed**: yes — assertions (b) and (c).

4. **NEVER paraphrase the Step 5a adopted-issue-closed directive ``Do NOT call `issue-lifecycle.sh close` ``.** **Why**: when the adopted issue is already closed, a second `issue-lifecycle.sh close` would double-post a DONE comment on top of the externally-written closing comment and run the PR-backfill with an empty `PR_URL` (since `/implement` bailed before producing a PR) — visible doubled noise on the closed issue. The directive is phrased with the specific script name, not a bare "Do NOT call" fragment, because the harness's `awk` window also includes Step 5b (whose "Do NOT call `/implement`" sentence would otherwise mask the deletion). **How to apply**: preserve the full phrase verbatim; if `issue-lifecycle.sh` is ever renamed, update the harness in the same PR. **CI-backed**: yes — assertion (d).

5. **NEVER re-route Step 5a failure branches away from `Skip to Step 8`.** **Why**: both failure branches (adopted-issue-closed and generic-failure) must drop into Step 8 cleanup, not into Step 6 (close issue) or Step 7 (Slack announce). Step 6 would either double-close an already-closed issue or DONE-comment a PR-less task; Step 7 would announce a merged PR that never existed. Step 8 cleanup is the only safe landing — the `IN PROGRESS` comment stays in place on generic failure as the manual-intervention signal. **How to apply**: keep `Skip to Step 8` in both 5a failure-branch bullets. **CI-backed**: yes — assertion (e).

6. **NEVER allow the NON_PR path (Step 5b) to modify working-tree files.** **Why**: `NON_PR` tasks are defined by producing GitHub issues, research summaries, or comment output rather than code changes. Writing to the working tree on this path opens a cascade of unanswered questions: what to commit, what branch to use, whether to push, whether to create a PR — none of which the NON_PR workflow addresses. The invariant is editorial (the runtime does not block edits) and depends on the SKILL.md text making the rule unambiguous. **How to apply**: keep the "Do NOT call `/implement`. Do NOT modify files in the working tree" sentence inside Step 5b (in SKILL.md, not only in the reference). `--input-file` markdown for `/issue` batch mode lives under `$FIX_ISSUE_TMPDIR` per `skills/fix-issue/references/non-pr-execution.md`. **CI-backed**: no (editorial invariant).

7. **NEVER auto-pick umbrellas in the no-arg find-lock-issue scan.** **Why**: the umbrella-PR design dialectic (DECISION_1, voted 2-1 ANTI_THESIS) chose explicit-target-only umbrella handling. Auto-pick must keep its GO-tail invariant unchanged — folding umbrella handling into the bulk sweep multiplies decision-surface complexity (umbrella resolution is a distinct state machine with non-GO locking, child-pick semantics, and finalization paths) and increases operator surprise (umbrellas can be passive long-lived planning trackers). **How to apply**: `umbrella-handler.sh` is invoked ONLY in the explicit-issue path of `find-lock-issue.sh`. The auto-pick scan loop continues to require `GO` as the last comment for ANY candidate. Operators who want umbrella-tracked work to drain in `/loop-fix-issue` must explicitly pass the umbrella number (e.g., `/fix-issue <umbrella#>` once per dispatch cycle). **CI-backed**: yes — `test-find-lock-issue.sh` carries an `auto-pick-skips-umbrella` regression fixture.

## Step 0 — Find and Lock

Run find + lock + title rename FIRST so that no setup work (tmpdir, preflight, Slack/repo derivation, session-env write) is performed when there is no eligible issue, and so the `[IN PROGRESS]` title prefix is applied immediately on lock acquisition rather than minutes later (closes #496 — the prior delay came from /implement Step 0.5 Branch 2 owning the rename, which only ran after `/fix-issue`'s Step 1 setup, Step 2 read-details, Step 3 triage, Step 4 classification, Step 5a delegation, and `/implement`'s own Step 0 setup all completed; mapped from the pre-renumber Step 2/3/4/5/6a names by the fold-find-and-lock refactor).

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/find-lock-issue.sh ["$ISSUE_ARG"]
```

Only include `"$ISSUE_ARG"` as a positional argument if `ISSUE_ARG` is non-empty (the user provided an issue number/URL via positional argument or the deprecated `--issue` flag).

The script combines three operations in sequence: (1) eligibility scan or explicit-issue verification, (2) comment-lock acquisition by delegating to `issue-lifecycle.sh comment --lock` (verifies tail `GO`, deletes `GO`, posts `IN PROGRESS`, post-checks for duplicate `IN PROGRESS` races), (3) best-effort title rename to `[IN PROGRESS] <title>` by delegating to `tracking-issue-write.sh rename --state in-progress`. The comment lock is the **correctness invariant**; the title rename is purely a visual lifecycle marker. A rename failure does NOT undo the lock — `find-lock-issue.sh` still exits 0 with `LOCK_ACQUIRED=true RENAMED=false`. `/implement` Step 0.5 Branch 2's idempotent rename serves as the safety net (re-attempts on the next run-segment).

Candidates are required to be open, have `GO` as their last comment, not be locked by a prior `IN PROGRESS` comment, not carry a managed lifecycle title prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`), and **have no currently-open blocking dependencies** from either of two sources: (1) GitHub's native issue-dependencies feature, queried via `repos/{owner}/{repo}/issues/{N}/dependencies/blocked_by`, and (2) prose-stated dependencies in the issue body and every comment body, matched against the conservative case-insensitive keyword set `Depends on #N`, `Blocked by #N`, `Blocked on #N`, `Requires #N`, `Needs #N` (each keyword followed by whitespace + `#<digits>`; emphasis wrappers like `**#150**` are tolerated, link-target forms like `[#150](url)` and cross-repo `owner/repo#N` are deliberately NOT matched). An issue whose listed blockers are all closed is eligible; an issue with even one open blocker (from either source) is skipped in auto-pick mode and reported as ineligible in explicit positional-target mode. **Auto-pick selection order**: candidates are evaluated with issues whose title matches the whole word `urgent` (case-insensitive regex bounded by an explicit non-word lookaround that treats `-` as word-internal, anywhere in the title) FIRST; within each tier (Urgent vs. non-Urgent) ordering falls back to oldest-first by issue number. The match deliberately rejects substrings inside other words — `non-urgent`, `insurgent`, and `urgently` do NOT count as Urgent — to avoid the false positive a plain substring match would create on titles that mean the opposite of urgent (or use the letters incidentally). The Urgent preference is a soft signal — it only re-orders evaluation; a non-Urgent eligible issue is still picked when no Urgent eligible issue exists. The preference applies only to auto-pick (no positional argument); explicit-target mode picks exactly the issue named regardless of its title. If either dependency check fails at any boundary (API unavailability, parser error, transient `gh` failure), it degrades silently to "no blockers known from that source" so API availability never hard-blocks the automation. Prose parsing is implemented by `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/parse-prose-blockers.sh`, guarded by the offline regression harness `test-parse-prose-blockers.sh` (run via `make lint`).

**Umbrella-issue exception** (explicit-target path only — auto-pick never selects umbrellas, per the umbrella-PR design dialectic's DECISION_1): when the explicit issue is detected as an umbrella (body literal `Umbrella tracking issue.` OR title prefix `Umbrella:` / `Umbrella —`), the umbrella body serves as the approval signal and the chosen child is dispatched without a `GO` requirement. The umbrella's own blocker check still applies — a blocked umbrella exits 2. Children selected by `umbrella-handler.sh pick-child` inherit approval from the umbrella's existence (no per-child GO required). Eligibility for a chosen child = open + no managed lifecycle prefix + last comment ≠ `IN PROGRESS` + no open native/prose blockers. See `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/umbrella-handler.md` for the detection / child-enumeration / pick-child contracts and `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/finalize-umbrella.md` for the finalization (rename → comment → close) contract used by the Step 0 exit-4 path and the Step 3 / 5a / 6 finalize hooks.

`find-lock-issue.sh` resolves the repo identity itself via `gh repo view` and does not depend on any session-setup-derived state — making this step safe to run before Step 1 setup. See `skills/fix-issue/scripts/find-lock-issue.md` for the full stdout contract (`ELIGIBLE` / `ISSUE_NUMBER` / `ISSUE_TITLE` / `LOCK_ACQUIRED` / `RENAMED` / `ERROR`) and exit code semantics.

Handle exit codes:

- **Exit 0**: Parse `ISSUE_NUMBER`, `ISSUE_TITLE`, `LOCK_ACQUIRED=true`, `RENAMED`, plus the umbrella-only keys (`IS_UMBRELLA`, `UMBRELLA_NUMBER`, `UMBRELLA_TITLE`, `UMBRELLA_ACTION`) when present. **Hold `$UMBRELLA_NUMBER` as a session variable across Steps 1-7** so Steps 3, 5a, and 6 can run the umbrella-finalization hook (FINDING_1).
  - **Non-umbrella path** (`IS_UMBRELLA` absent or empty): print `> **🔶 0: find & lock — found and locked #$ISSUE_NUMBER: $ISSUE_TITLE**`. If `RENAMED=false`, the title rename failed best-effort — print `**⚠ 0: find & lock — title rename failed; /implement Branch 2 will retry. (<elapsed>)**` and continue. If `RENAMED=true`, print `✅ 0: find & lock — issue #$ISSUE_NUMBER locked and titled [IN PROGRESS] (<elapsed>)`. Continue to Step 1.
  - **Umbrella-dispatched path** (`IS_UMBRELLA=true UMBRELLA_ACTION=dispatched`): print `> **🔶 0: find & lock — found and locked child #$ISSUE_NUMBER of umbrella #$UMBRELLA_NUMBER: $ISSUE_TITLE**`. The literal substring `found and locked` is preserved (matching the non-umbrella path) so loop drivers like `/loop-fix-issue` recognize the success path with a single sentinel — see FINDING_2 from the umbrella-PR code-review panel. Same `RENAMED` warning/success print as the non-umbrella path. Continue to Step 1 — `$ISSUE_NUMBER` refers to the chosen child; downstream `/implement` adopts the CHILD via `--issue $ISSUE_NUMBER`.
- **Exit 1**: Print `✅ 0: find & lock — no approved issues found (<elapsed>)`. Skip to Step 8. **Note**: `FIX_ISSUE_TMPDIR` is unset on this path; Step 8's cleanup guard handles the no-tmpdir case.
- **Exit 2**: Parse `ERROR` from stdout. Print `**⚠ 0: find & lock — error: $ERROR (<elapsed>)**`. Skip to Step 8. **Note**: `FIX_ISSUE_TMPDIR` is unset on this path; Step 8's cleanup guard handles the no-tmpdir case.
- **Exit 3**: Eligibility passed but lock acquisition failed (concurrent runner won the race, the GO sentinel changed between the eligibility scan and the lock attempt, or `gh` API failed mid-sequence; for umbrella-dispatched paths, the failure is on the chosen child and the `ERROR` carries umbrella context — `Failed to lock chosen child #C of umbrella #U: <reason>`). Parse `ISSUE_NUMBER` and `ERROR`. Print `**⚠ 0: find & lock — lock failed for #$ISSUE_NUMBER: $ERROR. Another run may have claimed this issue, or the GO/IN PROGRESS comment stream may have been partially mutated — see Known Limitations "Stale IN PROGRESS lock" for recovery before re-running. (<elapsed>)**`. Skip to Step 8. The candidate may NOT be cleanly recoverable: `issue-lifecycle.sh comment --lock` deletes the GO comment BEFORE posting `IN PROGRESS`, so a `gh issue comment` failure between those two writes leaves the issue with no comment sentinel; a duplicate-`IN PROGRESS` post-check failure leaves both `IN PROGRESS` comments present. Both states require manual recovery per Known Limitations "Stale IN PROGRESS lock". The pre-write GO-tail re-check failure mode (last comment is no longer GO) IS clean — comment stream unchanged.
- **Exit 4** (umbrella complete — all parsed children CLOSED): parse `UMBRELLA_NUMBER` and `UMBRELLA_TITLE`. Print `> **🔶 0: find & lock — umbrella #$UMBRELLA_NUMBER all-closed; finalizing**`. Invoke:
  ```bash
  ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/finalize-umbrella.sh finalize --issue $UMBRELLA_NUMBER
  ```
  Parse `FINALIZED`, `ALREADY_FINALIZED`, `RENAMED`, `CLOSED`, `ERROR`. On `FINALIZED=true`: print `✅ 0: find & lock — umbrella #$UMBRELLA_NUMBER finalized ([DONE] + closed) (<elapsed>)`. On `ALREADY_FINALIZED=true`: print `✅ 0: find & lock — umbrella #$UMBRELLA_NUMBER already finalized (<elapsed>)`. On `FINALIZED=false` non-idempotent failure: print `**⚠ 0: find & lock — umbrella #$UMBRELLA_NUMBER finalize failed: $ERROR (<elapsed>)**`. In all three sub-cases, skip to Step 8.
- **Exit 5** (umbrella detected but no eligible child): parse `UMBRELLA_NUMBER` and `ERROR`. Print `**⚠ 0: find & lock — umbrella #$UMBRELLA_NUMBER has no eligible child: $ERROR (<elapsed>)**`. Skip to Step 8. The umbrella stays open; the next `/fix-issue` invocation re-evaluates its children.

## Step 1 — Setup

Runs only after Step 0 successfully locked the issue. A failure here leaves the issue locked with `IN PROGRESS` (and the title prefixed `[IN PROGRESS]`) — same recovery semantics as any mid-run crash (manual `IN PROGRESS` comment clearance + title-prefix strip + re-add `GO`).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-fix-issue --skip-branch-check
```

Parse output for `SESSION_TMPDIR`, `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`. **Set `FIX_ISSUE_TMPDIR` = `SESSION_TMPDIR` IMMEDIATELY after parsing — before any abort branch below** — so that a post-mktemp setup failure (e.g., `REPO_UNAVAILABLE=true`) still gets the tmpdir cleaned up by Step 8. If `SESSION_TMPDIR` is absent from output (preflight failed before mktemp), leave `FIX_ISSUE_TMPDIR` unset; Step 8's cleanup guard handles that case.

If `REPO_UNAVAILABLE=true`, print `**⚠ Could not determine repository. GitHub issue access requires a valid repo. Aborting.**` and skip to Step 8.

If `SLACK_OK=true`, set `slack_available=true`. **Do NOT make a separate Bash call to resolve Slack env vars.** When Slack tokens are needed (Steps 3 and 7), use inline shell expansion: `"${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}"` and `"${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}"`.

If `SLACK_OK=false`, print (only when `slack_enabled=true`) `**⚠ Slack not configured ($SLACK_MISSING). Slack announcements will be skipped.**` Set `slack_available=false`. When `slack_enabled=false` (user passed `--no-slack`), suppress the warning.

Write session-env for forwarding to `/implement`:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$FIX_ISSUE_TMPDIR/session-env.sh" \
  --slack-ok <value> --slack-missing <value> --repo <value> --repo-unavailable <value> \
  --codex-healthy true --cursor-healthy true
```

## Step 2 — Read Issue Details

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/get-issue-details.sh \
  --issue $ISSUE_NUMBER --output "$FIX_ISSUE_TMPDIR/issue-details.txt"
```

Read `$FIX_ISSUE_TMPDIR/issue-details.txt` to get the full issue content.

## Step 3 — Triage

Print `> **🔶 3: triage**`

**MANDATORY — READ ENTIRE FILE** before beginning triage: `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/references/triage-classification.md`. Contains the triage check list, the not-material closure flow detail (rationale composition with research summary), and the Step 4 classification detail that shares the same file. **Do NOT load** outside Steps 3 and 4 — this file is not consumed anywhere else. **Do NOT load** on any path that has already branched to Step 8 (Steps 3 and 4 do not run there). Concrete examples: Step 0 returned exit 1 / 2 / 3 (lock failed after eligibility), Step 1 setup aborted with `REPO_UNAVAILABLE=true`.

Decide whether the issue is still material against the codebase (see the reference for the check list and the triage-targets rule for investigation/review-only issues).

**If the issue is no longer material** (already fixed, invalid, or no longer relevant): compose a detailed explanation with a research summary per the reference, then:

1. Close with the explanation as the comment:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
     --issue $ISSUE_NUMBER --comment "Closing: <detailed explanation with research summary>"
   ```
2. **Best-effort terminal title rename** to clear the `[IN PROGRESS]` prefix Step 0 applied at lock time, replacing it with `[DONE]` so the closed issue's title accurately reflects that automated processing concluded:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/tracking-issue-write.sh rename \
     --issue $ISSUE_NUMBER --state done
   ```
   Idempotent and best-effort: on `FAILED=true` or non-zero exit, log to `Tool Failures` and continue. Without this rename, a closed not-material issue would persist with the misleading `[IN PROGRESS]` title prefix until manually edited (because `/implement` Step 12a/12b/18 terminal renames only run on the PR delegation path).
3. **Umbrella finalize hook** (FINDING_7 — ordering: AFTER child rename in step 2, BEFORE Slack in step 4): if `$UMBRELLA_NUMBER` is set (Step 0 dispatched this child from an umbrella), check whether the umbrella is now empty and finalize if so:
   ```bash
   PICK_OUT=$(${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/umbrella-handler.sh pick-child --issue $UMBRELLA_NUMBER 2>&1)
   ALL_CLOSED=$(echo "$PICK_OUT" | awk -F= '/^ALL_CLOSED=/ { v=$2 } END { print v }')
   if [ "$ALL_CLOSED" = "true" ]; then
       ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/finalize-umbrella.sh finalize --issue $UMBRELLA_NUMBER
   fi
   ```
   Best-effort: on `FAILED=true` / non-zero exit / `FINALIZED=false` non-idempotent error, log to `Tool Failures` and continue. The next `/fix-issue <umbrella#>` invocation will re-attempt finalization via the Step 0 exit-4 path.
4. If `slack_enabled=true` AND `slack_available=true`, post Slack notification via the shared script (carries the closure reason as `--detail`):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/post-issue-slack.sh \
     --issue-number "$ISSUE_NUMBER" --status closed --repo "$REPO" \
     --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
     --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
     --detail "<one-sentence reason>"
   ```
   On non-zero exit, log to `Tool Failures` and continue. Do not abort.
5. Print `✅ 3: triage — issue #$ISSUE_NUMBER closed, not material (<elapsed>)`. Skip to Step 8.

**If the issue is still actual**, print `✅ 3: triage — issue is active, proceeding (<elapsed>)` and continue.

## Step 4 — Classify Intent and Complexity

Print `> **🔶 4: classify**`

The reference loaded at Step 3 (`skills/fix-issue/references/triage-classification.md`) owns the decision rules for both dimensions — do not re-load it here.

- **Intent** (`PR` vs `NON_PR`): does this issue prescribe work whose natural output is a pull request, or something else (new issues, a written report)? Default to `PR` only when the issue is genuinely ambiguous; when the issue text explicitly forbids a PR or mandates research/issues as the deliverable, pick `NON_PR` regardless of the default.
- **Complexity** (only when `INTENT=PR`): `SIMPLE` (isolated fix in ≤2 files with no architectural decisions) vs `HARD` (everything else). Default to `HARD` when uncertain. Leave `COMPLEXITY` unset when `INTENT=NON_PR`.

Set `INTENT` and (when `INTENT=PR`) `COMPLEXITY` per those rules using the issue details and Step 3's codebase exploration.

Print `✅ 4: classify — INTENT=$INTENT [COMPLEXITY=$COMPLEXITY] (<elapsed>)` (omit the `COMPLEXITY=` segment when `INTENT=NON_PR`).

## Step 5 — Execute

Print `> **🔶 5: execute**`

Branch on `INTENT` from Step 4.

### 5a — `INTENT=PR` path (delegate to `/implement`)

Compose the feature description from the issue content: use the issue title as the primary description, with key details from the issue body and comments as context.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Invoke `/implement` via the Skill tool. Forwarding `--issue $ISSUE_NUMBER` makes `/implement` adopt the queue issue as its tracking issue (Phase 3 Branch 2 adoption), so the two skills converge on the same tracking issue and `/fix-issue` avoids a duplicate tracking-issue on its path:

- **SIMPLE**: `/implement --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh --issue $ISSUE_NUMBER [--no-slack if !slack_enabled] [--no-admin-fallback if no_admin_fallback] [--debug if debug_mode] <feature description>`
- **HARD**: `/implement --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh --issue $ISSUE_NUMBER [--no-slack if !slack_enabled] [--no-admin-fallback if no_admin_fallback] [--debug if debug_mode] <feature description>`

After `/implement` completes, capture the PR URL and PR number from its output. Save as `PR_URL` and `PR_NUMBER`.

> **Continue after child returns (success path only).** If `/implement` succeeded and `PR_URL` / `PR_NUMBER` are captured, your next user-facing output MUST be the Step 6 breadcrumb (`> **🔶 6: close issue**`) — do NOT write a summary, status recap, or "returning to caller" message first. If `/implement` failed or bailed, ignore this directive and follow the failure-path branch below. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

If `/implement` exits non-zero, branch on whether the captured output (stdout + transcript surface) contains the literal token `IMPLEMENT_BAIL_REASON=adopted-issue-closed` (emitted by `/implement` Step 0.5 Branch 2 when the adopted tracking issue is closed):

- **Bail detected** (token present): the adopted issue was closed externally after `/fix-issue` locked it. Print `**⚠ 5: execute — /implement bailed: issue #$ISSUE_NUMBER was closed externally after /fix-issue locked it. Cannot recover automatically. (<elapsed>)**`. Do NOT call `issue-lifecycle.sh close` — the issue is already closed and there is no successful run to pair with a DONE comment / PR backfill. **Umbrella finalize hook** (FINDING_8): before skipping to Step 8, if `$UMBRELLA_NUMBER` is set, check whether the externally-closed child was the umbrella's last open child and finalize if so:
   ```bash
   PICK_OUT=$(${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/umbrella-handler.sh pick-child --issue $UMBRELLA_NUMBER 2>&1)
   ALL_CLOSED=$(echo "$PICK_OUT" | awk -F= '/^ALL_CLOSED=/ { v=$2 } END { print v }')
   if [ "$ALL_CLOSED" = "true" ]; then
       ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/finalize-umbrella.sh finalize --issue $UMBRELLA_NUMBER
   fi
   ```
   Best-effort: log to `Tool Failures` on failure. Skip to Step 8 cleanup.
- **Generic failure** (token absent): print `**⚠ 5: execute — /implement failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS comment and [IN PROGRESS] title prefix. (<elapsed>)**`. Skip to Step 8. The IN PROGRESS comment serves as an indicator that manual intervention is needed. Note: `/implement` Step 18 may have renamed the issue title to `[STALLED] ...` (managed lifecycle prefix); see Known Limitations "Title-prefix interaction on adopted-issue retry" for the recovery flow before re-running `/fix-issue` against the same issue.

### 5b — `INTENT=NON_PR` path (follow instructions inline)

**MANDATORY — READ ENTIRE FILE** before executing the NON_PR path: `${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/references/non-pr-execution.md`. Contains the common NON_PR patterns (research, code-review, other investigative/planning tasks), the `WORK_SUMMARY` running-summary discipline that becomes Step 6b's closing comment and Step 7b's Slack message, and the failure fallback. **Do NOT load** when `INTENT=PR` — Step 5a delegates to `/implement` and never consumes this file. **Do NOT load** in any step other than 5.

Read the issue details from Step 2 and execute the instructions directly using Read, Grep, Glob, and Bash. Do NOT call `/implement`. Do NOT modify files in the working tree — `NON_PR` tasks deliver their output as new GitHub issues, a written summary comment, or both.

> **Continue after child returns.** When any child Skill (`/issue`, `/research`, ...) returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Maintain a running `WORK_SUMMARY` per the reference — it becomes the closing comment in Step 6 and the Slack message in Step 7. Keep `PR_URL` and `PR_NUMBER` unset on this path.

If the work cannot be completed (e.g., `/issue` fails repeatedly, the issue's instructions are infeasible, or required external access is unavailable), print `**⚠ 5: execute — non-PR task failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS comment and [IN PROGRESS] title prefix. (<elapsed>)**` and skip to Step 8. The IN PROGRESS comment serves as an indicator that manual intervention is needed — same recovery semantics as the `/implement` failure path.

## Step 6 — Close Issue

Print `> **🔶 6: close issue**`

`issue-lifecycle.sh close` is **idempotent**: if the issue was auto-closed externally before Step 6 runs (e.g., GitHub's `Closes #<N>` PR-merge auto-close from a `/implement --merge` invocation), the call still succeeds cheaply — the DONE comment and `--pr-url` body backfill still run, only the `gh issue close` call is skipped. The stdout contract (`CLOSED=true` on success) is identical across the open and already-closed paths, so this step does not need to branch on whether the issue was already closed (stderr carries a diagnostic `INFO` or `WARNING` signal when relevant). See `skills/fix-issue/scripts/issue-lifecycle.md` for the full contract including probe-failure fallback and partial-success semantics.

Branch on `INTENT`.

### 6a — `INTENT=PR`

Update the issue body with the PR link and close with a DONE comment (single call):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --pr-url "$PR_URL" --comment "DONE"
```

The `[IN PROGRESS]` title prefix Step 0 applied at lock time has already been flipped to `[DONE]` by `/implement` Step 12a/12b on PR merge. No additional rename is needed here.

### 6b — `INTENT=NON_PR`

Close the issue with `WORK_SUMMARY` as the closing comment (no `--pr-url`, no body update):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/issue-lifecycle.sh close \
  --issue $ISSUE_NUMBER --comment "$WORK_SUMMARY"
```

**Best-effort terminal title rename** to clear the `[IN PROGRESS]` prefix Step 0 applied at lock time, replacing it with `[DONE]` so the closed issue's title accurately reflects that automated processing concluded:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/tracking-issue-write.sh rename \
  --issue $ISSUE_NUMBER --state done
```

Idempotent and best-effort: on `FAILED=true` or non-zero exit, log to `Tool Failures` and continue. Without this rename, a closed NON_PR issue would persist with the misleading `[IN PROGRESS]` title prefix until manually edited (because `/implement` Step 12a/12b/18 terminal renames only run on the PR delegation path).

### 6c — Umbrella finalize hook (both 6a and 6b)

After Step 6a / 6b completes (the just-processed child has been closed), if `$UMBRELLA_NUMBER` is set (Step 0 dispatched this child from an umbrella), check whether the umbrella is now empty and finalize if so:

```bash
PICK_OUT=$(${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/umbrella-handler.sh pick-child --issue $UMBRELLA_NUMBER 2>&1)
ALL_CLOSED=$(echo "$PICK_OUT" | awk -F= '/^ALL_CLOSED=/ { v=$2 } END { print v }')
if [ "$ALL_CLOSED" = "true" ]; then
    ${CLAUDE_PLUGIN_ROOT}/skills/fix-issue/scripts/finalize-umbrella.sh finalize --issue $UMBRELLA_NUMBER
fi
```

Best-effort: on `FAILED=true` / non-zero exit / `FINALIZED=false` non-idempotent error, log to `Tool Failures` and continue. The next `/fix-issue <umbrella#>` invocation will re-attempt finalization via the Step 0 exit-4 path. The `finalize-umbrella.sh` idempotency guard ensures concurrent or repeated invocations do not double-comment (FINDING_2). If `$UMBRELLA_NUMBER` is empty, this hook is a no-op.

Print `✅ 6: close issue — #$ISSUE_NUMBER closed (<elapsed>)` (mention umbrella-finalized when applicable: `✅ 6: close issue — #$ISSUE_NUMBER closed; umbrella #$UMBRELLA_NUMBER finalized (<elapsed>)`).

## Step 7 — Slack Announce (NON_PR path only)

The PR path's Slack announcement is handled by the child `/implement` at its Step 16a — this skill does NOT post again to avoid duplication. This step runs only for `INTENT=NON_PR`.

If `INTENT=PR`, print `⏭️ 7: slack announce — skipped (PR path — /implement posted at Step 16a) (<elapsed>)` and proceed to Step 8.

If `slack_enabled=false` (user passed `--no-slack`), print `⏭️ 7: slack announce — skipped (--no-slack) (<elapsed>)` and proceed to Step 8.

If `slack_available=false`, print `⏭️ 7: slack announce — skipped (Slack not configured) (<elapsed>)` and proceed to Step 8.

### 7b — `INTENT=NON_PR`

Post a Slack message summarizing the non-PR work via the shared script. Compose the `--detail` value from `WORK_SUMMARY` — a one-sentence summary is ideal (e.g., "research complete, filed #123 and #124" or "code review complete, filed 5 issues"):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/post-issue-slack.sh \
  --issue-number "$ISSUE_NUMBER" --status closed --repo "$REPO" \
  --token "${LARCH_SLACK_BOT_TOKEN:-$CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN}" \
  --channel-id "${LARCH_SLACK_CHANNEL_ID:-$CLAUDE_PLUGIN_OPTION_SLACK_CHANNEL_ID}" \
  --detail "<one-sentence summary from WORK_SUMMARY>"
```

If the script exits non-zero, print `**⚠ 7: slack announce — failed. Continuing.**` and log to `Tool Failures`.

Print `✅ 7: slack announce — posted (<elapsed>)`

## Step 8 — Cleanup

**This step ALWAYS runs**, regardless of the outcome of prior steps (success, failure, early exit, or abort). "Always runs" is a control-flow guarantee — the cleanup-tmpdir.sh invocation itself is gated on `FIX_ISSUE_TMPDIR` being set, since Step 0 find-and-lock may short-circuit before Step 1 setup creates the tmpdir.

If `FIX_ISSUE_TMPDIR` is set and non-empty:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$FIX_ISSUE_TMPDIR"
```

Otherwise (Step 0 exited 1 / 2 / 3 — i.e., no eligible issue, error, or lock-failed-after-eligibility-pass — or Step 1 setup failed before mktemp), print `⏭️ 8: cleanup — skipped (no temp dir created) (<elapsed>)`. (`cleanup-tmpdir.sh` rejects empty `--dir` with exit 1 as a backstop, so the guard is defense in depth, not the only line.)

Then unconditionally print `✅ 8: cleanup — fix-issue complete! (<elapsed>)`

## Known Limitations

- **Stale IN PROGRESS lock**: Step 0 deletes the `GO` comment and posts `IN PROGRESS` (so the `GO` sentinel no longer remains after locking) and prepends `[IN PROGRESS]` to the title. If the skill crashes after Step 0 completes, the issue's last comment is `IN PROGRESS` AND the title carries the `[IN PROGRESS]` prefix — recovery: manually delete the `IN PROGRESS` comment, strip the title prefix (`gh issue edit <N> --title "<user-title>"`), and re-add `GO`. If it crashes mid-Step-0 (between deleting `GO` and posting `IN PROGRESS`), the issue has no comment sentinel — recovery: manually re-add `GO`. If it crashes between the `IN PROGRESS` post and the title rename (or if the rename failed best-effort, signaled by `RENAMED=false` on `find-lock-issue.sh`'s stdout), the comment lock is in place but the title is unchanged — `/implement` Step 0.5 Branch 2's idempotent rename will recover this on the next run-segment, but a crashed run leaves the issue with the `IN PROGRESS` comment and original title; recovery: manually delete the `IN PROGRESS` comment and re-add `GO`.
- **Lock-before-setup behavioral delta**: under the `find-and-lock → setup` ordering, Step 1 setup failures leave the issue locked with `IN PROGRESS` (comment + title prefix) and require the same manual recovery as any post-lock failure. Two representative failure modes: (a) a transient `git fetch origin main` failure inside `preflight.sh` (run by `session-setup.sh` before mktemp) — network-bound and the more likely transient cause; (b) `REPO_UNAVAILABLE=true` after `gh repo view` and the `git remote get-url` fallback both fail to yield an `owner/repo` — non-network. The earlier `fetch → setup → lock` ordering (pre-PR #468) would have aborted before posting `IN PROGRESS` on the same setup failure, leaving the `GO` sentinel intact. The trade narrows the candidate-selection-to-lock-acquisition TOCTOU window in exchange for occasional manual `IN PROGRESS` clearance after a setup-stage abort. The design panel for the related reorder (PR #468) considered splitting `session-setup.sh` into a pre-lock preflight phase and a post-lock setup phase as a heavier mitigation; the panel exonerated the concern (3 EXONERATE) judging the split heavier than the reorder warranted, so the documented failure mode is the accepted trade-off rather than a deferred bug.
- **Single-runner assumption**: The comment-based locking (Step 0) includes duplicate detection but is not fully atomic. For reliable operation, run one instance of `/fix-issue` at a time per repository.
- **Dependency check degrades silently on API failure**: The blocked-by check (Step 0) treats unreachable or erroring dependency-API responses as "no blockers known" to avoid hard-blocking the automation. If GitHub's issue-dependencies endpoint is returning 5xx or an unexpected payload, a blocked issue could temporarily be eligible. The GO sentinel still applies, so the blast radius is limited to whatever the reviewer intended to allow via `GO`.
- **Brief no-GO window during /issue dep-wiring (issue #546)**: when `/issue --go` creates an issue with one or more blocker dependencies (always-on), the GO comment is posted only AFTER all of `add-blocked-by.sh`'s dependency POSTs succeed for that issue. An issue may briefly exist on GitHub without a GO comment during the wiring window (typically <1s; up to ~40s if both retry sleeps fire). `/fix-issue` will not pick up such an issue until /issue completes the GO post — there is no race condition because `/fix-issue` requires `GO` as the last comment, which `/issue` only posts after dep wiring. See `skills/issue/SKILL.md` `## Dependency Analysis` for the contract on the producing side.
- **Prose-dependency check shares the same fail-open posture**: A parser regression, body/comment fetch failure, or per-reference state lookup failure all degrade to "no prose blockers known" for that candidate. The offline harness (`test-parse-prose-blockers.sh`, run via `make lint`) is the primary guard against parser regressions.
- **Prose-dep check uses a strict keyword grammar**: The five recognized phrases (`Depends on`, `Blocked by`, `Blocked on`, `Requires`, `Needs`) must be immediately followed by whitespace + `#<digits>`. Typos like `Depends on#150` (no space), cross-repo references (`owner/repo#150`), URL forms (`https://github.com/…/150`), and bare `#150` mentions are deliberately NOT matched. Emphasis wrappers (`**#150**`, `_#150_`) ARE matched. Link-target wrappers (`[#150](url)`) are NOT matched, so link targets can never smuggle cross-repo references through the parser.
- **Short-circuit when native blockers exist — user-visible messages may omit prose blockers**: When an issue has BOTH native and prose open blockers, the prose path is short-circuited for rate-limit efficiency. The skip/error message will list only the native blocker numbers. Closing all listed native blockers and re-running `/fix-issue` will surface any remaining prose blockers on the next run.
- **External close while `/fix-issue` holds IN PROGRESS**: `/implement`'s Step 0.5 detects a closed adopted issue and bails with `IMPLEMENT_BAIL_REASON=adopted-issue-closed`; `/fix-issue` Step 5a reports the condition but does not unlock, since a closed issue cannot be re-locked. Recovery: re-open the issue manually and re-trigger via a new `GO` comment.
- **Title-rename failure on Step 0 is non-fatal but visible**: when `find-lock-issue.sh`'s best-effort `tracking-issue-write.sh rename --state in-progress` call fails (transient `gh` API failure, rate limiting, etc.), the script emits `LOCK_ACQUIRED=true RENAMED=false` and continues; SKILL.md Step 0 logs a warning. The comment lock is still held, and `/implement` Step 0.5 Branch 2's idempotent rename re-attempts the title rename when the PR path runs. On the not-material (Step 3) and NON_PR (Step 5b → Step 6b) close paths, the title rename failure means the issue closes with the original (un-prefixed) title — operationally fine.
- **Bail-token detection depends on output preservation**: the adopted-issue-closed branch in Step 5a scans the captured `/implement` output for the exact literal `IMPLEMENT_BAIL_REASON=adopted-issue-closed`. If the runtime summarizes the child skill's output and the literal token is lost, Step 5a falls through to the generic-failure branch and prints the "remains locked with IN PROGRESS" message — misleading for an externally-closed issue, but operator recovery is identical (re-open, re-add `GO`). The harness at `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` guards against accidental removal of the token literal from this SKILL.md, but cannot guarantee runtime preservation of the token.
- **Title-prefix interaction on adopted-issue retry**: Step 0's `find-lock-issue.sh` applies `[IN PROGRESS]` immediately on lock; `/implement` Step 0.5 Branch 2's idempotent rename hits a `RENAMED=false` no-op on this path. On `--merge` success `/implement` Step 12a/12b flips the title to `[DONE]`; on Step 18 stall it flips to `[STALLED]`. The eligibility filter (`find-lock-issue.sh`) rejects ANY title starting with a managed lifecycle prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`) in both auto-pick and explicit `/fix-issue <N>` modes — so after a generic `/implement` failure the issue is left at `[STALLED] <user title>` and is no longer pickable by `/fix-issue` until the prefix is cleared. Recovery: (1) delete the `IN PROGRESS` comment, (2) clear the title prefix using `gh issue edit <N> --title "<original-title>"` (or run `${CLAUDE_PLUGIN_ROOT}/scripts/tracking-issue-write.sh rename --issue <N> --state in-progress` and then manually drop the prefix), and (3) re-add a `GO` comment. This is the documented manual flow until `/fix-issue` learns to accept `[STALLED]`-prefixed titles in explicit-retry mode.

- **Umbrella support is explicit-target-only**: `/fix-issue <umbrella#>` accepts an umbrella issue and dispatches to the next eligible child. The auto-pick scan (no-arg `/fix-issue`) NEVER selects umbrellas — operators must explicitly target the umbrella, by design (umbrella-PR DECISION_1, voted 2-1). The umbrella body literal `Umbrella tracking issue.` is the primary detection signal; the title prefix `Umbrella:` / `Umbrella —` is a fallback for hand-authored umbrellas. Children are dispatched without their own `GO` comment — they inherit approval from the umbrella's existence. To run umbrella-tracked work to completion, invoke `/fix-issue <umbrella#>` once per child you want processed; the umbrella finalizes automatically (rename to `[DONE]`, post closing comment, close) when its last open child closes (Steps 0, 3, 5a, 6 all carry the finalization hook).

- **Umbrella child enumeration is task-list-only**: `umbrella-handler.sh` parses children from the umbrella body using a markdown task-list regex (`- [ ] #N` or `- [x] #N`, with leading whitespace allowed; see `skills/fix-issue/scripts/umbrella-handler.md` for the full grammar). This catches `/umbrella`-rendered children (`- [ ] #N — title`) and hand-authored operator checklists (`- [ ] /fix-issue executes #N` as in #348). It does NOT match table-format umbrellas (e.g., `| #N | … |` rows) or prose `#N` references. Cross-repo references (`owner/repo#N`) are deliberately filtered out at parse time. Umbrella authors who use a table or free-form prose for their children list must add a parallel `- [ ]` checklist (or migrate to `/umbrella` rendering) to be machine-parseable.

- **Umbrella with zero parseable children does NOT auto-close**: if `/fix-issue <umbrella#>` is invoked on an issue that satisfies the umbrella detection signal (body literal or title prefix) but has zero parseable task-list child references, `find-lock-issue.sh` exits 5 with `Umbrella #N has no eligible child: no parseable children found in umbrella body` — the umbrella is NOT destructively renamed/closed. This is FINDING_3 from the umbrella-PR plan review: vacuous-truth `ALL_CLOSED` would otherwise let any open issue accidentally matching the detection signal be irreversibly closed.

- **Umbrella concurrent finalize is comment-idempotent**: when two `/fix-issue` runners reach the umbrella-finalization hook simultaneously (e.g., both close their respective last-children at the same time), `finalize-umbrella.sh`'s pre-finalization guard probes the umbrella's state, title prefix, and existing comment marker (`<!-- larch:fix-issue:umbrella-finalized -->` embedded in the closing comment body) and branches on three cases consistent with `skills/fix-issue/scripts/finalize-umbrella.md` Idempotency-guard section: (a) **state=CLOSED** is the only strict short-circuit — emits `FINALIZED=false ALREADY_FINALIZED=true REASON=already CLOSED` and exits 0 with no further mutation; (b) **state=OPEN with `[DONE]` title prefix** is a partial-success signal (prior rename succeeded, prior `gh issue close` did not) — skip the rename API call, drive a close-only retry, emit `FINALIZED=true CLOSED=true RENAMED=false`; (c) **state=OPEN with the marker comment present** is a partial-success signal (prior comment-post succeeded) — skip the comment-post step (avoid double-comment under concurrency), drive a close-only retry via `issue-lifecycle.sh close --issue N` (no `--comment`), emit `FINALIZED=true CLOSED=true RENAMED=<bool>`. Cases (b) and (c) are independent and may co-occur (rename + comment both done from a prior attempt); in either OPEN case the close call still runs to drive the umbrella to CLOSED, otherwise every retry would loop on `ALREADY_FINALIZED=true` and the umbrella would stay OPEN forever (FINDING_3). If both runners race the marker probe and both proceed past the guard, the second runner's `issue-lifecycle.sh close` call is idempotent on `state == CLOSED` and skips the `gh issue close` itself, but the comment is posted-before-probe in `cmd_close` — so a strict double-comment requires both runners to clear the marker probe before either has posted the comment. With `gh issue comment` taking ~200-500ms in practice, the window is small but not zero; operators noticing duplicate comments on the umbrella can manually delete one.

- **Umbrella's own blockers gate dispatch**: when `/fix-issue <umbrella#>` is invoked on an umbrella that itself has open native or prose blockers, the existing `all_open_blockers` check in `find-lock-issue.sh` runs against the umbrella (parallel to the non-umbrella explicit-issue path) and exits 2 before umbrella detection runs. The error message names the umbrella's blockers, not the children's blockers. Children's blockers are checked separately in the umbrella dispatch path (after `pick-child` returns a `CHILD_NUMBER` and before the child lock attempt).
