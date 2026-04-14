---
name: review
description: "Use when reviewing current branch changes with specialized subagents."
argument-hint: "[--debug] [--session-env <path>]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, Skill
---

# Code Review Skill

Review all changes on the current branch (vs `main`) using two specialized Claude subagent reviewers plus two Codex and one Cursor reviewer, then implement all accepted suggestions.

**Flags**: Parse flags from `$ARGUMENTS`. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, the remainder (if any) is unused — `/review` takes no positional arguments. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--debug`: Set a mental flag `debug_mode=true`. Controls output verbosity — see Verbosity Control below. Default: `debug_mode=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) including reviewer health state (`CODEX_HEALTHY`, `CURSOR_HEALTHY`). If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full health probe at Step 0b).
- `--step-prefix <prefix>`: Encodes both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for the full encoding spec. Examples: `"5.::code review"` (numeric `5.`, path `code review`), `"5."` (numeric only, backward compat). Parse into `STEP_NUM_PREFIX` (before `::`) and `STEP_PATH_PREFIX` (after `::`, or empty if `::` absent). Default: empty (standalone numbering). This is an internal orchestration flag used when `/review` is invoked from `/implement`.

## Progress Reporting

**Every step MUST print clearly visible breadcrumb status lines** so the user can instantly see where execution is and which parent steps they are inside. Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

- Print a **start line** when entering a step: e.g., `▸ 2: launch reviewers` (standalone) or `▸ 5.2: code review | launch reviewers` (nested from `/implement`)
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
- Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `▸`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (voting tallies, scoreboards, round summaries, findings lists, final summary), and the compact reviewer status table (see below).

**Compact reviewer status table**: After launching all reviewers (Step 2), maintain a mental tracker of each reviewer's status. Print a compact table after EACH status change:

```
📊 Reviewers: | General: ✅ | Deep: ⏳ | Codex-G: ✅ | Codex-D: ❌ | Cursor: ⏳ |
```

Icons: ✅ done, ⏳ pending/in-progress, ❌ failed/timeout, ⊘ skipped (unavailable).

**Timing**: (1) Print initial table after launching all reviewers (all ⏳ or ⊘). (2) Update after each Claude subagent returns. (3) Update after `wait-for-reviewers.sh` returns (all external reviewers resolved).

This replaces individual per-reviewer completion messages in non-debug mode. Do NOT print individual "Reviewer X completed" or "Reviewer X returned N findings" lines.

**Suppressed output (only when `debug_mode=false`):** explanatory prose, script paths, rationale for decisions between tool calls, per-reviewer individual completion messages.

**When `debug_mode=true`:** use descriptive text for `description` on all Bash and Agent tool calls; print full explanatory text and BOTH status table and per-reviewer details.

**Limitation**: Verbosity suppression is prompt-enforced and best-effort.

## Domain-Specific Review Rules

These rules supplement the generic reviewer templates. The orchestrating agent applies them when evaluating findings and reviewing the diff, especially during Step 3c (deduplication).

### Settings.json Permissions Ordering

When changes touch `.claude/settings.json`, verify that the `permissions.allow` array remains in **strict ASCII/Unicode code-point order** (equivalent to `LC_ALL=C sort`, Go's `sort.Strings`, or Python's `sorted()`). Entries must be sorted as raw strings without preprocessing or normalization. This means special characters sort by their code-point value (e.g., `$` < `.` < `/` < uppercase letters < `[` < lowercase letters < `~`).

### Skill and Script Genericity

When changes touch files under `scripts/` or `skills/shared/`, verify the changes do not introduce repo-specific content: no repo-specific paths (e.g., `server/`, `cli/`, `myservice`), cluster names (e.g., `prod-1`, `staging-2`), service-specific environment variable names, or hardcoded project references that would break when the file is used in a different repository.

- **Generic directories**: `scripts/`, `skills/shared/` — changes to files here must not introduce repo-specific references.
- **Repo-specific directories**: individual skill-specific script directories (e.g., `skills/implement/scripts/`, `skills/loop-review/scripts/`), and the private `.claude/skills/relevant-checks/` skill — files here are repo-specific by design and exempt from this rule.

## Step 0 — Session Setup

