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
- `${CLAUDE_PLUGIN_ROOT}/scripts/sessionstart-health.sh` is the SessionStart preflight hook that probes `jq` and `git` on `PATH` at session start and injects an advisory into session context when either is missing. `${CLAUDE_PLUGIN_ROOT}/scripts/test-sessionstart-health.sh` is its regression test, wired into `make lint` via the `test-sessionstart` target (run manually via `bash ${CLAUDE_PLUGIN_ROOT}/scripts/test-sessionstart-health.sh`). The hook MUST always exit 0 (SessionStart is non-blocking by spec) and the `additionalContext` string MUST remain fixed ASCII literals — see the invariant comment in the script.
- `scripts/audit-edit-write.sh` is a dev-only PostToolUse audit hook for `Edit`/`Write` tool use. It is shipped in the plugin install tree but is **not registered by default** in `hooks/hooks.json` or `.claude/settings.json`; contributors opt in locally by adding a `PostToolUse` entry to `.claude/settings.local.json` (gitignored). Appends one JSONL record per invocation to `.claude/hook-audit.log` (also gitignored). `scripts/test-audit-edit-write.sh` is its regression harness, wired into `make lint` via the `test-audit-edit-write` target. See `docs/dev-hook-audit.md` for enable/rotate/privacy details and `SECURITY.md` for the security posture.
- `scripts/block-submodule-edit.sh` is the PreToolUse hook that denies edits to files inside submodules. `scripts/test-block-submodule-edit.sh` is its regression harness, wired into `make lint` via the `test-block-submodule` target; edits to the hook must stay in sync with the harness.
- `scripts/deny-edit-write.sh` is the skill-scoped PreToolUse deny hook registered in `skills/research/SKILL.md`'s `hooks:` frontmatter — it denies `Edit|Write|NotebookEdit` while `/research` is active by emitting a fixed `hookSpecificOutput` JSON deny envelope. The script ignores stdin (the matcher already restricts the trigger), is composed only of fixed ASCII literals (no runtime interpolation into the deny JSON), and always exits 0 — when `jq` is present it composes the JSON via `jq -cn`; when `jq` is absent it falls back to a byte-identical static `printf`, so the deny semantics never depend on `jq` availability. This mirrors the `jq`-absent precedent in `scripts/block-submodule-edit.sh`. This is a defense-in-depth second layer; the primary mechanical control remains the `allowed-tools` frontmatter that omits `Edit`/`Write`/`Skill` (see `SECURITY.md`). `scripts/test-deny-edit-write.sh` is its regression harness, wired into `make lint` via the `test-deny-edit-write` target; the harness FAILs (exit 1) when its own `jq` is missing because the assertions need a JSON parser, and it exercises both the `jq` and `printf` fallback branches to enforce the byte-identity invariant. Edits to the hook must stay in sync with the harness. The test script is added to `agent-lint.toml`'s exclude list because agent-lint's dead-script rule does not follow Makefile-only references.
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
