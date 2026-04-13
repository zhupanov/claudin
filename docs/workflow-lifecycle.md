# Workflow Lifecycle

How skills compose to form the end-to-end development workflow in Larch.

## Skill Orchestration Hierarchy

Skills are not invoked in a flat sequence. They form a hierarchical call graph where higher-level skills orchestrate lower-level ones:

```mermaid
graph TD
    IMPLEMENT["/implement"] -->|invokes| DESIGN["/design"]
    IMPLEMENT -->|invokes| REVIEW["/review"]
    IMPLEMENT -->|invokes| CHECKS["/relevant-checks"]
    LOOP["/loop-review"] -->|invokes| IMPLEMENT
    ALIAS["/alias"] -->|writes| SKILL_FILE[".claude/skills/&lt;name&gt;/SKILL.md"]

    style IMPLEMENT fill:#2d5a27,color:#fff
    style LOOP fill:#2d5a27,color:#fff
    style DESIGN fill:#4a3a6e,color:#fff
    style REVIEW fill:#4a3a6e,color:#fff
    style CHECKS fill:#555,color:#fff
    style ALIAS fill:#6b4c2a,color:#fff
    style SKILL_FILE fill:#555,color:#fff
```

- **`/implement`** is the top-level orchestrator. It runs the full design → code → review → PR workflow by default. With the `--merge` flag, it also runs the CI+rebase+merge loop and local cleanup after PR creation.
- **`/loop-review`** partitions the codebase into slices, reviews each, and invokes `/implement` to implement accepted improvements — accumulating up to 3 slices per `/implement` invocation before flushing.

## End-to-End Flow

The full lifecycle when running `/implement <feature description>`:

```mermaid
flowchart TD
    START([Start]) --> DESIGN_PHASE

    subgraph DESIGN_PHASE["Design Phase (/design)"]
        BRANCH[Create branch] --> QUESTIONS[Clarifying questions]
        QUESTIONS --> DISCUSS1[Design discussion round 1]
        DISCUSS1 --> SKETCHES[5-agent collaborative sketches]
        SKETCHES --> SYNTHESIS[Approach synthesis]
        SYNTHESIS --> DIALECTIC[Dialectic debate on contested decisions]
        DIALECTIC --> PLAN[Write implementation plan]
        PLAN --> PLAN_REVIEW[Plan review: 5 reviewers]
        PLAN_REVIEW --> VOTE1[Voting panel adjudicates findings]
        VOTE1 --> REVISE[Revise plan if needed]
        REVISE --> DISCUSS2[Design discussion round 2]
    end

    DESIGN_PHASE --> IMPL_PHASE

    subgraph IMPL_PHASE["Implementation Phase"]
        CODE[Implement feature] --> VALIDATE1[Validation checks]
        VALIDATE1 --> COMMIT1[First commit]
        COMMIT1 --> CODE_REVIEW[Code review: 5 reviewers]
        CODE_REVIEW --> VOTE2[Voting panel adjudicates findings]
        VOTE2 --> FIX[Implement accepted fixes]
        FIX --> VALIDATE2[Validation checks]
        VALIDATE2 --> COMMIT2[Second commit]
        COMMIT2 --> VERSION[Version bump]
        VERSION --> PR[Create PR]
        PR --> CI_MONITOR[Monitor CI + fix failures]
        CI_MONITOR --> SLACK[Slack announcement]
    end

    IMPL_PHASE --> MERGE_FLAG{--merge<br/>flag set?}
    MERGE_FLAG -->|No| DONE([Complete])
    MERGE_FLAG -->|Yes| MERGE_PHASE

    subgraph MERGE_PHASE["Merge Phase (/implement --merge)"]
        CI_WAIT[Wait for CI to pass] --> REBASE{Main advanced?}
        REBASE -->|Yes| DO_REBASE[Rebase + push]
        DO_REBASE --> CI_WAIT
        REBASE -->|No| MERGE[Merge PR]
        MERGE --> EMOJI[Add :merged: emoji to Slack]
        EMOJI --> CLEANUP[Local cleanup]
        CLEANUP --> VERIFY[Verify main]
    end

    MERGE_PHASE --> DONE
```

## Standalone Usage

Not every task requires the full `/implement` pipeline. Skills can be used independently:

- **`/design [--debug] <feature>`** — Plan a feature without implementing it. Creates a branch, runs collaborative sketches, writes and reviews the plan.
- **`/review [--debug]`** — Review the current branch's changes. Launches reviewers, runs voting on findings, implements accepted fixes, and re-runs validation checks in a recursive loop.
- **`/research [--debug] <topic>`** — Read-only investigation. Does not create branches, modify files, or make commits. Uses a restricted tool set (no Edit, Write, or Skill tools).
- **`/alias <name> <skill> [flags...]`** — Create a project-level alias skill in `.claude/skills/` that forwards to a larch skill with preset flags. Does not invoke `/implement` — writes files directly and commits.

## Flags

Flags modify behavior across the skill hierarchy:

| Flag | Available on | Effect |
|---|---|---|
| `--quick` | `/implement` | Skips `/design` (produces inline plan instead). Simplifies code review to 1 round with 2 Claude subagents only (no external reviewers, no voting panel). |
| `--auto` | `/implement`, `/design` | Suppresses all interactive question checkpoints. Skills run fully autonomously without user interaction. |
| `--merge` | `/implement` | Runs the CI+rebase+merge loop, :merged: emoji, local branch cleanup, and main verification after PR creation. Without `--merge`, `/implement` creates the PR and stops (the initial CI wait, Slack announcement, rejected findings report, final report, and temp cleanup still run). |
| `--debug` | `/implement`, `/design`, `/review`, `/research`, `/loop-review` | Enables verbose output: descriptive Bash tool descriptions, full explanatory prose between tool calls, per-reviewer individual completion messages alongside the compact status table. Default (no `--debug`) uses minimal output with compact status tables and suppressed prose. `/implement` auto-propagates `--debug` to `/design` and `/review`. `/loop-review` propagates to `/implement`. |

## Conditional Steps

Certain steps in the workflow depend on configuration prerequisites and are skipped when unavailable:

- **Slack announcements** — Require Slack configuration. When unavailable, the announcement step is skipped with a warning but the workflow continues.
- **CI monitoring** — Requires repository identification. When unavailable, CI monitoring is skipped.
- **Version bump** — Requires a `/bump-version` skill defined in the repo. When absent, the version bump step is skipped with a warning.
- **External reviewers (Cursor, Codex)** — When unavailable, Claude subagents replace them so the total reviewer/voter count remains constant. The quality of review is maintained through diverse Claude perspectives rather than degrading to fewer reviewers.

## Resolution Protocols

Different skills use different protocols for resolving review findings:

| Protocol | Used by | Mechanism |
|---|---|---|
| [Voting](voting-process.md) | `/design`, `/review` | 3-agent panel votes YES/NO/EXONERATE. 2+ YES required to accept. |
| Negotiation | `/research`, `/loop-review` | Up to N rounds of back-and-forth with external reviewers. Claude makes the final call. |

See [Voting Process](voting-process.md) for full details on the voting protocol.