Run the shared session setup script. This handles temp directory creation, reviewer health probe, and health status file in a single call:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-review --skip-preflight --skip-branch-check --skip-slack-check --skip-repo-check --check-reviewers [--caller-env "$SESSION_ENV_PATH"] [--skip-codex-probe] [--skip-cursor-probe] [--write-health "${SESSION_ENV_PATH}.health"]
```

Only include `--caller-env "$SESSION_ENV_PATH"` and `--write-health "${SESSION_ENV_PATH}.health"` if `SESSION_ENV_PATH` is non-empty. If `SESSION_ENV_PATH` provides `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, the script auto-sets the corresponding `--skip-codex-probe` / `--skip-cursor-probe` flag — you do not need to pass these explicitly when using `--caller-env`.

If the script exits non-zero, print the error and abort.

Parse the output for `SESSION_TMPDIR`, `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`. Set `REVIEW_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

Set mental flags `codex_available` and `cursor_available` based on the output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed). Using Claude replacement.**`
- Else: `codex_available=true`
- Same logic for Cursor.

## Step 1 — Gather Context

Run the gather script to collect the diff and context:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gather-branch-context.sh --output-dir "$REVIEW_TMPDIR"
```

Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log — you will pass these to each subagent.

## Step 2 — Launch Review Subagents in Parallel

Launch **all 5 reviewers** in a **single message**: Cursor and two Codex instances via `Bash` tool (background), plus two Claude subagents via the `Agent` tool. When external tools are unavailable, launch Claude replacement subagents instead so the total reviewer count always remains 5. **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then both Codex instances, then Claude subagents (fastest). Each reviewer receives the full diff text and file list, plus its specialized review instructions. Each must **only report findings** — never edit files.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the changes itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "$REVIEW_TMPDIR/cursor-output.txt" --timeout 1800 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor) --workspace "$PWD" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Combine 4 review perspectives: (1) General: bugs, logic, quality, tests, backward compat, style. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Cursor replacement** (if `cursor_available` is false): Launch a Claude subagent (Risk/Integration) via the Agent tool instead. This replacement ensures the total reviewer count remains 5 regardless of external tool availability.

Prompt: `"You are a Risk/Integration reviewer examining code changes. <include {CONTEXT_BLOCK} and competition notice>. Combine 4 review perspectives: (1) General: bugs, logic, quality, tests, backward compat, style. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with file:line, issue, suggested fix) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT edit any files."`

### Codex Reviewers (if `codex_available`) — 2 instances

Run both Codex instances **second** in the parallel message. Each Codex instance has full repo access and will examine the changes itself.

Invoke both Codex instances via the shared monitored wrapper script:

**Codex-General** (general code quality and risk/integration):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$REVIEW_TMPDIR/codex-general-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$REVIEW_TMPDIR/codex-general-output.txt" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Focus on general code quality and risk/integration: bugs, logic, quality, tests, backward compat, style, breaking changes, deployment risks, regressions, CI constraints. Return numbered findings with file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex-Deep-Analysis** (deep correctness and architecture):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "$REVIEW_TMPDIR/codex-deep-output.txt" --timeout 1800 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex) \
    --output-last-message "$REVIEW_TMPDIR/codex-deep-output.txt" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Focus on deep correctness and architecture: logic errors, off-by-one, nil handling, type mismatches, races, error paths, separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 1860000` on the Bash tool call.

**Codex replacements** (if `codex_available` is false): Launch 2 Claude subagents to replace the 2 Codex instances. These replacements ensure the total reviewer count remains 5 regardless of external tool availability.

**Claude (Codex-General replacement)**: Launch via Agent tool with prompt: `"You are a code quality and risk/integration reviewer examining code changes. <same {CONTEXT_BLOCK} as Claude subagents>. Focus on general code quality and risk/integration: bugs, logic, quality, tests, backward compat, style, breaking changes, deployment risks, regressions, CI constraints. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with file:line, issue, suggested fix) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT edit any files."`

**Claude (Codex-Deep-Analysis replacement)**: Launch via Agent tool with prompt: `"You are a deep correctness and architecture reviewer examining code changes. <same {CONTEXT_BLOCK} as Claude subagents>. Focus on deep correctness and architecture: logic errors, off-by-one, nil handling, type mismatches, races, error paths, separation of concerns, contract boundaries, invariants, semantic boundaries. Quality gate: for each in-scope finding, verify the proposed change is justified by a concrete need and proportionate to the issue. Return findings in two separate sections: In-Scope Findings (numbered, with file:line, issue, suggested fix) and Out-of-Scope Observations. If no in-scope issues, say 'No in-scope issues found.' Do NOT edit any files."`

