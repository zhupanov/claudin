---
name: relevant-checks
description: Run repo-specific validation checks (pre-commit on modified files + agent-lint on the full repo). Use when you need to validate code quality after implementation, after code review fixes, or when fixing CI failures.
allowed-tools: Bash
---

# Relevant Checks

Run validation checks scoped to files modified on current branch. Repo-specific skill — each repo define own `/relevant-checks` with checks fit repo.

## Mindset

Before diagnose failure, classify by phase: **changed-file phase** (`pre-commit run --files`) or **full-repo phase** (`agent-lint --pedantic`). Two phases of `run-checks.sh` not strictly "mechanical vs structural" — `.pre-commit-config.yaml` already route some structural hooks (e.g., agnix on SKILL.md/CLAUDE.md) through changed-file phase. Phase split: what script applied to changed files vs. what applied to whole repo. On **deletions-only branch**, changed-file phase skipped entirely (empty `files[]`) while full-repo phase still run.

**Maintenance rule.** Before edit `run-checks.sh` or skill, ask: change alter anything Failure-mode taxonomy table or NEVER list pin to — observable banners, exit paths, `WARNING:`/`ERROR:` lines, or script comment labels / branch names (e.g., `files[] empty but MODIFIED_FILES non-empty` branch)? If yes, update both script and doc in same commit — script source of truth, but doc decision table and NEVER bullets pinned to specific strings from it.

Skill DESCRIBES `run-checks.sh` behavior — NOT define new policy. If want add NEVER bullet or taxonomy row whose WHY not observable script branch or banner, reconsider: drift risk higher than doc value.

**Re-run after structural edits.** After fix that edit structure-adjacent files (SKILL.md, AGENTS.md, CHANGELOG.md, harness scripts, or anything `agent-lint` scan), re-invoke `/relevant-checks` even if changed-file phase passed first time — full-repo `agent-lint` pass may flag cross-file invariants (dangling references, orphaned harnesses, frontmatter mismatches) that changed-file phase cannot see in isolation.

## How it works

Changed files collected from branch diff, staged changes, unstaged changes, untracked files. Union passed to `pre-commit run --files`, which route each file to appropriate linter hooks based on file type. Deleted files filtered out automatically. See `.pre-commit-config.yaml` for authoritative hook list applied to changed-file phase — consulted at invocation time by `pre-commit`, evolve independently of skill.

After pre-commit linting succeed, `run-checks.sh` also invoke `agent-lint` (if on PATH) to catch structural regressions on full repo. Same linter CI's `agent-lint` job run, so devs catch structural breakage locally before push. If pre-commit fail, agent-lint skipped — only run when basic linting pass.

## Usage

Run private check script:

```bash
$PWD/.claude/skills/relevant-checks/scripts/run-checks.sh
```

Script auto-detect which files modified on current branch, filter to existing files, run `pre-commit run --files` on them. Pre-commit handle file-type routing internally — only hooks whose file patterns match changed files execute.

## Retry semantics

If script exit non-zero, one or more checks failed. Caller should:

1. Diagnose failure from script output
2. Fix issue
3. Re-invoke `/relevant-checks` to confirm fix

Pre-commit run all applicable hooks even if earlier ones fail, so see all failures at once.

## Failure-mode taxonomy

When `run-checks.sh` exit non-zero, classify by how exit:

| Exit path | Failure class | Remediation |
|-----------|---------------|-------------|
| Line `ERROR: pre-commit not found` printed, immediate exit 1 | Missing `pre-commit` binary | Install binary (`pip install pre-commit`, or package manager), re-invoke. `make setup` only wire hook via `pre-commit install` and still need binary exist first. |
| Line `ERROR: not inside a git repository` printed, immediate exit 1 | Not git worktree | `cd` into repo (or re-clone); re-invoke. |
| `=== Running pre-commit ...` banner printed, script exit non-zero **before** any `=== Running agent-lint ===` banner | Changed-file phase failure (file-scoped lint) | Read hook diffs/output, fix file(s), re-invoke. |
| `=== Running agent-lint ===` banner printed, script exit non-zero **after** it | Full-repo phase failure (structural) | Follow specific `agent-lint` finding — typical fixes update frontmatter, references, harnesses, or docs in same PR; re-invoke. |

Note: `WARNING: agent-lint not found on PATH — skipping` non-fatal — script still exit 0 on changed-file-phase success even without `agent-lint` installed. Install before merge if CI's `agent-lint` job run.

## Anti-patterns (NEVER)

- **NEVER substitute `git commit --no-verify` for `/relevant-checks`.** **Why:** `--no-verify` only skip local git `pre-commit` hook (optional, separate install); does NOT run or replace skill's checks. Always run `/relevant-checks` before merge.
- **NEVER assume deletions-only branch has nothing to check.** **Why:** `run-checks.sh` skip changed-file phase (empty `files[]`) but still run full-repo `agent-lint` phase — see `files[] empty but MODIFIED_FILES non-empty` branch. Deletions most common source of structural regressions (dangling references, orphaned harnesses).
- **NEVER read `/relevant-checks` exit 0 as "every gate ran green".** **Why:** exit 0 only guarantee each phase that *ran* passed — does NOT guarantee every phase ran. Reduced-coverage exit-0 outcomes to watch for:

  | Case | Observable signal | Coverage implication |
  |------|-------------------|----------------------|
  | No modified files detected | `No modified files detected — no checks to run.` → exit 0 | Zero phases ran (common on detached HEAD or freshly-reset tree) |
  | Deletions-only + `agent-lint` absent | `No existing modified files to check (all changes are deletions).` followed by `WARNING: agent-lint not found on PATH — skipping` | Zero phases ran |
  | `agent-lint` absent, changed-file phase ran | `WARNING: agent-lint not found on PATH — skipping` after successful pre-commit pass | Changed-file phase only; no structural coverage |

  CI's `agent-lint` job (and re-invocation once modified files exist on-branch) authoritative gate — exit 0 from `/relevant-checks` alone never substitute for it.
