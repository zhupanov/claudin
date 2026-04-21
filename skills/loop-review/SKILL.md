---
name: loop-review
description: "Use when a comprehensive quality sweep or systematic code review is needed. Partitions the repo into slices, reviews each with a 3-reviewer panel, and files deduplicated GitHub issues via /issue for every actionable finding."
argument-hint: "[--debug] [partition criteria]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Loop Review

Review whole codebase. Partition to slices. Each slice = 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). File every actionable finding as deduped GitHub issue via `/issue`. Security-tagged findings held local (per SECURITY.md), not auto-filed.

**Flags**: Parse flags from start of `$ARGUMENTS` before rest = partition criteria. Flags any order, stop at first non-flag token. **All bool flags default `false`. Set `true` only when `--flag` token explicit. Flags independent — one flag presence no influence default of another.**

- `--debug`: Mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`. `--debug` controls only loop-review own verbosity; NOT propagated downstream. `/issue` no `--debug` flag, `/implement` no longer invoked by loop-review.

**Skill run fully autonomous** — never ask user confirm. Make all FILE/drop decisions per Step 3d criteria. Only sub-skill invoked via Skill tool = `/issue` (batch mode, `--input-file` with `--label loop-review`) so findings discoverable via label filter in issue tracker; reviewer lanes run as Cursor/Codex CLI processes or Claude Code Reviewer subagents direct, not through `/review`, `/design`, `/relevant-checks`. **The `loop-review` label must be pre-created in target repo** — Step 0 preflight-checks existence; if missing, skill append warning to `$LR_TMPDIR/warnings.md` and continue (issues filed unlabeled, excluded from `label:loop-review` discovery filter).

**Anti-halt continuation reminder.** Only child `Skill` tool call this skill makes = `/issue` (at Step 3f batch flush). After `/issue` return, IMMEDIATELY continue this skill NEXT step — do NOT end turn on child cleanup output. Rule strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). Normal sequential `proceed to Step N+1` = default continuation this rule reinforces, NOT exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for canonical rule. **Loop-internal note**: `/issue` in Step 3f invoked inside slice loop. After `/issue` return, continue slice loop per Step 3g explicit loop-back directive — do NOT exit loop unless exit condition fire.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so user instantly see where execution is. Follow formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print **start line** when enter step: e.g., `> **🔶 3: review + file issues — slice: scripts/...**`
- Print **completion line** when done: e.g., `✅ 3: review + file issues — 4 findings accumulated, 2 issues filed (3m12s)`

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | partition |
| 3 | review + file issues |
| 4 | summary |
| 5 | cleanup |

### Verbosity Control

**When `debug_mode=false` (default):**

- Empty string for `description` parameter on all Bash tool calls.
- Terse 3-5 word descriptions for Agent tool calls.
- No explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (slice results, per-batch `/issue` counters, held security notes, dropped nits, final report).

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text (current verbose behavior).

**Limitation**: Verbosity suppression prompt-enforced, best-effort.

## Step 0 — Session Setup

### 0a — Session Setup, Preflight, and Reviewer Check

Run shared session setup script. Handles preflight (must be on clean `main`), temp dir create, reviewer health probe in single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-loop-review --skip-slack-check --skip-repo-check --check-reviewers
```

Note: Neither `--skip-preflight` nor `--skip-branch-check` passed — ensures full preflight with branch check, enforces on-main requirement.

If script exit non-zero, print `PREFLIGHT_ERROR` from output and abort.

Parse output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `LR_TMPDIR` = `SESSION_TMPDIR`.

Set `codex_available` and `cursor_available` flags for whole session:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Append `**⚠ Codex not available (binary not found).**` to `$LR_TMPDIR/warnings.md`.
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Append `**⚠ Codex installed but not responding. Using Claude replacement.**` to `$LR_TMPDIR/warnings.md`.
- Else: `codex_available=true`
- Same logic for Cursor.

### 0b — Initialize Tracking Files

