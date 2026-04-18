# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [3.1.0] - 2026-04-18

### Added

- New `/issue` skill (`skills/issue/SKILL.md`) that creates a GitHub issue in the current repository from a free-form description. With the optional `--go` flag, it additionally posts a final `GO` comment on the new issue so it becomes immediately eligible for `/fix-issue` automation without manual approval. `skills/alias/SKILL.md` now reserves the `issue` name so project-level aliases cannot collide with the shipped skill. README install blurb, Skills summary row, and skills table updated to document `/issue`.

## [3.0.7] - 2026-04-18

### Changed

- `/fix-issue` now skips candidates with currently-open blocking dependencies. After an issue passes the `GO` sentinel check, `fetch-eligible-issue.sh` queries GitHub's native issue-dependencies API (`repos/{owner}/{repo}/issues/{N}/dependencies/blocked_by`); if any blocker is still in the `open` state, auto-pick mode continues scanning and explicit `--issue` mode reports ineligible with the blocker list. The dependency lookup uses `gh api --paginate --jq` so results across multiple pages are merged correctly. API errors (404 on repos without the feature, 5xx, transient gh failures) degrade silently to the prior GO-only behavior so dependency-API availability never hard-blocks the automation; the degradation is documented under the skill's Known Limitations.

## [3.0.6] - 2026-04-18

### Changed

- Code Reviewer archetype (`agents/code-reviewer.md` and `skills/shared/reviewer-templates.md`) tuned with severity tags (`**Important**` / `**Nit**` / `**Latent**`, with a PR-introduced-defect tiebreaker), a conservatism header ("when in doubt, say nothing"), an explicit "Do NOT report" exclusion list, a context-sensitive proof-before-report clause for `**Important**` findings (failing scenario or concrete breakage path), a Nit cap of 5 with a required "count plus categories" overflow summary, a tightened Quality gate that applies uniformly to In-Scope and Out-of-Scope findings with review-mode-appropriate evidence (file:line for code review; plan/validation anchors otherwise), Style consistency and red-green-TDD-that-should-have-happened both demoted to `**Nit**`-only, Backward compatibility and Thread safety folded into §2 Breaking changes and §3 Race conditions via cross-references that preserve legacy vocabulary, and the 5-step "Review process" softened into "Review priorities (in order, not a sequence)" to reduce premature stopping or anchoring. Phase 1 is Claude-lane-only — external Codex/Cursor reviewers still run their inline prompts from the individual skill SKILL.md files, so severity tags and the conservatism/exclusion rules reach Claude reviewers and Claude fallbacks only; external-lane alignment is deferred to a follow-up phase. Closes #91.

## [3.0.5] - 2026-04-18

### Changed

- `/research` refactored from a 5+5 lane composition to 3+3. Phase 1 (Research) now launches 3 agents — Claude inline + Cursor + Codex — all running a single uniform `RESEARCH_PROMPT` that requires alternative perspectives, edge cases/gaps, architectural patterns, and risks/feasibility. Phase 2 (Validation) now launches 3 lanes — Codex deep + Codex broad + Cursor generic. Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant in each phase when an external tool is unavailable, with per-slot attribution (Cursor-unavailable → 1 generic Claude lane; Codex-unavailable → 2 Claude lanes, deep + broad). Both phases build a `COLLECT_ARGS` list from only actually-launched externals and skip `collect-reviewer-results.sh` entirely when zero externals are launched. Runtime external timeouts trigger an immediate same-phase Claude fallback so the 3-lane invariant holds at synthesis/negotiation time. Docs, diagram, and progress-reporting examples are synced across `README.md`, `docs/agents.md`, `docs/review-agents.md`, `docs/workflow-lifecycle.md`, `docs/external-reviewers.md`, `docs/collaborative-sketches.md`, `skills/shared/progress-reporting.md`, `skills/shared/voting-protocol.md`, and `skills/research/diagram.svg`.

## [3.0.4] - 2026-04-18

### Changed

- `/implement --quick` code review now uses a single-reviewer loop with the Cursor → Codex → Claude Code Reviewer subagent fallback chain, re-reviewing up to 5 rounds when a round's fixes introduce significant changes. Previously, quick mode ran a single Claude subagent for one round with no re-review. The fallback chain re-evaluates per round so runtime timeouts cascade to the next tier. Step 0 now explicitly sets the `cursor_available`/`codex_available` mental flags consumed by the new Step 5 selection logic.

