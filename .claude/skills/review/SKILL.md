---
name: review
description: Code review current branch changes with specialized subagents
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, Skill
---

# Code Review Skill

Review all changes on the current branch (vs `main`) using four specialized Claude subagent reviewers plus Codex and Cursor reviewers, then implement all accepted suggestions.

## Domain-Specific Review Rules

These rules supplement the generic reviewer templates. The orchestrating agent applies them when evaluating findings and reviewing the diff, especially during Step 3c (deduplication).

### Settings.json Permissions Ordering

When changes touch `.claude/settings.json`, verify that the `permissions.allow` array remains in **strict ASCII/Unicode code-point order** (equivalent to `LC_ALL=C sort`, Go's `sort.Strings`, or Python's `sorted()`). Entries must be sorted as raw strings without preprocessing or normalization. This means special characters sort by their code-point value (e.g., `$` < `.` < `/` < uppercase letters < `[` < lowercase letters < `~`).

### Skill and Script Genericity

When changes touch files under `.claude/scripts/generic/` or `.claude/skills/shared/`, verify the changes do not introduce repo-specific content: no repo-specific paths (e.g., `server/`, `cli/`, `myservice`), cluster names (e.g., `prod-1`, `staging-2`), service-specific environment variable names, or hardcoded project references that would break when the file is used in a different repository.

- **Generic directories**: `.claude/scripts/generic/`, `.claude/skills/shared/` — changes to files here must not introduce repo-specific references.
- **Repo-specific directories**: `.claude/scripts/repo/`, individual skill directories (e.g., `.claude/skills/brand-new/`, `.claude/skills/optimize/`) — files here are repo-specific by design and exempt from this rule.

## Step 0 — Session Setup

### 0a — Create Session Temp Directory

Create a session-scoped temporary directory to avoid collisions with parallel sessions:

```bash
$PWD/.claude/scripts/generic/create-session-tmpdir.sh --prefix claude-review
```

Parse the output for `SESSION_TMPDIR`. Set `REVIEW_TMPDIR` = `SESSION_TMPDIR`. Substitute the actual path in every command below.

### 0b — Quick External Reviewer Check

Read and follow the **Binary Check** section in `.claude/skills/shared/external-reviewers.md`.

## Step 1 — Gather Context

Run the gather script to collect the diff and context:

```bash
$PWD/.claude/scripts/generic/gather-branch-context.sh --output-dir "$REVIEW_TMPDIR"
```

Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log — you will pass these to each subagent.

## Step 2 — Launch Review Subagents in Parallel

Launch **all reviewers** in a **single message**: Cursor and Codex via `Bash` tool (background), plus four Claude subagents via the `Agent` tool. **Spawn order matters for parallelism** — launch the slowest reviewers first: Cursor (slowest), then Codex, then Claude subagents (fastest). Each reviewer receives the full diff text and file list, plus its specialized review instructions. Each must **only report findings** — never edit files.

### Cursor Reviewer (if `cursor_available`)

Run Cursor **first** in the parallel message (it takes the longest). Cursor has full repo access and will examine the changes itself.

Invoke Cursor via the shared monitored wrapper script (with `--capture-stdout` since Cursor writes results to stdout):

```bash
$PWD/.claude/scripts/generic/run-external-reviewer.sh --tool cursor --output "$REVIEW_TMPDIR/cursor-output.txt" --timeout 900 --capture-stdout -- \
  cursor agent -p --force --trust --model gpt-5.4-medium --workspace "$PWD" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Combine 4 review perspectives: (1) General: bugs, logic, quality, tests, backward compat, style. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Codex Reviewer (if `codex_available`)

Run Codex **second** in the parallel message. Codex has full repo access and will examine the changes itself.

Invoke Codex via the shared monitored wrapper script:

```bash
$PWD/.claude/scripts/generic/run-external-reviewer.sh --tool codex --output "$REVIEW_TMPDIR/codex-output.txt" --timeout 900 -- \
  codex exec --full-auto -C "$PWD" \
    --output-last-message "$REVIEW_TMPDIR/codex-output.txt" \
    "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Combine 4 review perspectives: (1) General: bugs, logic, quality, tests, backward compat, style. (2) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (3) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. Return numbered findings with perspective, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files."
