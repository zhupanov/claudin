# Claudin → Larch Migration Plan

The repository was renamed from `claudin` to `larch` via the GitHub UI. This document tracks the internal rename of all `claudin` references to `larch`, which is being done in three PRs (PR #1, PR #2a, PR #2b) to avoid disrupting in-flight skill sessions that depend on the current `claudin/` script paths.

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

During the PR #1 → PR #2a transition window, both `.claude/scripts/generic/claudin/` and `.claude/scripts/generic/larch/` subtrees coexist inside the (renamed) larch submodule. Because `setup-larch.sh` is a literal `sed`-substituted copy of `setup-claudin.sh`, it walks the entire submodule's `.claude/` tree (via the same `find` loop its parent uses) and creates symlinks for files in **both** subtrees.

This means a client repo running `setup-larch.sh` during the PR #1 window will end up with symlinks at **both** `.claude/scripts/generic/claudin/*` and `.claude/scripts/generic/larch/*`, both resolving into the (renamed) larch submodule. Similarly for the two shared-doc trees under `.claude/skills/shared/`.

This dual-namespace behavior is **intentional** and **benign**:
- Existing claudin-pathed callers (SKILL.md files, hooks, etc.) continue to work because the claudin symlinks and their target files both still exist.
- New larch-pathed callers also work because the larch symlinks and their target files also exist.
- It is the safest possible behavior for the dual-tree window: nothing that used to work stops working, and the new namespace is fully populated.

**This dual-namespace behavior resolves naturally in PR #2b** when the claudin subtree is deleted from the submodule:
- `setup-larch.sh` after PR #2b sees only the larch tree and only creates larch symlinks.
- Any orphan claudin symlinks in the client repo (carried over from PR #1) will be removed by Phase 2 (dead-symlink cleanup) of `setup-larch.sh` because their resolved targets — for example `larch/.claude/scripts/generic/claudin/foo.sh` — will then point at deleted files, and Phase 2 specifically removes symlinks whose resolved targets live inside the larch submodule and no longer exist.

### Behavioral callout: `CLAUDIN_*` environment variables become `LARCH_*` in the copies

The case-preserving substitution rewrites `CLAUDIN_*` environment variable names to `LARCH_*` inside every new larch script. Specifically:

- `CLAUDIN_SLACK_BOT_TOKEN` → `LARCH_SLACK_BOT_TOKEN`
- `CLAUDIN_SLACK_CHANNEL_ID` → `LARCH_SLACK_CHANNEL_ID`
- `CLAUDIN_SLACK_USER_ID` → `LARCH_SLACK_USER_ID`

During the PR #1 window the new larch scripts are dead code (not invoked by any SKILL.md or hook — the in-flight skills still call the claudin paths), so this rename has **no runtime effect in PR #1**.

Once PR #2a cuts over (SKILL.md files, agents, settings.json hooks, and docs are all re-pointed to the larch paths) and PR #2b deletes the claudin originals, operators running these scripts **must** set the `LARCH_*` environment variables in their shell/CI environment. If an operator's existing environment has `CLAUDIN_SLACK_BOT_TOKEN` set but not `LARCH_SLACK_BOT_TOKEN`, the new larch scripts will treat the Slack token as missing and skip Slack posting with a warning. Document this clearly in the PR #2a and PR #2b release notes.

## PR #2a — Cutover only (this PR)

Goal: Switch all internal references from `claudin` paths to `larch` paths, but leave the claudin-named originals on disk. The final `grep -ri claudin .` zero-match verification is deferred to PR #2b.

- [DONE] Update content of `README.md` (replace `claudin` with `larch`, case-preserving)
- [DONE] Update content of `.claude/agents/general-reviewer.md`
- [DONE] Update content of `.claude/agents/deep-analysis-reviewer.md`
- [DONE] Update content of `.claude/skills/design/SKILL.md`
- [DONE] Update content of `.claude/skills/implement/SKILL.md`
- [DONE] Update content of `.claude/skills/research/SKILL.md`
- [DONE] Update content of `.claude/skills/review/SKILL.md`
- [DONE] Update content of `.claude/skills/loop-review/SKILL.md`
- [DONE] Update content of `.claude/skills/shazam/SKILL.md`
- [DONE] Update content of `docs/review-agents.md`
- [DONE] Update content of `docs/agents.md` (not in the original PR #2 list — contains "Claudin" references that would fail final grep verification)
- [DONE] Update content of `docs/external-reviewers.md` (not in the original PR #2 list)
- [DONE] Update content of `docs/workflow-lifecycle.md` (not in the original PR #2 list)
- [DONE] Update content of `.pre-commit-config.yaml` (header comment mentions "Claudin")
- [DONE] Update content of `Makefile` (header comment mentions "Claudin")
- [DONE] Re-point the four hook entries in `.claude/settings.json` from `.claude/scripts/generic/claudin/block-submodule-edit.sh` and `.claude/scripts/generic/claudin/auto-goimports.sh` to the `.claude/scripts/generic/larch/` equivalents
- [DONE] Remove the `Run claudin integration test` step from `.github/workflows/ci.yaml` (keeping only the larch integration test step, with the `if: always()` guard removed since there is no longer a predecessor step it needs to run after)
- [DONE] Extend `tests/test-setup-larch.sh` to simulate a PR #1-upgraded client repo with stale `.claude/scripts/generic/claudin/*` and `.claude/skills/shared/claudin/*` symlinks and assert they are removed after rerunning `setup-larch.sh` (validates the Phase 2 dead-symlink cleanup that PR #2b's deletion will trigger in real client repos)
- [DONE] Document the `CLAUDIN_* → LARCH_*` env var rename and the downstream client settings.json migration requirement in this PR's release notes

## PR #2b — Cleanup (follow-up, not done in this PR)

Goal: Remove the claudin-named originals. After this PR, `grep -ri claudin .` (excluding `.git/` and this migration doc) must return zero matches.

- [TODO] Remove `Bash($PWD/.claude/scripts/generic/claudin/*)` permission entry from `.claude/settings.json`
- [TODO] Remove `Bash(CLAUDIN_SLACK_USER_ID=:*)` from `.claude/settings.json` (verified vestigial in PR #2a — only used as bare assignment inside `slack-announce.sh`, never as inline env-var-prefix form)
- [TODO] Delete `.claude/scripts/generic/claudin/` (directory and all 38 scripts)
- [TODO] Delete `.claude/skills/shared/claudin/` (directory and all 3 docs)
- [TODO] Delete `setup-claudin.sh`
- [TODO] Delete `tests/test-setup-claudin.sh`
- [TODO] Run `grep -ri claudin .` (excluding `.git/` and this migration doc) and verify zero matches
- [TODO] Mark this section DONE and merge PR #2b

## Why three PRs (PR #1, PR #2a, PR #2b)?

The in-flight `/shazam` and `/implement` skill sessions running at the moment this migration is executed are currently invoking scripts under `.claude/scripts/generic/claudin/`. A single-PR rename would require modifying those scripts (or the SKILL.md files that reference them) mid-flight, risking breakage of the very skill session doing the migration. PR #1 solved half the problem by creating byte-identical `larch`-named copies without touching the originals.

Initially PR #2 was planned as a single cutover+deletion PR, but during plan review (by the 5-reviewer voting panel) a critical hazard was surfaced: **the running /shazam session has SKILL.md files already loaded in its context window with claudin-path references for ALL later steps** (version bump, CI monitor, Slack, cleanup, merge loop). Rewriting the SKILL.md files on disk in the same session does NOT retarget the already-running agent — it continues to invoke claudin paths from its in-memory instructions. Deleting the claudin script tree in the same live session that depends on those scripts would cause every subsequent `.claude/scripts/generic/claudin/*` invocation to fail with ENOENT after the deletion commit lands.

PR #2 was therefore split into PR #2a and PR #2b:

- **PR #2a** (this PR) — Cutover only: rewrite all references to point at larch paths, but leave the claudin script tree intact on disk. The running /shazam session's in-memory SKILL.md still references claudin paths, but those claudin scripts still exist, so everything works. The final `grep -ri claudin` zero-match verification is deferred.

- **PR #2b** (follow-up, separate session) — Cleanup: delete the claudin script tree (`.claude/scripts/generic/claudin/` and `.claude/skills/shared/claudin/`) along with the legacy entry-point scripts (`setup-claudin.sh` and `tests/test-setup-claudin.sh`), remove the claudin Bash permission entries from settings.json, and verify the final grep. (See the PR #2b checklist above for the full item list.) PR #2b must be run in a **fresh /shazam or /implement session** — one that loads the rewritten (larch-referencing) SKILL.md files from the outset, so all its tool invocations use larch paths and the claudin scripts can be safely deleted.