## [3.0.3] - 2026-04-18

### Fixed

- `/implement` and `/bump-version` no longer touch `$PWD/.git/`. The classify-bump.sh reasoning-log default path moved from `$PWD/.git/bump-version-reasoning.md` to `${TMPDIR:-/tmp}/bump-version-reasoning.md`, and `/implement` Step 8 now parses the absolute path from `classify-bump.sh`'s `REASONING_FILE=<path>` stdout line instead of reconstructing it from `IMPLEMENT_TMPDIR`. Fixes a permission-prompt storm that occurred when the Skill tool invocation lost the env var and `/implement` fell back to copying the reasoning file out of `.git/`.

### Added

- Ten git wrapper scripts under `scripts/` that replace direct `git` commands in `skills/implement/SKILL.md`: `git-current-branch.sh`, `git-amend-add.sh`, `git-force-push.sh` (with internal fetch/compare/retry recovery), `git-sync-local-main.sh`, `git-rebase-skip.sh`, `git-conflict-files.sh`, `git-show-stage.sh`, `git-checkout-ours.sh`, `git-stage.sh`, and `git-push.sh`. Each is pre-approved by `settings.json`'s `Bash($PWD/scripts/*)` rule, so invoking them does not trigger per-command permission prompts. `skills/implement/SKILL.md` updated at every call site (Step 1 branch capture, Step 8a CHANGELOG amend, Rebase + Re-bump Sub-procedure steps 3/4a/5/6, Conflict Resolution Procedure Phase 1 + Phase 4 Exit 3, Step 10/12c CI fix handlers).

## [3.0.2] - 2026-04-18

### Changed

- Renamed the top-level heading in `KARPATHY_CLAUDE.md` from `# CLAUDE.md` to `# KARPATHY_CLAUDE.md` to match the filename.

## [3.0.1] - 2026-04-18

### Added

- `KARPATHY_CLAUDE.md` at repo root — verbatim copy of Andrej Karpathy's coding guidelines (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution).
- `@KARPATHY_CLAUDE.md` include added to root `CLAUDE.md` after the existing `@AGENTS.md` include, loading the guidelines into developer context when working inside this repo.

## [3.0.0] - 2026-04-18

### Changed

- Reviewer consolidation: `/design` plan review, `/review` code review, and `/implement` Phase 3 conflict-review now run a unified 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor) instead of the previous 5-reviewer panel (2 Claude + 2 Codex + 1 Cursor). `/implement` quick-mode drops from 2 Claude subagents to 1.
- Sketch phase composition changed from 3 Claude + 1 Cursor + 1 Codex to 1 Claude General + 2 Cursor + 2 Codex. The four non-general personalities (Architecture/Standards, Edge-cases/Failure-modes, Innovation/Exploration, Pragmatism/Safety) now live on the external slots (Cursor: Arch + Edge; Codex: Innovation + Pragmatism), with per-slot Claude fallbacks preserving the 5-agent invariant when a tool is unavailable.
- Unified Code Reviewer archetype in `skills/shared/reviewer-templates.md` replaces the previous Reviewer A (General) and Reviewer B (Deep Analysis) archetypes. The new archetype covers code quality, risk/integration, correctness, and architecture in one prompt with mandatory per-finding focus-area tagging.
- Voter 1 canonical label is now `Claude Code Reviewer subagent` in both `/design` and `/review` (previously split between Deep Analysis and General names).
- Attribution strings in round summaries and reviewer competition scoreboards collapse from `General / Deep-Analysis / Codex-General / Codex-Deep-Analysis / Cursor` to `Code / Codex / Cursor`.
- Output file paths for the single Codex review launch are now `codex-plan-output.txt` (design) and `codex-output.txt` (review); the old `codex-general-*` / `codex-deep-*` names are no longer emitted by these skills.
- `skills/research/SKILL.md` and `skills/loop-review/SKILL.md` retained a 5-reviewer composition under the Negotiation Protocol at this version; their two Claude lanes are attributed as `Code Reviewer (broad perspective)` and `Code Reviewer (deep perspective)`, both invoking the unified archetype. (`/research` was later refactored to a 3-lane composition — see subsequent changelog entries.)
- `scripts/reviewer-model-args.sh` gained a `--with-effort` opt-in flag. When passed, it emits `-c model_reasoning_effort="$EFFORT"` for Codex, where EFFORT resolves from `LARCH_CODEX_EFFORT` → `CLAUDE_PLUGIN_OPTION_CODEX_EFFORT` → default `high`. Default (no flag) behavior is unchanged — health probes and negotiation callers do not pass `--with-effort` and therefore remain at Codex's default effort.
- `.claude-plugin/plugin.json` adds `codex_effort` userConfig (default `high`). The plugin-level description is updated to reflect the new reviewer composition.

