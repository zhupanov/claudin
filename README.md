# Larch

Larch is a Claude Code workflow automation framework that orchestrates multi-agent design, code review, and implementation through collaborative AI-driven processes.

## Table of Contents

- **Setup**
  - [Installation and Setup](docs/installation-and-setup.md) — plugin install, local development, agent setup recipes (Claude / Codex / Cursor), what the plugin provides, `/relevant-checks` consumer dependency, prerequisites
  - [Configuration and Permissions](docs/configuration-and-permissions.md) — [Strict-permissions consumers](docs/configuration-and-permissions.md#strict-permissions-consumers--skill-permission-entries), [`--admin` merge behavior](docs/configuration-and-permissions.md#--admin-merge-behavior), [Environment Variables](docs/configuration-and-permissions.md#environment-variables) (`LARCH_SLACK_*`, `LARCH_CURSOR_MODEL`, `LARCH_CODEX_MODEL`, `LARCH_CODEX_EFFORT`, `LARCH_BUMP_FILES`)
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

- **[Multi-agent design planning, reviews, and adjudication](docs/collaborative-sketches.md)** — 9 sketch agents in regular mode (3 in quick mode) diverge, a dialectic 3-judge binary panel resolves contested decisions, and a 3-reviewer panel validates the final plan.
- **[Voting-based review resolution](docs/voting-process.md)** — A 3-agent YES/NO/EXONERATE panel adjudicates plan and code review findings.
- **[Reviewer competition scoring](docs/point-competition.md)** — Reviewers earn points based on finding quality; a scoreboard tracks accepted, neutral, exonerated, and rejected findings.
- **[End-to-end automation](docs/workflow-lifecycle.md)** — From feature design through PR creation and initial CI wait in one command; `--merge` adds the CI+rebase+merge loop, local cleanup, and main verification. Each run also posts a single Slack status message about its tracking issue near the end (✅ closed / 📝 PR opened / ❌ blocked / ❓ user input needed) when Slack is configured — opt out with `--no-slack`. `--draft` creates a draft PR and keeps the branch for further iteration.
- **[External reviewer integration](docs/external-reviewers.md)** — Codex and Cursor participate alongside Claude subagents as sketch agents, debaters, judges, reviewers, and voters.
- **[Tracked runs](skills/implement/SKILL.md)** — `/implement` PRs link to a tracking issue whose anchor comment is the single source of truth for full report content (voting tallies, rejected findings, version-bump reasoning, diagrams, OOS links, execution issues, run statistics).

## Skills

<table>
  <thead>
    <tr><th>Name</th><th>Arguments</th></tr>
  </thead>
  <tbody>
    <tr>
      <td><a href="docs/skills.md#alias"><code>/alias</code></a></td>
      <td><code>[--merge] [--no-slack] [--private] &lt;alias-name&gt; &lt;target-skill&gt; [preset-flags...]</code></td>
    </tr>
    <tr><td colspan="2">Create an alias for a larch skill with preset flags. Auto-routes to <code>skills/&lt;n&gt;/</code> in plugin source repos and <code>.claude/skills/&lt;n&gt;/</code> elsewhere; <code>--private</code> forces the latter.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#compress-skill"><code>/compress-skill</code></a></td>
      <td><code>[--debug] [--no-slack] &lt;skill-name-or-path&gt;</code></td>
    </tr>
    <tr><td colspan="2">Compress a skill's Markdown prose via a behavior-preserving rewrite.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#create-skill"><code>/create-skill</code></a></td>
      <td><code>[--plugin] [--multi-step] [--merge] [--debug] [--no-slack] &lt;skill-name&gt; &lt;description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Scaffold a new larch-style skill from a name and description.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#design"><code>/design</code></a></td>
      <td><code>[--auto] [--quick] [--debug] &lt;feature description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Design an implementation plan with 9 sketch agents (3 in quick mode), dialectic adjudication, and a 3-reviewer validation panel.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#fix-issue"><code>/fix-issue</code></a></td>
      <td><code>[--debug] [--no-slack] [--no-admin-fallback] [&lt;number-or-url&gt;]</code></td>
    </tr>
    <tr><td colspan="2">Process one approved GitHub issue per invocation, classifying intent and delegating PR work to <code>/implement</code>.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#implement"><code>/implement</code></a></td>
      <td><code>[--quick] [--auto] [--merge | --draft] [--no-slack] [--no-admin-fallback] [--debug] [--issue &lt;N&gt;] &lt;feature description&gt;</code></td>
    </tr>
    <tr><td colspan="2">Full end-to-end feature workflow — design, implement, PR. <code>--quick</code> skips <code>/design</code> and runs a simplified single-reviewer loop of up to 7 rounds with a per-round Cursor → Codex → Claude fallback chain (no voting panel).</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#issue"><code>/issue</code></a></td>
      <td><code>[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [&lt;issue description&gt;]</code></td>
    </tr>
    <tr><td colspan="2">Create one or more GitHub issues with LLM-based semantic duplicate detection and always-on inter-issue blocker-dependency analysis.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#relevant-checks"><code>/relevant-checks</code></a></td>
      <td><em>(none)</em></td>
    </tr>
    <tr><td colspan="2">Run pre-commit linters scoped to changed files. <strong>Not part of the plugin surface; each consuming repo provides its own.</strong></td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#research"><code>/research</code></a></td>
      <td><code>[--debug] [--plan] [--interactive] [--scale=quick|standard|deep] [--adjudicate] [--keep-sidecar[=PATH]] [--token-budget=N] [--no-issue] &lt;research question or topic&gt;</code></td>
    </tr>
    <tr><td colspan="2">Collaborative best-effort read-only research with adaptive scaling (<code>quick</code> / <code>standard</code> / <code>deep</code>) chosen by a deterministic classifier or via <code>--scale=...</code>. Every run includes unconditional citation validation (HEAD-fetches cited URLs under SSRF guards, validates DOIs, spot-checks file:line refs) emitted as a fail-soft PASS / FAIL / UNKNOWN ledger spliced into the final report.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#review"><code>/review</code></a></td>
      <td><code>[--debug]</code></td>
    </tr>
    <tr><td colspan="2">Code review current branch changes with a 6-reviewer specialist panel (5 Cursor specialists + 1 Codex generic), implementing accepted suggestions in a recursive loop.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#simplify-skill"><code>/simplify-skill</code></a></td>
      <td><code>[--debug] [--no-slack] &lt;skill-name&gt;</code></td>
    </tr>
    <tr><td colspan="2">Refactor a skill for stronger adherence to design principles and reduced SKILL.md footprint.</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#skill-evolver"><code>/skill-evolver</code></a></td>
      <td><code>[--debug] &lt;skill-name&gt;</code></td>
    </tr>
    <tr><td colspan="2">Evolve an existing larch skill by running <code>/research --scale=deep</code> against repo-local sibling skills and reputable external sources, then delegating any actionable findings to <code>/umbrella</code> (research-and-file-issues only — does not modify the target skill's files).</td></tr>
    <tr><td colspan="2"><hr></td></tr>
    <tr>
      <td><a href="docs/skills.md#umbrella"><code>/umbrella</code></a></td>
      <td><code>[--label L]... [--title-prefix P] [--repo OWNER/REPO] [--closed-window-days N] [--dry-run] [--go] [--debug] &lt;task description or empty to deduce from context&gt;</code></td>
    </tr>
    <tr><td colspan="2">Plan-to-issues orchestrator: classifies a task description as one-shot or multi-piece, delegates GitHub issue creation to <code>/issue</code> (batch mode plus an umbrella tracking issue when multi-piece), and wires native blocked-by edges plus child→umbrella back-links. Typically invoked transitively by <code>/review --create-issues</code> and <code>/skill-evolver</code>.</td></tr>
  </tbody>
</table>

See [docs/skills.md](docs/skills.md) for full details on each skill.

## Aliases

Shortcut skills shipped with the plugin. Each alias forwards to an existing skill with preset flags.

| Alias | Equivalent |
|---|---|
| [`/im`](skills/im/SKILL.md) | `/implement --merge` |
| [`/imaq`](skills/imaq/SKILL.md) | `/implement --merge --auto --quick` |
