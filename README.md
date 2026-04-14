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

The first command registers larch's marketplace manifest (`.claude-plugin/marketplace.json`). The second command installs the `larch` plugin into your Claude Code user scope. Once installed, the `/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/fix-issue`, and `/alias` slash commands become available in every Claude Code session.

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
| Skills | `/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/fix-issue`, `/alias` |
| Agents | `general-reviewer`, `deep-analysis-reviewer` |
| PreToolUse hook | `block-submodule-edit.sh` — blocks `Edit`/`Write` on files inside any checked-out git submodule of the consuming project |

### `/relevant-checks` — required consumer dependency

> **Important:** `/implement` and `/review` invoke `/relevant-checks` after each commit during their workflows. If your repo does not define one, these workflows will fail at the validation step.

The `/relevant-checks` skill is **not part of the plugin surface** — it is present in the install directory but not loaded by the plugin runtime. Each consuming repo must provide its own `/relevant-checks` as a project-level skill at `.claude/skills/relevant-checks/` with build and lint commands tailored to that repo.

**To create one for your repo:**

1. Create `.claude/skills/relevant-checks/SKILL.md` with `allowed-tools: Bash`
2. Add a `scripts/run-checks.sh` that runs your repo's linters, tests, or validators
3. Reference the script from SKILL.md using `$PWD/.claude/skills/relevant-checks/scripts/run-checks.sh`

Larch's own copy at `.claude/skills/relevant-checks/` serves as a reference implementation — it runs `pre-commit` linters plus `claude-lint` (if available on PATH).

### `--admin` merge behavior

When `/implement --merge` encounters a PR that passes CI but cannot be merged due to branch protection rules (e.g., required reviews), it retries with `gh pr merge --admin` as a fallback. The `--admin` flag overrides **all** branch protection rules including review requirements.

**Safety invariants enforced before `--admin` is attempted:**

1. All CI checks must be passing (every check in the "pass" bucket)
2. The branch must be up-to-date with main (not behind)

These checks are re-verified immediately before the `--admin` attempt — the script does not rely on cached state. See `scripts/merge-pr.sh` for the implementation.

## Prerequisites

Larch skills have different dependency requirements depending on which features you use.

### Installation

