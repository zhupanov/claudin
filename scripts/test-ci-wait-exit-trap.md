# `scripts/test-ci-wait-exit-trap.sh` — contract

**Purpose**: regression test for `scripts/ci-wait.sh`'s EXIT-trap-writes-`.done` behavior under signal-kill, and for the backward-compat default-mode (stdout) contract. Closes a regression vector identified in issue #842.

## Two sub-tests

### Sub-test A — `--output-file` SIGTERM-mid-poll convergence

Asserts the file-mode contract holds when ci-wait.sh is signal-killed mid-polling-loop:

1. `<path>` exists (KV file published via the atomic `<path>.tmp` + `mv -f` chain).
2. `<path>` contains a parseable `ACTION=` line.
3. `<path>.done` exists (sentinel written by the EXIT trap).
4. `<path>.done` content is a parseable non-negative integer (numeric exit code, mirroring `scripts/run-external-reviewer.sh:70`).
5. `<path>.tmp` does NOT linger after the atomic publish.

### Sub-test B — default-mode (stdout) backward-compat

Asserts no behavioral drift for existing callers when `--output-file` is absent:

6. Script exits 0 on `ACTION=merge` resolution.
7. All 7 KV keys (`ACTION=`, `CI_STATUS=`, `BEHIND_COUNT=`, `FAILED_RUN_ID=`, `BAIL_REASON=`, `ITERATION=`, `ELAPSED=`) appear on stdout in order.
8. No file-mode side effects: no `<dir>/out.txt`, `<dir>/out.txt.done`, or `<dir>/out.txt.tmp` files created adjacent to the test fixture.

## Fixture layout

For each sub-test, a per-test tmpdir under `$TMPDIR_BASE` contains:
- A copy (NOT a symlink) of `scripts/ci-wait.sh` — the copy is required because `ci-wait.sh` resolves `SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"` to its own directory and looks for `ci-status.sh` / `ci-decide.sh` siblings there. A copy lets the fixture stub those siblings without touching the real `$REPO/scripts/ci-status.sh` or `ci-decide.sh`.
- A stub `ci-status.sh` whose behavior is sub-test-specific (Sub-test A: `touch loop-entered` + emit `CI_STATUS=pending`; Sub-test B: emit `CI_STATUS=pass`).
- A stub `ci-decide.sh` (Sub-test A: `ACTION=wait` so the loop never exits naturally; Sub-test B: `ACTION=merge` so the script exits cleanly).

## Signal-choice rationale

The harness sends **SIGTERM**, NOT SIGKILL. Bash CANNOT trap SIGKILL; no shell-side mechanism can write the sentinel under SIGKILL. The doc-layer fix in `skills/implement/SKILL.md` and `skills/implement/references/rebase-rebump-subprocedure.md` (synchronous-only invocation rule) is the operational defense for SIGKILL paths. This harness exercises the trap-deliverable signal class only.

## Deterministic readiness signal

Sub-test A uses a **stub-touched marker file** (`$tmpdir/loop-entered`, set by the stub `ci-status.sh` on its first call) as the readiness signal, polled with `until [ -f ... ]; do sleep 0.05; done` capped at 10 seconds. This avoids the `⏳ CI: waiting` stderr-marker race the design dialectic flagged: that marker is printed BEFORE the loop's first sleep, so observing it does NOT confirm the trap has had time to install or that the loop has reached `sleep 10`. The stub-touched marker fires exactly when the polling loop's first iteration runs — deterministic.

A small additional `sleep 0.5` buffer follows the readiness wait to ensure the EXIT trap chain is fully installed before SIGTERM is delivered.

## Makefile wiring

```makefile
test-ci-wait-exit-trap:
    bash scripts/test-ci-wait-exit-trap.sh
```

(Note: the snippet above uses spaces for markdown rendering; the actual `Makefile` rule MUST start with a tab character per Make syntax.)

Listed in `Makefile`'s `.PHONY` declaration and in the `test-harnesses` target's dependency list. `make lint` runs the harness via the `lint: test-harnesses lint-only` chain.

## Edit-in-sync rules

Update this harness in lockstep with:

- `scripts/ci-wait.sh` — any change to the EXIT trap, the `--output-file` parse, the publish chain (`<path>.tmp` + `mv -f`), or the `.done` sentinel content/format invalidates the sub-test assertions.
- `scripts/ci-wait.md` — contract rewrites (especially the I/O contract section, the SIGTERM-vs-SIGKILL section, or the trusted-path discipline) trigger test re-validation.

## Cross-references

- Issue #842 — surfacing failure-mode trace (the leaked-polling-loop scenario this harness regresses against).
- `scripts/run-external-reviewer.sh:70` — positive precedent for the EXIT-trap-writes-`.done` idiom; the test mirrors its numeric-content sentinel format.
- `scripts/test-check-bump-version.sh`, `scripts/test-collect-reviewer-bash32.sh` — peer test harnesses with similar Makefile-wired regression-test patterns.
