# Workflow Lifecycle

How skills compose to form the end-to-end development workflow in Claudin2.

## Skill Orchestration Hierarchy

Skills are not invoked in a flat sequence. They form a hierarchical call graph where higher-level skills orchestrate lower-level ones:

```mermaid
graph TD
    SHAZAM["/shazam"] -->|invokes| IMPLEMENT["/implement"]
    IMPLEMENT -->|invokes| DESIGN["/design"]
    IMPLEMENT -->|invokes| REVIEW["/review"]
    IMPLEMENT -->|invokes| CHECKS["/relevant-checks"]
    LOOP["/loop-review"] -->|invokes| SHAZAM

    style SHAZAM fill:#2d5a27,color:#fff
    style LOOP fill:#2d5a27,color:#fff
    style IMPLEMENT fill:#1a4a6e,color:#fff
    style DESIGN fill:#4a3a6e,color:#fff
    style REVIEW fill:#4a3a6e,color:#fff
    style CHECKS fill:#555,color:#fff
```

- **`/shazam`** is the top-level orchestrator. It invokes `/implement` for the full workflow (design, code, review, PR, CI, Slack), then handles CI monitoring, rebasing, merging, and cleanup.
- **`/implement`** invokes `/design` for planning, `/review` for code review, and `/relevant-checks` for validation. It creates the PR and monitors CI, but does not merge.
- **`/loop-review`** partitions the codebase into slices, reviews each, and invokes `/shazam` to implement accepted improvements — accumulating up to 3 slices per `/shazam` invocation before flushing.

## End-to-End Flow

The full lifecycle when running `/shazam <feature description>`:

```mermaid
flowchart TD
    START([Start]) --> DESIGN_PHASE

    subgraph DESIGN_PHASE["Design Phase (/design)"]
        BRANCH[Create branch] --> QUESTIONS[Clarifying questions]
        QUESTIONS --> SKETCHES[5-agent collaborative sketches]
        SKETCHES --> SYNTHESIS[Approach synthesis]
        SYNTHESIS --> PLAN[Write implementation plan]
        PLAN --> PLAN_REVIEW[Plan review: 6 reviewers]
        PLAN_REVIEW --> VOTE1[Voting panel adjudicates findings]
        VOTE1 --> REVISE[Revise plan if needed]
    end

    DESIGN_PHASE --> IMPL_PHASE

    subgraph IMPL_PHASE["Implementation Phase (/implement)"]
        CODE[Implement feature] --> VALIDATE1[Validation checks]
        VALIDATE1 --> COMMIT1[First commit]
        COMMIT1 --> CODE_REVIEW[Code review: 6 reviewers]
        CODE_REVIEW --> VOTE2[Voting panel adjudicates findings]
        VOTE2 --> FIX[Implement accepted fixes]
        FIX --> VALIDATE2[Validation checks]
        VALIDATE2 --> COMMIT2[Second commit]
        COMMIT2 --> VERSION[Version bump]
        VERSION --> PR[Create PR]
        PR --> CI_MONITOR[Monitor CI + fix failures]
        CI_MONITOR --> SLACK[Slack announcement]
    end

    IMPL_PHASE --> MERGE_PHASE

    subgraph MERGE_PHASE["Merge Phase (/shazam)"]
        CI_WAIT[Wait for CI to pass] --> REBASE{Main advanced?}
        REBASE -->|Yes| DO_REBASE[Rebase + push]
        DO_REBASE --> CI_WAIT
        REBASE -->|No| MERGE[Merge PR]
        MERGE --> EMOJI[Add :merged: emoji to Slack]
        EMOJI --> CLEANUP[Local cleanup]
        CLEANUP --> VERIFY[Verify main]
    end

    MERGE_PHASE --> DONE([Complete])
```

## Standalone Usage

Not every task requires the full `/shazam` pipeline. Skills can be used independently:

- **`/design <feature>`** — Plan a feature without implementing it. Creates a branch, runs collaborative sketches, writes and reviews the plan.
- **`/implement <feature>`** — Implement and create a PR without merging. If a reviewed design plan is visible in the current session context, it skips `/design`.
- **`/review`** — Review the current branch's changes. Launches reviewers, runs voting on findings, implements accepted fixes, and re-runs validation checks in a recursive loop.
- **`/research <topic>`** — Read-only investigation. Does not create branches, modify files, or make commits. Uses a restricted tool set (no Edit, Write, or Skill tools).

## Flags

Flags modify behavior across the skill hierarchy:

| Flag | Available on | Effect |
|---|---|---|
| `--quick` | `/shazam`, `/implement` | Skips `/design` (produces inline plan instead). Simplifies code review to 1 round with 4 Claude subagents only (no external reviewers, no voting panel). |
| `--auto` | `/shazam`, `/implement`, `/design` | Suppresses all interactive question checkpoints. Skills run fully autonomously without user interaction. |
| `--no-merge` | `/shazam` | Creates PR but skips CI monitoring, merge, :merged: emoji, and local branch cleanup. |

## Conditional Steps

Certain steps in the workflow depend on configuration prerequisites and are skipped when unavailable:

- **Slack announcements** — Require Slack configuration. When unavailable, the announcement step is skipped with a warning but the workflow continues.
- **CI monitoring** — Requires repository identification. When unavailable, CI monitoring is skipped.
- **Version bump** — Requires a `/bump-version` skill defined in the repo. When absent, the version bump step is skipped with a warning.

## Resolution Protocols

Different skills use different protocols for resolving review findings:

| Protocol | Used by | Mechanism |
|---|---|---|
| [Voting](voting-process.md) | `/design`, `/review` | 3-agent panel votes YES/NO/EXONERATE. 2+ YES required to accept. |
| Negotiation | `/research`, `/loop-review` | Up to N rounds of back-and-forth with external reviewers. Claude makes the final call. |

See [Voting Process](voting-process.md) for full details on the voting protocol.
