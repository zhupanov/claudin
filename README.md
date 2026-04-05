# Claudin

Claudin is a Claude Code workflow automation framework that orchestrates multi-agent design, code review, and implementation through collaborative AI-driven processes.

## Getting Started

There are two ways to integrate claudin into your repository:

- **Flow A (Git Submodule)** — recommended for teams that want automatic upstream updates
- **Flow B (Copy Skills)** — for teams that want to vendor a subset of skills and own them

Both flows require environment variables for Slack integration (see [Environment Variables](#environment-variables) below). If you don't use Slack, you can skip them — skills degrade gracefully when Slack is not configured.

### Flow A — Git Submodule

Add claudin as a submodule and use `update-claudin.sh` to create symlinks from your `.claude/` directory into the submodule:

```bash
# 1. Add the submodule
git submodule add <claudin-repo-url> claudin
git commit -m "Add claudin submodule"

# 2. Create symlinks from .claude/ into claudin/.claude/
./claudin/update-claudin.sh

# 3. Commit the symlinks and any new directories
git add .claude
git commit -m "Set up claudin symlinks"
```

**Updating to the latest version**: Every time you bump the claudin submodule to a newer version, re-run the update script to sync symlinks (create new ones, remove stale ones):

```bash
git submodule update --remote claudin
git add claudin
./claudin/update-claudin.sh
git add .claude
git commit -m "Bump claudin submodule"
```

**How it works**: `update-claudin.sh` creates symlinks from your `.claude/` directory tree into `claudin/.claude/`. Skill directories (those containing `SKILL.md`) get directory-level symlinks, while individual files (scripts, agents, shared docs) get file-level symlinks. Your repo can have its own additional skills, scripts, and agents alongside the symlinked ones.

**Important notes**:

- **`settings.json` is not symlinked.** Your repo must maintain its own `.claude/settings.json` with the permission entries needed by claudin scripts. The recommended approach is to copy the `permissions.allow` array from claudin's `settings.json` as a baseline. At minimum, include bash permissions for `$PWD/.claude/scripts/generic/*`, `$PWD/.claude/skills/*/scripts/*` (for skill-specific scripts), and the `block-submodule-edit.sh` hook.
- **Edits to `claudin/` are blocked.** The `block-submodule-edit.sh` hook prevents Claude Code from editing files inside git submodules. This is intentional — changes to claudin should be made via PRs to the claudin repo, then pulled in by updating the submodule.
- **Conflicts**: If a non-symlink file or directory already exists at a path the script needs to symlink, it exits with an error. Resolve the conflict manually (rename or remove the existing file) and re-run.

### Flow B — Copy Selected Skills

Copy the skills you need along with their shared dependencies into your repo's `.claude/` directory. Understanding the directory structure is essential to avoid missing dependencies.

#### Directory structure

```
.claude/
├── settings.json              # Permission and hook configuration (write your own)
├── agents/                    # Reviewer agent definitions (.md files)
│   ├── generic-reviewer.md
│   ├── correctness-reviewer.md
│   ├── risk-reviewer.md
│   └── architect-reviewer.md
├── scripts/
│   └── generic/               # ~37 reusable shell scripts invoked by skills
│       ├── session-setup.sh
│       ├── create-pr.sh
│       ├── ci-wait.sh
│       └── ...
└── skills/
    ├── shared/                # Shared .md files referenced by multiple skills
    │   ├── voting-protocol.md
    │   ├── reviewer-templates.md
    │   └── external-reviewers.md
    ├── design/                # Each skill directory contains SKILL.md
    │   ├── SKILL.md           #   and may include scripts/, agents/,
    │   └── diagram.svg        #   references/, assets/, diagrams
    ├── implement/
    │   ├── SKILL.md
    │   ├── scripts/
    │   └── diagram.svg
    └── ...
```

#### What to copy

When copying a skill, you must also copy its shared dependencies:

1. **The skill directory** — e.g., `.claude/skills/design/` (the entire directory including any nested `scripts/`, `agents/`, etc.)
2. **`.claude/skills/shared/`** — shared markdown files referenced by all review-related skills. **Always copy this.**
3. **`.claude/scripts/generic/`** — shell scripts that skills invoke for git operations, CI, Slack, etc. **Always copy this.**
4. **`.claude/agents/`** — reviewer agent definitions used by `/design`, `/review`, and `/loop-review`. Copy if using any review-related skill.

#### Transitive skill dependencies

Skills invoke other skills. If you copy `/shazam`, you also need `/implement`, `/design`, `/review`, and `/relevant-checks`. The dependency chain:

- `/shazam` → `/implement` → `/design`, `/review`, `/relevant-checks`
- `/loop-review` → `/shazam` (full chain above)
- `/implement` → `/design`, `/review`, `/relevant-checks`

#### Note on `/relevant-checks`

The `/relevant-checks` skill is **repo-specific** — its `SKILL.md` contains build and lint commands tailored to a specific repository. When copying it, treat it as a **template that must be rewritten** for your repo's build system. It will not work as-is.

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
| [`/relevant-checks`](.claude/skills/relevant-checks/SKILL.md) | *(none)* | Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint, ruff) scoped to files modified on the current branch. Invoked automatically by `/implement` and `/review` after code changes. |

## Review Agents

Internal agent definitions used by skills like `/design`, `/review`, and `/loop-review`. They are not invoked directly — the skills launch them as specialized subagents during plan and code review.

| Agent | Description |
|---|---|
| [`generic-reviewer`](.claude/agents/generic-reviewer.md) | General-purpose code reviewer for bugs, logic, quality, tests, backward compatibility, and style consistency. |
| [`correctness-reviewer`](.claude/agents/correctness-reviewer.md) | Correctness-focused code reviewer specializing in logic errors, off-by-one bugs, nil handling, type mismatches, race conditions, and error path analysis. |
| [`risk-reviewer`](.claude/agents/risk-reviewer.md) | Risk and integration reviewer specializing in breaking changes, side effects, thread safety, deployment risks, regressions, and CI impact analysis. |
| [`architect-reviewer`](.claude/agents/architect-reviewer.md) | Senior systems architect reviewer focused on separation of concerns, contract boundaries, invariants, and semantic boundary violations. |

## Linting

Claudin uses [pre-commit](https://pre-commit.com/) as the single source of truth for linter configuration. All linter definitions, versions, and file filters live in `.pre-commit-config.yaml`.

### Linters

| Linter | File Types | Description |
|--------|-----------|-------------|
| [shellcheck](https://www.shellcheck.net/) | `.sh` | Shell script analysis |
| [markdownlint](https://github.com/igorshubovych/markdownlint-cli) | `.md` | Markdown style enforcement (config: `.markdownlint.json`) |
| [jq](https://jqlang.github.io/jq/) | `.json` | JSON syntax validation |
| [actionlint](https://github.com/rhysd/actionlint) | `.yml`, `.yaml` | GitHub Actions workflow validation |
| [ruff](https://docs.astral.sh/ruff/) | `.py` | Python linting |

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
| `make ruff` | Run ruff only |
| `make setup` | Install pre-commit git hooks |

## Environment Variables

Claudin uses three environment variables for Slack integration. All are optional — when not set, Slack-related features are skipped with warnings and all other workflow steps continue normally.

> **Note:** Both `CLAUDIN_SLACK_BOT_TOKEN` and `CLAUDIN_SLACK_CHANNEL_ID` must be set for Slack features to function. If either is missing, all Slack operations (PR announcements, `:merged:` emoji) are skipped with a warning at session setup time identifying which variable(s) are absent.

### `CLAUDIN_SLACK_BOT_TOKEN`

A Slack Bot User OAuth Token (starts with `xoxb-`) used to authenticate Slack API calls.

**When set:**
- `/implement` and `/shazam` post PR announcements to Slack after creating a PR
- `/shazam` adds a `:merged:` emoji reaction to the Slack announcement after the PR is merged
- The token's presence is checked during session setup and its availability is propagated to child skills

**When not set:**
- All Slack operations are skipped with a warning at session setup (e.g., `⚠ Slack is not fully configured (CLAUDIN_SLACK_BOT_TOKEN not set). Slack announcement (Step 11) will be skipped.`)
- The `:merged:` emoji step in `/shazam` is skipped
- All other workflow steps (design, implementation, code review, CI monitoring, merge) proceed normally

### `CLAUDIN_SLACK_CHANNEL_ID`

The Slack channel ID (e.g., `C0123456789`) where PR announcements and emoji reactions are posted.

**When set:**
- PR announcements are posted to this channel
- The `:merged:` emoji reaction targets announcements in this channel

**When not set:**
- All Slack operations are skipped with a warning at session setup (e.g., `⚠ Slack is not fully configured (CLAUDIN_SLACK_CHANNEL_ID not set).`)
- The `:merged:` emoji step in `/shazam` is also skipped
- All other workflow steps proceed normally

### `CLAUDIN_SLACK_USER_ID`

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
- [Review Agents](docs/review-agents.md) — The 4 specialized Claude reviewer archetypes
- [Agent System](docs/agents.md) — How skills orchestrate parallel subagents
