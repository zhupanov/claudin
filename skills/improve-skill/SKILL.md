---
name: improve-skill
description: "Use when running exactly one iteration of the judge-design-implement loop (judge → design → im) against an existing larch skill; bash kernel invokes each child skill as a fresh `claude -p` subprocess."
argument-hint: "[--no-slack] [--issue <N>] <skill-name>"
allowed-tools: Bash, Monitor
---

# improve-skill

Run **one iteration** of the iterative skill-improvement pipeline against an existing skill: `/skill-judge` → grade parse → `/design` (with a narrow per-finding pushback carve-out for skill-judge findings that appear erroneous) → `/larch:im`. Each child skill runs as a fresh `claude -p` subprocess invoked by the bash kernel at `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh` so the halt class eliminated by `#273` stays eliminated — there is no post-child-return model turn to halt between child-return and post-call Bash.

Example: `/improve-skill design` or `/improve-skill --issue 391 design`.

The companion `/loop-improve-skill` skill calls the same `iteration.sh` kernel up to 10 times from its own driver; `/improve-skill` is the single-iteration wrapper users invoke directly.

## Flags

- `--no-slack`: When present before `<skill-name>`, forwarded to the `/larch:im` invocation inside the iteration so the PR does NOT post to Slack. Default: absent — `/larch:im` posts to Slack per `/implement`'s default-on behavior (gated on Slack env vars).
- `--issue <N>`: When present, the iteration reuses tracking issue #N instead of creating a new one. Used by `/loop-improve-skill`'s driver to accumulate all 10 iterations' comments on one issue. Standalone users who want their iteration comments on an existing issue can also supply `--issue <N>`.

**Termination contract: strives for grade A in this single iteration.** The iteration's success exit is when `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` reports per-dimension grade A on every D1..D8 immediately from the first `/skill-judge` call (short-circuits before `/design`). Otherwise the iteration runs `/design` + `/larch:im`, then exits with `ITER_STATUS=ok` if `/larch:im` reached its canonical completion line, or `ITER_STATUS=no_plan` / `design_refusal` / `im_verification_failed` on recoverable halts (each writes an infeasibility justification under the work-dir).

## Kernel

Execution is delegated to the bash kernel at `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh`. The kernel owns argv parsing, work-dir management, tracking-issue creation or adoption, prompt assembly (including the amended four-rule `/design` directive set carrying the pushback carve-out), subprocess invocation, grade parsing, verification, tracking-issue comment posting, cleanup, and KV-footer emission on stdout. See `iteration.sh` source and `iteration.md` sibling contract for the full contract.

## Pushback on judge findings — narrow carve-out

The amended `/design` prompt in `iteration.sh` allows **per-finding** pushback on `/skill-judge` findings that appear erroneous. `/design` may include a `## Pushback on judge findings` subsection at the plan's end, with per-finding justification (which dimension + short excerpt, specific reasoning for why the finding is erroneous or misapplied, concrete codebase evidence via `file:line` references or verbatim quotes). Pushback is strictly per-finding — the plan MUST still address every undisputed non-A dimension with concrete implementable steps. The existing three directives remain in force: `/design` still must not emit no-plan sentinels, must not self-curtail on budget grounds, and must address minor findings with small plans.

## Live streaming pattern (Bash background + Monitor)

The kernel runs for many minutes (judge + design + `/larch:im` each can run 10–20 min). To give the user live visibility without reintroducing the halt class eliminated by `#273`, this skill launches `iteration.sh` as a **background Bash task** with combined stdout/stderr redirected to a stable log-file path, then **attaches Monitor** to tail that file filtered to the kernel's breadcrumb lines. The kernel itself is byte-aligned with `/loop-improve-skill/scripts/driver.sh`'s breadcrumb helpers (`breadcrumb_done`, `breadcrumb_inprogress`, `breadcrumb_warn`) — Monitor is passive observability only, not a new Skill-tool chain.

### Shell-state discipline (MANDATORY)

Every Bash tool call is a fresh shell — environment variables set in one Bash call do **not** survive into the next. The steps below therefore **resolve the log path once** (Step 1) and then embed the **literal resolved absolute path** into every downstream command (Steps 2–5). Do NOT use `$LOG_FILE` as an unresolved variable in Steps 2, 3, 4, or 5 — substitute the literal path returned by Step 1.

### Step 1 — Resolve and validate log path (synchronous Bash)

