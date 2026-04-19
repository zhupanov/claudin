---
name: loop-review
description: "Use when a comprehensive quality sweep or systematic code review is needed. Partitions the repo into slices, reviews each with a 3-reviewer panel, and files deduplicated GitHub issues via /issue for every actionable finding."
argument-hint: "[--debug] [partition criteria]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, WebSearch, Skill
---

# Loop Review

Systematically review the entire codebase by partitioning into slices, reviewing each with a 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor), and filing every actionable finding as a deduplicated GitHub issue via `/issue`. Security-tagged findings are held locally (per SECURITY.md) instead of auto-filed.

**Flags**: Parse flags from the start of `$ARGUMENTS` before treating the remainder as partition criteria. Flags may appear in any order; stop at the first non-flag token. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`. `--debug` controls only loop-review's own verbosity; it is NOT propagated downstream. `/issue` does not expose a `--debug` flag, and `/implement` is no longer invoked by loop-review.

**This skill runs fully autonomously** — never ask for user confirmation. Make all FILE/drop decisions based on the classification criteria in Step 3d. The only sub-skill invoked via the Skill tool is `/issue` (in batch mode, `--input-file` with `--label loop-review`) so findings are discoverable via label filter in the issue tracker; the reviewer lanes run as Cursor/Codex CLI processes or Claude Code Reviewer subagents directly, not through `/review`, `/design`, or `/relevant-checks`. **The `loop-review` label must be pre-created in the target repository** — Step 0 preflight-checks its existence; if missing, the skill appends a warning to `$LR_TMPDIR/warnings.md` and continues (issues will be filed unlabeled and excluded from the `label:loop-review` discovery filter).

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 3: review + file issues — slice: scripts/...**`
- Print a **completion line** when done: e.g., `✅ 3: review + file issues — 4 findings accumulated, 2 issues filed (3m12s)`

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

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (slice results, per-batch `/issue` counters, held security notes, dropped nits, final report).

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text (current verbose behavior).

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Step 0 — Session Setup

### 0a — Session Setup, Preflight, and Reviewer Check

Run the shared session setup script. This handles preflight (must be on clean `main`), temp directory creation, and reviewer health probe in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-loop-review --skip-slack-check --skip-repo-check --check-reviewers
```

Note: Neither `--skip-preflight` nor `--skip-branch-check` is passed — this ensures full preflight with branch check, which enforces the on-main requirement.

If the script exits non-zero, print the `PREFLIGHT_ERROR` from its output and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `LR_TMPDIR` = `SESSION_TMPDIR`.

Set `codex_available` and `cursor_available` flags for the entire session:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Append `**⚠ Codex not available (binary not found).**` to `$LR_TMPDIR/warnings.md`.
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Append `**⚠ Codex installed but not responding. Using Claude replacement.**` to `$LR_TMPDIR/warnings.md`.
- Else: `codex_available=true`
- Same logic for Cursor.

### 0b — Initialize Tracking Files

Initialize tracking files for the slice review loop:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/init-session-files.sh --dir "$LR_TMPDIR"
```

### 0c — Preflight Label Check

Verify the `loop-review` GitHub label exists in the current repository. `/issue`'s create-one.sh drops unknown labels with a stderr-only warning, and loop-review's flush path only parses `/issue`'s stdout machine lines — so a missing label would silently produce unlabeled issues that escape the final summary's label filter. Preflight-check once here, not per-flush:

```bash
gh label list --limit 200 --json name --jq '.[].name' | grep -Fxq loop-review
```

If the command exits non-zero (label missing OR `gh` unreachable), append `**⚠ 'loop-review' label not found in current repo — /issue will create issues unlabeled. Create it once with: gh label create loop-review --description "Surfaced by /loop-review" --color 5319E7**` to `$LR_TMPDIR/warnings.md`. Do NOT abort — the skill still files issues, they will just not carry the label. The Step 4 summary surfaces the warning.

## Step 1 — Partition the Repository

After flag stripping in the Flags section above, save the remainder of `$ARGUMENTS` as `PARTITION_CRITERIA`. Use `PARTITION_CRITERIA` (not raw `$ARGUMENTS`) for all partition logic below.

### Custom criteria (if `PARTITION_CRITERIA` is non-empty)

Parse `PARTITION_CRITERIA` as the partition strategy:

- `by directory` — same as default below
- `by module` — one slice per logical module: group related source files, handlers, and tests together based on the project's module/package structure (e.g., one slice per package in Go, one per module directory in Python, one per feature directory in TypeScript)
- Explicit paths (space-separated) — use those directories as slices
- Any other text — interpret as a natural-language description of how to partition and apply it

### Default: From partition config or auto-discovery

If `PARTITION_CRITERIA` is empty:

