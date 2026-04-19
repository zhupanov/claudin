# Collaborative Sketches

The collaborative sketch phase is a diverge-then-converge process in `/design` where 5 agents independently propose architectural approaches before the full implementation plan is written. This prevents anchoring bias — where a single perspective locks in the direction before alternatives are considered.

## Why Sketches Exist

Without the sketch phase, the first idea considered tends to dominate the plan. By having 5 agents independently explore the design space, the system surfaces different perspectives early — when they can still influence the architectural direction — rather than waiting for review when the plan is already anchored.

## The 5 Sketch Agents

The sketch phase always uses exactly 5 agents: 1 Claude subagent (the orchestrator's inline sketch) plus 4 external slots (2 Cursor + 2 Codex) that carry the four non-general personalities. Each external slot has a Claude subagent fallback that activates when the respective tool is unavailable.

| Agent | Harness | Role | Focus |
|---|---|---|---|
| **Claude (General)** | Inline (orchestrator) | Orchestrator's own sketch | Key decisions, files to modify, tradeoffs |
| **Cursor slot 1** (fallback: Claude) | Cursor | Architecture/Standards | Clean design, proper layering, reuse of existing libraries |
| **Cursor slot 2** (fallback: Claude) | Cursor | Edge-cases/Failure-modes | Boundary conditions, error handling, failure recovery |
| **Codex slot 1** (fallback: Claude) | Codex | Innovation/Exploration | Creative alternatives, unconventional solutions, questioned assumptions |
| **Codex slot 2** (fallback: Claude) | Codex | Pragmatism/Safety | Smallest change set, avoid regressions, protect existing features |

### Important Distinction

The 5 sketch agents are **completely separate** from the 3 plan-review agents that evaluate the plan later in `/design` Step 3. The sketch agents explore the design space (5 perspectives); the plan reviewers validate the resulting plan (3-reviewer panel: 1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). They have different roles, different prompts, and serve different purposes.

## Per-Slot Fallback

When Cursor or Codex is unavailable, each affected slot falls back to a Claude subagent carrying the **same personality prompt** as the original external slot. This preserves the always-5-agents invariant and the always-5-personalities invariant regardless of external tool availability.

## Fallback Behavior by Phase

The handling of unavailable external tools differs across workflow phases:

| Phase | Unavailable Tool Handling |
|---|---|
| **Sketch phase** (`/design`) | Per-slot Claude fallbacks with matching personality — always 5 agents |
| **Plan review** (`/design`) | Claude Code Reviewer subagent fallbacks — always 3 reviewers |
| **Code review** (`/review`) | Claude Code Reviewer subagent fallbacks — always 3 reviewers |
| **Voting** | Claude replacement voters used — always 3 voters. 3 voters: 2+ YES to accept; 2 voters: unanimous YES; <2 voters: voting skipped, all findings accepted |
| **Dialectic debate** (`/design`) | **No Claude substitution** — when the assigned external tool (Cursor for odd-indexed decisions, Codex for even-indexed) is unavailable, that decision's bucket is skipped entirely and the Step 2a.4 synthesis decision stands. Intentional divergence from the rules above; see Step 2a.5 in `skills/design/SKILL.md` |

## How It Works

```mermaid
flowchart TD
    START([Feature description]) --> LAUNCH

    subgraph LAUNCH["Launch in parallel (slowest first)"]
        direction LR
        CURSOR1[Cursor: Arch/Standards] ~~~ CURSOR2[Cursor: Edge-cases/Failure-modes]
        CURSOR2 ~~~ CODEX1[Codex: Innovation/Exploration]
        CODEX1 ~~~ CODEX2[Codex: Pragmatism/Safety]
    end

    LAUNCH --> GENERAL[Claude General inline sketch]
    GENERAL --> WAIT[Wait for all 5 sketches]
    WAIT --> SYNTHESIS[Synthesis]

    subgraph SYNTHESIS["Approach Synthesis"]
        AGREE[Where agents agree] ~~~ DIVERGE[Where agents diverge]
        DIVERGE ~~~ DECISION[Reasoned decisions on contested points]
    end

    SYNTHESIS --> CHECK{Contested\ndecisions?}
    CHECK -->|None| PLAN[Full implementation plan]
    CHECK -->|1-5 found| DIALECTIC

    subgraph DIALECTIC["Dialectic Debate (/design only)"]
        direction LR
        THESIS[Thesis agents] ~~~ ANTITHESIS[Antithesis agents]
    end

    DIALECTIC --> PLAN

    style CURSOR1 fill:#1a4a6e,color:#fff
    style CURSOR2 fill:#1a4a6e,color:#fff
    style CODEX1 fill:#4a3a6e,color:#fff
    style CODEX2 fill:#4a3a6e,color:#fff
    style GENERAL fill:#2d5a27,color:#fff
    style DIALECTIC fill:#5a3a2e,color:#fff
    style CHECK fill:#f6ad55,color:#000
```

1. **Parallel launch** — All external and per-slot Claude fallback sketches are launched simultaneously. Both Cursor slots first (slowest), then both Codex slots, then any Claude fallback sketches. The orchestrating agent writes its own General sketch last, before reading any others, to preserve independence.

2. **Each agent produces** a 2-3 paragraph sketch covering:
   - Key architectural decisions and approach
   - Which files/modules to modify and why
   - Main tradeoffs to consider

3. **Synthesis** — After all 5 sketches return, the orchestrating agent produces a synthesis that:
   - Identifies where approaches agree (likely the majority)
   - Identifies divergence points and makes reasoned calls with justification
   - Notes which ideas from each sketch are incorporated
   - Highlights **Architecture/Standards** concerns sourced from Cursor slot 1
   - Highlights **Pragmatism/Safety** warnings sourced from Codex slot 2
   - Surfaces **Edge-case/Failure-mode** risks sourced from Cursor slot 2
   - Notes **Innovation/Exploration** alternatives sourced from Codex slot 1 that are worth preserving as options
   - Lists contested decisions in a structured format for the dialectic debate phase

4. **Dialectic debate** (`/design` only) — If the synthesis identifies contested decisions (points where sketches genuinely diverged), up to 5 (in priority order) are submitted to structured thesis/antithesis debates run on Cursor and Codex via deterministic per-decision bucketing. For each contested decision, a thesis agent defends the synthesis choice and an antithesis agent argues for the strongest alternative. Both run in parallel with codebase access. The orchestrator then writes binding resolutions that must explicitly address the antithesis arguments. This step is skipped when all sketches agree. See [Dialectic Debate](#dialectic-debate-design-only) below for details.

5. **Full plan** — The synthesis and any dialectic resolutions inform the complete implementation plan, which is then submitted to the 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor) for validation.

## Dialectic Debate (/design only)

> **Note**: This phase applies only to `/design`. `/research` does not include a dialectic debate step.

The dialectic debate phase adds reasoning depth on contested points without replacing the breadth-of-perspectives from the sketch phase. It addresses a specific weakness in the convergence step: when the synthesis identifies divergence points, the orchestrator would otherwise unilaterally resolve them — exactly where confirmation bias can creep in.

### When It Runs

The dialectic debate runs only when the synthesis in Step 2a.4 identifies genuine contested decisions — points where multiple sketches proposed fundamentally different approaches. If all 5 sketches agreed, the debate is skipped entirely.

### How It Works

For each contested decision (up to 5, prioritized by impact):

1. A **thesis agent** defends the approach chosen by the synthesis, arguing why it's the right call given the codebase and requirements
2. An **antithesis agent** attacks that choice, arguing for the strongest alternative, poking at hidden assumptions, and surfacing risks the synthesis glossed over

Both agents run in parallel and produce 1-2 focused paragraphs. A **quorum rule** requires both sides to report `STATUS=OK` from the collector and produce substantive structured output before a binding resolution is written — if either side's status check or content check fails, the debate falls back to the original synthesis decision.

The orchestrator then writes a resolution for each contested point that must explicitly address the antithesis arguments. It can still pick the original choice, but now it must justify against the strongest counterargument.

### Scope of Resolutions

Dialectic resolutions are **binding for Step 2b** (plan generation) only. They may be superseded by accepted findings from the Step 3 plan review. The finalized plan remains the sole canonical output.
