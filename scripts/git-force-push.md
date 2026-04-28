# scripts/git-force-push.sh — contract

## Purpose

Force-push the current branch with `--force-with-lease` protection and single-retry recovery. Wraps the full recovery logic from `/implement`'s Rebase + Re-bump Sub-procedure step 5 (`skills/implement/references/rebase-rebump-subprocedure.md`):

1. Try `git push --force-with-lease` once.
2. On failure: refresh the local tracking ref (`git fetch origin <branch>`), compare local HEAD vs `origin/<branch>`. If equal, the push actually landed (rare race) — return success with `STATUS=noop_same_ref`.
3. If they differ, sleep 5s (via `sleep-seconds.sh`) and retry the push once.
4. If the retry fails, return `STATUS=diverged_retry_failed` so the caller can bail.

## Interface

```
git-force-push.sh
```

No flags, no arguments. Operates on the current branch (detected via `git symbolic-ref --short HEAD`).

## Output contract (KEY=VALUE on stdout)

```
BRANCH=<current branch name>
PUSHED=true|false
STATUS=pushed|noop_same_ref|diverged_retry_failed
```

- `BRANCH` is always emitted first (even on exit 2, it is not emitted — only the stderr message is).
- `PUSHED=true` with `STATUS=pushed`: force-push succeeded on first or retry attempt.
- `PUSHED=true` with `STATUS=noop_same_ref`: push appeared to fail but local HEAD matches `origin/<branch>` after refresh — the push landed in a race window.
- `PUSHED=false` with `STATUS=diverged_retry_failed`: both push attempts failed and local/remote diverge.

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | `PUSHED=true` — branch successfully force-pushed (either `pushed` or `noop_same_ref`). |
| 1 | `PUSHED=false` with `STATUS=diverged_retry_failed` — caller should bail. |
| 2 | Not on a named branch (detached HEAD or not a git repo). Stderr: `git-force-push.sh: not on a named branch`. No stdout keys emitted. |

## Dependencies

- `scripts/sleep-seconds.sh` — used for the 5s delay between retry attempts. Falls back to `sleep 5` if the helper is unavailable.

## Callers

- `scripts/create-pr.sh` — existing-PR fast-path escalation when a plain `git push` fails (non-fast-forward after rebase). Stdout is suppressed (`>/dev/null`) so the `PR_*` contract stays clean; exit code drives success/failure.
- `/implement` Step 8b force-push gate — force-pushes after a rebase when the feature branch already exists on origin. `STATUS` is parsed to decide whether to proceed to Step 9 or bail to Step 18.
- Rebase + Re-bump Sub-procedure step 5 (`skills/implement/references/rebase-rebump-subprocedure.md`) — force-pushes after rebase + re-bump during Steps 10/12 CI+merge iterations. Exit code and `STATUS` drive the caller-family failure semantics (step12 hard-bail vs step10 best-effort).

## Test harness

No dedicated test harness. Real-world coverage comes from `/implement`'s CI+rebase+merge loop (the sub-procedure step 5 path runs on every rebase iteration) and `create-pr.sh`'s existing-PR fast-path (runs on every PR resumption where history was rewritten).

## Edit-in-sync rules

When changing `scripts/git-force-push.sh`:

- Update this file (`scripts/git-force-push.md`) in the same PR if any of the following changes: stdout contract (`BRANCH`/`PUSHED`/`STATUS` keys or their values), exit code semantics, retry logic or timing, dependency on `sleep-seconds.sh`.
- Verify `scripts/create-pr.sh`'s escalation path still suppresses stdout and checks exit code correctly.
- Verify `/implement` Step 8b's `STATUS` parsing in `skills/implement/SKILL.md`.
- Verify the Rebase + Re-bump Sub-procedure step 5's invocation and exit-code handling in `skills/implement/references/rebase-rebump-subprocedure.md`.
