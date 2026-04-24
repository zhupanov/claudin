# PR Body Template

**Consumer**: `/implement` Step 9a (PR body composition).

**Contract**: Authoritative source for the slim PR body markdown scaffold on a Phase 3+ tracked run. Section headers must NOT drift — downstream tooling treats `Closes #<N>` as the PR-to-tracking-issue linkage. The anchor comment on the tracking issue owns all rich report content (voting tallies, OOS pipeline output, execution issues, run statistics, version bump reasoning); this template owns only the slim PR projection. Blank lines immediately after opening `<summary>` tags and before closing `</details>` tags are load-bearing for GitHub Markdown rendering.

**When to load**: before writing `$IMPLEMENT_TMPDIR/pr-body.md` in Step 9a. Do NOT load in any other step.

**Sibling**: `skills/implement/references/anchor-comment-template.md` owns the canonical anchor body that carries voting tallies, diagrams, version bump reasoning, OOS list, execution issues, and run statistics.

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

<details><summary>Test plan</summary>

<bulleted checklist of testing steps>

</details>

Closes #<TRACKING_ISSUE_NUMBER>

Generated with [Claude Code](https://claude.com/claude-code)
```

---

## Composition notes

- `<TRACKING_ISSUE_NUMBER>` is `$ISSUE_NUMBER` from Step 0.5 — set on all four branches when the path succeeds (Branch 1 sentinel reuse, Branch 2 `--issue` adoption, Branch 3 PR-body recovery, Branch 4 immediate first-remote-write). On degraded runs (`repo_unavailable=true` OR Step 0.5 Branch 4 create-issue/anchor/sentinel failure set `deferred=true` with `$ISSUE_NUMBER` unset), Step 9a substitutes `(no tracking issue created)` and the auto-close link is absent.
- The `Closes #<N>` line is load-bearing for three consumers: (1) GitHub's auto-close-on-merge behavior (closes the tracking issue when the PR merges); (2) Step 0.5 Branch 3 (PR-body-recovery) uses the FIRST `Closes #<N>` match on an existing PR body to adopt the same tracking issue on a subsequent session; (3) `/fix-issue`'s Phase 2 close idempotency relies on this auto-close to transition the tracking issue cleanly.
- Rich report content (voting tallies, diagrams, execution issues, OOS list, run statistics, version bump reasoning) is written to the anchor comment via `tracking-issue-write.sh upsert-anchor`, not to this PR body. See `skills/implement/references/anchor-comment-template.md` for the anchor's canonical template and section markers.
