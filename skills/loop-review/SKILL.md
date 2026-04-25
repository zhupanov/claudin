---
name: loop-review
description: "Use when a comprehensive quality sweep or systematic code review is needed. Bash driver partitions the repo into verbal slices via one claude -p call, then loops invoking /review --slice-file --create-issues per slice."
argument-hint: "[--debug] [partition criteria]"
allowed-tools: Bash, Monitor
---

# loop-review

Systematically review the entire codebase by partitioning into verbal slices via a single LLM partition call, reviewing each slice with `/review --slice-file --create-issues --label loop-review`, and filing every voted-in finding (in-scope-accepted AND OOS-accepted) as a deduplicated GitHub issue. Security-tagged findings are held locally per SECURITY.md and never auto-filed.

Execution is delegated to the bash driver at `${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/driver.sh`. The driver owns loop control, repo partitioning, per-slice `claude -p /review` invocations, KV-footer counter aggregation, and security-finding aggregation. Halt class eliminated by construction: each per-slice `/review` runs as its own `claude -p` subprocess, so there is no post-child-return model turn that can halt.

## Flags

- `--debug`: When present, forwarded to the driver to enable verbose output.

Any non-flag tokens after argument parsing are concatenated as freeform partition criteria appended to the partition prompt (e.g., `/loop-review focus on the design skill and its references`).

## Driver

See `driver.sh` source and the contract sibling at `${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/driver.md` for the full contract: argv parsing, security boundaries on `LOOP_TMPDIR`, partition prompt schema, per-slice `### slice-result` KV footer parse, security-findings handoff via `--security-output`, and EXIT-trap retention rules.

## Live streaming pattern (Bash background + Monitor)

The driver runs for many minutes (one `claude -p /review` per slice; typical sweep covers 5–20 slices). To give the user live visibility into driver progress without reintroducing the halt class, this skill launches `driver.sh` as a **background Bash task** with combined stdout/stderr redirected to a stable log-file path, then **attaches Monitor** to tail that file filtered to the driver's step-marker lines. Monitor is passive observability only.

### Shell-state discipline (MANDATORY)

Every Bash tool call is a fresh shell — environment variables set in one Bash call do **not** survive into the next. The steps below therefore **resolve the log path once** (Step 1) and then embed the **literal resolved absolute path** into every downstream command (Steps 2–5). Do NOT use `$LOG_FILE` as an unresolved variable in Steps 2, 3, 4, or 5 — substitute the literal path returned by Step 1.

### Step 1 — Resolve and validate log path (synchronous Bash)

Run this command synchronously (NOT `run_in_background`) and capture the `RESOLVED_LOG_FILE=` line from its stdout. The `LOOP_DRIVER_LOG_FILE` env-overridable default is validated to begin with `/tmp/` or `/private/tmp/` (preventing the env var from being used as an arbitrary write/truncate primitive) and to contain no `..` path components (mirroring `driver.sh`'s own `LOOP_TMPDIR` prefix + `..` guard).

```bash
LOG_FILE="${LOOP_DRIVER_LOG_FILE:-/tmp/loop-review-driver-$(date +%s)-$$.log}"
case "$LOG_FILE" in
  /tmp/*|/private/tmp/*) ;;
  *) echo "LOOP_DRIVER_LOG_FILE must start with /tmp/ or /private/tmp/ (got: $LOG_FILE)" >&2; exit 1 ;;
esac
case "$LOG_FILE" in
  */..|*/../*) echo "LOOP_DRIVER_LOG_FILE must not contain '..' path components (got: $LOG_FILE)" >&2; exit 1 ;;
esac
: > "$LOG_FILE"
echo "RESOLVED_LOG_FILE=$LOG_FILE"
```

Parse the `RESOLVED_LOG_FILE=<absolute-path>` line from stdout. Save the path as `LOG_PATH` — this is the literal value substituted into Steps 2–5 below. Abort the skill if the command exits non-zero.

The log file lives **outside** `LOOP_TMPDIR` on purpose: `driver.sh`'s EXIT trap wipes `LOOP_TMPDIR` on completion (or retains it on failure), which would destroy the log mid-tail. Placing the log directly under `/tmp` keeps it available for post-run inspection.

### Step 2 — Surface the log path to the user (visible line)

Emit a prominent line (outside any suppressed-verbosity section) BEFORE launching Monitor, so the user always knows where the unfiltered output lives. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log: <LOG_PATH>
```

### Step 3 — Launch driver in background

Substitute the literal `LOG_PATH` from Step 1 (do NOT reference `$LOG_FILE` here — the prior shell is gone). Quote the path to tolerate any path containing spaces:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/driver.sh" $ARGUMENTS > "<LOG_PATH>" 2>&1
```

Launch this Bash command with `run_in_background: true`. When the background task completes, Claude Code emits an automatic task-completion notification — no additional end-of-run wiring is needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke the Monitor tool with `persistent: true` and the following command (substitute the literal `LOG_PATH` from Step 1; filter regex pinned byte-verbatim; MUST remain in parity with `driver.sh`'s three breadcrumb prefixes):

```
tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

where `"$LOG_FILE"` is the literal Step-1 path, double-quoted to tolerate whitespace in the path. The `$LOG_FILE` notation is preserved byte-verbatim as the canonical filter literal asserted by `scripts/test-loop-review-skill-md.sh`; at Monitor-invocation time, substitute the resolved absolute path into that literal.

- `tail -F` (capital F) tolerates the log file not yet existing at Monitor-attach time and handles rotation.
- `grep --line-buffered` keeps the pipe unbuffered so Monitor sees each line as the driver emits it.
- `persistent: true` is load-bearing for multi-slice sweeps.

### Step 5 — Completion

When the background Bash task completes, re-emit the log path so the user can easily retrieve the unfiltered output without scrolling. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log (retained): <LOG_PATH>
```

### What the Monitor stream shows vs. what the log file holds

- The **Monitor stream** (live in conversation) shows ONLY lines matching `^(✅|> \*\*🔶|\*\*⚠)` — the driver's three breadcrumb prefix families.
- The **log file** at `LOG_PATH` holds the FULL unfiltered output — every breadcrumb, all `/review` subprocess stdout, all stderr, and any other diagnostic lines. The file is retained on /tmp for post-run inspection.

### If Monitor is unavailable (older runtime)

If the Claude runtime does not expose the Monitor tool, the background Bash launch still runs and the task-completion notification still fires. Only the live stream is lost. To inspect driver progress in that case, run `tail -f <LOG_PATH>` in a separate shell using the path printed in Step 2.

## Verification

The driver's structural and behavioral contracts are regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-review-driver.sh`. The SKILL.md contract (frontmatter `allowed-tools`, log-path visibility, filter-regex parity with `driver.sh` breadcrumb helpers) is regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-review-skill-md.sh`. Both are wired into `make lint`.