Run this command synchronously (NOT `run_in_background`) and capture the `RESOLVED_LOG_FILE=` line from its stdout. The `IMPROVE_SKILL_LOG_FILE` env-overridable default is validated to begin with `/tmp/` or `/private/tmp/` (preventing the env var from being used as an arbitrary write/truncate primitive) and to contain no `..` path components (mirroring `iteration.sh`'s own work-dir prefix + `..` guard).

```bash
LOG_FILE="${IMPROVE_SKILL_LOG_FILE:-/tmp/improve-skill-iteration-$(date +%s)-$$.log}"
case "$LOG_FILE" in
  /tmp/*|/private/tmp/*) ;;
  *) echo "IMPROVE_SKILL_LOG_FILE must start with /tmp/ or /private/tmp/ (got: $LOG_FILE)" >&2; exit 1 ;;
esac
case "$LOG_FILE" in
  */..|*/../*) echo "IMPROVE_SKILL_LOG_FILE must not contain '..' path components (got: $LOG_FILE)" >&2; exit 1 ;;
esac
: > "$LOG_FILE"
echo "RESOLVED_LOG_FILE=$LOG_FILE"
```

Parse the `RESOLVED_LOG_FILE=<absolute-path>` line from stdout. Save the path as `LOG_PATH` — this is the literal value substituted into Steps 2–5 below. Abort the skill if the command exits non-zero.

The log file lives **outside** the kernel's work-dir on purpose: `iteration.sh`'s EXIT trap wipes the work-dir in standalone mode (the common user path), which would destroy the log mid-tail. Placing the log directly under `/tmp` keeps it available for post-run inspection.

### Step 2 — Surface the log path to the user (visible line)

Emit a prominent line (outside any suppressed-verbosity section) BEFORE launching Monitor, so the user always knows where the unfiltered output lives. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full iteration log: <LOG_PATH>
```

### Step 3 — Launch iteration kernel in background

Substitute the literal `LOG_PATH` from Step 1 (do NOT reference `$LOG_FILE` here — the prior shell is gone). Quote the path to tolerate any path containing spaces:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh" $ARGUMENTS > "<LOG_PATH>" 2>&1
```

Launch this Bash command with `run_in_background: true`. When the background task completes, Claude Code emits an automatic task-completion notification — no additional end-of-run wiring is needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke the Monitor tool with `persistent: true` and the following command (substitute the literal `LOG_PATH` from Step 1; filter regex pinned byte-verbatim; MUST remain in parity with `iteration.sh`'s three breadcrumb prefixes):

```
tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

where `"$LOG_FILE"` is the literal Step-1 path, double-quoted to tolerate whitespace in the path. The `$LOG_FILE` notation is preserved byte-verbatim as the canonical filter literal asserted by `scripts/test-improve-skill-skill-md.sh`; at Monitor-invocation time, substitute the resolved absolute path into that literal (e.g. `tail -F "/tmp/improve-skill-iteration-1713720000-12345.log" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`).

- `tail -F` (capital F) tolerates the log file not yet existing at Monitor-attach time and handles rotation — `tail -f` would fail on a missing file.
- `grep --line-buffered` keeps the pipe unbuffered so Monitor sees each line as the kernel emits it.
- `persistent: true` is load-bearing: non-persistent Monitor has a max timeout far shorter than long-running kernel runs.

### Step 5 — Completion

When the background Bash task completes, re-emit the log path so the user can easily retrieve the unfiltered output without scrolling. Substitute the literal `LOG_PATH` from Step 1:

```
📄 Full iteration log (retained): <LOG_PATH>
```

### What the Monitor stream shows vs. what the log file holds

- The **Monitor stream** (live in conversation) shows ONLY lines matching `^(✅|> \*\*🔶|\*\*⚠)` — i.e., the kernel's three breadcrumb prefix families (`breadcrumb_done`, `breadcrumb_inprogress`, `breadcrumb_warn`).
- The **log file** at `LOG_PATH` holds the FULL unfiltered output — including every breadcrumb (filtered and unfiltered), the KV footer (`### iteration-result` block with 9 keys), all `/skill-judge` / `/design` / `/im` subprocess stdout, all stderr, and any other diagnostic lines that do not match the filter. The file is retained on `/tmp` for post-run inspection.

### If Monitor is unavailable (older runtime)

If the Claude runtime does not expose the Monitor tool, the background Bash launch still runs and the task-completion notification still fires. Only the live stream is lost. To inspect iteration progress in that case, run `tail -f <LOG_PATH>` (or `less +F <LOG_PATH>`) in a separate shell using the path printed in Step 2.

## Verification

The kernel's structural and behavioral contracts are regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-improve-skill-iteration.sh`. The SKILL.md contract (frontmatter `allowed-tools`, log-path visibility, and filter-regex parity with `iteration.sh` breadcrumb helpers) is regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-improve-skill-skill-md.sh`. Both are wired into `make lint`. The loop-companion `/loop-improve-skill` reuses the same kernel; its driver's KV-footer parse contract is regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-driver.sh`.
