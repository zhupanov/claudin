# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [2.0.0] - 2026-04-13

### Changed

- **BREAKING**: Renamed `/fix-issues` skill to `/fix-issue` (singular) to match its single-iteration semantics
- Added `--issue <number-or-url>` flag to `/fix-issue` for targeting a specific GitHub issue instead of auto-picking the oldest eligible one

## [1.4.0] - 2026-04-13

### Added

- New `/fix-issues` skill that processes one approved GitHub issue per invocation: fetches issues with `GO` sentinel, triages against codebase, classifies complexity (SIMPLE/HARD), and delegates to `/implement`
- Added `claude-lint` to `/relevant-checks` validation pipeline (runs after plugin structure validation when available on PATH)

### Fixed

- Added explicit flag-parsing defaults to all 5 skill SKILL.md files to prevent cross-flag contamination where parsing one flag (e.g. `--merge`) could cause the agent to incorrectly set another (e.g. `auto_mode=true`). Each flag now has an explicit `Default:` sentinel and a shared preamble states all boolean flags default to `false` and are independent.

## [1.3.10] - 2026-04-13

### Fixed

- Fixed `mktemp`/`mv` failure when `--write-session-env /dev/null` or `--write-health /dev/null` is passed to session setup scripts. Both `mktemp` and `mv` fail on device nodes on macOS.

## [1.3.9] - 2026-04-13

### Changed

- Updated author/contact email from `sergey@zhupanov.com` to `zhupanov@yahoo.com` in plugin manifests and security policy.

## [1.3.8] - 2026-04-13

### Changed

- Cursor reviewer now defaults to `--model composer-2-fast` when `LARCH_CURSOR_MODEL` is unset, since `cursor agent` CLI does not honor `~/.cursor/cli-config.json` and would otherwise fall back to a potentially rate-limited model.

## [1.3.7] - 2026-04-13

### Added

- `LARCH_CURSOR_MODEL` and `LARCH_CODEX_MODEL` environment variables for controlling which models Cursor and Codex use as external reviewers.
- New `scripts/reviewer-model-args.sh` script that centralizes model flag injection for both tools.
- Plugin `userConfig` entries (`cursor_model`, `codex_model`) as alternative to environment variables.
- Prominent `═══` banner-style warnings in terminal output when Cursor or Codex health checks fail.

## [1.3.6] - 2026-04-13

### Fixed

- Resolved all claude-lint errors: added trigger context to skill descriptions (S017), shortened long descriptions to ≤250 chars (S015), and rewrote descriptions in third person (S016).
- Removed `continue-on-error: true` from claude-lint CI step now that all errors are resolved.

### Added

- `claude-lint.toml` config file disabling the `body-too-long` rule for intentionally long SKILL.md bodies.

## [1.3.5] - 2026-04-13

### Added

- CI job running `claude-lint` via `zhupanov/claude-lint@v1` GitHub Action with explicit `github-token` for version resolution.

## [1.3.4] - 2026-04-12

### Changed

- Replaced per-step emoji progress lines with breadcrumb-style step paths across all 5 skill SKILL.md files (e.g., `▸ 1.2a: design plan | sketches` instead of `🤝 Step 1.2a — Collaborative sketches...`).
- Created `skills/shared/progress-reporting.md` shared formatting contract defining icon taxonomy, breadcrumb format, and `--step-prefix` `::` encoding.
- Extended `--step-prefix` to carry both numeric prefix and textual breadcrumb path (e.g., `"1.::design plan"`), with backward-compatible fallback for numeric-only values.
- Added Step Name Registry tables (<=20-char short names per step) to all 5 skill SKILL.md files.
- Preserved `⏭️`/`⏩` semantic distinction for precondition vs. sub-step skips.

## [1.3.3] - 2026-04-12

### Changed

- Renamed "grilling"/"grill" terminology to "discussion"/"discuss" throughout `/design` skill, `docs/workflow-lifecycle.md`, and prior CHANGELOG entries for clarity.

