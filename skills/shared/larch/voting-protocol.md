# Voting Protocol

Shared voting protocol for adjudicating review findings. Used by `/design` (plan review) and `/review` (code review). This protocol **replaces** the Negotiation Protocol for `/design` and `/review`. `/loop-review` and `/research` continue using the Negotiation Protocol in `external-reviewers.md`.

## Overview

After reviewers submit findings and findings are deduplicated, a 3-agent voting panel votes YES/NO/EXONERATE on each finding. Findings with 2+ YES votes are accepted; others are not implemented. Original reviewers earn competition points based on how their findings perform in voting. EXONERATE is a third option meaning "legitimate concern, but not worth implementing in this PR" — it spares the proposing reviewer from losing a point.

## Ballot Format

Before sending to voters, assign each deduplicated finding a stable sequential ID. Format the ballot as:

```
## Findings Ballot

Vote YES, NO, or EXONERATE on each finding. A finding should receive YES if it is correct, important, and worth implementing. Vote NO if the finding is incorrect, trivial, or would cause more harm than good. Vote EXONERATE if the finding raises a legitimate concern worth noting, but is not worth implementing in this PR — this spares the proposing reviewer from a penalty.

FINDING_1: <reviewer attribution> — <finding description>
FINDING_2: <reviewer attribution> — <finding description>
...
```

Include the reviewer attribution (e.g., "General", "Deep-Analysis", "Codex-General", "Codex-Deep-Analysis", "Cursor") so voters have context, but instruct voters to evaluate each finding on its merits regardless of who proposed it.

## Voter Output Format

Each voter must output one line per finding:

```
FINDING_1: YES — <one-line rationale>
FINDING_2: NO — <one-line rationale>
FINDING_3: EXONERATE — <one-line rationale>
...
```

Valid vote tokens are `YES`, `NO`, and `EXONERATE`. If a voter's output contains valid votes for some findings but is missing votes for others, use the valid votes and treat only the missing findings as abstentions (reduce the voter pool size for those findings). Treat the entire output as unparseable only if zero findings can be matched to the expected format — in that case, treat all their votes as abstentions.

## Threshold Rules

| Eligible Voters | YES Votes Required | Notes |
|---|---|---|
| 3 | 2+ | Standard majority |
| 2 | 2 (unanimous) | When one voter unavailable/timed out |
| 1 | Skip voting | Fall back to accepting all findings |
| 0 | Skip voting | Fall back to accepting all findings |

When voting is skipped due to insufficient voters, print: `**⚠ Voting skipped (<N> voter(s) available, minimum 2 required). All findings accepted.**`

## Voter Panel Composition

**For plan review** (`/design` Step 3):
- **Voter 1**: Claude Deep Analysis reviewer subagent — launched as a fresh Agent tool invocation with a focused voting prompt (separate from the reviewer subagents)
- **Voter 2**: Codex — via `run-external-reviewer.sh`
- **Voter 3**: Cursor — via `run-external-reviewer.sh`

**For code review** (`/review` Step 3):
- **Voter 1**: Claude General reviewer subagent — launched as a fresh Agent tool invocation
- **Voter 2**: Codex — via `run-external-reviewer.sh`
- **Voter 3**: Cursor — via `run-external-reviewer.sh`

All voters vote on **all** findings — no self-voting exclusion. Voters are instructed to evaluate each finding objectively regardless of who proposed it.

## Voter Prompt Template

Customize the `{VOTER_ROLE}` and `{REVIEW_CONTEXT}` per skill:

```
You are a {VOTER_ROLE} participating in a voting panel. You will be presented with a list of proposed changes to {REVIEW_CONTEXT}. For each finding, vote YES, NO, or EXONERATE:
- **YES**: The finding is correct, important, and worth implementing.
- **NO**: The finding is incorrect, trivial, duplicative, or would cause more harm than good.
- **EXONERATE**: The finding raises a legitimate concern worth noting, but is not worth implementing in this PR. This spares the proposing reviewer from a penalty.

Be scrupulous — only vote YES for findings that genuinely improve the {REVIEW_CONTEXT}. Use EXONERATE when a concern is valid but not actionable now.

{BALLOT}

For each finding, output exactly one line:
FINDING_N: YES — <one-line rationale>
or
FINDING_N: NO — <one-line rationale>
or
FINDING_N: EXONERATE — <one-line rationale>

You must vote on every finding. Do NOT skip any. Do NOT modify files.
```

## Launching Voters

Launch all 3 voters **in parallel** (in a single message). Spawn order: Cursor first (slowest), then Codex, then Claude subagent (fastest).