```

Use `run_in_background: true` and `timeout: 960000` on the Bash tool call.

### Claude Subagents (4 reviewers)

Launch all four Claude subagents **last** in the same message (they finish fastest).

Use the four reviewer archetypes from `.claude/skills/shared/reviewer-templates.md`, filling in the variables for **code review**:

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

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Generic code reviewer, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Concerns that are valid but not actionable in this PR may still be exonerated rather than penalized. Out-of-scope observations (pre-existing issues, items beyond PR scope) can never cost you points — surface them freely.

### Monitoring External Reviewers

Follow the **Monitoring External Reviewers** and **Validating External Reviewer Output** sections in `.claude/skills/shared/external-reviewers.md`, using `$REVIEW_TMPDIR/codex-output.txt` and `$REVIEW_TMPDIR/cursor-output.txt` as the output files.

**Critical**: Do NOT read `$REVIEW_TMPDIR/cursor-output.txt` until `$REVIEW_TMPDIR/cursor-output.txt.done` exists. Cursor buffers all stdout — the file is empty (0 bytes) until the process exits. The `.done` sentinel file is written by the wrapper script upon completion and contains the exit code.

## Step 3 — Collect, Deduplicate, and Implement (Recursive Loop)

This step repeats until reviewers find no more issues. Track the current **round number** starting at 1.

### 3a — Collect

**Process Claude findings immediately** — do not wait for external reviewers before starting. After all four Claude subagents return:

1. Collect findings from the four Claude subagents right away. Claude subagents produce **dual-list output** (per `reviewer-templates.md`): "In-Scope Findings" and "Out-of-Scope Observations". Parse both lists from each subagent.
2. **Then** poll for external reviewer sentinel files (`$REVIEW_TMPDIR/cursor-output.txt.done` and `$REVIEW_TMPDIR/codex-output.txt.done`, only for reviewers that were actually launched) using the polling procedure in `.claude/skills/shared/external-reviewers.md`.
3. Once sentinel files exist, read each reviewer's exit code, then read and validate the output per the shared procedure. External reviewers (Codex, Cursor) produce single-list output — treat their entire output as in-scope findings.
4. Merge external reviewer in-scope findings into the Claude in-scope findings. Deduplicate in-scope findings and OOS observations separately (see `voting-protocol.md` OOS section). If the same issue appears in both lists from different reviewers, merge under the in-scope finding.

This way Claude findings are processed during the 5-10 minutes external reviewers take, instead of sitting idle. OOS observations are only collected in round 1 — rounds 2+ use Claude-only reviewers without OOS collection.

### 3b — Check for Zero Findings

If **all reviewers** (4 Claude subagents + Codex and Cursor if available) report no issues (e.g., "No issues found.", "No architecture concerns found.", "No concerns found.", "NO_ISSUES_FOUND"), the loop is done — skip to **Step 4**.

### 3c — Deduplicate

Merge findings from all reviewers into a single deduplicated list, grouped by file. If two reviewers flag the same issue, keep the more specific suggestion. Assign each deduplicated finding a stable sequential ID (`FINDING_1`, `FINDING_2`, etc.) and note which reviewer(s) proposed each.

### 3c.1 — Voting Panel (round 1 only)

**In round 1**: Submit both in-scope findings and out-of-scope observations to a 3-agent voting panel per the **Voting Protocol** in `.claude/skills/shared/voting-protocol.md`. Include OOS items on the ballot with `[OUT_OF_SCOPE]` prefix per the protocol's OOS section. For code review:

- **Voter 1**: Claude Generic code reviewer subagent — fresh Agent tool invocation with the voting prompt. Instruct: `"You are a very scrupulous senior engineer code reviewer on a voting panel. You will vote YES, NO, or EXONERATE on proposed code changes. Be extremely rigorous — only vote YES for findings that identify genuine bugs, logic errors, security issues, or clearly important improvements. Vote EXONERATE if the concern is legitimate but not worth implementing in this PR. Vote NO for trivial style nits, subjective preferences, or speculative concerns."`
- **Voter 2**: Codex — via `run-external-reviewer.sh` with the ballot. Instruct similarly as a "very scrupulous senior engineer code reviewer."
- **Voter 3**: Cursor — via `run-external-reviewer.sh` with the ballot. Instruct similarly.

If fewer than 2 voters are available (both Codex and Cursor unavailable), follow the Voting Protocol's fallback: skip voting, accept all findings, and print the insufficient-voters warning.

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
- Bullet list of **accepted** findings (after voting in round 1, or all findings in rounds 2+) with reviewer attribution (Generic / Correctness / Risk-Integration / Architect / Codex / Cursor)
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

**Round 2+ optimization**: Only launch the **4 Claude subagent reviewers** — skip Codex and Cursor. External reviewers are expensive (5-15 min each) and provide diminishing returns on incremental fix diffs. Claude subagents review the **cumulative diff** (main...HEAD), which includes both the original changes and the fixes just applied.

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
- Findings per round (with per-reviewer breakdown: Generic / Correctness / Risk-Integration / Architect / Codex / Cursor)
- Voting summary (round 1): total findings voted on, accepted (2+ YES), neutral (1 YES), exonerated (0 YES + 1+ EXONERATE), rejected (0 YES + 0 EXONERATE)
- Reviewer Competition Scoreboard (from round 1 voting)
- Total fixes applied across all rounds
- Build/test status (pass/fail)
- **External reviewer warnings** (repeat any preflight or runtime warnings from Codex/Cursor here so they are visible at the end)

## Step 5 — Cleanup

Remove the session temp directory and all files within it:

```bash
$PWD/.claude/scripts/generic/cleanup-tmpdir.sh --dir "$REVIEW_TMPDIR"
```