## [1.3.2] - 2026-04-12

### Changed

- Consolidated skill setup: all 5 skills now call `session-setup.sh` with `--check-reviewers` instead of separate `create-session-tmpdir.sh` + `check-reviewers.sh` + health file write sequences.
- Created `collect-reviewer-results.sh` to consolidate post-launch reviewer output validation, retry, and health tracking across all skills.
- Extended `session-setup.sh` with `--skip-preflight`, `--check-reviewers`, `--write-health`, `--write-session-env` flags.
- Added `.meta` file support to `run-external-reviewer.sh` for retry capability in `collect-reviewer-results.sh`.

### Removed

- Deleted `create-session-tmpdir.sh` (all callers migrated to `session-setup.sh`).

## [1.3.1] - 2026-04-12

### Changed

- Removed pure "done" step-completion announcements from `/implement`, `/design`, and `/review`; only result-bearing completions (with counts/outcomes) and conditional-skip markers are preserved.
- Added internal `--step-prefix` flag to `/design` and `/review` for hierarchical step numbering when called from `/implement` (e.g., Step 1.0, Step 5.2).
- Added internal `--branch-info` flag to `/design` to skip redundant `create-branch.sh --check` when invoked from `/implement`.
- Suppressed rebase-skip messages (`⏩ Rebase skipped — ...`) in non-debug mode in `/implement`.

## [1.3.0] - 2026-04-12

### Added

- External reviewer health probe: `check-reviewers.sh --probe` sends a trivial prompt to each external reviewer (Codex/Cursor) with a 60-second timeout at session startup, catching outages before wasting time on long review timeouts.
- Runtime timeout fallback: when an external reviewer times out during any step, it is replaced by a Claude subagent with similar persona for all subsequent invocations in the session.
- Cross-skill health propagation: reviewer health state flows from `/implement` → `/design` → `/review` via `--session-env` and structured health status files.
- `--session-env <path>` flag for `/review` skill (MINOR: new flag in `argument-hint`).
- `--skip-codex-probe` / `--skip-cursor-probe` flags for `check-reviewers.sh` to avoid re-probing tools already known unhealthy.

### Changed

- `write-session-env.sh`: added `--codex-healthy`/`--cursor-healthy` flags, atomic writes via temp+mv, conditional health key emission.
- `session-setup.sh`: parses and re-emits `CODEX_HEALTHY`/`CURSOR_HEALTHY` from caller-env.
- `external-reviewers.md`: renamed "Binary Check" to "Binary Check and Health Probe", added "Runtime Timeout Fallback" section.

## [1.2.0] - 2026-04-12

### Added

- `--debug` flag for all 5 workflow skills (`/implement`, `/design`, `/review`, `/research`, `/loop-review`). Default (no `--debug`) uses compact output: empty Bash tool descriptions, suppressed explanatory prose, compact reviewer status tables. `--debug` restores verbose output.
- Compact reviewer status table in `/review`, `/design`, and `/research` — replaces per-reviewer individual completion messages with a single reprinted line showing all reviewer statuses.
- Progress Reporting sections for `/review` and `/loop-review` (previously missing).
- Auto-propagation: `/implement` forwards `--debug` to `/design` and `/review`; `/loop-review` forwards to `/implement`.

## [1.1.12] - 2026-04-12

### Added

- Two-round design discussion steps in `/design` skill: Step 1d (pre-sketch, scope/requirements interrogation) and Step 3.5 (post-review, covers decisions not addressed in round 1 or deemed suboptimal by reviewers). Both rounds walk the decision tree one question at a time with recommended answers, explore the codebase first, and are skipped in `--auto` mode.
- New `accepted-plan-findings.md` artifact written during plan review finalization, bridging Step 3 and Step 3.5.

### Changed

- Updated `docs/workflow-lifecycle.md` mermaid diagram to include both discussion nodes in the design phase.

## [1.1.11] - 2026-04-12

### Added

