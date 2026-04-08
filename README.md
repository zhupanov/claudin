# Larch

Larch is a Claude Code workflow automation framework that orchestrates multi-agent design, code review, and implementation through collaborative AI-driven processes.

## Installation

Larch is distributed as a [Claude Code plugin](https://code.claude.com/docs/en/plugin-marketplaces). Installation is a two-step process: register the marketplace that hosts larch, then install the plugin from that marketplace.

Slack integration is optional. See [Environment Variables](#environment-variables) below — skills degrade gracefully when Slack is not configured.

### Install from GitHub

```bash
claude plugin marketplace add zhupanov/larch
claude plugin install larch@larch-local
```

The first command registers larch's marketplace manifest (`.claude-plugin/marketplace.json`). The second command installs the `larch` plugin into your Claude Code user scope. Once installed, the `/design`, `/implement`, `/review`, `/research`, and `/loop-review` slash commands become available in every Claude Code session.

To scope the install to a single project instead of the user scope, append `--scope project` to the `install` command.

### Install for local development (contributors)

If you are hacking on larch itself and want Claude Code to load the plugin directly from your working checkout (so `${CLAUDE_PLUGIN_ROOT}` resolves to the repo you are editing), launch Claude Code with `--plugin-dir`:

```bash
git clone https://github.com/zhupanov/larch.git
cd larch
claude --plugin-dir .
```

Alternatively, add the working checkout as a local marketplace and install from it:

```bash
cd larch
claude plugin marketplace add .
claude plugin install larch@larch-local
```

### What the plugin provides

| Component | Description |
|---|---|
| Skills | `/design`, `/implement`, `/review`, `/research`, `/loop-review` |
| Agents | `general-reviewer`, `deep-analysis-reviewer` |
| PreToolUse hook | `block-submodule-edit.sh` — blocks `Edit`/`Write` on files inside any checked-out git submodule of the consuming project |

### `/relevant-checks` is repo-specific (not part of the plugin)

The `/relevant-checks` skill is **intentionally not shipped by the larch plugin**. Each consuming repo must provide its own `/relevant-checks` as a project-level skill at `.claude/skills/relevant-checks/` with build and lint commands tailored to that repo. Larch's own copy lives at `.claude/skills/relevant-checks/` in this repo as a reference implementation. The `/implement` and `/review` workflows invoke `/relevant-checks` after each commit, so your repo must define one for those workflows to run cleanly.

## Features

- **Multi-agent design planning** — 5 agents independently propose architectural approaches before a full implementation plan is written, preventing anchoring bias
- **Voting-based review resolution** — A 3-agent voting panel (YES/NO/EXONERATE) adjudicates review findings for both plan review and code review
- **Reviewer competition scoring** — Reviewers earn points based on finding quality, with a scoreboard tracking accepted, neutral, exonerated, and rejected findings
- **End-to-end automation** — From feature design through PR creation, initial CI wait, and Slack announcement in a single command. With `--merge`, also runs the CI+rebase+merge loop, :merged: emoji, local branch cleanup, and main verification
- **External reviewer integration** — Codex and Cursor participate alongside Claude subagents as both reviewers and voters
- **Systematic codebase review** — Partition an entire repository into slices, review each with specialized subagents, and implement improvements automatically

## Skills

Slash commands available in Claude Code sessions. They automate multi-step workflows by orchestrating git, GitHub, Slack, and other tools.

| Command | Arguments | Description |
|---|---|---|
| [`/design`](skills/design/SKILL.md) | `[--auto] <feature description>` | Design an implementation plan with collaborative multi-reviewer review. 5 agents (3 Claude + Cursor + Codex) independently propose architectural approaches, then 5 reviewers (2 Claude + 2 Codex + Cursor) validate the plan. `--auto` suppresses all interactive question checkpoints. [(Diagram).](skills/design/diagram.svg) |
| [`/research`](skills/research/SKILL.md) | `<research question or topic>` | Collaborative read-only research using 5 research agents (3 Claude + Cursor + Codex) then 5 validation reviewers (2 Claude + 2 Codex + Cursor). Produces a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict. Does not modify the repo. [(Diagram).](skills/research/diagram.svg) |
| [`/review`](skills/review/SKILL.md) | *(none)* | Code review current branch changes with specialized subagents (2 Claude + 2 Codex + Cursor, if available), implementing accepted suggestions in a recursive loop (up to 5 rounds). Reviews the diff between main and HEAD. [(Diagram).](skills/review/diagram.svg) |
| [`/implement`](skills/implement/SKILL.md) | `[--quick] [--auto] [--merge] <feature description>` | Full end-to-end feature workflow — design, implement, PR, and Slack announce. `--quick` skips `/design` and uses simplified code review (2 Claude subagents, 1 round). `--auto` suppresses all interactive question checkpoints. `--merge` additionally runs the CI+rebase+merge loop, :merged: emoji, local branch cleanup, and main verification (without `--merge`, the PR is created and the workflow stops after the initial CI wait, Slack announcement, and reports). [(Diagram).](skills/implement/diagram.svg) |
| [`/loop-review`](skills/loop-review/SKILL.md) | `[partition criteria]` | Systematic code review of entire repository by partitioning into slices, reviewing each with specialized subagents (2 Claude + 2 Codex + Cursor, if available), implementing improvements via `/implement`, and logging deferred suggestions. The optional argument specifies how to partition the codebase (e.g., by directory, by file type). [(Diagram).](skills/loop-review/diagram.svg) |
| [`/relevant-checks`](.claude/skills/relevant-checks/SKILL.md) | *(none)* | Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint) scoped to files modified on the current branch. Invoked automatically by `/implement` and `/review` after code changes. **Repo-private; not shipped by the plugin.** |

## Review Agents

Internal agent definitions used by skills like `/design`, `/review`, and `/loop-review`. They are not invoked directly — the skills launch them as specialized subagents during plan and code review.

| Agent | Description |
|---|---|
| [`general-reviewer`](agents/general-reviewer.md) | General-purpose code reviewer covering bugs, logic, quality, tests, backward compatibility, style consistency, breaking changes, deployment risks, regressions, and CI impact. |
| [`deep-analysis-reviewer`](agents/deep-analysis-reviewer.md) | Deep analysis reviewer combining correctness (logic errors, off-by-one bugs, nil handling, type mismatches, race conditions) with architectural rigor (separation of concerns, contract boundaries, invariants, semantic boundaries). |

## Linting

Larch uses [pre-commit](https://pre-commit.com/) as the single source of truth for linter configuration. All linter definitions, versions, and file filters live in `.pre-commit-config.yaml`.

### Linters

| Linter | File Types | Description |
|--------|-----------|-------------|
| [shellcheck](https://www.shellcheck.net/) | `.sh` | Shell script analysis |
| [markdownlint](https://github.com/igorshubovych/markdownlint-cli) | `.md` | Markdown style enforcement (config: `.markdownlint.json`) |
| [jq](https://jqlang.github.io/jq/) | `.json` | JSON syntax validation |
| [actionlint](https://github.com/rhysd/actionlint) | `.yml`, `.yaml` | GitHub Actions workflow validation |

### Usage

There are three ways to run linters, all backed by the same `.pre-commit-config.yaml`:

- **CI** — Runs `make lint` (repo-wide) on every pull request.
- **`/relevant-checks`** — Runs `pre-commit run --files <changed-files>` scoped to branch changes. Invoked automatically by `/implement` and `/review`.
- **Local git hook** — Run `make setup` (or `pre-commit install`) to enable pre-commit hooks that lint staged files on every commit.

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make lint` | Run all linters repo-wide |
| `make shellcheck` | Run shellcheck only |
| `make markdownlint` | Run markdownlint only |
| `make jsonlint` | Run JSON validation only |
| `make actionlint` | Run actionlint only |
| `make setup` | Install pre-commit git hooks |

## Environment Variables

Larch uses three environment variables for Slack integration. All are optional — when not set, Slack-related features are skipped with warnings and all other workflow steps continue normally.

> **Note:** Both `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID` must be set for Slack features to function. If either is missing, all Slack operations (PR announcements, `:merged:` emoji) are skipped with a warning at session setup time identifying which variable(s) are absent.

### `LARCH_SLACK_BOT_TOKEN`

A Slack Bot User OAuth Token (starts with `xoxb-`) used to authenticate Slack API calls.

**When set:**
- `/implement` posts PR announcements to Slack after creating a PR
- `/implement` adds a `:merged:` emoji reaction to the Slack announcement after the PR is merged
- The token's presence is checked during session setup and its availability is propagated to child skills

**When not set:**
- All Slack operations are skipped with a warning at session setup (e.g., `⚠ Slack is not fully configured (LARCH_SLACK_BOT_TOKEN not set). Slack announcement (Step 11) will be skipped.`)
- The `:merged:` emoji step in `/implement` is skipped
- All other workflow steps (design, implementation, code review, CI monitoring, merge) proceed normally

### `LARCH_SLACK_CHANNEL_ID`

The Slack channel ID (e.g., `C0123456789`) where PR announcements and emoji reactions are posted.

**When set:**
- PR announcements are posted to this channel
- The `:merged:` emoji reaction targets announcements in this channel

**When not set:**
- All Slack operations are skipped with a warning at session setup (e.g., `⚠ Slack is not fully configured (LARCH_SLACK_CHANNEL_ID not set).`)
- The `:merged:` emoji step in `/implement` is also skipped
- All other workflow steps proceed normally

### `LARCH_SLACK_USER_ID`

A Slack user ID (e.g., `U0123456789`) used to @-mention the PR author in Slack announcements.

**When set:**
- Slack announcements include an @-mention of this user, notifying them directly in the channel

**When not set:**
- Slack announcements are still posted, but without an @-mention — the message appears without a user notification

## Detailed Documentation

- [Workflow Lifecycle](docs/workflow-lifecycle.md) — How skills compose to form the end-to-end development workflow
- [Voting Process](docs/voting-process.md) — The 3-agent voting panel that adjudicates review findings
- [Point Competition](docs/point-competition.md) — Reviewer scoring system and competition mechanics
- [Collaborative Sketches](docs/collaborative-sketches.md) — The diverge-then-converge design phase
- [External Reviewers](docs/external-reviewers.md) — Codex and Cursor integration procedures
- [Review Agents](docs/review-agents.md) — The 2 specialized Claude reviewer archetypes
- [Agent System](docs/agents.md) — How skills orchestrate parallel subagents
