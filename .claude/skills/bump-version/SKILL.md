---
name: bump-version
description: Classify and apply a semantic version bump based on the current branch diff. Updates .claude-plugin/plugin.json and commits exactly one version-only commit. Invoked by /implement Step 8. Only inspects the public plugin surface (skills/**, agents/**) — changes under .claude/** default to PATCH.
allowed-tools: Bash, Read
---

# Bump Version

Classify and apply a semantic version bump for this PR. This is a repo-private skill invoked by `/implement` Step 8. It produces exactly ONE commit: a version-only edit of `.claude-plugin/plugin.json`.

## Classification rules

The classifier inspects **only the public plugin surface** — `skills/**` and `agents/**`. Changes under `.claude/**`, `scripts/**`, `hooks/**`, `docs/**`, `.github/**`, `CHANGELOG.md`, etc. do not contribute to MAJOR/MINOR classification and default the bump to PATCH.

Severity hierarchy: **MAJOR > MINOR > PATCH** (highest wins).

### MAJOR — backward-incompatible changes
Any of the following in `skills/**` or `agents/**`:
- A deleted `skills/*/SKILL.md` or `agents/*.md`
- A renamed `skills/*/SKILL.md` (git status `R`)
- A changed `name:` frontmatter field in an existing SKILL.md
- A `--<flag>` token removed from a SKILL.md's `argument-hint:` frontmatter field (token-set comparison; wording-only edits to the argument-hint that preserve all tokens do not count)

### MINOR — backward-compatible additions
Any of the following in `skills/**` or `agents/**` (only if not MAJOR):
- A newly added `skills/*/SKILL.md` or `agents/*.md`
- A `--<flag>` token added to a SKILL.md's `argument-hint:` frontmatter field

### PATCH — everything else
Default for all other changes. Every PR must bump at least PATCH per policy.

## Caveat — escalation-only clause

After `classify-bump.sh` computes its deterministic baseline, the main agent (you) reviews the full diff for **behavioral** changes that a reasonable client would judge as unexpectedly backward-incompatible relative to a skill's original intent — even when no signature changed.

**You may ONLY escalate severity (PATCH → MINOR → MAJOR). Never downgrade.**

If you escalate, append a paragraph to the reasoning log file explaining why.

## How it works

1. The caller (`/implement` Step 8) invokes this skill.
2. The skill runs `classify-bump.sh`, which:
   - Fetches `origin/main` (best-effort, non-fatal on failure)
   - Resolves `BASE` via `main` → `origin/main` fallback
   - Validates `.claude-plugin/plugin.json` via `jq`
   - Detects an **already-bumped branch** by checking whether HEAD itself is a commit with subject `^Bump version to [0-9]+\.[0-9]+\.[0-9]+$`. If HEAD is such a commit, emits `BUMP_TYPE=NONE` and exits 0 (no-op). If a bump exists earlier in the branch but additional commits have landed on top, a fresh bump is required.
   - Computes `git diff -M --name-status $BASE HEAD -- skills agents` for file-level classification (added/deleted/renamed SKILL.md and agent files)
   - For each modified SKILL.md, reads the old and new full file contents via `git show "$BASE:<path>"` and `git show "HEAD:<path>"`, extracts the first YAML frontmatter block between `---` markers, and compares the `name:` and `argument-hint:` fields. The `argument-hint:` comparison uses token sets: a `--<flag>` present in both old and new is treated as unchanged; only genuine additions or removals contribute to classification.
   - Writes evidence to `${IMPLEMENT_TMPDIR:-$PWD/.git}/bump-version-reasoning.md`
   - Emits `KEY=VALUE` lines on stdout: `CURRENT_VERSION`, `NEW_VERSION`, `BUMP_TYPE`, `REASONING_FILE`
3. You (main agent) parse the output, read the reasoning log, review the diff, and apply the **escalation-only** caveat review. If you escalate, update `NEW_VERSION` accordingly and append reasoning to the log.
4. You invoke `apply-bump.sh --new-version <NEW_VERSION>`, which:
   - First verifies the working tree is clean (fails on any staged or unstaged changes)
   - Backs up `.claude-plugin/plugin.json`
   - Rewrites the `version` field via `jq` (atomic via tmp + mv)
   - `git add` + `git commit -m "Bump version to <NEW_VERSION>"`
   - Rolls back from backup on commit failure
5. If `BUMP_TYPE=NONE`, skip the apply step and report "already bumped".

## Usage

```bash
${CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-$PWD}/.claude/skills/bump-version/scripts/classify-bump.sh
```

Parse the output for `CURRENT_VERSION`, `NEW_VERSION`, `BUMP_TYPE`, `REASONING_FILE`.

If `BUMP_TYPE=NONE`, report the no-op and exit.

Otherwise, review the reasoning log and the branch diff. Decide whether to escalate. If escalating, compute the new version from `CURRENT_VERSION` + your escalated bump type and append your reasoning to the log file.

Then apply:

```bash
$PWD/.claude/skills/bump-version/scripts/apply-bump.sh --new-version <NEW_VERSION>
```

## Output contract

The reasoning log at `${IMPLEMENT_TMPDIR:-$PWD/.git}/bump-version-reasoning.md` is read by `/implement` Step 9a and embedded into the PR body under `<details><summary>Version Bump Reasoning</summary>`.

## Exit codes
- `classify-bump.sh` — 0 on success (including `BUMP_TYPE=NONE`), non-zero on parse/validation failure
- `apply-bump.sh` — 0 on successful commit, non-zero on dirty worktree or commit failure (rollback performed)