1. **Check for `.claude/loop-review-partitions.json`**: If this file exists, read it. It contains an array of `{"name": "<slice name>", "paths": ["<path>", ...]}` objects. Use these as the slices.

2. **Auto-discovery fallback**: If no partition config exists, auto-discover slices by finding directories at depth 1–2 from the repo root that contain source files (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`). Group them into slices, one per top-level directory. Add a final "Skills & documentation" slice for `.claude/skills/` and top-level `.md` files. Cap at 10 slices; merge smaller directories into an "other" bucket.

Print the partition plan with file counts per slice.

## Step 3 — Slice Review Loop

Process slices with **batched issue filing**. Review slices sequentially, but accumulate actionable findings across up to 3 slices before invoking `/issue --input-file` so `/issue`'s 2-phase LLM dedup runs once per batch instead of once per finding (bounds the Phase-2 30-candidate cap and minimizes network round-trips).

**Legacy `LOOP_REVIEW_DEFERRED.md`**: this skill no longer creates, updates, or commits `LOOP_REVIEW_DEFERRED.md`. If a file by that name exists in a consumer repo, it is historical and this skill leaves it untouched.

For each slice (using `N` as the 1-based slice index):

### 3a — Announce

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔍 Reviewing Slice N/M: <name>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

### 3b — Gather file list

Use Glob to collect relevant source files in the slice (common extensions: `.py`, `.ts`, `.tsx`, `.js`, `.jsx`, `.go`, `.rs`, `.java`, `.rb`, `.sh`, `.c`, `.cpp`, `.cs`, `.md`, `.yaml`, `.yml`, `.json`). Exclude test files (e.g., `*_test.go`, `*_test.py`, `*.test.ts`, `*.spec.js`) from review targets (but tests serve as context for reviewers).

Write the full file list to `$LR_TMPDIR/slice-N-files.txt` (one path per line) for external reviewers to read.

**Sub-slicing (>50 files):** If the slice has more than 50 files, split the file list into sub-slices of ≤50 files each. For each sub-slice, launch 1 Claude Code Reviewer subagent lane with only that sub-slice's files as `{FILE_LIST}`. External reviewers always receive the full slice file list (one invocation per slice regardless of sub-slicing). After all sub-slices and external reviewers complete, merge all Claude findings from all sub-slices with external reviewer findings before proceeding to Step 3d.

### 3c — Launch 3 review subagents in parallel

Launch **all 3 reviewer lanes** in a **single message**. When external tools are unavailable, launch Claude Code Reviewer subagent fallbacks instead so the total reviewer count always remains 3. **Spawn order matters for parallelism** — launch the slowest reviewer first: Cursor (slowest), then Codex, then the Claude Code Reviewer subagent (fastest). External reviewers are launched once per slice even when sub-slicing. The Claude subagent lane uses the current sub-slice's `{FILE_LIST}` if sub-slicing, or the full file list otherwise. Each must **only report findings — never edit files**.

**Cursor Reviewer (if `cursor_available`):**

Run Cursor **first** in the parallel message (it takes the longest):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$LR_TMPDIR/cursor-output-slice-N.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Walk five focus areas: (1) code-quality: bugs, logic errors, dead code, duplication, missing error handling. (2) correctness: off-by-one, nil handling, type mismatches, races, error paths. (3) risk-integration: broken contracts, thread safety, deployment risks, CI gaps. (4) architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area using EXACTLY one of these labels: code-quality / correctness / risk-integration / architecture / security. Return numbered findings with focus-area tag, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor fallback** (if `cursor_available` is false): Launch a Claude Code Reviewer subagent (subagent_type: `code-reviewer`) via the Agent tool instead. Use the unified Code Reviewer checklist. Bind `{FILE_LIST}` to the **current sub-slice** file list when sub-slicing; otherwise use the full slice file list. Drop the `"Work at your maximum reasoning effort"` suffix (Claude uses session-default effort).

**Codex Reviewer (if `codex_available`):**

Run Codex **second** in the parallel message (after Cursor):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$LR_TMPDIR/codex-output-slice-N.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$LR_TMPDIR/codex-output-slice-N.txt" \
    "Review EXISTING code (not a diff — do NOT run git diff) in this project. The file list is in $LR_TMPDIR/slice-N-files.txt — read it, then read and review each listed file. Also inspect corresponding tests and callers for context. Walk five focus areas: (1) code-quality: bugs, logic, reuse, tests, backward compat, style. (2) risk-integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area using EXACTLY one of these labels: code-quality / correctness / risk-integration / architecture / security. Return numbered findings with focus-area tag, file:line, issue, and specific fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex fallback** (if `codex_available` is false): Launch **1 Claude Code Reviewer subagent** via the Agent tool (`subagent_type: code-reviewer`) with the same slice-review context. Bind `{FILE_LIST}` to the **current sub-slice** file list when sub-slicing (>50 files per slice), matching the always-on Claude lane's sub-slicing rule; otherwise use the full slice file list. Reserve `slice-N-files.txt` (the full slice) for actual external reviewers. Attribute as `Code`.

**Claude Code Reviewer subagent (1 reviewer, always-on — launched last in the same parallel message, finishes fastest):**

Invoke `subagent_type: code-reviewer` using the unified checklist from `skills/shared/reviewer-templates.md`. The `code-reviewer` archetype walks five focus areas: code quality, risk/integration, correctness, architecture, and security. Prompt body:

> Review EXISTING code for this project. Files: {FILE_LIST}. Read each file. Walk the unified 5-focus-area checklist (code quality, risk/integration, correctness, architecture, security). Tag each finding with its focus area. Quality gate: for each finding, verify the proposed fix is justified by a concrete need and proportionate to the issue. Return numbered findings: file:line, issue, specific fix. If none: "No issues found." Do NOT edit files.

**Collecting External Reviewer Results:**

Build the argument list from only the externals that were actually launched:

```
COLLECT_ARGS=()
[[ "$cursor_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/cursor-output-slice-N.txt")
[[ "$codex_available" == true ]] && COLLECT_ARGS+=("$LR_TMPDIR/codex-output-slice-N.txt")
```

**Zero-externals branch**: If BOTH Cursor and Codex are unavailable for this slice (`COLLECT_ARGS` is empty — the 3 lanes are the always-on Claude lane plus 2 Claude fallback lanes), **skip `collect-reviewer-results.sh` entirely** and **skip all external negotiation** below. Merge the 3 Claude findings and proceed to Step 3d.

Otherwise, invoke the collection script with only the launched paths:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 "${COLLECT_ARGS[@]}"
```

Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`: **immediately launch the matching single Claude Code Reviewer subagent fallback** for the current slice before proceeding to Step 3d (so this slice still has 3 lanes), then **flip that reviewer's availability flag to false** for all remaining slices (prevents repeated failures). Also append a detailed warning to `$LR_TMPDIR/warnings.md`.

### 3d — Collect, negotiate, deduplicate, and classify findings

**After ALL reviewers return** (the always-on Claude Code Reviewer subagent lane AND any launched external reviewers or their runtime-fallback Claude replacements), proceed:

**1. Collect** all findings from the Claude Code Reviewer subagent lane and validated external reviewer output (and any runtime-fallback Claude findings).

**2. Negotiate** with external reviewers (if they produced findings):

Follow the **Negotiation Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`, using `$LR_TMPDIR` as the tmpdir, with `max_rounds=1`. Use `codex-negotiation-prompt.txt` / `codex-negotiation-output.txt` for the single Codex negotiation track and `cursor-negotiation-prompt.txt` / `cursor-negotiation-output.txt` for the Cursor negotiation track. Run both negotiations in parallel when both externals produced findings. Accept findings unless factually incorrect or contradicting CLAUDE.md.

Note: "accepted" in the negotiation sense means the finding is valid — it may still be dropped at Step 3d's FILE gate below.

**3. Deduplicate** — merge findings from all reviewers (if two reviewers flag the same issue, keep the more specific suggestion).

**4. Classify each finding** (FILE gate with security-focus exception):

**→ FILE** (append to `$LR_TMPDIR/findings-accumulated.md` for batched `/issue` filing) if ALL of:
- Has a specific, actionable concern (not vague).
- Cites a concrete location (file, or file:line, or module).
- Focus area is NOT `security`.

**→ HOLD LOCAL** (append to `$LR_TMPDIR/security-findings.md`, do NOT auto-file) if:
- Focus area is `security`. Per SECURITY.md, security vulnerabilities must not be opened as public GitHub issues — operator handles disclosure.

**→ DROP** (append one line to `$LR_TMPDIR/warnings.md` for visibility; do NOT file) if ANY of:
- Purely cosmetic nit (formatting, subjective naming) with no concrete fix impact.
- Vague concern without a specific location or repro signal.
- Requires coordination with external systems or teams (not actionable as a code-level issue).

Print the classification: `📋 Slice N: X findings (Y to file, Z held local, W dropped)`

### 3e — Zero findings

If all reviewers found nothing: `✅ Slice N: <name> — Clean (<elapsed>)`. Continue to next slice.

### 3f — Accumulate findings and flush batch

For each classified finding in this slice:
- **FILE**: append one entry to `$LR_TMPDIR/findings-accumulated.md` in this generic format (consumed by `/issue`'s `parse-input.sh` generic-format fallback):

  ```markdown
  ### <terse title, ≤ 80 chars, no leading `#` characters>

  **Slice**: <slice name>
  **File**: <path:line or path>
  **Reviewer**: <Code | Cursor | Codex>
  **Focus area**: <code-quality | correctness | risk-integration | architecture>

  **Problem**: <what's wrong, concrete>

  **Suggested fix**: <actionable fix>
  ```

  Body must be non-empty. If the reviewer's problem or fix text contains a `###`-prefixed line at line-start (i.e., three hashes plus a space), normalize it (replace with `####` or prepend two spaces) so `parse-input.sh` does not split the finding into multiple items.

- **HOLD LOCAL**: append to `$LR_TMPDIR/security-findings.md` using the same structured body but omit the `###`-prefixed heading (or use `####`) so the file is never fed to `/issue`.
- **DROP**: append one line to `$LR_TMPDIR/warnings.md`: `- Slice <name>: dropped nit — <title> (<reviewer>)`.

**Flush condition**: invoke `/issue --input-file` when **any** of these are true:
- 3 slices worth of FILE findings have accumulated.
- This is the last slice.
- Accumulated FILE findings reference more than 10 distinct files (keeps each batch's Phase 2 dedup window under `/issue`'s 30-candidate cap).

**When flushing — invoke `/issue`:**

If `$LR_TMPDIR/findings-accumulated.md` contains zero `###`-prefixed headings (all slices were clean or all findings were held/dropped), skip the `/issue` invocation entirely.

Otherwise, invoke the `/issue` skill via the Skill tool with:

```
--input-file $LR_TMPDIR/findings-accumulated.md --label loop-review
```

Do NOT pass `--debug`, `--auto`, or `--merge` — `/issue` is a non-interactive skill and none of those flags apply. Do NOT forward `--title-prefix` — the `loop-review` label is the discovery mechanism and preserves the 80-char title budget.

**Per-item retention on partial failure.** After `/issue` returns, parse its stdout for any line matching `^(ISSUES?_[A-Z0-9_]+)=(.*)$`. The input-file order is 1-indexed and stable: finding i in `findings-accumulated.md` (the i-th `###`-prefixed heading) corresponds to `ITEM_<i>_*` on `/issue`'s stdout. Rebuild the accumulator per-item:

- **Resolved** (remove from accumulator): any ITEM_<i>_* output with `ISSUE_<i>_NUMBER=<N>`, `ISSUE_<i>_DRY_RUN=true`, or `ISSUE_<i>_DUPLICATE=true`.
- **Retain in accumulator** (so the next flush retries it): `ISSUE_<i>_FAILED=true`, or no ITEM_<i>_* line present at all.
- **Whole-batch failure** (no machine lines on stdout, or `/issue` exited non-zero without emitting them): retain the entire accumulator unchanged, log a warning to `$LR_TMPDIR/warnings.md`, and proceed to the next slice.

Update counters using `/issue`'s aggregate machine lines: bump `issue-count.txt` by `ISSUES_CREATED`, `issue-dedup-count.txt` by `ISSUES_DEDUPLICATED`, `issue-failed-count.txt` by `ISSUES_FAILED`.

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

Counter sources: `X`/`Y`/`Z` from the `$LR_TMPDIR/issue-count.txt` / `issue-dedup-count.txt` / `issue-failed-count.txt` files updated after each flush (Step 3f's "Update counters" instruction). `W` is derived at summary time by counting `####` HOLD-LOCAL headings in `$LR_TMPDIR/security-findings.md`, and `V` by counting lines in `$LR_TMPDIR/warnings.md` that start with the per-drop format `- Slice <name>:` (the format written by Step 3f for DROPPED nits). Per-slice totals are accumulated as the slice loop runs.

If `$LR_TMPDIR/security-findings.md` is non-empty (use `[ -s "$LR_TMPDIR/security-findings.md" ]` via a Bash tool call to decide — do NOT gate on the mental counter `W` above, which is only a display value), print the **full verbatim contents** of the file inline in the summary output (the session tmpdir is removed by Step 5, so this is the only durable copy surfaced to the operator). Wrap it under a clearly-labeled block:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security-tagged findings (held locally per SECURITY.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
<full contents of $LR_TMPDIR/security-findings.md>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then print: `**⚠ Handle these findings per SECURITY.md's vulnerability-disclosure procedure. They are NOT filed as public GitHub issues. Session tmpdir is removed by Step 5 — preserve the block above if further triage is needed.**`

**Repeat any external reviewer warnings** accumulated in `$LR_TMPDIR/warnings.md` so they are visible at the end. For example:
- `**⚠ Codex not available: <reason>**`
- `**⚠ Cursor review timed out on slice 3**`
- `**⚠ /issue: label 'loop-review' not found, dropping**` — indicates the label must be pre-created in the target repo.

## Step 5 — Cleanup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$LR_TMPDIR"
```