### Added

- New `agents/code-reviewer.md` agent definition (unified Code Reviewer archetype, model: sonnet, Read/Grep/Glob tools).
- New `LARCH_CODEX_EFFORT` environment variable and `codex_effort` plugin userConfig knob.

### Removed

- `agents/general-reviewer.md` and `agents/deep-analysis-reviewer.md` — replaced by the unified `code-reviewer` agent. **Migration note**: consumers that referenced `general-reviewer` or `deep-analysis-reviewer` directly (via `--agents` or subagent_type references in downstream docs/scripts) must switch to `code-reviewer`.

## [2.3.5] - 2026-04-17

### Added

- Integrated agnix linter for AI agent configuration validation (pre-commit hook, Makefile target, CI job)
- Created `.agnix.toml` config suppressing file-length rules and false positives for this plugin repo
- Fixed all agnix warnings in `AGENTS.md` and `.claude/settings.json`
- Added hook timeout to shipped `hooks/hooks.json` for consumer parity

## [2.3.4] - 2026-04-16

### Changed

- Split `CLAUDE.md` into a thin `@AGENTS.md` include and a new `AGENTS.md` with terse agent-generic editing guidance
- Upgraded agent-lint from v2.2.4 to v2.3.2 and aligned pre-commit, CI, and config syntax (`ignore` → `suppress`)

## [2.3.3] - 2026-04-15

### Added

- Added `agent-lint` v2.2.4 as a pre-commit hook with `--pedantic` flag
- Added `agent-lint` Make target for standalone invocation
- Aligned `--pedantic` flag across all agent-lint invocations (CI action, `/relevant-checks` post-check)

## [2.3.2] - 2026-04-15

### Changed

- Dropped the Description column from the Aliases table in README.md for a leaner two-column layout

## [2.3.1] - 2026-04-15

### Changed

- Changed `/imaq` `argument-hint` from `<feature-description>` to `<arguments>` to match `/im`, signaling that extra flags are forwarded to `/implement`
- Fixed `generate-alias.sh` to emit `<arguments>` as the argument-hint for newly generated aliases

## [2.3.0] - 2026-04-15

### Changed

- Added `.diag` diagnostic files to `run-external-reviewer.sh` for timeout, failure, and empty output cases
- Health check failure banners in `session-setup.sh` now include the specific cause of failure
- `collect-reviewer-results.sh` emits `FAILURE_REASON` field explaining why each non-OK reviewer failed
- Updated `external-reviewers.md` and `voting-protocol.md` to instruct including failure reasons in all user-facing messages

## [2.2.0] - 2026-04-15

### Added

- Migrated `/im` and `/imaq` aliases from project-level (`.claude/skills/`) to plugin-exported (`skills/`) so they ship to all consumers
- Added `Aliases` subsection in README.md Skills section documenting both shortcuts
- Added `/im` and `/imaq` to all skill inventory locations (README, CLAUDE.md, settings.json)
- Added `im` and `imaq` to `/alias` reserved-name list

## [2.1.3] - 2026-04-15

### Added

- `/imaq` project-level alias for `/implement --merge --auto --quick`
- `argument-hint` field emission in `generate-alias.sh` for agent-lint compliance

## [2.1.2] - 2026-04-14

### Added

- `/im` project-level alias for `/implement --merge`
- `Skill(im)` permission entry in `.claude/settings.json` for development harness consistency

## [2.1.1] - 2026-04-14

### Changed

