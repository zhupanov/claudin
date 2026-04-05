# Claudin2

Claudin2 is a Claude Code workflow automation framework that orchestrates multi-agent design, code review, and implementation through collaborative AI-driven processes.

## Features

- **Multi-agent design planning** — 5 agents independently propose architectural approaches before a full implementation plan is written, preventing anchoring bias
- **Voting-based review resolution** — A 3-agent voting panel (YES/NO/EXONERATE) adjudicates review findings for both plan review and code review
- **Reviewer competition scoring** — Reviewers earn points based on finding quality, with a scoreboard tracking accepted, neutral, exonerated, and rejected findings
- **End-to-end automation** — From feature design through PR creation, CI monitoring, merge, and Slack announcement in a single command
- **External reviewer integration** — Codex and Cursor participate alongside Claude subagents as both reviewers and voters
- **Systematic codebase review** — Partition an entire repository into slices, review each with specialized subagents, and implement improvements automatically

## Skills

Slash commands available in Claude Code sessions. They automate multi-step workflows by orchestrating git, GitHub, Slack, and other tools.

| Command | Arguments | Description |
|---|---|---|
| [`/design`](.claude/skills/design/SKILL.md) | `[--auto] <feature description>` | Design an implementation plan with collaborative multi-reviewer review. 5 agents (3 Claude + Cursor + Codex) independently propose architectural approaches, then 6 reviewers (4 Claude + Cursor + Codex) validate the plan. `--auto` suppresses all interactive question checkpoints. [(Diagram).](.claude/skills/design/diagram.svg) |
| [`/implement`](.claude/skills/implement/SKILL.md) | `[--quick] [--auto] <feature description>` | Implement a feature from design through PR creation, CI monitoring, and Slack announcement, with code review and version bump. `--quick` skips `/design` and uses simplified code review (4 Claude subagents, 1 round). `--auto` suppresses all interactive question checkpoints. Does not merge — use `/shazam` for the full end-to-end workflow including merge. [(Diagram).](.claude/skills/implement/diagram.svg) |
| [`/research`](.claude/skills/research/SKILL.md) | `<research question or topic>` | Collaborative read-only research using 5 research agents (3 Claude + Cursor + Codex) then 6 validation reviewers (4 Claude + Cursor + Codex). Produces a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict. Does not modify the repo. [(Diagram).](.claude/skills/research/diagram.svg) |
| [`/review`](.claude/skills/review/SKILL.md) | *(none)* | Code review current branch changes with specialized subagents (4 Claude + Codex + Cursor, if available), implementing accepted suggestions in a recursive loop (up to 5 rounds). Reviews the diff between main and HEAD. [(Diagram).](.claude/skills/review/diagram.svg) |
| [`/shazam`](.claude/skills/shazam/SKILL.md) | `[--quick] [--auto] [--no-merge] <feature description>` | Full end-to-end feature workflow — design, implement, PR, Slack announce, CI+rebase+merge, and cleanup. `--quick` skips `/design` and uses simplified code review (4 Claude subagents, 1 round). `--auto` suppresses all interactive question checkpoints. `--no-merge` skips CI monitoring, merge, :merged: emoji, and local branch cleanup (final report and temp cleanup still run). [(Diagram).](.claude/skills/shazam/diagram.svg) |
| [`/loop-review`](.claude/skills/loop-review/SKILL.md) | `[partition criteria]` | Systematic code review of entire repository by partitioning into slices, reviewing each with specialized subagents (4 Claude + Codex + Cursor, if available), implementing improvements via `/shazam`, and logging deferred suggestions. The optional argument specifies how to partition the codebase (e.g., by directory, by file type). [(Diagram).](.claude/skills/loop-review/diagram.svg) |
| [`/skill-creator`](.claude/skills/skill-creator/SKILL.md) | *(conversational)* | Create new skills, modify and improve existing skills, and measure skill performance via eval-based testing. No specific arguments — works conversationally based on your request. [(Diagram).](.claude/skills/skill-creator/diagram.svg) |
| [`/relevant-checks`](.claude/skills/relevant-checks/SKILL.md) | *(none)* | Run repo-specific validation checks based on modified files. Invoked automatically by `/implement` and `/review` after code changes. |

## Review Agents

Internal agent definitions used by skills like `/design`, `/review`, and `/loop-review`. They are not invoked directly — the skills launch them as specialized subagents during plan and code review.

| Agent | Description |
|---|---|
| [`generic-reviewer`](.claude/agents/generic-reviewer.md) | General-purpose code reviewer for bugs, logic, quality, tests, backward compatibility, and style consistency. |
| [`correctness-reviewer`](.claude/agents/correctness-reviewer.md) | Correctness-focused code reviewer specializing in logic errors, off-by-one bugs, nil handling, type mismatches, race conditions, and error path analysis. |
| [`risk-reviewer`](.claude/agents/risk-reviewer.md) | Risk and integration reviewer specializing in breaking changes, side effects, thread safety, deployment risks, regressions, and CI impact analysis. |
| [`architect-reviewer`](.claude/agents/architect-reviewer.md) | Senior systems architect reviewer focused on separation of concerns, contract boundaries, invariants, and semantic boundary violations. |

## Environment Variables

*Coming soon.*

## Detailed Documentation

- [Workflow Lifecycle](docs/workflow-lifecycle.md) — How skills compose to form the end-to-end development workflow
- [Voting Process](docs/voting-process.md) — The 3-agent voting panel that adjudicates review findings
- [Point Competition](docs/point-competition.md) — Reviewer scoring system and competition mechanics
- [Collaborative Sketches](docs/collaborative-sketches.md) — The diverge-then-converge design phase
- [External Reviewers](docs/external-reviewers.md) — Codex and Cursor integration procedures
- [Review Agents](docs/review-agents.md) — The 4 specialized Claude reviewer archetypes
- [Agent System](docs/agents.md) — How skills orchestrate parallel subagents