- Validators 24-25 in `validate-plugin-structure.sh`: every `userConfig` entry must have a non-empty `title` string field (V24) and a non-empty `type` string field (V25).

## [1.1.10] - 2026-04-12

### Fixed

- Added missing `title` and `type: "string"` fields to all three `userConfig` entries in `plugin.json` to conform to the Claude CLI plugin manifest schema.

## [1.1.9] - 2026-04-10

### Fixed

- Updated V19 header and function comments to include `LARCH_SLACK_USER_ID` (was stale after adding USER_ID to the loop).
- Moved V23 (`validate_userconfig_sensitive_type`) function definition to after V22 to match numeric and `main()` call order.
- Updated `smoke-test.sh` advisory comment to remove stale `$schema`/`description` examples.

## [1.1.8] - 2026-04-10

### Fixed

- V19: added `LARCH_SLACK_USER_ID` to Slack fallback consistency check (was only checking BOT_TOKEN and CHANNEL_ID).
- V23: extracted from V18 into standalone `validate_userconfig_sensitive_type()` function with own `main()` call, matching the 1-function-per-validator pattern.

### Removed

- Removed `$schema` and top-level `description` from `marketplace.json` — rejected by Claude CLI schema validator. Removed corresponding V12 checks.

## [1.1.7] - 2026-04-10

### Added

- Validators 19-23 in `validate-plugin-structure.sh`: Slack fallback consistency (V19), userConfig key→env var mapping (V20), bidirectional agent-template count (V21), docs file reference existence (V22), userConfig sensitive boolean type check (V23).

### Changed

- Enhanced V16 with bidirectional count check (reviewer-template sections must match agent file count).
- Enhanced V18 with `sensitive` field boolean type validation.
- Narrowed V22 scope to only the Canonical sources section of CLAUDE.md.
- Improved V20 key normalization to handle camelCase and kebab-case keys.

## [1.1.6] - 2026-04-09

### Added

- Four new validators (15-18) in `validate-plugin-structure.sh`: shared markdown reference integrity, agent-template alignment ("Derived from" marker), email format validation, userConfig structure validation.

### Changed

- Cleaned `.claude/settings.json`: removed repo-specific entries (gcloud, kubectl, argocd, K8S_WORK, KUBECONFIG, codeql, temporal, Go tooling, etc.) and PostToolUse auto-goimports hook. Kept `bypassPermissions` for development.
- Deduplicated CI: removed standalone `validate-plugin-structure.sh` step, kept only `smoke-test.sh` as sole entry point.
- Generified `loop-review/SKILL.md`: replaced Go-specific partition examples and file extensions with language-agnostic alternatives across both Step 1 discovery and Step 3b collection.

### Removed

- `scripts/auto-goimports.sh` — Go-specific PostToolUse hook no longer referenced.

## [1.1.5] - 2026-04-09

### Added

- Dialectic debate step (Step 2a.5) in `/design` skill: structured thesis/antithesis debates on contested decisions between synthesis and plan writing.
- Structured contested-decisions schema with `NO_CONTESTED_DECISIONS` sentinel, debate quorum rule, and binding resolution format.
- Documentation for the dialectic debate phase in `docs/collaborative-sketches.md` and `docs/workflow-lifecycle.md`.

## [1.1.4] - 2026-04-09

### Added

- Plugin store readiness: enriched `marketplace.json` (`$schema`, `description`, `owner.email`, `category`) and `plugin.json` (`author.email`, `userConfig` for Slack, enriched `keywords`).
- `SECURITY.md` with minimal security policy, trust model, and external tool delegation documentation.
- `scripts/smoke-test.sh` validation-only smoke test wrapping `validate-plugin-structure.sh` plus advisory `claude plugin validate .`.
- Three new validators (12-14) in `validate-plugin-structure.sh`: marketplace enriched metadata, plugin.json enriched metadata, SECURITY.md presence.
- Prerequisites section in `README.md` split by use case (installation, workflow automation, optional integrations, contributor development).
- `--admin` merge behavior documentation in `README.md` with safety invariants.
- `/relevant-checks` consumer dependency guidance with setup instructions in `README.md`.

