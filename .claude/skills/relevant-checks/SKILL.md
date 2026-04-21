---
name: relevant-checks
description: Run repo-specific validation checks based on modified files. Use when you need to validate code quality after implementation, after code review fixes, or when fixing CI failures.
allowed-tools: Bash
---

# Relevant Checks

Run validation checks scoped to files modified on the current branch. This is a repo-specific skill — each repository defines its own `/relevant-checks` with checks appropriate for that repo.

## Mindset

Before diagnosing a failure, classify it by phase: **changed-file phase** (`pre-commit run --files`) or **full-repo phase** (`agent-lint --pedantic`). The two phases of `run-checks.sh` are not strictly "mechanical vs structural" — `.pre-commit-config.yaml` already routes some structural hooks (e.g., agnix on SKILL.md/CLAUDE.md) through the changed-file phase. The phase-based split is: what the script applied to the changed files vs. what it applied to the whole repo. On a **deletions-only branch**, the changed-file phase is skipped entirely (empty `files[]`) while the full-repo phase still runs.

## How it works

Changed files are collected from the branch diff, staged changes, unstaged changes, and untracked files. The union is passed to `pre-commit run --files`, which routes each file to the appropriate linter hooks based on file type. Deleted files are filtered out automatically. `.pre-commit-config.yaml` is the authoritative hook catalogue — it is consulted at invocation time by `pre-commit`, so changes to that file take effect on the next `/relevant-checks` run.

The following linters are configured in `.pre-commit-config.yaml`:

- **Shell scripts (`.sh`)**: shellcheck
- **Markdown files (`.md`)**: markdownlint (using `.markdownlint.json` config)
- **JSON files (`.json`)**: jq validation
- **GitHub Actions workflows (`.yml`, `.yaml`)**: actionlint
- **AI agent configs (`SKILL.md`, `CLAUDE.md`, agent configs)**: agnix (using `.agnix.toml` config)

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
| Line `ERROR: pre-commit not found` printed, immediate exit 1 | Missing `pre-commit` binary | `pip install pre-commit` OR `make setup`; re-invoke. |
| Line `ERROR: not inside a git repository` printed, immediate exit 1 | Not a git worktree | `cd` into the repo (or re-clone); re-invoke. |
| `=== Running pre-commit ...` banner printed, script exits non-zero **before** any `=== Running agent-lint ===` banner | Changed-file phase failure (file-scoped lint) | Read hook diffs/output, fix the file(s), re-invoke. |
| `=== Running agent-lint ===` banner printed, script exits non-zero **after** it | Full-repo phase failure (structural) | Follow the specific `agent-lint` finding — typical fixes update frontmatter, references, harnesses, or docs in the same PR; re-invoke. |

Note: `WARNING: agent-lint not found on PATH — skipping` is non-fatal — the script still exits 0 on changed-file-phase success even without `agent-lint` installed. Install it before merging if CI's `agent-lint` job runs.

## Anti-patterns (NEVER)

- **NEVER substitute `git commit --no-verify` for `/relevant-checks`.** **Why:** `--no-verify` only skips the local git `pre-commit` hook (an optional, separate install); it does NOT run or replace this skill's checks. Always run `/relevant-checks` before the merge.
- **NEVER assume a deletions-only branch has nothing to check.** **Why:** `run-checks.sh` skips the changed-file phase (empty `files[]`) but still runs the full-repo `agent-lint` phase — see the `files[] empty but MODIFIED_FILES non-empty` branch. Deletions are the most common source of structural regressions (dangling references, orphaned harnesses).
- **NEVER read `/relevant-checks` exit 0 as "every gate ran green".** **Why:** exit 0 means the changed-file phase passed (if it ran) AND the full-repo phase either passed or was skipped. When `agent-lint` is absent from `PATH`, the script prints `WARNING: agent-lint not found on PATH — skipping` and still exits 0. Treat a skipped `agent-lint` as reduced coverage; CI's `agent-lint` job is the authoritative gate.
