# Point Competition

Reviewer earn point from finding perform in [voting process](voting-process.md). Competition reward good finding, punish noise.

## Scoring Rules

Each finding vote outcome decide point for reviewer who propose:

| Vote Result | Points | Description |
|---|---|---|
| **Accepted** (2+ YES) | +1 | Panel validate finding |
| **Neutral** (exactly 1 YES) | 0 | Not enough support, not dismissed |
| **Exonerated** (0 YES, 1+ EXONERATE) | 0 | Real concern, not actionable this PR |
| **Rejected** (0 YES, 0 EXONERATE) | -1 | Panel unanimous dismiss |

If dedup merge finding from many reviewer, all contributor get same point.

## Out-of-Scope Scoring

OOS use **asymmetric reward-only scoring** — accepted OOS +1 (same as in-scope), rejected OOS no penalty. Asymmetry push reviewer surface observation free, dismiss cost nothing. Accepted OOS still need 2+ YES, so threshold filter noise.

| OOS Vote Result | Points | Description |
|---|---|---|
| **OOS Accepted** (2+ YES) | +1 | Reviewer surface issue worth GitHub tracking |
| **OOS Neutral** (exactly 1 YES) | 0 | Not enough support, not dismissed |
| **OOS Exonerated** (0 YES, 1+ EXONERATE) | 0 | Real observation, not worth file issue |
| **OOS Rejected** (0 YES, 0 EXONERATE) | 0 | No penalty — surface free |

## OOS Issue Filing

OOS item go on same ballot as in-scope, label `[OUT_OF_SCOPE]`:

```text
OOS_1: [OUT_OF_SCOPE] Code — <description>
```

Voter decide if OOS deserve GitHub issue:

- **2+ YES** → Accepted: `/implement` file GitHub issue, reviewer get +1
- **Fewer than 2 YES** → Not accepted: stay observation in PR body

**OOS never implement in current PR.** Accepted OOS only create GitHub issue — clean split "fix now" (in-scope) from "fix later" (OOS).

## Scoreboard

After vote done, scoreboard print each reviewer performance:

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | OOS Proposed | OOS Accepted | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|--------------|--------------|-------|
| Code | 3 | 2 | 1 | 0 | 0 | 1 | 0 | +2 |
| Codex | 2 | 1 | 0 | 1 | 0 | 0 | 0 | +1 |
| Cursor | 2 | 1 | 1 | 0 | 0 | 1 | 1 | +2 |

## Future Plans

Future: token allocation weight by reviewer score — high score get more token for deep analysis.

## Where Scoring Applies

Competition score active in skill use [voting protocol](voting-process.md):

- **`/design`** — Plan review finding score after panel adjudicate
- **`/review`** — Code review finding (round 1) score after vote

Skill use negotiation protocol (`/research`, `/loop-review`) no use competition score.