### Changed

- Fixed fallback behavior documentation in `docs/external-reviewers.md` and `docs/collaborative-sketches.md` to accurately describe Claude replacement agents maintaining constant participant counts and step-function voting thresholds.
- Replaced dangling cross-references to non-existent `/admin-upgrade-clients` and `/admin-add-user` skills in `scripts/merge-pr.sh` and `skills/implement/SKILL.md` with canonical implementation notes.
- Added `CLAUDE_PLUGIN_OPTION_*` fallback to all Slack-related scripts (`session-setup.sh`, `slack-announce.sh`, `post-pr-announce.sh`, `add-merged-emoji.sh`, `post-merged-emoji.sh`) so plugin `userConfig` Slack tokens propagate end-to-end.
- Updated `CLAUDE.md` to reference 14 validators, document `SECURITY.md` as a protected file, and note `userConfig` env var convention.
- Emphasized Slack env var requirements in `README.md` Environment Variables section with `userConfig` alternative documentation.

## [1.1.3] - 2026-04-09

### Added

- `/implement` Step 8a: automatically updates `CHANGELOG.md` (if present) with a brief summary after the version bump, amending it into the bump commit.
- Backfilled CHANGELOG entries for versions 1.0.3 through 1.1.2.

### Changed

- Updated `drop-bump-commit.sh` Guard 4 to accept `CHANGELOG.md` alongside `plugin.json` in the bump commit, preventing re-bump failures when Step 8a has amended the changelog.
- Added CHANGELOG re-update (step 4a) to the Rebase+Re-bump sub-procedure so changelog entries survive rebases.

## [1.1.2] - 2026-04-09

### Changed

- Added `actions/cache@v4` for pre-commit tool cache in CI, reducing lint job time from ~44s to ~2s on cache hits.
- Flattened `skills/shared/larch/` to `skills/shared/` and updated all path references across 14 files.

## [1.1.1] - 2026-04-09

### Changed

- Increased external reviewer timeouts from 15 to 30 minutes (review/plan review) and 10 to 20 minutes (sketch/voting).
- Added Claude subagent fallbacks for all skills when Cursor/Codex are unavailable, ensuring total reviewer count (5) and voter count (3) remain constant.

## [1.1.0] - 2026-04-09

### Added

- `/alias` skill for creating project-level alias shortcuts that forward to existing larch skills with preset flags. Generates `.claude/skills/<name>/SKILL.md` and commits.

## [1.0.6] - 2026-04-09

### Changed

- Switched `.claude/settings.json` to `bypassPermissions` mode for local development.
- Fixed CLAUDE.md shipped-vs-runtime classification for supplementary files.

## [1.0.5] - 2026-04-09

### Added

- `CLAUDE.md` with editing-agent invariants, repository layout documentation, golden rules for edits, and canonical source references.

## [1.0.4] - 2026-04-09

### Changed

- `/implement` now re-runs `/bump-version` after every rebase in Steps 10 and 12 (the Rebase + Re-bump Sub-procedure), ensuring the merged version reflects `origin/main` at merge time rather than at PR-creation time.

## [1.0.3] - 2026-04-09

### Added

- Plugin structure validator (`scripts/validate-plugin-structure.sh`) with 11 validators covering manifests, frontmatter, path hygiene, script references, executability, and dead-script detection.
- Extended `/relevant-checks` to run the plugin structure validator after pre-commit passes.

## [1.0.2] - 2026-04-08

### Removed

