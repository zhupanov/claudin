---
name: bump-version
description: Use when applying a version bump after implementation. Classify and apply a semantic version bump based on the current branch diff. Updates .claude-plugin/plugin.json and commits exactly one version-only commit. Invoked by /implement Step 8. Only inspects the public plugin surface (skills/**, agents/**) — changes under .claude/** default to PATCH.
allowed-tools: Bash, Read
---

# Bump Version

Classify + apply semantic version bump for PR. Dev-only skill, invoked by `/implement` Step 8. Produces ONE commit: version-only edit of `.claude-plugin/plugin.json`.

## Classification rules

Classifier inspect **only public plugin surface** — `skills/**` and `agents/**`. Changes under `.claude/**`, `scripts/**`, `hooks/**`, `docs/**`, `.github/**`, `CHANGELOG.md`, etc. no contribute to MAJOR/MINOR, default to PATCH.

Severity: **MAJOR > MINOR > PATCH** (highest win).

### MAJOR — backward-incompatible changes
Any below in `skills/**` or `agents/**`:
- Deleted `skills/*/SKILL.md` or `agents/*.md`
- Renamed `skills/*/SKILL.md` (git status `R`)
- Changed `name:` frontmatter field in existing SKILL.md
- `--<flag>` token removed from SKILL.md `argument-hint:` frontmatter (token-set compare; wording-only edits that keep all tokens no count)

### MINOR — backward-compatible additions
Any below in `skills/**` or `agents/**` (only if not MAJOR):
- New `skills/*/SKILL.md` or `agents/*.md`
- `--<flag>` token added to SKILL.md `argument-hint:` frontmatter

### PATCH — everything else
Default for all else. Every PR must bump at least PATCH per policy.

## Caveat — escalation-only clause

After `classify-bump.sh` compute deterministic baseline, main agent (you) review full diff for **behavioral** changes reasonable client judge unexpectedly backward-incompatible vs skill original intent — even when no signature change.

**You may ONLY escalate severity (PATCH → MINOR → MAJOR). Never downgrade.**

If escalate, append paragraph to reasoning log file explain why.

## How it works

1. Caller (`/implement` Step 8) invoke skill.
2. Skill run `classify-bump.sh`, which:
   - Fetch `origin/main` (best-effort, non-fatal on fail)
   - Resolve `BASE` via `main` → `origin/main` fallback
   - Validate `.claude-plugin/plugin.json` via `jq`
   - Detect **already-bumped branch** by check whether HEAD itself commit with subject `^Bump version to [0-9]+\.[0-9]+\.[0-9]+$`. If HEAD such commit, emit `BUMP_TYPE=NONE` + exit 0 (no-op). If bump exist earlier in branch but more commits landed on top, fresh bump needed.
   - Compute `git diff -M --name-status $BASE HEAD -- skills agents` for file-level classification (added/deleted/renamed SKILL.md + agent files)
   - For each modified SKILL.md, read old + new full file contents via `git show "$BASE:<path>"` and `git show "HEAD:<path>"`, extract first YAML frontmatter block between `---` markers, compare `name:` + `argument-hint:` fields. `argument-hint:` compare use token sets: `--<flag>` present in both old + new treated unchanged; only genuine adds or removes contribute to classification.
   - Write evidence to `${IMPLEMENT_TMPDIR:-${TMPDIR:-/tmp}}/bump-version-reasoning.md` (absolute path also emitted as `REASONING_FILE=<path>` on stdout)
   - Emit `KEY=VALUE` lines on stdout: `CURRENT_VERSION`, `NEW_VERSION`, `BUMP_TYPE`, `REASONING_FILE`
3. You (main agent) parse output, read reasoning log, review diff, apply **escalation-only** caveat review. If escalate, update `NEW_VERSION` + append reasoning to log.
4. You invoke `apply-bump.sh --new-version <NEW_VERSION>`, which:
   - First verify working tree clean (fail on any staged/unstaged change)
   - Back up `.claude-plugin/plugin.json`
   - Rewrite `version` field via `jq` (atomic via tmp + mv)
   - `git add` + `git commit -m "Bump version to <NEW_VERSION>"`
   - Roll back from backup on commit fail
5. If `BUMP_TYPE=NONE`, skip apply step + report "already bumped".

## Usage

```bash
${CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-$PWD}/.claude/skills/bump-version/scripts/classify-bump.sh
```

Parse output for `CURRENT_VERSION`, `NEW_VERSION`, `BUMP_TYPE`, `REASONING_FILE`.

If `BUMP_TYPE=NONE`, report no-op + exit.

Else, review reasoning log + branch diff. Decide whether escalate. If escalate, compute new version from `CURRENT_VERSION` + escalated bump type and append reasoning to log file.

Then apply:

```bash
$PWD/.claude/skills/bump-version/scripts/apply-bump.sh --new-version <NEW_VERSION>
```

## Output contract

Reasoning log at `${IMPLEMENT_TMPDIR:-${TMPDIR:-/tmp}}/bump-version-reasoning.md` read by `/implement` Step 9a + embedded into PR body under `<details><summary>Version Bump Reasoning</summary>`. Absolute path also emitted on stdout by `classify-bump.sh` as `REASONING_FILE=<path>` — callers should prefer that structured output over reconstructing path from env vars.

## Exit codes
- `classify-bump.sh` — 0 on success (including `BUMP_TYPE=NONE`), non-zero on parse/validation fail
- `apply-bump.sh` — 0 on successful commit, non-zero on dirty worktree or commit fail (rollback done)
