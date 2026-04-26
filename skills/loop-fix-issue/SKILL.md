---
name: loop-fix-issue
description: "Use when systematically closing the open GitHub issue backlog by repeatedly invoking /fix-issue. Bash driver loops a claude -p subprocess each iteration and terminates when no actionable issues remain."
argument-hint: "[--debug] [--max-iterations N] [--no-slack] [--no-admin-fallback]"
allowed-tools: Bash, Monitor
---

# loop-fix-issue

Systematically close the open GitHub issue backlog by repeatedly invoking `/fix-issue` — one issue per iteration — until no eligible issue remains.

`/fix-issue` is a single-iteration design (it processes one approved issue per invocation, then exits). This skill is the caller responsible for repeated execution, with a `--max-iterations` safety cap.

Execution is delegated to the bash driver at `${CLAUDE_PLUGIN_ROOT}/skills/loop-fix-issue/scripts/driver.sh`. The driver owns loop control, per-iteration `claude -p /fix-issue` invocations, and termination detection. Halt class eliminated by construction: each per-iteration `/fix-issue` runs as its own `claude -p` subprocess, so there is no post-child-return model turn that can halt.

## Flags

- `--debug`: forwarded to the driver (currently no-op; reserved for future verbosity control).
- `--max-iterations N`: positive integer safety cap on the loop. Default `50`. The loop terminates earlier on the natural termination signal below; this cap protects against pathological cases (e.g., an issue being re-locked endlessly by an external runner).
- `--no-slack`: forwarded to the driver, which forwards it to each iteration's `/fix-issue` invocation.
- `--no-admin-fallback`: forwarded to the driver, which forwards it to each iteration's `/fix-issue` invocation. Each `/fix-issue` then forwards it to the delegated `/implement` run, where `merge-pr.sh` returns `MERGE_RESULT=policy_denied` instead of retrying with `--admin` once the admin-eligible gate is reached. Applies to every iteration of the sweep — without this flag, individual iterations may silently bypass branch protection via `--admin` retry.

## Termination

The driver greps each iteration's captured stdout for the fixed substring `find & lock — found and locked` — the explicit literal `/fix-issue` Step 0 prints on the success path (`> **🔶 0: find & lock — found and locked #<N>: <title>**`). Step 0 exits 1/2/3 (no eligible / error / lock-failed-mid-sequence) print different literals, so the substring's absence is the deterministic "no work was done" signal — break the loop. See `${CLAUDE_PLUGIN_ROOT}/skills/loop-fix-issue/scripts/driver.md` for the full contract.

## Driver

See `driver.sh` source and the contract sibling at `${CLAUDE_PLUGIN_ROOT}/skills/loop-fix-issue/scripts/driver.md` for the full contract: argv parsing, security boundaries on `LOOP_TMPDIR`, per-iteration `claude -p` invocation contract, and EXIT-trap retention rules.

## Live streaming pattern (Bash background + Monitor)

The driver runs for many minutes (one `claude -p /fix-issue` per iteration; an iteration that delegates to `/implement --merge` can take 30+ minutes). To give the user live visibility into driver progress without reintroducing the halt class, this skill launches `driver.sh` as a **background Bash task** with combined stdout/stderr redirected to a stable log-file path, then **attaches Monitor** to tail that file filtered to the driver's step-marker lines. Monitor is passive observability only.

### Shell-state discipline (MANDATORY)

Every Bash tool call is a fresh shell — environment variables set in one Bash call do **not** survive into the next. The steps below therefore **resolve the log path once** (Step 1) and then embed the **literal resolved absolute path** into every downstream command (Steps 2–5). Do NOT use `$LOG_FILE` as an unresolved variable in Steps 2, 3, 4, or 5 — substitute the literal path returned by Step 1.

### Step 1 — Resolve and validate log path (synchronous Bash)

