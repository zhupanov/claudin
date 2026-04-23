# PR Body Template

**Consumer**: `/implement` Step 9a (PR body composition), Step 9a.1 (OOS GitHub issue creation pipeline), Step 11 (post-execution PR body refresh), and the Rebase + Re-bump Sub-procedure step 6 (Version Bump Reasoning block refresh).

**Contract**: Authoritative source for the PR body markdown scaffold, Voting Tally extraction guidance, Quick-mode PR body guidance, the Step 9a.1 OOS issue-creation pipeline, and the Step 11 post-execution PR body refresh. Section headers and `<details><summary>` block structure must NOT drift — they are parsed by the sub-procedure step 6's `<details><summary>Version Bump Reasoning</summary>` marker search and by Step 11's `<details><summary>Execution Issues</summary>` marker search. Blank lines immediately after opening `<summary>` tags and before closing `</details>` tags are load-bearing for GitHub Markdown rendering.

**When to load**: before writing `$IMPLEMENT_TMPDIR/pr-body.md` in Step 9a; at Step 9a.1 entry (OOS pipeline); at Step 11's post-execution PR body refresh; at sub-procedure step 6 (Version Bump Reasoning refresh). Do NOT load in any other step.

---

## PR Body Template

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

<content of $BUMP_REASONING_FILE (the path captured from classify-bump.sh's REASONING_FILE=<path> output in Step 8) if it exists and is non-empty, otherwise "No version bump reasoning available (skill may have skipped via BUMP_TYPE=NONE, or /bump-version was not invoked).">

</details>

<details><summary>Rejected Plan Review Suggestions</summary>

<rejected plan review findings from the /design phase's Step 4 output visible in conversation context above. If none were rejected, write "All plan review suggestions were implemented." If /design was interrupted and these findings are not visible in context, omit this entire <details> block.>

</details>

<details><summary>Implementation Deviations</summary>

<compare the plan to what was actually implemented. List any deviations, or write "No deviations from the plan." If no plan exists, write "Design phase did not complete — no plan to compare against." If any item here is durable, actionable follow-up work, file an issue per the Follow-up Work Principle in skills/implement/SKILL.md and reference the issue number here instead of leaving it only as prose.>

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

**Accepted OOS (GitHub issues filed):**
<If Step 9a.1 created issues, list each with its issue link: "- #<NUMBER>: <title> (<reviewer attribution>)". Reviewer attribution may be `Code`, `Cursor`, `Codex`, or `Main agent` — the latter for items sourced from the dual-write to oos-accepted-main-agent.md per the Execution Issues Tracking → Mandatory dual-write rule. If no OOS items were accepted, write "No OOS items were accepted for issue filing.">

**Non-accepted OOS observations:**
<Non-accepted out-of-scope observations from both plan review (/design Step 3) and code review (/review Step 3c.1) visible in conversation context above. These are pre-existing issues or concerns beyond the PR's scope that reviewers surfaced for future attention. Copy the non-accepted OOS items as they were listed, including the reviewer attribution and description. If no OOS observations were raised, write "No out-of-scope observations were raised." If the observations are not visible in conversation context, write "Out-of-scope observations not available.">

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
| OOS issues filed | <N> |
| External reviewers | Cursor: <✅/❌>, Codex: <✅/❌> |

</details>

Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Voting Tally extraction guidance

Populate Run Statistics from conversation context: count accepted/rejected findings from /design Step 3 output, count review rounds and findings from /review output, count entries in `execution-issues.md` by category, and note external reviewer availability from /design and /review preflight checks. Note: Run Statistics aggregates (N accepted, N rejected) intentionally coexist with the detailed per-finding tally tables in the voting tally sections — they serve different purposes (quick summary vs. full audit trail).

**Voting tally extraction guidance**: For the Plan Review Voting Tally, extract the per-finding vote breakdown and Reviewer Competition Scoreboard printed during `/design` Step 3's voting output. The vote breakdown may be a table or a list — extract whatever format was printed. The Reviewer Competition Scoreboard follows the format defined in `voting-protocol.md`. For the Code Review Voting Tally, extract the per-finding vote breakdown from `/review` Step 3d (the round 1 summary output) and the Reviewer Competition Scoreboard from `/review` Step 4 (Final Summary). Step 3d prints the per-finding details; Step 4 prints the consolidated scoreboard.

---

## Quick-mode PR body guidance

**Quick-mode PR body guidance** (`quick_mode=true`): When populating the PR body in quick mode, use these section-specific rules:
- **Architecture Diagram**: Write "Quick mode — architecture diagram skipped."
- **Code Flow Diagram**: Write "Quick mode — code flow diagram skipped."
- **Final Design**: Use the inline implementation plan produced in Step 1 (not from `/design`).
- **Version Bump Reasoning**: Populate from `$BUMP_REASONING_FILE` (the absolute path parsed from `classify-bump.sh`'s `REASONING_FILE=<path>` stdout line in Step 8, identical to normal mode) if it exists and is non-empty, otherwise the standard fallback text from the normal-mode template.
- **Rejected Plan Review Suggestions**: Write "Quick mode — no plan review was conducted."
- **Plan Review Voting Tally**: Write "Quick mode — no plan review voting."
- **Code Review Voting Tally (Round 1)**: Write "Quick mode — no voting panel. Main agent reviewed findings across up to 7 single-reviewer rounds (Cursor → Codex → Claude fallback chain)."
- **Implementation Deviations**: Compare implementation to the inline plan (same as normal mode).
- **Out-of-Scope Observations**:
  - **Accepted OOS (GitHub issues filed)**: Populate from Step 9a.1's main-agent-surfaced items in `oos-accepted-main-agent.md`. If Step 9a.1 filed no issues (no main-agent OOS findings), write "No OOS items were accepted for issue filing."
  - **Non-accepted OOS observations**: Write "Quick mode — no reviewer voting panel. Main-agent OOS items (if any) are auto-filed per policy; see Accepted OOS above."
- **Run Statistics**: Set "Plan review findings" to "N/A (quick mode)", "External reviewers" to "N/A (quick mode)". For "OOS issues filed", do NOT hardcode `N/A (quick mode)` — Step 9a.1 runs in quick mode now and writes the actual count to this cell per its sub-step 7b. The cell will be `<N> created, <M> deduplicated`, `0`, or `N/A (repo unavailable)` depending on the Step 9a.1 outcome. Code review findings should reflect the quick review results.

---

## Step 9a.1 OOS GitHub Issue Creation Pipeline

**Unconditional execution** regardless of mode (`--quick`, `--auto`, `--merge`, `--debug`, `--no-merge`, or any future flag). The only legitimate hard-skip is `repo_unavailable=true`.

**Repo-unavailable early-exit**: If `repo_unavailable=true`, print `⏩ 9a.1: OOS issues — skipped (repo unavailable) (<elapsed>)`. Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Warnings`. Update `$IMPLEMENT_TMPDIR/pr-body.md`: replace the "Accepted OOS (GitHub issues filed)" placeholder with `Skipped — repo unavailable; OOS items remain in execution-issues.md only.` and set the `| OOS issues filed |` Run Statistics cell to `N/A (repo unavailable)`. Proceed to Step 9b.

**Read OOS artifacts**:
- `$IMPLEMENT_TMPDIR/oos-accepted-design.md` (from `/design` plan review)
- `$IMPLEMENT_TMPDIR/oos-accepted-review.md` (from `/review` code review)
- `$IMPLEMENT_TMPDIR/oos-accepted-main-agent.md` (from main-agent dual-write per SKILL.md's Execution Issues Tracking section)

**All-empty early-exit**: If none of the three artifacts exist or all are empty, print `⏩ 9a.1: OOS issues — no accepted OOS items (<elapsed>)`. Update `$IMPLEMENT_TMPDIR/pr-body.md`: replace the "Accepted OOS (GitHub issues filed)" placeholder with `No OOS items were accepted for issue filing.` and set the `| OOS issues filed |` Run Statistics cell to `0`. Proceed to Step 9b.

**Idempotency**: If `$IMPLEMENT_TMPDIR/oos-issues-created.md` already exists (written by a previous Step 9a.1 in this session), skip issue creation entirely. Read the existing file to recover previously created issue URLs (`ISSUE_N_NUMBER` / `ISSUE_N_URL` / `ISSUE_N_TITLE` / `ISSUE_N_DUPLICATE*` lines) and the previous tally (`ISSUES_CREATED` / `ISSUES_FAILED` / `ISSUES_DEDUPLICATED`). Update `$IMPLEMENT_TMPDIR/pr-body.md` from recovered values exactly as the create-script branch (steps 7 and 7b below) would: replace the "Accepted OOS" placeholder with the recovered issue links and set the `| OOS issues filed |` Run Statistics cell from the recovered counts. Proceed to Step 9b. (This is Load-Bearing Invariant #2 — sentinel-based byte-exact idempotency guard.)

**Create-script branch** (at least one artifact has content; no idempotency sentinel):

1. Read and parse all accepted OOS items from all three files.
2. **Cross-phase deduplication**: if the same pre-existing issue was surfaced and accepted in two or more of {design, review, implement} (matching by exact normalized title — case-insensitive, `[oos]`-prefix-stripped, whitespace-collapsed), keep one entry whose Description text notes the contributing phases (append e.g., " (also surfaced during design review)"). Do NOT modify schema fields — Reviewer and Phase remain single-valued; merged provenance lives in the Description prose. This cross-phase merge runs **before** calling `/issue` so the batch mode sees one canonical item per observation.
3. Write the deduplicated items to `$IMPLEMENT_TMPDIR/oos-items.md` as input for `/issue` batch mode. Preserve the OOS markdown format — `/issue`'s parser reads it directly.
4. Invoke `/issue` in batch mode via the Skill tool:
   - `skill: "issue"`, `args: --input-file $IMPLEMENT_TMPDIR/oos-items.md --title-prefix "[OOS]" --label out-of-scope --repo $REPO`
5. Parse `/issue`'s stdout for lines matching `^(ISSUES?_[A-Z0-9_]+)=(.*)$`: `ISSUES_CREATED`, `ISSUES_FAILED`, `ISSUES_DEDUPLICATED`, and per-issue `ISSUE_N_NUMBER` / `ISSUE_N_URL` / `ISSUE_N_TITLE` / `ISSUE_N_DUPLICATE` / `ISSUE_N_DUPLICATE_OF_NUMBER` / `ISSUE_N_DUPLICATE_OF_URL` / `ISSUE_N_FAILED=true`. `/issue` writes only machine lines to stdout; warnings go to stderr.
6. If `ISSUES_FAILED > 0`: log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Tool Failures`: `Step 9a.1 — /issue batch mode failed to create <N> of <total> OOS issues.`
7. Update `$IMPLEMENT_TMPDIR/pr-body.md`: replace the "Accepted OOS (GitHub issues filed)" placeholder with the actual issue links. For deduplicated items, link to the existing issue: `"- #<EXISTING_NUMBER>: <title> (deduplicated — already tracked) (<reviewer attribution>)"`. Reviewer attribution (`Code` / `Cursor` / `Codex` / `Main agent`) comes from the contributing artifact's `Reviewer:` field.
7b. **Rewrite Run Statistics `| OOS issues filed |` cell** to `<ISSUES_CREATED> created, <ISSUES_DEDUPLICATED> deduplicated` (e.g., `3 created, 1 deduplicated`). The early-exit branches above already update this cell themselves; step 7b handles only the create-script branch. This applies to both quick and normal mode — the Quick-mode PR body guidance no longer overrides this cell.
8. Write the created issue metadata to `$IMPLEMENT_TMPDIR/oos-issues-created.md` as the idempotency sentinel. Include `ISSUES_CREATED`, `ISSUES_FAILED`, `ISSUES_DEDUPLICATED`, and all `ISSUE_N_NUMBER` / `ISSUE_N_URL` / `ISSUE_N_TITLE` / `ISSUE_N_DUPLICATE*` lines from the script output.

Print: `✅ 9a.1: OOS issues — <ISSUES_CREATED> created, <ISSUES_DEDUPLICATED> deduplicated (<elapsed>)`

---

## Step 11 Post-execution PR body refresh

Runs unconditionally after all Step 11 branches converge — including when Slack was skipped (`slack_enabled=false` or `slack_available=false`) or when `PR_STATUS=existing`. All Step 11 early-exit paths must reach this section before proceeding to Step 12.

If `$IMPLEMENT_TMPDIR/execution-issues.md` exists and is non-empty, update the PR body to reflect the final execution issues (may include issues logged during Steps 10–11, after the initial PR body was written):

1. Fetch the current live PR body (do NOT re-read `$IMPLEMENT_TMPDIR/pr-body.md` — the live body may differ from the local copy):
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md` to get the current body text.
2. Replace the entire inner content of the `<details><summary>Execution Issues</summary>...</details>` block with the full current contents of `$IMPLEMENT_TMPDIR/execution-issues.md`, preserving the blank lines after the opening tag and before the closing `</details>` (required for GitHub Markdown rendering). If the `<details><summary>Execution Issues</summary>` block is not found in the fetched body, print `**⚠ Execution Issues block not found in live PR body. Skipping refresh.**` and skip the update.
3. Write the result to `$IMPLEMENT_TMPDIR/pr-body.md`.
4. Update the PR:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```

If `execution-issues.md` does not exist or is empty, skip this refresh.
