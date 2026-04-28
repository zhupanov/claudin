# `scripts/ci-wait.sh` — contract

**Purpose**: blocking polling helper for the CI+merge loop. Wraps `scripts/ci-status.sh` (gh API status probe) + `scripts/ci-decide.sh` (action classification) into a single long-running synchronous call that returns when the resolved action transitions away from `wait`.

## Synchronous-only invocation contract

`ci-wait.sh` MUST be invoked synchronously (no `run_in_background: true` in Bash tool calls). The recommended `timeout: 1860000` (31 minutes) on the Bash tool call covers the script's `1800`-second wall-clock default plus generous overhead.

Backgrounding `ci-wait.sh` disconnects the orchestrator from the script's return code AND creates a leaked-polling-loop risk: when the harness later force-kills the wrapper shell mid-poll, the EXIT trap fires only on trap-deliverable signals (SIGTERM, etc.), and any operator-improvised polling loop watching the harness's `<task-id>.output.done` (rather than this script's optional `--output-file <path>.done`) will spin forever because the harness only writes its own sentinel on clean wrapper-shell exit. See issue #842 for the full failure-mode trace.

## Default I/O contract

When `--output-file` is **absent**, the EXIT trap emits 7 KV lines on stdout in this order:

```
ACTION=merge|rebase|already_merged|rebase_then_evaluate|evaluate_failure|bail
CI_STATUS=pass|fail|pending|merged
BEHIND_COUNT=<N>
FAILED_RUN_ID=<id-or-empty>
BAIL_REASON=<text-or-empty>
ITERATION=<N>
ELAPSED=<seconds>
```

Default callers (`/implement` Step 10, Step 12a, and the four step-7 re-invocation branches in `skills/implement/references/rebase-rebump-subprocedure.md`) parse stdout. No `.done` sentinel is written in default mode.

## Optional `--output-file <path>` mode

When `--output-file <path>` is set, the trap behavior changes in three coordinated ways:

1. **Stale clear**: on script start (after argument validation, before the polling loop), `<path>`, `<path>.done`, and `<path>.tmp` are removed. Consumers polling for `.done` never see a stale sentinel from a prior crashed run.
2. **Atomic publish of the KV payload**: `emit_output` writes the same 7 KV lines to `<path>.tmp`, then performs `mv -f "<path>.tmp" "<path>"` as a single same-filesystem atomic rename. The two operations are AND-chained; if either fails (disk full, permission denied), the `<path>` does NOT exist.
3. **Numeric `.done` sentinel**: the EXIT trap captures the script's exit status FIRST (before `emit_output` mutates `$?`), runs `emit_output`, then writes `printf '%s\n' "$EXIT_STATUS" > "${OUTPUT_FILE}.done" 2>/dev/null || true`. This mirrors `scripts/run-external-reviewer.sh:70` byte-for-byte; existing repo readers (`scripts/collect-reviewer-results.sh`, `scripts/wait-for-reviewers.sh`) parse `.done` as a numeric exit code.

**Consumer read order** (same discipline as `collect-reviewer-results.sh`): wait for `<path>.done` to exist; THEN parse `<path>`. Never read `<path>` directly without first observing `<path>.done` — a partial KV file (publish mid-write) cannot be observed by conforming consumers because `.done` is written only AFTER the atomic rename publishes `<path>`.

**Failure semantics (fail-closed)**: if `<path>.tmp` write fails OR `mv -f` fails, no `<path>.done` is written either. Consumers waiting on `.done` never see it and eventually time out — strictly fail-closed. This is intentional: a false-ready sentinel pointing at a missing or stale payload would cascade into wrong CI / merge decisions.

## Trusted-path discipline

`--output-file` is a filesystem write primitive. Callers MUST pass a trusted path under their session tmpdir (`$IMPLEMENT_TMPDIR` for `/implement` callers, or equivalent for other consumers). Avoid attacker-controlled paths and absolute paths outside the session tmpdir. Same discipline as `scripts/run-external-reviewer.sh`'s `--output` flag.

The script does NOT validate that `<path>` is well-formed beyond what `mv` itself requires. A path containing `..` traversal, symlink chains pointing outside the session tmpdir, or shell-metacharacter content will be passed through to filesystem operations as written — the caller is responsible for providing a trusted path.

## SIGTERM vs SIGKILL

The EXIT trap fires on every signal that bash can trap (most importantly **SIGTERM**, which the harness's session-cleanup uses first). **SIGKILL is uncatchable** in userspace; no shell-side mechanism can write the sentinel under SIGKILL. The synchronous-only invocation contract above is the operational defense for SIGKILL paths — synchronous callers never reach a state where the harness might SIGKILL their `ci-wait.sh` shell.

## Test harness

`scripts/test-ci-wait-exit-trap.sh` (sibling: `scripts/test-ci-wait-exit-trap.md`) regression-tests both modes:

- **Sub-test A**: `--output-file` SIGTERM-mid-poll convergence — asserts `<path>` exists with parseable `ACTION=` and `<path>.done` exists with parseable numeric content.
- **Sub-test B**: default-mode backward-compat — asserts all 7 KV keys appear on stdout in order with no implicit file-mode side effects.

Wired into `Makefile`'s `lint` and `test-harnesses` targets via the `test-ci-wait-exit-trap` rule.

## Edit-in-sync rules

A "**site**" is either a fenced Bash invocation block OR a prose re-invocation directive in another markdown file. When the synchronous-only contract changes, all sites below must be updated:

**Executable Bash invocation sites (2)**:
- `skills/implement/SKILL.md` Step 10 — initial CI wait after PR creation.
- `skills/implement/SKILL.md` Step 12a — CI+merge poll loop.

**Prose re-invocation directive sites (4)**:
- `skills/implement/references/rebase-rebump-subprocedure.md` step 7 caller-kinds — `step12_rebase`, `step12_phase4`, `step12_rebase_then_evaluate`, `step10_rebase`, `step10_rebase_then_evaluate`. (Five caller-kind branches; four contain explicit re-invocation directives, the `*_then_evaluate` branches fall through without re-invocation but still inherit the synchronous-invocation rule from the parent step.) The synchronous-only paragraph following the caller-kind list serves the entire block.

**Test asserter**: `scripts/test-implement-structure.sh` assertion 17 (negative-pin against `ci-wait.sh` adjacent to `run_in_background: true` in both `SKILL.md` and `rebase-rebump-subprocedure.md`; positive-pin asserting the literal `ci-wait.sh MUST be invoked synchronously` is present in each file).

**Test asserter sibling**: `scripts/test-implement-structure.md` (assertion enumeration must list assertion 17 in lockstep with the in-script header comment).

## Cross-references

- Issue #842 — surfacing failure-mode trace.
- PR #821 — the `/implement` run that surfaced #842 (during post-merge cleanup of #775).
- `scripts/run-external-reviewer.sh:70` — positive precedent for the EXIT-trap-writes-`.done` numeric-content idiom adopted here.
- `scripts/collect-reviewer-results.sh`, `scripts/wait-for-reviewers.sh` — the existing sentinel readers that consume `<path>.done`'s numeric content.
