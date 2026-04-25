# NON_PR Path — Inline Execution

**Consumer**: `/fix-issue` Step 5b (`INTENT=NON_PR` path — follow instructions inline).

**Contract**: Authoritative detail for the NON_PR execution path — what `NON_PR` tasks deliver, which child skills to invoke (`/research`, `/issue`), the no-working-tree-edits rule, the `WORK_SUMMARY` running-summary discipline that becomes Step 6b's closing comment and Step 7b's Slack message, and the per-failure fallback. SKILL.md Step 5b carries the control-flow shell (the branch on `INTENT`, the `Do NOT call /implement` / `Do NOT modify files in the working tree` top-level invariants, the anti-halt continuation reminder for child-skill returns, and the failure-path breadcrumb that skips to Step 8); this file carries the per-pattern detail.

**When to load**: only when Step 4's classifier sets `INTENT=NON_PR`. **Do NOT load** when `INTENT=PR` — Step 5a delegates to `/implement` and never references this file. **Do NOT load** in any step other than 5.

**Sibling**: `skills/fix-issue/references/triage-classification.md` owns the triage (Step 3) and classification (Step 4) detail that produces the `INTENT` value this file gates on.

---

## Step 5b — NON_PR execution detail

Read the issue details from Step 2 and execute the instructions directly using Read, Grep, Glob, and Bash. Do NOT call `/implement`. Do NOT modify files in the working tree — `NON_PR` tasks deliver their output as new GitHub issues, a written summary comment, or both.

### Common NON_PR patterns

- **Research task** — investigate the requested topic in-codebase via Read/Grep/Glob; when the scope warrants a collaborative read-only research panel, invoke `/research` via the Skill tool. Create one or more summary issues via `/issue` (invoked via the Skill tool) if the issue body requests it.
- **Code-review task** — examine the requested area and file one issue per problem found. Invoke `/issue` via the Skill tool in batch mode (`--input-file` with a markdown file listing the findings) to file all findings in a single pass with semantic duplicate detection. Write the `--input-file` markdown to a path under `$FIX_ISSUE_TMPDIR` (never inside the repository working tree) so the "no working-tree edits" rule above holds.
- **Other investigative or planning tasks** — follow the body's instructions literally; when ambiguous, prefer the interpretation that produces actionable output (issues, documented findings) over the interpretation that produces code changes.

### WORK_SUMMARY running discipline

As work proceeds, maintain a running `WORK_SUMMARY` — a concise markdown summary of what was done and the output artifacts (links to any issues created, key findings, etc.). This summary becomes the closing comment in Step 6b and the one-sentence Slack message in Step 7b. Keep `PR_URL` and `PR_NUMBER` unset on this path.

### Failure fallback

If the work cannot be completed (e.g., `/issue` fails repeatedly, the issue's instructions are infeasible, or required external access is unavailable), SKILL.md Step 5b prints the NON_PR-failure breadcrumb (`**⚠ 5: execute — non-PR task failed. Issue #$ISSUE_NUMBER remains locked with IN PROGRESS comment and [IN PROGRESS] title prefix. (<elapsed>)**`) and skips to Step 8. The `IN PROGRESS` comment serves as an indicator that manual intervention is needed — same recovery semantics as the `/implement` failure path in Step 5a.
