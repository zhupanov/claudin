# Larch

Larch = Claude Code workflow automation framework. Orchestrate multi-agent design, code review, implementation via collaborative AI process.

## Installation

Larch ship as [Claude Code plugin](https://code.claude.com/docs/en/plugin-marketplaces). Install = two step: register marketplace, then install plugin.

Slack optional. See [Environment Variables](#environment-variables) — skill degrade gracefully when Slack not configured.

### Install from GitHub

```bash
claude plugin marketplace add zhupanov/larch
claude plugin install larch@larch-local
```

First command register larch marketplace manifest (`.claude-plugin/marketplace.json`). Second install `larch` plugin into user scope. After install, `/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/fix-issue`, `/issue`, `/alias`, `/create-skill`, `/im`, `/imaq` slash commands available every session.

Scope to single project instead of user: append `--scope project` to `install`.

### Install for local development (contributors)

Hack on larch, want Claude Code load plugin from working checkout (so `${CLAUDE_PLUGIN_ROOT}` resolve to repo you edit): launch with `--plugin-dir`:

```bash
git clone https://github.com/zhupanov/larch.git
cd larch
claude --plugin-dir .
```

Or add working checkout as local marketplace, install from it:

```bash
cd larch
claude plugin marketplace add .
claude plugin install larch@larch-local
```

### What the plugin provides

| Component | Description |
|---|---|
| Skills | `/design`, `/implement`, `/review`, `/research`, `/loop-review`, `/fix-issue`, `/issue`, `/alias`, `/create-skill`, `/im`, `/imaq` |
| Agents | `code-reviewer` (unified archetype: code quality, risk/integration, correctness, architecture, security) |
| PreToolUse hook | `block-submodule-edit.sh` — block `Edit`/`Write` on files inside any checked-out git submodule |
| SessionStart hook | `sessionstart-health.sh` — at session start/resume/clear/compact, probe `jq` and `git` on `PATH`. If missing, inject advisory into session context before first `Edit`/`Write`. Non-blocking (exit 0); silent when both present |

### `/relevant-checks` — required consumer dependency

> **Important:** `/implement` and `/review` invoke `/relevant-checks` after each commit. No `/relevant-checks` in repo = workflow fail at validation.

`/relevant-checks` skill **not part of plugin surface** — present in install dir but not loaded by plugin runtime. Each repo must provide own `/relevant-checks` as project-level skill at `.claude/skills/relevant-checks/` with build/lint commands for that repo.

**Make one for your repo:**

1. Create `.claude/skills/relevant-checks/SKILL.md` with `allowed-tools: Bash`
2. Add `scripts/run-checks.sh` that run your linters, tests, validators
3. Reference script from SKILL.md via `$PWD/.claude/skills/relevant-checks/scripts/run-checks.sh`

Larch own copy at `.claude/skills/relevant-checks/` = reference implementation. Run `pre-commit` linters plus `agent-lint` (if on PATH).

### Strict-permissions consumers — Skill permission entries

> **Important:** Consumer repos with strict permissions (no `"defaultMode": "bypassPermissions"`) must grant **both** bare and fully-qualified form of each larch skill invoked. Wildcards like `Skill(larch:*)` **not currently documented** by Claude Code, will not authorize plugin skills. See [Skill permission syntax](https://code.claude.com/docs/en/permissions) and [Extend Claude with skills](https://code.claude.com/docs/en/skills).

**Why both form?** `Skill(name)` = exact-match rule — does **not** authorize `Skill(larch:name)`. Larch alias skills (`/im`, `/imaq`, anything from `/alias`) invoke target with bare-then-qualified fallback: try `Skill("implement")` first, fall back to `Skill("larch:implement")`. Under strict permissions, denied bare-name call may or may not trigger LLM fallback, so reliable = allow both explicitly. `Skill(name *)` = argument-prefix match (for `Skill(name <args>)`), not namespace match — no help for `plugin:name` form.

**Shadowing caveat:** Bare name like `Skill(implement)` may resolve to project-local skill under `.claude/skills/implement/` in consumer repo before reach plugin. Consumers need plugin version: use qualified `larch:implement` in orchestration, or avoid local skills duplicating plugin short names.

**Copy-paste settings.allow snippet (Skill entries only).** Add to `.claude/settings.json` `permissions.allow` list, keep strict ASCII code-point order across list. This snippet cover only `Skill(...)` entries; also need `Bash(...)` allowlist patterns for larch shell helpers — see larch own [`.claude/settings.json`](.claude/settings.json) for full reference.

```json
"Skill(alias)",
"Skill(create-skill)",
"Skill(design)",
"Skill(fix-issue)",
"Skill(im)",
"Skill(imaq)",
"Skill(implement)",
"Skill(issue)",
"Skill(larch:alias)",
"Skill(larch:create-skill)",
"Skill(larch:design)",
"Skill(larch:fix-issue)",
"Skill(larch:im)",
"Skill(larch:imaq)",
"Skill(larch:implement)",
"Skill(larch:issue)",
"Skill(larch:loop-improve-skill)",
"Skill(larch:loop-review)",
"Skill(larch:research)",
"Skill(larch:review)",
"Skill(loop-improve-skill)",
"Skill(loop-review)",
"Skill(research)",
"Skill(review)"
```

Note ordering: `Skill(larch:...)` begin with `l` then `a`, so all `larch:`-prefixed entries sort **before** `Skill(loop-review)`, `Skill(research)`, `Skill(review)` (first letters `l`-then-`o`, `r`, `r`). Sort whole block with `sort -u` to verify if extended. Section reflect current documented Claude Code behavior; consult upstream docs above if match semantics change.

### `--admin` merge behavior

When `/implement --merge` hit PR that pass CI but cannot merge due to branch protection (e.g., required reviews), retry with `gh pr merge --admin` as fallback. `--admin` flag override **all** branch protection including review requirements.

**Safety invariants enforced before `--admin` attempt:**

1. All CI checks pass (every check in "pass" bucket)
2. Branch up-to-date with main (not behind)

Checks re-verified right before `--admin` attempt — script no rely on cached state. See `scripts/merge-pr.sh`.

## Prerequisites

Larch skill have different dependency requirement depending on which feature used.

### Installation

- **Claude Code** — required. Install via [setup instructions](https://code.claude.com/docs/en/setup).

### Workflow automation (`/implement --merge`, `/review`)

Tools required for full design → implement → PR → merge workflow:

- **git** — version control (used by all skills)
- **gh** — [GitHub CLI](https://cli.github.com/), authenticated with repo write access (`gh auth login`). Required for PR create, CI monitor, merge automation.
- **jq** — [JSON processor](https://jqlang.github.io/jq/). Used by validation scripts and session setup.

### Optional integrations

Tools enhance workflow but not required. When unavailable, Claude replacement agents fill in auto:

- **Codex** — [OpenAI Codex CLI](https://github.com/openai/codex). Participate as external reviewer and voter alongside Claude subagents. When unavailable, Claude subagent replacement keep reviewer count.
- **Cursor** — [Cursor AI editor](https://cursor.com/). Participate as external reviewer and voter. When unavailable, Claude subagent replacement keep reviewer count.
- **Slack** — PR announcements and `:merged:` emoji reactions. Need env vars or plugin `userConfig` (see [Environment Variables](#environment-variables)). When not configured, all Slack op skipped with warning; all other workflow steps proceed normal.

### Contributor development

- **pre-commit** — `pip install pre-commit` for local linting (`make setup` install git hooks)
- **Python 3.12+** — required by pre-commit

## Features

- **Multi-agent design planning** — 5 sketch agents (1 Claude + 2 Cursor + 2 Codex) propose architectural approaches independently before full plan written. Prevent anchoring bias.
- **Dialectic adjudication** — Contested design decisions from sketch phase resolved by 3-judge binary panel (Claude Code Reviewer subagent + Codex + Cursor) after thesis/antithesis debate on external Cursor/Codex. Ballots attribution-stripped with deterministic position rotation to cancel judge bias.
- **Voting-based review resolution** — 3-agent voting panel (YES/NO/EXONERATE) adjudicate review findings for plan and code review
- **Reviewer competition scoring** — Reviewers earn points from finding quality. Scoreboard track accepted, neutral, exonerated, rejected findings
- **End-to-end automation** — From feature design through PR create, initial CI wait, Slack announcement in single command. With `--merge`, also run CI+rebase+merge loop, :merged: emoji, local branch cleanup, main verify. With `--draft` (mutually exclusive with `--merge`), create draft PR and keep feature branch checked out so user keep iterating
- **External reviewer integration** — Codex and Cursor participate alongside Claude subagents as reviewers and voters
- **Systematic codebase review** — Partition repo into slices, review each with specialized subagents, file every actionable finding as deduplicated GitHub issue (labeled `loop-review`). Security-tagged findings held locally per SECURITY.md, not auto-filed.

## Skills

Slash commands in Claude Code sessions. Automate multi-step workflows by orchestrate git, GitHub, Slack, other tools.

| Command | Arguments | Description |
|---|---|---|
| [`/design`](skills/design/SKILL.md) | `[--auto] [--debug] <feature description>` | Design implementation plan with collaborative multi-reviewer review. 5 sketch agents (1 Claude + 2 Cursor + 2 Codex) propose architectural approaches independent, then **dialectic debate + 3-judge binary panel** resolve up to 5 contested decisions (bucketed Cursor/Codex debaters with bucket-skip fallback; Claude/Cursor/Codex judges with replacement-first fallback; attribution-stripped ballot with position rotation — see `skills/shared/dialectic-protocol.md`), then 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor) validate full plan. `--auto` suppress all interactive question checkpoint. `--debug` enable verbose output with detailed tool descriptions and explanatory prose (default compact). [(Diagram).](skills/design/diagram.svg) |
| [`/research`](skills/research/SKILL.md) | `[--debug] <research question or topic>` | Collaborative read-only research using 3 research agents (Claude inline + Cursor + Codex, uniformly briefed) then 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Claude Code Reviewer subagent fallbacks preserve 3-lane invariant when external tool unavailable. Produce structured report with findings, risk assessment, difficulty estimates, feasibility verdict. Not modify repo: scratch writes permitted only under canonical `/tmp` (enforced mechanically by skill-scoped `scripts/deny-edit-write.sh` PreToolUse hook), `/issue` may be invoked via Skill tool to file research-result issues. [(Diagram).](skills/research/diagram.svg) |
| [`/review`](skills/review/SKILL.md) | `[--debug]` | Code review current branch changes with 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor, if available), implement accepted suggestions in recursive loop (up to 5 rounds). Review diff between main and HEAD. [(Diagram).](skills/review/diagram.svg) |
| [`/implement`](skills/implement/SKILL.md) | `[--quick] [--auto] [--merge \| --draft] [--debug] <feature description>` | Full end-to-end feature workflow — design, implement, PR, Slack announce. `--quick` skip `/design`, use simplified code review (1 Claude Code Reviewer subagent, 1 round). `--auto` suppress all interactive question checkpoint. `--merge` additionally run CI+rebase+merge loop, :merged: emoji, local branch cleanup, main verify (without `--merge`, PR created and workflow stop after initial CI wait, Slack announcement, reports). `--draft` create PR in draft state and skip local cleanup so branch kept for further iteration; mutually exclusive with `--merge`. `--debug` enable verbose output with detailed tool descriptions and explanatory prose (default compact). [(Diagram).](skills/implement/diagram.svg) |
| [`/loop-review`](skills/loop-review/SKILL.md) | `[--debug] [partition criteria]` | Systematic code review of entire repo by partition into slices, review each with 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor, if available), file every actionable finding as deduplicated GitHub issue via `/issue --input-file --label loop-review`. Use Negotiation Protocol to merge per-slice reviewer findings. Security-tagged findings held locally per SECURITY.md. Batches accumulate up to 3 slices per `/issue` flush so its 2-phase LLM dedup run once per batch. Optional arg specify how to partition codebase (e.g., by dir, by file type). `loop-review` label should be pre-created in target repo — `/issue` silently drop unknown labels with stderr warning. [(Diagram).](skills/loop-review/diagram.svg) |
| [`/fix-issue`](skills/fix-issue/SKILL.md) | `[--debug] [<number-or-url>]` | Process one approved GitHub issue per invocation. Fetch open issues with `GO` sentinel comment, skip any blocked by open dependency (GitHub native blocked-by API plus conservative prose-keyword scan of body and comments — `Depends on #N`, `Blocked by #N`, etc., with fail-open posture), triage against codebase, classify complexity (SIMPLE/HARD), delegate to `/implement`. With number or URL arg, target specific issue instead of auto-pick. Single-iteration design — caller handle repetition. |
| [`/issue`](skills/issue/SKILL.md) | `[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [<issue description>]` | Create one or more GitHub issues with LLM-based semantic duplicate detection. Two modes: single (free-form description) and batch (`--input-file`). 2-phase dedup against open + recently-closed issues (default 90-day window). `/implement` Step 9a.1 call this skill in batch mode to file OOS issues. `--go` (single mode only) post final `GO` comment so new issue eligible for `/fix-issue` automation; error on semantic duplicate. |
| [`/alias`](skills/alias/SKILL.md) | `[--merge] <alias-name> <target-skill> [preset-flags...]` | Create project-level alias for larch skill with preset flags. Delegate to `/implement --quick --auto` for full pipeline (code review, version bump, PR). `--merge` also merge PR. Example: `/alias i implement --merge` create `/i` as shortcut for `/implement --merge`. |
| [`/create-skill`](skills/create-skill/SKILL.md) | `[--plugin] [--multi-step] [--merge] [--debug] <skill-name> <description>` | Scaffold new larch-style skill from name and description. Validate name (regex + reserved-name union + case-insensitive collision) and description (length + XML / shell-dangerous pattern rejection), then delegate to `/im --quick --auto` which write scaffold via `skills/create-skill/scripts/render-skill-md.sh` and auto-merge PR (via `/im` `--merge` pre-set). Default target `.claude/skills/<name>/` (consumer mode); `--plugin` write to `skills/<name>/`. `--multi-step` emit multi-step scaffold; default minimal. `--merge` accepted as backward-compat no-op since `/im` already auto-merge. (see `skills/shared/skill-design-principles.md`) |
| [`/loop-improve-skill`](skills/loop-improve-skill/SKILL.md) | `<skill-name>` | Iteratively improve existing larch skill. Create tracking GitHub issue, then run up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` via bash driver that invoke each child skill as fresh `claude -p` subprocess (halt class eliminated by construction, close #273). Termination contract: strive for grade A on every `/skill-judge` dimension (D1..D8); exit happy when achieved, with written infeasibility justification when `/design` produce no plan, `/design` refuse, or `/im` cannot be verified, or with auto-generated infeasibility justification (post-iter-cap final `/skill-judge` re-evaluation list remaining non-A dimensions) when 10-iteration cap reached. Justification appended to close-out tracking-issue comment. Example: `/loop-improve-skill design`. |
| [`/relevant-checks`](.claude/skills/relevant-checks/SKILL.md) | *(none)* | Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint) scoped to files modified on current branch. Invoked auto by `/implement` and `/review` after code changes. **Not part of plugin surface; each consuming repo provide own.** |

### Aliases

Shortcut skills shipped with plugin. Each alias forward to existing skill with preset flags.

| Alias | Equivalent |
|---|---|
| [`/im`](skills/im/SKILL.md) | `/implement --merge` |
| [`/imaq`](skills/imaq/SKILL.md) | `/implement --merge --auto --quick` |

## Review Agents

Internal agent definitions used by skills like `/design`, `/review`, `/loop-review`. Not invoked directly — skills launch as specialized subagents during plan and code review.

| Agent | Description |
|---|---|
| [`code-reviewer`](agents/code-reviewer.md) | Unified code reviewer combine code quality (bugs, reuse, tests, backward compat, style), risk/integration (breaking changes, thread safety, deployment, regressions, CI), correctness (logic errors, off-by-one, nil, types, races, errors, math), architecture (separation of concerns, contract boundaries, invariants, semantic boundaries), security (injection, authn/authz, secrets, crypto, deserialization, SSRF, path traversal, dependency CVEs). Findings tagged with focus area. Generated from `skills/shared/reviewer-templates.md` via `scripts/generate-code-reviewer-agent.sh`. |

### Migration note

Previous two archetypes `general-reviewer` and `deep-analysis-reviewer` replaced by single unified `code-reviewer`. Consumers that invoked older agent slugs directly (via `--agents` or subagent_type references in downstream docs/scripts) must switch to `code-reviewer`.

## Linting

Larch use [pre-commit](https://pre-commit.com/) as single source of truth for linter config. All linter definitions, versions, file filters live in `.pre-commit-config.yaml`.

### Linters

| Linter | File Types | Description |
|--------|-----------|-------------|
| [shellcheck](https://www.shellcheck.net/) | `.sh` | Shell script analysis |
| [markdownlint](https://github.com/igorshubovych/markdownlint-cli) | `.md` | Markdown style enforcement (config: `.markdownlint.json`) |
| [jq](https://jqlang.github.io/jq/) | `.json` | JSON syntax validation |
| [actionlint](https://github.com/rhysd/actionlint) | `.yml`, `.yaml` | GitHub Actions workflow validation |
| [agnix](https://github.com/agent-sh/agnix) | `SKILL.md`, `CLAUDE.md`, agent configs | AI agent config linting (config: `.agnix.toml`) |

### Usage

Three ways to run linters, all backed by same `.pre-commit-config.yaml`:

- **CI** — Run `make lint` (repo-wide) on every pull request.
- **`/relevant-checks`** — Run `pre-commit run --files <changed-files>` scoped to branch changes. Invoked auto by `/implement` and `/review`.
- **Local git hook** — Run `make setup` (or `pre-commit install`) to enable pre-commit hooks that lint staged files on every commit.

### Makefile Targets

| Target | Description |
|--------|-------------|
| `make lint` | Run all linters repo-wide |
| `make shellcheck` | Run shellcheck only |
| `make markdownlint` | Run markdownlint only |
| `make jsonlint` | Run JSON validation only |
| `make actionlint` | Run actionlint only |
| `make agnix` | Run agnix only |
| `make setup` | Install pre-commit git hooks |
| `make smoke-dialectic` | Run offline fixture-driven smoke test for `/design` Step 2a.5 (dialectic parser + tally + structural-invariant guard). Exercise `scripts/dialectic-smoke-test.sh` against `tests/fixtures/dialectic/`. |
| `make test-block-submodule` | Run regression harness for `scripts/block-submodule-edit.sh` (PreToolUse hook that deny edits inside submodules). Exercise `scripts/test-block-submodule-edit.sh` end-to-end against temp superproject + submodule fixture. |
| `make test-deny-edit-write` | Run regression harness for `scripts/deny-edit-write.sh` (skill-scoped PreToolUse hook registered by `/research` that permit `Edit`/`Write`/`NotebookEdit` only when target path resolve under canonical `/tmp`, deny otherwise). Exercise `scripts/test-deny-edit-write.sh` — repo-deny, `/tmp`-allow, traversal-deny, relative-deny, `notebook_path` allow/deny, fail-closed on empty path, malformed JSON, idempotency, `jq`-absent fallback byte-identity. |
| `make test-lib-halt-ledger` | Run offline regression harness for `scripts/lib-loop-improve-halt-ledger.sh` (sourced-only halt-location classifier consumed by halt-rate probe). Exercise `scripts/test-lib-loop-improve-halt-ledger.sh` — empty dir, nonexistent dir, each per-substep sentinel, multi-iteration highest-iter scan, empty-sentinel-treated-as-missing cases. `make lint` prerequisite. |
| `make halt-rate-probe` | Run **opt-in** halt-rate regression probe for `/larch:loop-improve-skill` (close #278). Exercise `scripts/test-loop-improve-skill-halt-rate.sh` end-to-end against throwaway fixture skill to measure how often loop halts mid-turn after `/skill-judge` returns (recurring failure from #273). **Not `make lint` prerequisite** — too slow and non-deterministic for CI. See "Halt-rate regression harness" below for output contract and caveats. |

### Halt-rate regression harness

Opt-in probe that measure how often `/larch:loop-improve-skill` halts mid-iteration. Close #278; track halt-problem umbrella #273. Invocation:

```bash
make halt-rate-probe
# or with custom flags:
bash scripts/test-loop-improve-skill-halt-rate.sh --runs 10 --timeout-per-run 2400
```

**Flags**: `--runs N` (default 5), `--timeout-per-run SEC` (default 1800), `--keep-tmpdirs` (skip cleanup for forensics).

**Prerequisites**: `claude` CLI on `PATH` (headless mode) + GNU `timeout` (macOS: `brew install coreutils`, then `gtimeout` detected auto). Harness provision per-run bare git origin under `mktemp -d`, copy fixture skill from `tests/fixtures/loop-halt-rate/SKILL.md`, PATH-shim `gh` to no-op stub (no live GitHub side effects), then invoke `claude --plugin-dir <larch-root> -p "/larch:loop-improve-skill loop-halt-rate"` bounded by `timeout --kill-after=10`.

**Output contract** (stdout — automation should grep these tokens):

```
RUN <i>: status=<completed_by_outer|halt_mid_turn|halt_detected_by_outer|timeout|tool_failure|error> last_completed=<token> clause="<halt-location clause>" elapsed=<s>s
...
HALT_RATE=<halted>/<measured>
MEASURED_RUNS=<measured>
PROBE_STATUS=ok|skipped_no_claude|error
PER_STATUS_BREAKDOWN: completed=<n> halt_mid_turn=<n> halt_detected_by_outer=<n> timeout=<n> tool_failure=<n> error=<n>
PER_LOCATION_BREAKDOWN: none=<n> 3j=<n> 3jv=<n> 3d-pre-detect=<n> 3d-post-detect=<n> 3d-plan-post=<n> 3i=<n> done=<n>
```

- `HALT_RATE` numerator = `halt_mid_turn + halt_detected_by_outer`. Denominator = `MEASURED_RUNS` = runs excluding `error` and `tool_failure` (infrastructure failures that prevented measurement). Automation should check `PROBE_STATUS` before consume `HALT_RATE`; KV format `HALT_RATE=0/0` with `PROBE_STATUS=error` signal "no measurement" and must not conflate with "zero halts observed".
- `halt_mid_turn` = halt-of-interest from #273: outer skill itself ended turn before reach Step 5 close-out.
- `halt_detected_by_outer` = LEGACY branch from pre-rewrite split-skill topology (outer `/loop-improve-skill` delegate to inner `/loop-improve-skill-iter` via Skill tool with `#231` mechanical gate catch `iteration sentinel missing`). Under new bash-driver topology (`skills/loop-improve-skill/scripts/driver.sh`, #273) branch never emitted, expected report `0` — driver eliminate inner-halt class by construction. True mid-turn halts under new topology manifest as `claude -p` subprocess exit-code failures, which driver handle via `break` with category-specific `EXIT_REASON` (e.g. `subprocess failure at /skill-judge iteration N`), classified as `completed_by_outer` since outer itself reach Step 5 close-out.
- `completed_by_outer` include all normal loop exits: `grade_a_achieved`, `max iterations (10) reached`, infeasibility exits like `im_verification_failed`. `/im` expected to fail under stubbed `gh` — NOT halt-of-interest; halt-of-interest fire much earlier, at `/skill-judge` return.
- `timeout` cover both `timeout --kill-after` TERM (exit 124) and SIGKILL escalation (exit 137 = 128+9).
- `tool_failure` cover wrapper exits other than 0/124/137 where no LOOP_TMPDIR ever emitted — claude itself crashed or plugin failed to load.
- `PROBE_STATUS=error` can emit from two paths with different exit codes — consumers should treat both same way (don't consume `HALT_RATE` as signal), but should not rely on exit code to distinguish: (a) **post-measurement** `PROBE_STATUS=error` with **exit 0** when `MEASURED_RUNS=0` OR any `error`/`tool_failure` run occurred; (b) **preflight** `PROBE_STATUS=error` with **exit 1** when startup check fail (missing `timeout`/`gtimeout`, bad repo root, missing fixture). stdout token identical; check `PROBE_STATUS` before `HALT_RATE`.
- `PROBE_STATUS=skipped_no_claude` emitted (and harness exit **non-zero**) when `claude` binary absent, per issue #278 explicit contract.
- `PER_LOCATION_BREAKDOWN` tokens correspond to `LAST_COMPLETED` taxonomy owned by `clause_for_last_completed()` in `scripts/lib-loop-improve-halt-ledger.sh`.

**Caveats**:

- Runtime highly variable (~5-30min per run). Budget accordingly.
- Fixture = minimal deliberately-deficient skill; measured halt rate = *lower bound* on production halt rate — real target skills produce longer reviewer chains that amplify turn-end cue. Document this when publish comparative numbers.
- Each run consume real Claude API tokens + external reviewer (Cursor/Codex) latency.
- `gh` PATH-shimmed to no-op stub — no live GitHub issue creation, no PR creation, no live CI. `/im` typically fail with `ITER_STATUS=im_verification_failed` (classified as `completed_by_outer`, not halt).
- Not wired into `make lint` by design — opt-in only.

## Environment Variables

Larch use env vars for Slack integration and external reviewer model config. All optional — when not set, Slack features skipped with warnings, external reviewers use default models.

> **Important:** Both `LARCH_SLACK_BOT_TOKEN` **and** `LARCH_SLACK_CHANNEL_ID` must be set in shell environment for Slack features to work. If either missing, **all** Slack op (PR announcements, `:merged:` emoji) skipped with warning at session setup identifying which var(s) absent. Vars must be present in environment where `claude` launched — not read from `.env` files or config.

**Alternative: Plugin `userConfig`** — If larch installed as plugin, can also configure Slack tokens via plugin `userConfig` (prompt at plugin enable time). `userConfig` values exported as `CLAUDE_PLUGIN_OPTION_*` env vars to subprocesses. Larch check both: env vars take precedence if both set.

### `LARCH_SLACK_BOT_TOKEN`

Slack Bot User OAuth Token (start with `xoxb-`) used to authenticate Slack API calls.

**When set:**
- `/implement` post PR announcements to Slack after create PR
- `/implement` add `:merged:` emoji reaction to Slack announcement after PR merged
- Token presence checked during session setup, availability propagated to child skills

**When not set:**
- All Slack op skipped with warning at session setup (e.g., `⚠ Slack is not fully configured (LARCH_SLACK_BOT_TOKEN not set). Slack announcement (Step 11) will be skipped.`)
- `:merged:` emoji step in `/implement` skipped
- All other workflow steps (design, implementation, code review, CI monitoring, merge) proceed normal

### `LARCH_SLACK_CHANNEL_ID`

Slack channel ID (e.g., `C0123456789`) where PR announcements and emoji reactions posted.

**When set:**
- PR announcements posted to this channel
- `:merged:` emoji reaction target announcements in this channel

**When not set:**
- All Slack op skipped with warning at session setup (e.g., `⚠ Slack is not fully configured (LARCH_SLACK_CHANNEL_ID not set).`)
- `:merged:` emoji step in `/implement` also skipped
- All other workflow steps proceed normal

### `LARCH_SLACK_USER_ID`

Slack user ID (e.g., `U0123456789`) used to @-mention PR author in Slack announcements.

**When set:**
- Slack announcements include @-mention of this user, notify directly in channel

**When not set:**
- Slack announcements still posted, but no @-mention — message appear without user notification

### External Reviewer Model Configuration

Vars control which model Cursor and Codex use when running as external reviewers. When unset, Cursor default to `composer-2-fast`, Codex use own configured default. Model passed via `--model` flag (Cursor) or `-m` flag (Codex).

Model config also available via plugin `userConfig` — env vars take precedence if both set.

### `LARCH_CURSOR_MODEL`

Model name to pass to Cursor `--model` flag (e.g., `gpt-5.4-medium`, `claude-sonnet-4-6`).

**When set:**
- All Cursor invocations (reviews, sketches, voting, health probes, negotiations) use this model
- Model flag injected by `scripts/reviewer-model-args.sh`, called from both scripts and skill prompts

**When not set:**
- Default `composer-2-fast` — Cursor `cursor agent` CLI not honor model configured in `~/.cursor/cli-config.json`, so explicit default required to avoid fall back to potentially rate-limited model

### `LARCH_CODEX_MODEL`

Model name to pass to Codex `-m` flag (e.g., `o3`, `o4-mini`).

**When set:**
- All Codex invocations (reviews, sketches, voting, health probes, negotiations) use this model
- Model flag injected by `scripts/reviewer-model-args.sh`, called from both scripts and skill prompts

**When not set:**
- Codex run without explicit `-m` flag, use own configured default

### `LARCH_CODEX_EFFORT`

Codex reasoning effort for reviewer launches. Accepted values: `minimal`, `low`, `medium`, `high`. Default `high` (match plugin `codex_effort` userConfig default).

**When set at reviewer launch sites (design sketches, plan review, code review, conflict-resolution review, voting panel):**
- `scripts/reviewer-model-args.sh --with-effort` emit `-c model_reasoning_effort="$LARCH_CODEX_EFFORT"`, raise Codex reasoning to configured level.

**When not set (or set to empty string):**
- `--with-effort` fall back to plugin userConfig value (`codex_effort`, default `high`).
- Setting `LARCH_CODEX_EFFORT=""` explicitly does NOT disable emission; to suppress effort flags entirely, callers already omit `--with-effort` flag (e.g., `check-reviewers.sh` health probes not use max effort regardless of env var setting).

**Scope**: Claude and Cursor reviewers run at defaults. Only Codex bumped to `high` by default. Deliberate — Claude sonnet default already well-suited to review work, Cursor no dedicated reasoning-effort CLI flag today.

## Detailed Documentation

- [Workflow Lifecycle](docs/workflow-lifecycle.md) — How skills compose to form end-to-end development workflow
- [Voting Process](docs/voting-process.md) — 3-agent voting panel that adjudicate review findings
- [Point Competition](docs/point-competition.md) — Reviewer scoring system and competition mechanics
- [Collaborative Sketches](docs/collaborative-sketches.md) — Diverge-then-converge design phase
- [External Reviewers](docs/external-reviewers.md) — Codex and Cursor integration procedures
- [Review Agents](docs/review-agents.md) — Unified Code Reviewer archetype
- [Agent System](docs/agents.md) — How skills orchestrate parallel subagents
