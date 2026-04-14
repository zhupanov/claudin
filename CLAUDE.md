# CLAUDE.md

This repository **is** the larch Claude Code plugin. When you edit here, you are modifying the plugin that ships to consumers. See `README.md` for installation, feature matrix, env vars, and the full skill catalog — do not duplicate that content in this file.

This file orients editing agents. Every rule below is framed as an invariant to prevent a mistake Claude would otherwise make.

## Repository layout — two independent axes

larch has two overlapping but distinct classifications. Treat them separately when reasoning about a change.

### Axis A — Plugin surface (active at runtime) vs. supplementary files

The plugin source (`"./"` in `marketplace.json`) ships the **entire repository** to consumers — every file below is physically present in the consumer's plugin install directory. The distinction here is about what the plugin runtime references, not what is physically present.

**Plugin surface (referenced at runtime by skills, hooks, and scripts):**

- `skills/` — public skills (`/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/alias`)
- `agents/` — reviewer archetype definitions
- `hooks/hooks.json` — `PreToolUse` hook registrations
- `scripts/` — invoked from shipped skills and hooks as `${CLAUDE_PLUGIN_ROOT}/scripts/…`
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — plugin manifests

**Supplementary (shipped but not referenced by plugin code at runtime):**

- `docs/` — prose documentation (linked from `README.md` with relative paths, readable locally by consumers)
- `README.md`, `CHANGELOG.md`, `SECURITY.md` — project-level documentation
- `.github/`, `Makefile`, `.pre-commit-config.yaml`, `.markdownlint.json` — CI and linter configuration
- `.claude/skills/bump-version/` — version classifier and applier; reference implementation for consumers (each consumer repo provides its own); invoked during plugin development by `/implement` Steps 8, 10, 12
- `.claude/skills/relevant-checks/` — reference implementation; each consumer repo provides its own
- `.claude/settings.json` — local Claude Code harness config (permissions, dev hooks); not loaded when installed via the marketplace (only active for `--plugin-dir .` development)

**Shared fragments (not a skill):** `skills/shared/` — reviewer templates, voting protocol, external-reviewer conventions. No `SKILL.md`.

### Axis B — What drives MAJOR/MINOR version bumps

**Only `skills/**` and `agents/**` drive MAJOR/MINOR classification.** Changes under every other directory — including shipped `scripts/`, `hooks/`, and `.claude-plugin/` — default to **PATCH**. Authority: `.claude/skills/bump-version/SKILL.md` and `.claude/skills/bump-version/scripts/classify-bump.sh`.

Inside `skills/**` and `agents/**`, the specific triggers are:

- **MAJOR**: deleting or renaming a `SKILL.md`/agent file, changing its `name:` frontmatter, or removing a `--flag` token from `argument-hint:`
- **MINOR**: adding a new `SKILL.md`/agent file, or adding a `--flag` token to `argument-hint:`
- **PATCH**: everything else

The main agent may **escalate** severity (never downgrade) for backward-incompatible behavioral changes anywhere in the diff — see the escalation-only caveat in `.claude/skills/bump-version/SKILL.md`.

## Golden rules for edits

These invariants are what an editing agent will otherwise get wrong.

### Path conventions

- Public `skills/*/SKILL.md` **MUST** use `${CLAUDE_PLUGIN_ROOT}/…` — never `$PWD`, `${PWD}`, or hardcoded absolute paths. Enforced by validator 8 in `scripts/validate-plugin-structure.sh`.
- `hooks/hooks.json` SHOULD also use `${CLAUDE_PLUGIN_ROOT}/…`. **This is a convention, not validator-enforced** — validator 8 only scans `skills/*/SKILL.md`.
- Development-only `.claude/skills/*/SKILL.md` intentionally use `$PWD/…` and are exempt from the hygiene check by design.

### Version and release

- **Never hand-edit `.claude-plugin/plugin.json`'s `version` field.** `/bump-version` owns that commit and is invoked automatically by `/implement` Step 8. The commit message `Bump version to X.Y.Z` is reserved for this skill.

### Scripts and references

- **Dead-script invariant**: every `scripts/*.sh` must have a structured reference somewhere in the repo. The authoritative list of accepted reference patterns (SKILL.md files, `hooks/hooks.json`, `.claude/settings.json`, workflow `run:` blocks, inter-script `$SCRIPT_DIR/` references, and fenced code blocks in `skills/shared/*.md`) is defined by **validator 11** in `scripts/validate-plugin-structure.sh` — consult its header when in doubt.
- **Script reference integrity** (validator 9): any script path referenced from a `SKILL.md` or `skills/shared/*.md` must exist on disk.
- **Executability** (validator 10): every `.sh` file under `scripts/`, `skills/*/scripts/`, and `.claude/skills/*/scripts/` must be `chmod +x`.

### SKILL.md and agents

- **Frontmatter** (validator 6): `name:` must equal `basename(dirname)`; `description:` is required.
- **Agents** (validator 7): every `agents/*.md` must have YAML frontmatter with `name:` and `description:`.
- **Reviewer archetypes must stay aligned**: `agents/<name>.md` and `skills/shared/reviewer-templates.md` are two sides of the same contract. The shared-templates file is the prompt source; the agent file is the harness registration. Never change one without the other.

