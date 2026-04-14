---
name: relevant-checks
description: Run repo-specific validation checks based on modified files. Use when you need to validate code quality after implementation, after code review fixes, or when fixing CI failures. This skill replaces the old /lint, /test, /format pattern.
allowed-tools: Bash
---

# Relevant Checks

Run validation checks scoped to files modified on the current branch. This is a repo-specific skill — each repository defines its own `/relevant-checks` with checks appropriate for that repo.

## How it works

Changed files are collected from the branch diff, staged changes, unstaged changes, and untracked files. The union is passed to `pre-commit run --files`, which routes each file to the appropriate linter hooks based on file type. Deleted files are filtered out automatically.

The following linters are configured in `.pre-commit-config.yaml`:

- **Shell scripts (`.sh`)**: shellcheck
- **Markdown files (`.md`)**: markdownlint (using `.markdownlint.json` config)
- **JSON files (`.json`)**: jq validation
- **GitHub Actions workflows (`.yml`, `.yaml`)**: actionlint

After pre-commit linting succeeds, `run-checks.sh` additionally invokes `claude-lint` (if available on PATH) to catch structural regressions on the full repository. This is the same linter that CI's `claude-lint` job runs, so developers can catch structural breakage locally before pushing. If pre-commit fails, claude-lint is skipped — only run when basic linting passes.

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
