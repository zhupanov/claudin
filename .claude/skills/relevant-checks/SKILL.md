---
name: relevant-checks
description: Run repo-specific validation checks (pre-commit on modified files + agent-lint on the full repo). Use when you need to validate code quality after implementation, after code review fixes, or when fixing CI failures.
allowed-tools: Bash
---

# Relevant Checks

Run validation checks scoped to files modified on the current branch. This is a repo-specific skill — each repository defines its own `/relevant-checks` with checks appropriate for that repo.

## Mindset

Before diagnosing a failure, classify it by phase: **changed-file phase** (`pre-commit run --files`) or **full-repo phase** (`agent-lint --pedantic`). The two phases of `run-checks.sh` are not strictly "mechanical vs structural" — `.pre-commit-config.yaml` already routes some structural hooks (e.g., agnix on SKILL.md/CLAUDE.md) through the changed-file phase. The phase-based split is: what the script applied to the changed files vs. what it applied to the whole repo. On a **deletions-only branch**, the changed-file phase is skipped entirely (empty `files[]`) while the full-repo phase still runs.

**Maintenance rule.** Before editing `run-checks.sh` or this skill, ask: does the change alter anything the Failure-mode taxonomy table or the NEVER list pins to — observable banners, exit paths, `WARNING:`/`ERROR:` lines, or script comment labels / branch names (e.g., the `files[] empty but MODIFIED_FILES non-empty` branch)? If yes, update both the script and the doc in the same commit — the script is the source of truth, but the doc's decision table and NEVER bullets are pinned to specific strings from it.

This skill DESCRIBES `run-checks.sh` behavior — it does NOT define new policy. If you find yourself wanting to add a NEVER bullet or taxonomy row whose WHY is not an observable script branch or banner, reconsider: the drift risk is higher than the doc value.

**Re-run after structural edits.** After a fix that edits structure-adjacent files (SKILL.md, AGENTS.md, CHANGELOG.md, harness scripts, or anything `agent-lint` scans), re-invoke `/relevant-checks` even if the changed-file phase passed the first time — the full-repo `agent-lint` pass may flag cross-file invariants (dangling references, orphaned harnesses, frontmatter mismatches) that the changed-file phase cannot see in isolation.

## How it works

Changed files are collected from the branch diff, staged changes, unstaged changes, and untracked files. The union is passed to `pre-commit run --files`, which routes each file to the appropriate linter hooks based on file type. Deleted files are filtered out automatically. See `.pre-commit-config.yaml` for the authoritative hook list applied to the changed-file phase — it is consulted at invocation time by `pre-commit` and evolves independently of this skill.

After pre-commit linting succeeds, `run-checks.sh` additionally invokes `agent-lint` (if available on PATH) to catch structural regressions on the full repository. This is the same linter that CI's `agent-lint` job runs, so developers can catch structural breakage locally before pushing. If pre-commit fails, agent-lint is skipped — only run when basic linting passes.

## Usage

Run the private check script:

```bash
$PWD/.claude/skills/relevant-checks/scripts/run-checks.sh
```

The script automatically detects which files were modified on the current branch, filters to existing files, and runs `pre-commit run --files` on them. Pre-commit handles file-type routing internally — only hooks whose file patterns match the changed files will execute.

## Retry semantics

If the script exits non-zero, one or more checks failed. The caller should:

1. Diagnose the failure from the script output
2. Fix the issue
3. Re-invoke `/relevant-checks` to confirm the fix

Pre-commit runs all applicable hooks even if earlier ones fail, so you can see all failures at once.

## Failure-mode taxonomy

When `run-checks.sh` exits non-zero, classify by how it exited:

| Exit path | Failure class | Remediation |
|-----------|---------------|-------------|
| Line `ERROR: pre-commit not found` printed, immediate exit 1 | Missing `pre-commit` binary | Install the binary (`pip install pre-commit`, or your package manager), then re-invoke. `make setup` only wires the hook via `pre-commit install` and still requires the binary to exist first. |
| Line `ERROR: not inside a git repository` printed, immediate exit 1 | Not a git worktree | `cd` into the repo (or re-clone); re-invoke. |
| `=== Running pre-commit ...` banner printed, script exits non-zero **before** any `=== Running agent-lint ===` banner | Changed-file phase failure (file-scoped lint) | Read hook diffs/output, fix the file(s), re-invoke. |
| `=== Running agent-lint ===` banner printed, script exits non-zero **after** it | Full-repo phase failure (structural) | Follow the specific `agent-lint` finding — typical fixes update frontmatter, references, harnesses, or docs in the same PR; re-invoke. |

Note: `WARNING: agent-lint not found on PATH — skipping` is non-fatal — the script still exits 0 on changed-file-phase success even without `agent-lint` installed. Install it before merging if CI's `agent-lint` job runs.

## Anti-patterns (NEVER)

- **NEVER substitute `git commit --no-verify` for `/relevant-checks`.** **Why:** `--no-verify` only skips the local git `pre-commit` hook (an optional, separate install); it does NOT run or replace this skill's checks. Always run `/relevant-checks` before the merge.
- **NEVER assume a deletions-only branch has nothing to check.** **Why:** `run-checks.sh` skips the changed-file phase (empty `files[]`) but still runs the full-repo `agent-lint` phase — see the `files[] empty but MODIFIED_FILES non-empty` branch. Deletions are the most common source of structural regressions (dangling references, orphaned harnesses).
- **NEVER read `/relevant-checks` exit 0 as "every gate ran green".** **Why:** exit 0 only guarantees that each phase that *ran* passed — it does NOT guarantee that every phase ran. Reduced-coverage exit-0 outcomes to watch for:

  | Case | Observable signal | Coverage implication |
  |------|-------------------|----------------------|
  | No modified files detected | `No modified files detected — no checks to run.` → exit 0 | Zero phases ran (common on detached HEAD or freshly-reset tree) |
  | Deletions-only + `agent-lint` absent | `No existing modified files to check (all changes are deletions).` followed by `WARNING: agent-lint not found on PATH — skipping` | Zero phases ran |
  | `agent-lint` absent, changed-file phase ran | `WARNING: agent-lint not found on PATH — skipping` after a successful pre-commit pass | Changed-file phase only; no structural coverage |

  CI's `agent-lint` job (and a re-invocation once modified files exist on-branch) is the authoritative gate — exit 0 from `/relevant-checks` alone never substitutes for it.