**Cursor voter** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool cursor --output "<tmpdir>/cursor-vote-output.txt" --timeout 600 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "<voter prompt with ballot>"
```

Use `run_in_background: true` and `timeout: 660000`.

**Codex voter** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-external-reviewer.sh --tool codex --output "<tmpdir>/codex-vote-output.txt" --timeout 600 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "<tmpdir>/codex-vote-output.txt" \
    "<voter prompt with ballot>"
```

Use `run_in_background: true` and `timeout: 660000`.

**Claude voter**: Launch via Agent tool with the voter prompt.

Wait for external voter sentinels using `wait-for-reviewers.sh` (use the same tmpdir as the review phase — do not create a new temp directory for voting). Only include sentinel paths for voters that were actually launched:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/wait-for-reviewers.sh --timeout 660 \
  "<tmpdir>/cursor-vote-output.txt.done" \
  "<tmpdir>/codex-vote-output.txt.done"
```

Use `timeout: 660000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Note: voter output files use the `-vote-` infix to avoid collision with reviewer output files (`-plan-output` or `-output`).

## Competition Scoring

After tallying votes, compute a score for each **original reviewer** (not voters):

| Vote Result | Points | Description |
|---|---|---|
| Finding accepted (2+ YES) | +1 | Reviewer's finding was validated by the panel |
| Finding got exactly 1 YES | 0 | Neutral — not enough support but not rejected |
| Finding got 0 YES but 1+ EXONERATE | 0 | Exonerated — legitimate concern, not actionable now |
| Finding got 0 YES and 0 EXONERATE | -1 | Rejected — finding was unanimously dismissed |

If a deduplicated finding was proposed by multiple reviewers (merged during deduplication), **all** contributing reviewers receive the same points for that finding.

## Scoreboard

After voting, print a scoreboard to the session:

```
## Reviewer Competition Scoreboard

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|-------|
| General              | 3        | 2        | 1               | 0                             | 0                         | +2    |
| Deep-Analysis        | 2        | 1        | 0               | 1                             | 0                         | +1    |
| Codex-General        | 1        | 0        | 0               | 0                             | 1                         | -1    |
| Codex-Deep-Analysis  | 1        | 1        | 0               | 0                             | 0                         | +1    |
| Cursor               | 2        | 1        | 1               | 0                             | 0                         | +1    |

Note: In future iterations, token allocation will be weighted proportionally
to reviewer scores — higher-scoring reviewers will receive more tokens.
```

## Out-of-Scope Observations

Reviewers may return a second list of **out-of-scope observations** — pre-existing issues or concerns beyond the PR's scope that are worth surfacing for future attention. These are handled alongside in-scope findings but with different semantics:

### OOS on the Ballot

Out-of-scope items are deduplicated separately from in-scope findings and assigned IDs with an `OOS_` prefix (e.g., `OOS_1`, `OOS_2`). They are included on the same ballot as in-scope findings, labeled with `[OUT_OF_SCOPE]`:

```
OOS_1: [OUT_OF_SCOPE] General — <description of pre-existing issue>
```

### OOS Vote Semantics

For out-of-scope items, the vote meanings are:
- **YES**: Promote this observation to in-scope — it should be implemented in this PR.
- **NO**: Keep as observation — not worth addressing now.
- **EXONERATE**: Legitimate observation worth documenting — keep as observation.

If an OOS item receives 2+ YES votes, it is **promoted** to in-scope and treated as an accepted finding (implemented/revised). Otherwise it remains an observation.

### OOS Scoring

Out-of-scope items use a **per-item scoring floor of 0**. This floor applies **only to OOS items** — in-scope findings retain normal scoring including -1 for rejected.

| OOS Vote Result | Points | Description |
|---|---|---|
| OOS promoted (2+ YES) | +1 | Reviewer surfaced an issue worth fixing now |
| OOS not promoted | 0 | Reviewer surfaced a useful observation (no penalty) |

### OOS Scoreboard

The scoreboard includes additional columns for OOS items:

```
| Reviewer | ... | OOS Proposed | OOS Promoted | ...
```

### OOS Reporting

Non-promoted OOS items are **not** written to `rejected-findings.md`. They are collected separately and reported in a dedicated `<details><summary>Out-of-Scope Observations</summary>` section in the PR body. This section is populated by `/implement` Step 9a from conversation context.

External reviewers (Codex, Cursor) use single-list prompts and do not produce OOS items — their entire output is treated as in-scope findings. Only Claude subagent reviewers (which use the dual-list templates from `reviewer-templates.md`) produce OOS items.

## Zero Accepted Findings

If voting filters out **all** in-scope findings (every in-scope finding rejected by the panel), print: `**ℹ Voting panel rejected all findings. No changes to implement.**` and skip the implementation/revision step. Proceed directly to the rejected findings report. (OOS items that were not promoted are still collected for reporting.)
