# Claudin → Larch Migration Plan

The repository was renamed from `claudin` to `larch` via the GitHub UI. This document tracks the internal rename of all `claudin` references to `larch`, which is being done in two PRs to avoid disrupting in-flight skill sessions that depend on the current `claudin/` script paths.

## PR #1 — Additive copy (this PR)

Goal: Create `larch`-named copies of every `claudin`-named file/directory, with file contents in the copies rewritten (case-preserving) so that all `claudin` substrings become `larch`. The original `claudin`-named files remain byte-identical so in-flight sessions and existing references continue to work.

- [DONE] Copy `.claude/scripts/generic/claudin/` → `.claude/scripts/generic/larch/` with content rewritten (38 shell scripts)
- [DONE] Copy `.claude/skills/shared/claudin/` → `.claude/skills/shared/larch/` with content rewritten (3 markdown docs: `voting-protocol.md`, `external-reviewers.md`, `reviewer-templates.md`)
- [DONE] Copy `setup-claudin.sh` → `setup-larch.sh` with content rewritten
- [DONE] Copy `tests/test-setup-claudin.sh` → `tests/test-setup-larch.sh` with content rewritten
- [DONE] Add `.claude/scripts/generic/larch/*` Bash permission entry to `.claude/settings.json` (claudin entry kept)
- [DONE] Extend `.github/workflows/ci.yaml` to also run `tests/test-setup-larch.sh` as a separate named step with `if: always()` so both tests run independently (claudin test kept)
- [DONE] Verify each new larch file contains zero `claudin`/`Claudin`/`CLAUDIN` substrings
- [DONE] Verify each original claudin-named file is byte-identical to the pre-PR version
- [DONE] Verify `tests/test-setup-larch.sh` passes locally

### Case-preserving substitution rules applied in the copies

- `claudin` → `larch`
- `Claudin` → `Larch`
- `CLAUDIN` → `LARCH`

All three rules are applied as literal `sed` substitutions (not regex). The order — `CLAUDIN` first, then `Claudin`, then `claudin` — is defensive: even though the three substrings are mutually exclusive at the character level, longest-first case order is standard best practice.

### Dual-namespace behavior of `setup-larch.sh` during PR #1

During the PR #1 → PR #2 transition window, both `.claude/scripts/generic/claudin/` and `.claude/scripts/generic/larch/` subtrees coexist inside the (renamed) larch submodule. Because `setup-larch.sh` is a literal `sed`-substituted copy of `setup-claudin.sh`, it walks the entire submodule's `.claude/` tree (via the same `find` loop its parent uses) and creates symlinks for files in **both** subtrees.

This means a client repo running `setup-larch.sh` during the PR #1 window will end up with symlinks at **both** `.claude/scripts/generic/claudin/*` and `.claude/scripts/generic/larch/*`, both resolving into the (renamed) larch submodule. Similarly for the two shared-doc trees under `.claude/skills/shared/`.

This dual-namespace behavior is **intentional** and **benign**:
- Existing claudin-pathed callers (SKILL.md files, hooks, etc.) continue to work because the claudin symlinks and their target files both still exist.
- New larch-pathed callers also work because the larch symlinks and their target files also exist.
- It is the safest possible behavior for the dual-tree window: nothing that used to work stops working, and the new namespace is fully populated.

