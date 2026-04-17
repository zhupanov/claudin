# AGENTS.md

This repository **is** the larch Claude Code plugin. Editing here modifies what ships to consumers. See `README.md` for installation, features, env vars, and the full skill catalog.

## Repository layout

Plugin ships the entire repo. **Runtime surface**: `skills/`, `agents/`, `hooks/`, `scripts/`, `.claude-plugin/`. Everything else is supplementary (docs, CI config, `.claude/skills/`, dev settings).

## Editing rules

- Never hand-edit `.claude-plugin/plugin.json` version. `/bump-version` owns that commit; `Bump version to X.Y.Z` is a reserved commit message.
- `agents/<name>.md` and `skills/shared/reviewer-templates.md` are two sides of the same contract. Never change one without the other.
- Never disable or bypass `scripts/block-submodule-edit.sh`. If a hook blocks a write, investigate — don't work around it.
- After any change, run `/relevant-checks`.
- Public `skills/*/SKILL.md` use `${CLAUDE_PLUGIN_ROOT}/…`; dev-only `.claude/skills/*/SKILL.md` use `$PWD/…`.
- Update `SECURITY.md` when security-relevant behavior changes.

## Common editing tasks

- **Changing a skill** → start at `skills/<name>/SKILL.md`, then trace every helper in `skills/<name>/scripts/`, `scripts/`, and `skills/shared/`. Behavior is often split between prompt and scripts.
- **Adding/modifying a reviewer archetype** → edit BOTH `agents/<name>.md` AND `skills/shared/reviewer-templates.md`.
- **Changing a shared script** → edit `scripts/<name>.sh`, then grep for callers across `skills/`, `hooks/`, `.claude/settings.json`, `.github/workflows/`, and other scripts.
- **Changing dev-only skills** → edit under `.claude/skills/bump-version/` or `.claude/skills/relevant-checks/`.
- **Docs or scripts only** → classified as PATCH.

## Canonical sources

- `README.md` — installation, feature matrix, env vars, skill catalog, Makefile targets
- `docs/workflow-lifecycle.md` — how skills compose end-to-end
- `docs/voting-process.md`, `docs/point-competition.md` — review mechanics
- `docs/agents.md`, `docs/review-agents.md` — subagent orchestration
- `docs/external-reviewers.md`, `docs/collaborative-sketches.md` — Codex/Cursor integration
- `.claude/skills/bump-version/SKILL.md` — authoritative version classification rules
- `SECURITY.md` — security policy

## Conventions

- Shell scripts use `set -euo pipefail` by default. Comment when `-e` is intentionally omitted.
- Follow recent commit history style. `Bump version to X.Y.Z` is reserved for `/bump-version`.
- Do not run `gh pr create` manually — drive it through the skill.
- Slack env vars are optional; skills degrade gracefully when absent.
