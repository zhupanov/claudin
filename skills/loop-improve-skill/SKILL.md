---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop in a GitHub issue; bash driver invokes the shared /improve-skill iteration kernel once per round; runs up to 10 rounds."
argument-hint: "[--slack] <skill-name>"
allowed-tools: Bash, Monitor
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then runs up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` via the shared iteration kernel at `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh` (the same kernel `/improve-skill` invokes standalone). The kernel itself spawns each child skill (`/skill-judge`, `/design`, `/im`) as a fresh `claude -p` subprocess. Halt class eliminated by construction: each child's report is its subprocess's output, so there is no post-child-return model turn that can halt (closes #273).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

## Flags

- `--slack`: When present before `<skill-name>`, forwarded to the driver and thence prepended to every `/larch:im` invocation in the loop (so each iteration's PR posts to Slack). Default: absent — no iteration posts to Slack regardless of Slack env-var presence. Note: with `--slack`, the loop's up-to-10 iterations can produce up to 10 Slack PR announcements; opt in only when that is the desired signal.

**Termination contract: strive for grade A.** The loop's primary success exit is when `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` reports per-dimension grade A on every D1..D8. The loop continues iterating until (a) grade A is achieved, (b) further automated progress is genuinely infeasible (no_plan / design_refusal / im_verification_failed, with written justification), or (c) the 10-iteration cap is reached (final re-judge captures post-cap grade). Token/context budget is NOT a valid exit condition.

## Driver

Execution is delegated to the bash driver at `${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh`. The driver owns loop control, tracking-issue creation, grade-history aggregation, post-iter-cap final `/skill-judge` re-evaluation, close-out composition, and cleanup. Per-iteration mechanics (judge → design → im → verify) live in the shared kernel at `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh`, invoked by the driver once per round via direct bash call with `--work-dir $LOOP_TMPDIR --iter-num $ITER --issue $ISSUE_NUM`. See `driver.sh` and `scripts/iteration.md` source for the full contract.

## Live streaming pattern (Bash background + Monitor)

The driver runs for minutes to hours (up to 10 iterations of `/skill-judge` → `/design` → `/im`). To give the user live visibility into driver progress without reintroducing the halt class eliminated by #273, this skill launches `driver.sh` as a **background Bash task** with combined stdout/stderr redirected to a stable log-file path, then **attaches Monitor** to tail that file filtered to the driver's step-marker lines. The streaming contract (background Bash + filtered Monitor tail) is unchanged from #291; the refactor factored out the per-iteration body into `skills/improve-skill/scripts/iteration.sh` without altering the log-path security boundary, filter regex, or breadcrumb prefix families that Monitor relies on. Monitor is passive observability only.

### Shell-state discipline (MANDATORY)

Every Bash tool call is a fresh shell — environment variables set in one Bash call do **not** survive into the next. The steps below therefore **resolve the log path once** (Step 1) and then embed the **literal resolved absolute path** into every downstream command (Steps 2–5). Do NOT use `$LOG_FILE` as an unresolved variable in Steps 2, 3, 4, or 5 — substitute the literal path returned by Step 1.

### Step 1 — Resolve and validate log path (synchronous Bash)

Run this command synchronously (NOT `run_in_background`) and capture the `RESOLVED_LOG_FILE=` line from its stdout. The `LOOP_DRIVER_LOG_FILE` env-overridable default is validated to begin with `/tmp/` or `/private/tmp/` (preventing the env var from being used as an arbitrary write/truncate primitive) and to contain no `..` path components (mirroring `driver.sh`'s own `LOOP_TMPDIR` prefix + `..` guard).

```bash
LOG_FILE="${LOOP_DRIVER_LOG_FILE:-/tmp/loop-improve-skill-driver-$(date +%s)-$$.log}"
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

The log file lives **outside** `LOOP_TMPDIR` on purpose: `driver.sh`'s EXIT trap wipes `LOOP_TMPDIR` on completion, which would destroy the log mid-tail. Placing the log directly under `/tmp` keeps it available for post-run inspection.

### Step 2 — Surface the log path to the user (visible line)

Emit a prominent line (outside any suppressed-verbosity section) BEFORE launching Monitor, so the user always knows where the unfiltered output lives. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log: <LOG_PATH>
```

### Step 3 — Launch driver in background

Substitute the literal `LOG_PATH` from Step 1 (do NOT reference `$LOG_FILE` here — the prior shell is gone). Quote the path to tolerate any path containing spaces:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh" $ARGUMENTS > "<LOG_PATH>" 2>&1
```

Launch this Bash command with `run_in_background: true`. When the background task completes, Claude Code emits an automatic task-completion notification — no additional end-of-run wiring is needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke the Monitor tool with `persistent: true` and the following command (substitute the literal `LOG_PATH` from Step 1; filter regex pinned byte-verbatim; MUST remain in parity with `driver.sh`'s three breadcrumb prefixes):

```
tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

where `"$LOG_FILE"` is the literal Step-1 path, double-quoted to tolerate whitespace in the path. The `$LOG_FILE` notation is preserved byte-verbatim as the canonical filter literal asserted by `scripts/test-loop-improve-skill-skill-md.sh`; at Monitor-invocation time, substitute the resolved absolute path into that literal (e.g. `tail -F "/tmp/loop-improve-skill-driver-1713720000-12345.log" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`).

- `tail -F` (capital F) tolerates the log file not yet existing at Monitor-attach time and handles rotation — `tail -f` would fail on a missing file.
- `grep --line-buffered` keeps the pipe unbuffered so Monitor sees each line as the driver emits it.
- `persistent: true` is load-bearing: non-persistent Monitor has a max timeout far shorter than multi-hour driver runs.

### Step 5 — Completion

When the background Bash task completes, re-emit the log path so the user can easily retrieve the unfiltered output without scrolling. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full driver log (retained): <LOG_PATH>
```

### What the Monitor stream shows vs. what the log file holds

- The **Monitor stream** (live in conversation) shows ONLY lines matching `^(✅|> \*\*🔶|\*\*⚠)` — i.e., the driver's three breadcrumb prefix families (`breadcrumb_done`, `breadcrumb_inprogress`, `breadcrumb_warn`).
- The **log file** at `LOG_PATH` holds the FULL unfiltered output — including every breadcrumb (filtered and unfiltered), all `/skill-judge` / `/design` / `/im` subprocess stdout, all stderr, and any other diagnostic lines that do not match the filter. The file is retained on /tmp for post-run inspection.

### If Monitor is unavailable (older runtime)

If the Claude runtime does not expose the Monitor tool, the background Bash launch still runs and the task-completion notification still fires. Only the live stream is lost. To inspect driver progress in that case, run `tail -f <LOG_PATH>` (or `less +F <LOG_PATH>`) in a separate shell using the path printed in Step 2.

## Verification

The driver's structural and behavioral contracts are regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-driver.sh`. The SKILL.md contract (frontmatter `allowed-tools`, log-path visibility, and filter-regex parity with `driver.sh` breadcrumb helpers) is regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-skill-md.sh`. Both are wired into `make lint`. On success the driver posts a close-out comment to the tracking issue containing a `## Grade History` section and (for non-grade-A exits) an `## Infeasibility Justification` section — reviewing that comment is the user-visible verification that the loop ran to an authoritative exit.