Init tracking files for slice review loop:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/init-session-files.sh --dir "$LR_TMPDIR"
```

### 0c — Preflight Label Check

Verify `loop-review` GitHub label exists in current repo. `/issue`'s create-one.sh drops unknown labels with stderr-only warning, and loop-review flush path only parses `/issue` stdout machine lines — so missing label would silent produce unlabeled issues escape final summary label filter. Preflight-check once here, not per-flush:

```bash
gh label list --limit 200 --json name --jq '.[].name' | grep -Fxq loop-review
```

If command exit non-zero (label missing OR `gh` unreachable), append `**⚠ 'loop-review' label not found in current repo — /issue will create issues unlabeled. Create it once with: gh label create loop-review --description "Surfaced by /loop-review" --color 5319E7**` to `$LR_TMPDIR/warnings.md`. Do NOT abort — skill still files issues, just no label. Step 4 summary surfaces warning.

## Step 1 — Partition the Repository

After flag stripping in Flags section above, save rest of `$ARGUMENTS` as `PARTITION_CRITERIA`. Use `PARTITION_CRITERIA` (not raw `$ARGUMENTS`) for all partition logic below.

### Custom criteria (if `PARTITION_CRITERIA` is non-empty)

Parse `PARTITION_CRITERIA` as partition strategy:

- `by directory` — same as default below
- `by module` — one slice per logical module: group related source files, handlers, tests together based on project module/package structure (e.g., one slice per package in Go, one per module dir in Python, one per feature dir in TypeScript)
- Explicit paths (space-separated) — use those dirs as slices
- Any other text — interpret as natural-language partition description, apply it

### Default: From partition config or auto-discovery

If `PARTITION_CRITERIA` empty:

1. **Check for `.claude/loop-review-partitions.json`**: If file exists, read it. Contains array of `{"name": "<slice name>", "paths": ["<path>", ...]}` objects. Use as slices.

2. **Auto-discovery fallback**: If no partition config, auto-discover slices by finding dirs at depth 1–2 from repo root containing source files (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`). Group to slices, one per top-level dir. Add final "Skills & documentation" slice for `.claude/skills/` and top-level `.md` files. Cap at 10 slices; merge smaller dirs to "other" bucket.

Print partition plan with file counts per slice.

## Step 3 — Slice Review Loop

Process slices with **batched issue filing**. Review slices sequential, but accumulate actionable findings across up to 3 slices before invoke `/issue --input-file` so `/issue` 2-phase LLM dedup run once per batch not once per finding (bounds Phase-2 30-candidate cap, minimizes network round-trips).

**Legacy `LOOP_REVIEW_DEFERRED.md`**: skill no longer creates, updates, or commits `LOOP_REVIEW_DEFERRED.md`. If file by that name exists in consumer repo, historical — skill leaves untouched.

For each slice (using `N` as 1-based slice index):

### 3a — Announce

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Reviewing Slice N/M: <name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 3b — Gather file list

