# test-check-review-changes.sh contract

## Purpose

Offline regression harness for `skills/implement/scripts/check-review-changes.sh`. Pins the post-fix behavior for issue #651 (the false-positive scenario where ANY pre-existing untracked file flipped `FILES_CHANGED=true`) plus the empty-vs-missing baseline-state distinction introduced by the fix.

## Test cases

Each case sets up an isolated `git init` sandbox via `mktemp -d`, optionally writes a baseline file, optionally mutates the working tree, runs `check-review-changes.sh` (with or without `--baseline`), and asserts both stdout keys.

| Case | Setup | Expected output | What it pins |
|------|-------|-----------------|--------------|
| (a) | clean tree, no `--baseline` | `FILES_CHANGED=false UNTRACKED_BASELINE=missing` | clean baseline behavior |
| (b) | pre-existing untracked file + baseline that includes it | `FILES_CHANGED=false UNTRACKED_BASELINE=present` | **THE regression case from #651** |
| (c) | pre-existing untracked + baseline + new untracked added after baseline | `FILES_CHANGED=true UNTRACKED_BASELINE=present` | review-created new untracked is detected |
| (d) | staged modification (with empty baseline) | `FILES_CHANGED=true UNTRACKED_BASELINE=present` | staged-only path is unchanged |
| (e) | unstaged modification (with empty baseline) | `FILES_CHANGED=true UNTRACKED_BASELINE=present` | unstaged-only path is unchanged |
| (f) | pre-existing untracked, NO `--baseline` flag | `FILES_CHANGED=false UNTRACKED_BASELINE=missing` | **deliberate behavior change** — see callout below |
| (g) | zero-byte readable baseline + new untracked file | `FILES_CHANGED=true UNTRACKED_BASELINE=present` | empty-vs-missing distinction (readable zero-byte = present, delta = current) |

## Case (f) is a deliberate behavior change — do NOT "fix" it

Before issue #651's fix, `check-review-changes.sh` reported `FILES_CHANGED=true` whenever ANY untracked file was present in the working tree (including stray operator files unrelated to the review step). Case (f) asserts the post-fix behavior: when invoked WITHOUT a `--baseline` flag, the script reports `FILES_CHANGED=false UNTRACKED_BASELINE=missing` even when the working tree has untracked files.

This is intentional graceful degradation: if `/implement` Step 5's snapshot fails (transient git error, atomic-rename failure, etc.) the baseline file is removed and the next Step 6 invocation correctly reports the run as degraded via `UNTRACKED_BASELINE=missing` rather than reintroducing the false-positive bug. See `check-review-changes.md` for the full degradation contract.

A future contributor reading this case might reason "untracked files exist, so `FILES_CHANGED=true`" and be tempted to "fix" the assertion. **DO NOT.** That would re-introduce issue #651. The behavior is documented here precisely to prevent that.

## Case (g) validates the empty-vs-missing distinction

Plan-review accepted FINDING_1: a readable zero-byte baseline file means "no untracked at snapshot time" and is `present` (not `missing`). Case (g) creates a zero-byte readable baseline, then adds an untracked file, and asserts `FILES_CHANGED=true UNTRACKED_BASELINE=present`. If a future change collapses zero-byte and missing into the same `=missing` bucket, this case fails.

## Running the harness

```bash
bash skills/implement/scripts/test-check-review-changes.sh
```

Exits 0 when all cases pass, 1 when any case fails. Prints `PASS:` / `FAIL:` per case, then a `RESULTS:` summary line.

## Wiring

Wired into `Makefile` in three places (per the project's per-harness convention):
- `.PHONY` declaration
- `test-harnesses` target dependency list
- Dedicated recipe block

Excluded from `agent-lint.toml` as a Makefile-only artifact (the harness is not structurally referenced from `SKILL.md`; only the runtime `check-review-changes.sh` is).

## Edit-in-sync

Behavior changes in `check-review-changes.sh` MUST update this harness in the same PR. Specifically:
- Adding a new stdout key → update `run_case` to assert it
- Renaming a key → update assertions
- Adding a new detection source → add a pinning case
- Changing `--baseline` flag semantics → update the relevant cases and the case-(f) callout above
