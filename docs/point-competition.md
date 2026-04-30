# Point Competition

Reviewers earn points based on how their findings perform in the [voting process](voting-process.md). The competition incentivizes high-quality, actionable findings and discourages noise.

## Scoring Rules

Each finding's vote outcome determines the points awarded to the reviewer(s) who proposed it:

| Vote Result | Points | Description |
|---|---|---|
| **Accepted** (2+ YES) | +1 | The finding was validated by the voting panel |
| **Neutral** (exactly 1 YES) | 0 | Insufficient support, but not dismissed |
| **Exonerated** (0 YES, 1+ EXONERATE) | 0 | Legitimate concern, but not actionable in this PR |
| **Rejected** (0 YES, 0 EXONERATE) | -1 | Finding was unanimously dismissed by the panel |

If a deduplicated finding was proposed by multiple reviewers (merged during deduplication), all contributing reviewers receive the same points for that finding.

## Out-of-Scope Scoring

Out-of-scope (OOS) observations use **asymmetric reward-only scoring** — accepted OOS earns +1 (the same upside as in-scope findings), but unanimously-rejected OOS carries no penalty. This deliberate asymmetry encourages reviewers to surface observations freely, since a dismissed observation costs nothing. Accepted OOS still requires 2+ YES votes, so the acceptance threshold filters out noise.

| OOS Vote Result | Points | Description |
|---|---|---|
| **OOS Accepted** (2+ YES) | +1 | Reviewer surfaced an issue worth tracking as a GitHub issue |
| **OOS Neutral** (exactly 1 YES) | 0 | Insufficient support, but not dismissed |
| **OOS Exonerated** (0 YES, 1+ EXONERATE) | 0 | Legitimate observation, but not worth filing an issue |
| **OOS Rejected** (0 YES, 0 EXONERATE) | 0 | No penalty — reviewers are encouraged to surface observations freely |

## OOS Issue Filing

Out-of-scope items go on the same voting ballot as in-scope findings, labeled with `[OUT_OF_SCOPE]`:

```text
OOS_1: [OUT_OF_SCOPE] Code — <description>
```

Voters decide whether each OOS item deserves a GitHub issue:

- **2+ YES** → Accepted: filed as a GitHub issue by `/implement` for future attention, reviewer earns +1
- **Fewer than 2 YES** → Not accepted: remains an observation reported in the PR body

**OOS items are never implemented in the current PR.** Accepted OOS items result in GitHub issue creation only — this cleanly separates "fix now" (in-scope findings) from "fix later" (OOS observations).

## Scoreboard

After voting completes, a scoreboard is printed showing each reviewer's performance. Attribution labels are skill-specific — `/review` uses 6 independent players (`Structure`, `Correctness`, `Testing`, `Security`, `Edge-cases`, `Codex`); `/design` uses 3 players (`Code`, `Codex`, `Cursor`). One row per independent reviewer:

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | OOS Proposed | OOS Accepted | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|--------------|--------------|-------|
| Structure | 2 | 1 | 1 | 0 | 0 | 0 | 0 | +1 |
| Correctness | 1 | 1 | 0 | 0 | 0 | 0 | 0 | +1 |
| Testing | 2 | 1 | 0 | 1 | 0 | 1 | 1 | +2 |
| Security | 1 | 1 | 0 | 0 | 0 | 0 | 0 | +1 |
| Edge-cases | 1 | 0 | 1 | 0 | 0 | 0 | 0 | 0 |
| Codex | 2 | 1 | 0 | 0 | 1 | 0 | 0 | 0 |

## Future Plans

In future iterations, token allocation will be weighted proportionally to reviewer scores — higher-scoring reviewers will receive more tokens, allowing them to conduct deeper analysis.

## Where Scoring Applies

The competition scoring system is active in skills that use the [voting protocol](voting-process.md):

- **`/design`** — Plan review findings are scored after the voting panel adjudicates
- **`/review`** — Code review findings (round 1) are scored after voting

Skills that use the negotiation protocol (`/research`) do not use competition scoring.
