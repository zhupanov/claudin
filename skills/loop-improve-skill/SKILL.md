---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop in a GitHub issue; bash driver invokes /skill-judge, /design, /im as fresh `claude -p` subprocesses; runs up to 10 rounds."
argument-hint: "<skill-name>"
allowed-tools: Bash, Monitor
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then runs up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` — each invoked as a fresh `claude -p` subprocess by the driver. Halt class eliminated by construction: each child's report is its subprocess's output, so there is no post-child-return model turn that can halt (closes #273).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Termination contract: strive for grade A.** The loop's primary success exit is when `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` reports per-dimension grade A on every D1..D8. The loop continues iterating until (a) grade A is achieved, (b) further automated progress is genuinely infeasible (no_plan / design_refusal / im_verification_failed, with written justification), or (c) the 10-iteration cap is reached (final re-judge captures post-cap grade). Token/context budget is NOT a valid exit condition.

## Driver

Execution is delegated to the bash driver at `${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh`. The driver owns loop control, subprocess invocation, grade parsing, audit-trail posting, infeasibility detection, close-out composition, and cleanup. See `driver.sh` source for the loop semantics.

## Live streaming pattern (Bash background + Monitor)

The driver runs for minutes to hours (up to 10 iterations of `/skill-judge` → `/design` → `/im`). To give the user live visibility into driver progress without reintroducing the halt class eliminated by #273, this skill launches `driver.sh` as a **background Bash task** with combined stdout/stderr redirected to a stable log-file path, then **attaches Monitor** to tail that file filtered to the driver's step-marker lines. The driver itself is byte-identical to its pre-#291 version — Monitor is passive observability only.

### Step 1 — Choose and validate log path

Compute the log-file path with an env-overridable default. The override (`LOOP_DRIVER_LOG_FILE`) MUST point under `/tmp/` or `/private/tmp/` — an arbitrary path would turn this into a write/truncate primitive, which is not the intent.

```bash
LOG_FILE="${LOOP_DRIVER_LOG_FILE:-/tmp/loop-improve-skill-driver-$(date +%s)-$$.log}"
case "$LOG_FILE" in
  /tmp/*|/private/tmp/*) ;;
  *) echo "LOOP_DRIVER_LOG_FILE must start with /tmp/ or /private/tmp/ (got: $LOG_FILE)" >&2; exit 1 ;;
esac
: > "$LOG_FILE"
```

The log file lives **outside** `LOOP_TMPDIR` on purpose: `driver.sh`'s EXIT trap wipes `LOOP_TMPDIR` on completion, which would destroy the log mid-tail. Placing the log directly under `/tmp` keeps it available for post-run inspection.

### Step 2 — Surface the log path to the user (visible line)

Emit a prominent line (outside any suppressed-verbosity section) BEFORE launching Monitor, so the user always knows where the unfiltered output lives:

```
📄 Full driver log: $LOG_FILE
```

### Step 3 — Launch driver in background

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh" $ARGUMENTS > "$LOG_FILE" 2>&1
```

Launch this Bash command with `run_in_background: true`. When the background task completes, Claude Code emits an automatic task-completion notification — no additional end-of-run wiring is needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke the Monitor tool with `persistent: true` and the following command (filter regex pinned byte-verbatim; MUST remain in parity with `driver.sh`'s three breadcrumb prefixes):

```
tail -F $LOG_FILE | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

- `tail -F` (capital F) tolerates the log file not yet existing at Monitor-attach time and handles rotation — `tail -f` would fail on a missing file.
- `grep --line-buffered` keeps the pipe unbuffered so Monitor sees each line as the driver emits it.
- `persistent: true` is load-bearing: non-persistent Monitor has a max timeout far shorter than multi-hour driver runs.

### Step 5 — Completion

When the background Bash task completes, re-emit the log path so the user can easily retrieve the unfiltered output without scrolling:

```
📄 Full driver log (retained): $LOG_FILE
```

### What the Monitor stream shows vs. what the log file holds

- The **Monitor stream** (live in conversation) shows ONLY lines matching `^(✅|> \*\*🔶|\*\*⚠)` — i.e., the driver's three breadcrumb prefix families (`breadcrumb_done`, `breadcrumb_inprogress`, `breadcrumb_warn`).
- The **log file** at `$LOG_FILE` holds the FULL unfiltered output — including every breadcrumb (filtered and unfiltered), all `/skill-judge` / `/design` / `/im` subprocess stdout, all stderr, and any other diagnostic lines that do not match the filter. The file is retained on /tmp for post-run inspection.

### If Monitor is unavailable (older runtime)

If the Claude runtime does not expose the Monitor tool, the background Bash launch still runs and the task-completion notification still fires. Only the live stream is lost. To inspect driver progress in that case, run `tail -f "$LOG_FILE"` (or `less +F "$LOG_FILE"`) in a separate shell using the path printed in Step 2.

## Verification

The driver's structural and behavioral contracts are regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-driver.sh`. The SKILL.md contract (frontmatter `allowed-tools`, log-path visibility, and filter-regex parity with `driver.sh` breadcrumb helpers) is regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-skill-md.sh`. Both are wired into `make lint`. On success the driver posts a close-out comment to the tracking issue containing a `## Grade History` section and (for non-grade-A exits) an `## Infeasibility Justification` section — reviewing that comment is the user-visible verification that the loop ran to an authoritative exit.
