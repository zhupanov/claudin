---
name: combine-issues
description: "Use when asked to try to combine existing issue to reduce issue count.  Examine all open issues that are not currently being worked on, and see if any number of them can be combined into one issue (closing the source issues afterwords), in order to save tokens / reduce the number of tasks to do.  Good candidated would be issues that either work in the same code area, or that apply very similar changes to different code areas, but think of other criteria that it would be appropriate as well.  Again, the primary goal is to reduce the tokens spent on executing unnecessarily fine-grained tasks."
argument-hint: "[--dry-run]"
allowed-tools: Bash, Read, Write
---

# Combine Issues

Reduce open issue count by merging related issues into combined ones. The primary goal is saving tokens — fewer, broader issues mean fewer `/fix-issue` invocations and less duplicated context loading.

## When to Combine

Good candidates share at least one of:

- **Same code area** — multiple issues touching the same file(s) or module.
- **Similar change pattern** — issues applying analogous edits to different files (e.g., "add error handling to script A" + "add error handling to script B").
- **Overlapping scope** — one issue is a subset of another, or both contribute to the same goal.
- **Sequential dependency** — issues that must land in order and are small enough to ship as one unit.

Do NOT combine issues that are genuinely independent and benefit from separate review (e.g., a bug fix and an unrelated feature).

## Step 1 — Fetch Eligible Issues

```bash
$PWD/.claude/skills/combine-issues/scripts/fetch-combinable-issues.sh
```

Parse `ISSUES_FILE` and `COUNT` from stdout. If `COUNT=0`, print `No open issues eligible for combination.` and stop.

Read the JSON file at `$ISSUES_FILE` to get the full issue list (number, title, body, labels).

## Step 2 — Analyze and Propose Groups

Read each issue's title and body. Identify groups of 2+ issues that meet the combination criteria above. For each proposed group:

1. List the source issue numbers and titles.
2. State the combination rationale (which criterion from "When to Combine" applies).
3. Draft a combined title and a combined body that preserves all actionable content from the source issues.

Present all proposed groups to the user in a numbered list. If no groups are identified, print `No combination candidates found among <COUNT> open issues.` and stop.

Ask the user which groups to apply (e.g., "all", "1,3", or "none").

## Step 3 — Apply Approved Combinations

For each approved group, write the combined body to a temp file, then invoke:

```bash
$PWD/.claude/skills/combine-issues/scripts/apply-combination.sh \
  --title "<combined title>" \
  --body-file "<temp-file>" \
  --source-issues "<comma-separated issue numbers>"
```

Parse `COMBINED_ISSUE` and `CLOSED_ISSUES` from stdout. Print a summary line per group: `Combined #X, #Y, #Z → #<new> (<N> issues closed)`.

After all groups are applied, print a final tally: `Done — <N> issues combined into <M>, net reduction: <N-M>`.

## Anti-patterns

- **NEVER combine issues without user confirmation.** The analysis is advisory; the user decides which groups to merge. Combining the wrong issues loses important context that is hard to recover.
- **NEVER combine an issue that has an `[IN PROGRESS]`, `[STALLED]`, or `[DONE]` title prefix.** The fetch script filters these out, but if one slips through (e.g., prefix applied after fetch), skip it and warn.
- **NEVER discard actionable content from source issues.** The combined body must preserve every concrete task, file reference, and reproduction step from the originals. Summarizing away specifics defeats the purpose.
