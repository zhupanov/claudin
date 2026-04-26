---
name: review
description: "Use when reviewing code changes (current branch diff, or a verbal slice of the repo) with a 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Slice mode supports file-batch review and inline /issue filing for /loop-review."
argument-hint: "[--debug] [--session-env <path>] [--slice <text> | --slice-file <path>] [--create-issues [<slice-text>]] [--label <label>] [--security-output <path>]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, Skill
---

# Code Review Skill

Review code changes (default: current branch diff vs `main`; slice mode: a verbal description of a code slice) using a unified 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor), then implement all accepted suggestions (diff mode) OR file accepted findings as GitHub issues (slice mode + `--create-issues`).

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Flags**: Parse flags from `$ARGUMENTS`. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, the remainder (if any) is unused, EXCEPT when `--create-issues` is set and neither `--slice` nor `--slice-file` is present — in that case the remainder (joined as a single string) is treated as the slice description (equivalent to `--slice <remainder>`), activating slice mode. See `--create-issues` below. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) including reviewer health state (`CODEX_HEALTHY`, `CURSOR_HEALTHY`). If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full health probe at Step 0).
- `--step-prefix <prefix>`: Encodes both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for the full encoding spec. Examples: `"5.::code review"` (numeric `5.`, path `code review`), `"5."` (numeric only, backward compat). Default: empty (standalone numbering). Internal orchestration flag.
- `--slice <text>`: Set `SLICE_TEXT` to the given verbal description (e.g., `--slice "implementation of /research skill"`). Mutually exclusive with `--slice-file`. Activates **slice mode** (see "Slice Mode" section below). Used for human-invoked slice reviews where the description is short.
- `--slice-file <path>`: Set `SLICE_FILE` to the given path; the verbal description is read from that file (single-line file). Mutually exclusive with `--slice`. Activates **slice mode**. Used for driver-invoked slice reviews (e.g., from `/loop-review`'s `driver.sh`) where file-based handoff bypasses argv shell-quoting hazards on verbal descriptions containing quotes, parens, ampersands, etc.
- `--create-issues`: Set `CREATE_ISSUES=true`. After voting completes, file every accepted finding (in-scope-accepted AND OOS-accepted, 2+ YES) as a GitHub issue via `/issue --input-file --label <forwarded-label>`. **Requires slice mode.** Slice mode may be activated three ways: (a) `--slice <text>`, (b) `--slice-file <path>`, or (c) by passing the slice description as trailing positional text after `--create-issues` (equivalent to `--slice <text>`). If none of these are provided (no slice flag AND no positional remainder), print `**⚠ --create-issues requires a slice description (--slice <text>, --slice-file <path>, or trailing positional text). Aborting.**` and exit. Security-tagged findings are written to `--security-output` and never auto-filed (per SECURITY.md).
- `--label <label>`: Set `ISSUE_LABEL` to the given label. Forwarded to `/issue` when `--create-issues` is set. Default: empty (no label).
- `--security-output <path>`: Set `SECURITY_OUTPUT_PATH` to the given path. In slice mode, accepted security-tagged findings are written verbatim to this file before `/review` exits. Default: `$REVIEW_TMPDIR/security-findings.md` (printed to terminal verbatim before tmpdir cleanup if `--security-output` is unset).

## Mutual exclusion + slice-mode activation

- `--slice <text>` and `--slice-file <path>` are mutually exclusive. If both are set, print `**⚠ --slice and --slice-file are mutually exclusive. Aborting.**` and exit.
- If positional slice text is present (trailing remainder after `--create-issues`, per `--create-issues` above) AND either `--slice` or `--slice-file` is also set, print `**⚠ Positional slice text cannot be combined with --slice or --slice-file. Aborting.**` and exit.
- **Slice mode** is active when `--slice` is set, `--slice-file` is set, OR positional slice text is present (the third form is gated on `--create-issues`, per the Flags section above). In slice mode, Step 1 replaces `gather-branch-context.sh` with a slice-resolve step (see Step 1 below), Step 2 reviewer prompts use slice-mode bodies, Step 3 skips the implement-fixes path, and Step 4 emits a `### slice-result` KV footer.
- **Diff mode** is active when neither slice flag is set. Diff mode is the default; behavior in diff mode is unchanged from the pre-slice-mode `/review`.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is and which parent steps they are inside. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `> **🔶 2: launch reviewers**` (standalone) or `> **🔶 5.2: code review | launch reviewers**` (nested from `/implement`)
- Print a **completion line** only when it carries informational payload. Pure "step complete" announcements without payload are not needed.
- When `STEP_NUM_PREFIX` is non-empty, prepend it to step numbers. When `STEP_PATH_PREFIX` is non-empty, prepend it to breadcrumb paths. **This rule overrides the literal step numbers and names in `Print:` directives and examples throughout this file.** Examples shown below assume standalone mode; when nested, prepend the parent context.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | gather context |
| 2 | launch reviewers |
| 3 | review cycle |
| 4 | final summary |
| 5 | cleanup |

### Verbosity Control

**When `debug_mode=false` (default):**

- Use empty string for the `description` parameter on all Bash tool calls.
- Use terse 3-5 word descriptions for Agent tool calls.
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (voting tallies, scoreboards, round summaries, findings lists, final summary), and the compact reviewer status table (see below).

**Compact reviewer status table**: After launching all reviewers (Step 2), maintain a mental tracker of each reviewer's status. Print a compact table after EACH status change:

```
📊 Reviewers: | Code: ✅ 2m31s | Codex: ⏳ | Cursor: ✅ 4m12s |
```

Icons: ✅ done (with elapsed time since launch), ⏳ pending/in-progress, ❌ failed/timeout (with elapsed time since launch), ⊘ skipped (unavailable). See `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for elapsed time and step start formatting rules.

**Status table updates**: (1) Print initial table after launching all reviewers (all ⏳ or ⊘). (2) Update after the Claude subagent returns (adding elapsed time to its ✅). (3) Update after `wait-for-reviewers.sh` returns (all external reviewers resolved).

This replaces individual per-reviewer completion messages in non-debug mode. Do NOT print individual "Reviewer X completed" or "Reviewer X returned N findings" lines.

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls, per-reviewer individual completion messages.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text and BOTH status table and per-reviewer details.

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Slice Mode

When `--slice <text>` or `--slice-file <path>` is set, `/review` operates in **slice mode** instead of the default diff-vs-main mode:

- Step 1 (Gather Context): replaced by a **slice-resolve** step that maps the verbal description to a canonical file list at `$REVIEW_TMPDIR/slice-files.txt` via Glob/Grep/Read. The canonical list anchors OOS classification.
- Step 2 (Launch Reviewers): reviewer prompts instruct the panel to review the canonical file list (existing code, not a diff). Reviewers may explore further via Glob/Grep/Read for context but OOS classification is anchored to the canonical list.
- Step 3 (Review Cycle): runs ONE round only (no recursive re-review loop). After voting, either compose a findings batch and invoke `/issue` via the Skill tool (if `--create-issues`) or just print the findings.
- Step 3e (Implement Fixes): SKIPPED in slice mode — slice mode is read-only review for issue filing, not implement-fixes.
- Step 4 (Final Summary): writes accepted security findings to `--security-output` path; emits a `### slice-result` KV footer for driver consumption.

The slice-mode protocol is consumed by `/loop-review`'s driver (`skills/loop-review/scripts/driver.sh`) which invokes `claude -p /review --slice-file ... --create-issues --label loop-review --security-output ...` per slice and parses the KV footer.

## Step 0 — Session Setup

Run the shared session setup script. This handles temp directory creation, reviewer health probe, and health status file in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-review --skip-preflight --skip-branch-check --skip-slack-check --skip-repo-check --check-reviewers [--caller-env "$SESSION_ENV_PATH"] [--skip-codex-probe] [--skip-cursor-probe] [--write-health "${SESSION_ENV_PATH}.health"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` and `--write-health "${SESSION_ENV_PATH}.health"` if `SESSION_ENV_PATH` is non-empty. If `SESSION_ENV_PATH` provides `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, the script auto-sets the corresponding `--skip-codex-probe` / `--skip-cursor-probe` flag.

If the script exits non-zero, print the error and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `REVIEW_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

Set mental flags `codex_available` and `cursor_available` based on the output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed). Using Claude replacement.**`
- Else: `codex_available=true`
- Same logic for Cursor.

## Step 1 — Gather Context

### Diff mode (no slice flag)

Run the gather script to collect the diff and context:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gather-branch-context.sh --output-dir "$REVIEW_TMPDIR"
```

Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log — you will pass these to each subagent.

### Slice mode (--slice or --slice-file set)

Skip `gather-branch-context.sh`. Resolve the verbal slice description to a canonical file list:

1. **Load the verbal description**: if `--slice` was set, use `SLICE_TEXT` directly. If `--slice-file` was set, read the first non-empty line from the file at `SLICE_FILE` and use it as `SLICE_TEXT` (driver invocations write a one-line file). If neither `--slice` nor `--slice-file` was set (positional slice mode active per the Mutual exclusion section), use the trailing positional remainder of `$ARGUMENTS` captured per the Flags section (joined as a single string) as `SLICE_TEXT`.
2. **Resolve to canonical file list**: use `Glob`, `Grep`, and `Read` tools to identify the files that match the verbal description. The orchestrating agent applies semantic judgment — for "implementation of /research skill", that means `skills/research/SKILL.md` and `skills/research/references/*.md` and any sibling scripts; for "all hook scripts under hooks/", that means `hooks/*.sh` and `hooks/hooks.json`; for "complete contents of foo library", that means every file under `foo/`.
3. **Write to `$REVIEW_TMPDIR/slice-files.txt`**: one file path (repo-relative) per line. This file is the **canonical anchor for OOS classification** — reviewers MUST treat this as the authoritative scope for the slice (per dialectic resolution DECISION_1, voted 3-0).
4. If the resolved file list is empty, print `**⚠ Slice resolved to zero files. Nothing to review. Exiting.**`, emit a `### slice-result` footer with `PARSE_STATUS=ok ISSUES_CREATED=0 ISSUES_DEDUPLICATED=0 ISSUES_FAILED=0 SECURITY_FINDINGS_HELD=0`, and proceed to Step 5 (cleanup).

Set `DIFF_FILE` to empty (no diff in slice mode). Set `FILE_LIST_FILE` to `$REVIEW_TMPDIR/slice-files.txt`. Set `COMMIT_LOG_FILE` to empty.

## Step 2 — Launch Review Subagents in Parallel

Launch **all 3 reviewers** in a **single message**: Cursor and Codex via `Bash` tool (background), plus 1 Claude Code Reviewer subagent via the `Agent` tool (subagent_type: `code-reviewer`). When an external tool is unavailable, launch a Claude Code Reviewer fallback subagent instead so the total reviewer count always remains 3. **Spawn order matters for parallelism** — launch the slowest reviewer first: Cursor (slowest), then Codex, then the Claude subagent (fastest). Each reviewer must **only report findings** — never edit files.

The reviewer prompts differ between diff mode and slice mode. Use the appropriate Bash block below based on which mode is active.

### Diff mode reviewers

#### Cursor Reviewer — diff mode (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the changes itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$REVIEW_TMPDIR/cursor-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level.")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor fallback** (if `cursor_available` is false): Launch a Claude Code Reviewer subagent via the Agent tool (subagent_type: `code-reviewer`) with the same code-review context.

#### Codex Reviewer — diff mode (if `codex_available`)

Run Codex **second** in the parallel message (after Cursor). Codex has full repo access and will examine the changes itself.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$REVIEW_TMPDIR/codex-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$REVIEW_TMPDIR/codex-output.txt" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex fallback** (if `codex_available` is false): Launch a Claude Code Reviewer subagent via the Agent tool (subagent_type: `code-reviewer`).

### Slice mode reviewers

In slice mode, reviewer prompts are tailored to "review existing code in the canonical file list" rather than "review changes vs main". The verbal slice description is also passed as semantic context. The canonical file list at `$REVIEW_TMPDIR/slice-files.txt` is the OOS classification anchor.

#### Cursor Reviewer — slice mode (if `cursor_available`)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$REVIEW_TMPDIR/cursor-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "Review existing code in the slice described as: '${SLICE_TEXT}'. The canonical file list for this slice is at $REVIEW_TMPDIR/slice-files.txt — read that file first to see exactly which files are in scope. Read each listed file in full. You may also explore via Glob/Grep/Read for additional context, but in-scope vs out-of-scope (OOS) classification MUST be anchored to the canonical file list — findings about files NOT in slice-files.txt are OOS, even if they look related. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, file:line, issue, and suggested fix. Mark any finding about a file NOT in slice-files.txt as OOS. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level.")"
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call. Same Cursor fallback as diff mode.

#### Codex Reviewer — slice mode (if `codex_available`)

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$REVIEW_TMPDIR/codex-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
    --output-last-message "$REVIEW_TMPDIR/codex-output.txt" \
    "Review existing code in the slice described as: '${SLICE_TEXT}'. The canonical file list for this slice is at $REVIEW_TMPDIR/slice-files.txt — read that file first to see exactly which files are in scope. Read each listed file in full. You may also explore via Glob/Grep/Read for additional context, but in-scope vs out-of-scope (OOS) classification MUST be anchored to the canonical file list — findings about files NOT in slice-files.txt are OOS, even if they look related. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, file:line, issue, and suggested fix. Mark any finding about a file NOT in slice-files.txt as OOS. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1860000`. Same Codex fallback as diff mode.

### Claude Code Reviewer Subagent (1 reviewer, both modes)

Launch the Claude subagent **last** in the same message (it finishes fastest).

Use the Code Reviewer archetype from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md`. The variables differ slightly between modes:

**Diff mode**:
- **`{REVIEW_TARGET}`** = `"code changes"`
- **`{CONTEXT_BLOCK}`**: includes `<reviewer_commits>`, `<reviewer_file_list>`, `<reviewer_diff>` blocks containing `COMMIT_LOG`, `FILE_LIST`, `DIFF` from Step 1.
- **`{OUTPUT_INSTRUCTION}`** = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix"`

**Slice mode**:
- **`{REVIEW_TARGET}`** = `"existing code in slice: " + SLICE_TEXT`
- **`{CONTEXT_BLOCK}`**: includes a `<reviewer_slice_description>` block (verbal description) and a `<reviewer_canonical_file_list>` block (contents of `$REVIEW_TMPDIR/slice-files.txt`). Instruct the reviewer to read each file in the canonical list, mark any finding about a file NOT in the canonical list as OOS, and walk the same five focus areas.
- **`{OUTPUT_INSTRUCTION}`** = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix"`. Reviewer must produce dual-list output (In-Scope + OOS) per `reviewer-templates.md`.

Invoke via Agent tool with subagent_type: `code-reviewer`. Any fallback Claude launches use the same subagent.

Append the following competition context to each reviewer's prompt (Claude subagent and external reviewers, both modes):

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Claude Code Reviewer subagent, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Out-of-scope observations use **asymmetric scoring** — accepted OOS items (2+ YES) earn +1 point and are filed as GitHub issues; all other OOS outcomes (including unanimous rejection) score 0.

### Collecting External Reviewer Results

External reviewer output collection, validation, and retry are handled by the shared collection script — see the **Collecting External Reviewer Results** section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`. The explicit `collect-reviewer-results.sh` invocation is in Step 3a below.

## Step 3 — Collect, Deduplicate, and Implement (Recursive Loop in diff mode; ONE round in slice mode)

**MANDATORY — READ ENTIRE FILE** before executing any sub-step of Step 3: `${CLAUDE_PLUGIN_ROOT}/skills/review/references/domain-rules.md`. It contains the Settings.json permissions ordering rule and the skill/script genericity rule that the orchestrating agent applies when evaluating findings and reviewing the diff/slice across Step 3 (collect, dedup, voting, fix application). Loaded unconditionally on every Step 3 entry.

**In diff mode**, this step repeats until reviewers find no more issues. Track the current **round number** starting at 1.

**In slice mode**, this step runs ONE round only — slice mode is read-only review for issue filing. After Step 3d's round summary, jump directly to Step 4 (skip Step 3e implement-fixes and Step 3f re-review).

### 3a — Collect

**Process the Claude finding immediately** — do not wait for external reviewers before starting. After the Claude Code Reviewer subagent returns:

1. Collect findings from the Claude Code Reviewer subagent right away. It produces **dual-list output**: "In-Scope Findings" and "Out-of-Scope Observations". Parse both lists.
2. **Then** collect and validate external reviewer outputs using the shared collection script. Only include output paths for reviewers that were actually launched:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 [--write-health "${SESSION_ENV_PATH}.health"] "$REVIEW_TMPDIR/cursor-output.txt" "$REVIEW_TMPDIR/codex-output.txt"
   ```
   Only include `--write-health` if `SESSION_ENV_PATH` is non-empty. Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure. Read valid output files. External reviewers (Codex, Cursor) produce single-list output — treat their entire output as in-scope findings.
3. Merge external reviewer in-scope findings (and any Claude fallback findings when externals were unavailable) into the Claude in-scope findings. Deduplicate in-scope findings and OOS observations separately. If the same issue appears in both lists from different reviewers, merge under the in-scope finding.

OOS observations are only collected in round 1 — rounds 2+ (diff mode only) use a Claude-only reviewer without OOS collection.

### 3b — Check for Zero Findings

If **all reviewers** report no issues (e.g., "No issues found.", "No in-scope issues found.", "NO_ISSUES_FOUND"), the loop is done — skip to **Step 4**.

### 3c — Deduplicate

Merge findings from all reviewers into a single deduplicated list, grouped by file. If two reviewers flag the same issue, keep the more specific suggestion. Assign each deduplicated finding a stable sequential ID (`FINDING_1`, `FINDING_2`, etc. for in-scope; `OOS_1`, `OOS_2`, etc. for OOS) and note which reviewer(s) proposed each.

### 3c.1 — Voting Panel (round 1 only)

**In round 1**: **MANDATORY — READ ENTIRE FILE** `${CLAUDE_PLUGIN_ROOT}/skills/review/references/voting.md` and execute its body — three-voter setup with proportionality guidance, ballot file handling rule (Write tool, not `cat`-heredoc), parallel launch order (Cursor → Codex → Claude subagent), threshold rules + competition scoring per `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`, the zero-accepted-findings short-circuit to **Step 4**, the OOS-accepted-by-vote artifact write to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-review.md` (only when `SESSION_ENV_PATH` is non-empty AND slice mode is OFF — slice mode bypasses this artifact and files directly via /issue at Step 4), and the save-not-accepted-IDs rule used to suppress re-raised findings in rounds 2+ (diff mode only).

**In rounds 2+ (diff mode only)**: Skip voting — accept all Claude-only findings directly, **except** findings that match round-1 rejected findings. **Do NOT load** `${CLAUDE_PLUGIN_ROOT}/skills/review/references/voting.md` in rounds 2+ — the body is round-1-only and would waste tokens. Same `Do NOT load` guidance applies on the Step 3b zero-findings short-circuit.

### 3d — Print Round Summary

Print to the user:
- `## Review Round {N}` header
- Bullet list of **accepted** findings with reviewer attribution (Code / Codex / Cursor)
- If round 1: vote counts per finding, accepted OOS items, and any findings not accepted by vote
- Total count of accepted findings for this round

### 3e — Implement Fixes

**SKIPPED in slice mode.** Slice mode is read-only — proceed directly to Step 4 after Step 3d.

**In diff mode**, for each **accepted in-scope** finding (`FINDING_*` items only — exclude `OOS_*` items, which are processed separately for issue filing by `/implement`):

1. Apply the suggested fix by editing the relevant file.
2. If the fix involves creating new tests, write them.
3. If the fix involves CI workflow changes, edit the workflow YAML.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill (Step 3f or Step 4) — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

After all fixes are applied, invoke `/relevant-checks` via the Skill tool to run validation checks. If checks fail, diagnose and fix the issue, then re-invoke `/relevant-checks` to confirm.

### 3f — Re-review

**SKIPPED in slice mode.** Proceed to Step 4.

**In diff mode**, increment the round number. Go back to **Step 1** (gather the updated diff) and **Step 2** (launch reviewers again).

**Round 2+ optimization**: Only launch the **1 Claude Code Reviewer subagent** — skip Codex and Cursor.

### 3g — Safety Limit

**Diff mode only.** If the loop has run **5 rounds** without converging, stop and print a warning, then proceed to Step 4.

## Step 4 — Final Summary (and slice-mode /issue filing)

### 4a — Print summary (both modes)

Print a final summary:
- Total number of review rounds (always 1 in slice mode)
- Findings per round (with per-reviewer breakdown: Code / Codex / Cursor)
- Voting summary (round 1): total findings voted on, accepted (2+ YES), neutral (1 YES), exonerated (0 YES + 1+ EXONERATE), rejected (0 YES + 0 EXONERATE)
- Reviewer Competition Scoreboard (from round 1 voting)
- Total fixes applied across all rounds (diff mode only)
- Build/test status (pass/fail)
- **External reviewer warnings** (repeat any preflight or runtime warnings from Codex/Cursor here so they are visible at the end)

### 4b — Slice-mode /issue filing (only when slice mode AND --create-issues)

If slice mode is OFF or `--create-issues` is unset, skip this sub-step.

Compose a findings batch markdown at `$REVIEW_TMPDIR/findings-batch.md`. Include:
- For each in-scope-accepted finding (2+ YES): a generic `### <terse title>` block with `**Slice**`, `**File**`, `**Reviewer**`, `**Focus area**`, `**Problem**`, `**Suggested fix**` body.
- For each OOS-accepted finding (2+ YES, NOT focus-area=security): an OOS schema block per `/issue`'s OOS-format parser:
  ```markdown
  ### OOS_N: <short title>
  - **Description**: <full description>
  - **Reviewer**: <attribution>
  - **Vote tally**: <YES/NO/EXONERATE counts>
  - **Phase**: review
  ```
- **Exclude** any finding tagged `security` — those are handled by Step 4c.

If the batch is empty (zero accepted findings, or all accepted findings were security-tagged), skip the `/issue` invocation.

Otherwise, invoke `/issue` via the Skill tool:

> **Continue after child returns.** When `/issue` returns, parse its stdout machine lines for `ISSUES_CREATED=`, `ISSUES_DEDUPLICATED=`, `ISSUES_FAILED=` aggregates and continue to Step 4c — do NOT end the turn or write a summary. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

```
/issue --input-file $REVIEW_TMPDIR/findings-batch.md [--label $ISSUE_LABEL]
```

Only forward `--label $ISSUE_LABEL` if `ISSUE_LABEL` is non-empty. Do NOT forward `--debug`, `--auto`, or `--merge` — `/issue` does not support those.

Parse `/issue`'s stdout for the aggregate counters: `ISSUES_CREATED=<n>`, `ISSUES_DEDUPLICATED=<n>`, `ISSUES_FAILED=<n>`. Save these for the KV footer at Step 4d.

### 4c — Write security findings (slice mode only)

If slice mode is ON, collect any accepted security-tagged findings (focus-area=security; both in-scope-accepted and OOS-accepted with 2+ YES). Write them verbatim to:
- `--security-output` path if set (provided by `/loop-review`'s driver as `$LOOP_TMPDIR/security-findings-slice-${N}.md`).
- `$REVIEW_TMPDIR/security-findings.md` otherwise (default; printed verbatim to terminal at end of run before tmpdir cleanup).

Format each entry:
```markdown
### <focus-area=security> — <short title>
- **File**: <path:line>
- **Reviewer(s)**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE>
- **Concern**: <full description>
- **Suggested fix**: <full text>
```

Set `SECURITY_FINDINGS_HELD` = number of entries written.

If `--security-output` is unset (standalone /review run, not from driver), print the file's contents verbatim to terminal under a clearly-labeled block:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security-tagged findings (held locally per SECURITY.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
<contents of security-findings.md>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then print: `**⚠ Handle these findings per SECURITY.md's vulnerability-disclosure procedure. They are NOT filed as public GitHub issues.**`

### 4d — Slice-mode KV footer (slice mode only)

Print the `### slice-result` KV footer immediately before exiting Step 4. The driver in `/loop-review` parses this footer.

```
### slice-result
ISSUES_CREATED=<n>
ISSUES_DEDUPLICATED=<n>
ISSUES_FAILED=<n>
SECURITY_FINDINGS_HELD=<n>
PARSE_STATUS=ok
```

Substitute `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED` from Step 4b (or zero each if Step 4b was skipped — i.e., the findings batch was empty). Substitute `SECURITY_FINDINGS_HELD` from Step 4c independently (zero only if Step 4c found no security findings — Step 4c always runs in slice mode regardless of whether Step 4b ran). `PARSE_STATUS=ok` always (any error path emits a different `PARSE_STATUS` value or aborts before reaching here).

## Step 5 — Cleanup

### 5a — Update Health Status File

Health status file updates are handled automatically by `collect-reviewer-results.sh --write-health` during reviewer collection (Step 3a). No additional cleanup-time write is needed unless a reviewer was marked unhealthy outside of a `collect-reviewer-results.sh` call. If `SESSION_ENV_PATH` is non-empty and any such untracked health change occurred, re-write the health status file at `${SESSION_ENV_PATH}.health` with the final health state before cleanup.

### 5b — Remove Temp Directory

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$REVIEW_TMPDIR"
```

In slice mode with `--security-output` set, the security findings file lives at the driver-provided path under `$LOOP_TMPDIR` (NOT `$REVIEW_TMPDIR`), so cleanup of `$REVIEW_TMPDIR` does not destroy it. The driver retains `$LOOP_TMPDIR` per its EXIT trap rules.
