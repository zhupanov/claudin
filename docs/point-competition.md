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

Out-of-scope (OOS) observations use a **per-item scoring floor of 0**. This asymmetry is a deliberate design decision: reviewers should feel free to surface pre-existing issues and observations beyond the PR's scope without risking penalty.

| OOS Vote Result | Points | Description |
|---|---|---|
| **OOS Promoted** (2+ YES) | +1 | Reviewer surfaced an issue worth fixing in this PR |
| **OOS Not Promoted** | 0 | Useful observation, no penalty regardless of vote outcome |

The key invariant: **OOS items can never score below 0.** This encourages reviewers to report pre-existing code issues, technical debt, and architectural concerns freely.

## OOS Promotion Mechanics

Out-of-scope items go on the same voting ballot as in-scope findings, labeled with `[OUT_OF_SCOPE]`:

```text
OOS_1: [OUT_OF_SCOPE] Generic — <description>
```

Voters can promote an OOS item to in-scope by voting YES:

- **2+ YES** → Promoted to in-scope, implemented in this PR, reviewer earns +1
- **Fewer than 2 YES** → Remains an observation, reported in the PR body, reviewer earns 0

## Scoreboard

After voting completes, a scoreboard is printed showing each reviewer's performance:

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | OOS Proposed | OOS Promoted | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|--------------|--------------|-------|
| Generic | 3 | 2 | 1 | 0 | 0 | 1 | 0 | +2 |
| Architect | 2 | 1 | 0 | 1 | 0 | 0 | 0 | +1 |
| Codex | 1 | 0 | 0 | 0 | 1 | 0 | 0 | -1 |

## Future Plans

In future iterations, token allocation will be weighted proportionally to reviewer scores — higher-scoring reviewers will receive more tokens, allowing them to conduct deeper analysis.

## Where Scoring Applies

The competition scoring system is active in skills that use the [voting protocol](voting-process.md):

- **`/design`** — Plan review findings are scored after the voting panel adjudicates
- **`/review`** — Code review findings (round 1) are scored after voting

Skills that use the negotiation protocol (`/research`, `/loop-review`) do not use competition scoring.