### Linter configuration

- `.pre-commit-config.yaml` is the single source of truth for **hook selection and version pinning**. Tool-specific rule configuration lives in dedicated files (e.g., `.markdownlint.json`). Do not split hook definitions or versions across multiple files, but do keep tool rule files where they are.

### Validation gate

- After any change, run `/relevant-checks`. It runs `pre-commit run --files <changed>` on branch-modified files; if pre-commit passes, it additionally runs `scripts/validate-plugin-structure.sh`. This is a fast local gate — CI's `lint` job runs repo-wide `make lint`, so a local pass does not guarantee CI passes.

### Hooks

- Never disable or bypass `scripts/block-submodule-edit.sh` (wired as a `PreToolUse` hook on `Edit`/`Write`). If a hook blocks a write, investigate the path — don't work around the hook.

## Workflow entry points — slash commands

Use the bare form (matches `README.md`; see each `SKILL.md` for full argument details):

- `/design [--debug] <feature>` — collaborative plan with 5 sketch agents + 5 plan reviewers + voting panel
- `/implement [--quick] [--auto] [--merge] [--debug] <feature>` — end-to-end: design → code → PR; with `--merge` also runs the CI+rebase+merge loop
- `/review [--debug]` — code review of current branch with 2 Claude + 2 Codex + Cursor reviewers
- `/research [--debug] <topic>` — read-only research; 5 researchers + 5 validators, no repo modifications
- `/loop-review [--debug] [partition]` — systematic repo-wide review, partitioned into slices
- `/relevant-checks` — pre-commit linters + plugin-structure validator, scoped to changed files
- `/fix-issue [--debug] [--issue <number-or-url>]` — process one approved GitHub issue: triage, classify, delegate to `/implement`
- `/alias <name> <skill> [flags...]` — create a project-level alias skill in `.claude/skills/` that forwards to a larch skill with preset flags
- `/bump-version` — classify and apply the semver bump (invoked by `/implement` Step 8 and after each rebase in Steps 10/12)

Full lifecycle: `docs/workflow-lifecycle.md`.

## Common editing tasks — where to look

- **Changing a skill's behavior** → **start** at `skills/<name>/SKILL.md`, then **trace every called helper script** in `skills/<name>/scripts/`, shared scripts in `scripts/`, and shared templates in `skills/shared/` before making changes. Editing only `SKILL.md` is often incomplete — behavior is frequently split between the prompt and executable helpers.
- **Adding or modifying a reviewer archetype** → edit BOTH `agents/<name>.md` AND `skills/shared/reviewer-templates.md`; they must stay aligned.
- **Changing a shared workflow script** → edit `scripts/<name>.sh`, then grep for every caller across `skills/`, `hooks/`, `.claude/settings.json`, `.github/workflows/`, and other scripts.
- **Changing development-only skills** → edit under `.claude/skills/bump-version/` or `.claude/skills/relevant-checks/`. Classified as PATCH.
- **Docs or scripts only** → classified as PATCH. No MAJOR/MINOR impact.

## Canonical sources

Read these directly when you need depth — CLAUDE.md deliberately does not duplicate them.

- `README.md` — installation, feature matrix, env vars, skill catalog, Makefile targets
- `docs/workflow-lifecycle.md` — how skills compose end-to-end
- `docs/voting-process.md`, `docs/point-competition.md` — review mechanics
- `docs/agents.md`, `docs/review-agents.md` — subagent orchestration
- `docs/external-reviewers.md`, `docs/collaborative-sketches.md` — Codex/Cursor integration
- `.claude/skills/bump-version/SKILL.md` — authoritative version classification rules
- `scripts/validate-plugin-structure.sh` — the header comment block is the definitive structural spec (25 validators)
- `SECURITY.md` — security policy (validated by validator 14; do not delete)

## Conventions

- **Shell scripts use `set -euo pipefail` by default.** When `-e` is intentionally omitted (e.g., collect-then-report patterns in validators, CI-wait loops), add an inline comment explaining why. See the header of `scripts/validate-plugin-structure.sh` for an example of the rationale.
- Follow recent history style for commit messages. The string `Bump version to X.Y.Z` is reserved for `/bump-version`.
- PR creation, Slack posting, and CI polling are automated inside `/implement`. Do not run `gh pr create` manually from inside a workflow — drive it through the skill.
- Slack env vars (`LARCH_SLACK_BOT_TOKEN`, `LARCH_SLACK_CHANNEL_ID`, `LARCH_SLACK_USER_ID`) are optional; skills degrade gracefully with a warning at session setup when absent. Plugin `userConfig` values (`CLAUDE_PLUGIN_OPTION_SLACK_BOT_TOKEN`, etc.) are also accepted as fallbacks — env vars take precedence.
- **`SECURITY.md` must not be deleted** — validator 14 enforces its presence. Update it when security-relevant behavior changes (e.g., external tool delegation, token handling).
