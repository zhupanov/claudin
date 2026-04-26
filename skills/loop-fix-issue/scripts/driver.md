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
| EXIT | `cleanup-tmpdir.sh` runs when `LOOP_PRESERVE_TMPDIR=false` (clean success, including `--max-iterations` cap-hit); `LOOP_TMPDIR` retained when `LOOP_PRESERVE_TMPDIR=true` (the four documented abnormal-exit paths — see `## Termination signal` and `## Security boundaries`) |

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
- **Sentinel absent**: no work was done → break the loop. The driver dispatches on a second-tier `grep -F -q` against the same iteration stdout to choose a termination reason and decide whether to preserve `LOOP_TMPDIR` for inspection. Each sub-sentinel is anchored with the literal `0: find & lock —` step-prefix (the `0:` step number followed by the breadcrumb head) so user-data-bearing `$ERROR` text in one branch cannot trigger another branch's keyword. The four sub-cases (mutually exclusive for the canonical `/fix-issue` Step 0 templates documented at SKILL.md lines 88–91, checked in this order):

  - `0: find & lock — no approved issues found` (Step 0 exit 1 — clean exhaustion) → `breadcrumb_done`, reason `"no eligible issues (clean exhaustion)"`, `LOOP_PRESERVE_TMPDIR=false` (cleanup runs).
  - `0: find & lock — error:` (Step 0 exit 2 — error reading candidates, e.g. `gh` API outage) → `breadcrumb_warn`, reason `"Step 0 error (likely transient)"`, `LOOP_PRESERVE_TMPDIR=true` (artifacts retained).
  - `0: find & lock — lock failed` (Step 0 exit 3 — eligibility passed but lock acquisition failed; concurrent runner or partial-state per `/fix-issue` Known Limitations) → `breadcrumb_warn`, reason `"Step 0 lock failure (concurrent runner or partial-state)"`, `LOOP_PRESERVE_TMPDIR=true`.
  - None of the above → defensive fallback. `breadcrumb_warn`, reason `"Step 0 unknown short-circuit (sentinel mismatch)"`, `LOOP_PRESERVE_TMPDIR=true`. Guards against silent regressions if `/fix-issue` Step 0 wording drifts; without it, any future Step 0 stdout change would silently degrade to a false "Loop complete" with no per-iteration artifacts.

  All four sub-cases stop the loop. Exit 2 / exit 3 both indicate conditions that retrying would not resolve (`/fix-issue`'s Known Limitations require manual recovery for lock races); the difference vs. exit 1 is that the termination message and `LOOP_PRESERVE_TMPDIR` signal a real failure mode rather than reporting "Loop complete".

Why the Step 0 success literal rather than the Step 1 setup breadcrumb: Step 0's `found and locked #<N>` line is *explicitly mandated* by `/fix-issue` SKILL.md (Step 0 success-path Print directive), whereas Step 1's `🔶 1: setup` breadcrumb is only an implicit progress-reporting convention inherited from `skills/shared/progress-reporting.md`. A model that runs Step 1's bash without emitting the breadcrumb would yield a false "no work" signal under the older sentinel and stop the loop prematurely after a successful pass; the Step 0 success literal eliminates that failure mode.

Other termination reasons:

- **`claude -p` non-zero exit**: log a warning, set `LOOP_PRESERVE_TMPDIR=true`, break with reason `"claude -p subprocess error (exit N)"`.
- **`--max-iterations` cap hit**: log a warning, leave `LOOP_PRESERVE_TMPDIR=false` (loop ran cleanly; cap is informational), terminate with reason `"--max-iterations cap reached"`.

## Security boundaries

- **`LOOP_TMPDIR`** MUST begin with `/tmp/` or `/private/tmp/` AND MUST NOT contain `..` as a path component. Validated immediately after `session-setup.sh` returns; non-conforming values abort the driver.
- **All subprocess `claude -p` invocations** follow:
  - `--plugin-dir "$CLAUDE_PLUGIN_ROOT"` (plugin resolution)
  - prompt on STDIN, not argv (avoids macOS ARG_MAX = 262144)
  - stderr redirected to `<out>.stderr` sidecar (never posted to GitHub)
- **On `claude -p` non-zero exit**, `LOOP_PRESERVE_TMPDIR` flips `true` so the EXIT trap retains `LOOP_TMPDIR` for inspection. Per-iteration artifacts (`iter-N-out.txt`, `iter-N-out.txt.stderr`) accumulate in `LOOP_TMPDIR`.
- **`$LOOP_TMPDIR` retention rule**: cleaned via `cleanup-tmpdir.sh` in the EXIT trap when `LOOP_PRESERVE_TMPDIR=false`; retained when `LOOP_PRESERVE_TMPDIR=true`. The driver sets `LOOP_PRESERVE_TMPDIR=true` on exactly four documented abnormal-exit paths: claude subprocess error (`claude -p` non-zero exit), Step 0 error (`grep -F -q '0: find & lock — error:'`), Step 0 lock failure (`grep -F -q '0: find & lock — lock failed'`), and the defensive sentinel-mismatch fallback (none of the canonical Step 0 sub-sentinels match). The clean-success path and the `--max-iterations` cap-hit path both leave `LOOP_PRESERVE_TMPDIR=false`, so the tmpdir is wiped by `cleanup-tmpdir.sh` and the per-iteration sidecars go with it. On retained paths, the cleanup warning explicitly names the `iter-*-out.txt` and `iter-*-out.txt.stderr` artifact glob patterns (both rooted under `${LOOP_TMPDIR}`) so they can be located without consulting these docs.

## Observability / Retention matrix

There are three observability surfaces (Monitor stream, `LOG_PATH` driver log, per-iteration sidecars) with distinct contents and retention rules. This matrix is byte-faithful to `driver.sh` and is the canonical contract; SKILL.md's "What the Monitor stream shows vs. what the log file holds vs. where child output lives" subsection mirrors it for operator-facing presentation. Keep them in sync.

| Surface | Contents | Retention |
|---------|----------|-----------|
| Monitor stream (live) | Driver-emitted lines from the parent process's stdout/stderr that match the breadcrumb regex `^(✅\|> \*\*🔶\|\*\*⚠)`. Driver-originated non-breadcrumb lines (e.g., the `LOOP_TMPDIR=` line in `cleanup_on_exit`) are in `LOG_PATH` but NOT on Monitor. Child `/fix-issue` breadcrumb-shaped lines live in the per-iteration sidecars (see below) and never reach driver stdout, so they never reach Monitor. | Live only; the Monitor tool tails `LOG_PATH` and applies the regex filter at display time — the filter does not persist anywhere. |
| `LOG_PATH` (driver stdout+stderr capture from the SKILL.md Step-3 outer `> "<LOG_PATH>" 2>&1` redirect) | Driver-emitted output: every breadcrumb (`🔶` / `✅` / `⚠`); the unconditional `LOOP_TMPDIR=…` line printed at the top of `cleanup_on_exit`; the final summary line; any `printf` to stderr from the argv parser, preflight checks, or the `session-setup.sh` capture path. Does **NOT** contain raw `/fix-issue` subprocess stdout/stderr — those are redirected by `invoke_claude_p_skill` into the per-iteration sidecars. | `/tmp/loop-fix-issue-driver-…log` — retained on `/tmp` post-run. The path lives outside `LOOP_TMPDIR` on purpose so the EXIT-trap cleanup does not wipe it mid-tail. |
| `$LOOP_TMPDIR/iter-N-out.txt` | Per-iteration `claude -p /fix-issue` stdout, raw and unredacted, exactly one file per iteration. Termination-detection grep reads this file (not driver stdout). | Wiped by `cleanup-tmpdir.sh` when `LOOP_PRESERVE_TMPDIR=false` (clean success and `--max-iterations` cap-hit). Retained when `LOOP_PRESERVE_TMPDIR=true` (the four documented abnormal-exit paths). On retained paths, the cleanup warning names the artifact glob patterns. |
| `$LOOP_TMPDIR/iter-N-out.txt.stderr` | Per-iteration `claude -p /fix-issue` stderr, raw and unredacted. Includes any `claude-iter-N: TIMED OUT after Xs` line — appended by the watcher subshell via `>> "$stderr_file"` when the per-iteration timeout (1800s) expires and the watcher kills the subprocess. The timeout-watcher line lives **only** here; it does NOT bubble up to driver stderr. | Same retention rule as the stdout sidecar. |

## Test-only override

`LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE=<path>` redirects `claude -p` invocations at a stub shim. Reserved for tests; the Tier-1 structural harness `scripts/test-loop-fix-issue-driver.sh` (wired into `make lint`) greps for the override token but does not exercise it. Tier-2 stub-shim integration coverage that actually invokes the override remains future work; when the first such harness lands, document the override in `SECURITY.md` alongside `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` (the analogous override for `loop-review/scripts/driver.sh`). Same-user arbitrary-executable risk if set in a production environment.

## Edit-in-sync

This contract documents `driver.sh`. When editing the script, update both files in the same PR:

- Argv grammar / new flags → update `## Invocation` and `## Topology`.
- Termination logic / sentinel literal → update `## Termination signal`.
- Subprocess invocation contract / new env vars → update `## Per-iteration claude -p invocation contract` + `## Security boundaries` + (if test-only) `## Test-only override`.
- Observability surfaces / retention rules / what each artifact contains → update `## Observability / Retention matrix` here AND `skills/loop-fix-issue/SKILL.md`'s "What the Monitor stream shows vs. what the log file holds vs. where child output lives" subsection. The matrix is the canonical contract; the SKILL.md subsection is the operator-facing mirror — they must remain semantically consistent.
