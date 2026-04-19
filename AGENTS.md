# AGENTS.md

This repository **is** the larch Claude Code plugin. Editing here modifies what ships to consumers. See `README.md` for installation, features, env vars, and the full skill catalog.

## Repository layout

Plugin ships the entire repo. **Runtime surface**: `skills/`, `agents/`, `hooks/`, `scripts/`, `.claude-plugin/`. Everything else is supplementary (docs, CI config, `.claude/skills/`, dev settings).

## Editing rules

- Use `/bump-version` to change `.claude-plugin/plugin.json` version — it owns that commit; `Bump version to X.Y.Z` is a reserved commit message.
- `skills/shared/reviewer-templates.md` is the canonical source for the Code Reviewer archetype. `agents/code-reviewer.md` is generated from it via `scripts/generate-code-reviewer-agent.sh` — do not hand-edit the agent file. Edit the template and run `bash scripts/generate-code-reviewer-agent.sh` to regenerate; the `agent-sync` CI job enforces that the committed agent file matches generator output.
- Always respect `scripts/block-submodule-edit.sh`. If a hook blocks a write, investigate and resolve the underlying issue.
- After any change, run `/relevant-checks`.
- `scripts/redact-secrets.sh` is the outbound secret-scrubbing filter invoked by `skills/issue/scripts/create-one.sh` before `gh issue create`. `scripts/test-redact-secrets.sh` is its regression test, wired into `make lint` via the `test-redact` target. Edit patterns only after reading `SECURITY.md`'s outbound-redaction subsection.
- `skills/issue/scripts/parse-input.sh` parses `/issue` batch-mode input. `skills/issue/scripts/test-parse-input.sh` is its regression harness, wired into `make lint` via the `test-parse-input` target so parser regressions cannot ship undetected.
- Public `skills/*/SKILL.md` use `${CLAUDE_PLUGIN_ROOT}/…`; dev-only `.claude/skills/*/SKILL.md` use `$PWD/…`.
- Update `SECURITY.md` when security-relevant behavior changes.

## Common editing tasks

- **Changing a skill** → start at `skills/<name>/SKILL.md`, then trace every helper in `skills/<name>/scripts/`, `scripts/`, and `skills/shared/`. Behavior is split between prompt and scripts.
- **Adding/modifying the Code Reviewer archetype** → edit `skills/shared/reviewer-templates.md` (canonical), then run `bash scripts/generate-code-reviewer-agent.sh` to regenerate `agents/code-reviewer.md`. For any other reviewer archetype, follow the general rule: identify the canonical source and mirror updates to any generated outputs.
- **Changing a shared script** → edit `scripts/<name>.sh`, then grep for callers across `skills/`, `hooks/`, `.claude/settings.json`, `.github/workflows/`, and other scripts.
- **Changing dev-only skills** → edit under `.claude/skills/bump-version/` or `.claude/skills/relevant-checks/`.
- **Docs or scripts only** → classified as PATCH.
- **Dialectic smoke test** → `scripts/dialectic-smoke-test.sh` is an offline fixture-driven regression guard for `/design` Step 2a.5. Fixtures live under `tests/fixtures/dialectic/` (a non-runtime path — everything outside the named runtime surface is supplementary). Run locally with `bash scripts/dialectic-smoke-test.sh` or via `make smoke-dialectic`; CI runs it in the `smoke-dialectic` job. When changing `skills/shared/dialectic-protocol.md` Parser tolerance or Threshold Rules sections, update the smoke test and/or fixtures in the same PR.

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
- Run `gh pr create` through the skill, not manually.
- Slack env vars are optional; skills degrade gracefully when absent.