- **Claude Code** — required. Install via [setup instructions](https://code.claude.com/docs/en/setup).

### Workflow automation (`/implement --merge`, `/review`)

These tools are required for the full design → implement → PR → merge workflow:

- **git** — version control (used by all skills)
- **gh** — [GitHub CLI](https://cli.github.com/), authenticated with repo write access (`gh auth login`). Required for PR creation, CI monitoring, and merge automation.
- **jq** — [JSON processor](https://jqlang.github.io/jq/). Used by validation scripts and session setup.

### Optional integrations

These tools enhance the workflow but are not required. When unavailable, Claude replacement agents fill in automatically:

- **Codex** — [OpenAI Codex CLI](https://github.com/openai/codex). Participates as an external reviewer and voter alongside Claude subagents. When unavailable, a Claude subagent replacement maintains the reviewer count.
- **Cursor** — [Cursor AI editor](https://cursor.com/). Participates as an external reviewer and voter. When unavailable, a Claude subagent replacement maintains the reviewer count.
- **Slack** — PR announcements and `:merged:` emoji reactions. Requires environment variables or plugin `userConfig` (see [Environment Variables](#environment-variables)). When not configured, all Slack operations are skipped with a warning; all other workflow steps proceed normally.

### Contributor development

- **pre-commit** — `pip install pre-commit` for local linting (`make setup` installs git hooks)
- **Python 3.12+** — required by pre-commit

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
| [`/design`](skills/design/SKILL.md) | `[--auto] [--debug] <feature description>` | Design an implementation plan with collaborative multi-reviewer review. 5 agents (3 Claude + Cursor + Codex) independently propose architectural approaches, then 5 reviewers (2 Claude + 2 Codex + Cursor) validate the plan. `--auto` suppresses all interactive question checkpoints. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output). [(Diagram).](skills/design/diagram.svg) |
| [`/research`](skills/research/SKILL.md) | `[--debug] <research question or topic>` | Collaborative read-only research using 5 research agents (3 Claude + Cursor + Codex) then 5 validation reviewers (2 Claude + 2 Codex + Cursor). Produces a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict. Does not modify the repo. [(Diagram).](skills/research/diagram.svg) |
| [`/review`](skills/review/SKILL.md) | `[--debug]` | Code review current branch changes with specialized subagents (2 Claude + 2 Codex + Cursor, if available), implementing accepted suggestions in a recursive loop (up to 5 rounds). Reviews the diff between main and HEAD. [(Diagram).](skills/review/diagram.svg) |
| [`/implement`](skills/implement/SKILL.md) | `[--quick] [--auto] [--merge] [--debug] <feature description>` | Full end-to-end feature workflow — design, implement, PR, and Slack announce. `--quick` skips `/design` and uses simplified code review (2 Claude subagents, 1 round). `--auto` suppresses all interactive question checkpoints. `--merge` additionally runs the CI+rebase+merge loop, :merged: emoji, local branch cleanup, and main verification (without `--merge`, the PR is created and the workflow stops after the initial CI wait, Slack announcement, and reports). `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output). [(Diagram).](skills/implement/diagram.svg) |
| [`/loop-review`](skills/loop-review/SKILL.md) | `[--debug] [partition criteria]` | Systematic code review of entire repository by partitioning into slices, reviewing each with specialized subagents (2 Claude + 2 Codex + Cursor, if available), implementing improvements via `/implement`, and logging deferred suggestions. The optional argument specifies how to partition the codebase (e.g., by directory, by file type). [(Diagram).](skills/loop-review/diagram.svg) |
| [`/fix-issue`](skills/fix-issue/SKILL.md) | `[--debug] [--issue <number-or-url>]` | Process one approved GitHub issue per invocation. Fetches open issues with a `GO` sentinel comment, triages against the codebase, classifies complexity (SIMPLE/HARD), and delegates to `/implement`. With `--issue`, targets a specific issue by number or GitHub URL instead of auto-picking. Single-iteration design — the caller handles repetition. |
| [`/alias`](skills/alias/SKILL.md) | `<alias-name> <target-skill> [preset-flags...]` | Create a project-level alias for a larch skill with preset flags. Writes `.claude/skills/<name>/SKILL.md` and commits. Example: `/alias i implement --merge` creates `/i` as a shortcut for `/implement --merge`. |
| [`/relevant-checks`](.claude/skills/relevant-checks/SKILL.md) | *(none)* | Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint) scoped to files modified on the current branch. Invoked automatically by `/implement` and `/review` after code changes. **Not part of the plugin surface; each consuming repo provides its own.** |

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

Larch uses environment variables for Slack integration and external reviewer model configuration. All are optional — when not set, Slack-related features are skipped with warnings, and external reviewers use their default models.

> **Important:** Both `LARCH_SLACK_BOT_TOKEN` **and** `LARCH_SLACK_CHANNEL_ID` must be set in your shell environment for Slack features to function. If either is missing, **all** Slack operations (PR announcements, `:merged:` emoji) are skipped with a warning at session setup time identifying which variable(s) are absent. These variables must be present in the environment where `claude` is launched — they are not read from `.env` files or configuration.

**Alternative: Plugin `userConfig`** — If you installed larch as a plugin, you can also configure Slack tokens via the plugin's `userConfig` (prompted at plugin enable time). The `userConfig` values are exported as `CLAUDE_PLUGIN_OPTION_*` environment variables to subprocesses. Larch checks both: environment variables take precedence if both are set.

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

### External Reviewer Model Configuration

These variables control which model Cursor and Codex use when running as external reviewers. When unset, Cursor defaults to `composer-2-fast` and Codex uses its own configured default. The model is passed via the `--model` flag (Cursor) or `-m` flag (Codex).

Model configuration is also available via plugin `userConfig` — environment variables take precedence if both are set.

### `LARCH_CURSOR_MODEL`

The model name to pass to Cursor's `--model` flag (e.g., `gpt-5.4-medium`, `claude-sonnet-4-6`).

**When set:**
- All Cursor invocations (reviews, sketches, voting, health probes, negotiations) use this model
- The model flag is injected by `scripts/reviewer-model-args.sh`, which is called from both scripts and skill prompts

**When not set:**
- Defaults to `composer-2-fast` — Cursor's `cursor agent` CLI does not honor the model configured in `~/.cursor/cli-config.json`, so an explicit default is required to avoid falling back to a potentially rate-limited model

### `LARCH_CODEX_MODEL`

The model name to pass to Codex's `-m` flag (e.g., `o3`, `o4-mini`).

**When set:**
- All Codex invocations (reviews, sketches, voting, health probes, negotiations) use this model
- The model flag is injected by `scripts/reviewer-model-args.sh`, which is called from both scripts and skill prompts

**When not set:**
- Codex runs without an explicit `-m` flag, using its own configured default

## Detailed Documentation

- [Workflow Lifecycle](docs/workflow-lifecycle.md) — How skills compose to form the end-to-end development workflow
- [Voting Process](docs/voting-process.md) — The 3-agent voting panel that adjudicates review findings
- [Point Competition](docs/point-competition.md) — Reviewer scoring system and competition mechanics
- [Collaborative Sketches](docs/collaborative-sketches.md) — The diverge-then-converge design phase
- [External Reviewers](docs/external-reviewers.md) — Codex and Cursor integration procedures
- [Review Agents](docs/review-agents.md) — The 2 specialized Claude reviewer archetypes
- [Agent System](docs/agents.md) — How skills orchestrate parallel subagents
