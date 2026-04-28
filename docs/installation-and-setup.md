# Installation and Setup

Larch is distributed as a [Claude Code plugin](https://code.claude.com/docs/en/plugin-marketplaces). Installation is a two-step process: register the marketplace that hosts larch, then install the plugin from that marketplace.

Slack integration is optional and **on by default** when `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID` are configured. `/implement` posts a single tracking-issue status message near the end of each run; pass `--no-slack` to opt out. See [Environment Variables](configuration-and-permissions.md#environment-variables) — skills degrade gracefully when Slack is not configured.

## Install from GitHub

```bash
claude plugin marketplace add zhupanov/larch
claude plugin install larch@larch-local
```

The first command registers larch's marketplace manifest (`.claude-plugin/marketplace.json`). The second command installs the `larch` plugin into your Claude Code user scope. Once installed, all larch skills (e.g., /implement) become available in every Claude Code session.

To scope the install to a single project instead of the user scope, append `--scope project` to the `install` command.

## Install for local development (contributors)

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

## Setting Up Claude, Codex, Cursor, etc.
- **Only `claude` is mandatory.** `codex` and `cursor` are optional — when either binary is missing or fails to authenticate, larch skills substitute Claude subagents automatically. See [Optional integrations](#optional-integrations) for the full fallback semantics.
- **Larch is agent-agnostic about authentication.** Each agent can be set up either with an **API key** in your shell environment, or with a **subscription plan** via web-based login from the binary itself. Larch does not care which — it only needs the corresponding binary (`claude`, `codex`, `cursor`) to be on your `PATH` and to land in an authenticated session when invoked.
- The subsections below document one concrete setup recipe per agent (API-key path). If you prefer the subscription-plan path, install the binary and follow its own web-login flow instead — the rest of larch's configuration (settings, model overrides) still applies.

### Claude
- Via web UI of your Claude org, create your own API key
- Add it to your env (e.g., in `.bashrc`: `export ANTHROPIC_API_KEY="<your-key>"` (replace `<your-key>`, of course))
- Add/edit the following in `~/.claude/settings.json` (remember to replace `<your-API-key>` with actual value):
```JSON
  "env": {
    "CLAUDE_CODE_EFFORT_LEVEL": "high"
  },
  "model": "claude-opus-4-6",
```
- Install claude code: `curl -fsSL https://claude.ai/install.sh | bash`
- Run `claude` and verify the above settings
- **Minimum `claude` CLI version**: a build that supports `--permission-mode bypassPermissions` is required. Every `claude -p` child launched by `skills/improve-skill/scripts/iteration.sh::invoke_claude_p` carries that flag (issue #585) so an in-child tool-permission prompt cannot stall the non-interactive subprocess until the 3600s watchdog fires. The shared kernel covers both `/improve-skill` (standalone) and `/loop-improve-skill` (loop body, per-iteration). `/loop-improve-skill`'s driver also carries its own slim `invoke_claude_p` for the Step 5a post-iter-cap re-judge (1200s watchdog) which carries the same flag (issue #614, sibling to #585) — both `claude -p` launch sites in `/loop-improve-skill` (per-iteration kernel + post-iter-cap re-judge) are now pinned. See SECURITY.md `## Trust Model` for the carve-out. Older `claude` binaries that do not recognize the flag fail-fast (subprocess returns non-zero; existing `dump_subprocess_diagnostics` captures stderr); the kernel will not silently degrade. Verify with `claude --permission-mode bypassPermissions --version` if uncertain.

### Codex
- Via web UI of your Codex org, create your own API key
- Add it to your env (e.g., in `.bashrc`: `export OPENAI_API_KEY="<your-key>"` (replace `<your-key>`, of course))
- Add to `~/.codex/config.toml`:
`env_key = "OPENAI_API_KEY"`
- Install Codex: `npm install -g @openai/codex`
- Run `codex` and verify the above settings

### Cursor
- Via web UI of your Cursor org, create your own API key
- Add it to your env (e.g., in `.bashrc`: `export CURSOR_API_KEY="<your-key>"` (replace `<your-key>`, of course))
- Edit `~/.cursor/cli-config.json` and change `model` section to read:
```JSON
  "model": {
    "modelId": "composer-2",
    "displayModelId": "composer-2",
    "displayName": "Composer 2",
    "displayNameShort": "Composer 2",
    "aliases": [
      "composer"
    ],
    "maxMode": true
  }
```

> **Note — larch overrides the cli-config.json model for its own Cursor invocations.**

## What the plugin provides

| Component | Description |
|---|---|
| Skills | `/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/loop-improve-skill`, `/improve-skill`, `/fix-issue`, `/issue`, `/alias`, `/create-skill`, `/simplify-skill`, `/compress-skill`, `/im`, `/imaq` |
| Agents | `code-reviewer` (unified archetype covering code quality, risk/integration, correctness, architecture, security) |
| PreToolUse hook | `block-submodule-edit.sh` — blocks `Edit`/`Write` on files inside any checked-out git submodule of the consuming project |
| SessionStart hook | `sessionstart-health.sh` — at session start/resume/clear/compact, probes `jq` and `git` on `PATH`; if either is missing, injects an advisory into session context so the issue is visible before the first `Edit`/`Write`. Non-blocking (always exits 0); silent when both tools are present |

## `/relevant-checks` — required consumer dependency

> **Important:** `/implement` and `/review` invoke `/relevant-checks` after each commit during their workflows. If your repo does not define one, these workflows will fail at the validation step.

The `/relevant-checks` skill is **not part of the plugin surface** — it is present in the install directory but not loaded by the plugin runtime. Each consuming repo must provide its own `/relevant-checks` as a project-level skill at `.claude/skills/relevant-checks/` with build and lint commands tailored to that repo.

**To create one for your repo:**

1. Create `.claude/skills/relevant-checks/SKILL.md` with `allowed-tools: Bash`
2. Add a `scripts/run-checks.sh` that runs your repo's linters, tests, or validators
3. Reference the script from SKILL.md using `$PWD/.claude/skills/relevant-checks/scripts/run-checks.sh`

Larch's own copy at `.claude/skills/relevant-checks/` serves as a reference implementation — it runs `pre-commit` linters plus `agent-lint` (if available on PATH).

## Prerequisites

Larch skills have different dependency requirements depending on which features you use.

### Installation dependencies

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
- **Slack** — Single tracking-issue status message per `/implement` run (and for `/fix-issue` NON_PR closures). On by default when Slack env vars are configured; pass `--no-slack` to opt out. Requires environment variables or plugin `userConfig` (see [Environment Variables](configuration-and-permissions.md#environment-variables)). When `--no-slack` is passed, all Slack operations are skipped silently. When env vars are missing (and `--no-slack` was not passed), the operation is skipped with a warning at session setup. All other workflow steps proceed normally in either case.

### Contributor development

- **pre-commit** — `pip install pre-commit` for local linting (`make setup` installs git hooks)
- **Python 3.12+** — required by pre-commit