### Claude Subagents (2 reviewers)

Launch both Claude subagents **last** in the same message (they finish fastest).

Use the two reviewer archetypes from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md`, filling in the variables for **code review**:

- **`{REVIEW_TARGET}`** = `"code changes"`
- **`{CONTEXT_BLOCK}`**:
  ```
  ## Changes to review
  Commits:
  {COMMIT_LOG}

  Files changed:
  {FILE_LIST}

  Full diff:
  {DIFF}
  ```
- **`{OUTPUT_INSTRUCTION}`** = `"File path and line number(s)"` + `"What the issue is"` + `"Suggested fix (be specific — show corrected code or describe the refactoring)"`

Additionally, append the following competition context to each reviewer's prompt (both Claude subagents and external reviewers):

> **Competition notice**: Your findings will be voted on by a 3-agent panel (General Reviewer, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Concerns that are valid but not actionable in this PR may still be exonerated rather than penalized. Out-of-scope observations (pre-existing issues, items beyond PR scope) can never cost you points — surface them freely.

### Collecting External Reviewer Results

External reviewer output collection, validation, and retry are handled by the shared collection script — see the **Collecting External Reviewer Results** section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`. The explicit `collect-reviewer-results.sh` invocation is in Step 3a below.

## Step 3 — Collect, Deduplicate, and Implement (Recursive Loop)

This step repeats until reviewers find no more issues. Track the current **round number** starting at 1.

### 3a — Collect

**Process Claude findings immediately** — do not wait for external reviewers before starting. After both Claude subagents return:

1. Collect findings from the two Claude subagents right away. Claude subagents produce **dual-list output** (per `reviewer-templates.md`): "In-Scope Findings" and "Out-of-Scope Observations". Parse both lists from each subagent.
2. **Then** collect and validate external reviewer outputs using the shared collection script. Only include output paths for reviewers that were actually launched:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout 1860 [--write-health "${SESSION_ENV_PATH}.health"] "$REVIEW_TMPDIR/cursor-output.txt" "$REVIEW_TMPDIR/codex-general-output.txt" "$REVIEW_TMPDIR/codex-deep-output.txt"
   ```
   Only include `--write-health` if `SESSION_ENV_PATH` is non-empty. Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure. Read valid output files. External reviewers (Codex, Cursor) produce single-list output — treat their entire output as in-scope findings.
4. Merge external reviewer in-scope findings into the Claude in-scope findings. Deduplicate in-scope findings and OOS observations separately (see `voting-protocol.md` OOS section). If the same issue appears in both lists from different reviewers, merge under the in-scope finding.

This way Claude findings are processed during the 5-10 minutes external reviewers take, instead of sitting idle. OOS observations are only collected in round 1 — rounds 2+ use Claude-only reviewers without OOS collection.

### 3b — Check for Zero Findings

If **all reviewers** (2 Claude subagents + 2 Codex instances and Cursor if available) report no issues (e.g., "No issues found.", "No architecture concerns found.", "No concerns found.", "NO_ISSUES_FOUND"), the loop is done — skip to **Step 4**.

### 3c — Deduplicate

Merge findings from all reviewers into a single deduplicated list, grouped by file. If two reviewers flag the same issue, keep the more specific suggestion. Assign each deduplicated finding a stable sequential ID (`FINDING_1`, `FINDING_2`, etc.) and note which reviewer(s) proposed each.

### 3c.1 — Voting Panel (round 1 only)

**In round 1**: Submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section. For code review:

- **Voter 1**: Claude General reviewer subagent — fresh Agent tool invocation with the voting prompt. Instruct: `"You are a very scrupulous senior engineer code reviewer on a voting panel. You will vote YES, NO, or EXONERATE on proposed code changes. Be extremely rigorous — only vote YES for findings that identify genuine bugs, logic errors, security issues, or clearly important improvements. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. Vote NO for trivial style nits, subjective preferences, or speculative concerns. When voting, also consider proportionality: vote EXONERATE (not YES) if the finding's concern is legitimate but the proposed change would introduce more complexity than the issue warrants."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot. If `codex_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly as a "very scrupulous senior engineer code reviewer," including the proportionality guidance.
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot. If `cursor_available` is false, launch a Claude subagent voter instead per the Voting Protocol. Instruct similarly, including the proportionality guidance.

**Ballot file handling**: Use the Write tool (not `cat` with heredoc or Bash) to write the ballot to `$REVIEW_TMPDIR/ballot.txt`. For Codex and Cursor voter prompts, reference the ballot file path (e.g., "Read the ballot from $REVIEW_TMPDIR/ballot.txt") instead of inlining the ballot content. This avoids permission prompts from `cat > file << 'EOF'` or `BALLOT=$(cat file)` patterns.

Launch all available voters **in parallel** (Cursor first, then Codex, then Claude subagent). Wait for external voter sentinels using `wait-for-reviewers.sh` per the Voting Protocol, then parse voter outputs.

**Tally votes**: Apply the threshold rules from the Voting Protocol based on eligible voters per finding (2+ YES with 3 voters, unanimous 2/2 with 2 voters, skip if <2 eligible). Print vote breakdown per finding.

**Competition scoring**: Compute and print the **Reviewer Competition Scoreboard** per the Voting Protocol. Note in the scoreboard that scores apply to round 1 only — round 2+ findings are auto-accepted and do not contribute to scores.

**Zero accepted findings**: If voting rejects all findings, print `**ℹ Voting panel rejected all findings. No changes to implement.**` and skip to **Step 4**.

**Save not-accepted finding IDs**: Record the IDs of findings not accepted by vote in round 1 (whether rejected or exonerated). In rounds 2+, if a Claude-only reviewer re-raises a finding that was not accepted by the round-1 voting panel (same file, same issue), suppress it — do not re-accept a finding the panel already voted down or exonerated.

**In rounds 2+**: Skip voting — accept all Claude-only findings directly, **except** findings that match round-1 rejected findings (same file and substantially similar issue). External reviewer findings are not present in rounds 2+.

### 3d — Print Round Summary

Print to the user:
- `## Review Round {N}` header
- Bullet list of **accepted** findings (after voting in round 1, or all findings in rounds 2+) with reviewer attribution (General / Deep-Analysis / Codex-General / Codex-Deep-Analysis / Cursor)
- If round 1: vote counts per finding and any findings not accepted by vote (rejected or exonerated)
- Total count of accepted findings for this round

