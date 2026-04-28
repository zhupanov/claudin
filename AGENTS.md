# AGENTS.md

This repository **is** the larch Claude Code plugin. Editing here modifies what ships to consumers. See `README.md` for features and the skill catalog. See `docs/installation-and-setup.md` for installation and prerequisites, `docs/configuration-and-permissions.md` for env vars and permissions, and `docs/linting.md` for Makefile targets and linters.

## Repository layout

Plugin ships the entire repo. **Runtime surface**: `skills/`, `agents/`, `hooks/`, `scripts/`, `.claude-plugin/`. Everything else is supplementary (docs, CI config, `.claude/skills/`, dev settings).

## Editing rules

- Use `/bump-version` to change `.claude-plugin/plugin.json` version — it owns that commit; `Bump version to X.Y.Z` is a reserved commit message.
- Always respect `scripts/block-submodule-edit.sh`. If a hook blocks a write, investigate and resolve the underlying issue. The guard ships via `hooks/hooks.json` only — `.claude/settings.json` no longer mirrors it, so contributors developing in this repo must load larch as a plugin (`claude --plugin-dir .` or the local marketplace) to pick up the guard.
- After any change, run `/relevant-checks`.
- Public `skills/*/SKILL.md` use `${CLAUDE_PLUGIN_ROOT}/…`; dev-only `.claude/skills/*/SKILL.md` use `$PWD/…`.
- Update `SECURITY.md` when security-relevant behavior changes.
- **Per-script contracts live beside the script.** Scripts and test harnesses under `scripts/` and `skills/<name>/scripts/` have a sibling `<basename>.md` next to them (e.g., `scripts/redact-secrets.md` beside `scripts/redact-secrets.sh`) documenting the script's purpose, invariants, Makefile wiring, test harness, and edit-in-sync rules. When editing a script, read its sibling `.md` first; update it in the same PR as any behavioral change. Where a bullet covered multiple related files (a script plus its sourced library and test harness), the primary script's sibling `.md` owns the full contract and cites the related files by path. For canonical documentation files (`skills/shared/*.md`), update triggers live inside the file itself at the bottom.

## Common editing tasks

- **Changing a skill** → start at `skills/<name>/SKILL.md`, then trace every helper in `skills/<name>/scripts/`, `scripts/`, and `skills/shared/`. Behavior is split between prompt and scripts.
- **Adding/modifying the Code Reviewer archetype** → edit `skills/shared/reviewer-templates.md` (canonical; update triggers in that file), then run `bash scripts/generate-code-reviewer-agent.sh` to regenerate `agents/code-reviewer.md`. For any other reviewer archetype, follow the general rule: identify the canonical source and mirror updates to any generated outputs.
- **Changing a shared script** → edit `scripts/<name>.sh`, read its sibling `scripts/<name>.md` for the contract, then grep for callers across `skills/`, `hooks/`, `.claude/settings.json`, `.github/workflows/`, and other scripts.
- **Changing dev-only skills** → edit under `.claude/skills/bump-version/` or `.claude/skills/relevant-checks/`.
- **Docs or scripts only** → classified as PATCH.

## Canonical sources

- `README.md` — feature matrix, skill catalog, Aliases
- `docs/installation-and-setup.md` — installation, setup recipes, prerequisites
- `docs/configuration-and-permissions.md` — strict-permissions Skill entries, `--admin` merge behavior, env vars
- `docs/linting.md` — linters, Makefile targets, halt-rate regression harness
- `docs/workflow-lifecycle.md` — how skills compose end-to-end
- `docs/voting-process.md`, `docs/point-competition.md` — review mechanics
- `docs/agents.md`, `docs/review-agents.md` — subagent orchestration
- `docs/external-reviewers.md`, `docs/collaborative-sketches.md` — Codex/Cursor integration
- `.claude/skills/bump-version/SKILL.md` — authoritative version classification rules
- `skills/shared/subskill-invocation.md` — sub-skill invocation conventions (invocation patterns, `allowed-tools` narrowing, post-invocation verification, anti-halt continuation reminder, session-env handoff)
- `skills/shared/skill-design-principles.md` — design principles for every larch skill (knowledge delta, structure, mechanical rules A/B/C, writing style, anti-patterns, freedom calibration); Section III overrides Section IV for larch skills
- `skills/shared/reviewer-templates.md` — Code Reviewer archetype (canonical; `agents/code-reviewer.md` is generated from it)
- `SECURITY.md` — security policy

## Conventions

- Shell scripts use `set -euo pipefail` by default. Comment when `-e` is intentionally omitted.
- Follow recent commit history style. `Bump version to X.Y.Z` is reserved for `/bump-version`.
- Run `gh pr create` through the skill, not manually.
- Run `gh issue create` through `/larch:issue`, not manually. Scripts under `scripts/` and `skills/*/scripts/` (e.g., hooks) may continue to call `gh issue create` directly — the rule targets interactive / assistant-driven issue creation only.
- Slack env vars are optional; skills degrade gracefully when absent.
