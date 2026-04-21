# PR Body Template

**Consumer**: `/implement` Step 9a — PR body composition. Also consumed by the Rebase + Re-bump Sub-procedure step 6 for the Version Bump Reasoning block refresh.

**Contract**: Byte-preserving extraction of the PR body markdown scaffold from `skills/implement/SKILL.md` L580–681 plus Voting Tally extraction guidance (L683–685) and Quick-mode PR body guidance (L687–699). Section headers and `<details><summary>` block structure must NOT drift — they are parsed by the Rebase + Re-bump Sub-procedure step 6's `<details><summary>Version Bump Reasoning</summary>` marker search and by Step 11's `<details><summary>Execution Issues</summary>` marker search. Blank lines immediately after opening `<summary>` tags and before closing `</details>` tags are load-bearing for GitHub Markdown rendering.

**When to load**: before writing `$IMPLEMENT_TMPDIR/pr-body.md` in Step 9a, and before the Rebase + Re-bump Sub-procedure step 6 PR body refresh. Do NOT load in any other step.

---

## PR Body Template (from SKILL.md L580–681)

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

## Voting Tally extraction guidance (from SKILL.md L683–685)

Populate Run Statistics from conversation context: count accepted/rejected findings from /design Step 3 output, count review rounds and findings from /review output, count entries in `execution-issues.md` by category, and note external reviewer availability from /design and /review preflight checks. Note: Run Statistics aggregates (N accepted, N rejected) intentionally coexist with the detailed per-finding tally tables in the voting tally sections — they serve different purposes (quick summary vs. full audit trail).

**Voting tally extraction guidance**: For the Plan Review Voting Tally, extract the per-finding vote breakdown and Reviewer Competition Scoreboard printed during `/design` Step 3's voting output. The vote breakdown may be a table or a list — extract whatever format was printed. The Reviewer Competition Scoreboard follows the format defined in `voting-protocol.md`. For the Code Review Voting Tally, extract the per-finding vote breakdown from `/review` Step 3d (the round 1 summary output) and the Reviewer Competition Scoreboard from `/review` Step 4 (Final Summary). Step 3d prints the per-finding details; Step 4 prints the consolidated scoreboard.

---

## Quick-mode PR body guidance (from SKILL.md L687–699)

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