Run this command synchronously (NOT `run_in_background`) and capture the `RESOLVED_LOG_FILE=` line from its stdout. The `LOOP_FIX_ISSUE_DRIVER_LOG_FILE` env-overridable default is validated to begin with `/tmp/` or `/private/tmp/` (preventing the env var from being used as an arbitrary write/truncate primitive) and to contain no `..` path components (mirroring `driver.sh`'s own `LOOP_TMPDIR` prefix + `..` guard).

```bash
LOG_FILE="${LOOP_FIX_ISSUE_DRIVER_LOG_FILE:-/tmp/loop-fix-issue-driver-$(date +%s)-$$.log}"
case "$LOG_FILE" in
  /tmp/*|/private/tmp/*) ;;
  *) echo "LOOP_FIX_ISSUE_DRIVER_LOG_FILE must start with /tmp/ or /private/tmp/ (got: $LOG_FILE)" >&2; exit 1 ;;
esac
case "$LOG_FILE" in
  */..|*/../*) echo "LOOP_FIX_ISSUE_DRIVER_LOG_FILE must not contain '..' path components (got: $LOG_FILE)" >&2; exit 1 ;;
esac
: > "$LOG_FILE"
echo "RESOLVED_LOG_FILE=$LOG_FILE"
```

Parse the `RESOLVED_LOG_FILE=<absolute-path>` line from stdout. Save the path as `LOG_PATH` — this is the literal value substituted into Steps 2–5 below. Abort the skill if the command exits non-zero.

The log file lives **outside** `LOOP_TMPDIR` on purpose: `driver.sh`'s EXIT trap wipes `LOOP_TMPDIR` on completion (or retains it on failure), which would destroy the log mid-tail. Placing the log directly under `/tmp` keeps it available for post-run inspection.

### Step 2 — Surface the log path to the user (visible line)

Emit a prominent line (outside any suppressed-verbosity section) BEFORE launching Monitor, so the user always knows where the driver log is written. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log: <LOG_PATH>
```

### Step 3 — Launch driver in background

Substitute the literal `LOG_PATH` from Step 1 (do NOT reference `$LOG_FILE` here — the prior shell is gone). Quote the path to tolerate any path containing spaces:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-fix-issue/scripts/driver.sh" $ARGUMENTS > "<LOG_PATH>" 2>&1
```

Launch this Bash command with `run_in_background: true`. When the background task completes, Claude Code emits an automatic task-completion notification — no additional end-of-run wiring is needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke the Monitor tool with `persistent: true` and the following command (substitute the literal `LOG_PATH` from Step 1; filter regex pinned byte-verbatim; MUST remain in parity with `driver.sh`'s three breadcrumb prefixes):

```
tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

where `"$LOG_FILE"` is the literal Step-1 path, double-quoted to tolerate whitespace in the path. The `$LOG_FILE` notation is preserved byte-verbatim as the canonical filter literal; at Monitor-invocation time, substitute the resolved absolute path into that literal.

- `tail -F` (capital F) tolerates the log file not yet existing at Monitor-attach time and handles rotation.
- `grep --line-buffered` keeps the pipe unbuffered so Monitor sees each line as the driver emits it.
- `persistent: true` is load-bearing for multi-iteration sweeps.

### Step 5 — Completion

When the background Bash task completes, re-emit the log path so the user can easily retrieve the driver log without scrolling. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log (retained): <LOG_PATH>
```

### What the Monitor stream shows vs. what the log file holds vs. where child output lives

There are three observability surfaces. Each carries a different kind of content with a different retention rule.

- **Monitor stream** (live in conversation): shows ONLY lines from the parent driver's stdout/stderr that match the breadcrumb regex `^(✅|> \*\*🔶|\*\*⚠)` — the driver's three breadcrumb prefix families. The child `/fix-issue` subprocess emits its own breadcrumb-shaped lines, but those go to per-iteration sidecar files (see below) — not to the parent driver's stdout — so they do **not** appear on the Monitor stream.
- **Log file at `LOG_PATH`** (driver stdout+stderr capture): retained on /tmp for post-run inspection. Holds the driver's own emitted output: every breadcrumb (`🔶` / `✅` / `⚠`), the unconditional cleanup `LOOP_TMPDIR=…` line, the final summary line, and any stderr `printf` from setup paths. It does **NOT** contain raw `/fix-issue` subprocess stdout/stderr; those streams are redirected by `invoke_claude_p_skill` into per-iteration sidecar files described next.
- **Per-iteration child stdout/stderr**: each iteration's `claude -p /fix-issue` writes its raw stdout to `$LOOP_TMPDIR/iter-N-out.txt` and its raw stderr (including any `claude-iter-N: TIMED OUT after Xs` watcher diagnostic) to `$LOOP_TMPDIR/iter-N-out.txt.stderr`. Retained **only** when `LOOP_PRESERVE_TMPDIR=true`, which the driver sets on every documented abnormal-exit path: claude subprocess error, Step 0 error, Step 0 lock failure, and sentinel mismatch. On clean success and on `--max-iterations` cap-hit (also a clean exit), `LOOP_TMPDIR` is wiped and the sidecars go with it. On retained paths, the cleanup warning line names the artifact glob patterns explicitly so they can be located without consulting these docs.

### If Monitor is unavailable (older runtime)

If the Claude runtime does not expose the Monitor tool, the background Bash launch still runs and the task-completion notification still fires. Only the live stream is lost. To inspect driver progress in that case, run `tail -f <LOG_PATH>` in a separate shell using the path printed in Step 2.