Use Glob to collect relevant source files in slice (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`, `.md`, `.yaml`, `.yml`, `.json`). Exclude test files (e.g., `*_test.go`, `*_test.py`, `*.test.ts`, `*.spec.js`) from review targets (but tests = context for reviewers).

Write full file list to `$LR_TMPDIR/slice-N-files.txt` (one path per line) for external reviewers to read.

**Sub-slicing (>50 files):** If slice > 50 files, split file list to sub-slices of ≤50 files each. For each sub-slice, launch 1 Claude Code Reviewer subagent lane with only that sub-slice files as `{FILE_LIST}`. External reviewers always receive full slice file list (one invocation per slice regardless of sub-slicing). After all sub-slices and external reviewers complete, merge all Claude findings from all sub-slices with external reviewer findings before proceeding to Step 3d.

### 3c — Launch 3 review subagents in parallel

Launch **all 3 reviewer lanes** in **single message**. When external tools unavailable, launch Claude Code Reviewer subagent fallbacks so total reviewer count always = 3. **Spawn order matter for parallelism** — launch slowest reviewer first: Cursor (slowest), then Codex, then Claude Code Reviewer subagent (fastest). External reviewers launched once per slice even when sub-slicing. Claude subagent lane uses current sub-slice `{FILE_LIST}` if sub-slicing, else full file list. Each must **only report findings — never edit files**.

**Cursor Reviewer (if `cursor_available`):**

Run Cursor **first** in parallel message (take longest):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$LR_TMPDIR/cursor-output-slice-N.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Walk five focus areas: (1) code-quality: bugs, logic errors, dead code, duplication, missing error handling. (2) correctness: off-by-one, nil handling, type mismatches, races, error paths. (3) risk-integration: broken contracts, thread safety, deployment risks, CI gaps. (4) architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area using EXACTLY one of these labels: code-quality / correctness / risk-integration / architecture / security. Return numbered findings with focus-area tag, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on Bash tool call.

**Cursor fallback** (if `cursor_available` false): Launch Claude Code Reviewer subagent (subagent_type: `code-reviewer`) via Agent tool instead. Use unified Code Reviewer checklist. Bind `{FILE_LIST}` to **current sub-slice** file list when sub-slicing; else use full slice file list. Drop `"Work at your maximum reasoning effort"` suffix (Claude uses session-default effort).

**Codex Reviewer (if `codex_available`):**

Run Codex **second** in parallel message (after Cursor):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$LR_TMPDIR/codex-output-slice-N.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$LR_TMPDIR/codex-output-slice-N.txt" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Walk five focus areas: (1) code-quality: bugs, logic, reuse, tests, backward compat, style. (2) risk-integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area using EXACTLY one of these labels: code-quality / correctness / risk-integration / architecture / security. Return numbered findings with focus-area tag, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on Bash tool call.

**Codex fallback** (if `codex_available` false): Launch **1 Claude Code Reviewer subagent** via Agent tool (`subagent_type: code-reviewer`) with same slice-review context. Bind `{FILE_LIST}` to **current sub-slice** file list when sub-slicing (>50 files per slice), match always-on Claude lane sub-slicing rule; else use full slice file list. Reserve `slice-N-files.txt` (full slice) for actual external reviewers. Attribute as `Code`.

**Claude Code Reviewer subagent (1 reviewer, always-on — launched last in same parallel message, finish fastest):**

Invoke `subagent_type: code-reviewer` using unified checklist from `skills/shared/reviewer-templates.md`. The `code-reviewer` archetype walks five focus areas: code quality, risk/integration, correctness, architecture, security. Prompt body:

> Review EXISTING code for this project. Files: {FILE_LIST}. Read each file. Walk the unified 5-focus-area checklist (code quality, risk/integration, correctness, architecture, security). Tag each finding with its focus area. Quality gate: for each finding, verify the proposed fix is justified by a concrete need and proportionate to the issue. Return numbered findings: file:line, issue, specific fix. If none: "No issues found." Do NOT edit files.

**Collecting External Reviewer Results:**

Build arg list from only externals actually launched:

```
COLLECT_ARGS=()
[[ "$cursor_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/cursor-output-slice-N.txt")
[[ "$codex_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/codex-output-slice-N.txt")
```

**Zero-externals branch**: If BOTH Cursor and Codex unavailable for this slice (`COLLECT_ARGS` empty — 3 lanes = always-on Claude lane plus 2 Claude fallback lanes), **skip `collect-reviewer-results.sh` entirely** and **skip all external negotiation** below. Merge 3 Claude findings and proceed to Step 3d.

Else, invoke collection script with only launched paths:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 "${COLLECT_ARGS[@]}"
```

Parse structured output for each reviewer `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`: **immediately launch matching single Claude Code Reviewer subagent fallback** for current slice before proceed to Step 3d (so slice still has 3 lanes), then **flip that reviewer availability flag to false** for all remaining slices (prevents repeat failures). Also append detailed warning to `$LR_TMPDIR/warnings.md`.

### 3d — Collect, negotiate, deduplicate, and classify findings

**After ALL reviewers return** (always-on Claude Code Reviewer subagent lane AND any launched external reviewers or runtime-fallback Claude replacements), proceed:

**1. Collect** all findings from Claude Code Reviewer subagent lane and validated external reviewer output (and any runtime-fallback Claude findings).

**2. Negotiate** with external reviewers (if they produced findings):

Follow **Negotiation Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`, use `$LR_TMPDIR` as tmpdir, with `max_rounds=1`. Use `codex-negotiation-prompt.txt` / `codex-negotiation-output.txt` for single Codex negotiation track and `cursor-negotiation-prompt.txt` / `cursor-negotiation-output.txt` for Cursor negotiation track. Run both negotiations in parallel when both externals produced findings. Accept findings unless factual wrong or contradict CLAUDE.md.

Note: "accepted" in negotiation sense means finding valid — may still drop at Step 3d FILE gate below.

**3. Deduplicate** — merge findings from all reviewers (if two reviewers flag same issue, keep more specific suggestion).

**4. Classify each finding** (FILE gate with security-focus exception):

**→ FILE** (append to `$LR_TMPDIR/findings-accumulated.md` for batched `/issue` filing) if ALL of:
- Has specific, actionable concern (not vague).
- Cites concrete location (file, or file:line, or module).
- Focus area NOT `security`.

**→ HOLD LOCAL** (append to `$LR_TMPDIR/security-findings.md`, do NOT auto-file) if:
- Focus area = `security`. Per SECURITY.md, security vulns must not open as public GitHub issues — operator handles disclosure.

**→ DROP** (append one line to `$LR_TMPDIR/warnings.md` for visibility; do NOT file) if ANY of:
- Purely cosmetic nit (formatting, subjective naming) with no concrete fix impact.
- Vague concern without specific location or repro signal.
- Requires coordination with external systems or teams (not actionable as code-level issue).

Print classification: `📋 Slice N: X findings (Y to file, Z held local, W dropped)`

### 3e — Zero findings

If all reviewers found nothing: `✅ Slice N: <name> — Clean (<elapsed>)`. Continue to next slice.

### 3f — Accumulate findings and flush batch

For each classified finding in slice:
- **FILE**: append one entry to `$LR_TMPDIR/findings-accumulated.md` in this generic format (consumed by `/issue` `parse-input.sh` generic-format fallback):

  ```markdown
  ### <terse title, ≤ 80 chars, no leading `#` characters>

  **Slice**: <slice name>
  **File**: <path:line or path>
  **Reviewer**: <Code | Cursor | Codex>
  **Focus area**: <code-quality | correctness | risk-integration | architecture>

  **Problem**: <what's wrong, concrete>

  **Suggested fix**: <actionable fix>
  ```

  Body must be non-empty. If reviewer problem or fix text contains `###`-prefixed line at line-start (i.e., three hashes plus space), normalize (replace with `####` or prepend two spaces) so `parse-input.sh` not split finding into multiple items.

- **HOLD LOCAL**: append to `$LR_TMPDIR/security-findings.md` using same structured body but omit `###`-prefixed heading (or use `####`) so file never fed to `/issue`.
- **DROP**: append one line to `$LR_TMPDIR/warnings.md`: `- Slice <name>: dropped nit — <title> (<reviewer>)`.

**Flush condition**: invoke `/issue --input-file` when **any** of these true:
- 3 slices worth of FILE findings accumulated.
- This is last slice.
- Accumulated FILE findings reference more than 10 distinct files (keep each batch Phase 2 dedup window under `/issue` 30-candidate cap).

**When flushing — invoke `/issue` via Skill tool:**

If `$LR_TMPDIR/findings-accumulated.md` contains zero `###`-prefixed headings (all slices clean or all findings held/dropped), skip `/issue` invocation entirely.

Else, invoke `/issue` via Skill tool with:

```
--input-file $LR_TMPDIR/findings-accumulated.md --label loop-review
```

Do NOT pass `--debug`, `--auto`, or `--merge` — `/issue` is non-interactive skill, none of those flags apply. Do NOT forward `--title-prefix` — `loop-review` label = discovery mechanism, preserves 80-char title budget.

> **Continue after child returns (loop-internal).** When `/issue` returns, continue slice loop — parse `/issue` stdout for per-item `ITEM_<i>_*` lines, rebuild accumulator per per-item retention rule below, then proceed to Step 3g "Move to next slice." Do NOT exit slice loop to Step 4 unless Step 3g exit condition fire. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

**Per-item retention on partial failure.** After `/issue` return, parse stdout for any line matching `^(ISSUES?_[A-Z0-9_]+)=(.*)$`. Input-file order 1-indexed and stable: finding i in `findings-accumulated.md` (i-th `###`-prefixed heading) corresponds to `ITEM_<i>_*` on `/issue` stdout. Rebuild accumulator per-item:

- **Resolved** (remove from accumulator): any ITEM_<i>_* output with `ISSUE_<i>_NUMBER=<N>`, `ISSUE_<i>_DRY_RUN=true`, or `ISSUE_<i>_DUPLICATE=true`.
- **Retain in accumulator** (so next flush retries it): `ISSUE_<i>_FAILED=true`, or no ITEM_<i>_* line present.
- **Whole-batch failure** (no machine lines on stdout, or `/issue` exit non-zero without emitting them): retain whole accumulator unchanged, log warning to `$LR_TMPDIR/warnings.md`, proceed to next slice.

Update counters using `/issue` aggregate machine lines: bump `issue-count.txt` by `ISSUES_CREATED`, `issue-dedup-count.txt` by `ISSUES_DEDUPLICATED`, `issue-failed-count.txt` by `ISSUES_FAILED`.

**When NOT flushing**: Print `📦 Slice N findings accumulated (batch X/3). Continuing to next slice.` and proceed.

### 3g — Continue

Move to next slice. Go back to 3a.

## Step 4 — Final Summary

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Loop Review Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Slices reviewed: M/M
Issues filed: X   (deduplicated: Y, failed: Z)
Security-tagged findings held locally: W   (see $LR_TMPDIR/security-findings.md)
Findings dropped: V   (see warnings.md)

Per-slice breakdown:
  <slice name>: N findings (A filed, B held, C dropped)
  ...

Filter in GitHub: `is:issue is:open label:loop-review`
```

Counter sources: `X`/`Y`/`Z` from `$LR_TMPDIR/issue-count.txt` / `issue-dedup-count.txt` / `issue-failed-count.txt` files updated after each flush (Step 3f "Update counters" instruction). `W` derived at summary time by counting `####` HOLD-LOCAL headings in `$LR_TMPDIR/security-findings.md`, and `V` by counting lines in `$LR_TMPDIR/warnings.md` starting with per-drop format `- Slice <name>:` (format written by Step 3f for DROPPED nits). Per-slice totals accumulated as slice loop runs.

If `$LR_TMPDIR/security-findings.md` non-empty (use `[ -s "$LR_TMPDIR/security-findings.md" ]` via Bash tool call to decide — do NOT gate on mental counter `W` above, only display value), print **full verbatim contents** of file inline in summary output (session tmpdir removed by Step 5, so this is only durable copy surfaced to operator). Wrap under clearly-labeled block:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security-tagged findings (held locally per SECURITY.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
<full contents of $LR_TMPDIR/security-findings.md>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then print: `**⚠ Handle these findings per SECURITY.md's vulnerability-disclosure procedure. They are NOT filed as public GitHub issues. Session tmpdir is removed by Step 5 — preserve the block above if further triage is needed.**`

**Repeat any external reviewer warnings** accumulated in `$LR_TMPDIR/warnings.md` so visible at end. E.g.:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review timed out on slice 3**`
- `**⚠ /issue: label 'loop-review' not found, dropping**` — indicates label must be pre-created in target repo.

## Step 5 — Cleanup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$LR_TMPDIR"
```
