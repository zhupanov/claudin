---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop in a GitHub issue; bash driver invokes /skill-judge, /design, /im as fresh `claude -p` subprocesses; runs up to 10 rounds."
argument-hint: "<skill-name>"
allowed-tools: Bash, Monitor
---

# loop-improve-skill

Improve existing skill iteratively. Make tracking GitHub issue, run up to 10 rounds of `/skill-judge` → `/design` → `/im` — each fresh `claude -p` subprocess from driver. Halt class gone by design: child report = subprocess output, no post-child model turn to halt (closes #273).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Termination contract: strive grade A.** Loop success = `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` report grade A on every D1..D8. Loop keep go until (a) grade A hit, (b) more progress infeasible (no_plan / design_refusal / im_verification_failed, with written justification), or (c) 10-iter cap hit (final re-judge catch post-cap grade). Token/context budget NOT valid exit.

## Driver

Bash driver do work: `${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh`. Driver own loop control, subprocess invoke, grade parse, audit post, infeasibility detect, close-out, cleanup. See `driver.sh` for loop semantics.

## Live streaming pattern (Bash background + Monitor)

Driver run minutes to hours (up to 10 iter of `/skill-judge` → `/design` → `/im`). For live user visibility without bring back halt class from #273, skill launch `driver.sh` as **background Bash task** with combined stdout/stderr to stable log path, then **attach Monitor** to tail file filtered to driver step-marker lines. Driver itself byte-identical to pre-#291 — Monitor just passive watch.

### Shell-state discipline (MANDATORY)

Every Bash call = fresh shell — env vars from one call NOT survive next. So steps below **resolve log path once** (Step 1), embed **literal absolute path** into every downstream cmd (Steps 2–5). Do NOT use `$LOG_FILE` as unresolved var in Steps 2, 3, 4, 5 — swap literal path from Step 1.

### Step 1 — Resolve and validate log path (synchronous Bash)

Run sync (NOT `run_in_background`), capture `RESOLVED_LOG_FILE=` line from stdout. `LOOP_DRIVER_LOG_FILE` env-override default validated to start with `/tmp/` or `/private/tmp/` (stop env var being arbitrary write/truncate primitive), no `..` path parts (match `driver.sh` `LOOP_TMPDIR` prefix + `..` guard).

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

Parse `RESOLVED_LOG_FILE=<absolute-path>` line from stdout. Save as `LOG_PATH` — this literal value go into Steps 2–5. Abort skill if cmd exit non-zero.

Log file live **outside** `LOOP_TMPDIR` on purpose: `driver.sh` EXIT trap wipe `LOOP_TMPDIR` on done, kill log mid-tail. Put log under `/tmp` keep it for post-run look.

### Step 2 — Surface the log path to the user (visible line)

Emit big line (outside suppressed-verbosity) BEFORE Monitor launch, so user always know where raw output live. Swap literal `LOG_PATH` from Step 1:

```
📄 Full driver log: <LOG_PATH>
```

### Step 3 — Launch driver in background

Swap literal `LOG_PATH` from Step 1 (do NOT use `$LOG_FILE` — prior shell gone). Quote path for space tolerance:

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh" $ARGUMENTS > "<LOG_PATH>" 2>&1
```

Launch Bash cmd with `run_in_background: true`. When background done, Claude Code fire auto task-complete notification — no more end-of-run wiring needed.

### Step 4 — Attach Monitor to the filtered live stream

Invoke Monitor with `persistent: true` and cmd below (swap literal `LOG_PATH` from Step 1; filter regex pinned byte-verbatim; MUST match `driver.sh` three breadcrumb prefixes):

```
tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'
```

where `"$LOG_FILE"` = literal Step-1 path, double-quoted for whitespace. `$LOG_FILE` notation kept byte-verbatim as canonical filter literal asserted by `scripts/test-loop-improve-skill-skill-md.sh`; at Monitor-invoke time, swap resolved absolute path into literal (e.g. `tail -F "/tmp/loop-improve-skill-driver-1713720000-12345.log" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`).

- `tail -F` (cap F) handle log file not exist yet at Monitor-attach and handle rotation — `tail -f` fail on missing file.
- `grep --line-buffered` keep pipe unbuffered so Monitor see each line as driver emit.
- `persistent: true` load-bearing: non-persistent Monitor timeout way shorter than multi-hour driver runs.

### Step 5 — Completion

When background Bash done, re-emit log path so user grab raw output no scroll. Swap literal `LOG_PATH` from Step 1:

```
📄 Full driver log (retained): <LOG_PATH>
```

### What the Monitor stream shows vs. what the log file holds

- **Monitor stream** (live in convo) show ONLY lines match `^(✅|> \*\*🔶|\*\*⚠)` — driver three breadcrumb prefix families (`breadcrumb_done`, `breadcrumb_inprogress`, `breadcrumb_warn`).
- **Log file** at `LOG_PATH` hold FULL raw output — every breadcrumb (filtered + not), all `/skill-judge` / `/design` / `/im` subprocess stdout, all stderr, other diagnostic lines not match filter. File kept on /tmp for post-run look.

### If Monitor is unavailable (older runtime)

If Claude runtime no expose Monitor tool, background Bash launch still run, task-complete notification still fire. Only live stream lost. To check driver progress then, run `tail -f <LOG_PATH>` (or `less +F <LOG_PATH>`) in other shell using path from Step 2.

## Verification

Driver structural + behavioral contracts regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-driver.sh`. SKILL.md contract (frontmatter `allowed-tools`, log-path visibility, filter-regex parity with `driver.sh` breadcrumb helpers) regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-skill-md.sh`. Both wired into `make lint`. On success driver post close-out comment to tracking issue with `## Grade History` section and (for non-grade-A exits) `## Infeasibility Justification` section — read that comment = user-visible check that loop ran to real exit.
