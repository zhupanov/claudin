# Larch

Larch is a Claude Code workflow automation framework that orchestrates multi-agent design, code review, and implementation through collaborative AI-driven processes.

## Table of Contents

- **Setup**
  - [Installation and Setup](docs/installation-and-setup.md) — plugin install, local development, agent setup recipes (Claude / Codex / Cursor), what the plugin provides, `/relevant-checks` consumer dependency, prerequisites
  - [Configuration and Permissions](docs/configuration-and-permissions.md) — [Strict-permissions consumers](docs/configuration-and-permissions.md#strict-permissions-consumers--skill-permission-entries), [`--admin` merge behavior](docs/configuration-and-permissions.md#--admin-merge-behavior), [Environment Variables](docs/configuration-and-permissions.md#environment-variables) (`LARCH_SLACK_*`, `LARCH_CURSOR_MODEL`, `LARCH_CODEX_MODEL`, `LARCH_CODEX_EFFORT`)
- **Reference**
  - [Features](#features)
  - [Skills](#skills)
  - [Aliases](#aliases)
  - [Review Agents](docs/review-agents.md) — the unified `code-reviewer` archetype
  - [Linting](docs/linting.md) — linters, Makefile targets, halt-rate regression harness
- **Architecture and workflow**
  - [Workflow Lifecycle](docs/workflow-lifecycle.md) — how skills compose end-to-end
  - [Agent System](docs/agents.md) — parallel subagent orchestration
  - [Collaborative Sketches](docs/collaborative-sketches.md) — the diverge-then-converge design phase
  - [External Reviewers](docs/external-reviewers.md) — Codex and Cursor integration
  - [Voting Process](docs/voting-process.md) — the 3-agent voting panel
  - [Point Competition](docs/point-competition.md) — reviewer scoring system

## Features

- **[Multi-agent design planning, reviews, and adjudication](docs/collaborative-sketches.md)** — 5 sketch agents diverge, a dialectic 3-judge binary panel resolves contested decisions, and a 3-reviewer panel validates the final plan.
- **[Voting-based review resolution](docs/voting-process.md)** — A 3-agent YES/NO/EXONERATE panel adjudicates plan and code review findings.
- **[Reviewer competition scoring](docs/point-competition.md)** — Reviewers earn points based on finding quality; a scoreboard tracks accepted, neutral, exonerated, and rejected findings.
- **[End-to-end automation](docs/workflow-lifecycle.md)** — From feature design through PR creation and initial CI wait in one command; `--merge` adds the CI+rebase+merge loop, local cleanup, and main verification. `--slack` announces the PR; `--draft` creates a draft PR and keeps the branch for further iteration.
- **[External reviewer integration](docs/external-reviewers.md)** — Codex and Cursor participate alongside Claude subagents as sketch agents, debaters, judges, reviewers, and voters.
- **[Systematic codebase review](skills/loop-review/SKILL.md)** — `/loop-review` partitions the repo into slices, reviews each with a 3-reviewer panel, and files every actionable finding as a deduplicated GitHub issue. Security-tagged findings are held locally per `SECURITY.md`.
- **[Tracked runs](skills/implement/SKILL.md)** — `/implement` PRs link to a tracking issue whose anchor comment is the single source of truth for full report content (voting tallies, rejected findings, version-bump reasoning, diagrams, OOS links, execution issues, run statistics).

## Skills

<table>
  <thead>
    <tr><th>Name</th><th>Arguments</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="docs/skills.md#alias"><code>/alias</code></a></td>
      <td><code>[--merge] [--slack] &lt;alias-name&gt; &lt;target-skill&gt; [preset-flags...]</code></td>
    </tr>
    <tr><td colspan="2">Create a project-level alias for a larch skill with preset flags.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#compress-skill"><code>/compress-skill</code></a></td>
      <td><code>[--debug] [--slack] &lt;skill-name-or-path&gt;</code></td>
    </tr>
    <tr><td colspan="2">Compress a skill's Markdown prose via a behavior-preserving rewrite.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#create-skill"><code>/create-skill</code></a></td>
      <td><code>[--plugin] [--multi-step] [--merge] [--debug] [--slack] &lt;skill-name&gt; &lt;description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Scaffold a new larch-style skill from a name and description.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#design"><code>/design</code></a></td>
      <td><code>[--auto] [--debug] &lt;feature description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Design an implementation plan with 5 sketch agents, dialectic adjudication, and a 3-reviewer validation panel.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#fix-issue"><code>/fix-issue</code></a></td>
      <td><code>[--debug] [--slack] [&lt;number-or-url&gt;]</code></td>
    </tr>
    <tr><td colspan="2">Process one approved GitHub issue per invocation, classifying intent and delegating PR work to <code>/implement</code>.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#implement"><code>/implement</code></a></td>
      <td><code>[--quick] [--auto] [--merge | --draft] [--slack] [--debug] [--issue &lt;N&gt;] &lt;feature description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Full end-to-end feature workflow — design, implement, PR. <code>--quick</code> skips <code>/design</code> and runs a simplified single-reviewer loop of up to 7 rounds with a per-round Cursor → Codex → Claude fallback chain (no voting panel).</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#issue"><code>/issue</code></a></td>
      <td><code>[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [&lt;issue description&gt;]</code></td>
    </tr>
    <tr><td colspan="2">Create one or more GitHub issues with LLM-based semantic duplicate detection.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#loop-improve-skill"><code>/loop-improve-skill</code></a></td>
      <td><code>[--slack] &lt;skill-name&gt;</code></td>
    </tr>
    <tr><td colspan="2">Iteratively improve an existing larch skill via a judge → design → implement loop (up to 10 rounds).</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#loop-review"><code>/loop-review</code></a></td>
      <td><code>[--debug] [partition criteria]</code></td>
    </tr>
    <tr><td colspan="2">Systematic code review of the entire repository; files every actionable finding as a deduplicated GitHub issue.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#relevant-checks"><code>/relevant-checks</code></a></td>
      <td><em>(none)</em></td>
    </tr>
    <tr><td colspan="2">Run pre-commit linters scoped to changed files. <strong>Not part of the plugin surface; each consuming repo provides its own.</strong></td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#research"><code>/research</code></a></td>
      <td><code>[--debug] &lt;research question or topic&gt;</code></td>
    </tr>
    <tr><td colspan="2">Collaborative read-only research with 3 research agents and a 3-reviewer validation panel.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#review"><code>/review</code></a></td>
      <td><code>[--debug]</code></td>
    </tr>
    <tr><td colspan="2">Code review current branch changes with a 3-reviewer panel, implementing accepted suggestions in a recursive loop.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#simplify-skill"><code>/simplify-skill</code></a></td>
      <td><code>[--debug] [--slack] &lt;skill-name&gt;</code></td>
    </tr>
    <tr><td colspan="2">Refactor a skill for stronger adherence to design principles and reduced SKILL.md footprint.</td></tr>
  </tbody>
</table>

See [docs/skills.md](docs/skills.md) for full details on each skill.

## Aliases

Shortcut skills shipped with the plugin. Each alias forwards to an existing skill with preset flags.

| Alias | Equivalent |
|---|---|
| [`/im`](skills/im/SKILL.md) | `/implement --merge` |
| [`/imaq`](skills/imaq/SKILL.md) | `/implement --merge --auto --quick` |