### 3e — Implement Fixes

For each **accepted** finding (voted in during round 1, or all findings in rounds 2+):

1. Apply the suggested fix by editing the relevant file.
2. If the fix involves creating new tests, write them.
3. If the fix involves CI workflow changes, edit the workflow YAML.

After all fixes are applied, invoke `/relevant-checks` to run validation checks. If checks fail, diagnose and fix the issue, then re-invoke `/relevant-checks` to confirm the fix.

### 3f — Re-review

Increment the round number. Go back to **Step 1** (gather the updated diff) and **Step 2** (launch reviewers again).

**Round 2+ optimization**: Only launch the **2 Claude subagent reviewers** — skip Codex and Cursor. External reviewers are expensive (5-15 min each) and provide diminishing returns on incremental fix diffs. Claude subagents review the **cumulative diff** (main...HEAD), which includes both the original changes and the fixes just applied.

### 3g — Safety Limit

If the loop has run **5 rounds** without converging (reviewers keep finding issues), stop and print a warning:

```
## Warning: Review loop did not converge after 5 rounds
Remaining findings from the last round are listed above.
Manual review recommended.
```

Then proceed to Step 4.

## Step 4 — Final Summary

Print a final summary:
- Total number of review rounds
- Findings per round (with per-reviewer breakdown: General / Deep-Analysis / Codex-General / Codex-Deep-Analysis / Cursor)
- Voting summary (round 1): total findings voted on, accepted (2+ YES), neutral (1 YES), exonerated (0 YES + 1+ EXONERATE), rejected (0 YES + 0 EXONERATE)
- Reviewer Competition Scoreboard (from round 1 voting)
- Total fixes applied across all rounds
- Build/test status (pass/fail)
- **External reviewer warnings** (repeat any preflight or runtime warnings from Codex/Cursor here so they are visible at the end)

## Step 5 — Cleanup

### 5a — Update Health Status File

Health status file updates are now handled automatically by `collect-reviewer-results.sh --write-health` during reviewer collection (Step 3a). No additional cleanup-time write is needed unless a reviewer was marked unhealthy outside of a `collect-reviewer-results.sh` call. If `SESSION_ENV_PATH` is non-empty and any such untracked health change occurred, re-write the health status file at `${SESSION_ENV_PATH}.health` with the final health state before cleanup.

### 5b — Remove Temp Directory

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$REVIEW_TMPDIR"
```