- `/fix-issue` now accepts issue number or URL as a positional argument (e.g., `/fix-issue 42`) instead of requiring the `--issue` flag
- Deprecated `--issue` flag with backward compatibility and runtime deprecation warning
- Added guard against multiple positional arguments in `fetch-eligible-issue.sh`

## [2.1.0] - 2026-04-14

### Changed

- `/alias` now delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR) instead of writing files directly
- Added `--merge` flag to `/alias` to optionally merge the PR after CI passes
- Renamed `claude-lint` CI job to `agent-lint` and upgraded to `zhupanov/agent-lint@v2`
- Renamed `claude-lint.toml` to `agent-lint.toml` and updated all references across codebase

## [2.0.10] - 2026-04-13

### Changed

- Replaced `▶` step start icon with `🔶` (large orange diamond) across all skills for improved visibility
- Added blockquote wrapping (`>`) to step start lines for color differentiation
- Updated all inline `Print:` directives to include full `> **🔶 ...**` format for consistency with the shared progress reporting contract

## [2.0.9] - 2026-04-13

### Changed

- Moved lock step before triage in `/fix-issue` (Step 2 → before read details and triage) to eliminate race conditions where concurrent runs could claim the same issue during triage
- Enhanced triage close to include detailed research summary explaining why the issue is no longer material
- Combined `update-body` + `close` into a single `issue-lifecycle.sh close --pr-url` call, eliminating a consecutive Bash call anti-pattern in Step 7
- Replaced saved `$SLACK_TOKEN`/`$SLACK_CHANNEL` variables with inline env var expansion to eliminate unnecessary env var resolution Bash call in Step 0
- Fixed `cmd_update_body` using `exit` instead of `return` for error paths, which would bypass `cmd_close`'s error guard when called as an internal function

## [2.0.8] - 2026-04-13

### Changed

- Replaced `▸` step start icon with `▶` (filled, more visible) across all skills
- Added 80-char `━` separator line and bold formatting for step start lines
- Expanded elapsed time to all terminal lines: `⏩`, `⏭️`, `❌` (status tables), and step-ending `⚠` — not just `✅`
- Clarified "step-ending ⚠" definition in progress reporting contract

## [2.0.7] - 2026-04-13

### Fixed

- Fixed multi-line description truncation in `scripts/create-oos-issues.sh` — the parser now accumulates continuation lines between `- **Description**:` and the next structured field, preserving full multi-line descriptions in filed GitHub issues

## [2.0.6] - 2026-04-13

### Changed

- Added elapsed time reporting to all `✅` completion indicators — step completion lines show `(<elapsed>)` and compact status tables show timing after each `✅`
- Defined elapsed time format rules in `skills/shared/progress-reporting.md` (central contract)
- Updated all `Print:` directives across all 7 skills to include `(<elapsed>)` placeholders

## [2.0.5] - 2026-04-13

### Changed

- Added deduplication to `create-oos-issues.sh` — fetches open issues before creating new ones and skips creation when a normalized-title match already exists
- Updated SKILL.md Step 9a.1 to document new `ISSUES_DEDUPLICATED` output field and dedup reporting in PR body

## [2.0.4] - 2026-04-13

### Changed

- Replaced OOS promotion with GitHub issue filing — accepted OOS items are filed as issues instead of being implemented in the PR
- Switched OOS scoring from floor-of-0 to symmetric -1/0/+1, matching in-scope finding scoring
- Added `scripts/create-oos-issues.sh` for automated OOS issue creation at PR time
- Updated voter prompt template with OOS-specific vote semantics and output format examples

## [2.0.3] - 2026-04-13

### Removed

- Deleted `scripts/validate-plugin-structure.sh` (25 bash validators) and `scripts/smoke-test.sh` wrapper, superseded by claude-lint
- Removed `plugin-structure` CI job; claude-lint is now the sole structural linter in CI
- Updated GitHub ruleset to require `claude-lint` instead of `plugin-structure`

## [2.0.2] - 2026-04-13

### Fixed

- Added 1-retry to Codex and Cursor health check probes to tolerate transient timeouts

## [2.0.1] - 2026-04-13

### Changed

- Added quality-improvement instructions across all reviewer archetypes: strengthened test coverage emphasis, TDD guidance for implementation, and a proportionality quality gate ("Is it justified? Is it over-engineered?") for reviewers, voters, and the antithesis agent

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