**This dual-namespace behavior resolves naturally in PR #2** when the claudin subtree is deleted from the submodule:
- `setup-larch.sh` in PR #2 sees only the larch tree and only creates larch symlinks.
- Any orphan claudin symlinks in the client repo (carried over from PR #1) will be removed by Phase 2 (dead-symlink cleanup) of `setup-larch.sh` because their resolved targets — for example `larch/.claude/scripts/generic/claudin/foo.sh` — will then point at deleted files, and Phase 2 specifically removes symlinks whose resolved targets live inside the larch submodule and no longer exist.

### Behavioral callout: `CLAUDIN_*` environment variables become `LARCH_*` in the copies

The case-preserving substitution rewrites `CLAUDIN_*` environment variable names to `LARCH_*` inside every new larch script. Specifically:

- `CLAUDIN_SLACK_BOT_TOKEN` → `LARCH_SLACK_BOT_TOKEN`
- `CLAUDIN_SLACK_CHANNEL_ID` → `LARCH_SLACK_CHANNEL_ID`
- `CLAUDIN_SLACK_USER_ID` → `LARCH_SLACK_USER_ID`

During the PR #1 window the new larch scripts are dead code (not invoked by any SKILL.md or hook — the in-flight skills still call the claudin paths), so this rename has **no runtime effect in PR #1**.

Once PR #2 cuts over (SKILL.md files, agents, settings.json hooks, and docs are all re-pointed to the larch paths, and the claudin originals are deleted), operators running these scripts **must** set the `LARCH_*` environment variables in their shell/CI environment. If an operator's existing environment has `CLAUDIN_SLACK_BOT_TOKEN` set but not `LARCH_SLACK_BOT_TOKEN`, the new larch scripts will treat the Slack token as missing and skip Slack posting with a warning. Document this clearly in the PR #2 release notes.

## PR #2 — Cutover and cleanup (follow-up, not done in this PR)

Goal: Switch all internal references from `claudin` paths to `larch` paths, then delete the claudin-named originals. After this PR, `grep -ri claudin .` (excluding `.git/` and this migration doc) should return zero matches.

- [TODO] Update content of `README.md` (replace `claudin` with `larch`, case-preserving)
- [TODO] Update content of `.claude/agents/general-reviewer.md`
- [TODO] Update content of `.claude/agents/deep-analysis-reviewer.md`
- [TODO] Update content of `.claude/skills/design/SKILL.md`
- [TODO] Update content of `.claude/skills/implement/SKILL.md`
- [TODO] Update content of `.claude/skills/research/SKILL.md`
- [TODO] Update content of `.claude/skills/review/SKILL.md`
- [TODO] Update content of `.claude/skills/loop-review/SKILL.md`
- [TODO] Update content of `.claude/skills/shazam/SKILL.md`
- [TODO] Update content of `docs/review-agents.md`
- [TODO] Update content of `.pre-commit-config.yaml` (header comment mentions "Claudin")
- [TODO] Update content of `Makefile` (header comment mentions "Claudin")
- [TODO] Remove `Bash($PWD/.claude/scripts/generic/claudin/*)` permission entry from `.claude/settings.json`
- [TODO] Remove `Bash(CLAUDIN_SLACK_USER_ID=:*)` from `.claude/settings.json` (if it proves vestigial — verify first that no script uses the inline env-var-prefix form)
- [TODO] Re-point the four hook entries in `.claude/settings.json` from `.claude/scripts/generic/claudin/block-submodule-edit.sh` and `.claude/scripts/generic/claudin/auto-goimports.sh` to the `.claude/scripts/generic/larch/` equivalents (lines ~235, 244, 255, 264 in the current file)
- [TODO] Remove the `Run claudin integration test` step from `.github/workflows/ci.yaml` (keeping only the larch integration test step, with the `if: always()` guard removed since there is no longer a predecessor step it needs to run after)
- [TODO] Delete `.claude/scripts/generic/claudin/` (directory and all 38 scripts)
- [TODO] Delete `.claude/skills/shared/claudin/` (directory and all 3 docs)
- [TODO] Delete `setup-claudin.sh`
- [TODO] Delete `tests/test-setup-claudin.sh`
- [TODO] Run `grep -ri claudin .` (excluding `.git/` and this migration doc) and verify zero matches
- [TODO] Document the `CLAUDIN_* → LARCH_*` env var rename in the PR #2 release notes so operators update their shell/CI environment variables
- [TODO] Mark this section DONE and merge PR #2

## Why two PRs?

The in-flight `/shazam` and `/implement` skill sessions running at the moment this migration is executed are currently invoking scripts under `.claude/scripts/generic/claudin/`. A single-PR rename would require modifying those scripts (or the SKILL.md files that reference them) mid-flight, risking breakage of the very skill session doing the migration. Splitting the work across two PRs guarantees that every file needed by the in-flight session remains byte-identical throughout PR #1; only after PR #1 has safely merged is it safe to mutate the originals in PR #2.