- **Temporary compatibility symlinks introduced in v1.0.1.** Deleted `scripts/larch` (a directory of per-file symlinks pointing back into `../scripts/`, added so that cached skill-prompt references to `${CLAUDE_PLUGIN_ROOT}/scripts/larch/<script>.sh` would still resolve to `${CLAUDE_PLUGIN_ROOT}/scripts/<script>.sh` during the v1.0.1 migration session) and `.claude/scripts/generic/larch` (a symlink pointing at `../../../scripts`, added so that cached `.claude/settings.json` PreToolUse/PostToolUse hook command paths would keep resolving during the migration session). Also removed the now-empty parent directories `.claude/scripts/generic/` and `.claude/scripts/`. The `.claude/settings.json` hook commands were already rewritten in v1.0.1 to `$PWD/scripts/block-submodule-edit.sh` and `$PWD/scripts/auto-goimports.sh`, and all SKILL.md path references were flattened to `${CLAUDE_PLUGIN_ROOT}/scripts/` — so these compatibility shims have no remaining consumers once sessions have restarted. The v1.0.1 follow-up is now complete.
- Corresponding assertions in the `.github/workflows/ci.yaml` `plugin-structure` job that verified the existence of the two compatibility shims.

## [1.0.1] - 2026-04-08

### Added

- `/bump-version` private skill (`.claude/skills/bump-version/`). Classifies and applies a semantic version bump based on the branch diff against `origin/main`. **Only inspects the public plugin surface** (`skills/**` and `agents/**`); changes under `.claude/**`, `scripts/**`, `hooks/**`, `docs/**`, `.github/**`, `CHANGELOG.md`, etc. default to PATCH. Uses deterministic shell + `jq` heuristics (MAJOR on skill/agent deletion or rename, `name:` frontmatter change, or flag removal; MINOR on new skill/agent or new flag) with an **escalation-only** caveat clause: after the classifier runs, the main agent may escalate PATCH → MINOR → MAJOR if a behavioral change would be judged backward-incompatible by a reasonable client, but may never downgrade. The classifier is idempotent — it detects an already-bumped branch (via `^Bump version to X.Y.Z$` commit subject) and emits `BUMP_TYPE=NONE` to skip double-bumps. Writes decision reasoning to `${IMPLEMENT_TMPDIR:-$PWD/.git}/bump-version-reasoning.md` for embedding in the PR body.
- `<details><summary>Version Bump Reasoning</summary>` section in `/implement` Step 9a PR body template, populated from the reasoning file written by `/bump-version`.

### Changed

- **Flattened scripts layout.** Moved all 38 scripts from `scripts/larch/*` to `scripts/*` and rewrote every `${CLAUDE_PLUGIN_ROOT}/scripts/larch/` reference across skill docs (`skills/{design,implement,review,research,loop-review}/SKILL.md`), shared docs (`skills/shared/larch/{external-reviewers,voting-protocol}.md`), `hooks/hooks.json`, `.claude/settings.json`, and `.github/workflows/ci.yaml`. Added a temporary compatibility shim `scripts/larch/` (a directory of 38 per-file symlinks, each pointing back into `../scripts/` — e.g. `scripts/larch/session-setup.sh -> ../session-setup.sh`) to preserve path resolution for in-flight `/implement` sessions whose cached skill prompts still reference the old path. To be removed in a follow-up PR.
- **Removed legacy `.claude/` compatibility symlinks.** Deleted `.claude/skills/{design,implement,review,research,loop-review,shared}` and `.claude/agents/{deep-analysis-reviewer,general-reviewer}.md`. The plugin is discovered via `${CLAUDE_PLUGIN_ROOT}` when launched with `claude --plugin-dir .` or via the local marketplace, so these legacy symlinks are no longer load-bearing. `.claude/skills/` remains as a real directory for private repo-specific skills (`relevant-checks`, `bump-version`).
- **Repointed `.claude/scripts/generic/larch`** from `../../../scripts/larch` to `../../../scripts` so that cached hook command paths in the running Claude Code session (loaded at startup from `.claude/settings.json`) continue to resolve to `scripts/block-submodule-edit.sh` and `scripts/auto-goimports.sh` after the scripts migration. To be removed in a follow-up PR after all sessions have restarted.
- **Updated `.claude/settings.json`.** Rewrote PreToolUse/PostToolUse hook command paths from `$PWD/.claude/scripts/generic/larch/*` to `$PWD/scripts/*`. Consolidated the Bash permission allowlist: replaced `Bash($PWD/scripts/larch/*)` and `Bash($PWD/.claude/scripts/generic/larch/*)` with `Bash($PWD/scripts/*)`. Added `Skill(bump-version)` and `Bash($PWD/.claude/skills/bump-version/scripts/*)` for the new skill. Removed stale entries for `$PWD/.claude/skills/implement/scripts/*` and `$PWD/.claude/skills/loop-review/scripts/*` (the underlying symlinks were deleted).
- **Simplified CI `plugin-structure` job** (`.github/workflows/ci.yaml`). Removed the `.claude/skills/*` and `.claude/agents/*.md` symlink verification loop. Replaced the `scripts/larch/block-submodule-edit.sh` path check with `scripts/block-submodule-edit.sh`. Added checks for the two remaining compatibility symlinks (`scripts/larch` and `.claude/scripts/generic/larch`).
- **Updated `docs/agents.md` and `docs/review-agents.md`** to reference `agents/*.md` and `skills/shared/larch/reviewer-templates.md` instead of the deleted `.claude/*` paths.

