# driver.sh contract

**Purpose**: Bash driver for `/loop-fix-issue`. Owns loop control, per-iteration `claude -p /fix-issue` invocations, and termination detection.

**Topology**: inversion of loop control. The `/loop-fix-issue` SKILL.md is a thin shell that background-launches this driver and attaches Monitor to a tail of its log file. All real work lives here in bash.

`/fix-issue` is a single-iteration design (one approved issue per invocation, then exits). This driver is the caller responsible for repeated execution until the GitHub issue queue is empty.

## Invocation

```
driver.sh [--debug] [--max-iterations N] [--no-slack] [--no-admin-fallback]
```

- `--debug`: optional flag (currently no-op; reserved for future verbosity control).
- `--max-iterations N`: positive integer safety cap on the loop. Default `50`. The loop terminates earlier on the natural termination signal below; this cap protects against pathological cases (e.g., an issue that is being re-locked endlessly by an external runner).
- `--no-slack`: forwarded to `/fix-issue` each iteration (which forwards it to `/implement`). When omitted, Slack announcements run per `/fix-issue`'s default-on behavior (gated on Slack env vars).
- `--no-admin-fallback`: forwarded to `/fix-issue` each iteration (which forwards it to `/implement`). When set, every iteration's `/implement` run instructs `merge-pr.sh` to emit `MERGE_RESULT=policy_denied` instead of retrying with `--admin` once the admin-eligible gate is reached, and bails to Step 12d on branch-protection denial. When omitted, default `--admin` retry behavior applies per iteration.

## Topology

| Step | Action |
|------|--------|
| 1 | argv parse + claude/gh CLI preflight |
| 2 | `session-setup.sh` → `LOOP_TMPDIR` (with `/tmp/`-prefix + no-`..` security guards) |
| 3 | per-iteration loop up to `--max-iterations`: write `claude -p` STDIN prompt, invoke, capture stdout, check termination sentinel |
| 4 | final summary: total iterations run + termination reason |
| EXIT | `cleanup-tmpdir.sh` on success; `LOOP_TMPDIR` retained on failure |

## Per-iteration `claude -p` invocation contract

The driver writes the STDIN prompt to `$LOOP_TMPDIR/fix-issue-prompt.txt` once before the loop. It is identical across iterations. The prompt is composed by appending optional flags to `/fix-issue` based on the driver's argv:

- Base: `/fix-issue`
- Append `--no-slack` (preceded by a single space) if `--no-slack` was passed.
- Append `--no-admin-fallback` (preceded by a single space) if `--no-admin-fallback` was passed.

Concrete examples (concatenation of optional-flag suffixes; flags appear in argv-parser order):

```
/fix-issue
/fix-issue --no-slack
/fix-issue --no-admin-fallback
/fix-issue --no-slack --no-admin-fallback
```

Each iteration invokes:

```
claude -p --plugin-dir "$CLAUDE_PLUGIN_ROOT" < $LOOP_TMPDIR/fix-issue-prompt.txt > $LOOP_TMPDIR/iter-${ITER}-out.txt 2> $LOOP_TMPDIR/iter-${ITER}-out.txt.stderr
```

Per-iteration timeout: 1800s (30 min), enforced by a polling kill loop (matches `loop-review/scripts/driver.sh`).

## Termination signal

`/fix-issue` Step 0 exit 0 (success) explicitly mandates printing the literal `> **🔶 0: find & lock — found and locked #<N>: <title>**` on stdout. Step 0 exits 1/2/3 (no eligible / error / lock-failed-mid-sequence) print different literals — `no approved issues found`, `error:`, `lock failed`. The driver greps the iteration's captured stdout for the fixed substring `find & lock — found and locked` (fixed-string match via `grep -F`):

- **Sentinel present**: Step 0 succeeded → an issue was processed → continue to next iteration.
- **Sentinel absent**: no work was done → break the loop with reason `"no eligible issues (Step 0 short-circuit)"`.

Why the Step 0 success literal rather than the Step 1 setup breadcrumb: Step 0's `found and locked #<N>` line is *explicitly mandated* by `/fix-issue` SKILL.md (Step 0 success-path Print directive), whereas Step 1's `🔶 1: setup` breadcrumb is only an implicit progress-reporting convention inherited from `skills/shared/progress-reporting.md`. A model that runs Step 1's bash without emitting the breadcrumb would yield a false "no work" signal under the older sentinel and stop the loop prematurely after a successful pass; the Step 0 success literal eliminates that failure mode.

Other termination reasons:

- **`claude -p` non-zero exit**: log a warning, set `LOOP_PRESERVE_TMPDIR=true`, break with reason `"claude -p subprocess error (exit N)"`.
- **`--max-iterations` cap hit**: log a warning, leave `LOOP_PRESERVE_TMPDIR=false` (loop ran cleanly; cap is informational), terminate with reason `"--max-iterations cap reached"`.

Note that "Step 0 short-circuit" subsumes Step 0 exit 1 (clean: no eligible issues), exit 2 (error fetching candidates), and exit 3 (lock race / partial sentinel mutation). All three are treated as "stop the loop" because:
- Exit 1 is the clean termination path.
- Exit 2 indicates a real error (e.g., `gh` API outage) that retrying would not fix.
- Exit 3 indicates a concurrent runner or a partially-mutated comment stream — `/fix-issue`'s Known Limitations require manual recovery; looping would race that recovery.

## Security boundaries

- **`LOOP_TMPDIR`** MUST begin with `/tmp/` or `/private/tmp/` AND MUST NOT contain `..` as a path component. Validated immediately after `session-setup.sh` returns; non-conforming values abort the driver.
- **All subprocess `claude -p` invocations** follow:
  - `--plugin-dir "$CLAUDE_PLUGIN_ROOT"` (plugin resolution)
  - prompt on STDIN, not argv (avoids macOS ARG_MAX = 262144)
  - stderr redirected to `<out>.stderr` sidecar (never posted to GitHub)
- **On `claude -p` non-zero exit**, `LOOP_PRESERVE_TMPDIR` flips `true` so the EXIT trap retains `LOOP_TMPDIR` for inspection. Per-iteration artifacts (`iter-N-out.txt`, `iter-N-out.txt.stderr`) accumulate in `LOOP_TMPDIR`.
- **`$LOOP_TMPDIR`** cleaned via `cleanup-tmpdir.sh` in the EXIT trap on success; retained on any abnormal exit.

## Test-only override

`LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE=<path>` redirects `claude -p` invocations at a stub shim. Reserved for tests; no harness using it is wired into `make lint` yet (harness is a future addition). Same-user arbitrary-executable risk if set in a production environment — when the first harness using this override lands, document it in `SECURITY.md` alongside `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` (the analogous override for `loop-review/scripts/driver.sh`).

## Edit-in-sync

This contract documents `driver.sh`. When editing the script, update both files in the same PR:

- Argv grammar / new flags → update `## Invocation` and `## Topology`.
- Termination logic / sentinel literal → update `## Termination signal`.
- Subprocess invocation contract / new env vars → update `## Per-iteration claude -p invocation contract` + `## Security boundaries` + (if test-only) `## Test-only override`.