## [1.0.0] - 2026-04-08

Initial release of larch as a Claude Code plugin.

### Added

- `.claude-plugin/plugin.json` manifest declaring the plugin name, version, and metadata.
- `.claude-plugin/marketplace.json` local marketplace catalog for `claude plugin marketplace add .`.
- `hooks/hooks.json` registering a PreToolUse hook that runs `block-submodule-edit.sh` for Edit and Write tool calls. The hook prevents Claude Code from editing files inside any git submodule of the user's repo.
- `CHANGELOG.md` (this file).
- New CI job `plugin-structure` that validates the plugin layout without requiring the `claude` CLI.

### Changed

- **Repo restructured for plugin layout.** Skills, agents, and scripts have moved from `.claude/` to the repo root:
  - `.claude/skills/{design,implement,review,research,loop-review,shared}` → `skills/{...}`
  - `.claude/agents/*.md` → `agents/*.md`
  - `.claude/scripts/generic/larch/*` → `scripts/larch/*`
  - Symlinks under `.claude/` (`.claude/skills/*`, `.claude/agents/*`, `.claude/scripts/generic/larch`) preserve the legacy paths for existing tooling and for the private `/relevant-checks` skill.
- Path references in plugin-exported SKILL.md files and shared docs rewritten from `$PWD/.claude/scripts/generic/larch/` and `` `.claude/skills/shared/larch/`` to `${CLAUDE_PLUGIN_ROOT}/scripts/larch/` and `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/`. Paths in `.claude/skills/implement/` and `.claude/skills/loop-review/` also switched to `${CLAUDE_PLUGIN_ROOT}/skills/{implement,loop-review}/scripts/`.
- `.claude/settings.json` gained three defensive Bash permissions to cover the new canonical script locations: `$PWD/scripts/larch/*`, `$PWD/skills/implement/scripts/*`, and `$PWD/skills/loop-review/scripts/*`.
- `README.md` installation section replaced with a plugin-based install flow covering GitHub and local development paths.

### Removed

- `setup-larch.sh` (legacy git-submodule installer, superseded by the Claude Code plugin flow).
- `tests/test-setup-larch.sh` integration test and the CI job that invoked it.

### Notes for contributors (repo self-use)

Contributors working on larch itself should launch Claude Code with `--plugin-dir .` from the repo root so that `${CLAUDE_PLUGIN_ROOT}` resolves to the repo root and plugin-exported skills can find their scripts:

```bash
cd larch
claude --plugin-dir .
```

Alternatively, register the repo as a local marketplace and install:

```bash
claude plugin marketplace add .
claude plugin install larch@larch-local
```

The private `/relevant-checks` skill (at `.claude/skills/relevant-checks/`) is intentionally not exported as part of the plugin; each consuming repo maintains its own version.
