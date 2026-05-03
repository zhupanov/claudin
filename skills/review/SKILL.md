---
name: review
description: "Use when reviewing code changes (--diff for branch diff, or positional text for existing code review). Description mode files findings as issues by default (--no-issues suppresses)."
argument-hint: "[--diff] [--no-issues] [--session-env <path>] [--step-prefix <prefix>] [<description>]"
allowed-tools: Bash, Read, Edit, Write, Grep, Glob, Agent, Task, WebFetch, Skill
---

# Code Review Skill

Review code changes using a 6-reviewer specialist panel (5 Cursor specialists + 1 Codex generic). Two modes: **diff mode** (`--diff`) reviews the current branch diff vs `main` and implements accepted suggestions; **description mode** (positional `<description>`) reviews existing code matching the description and files accepted findings as GitHub issues by default (`--no-issues` to suppress). Claude is not a reviewer but participates as a voter in the 3-voter adjudication panel.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns AND after every `Bash` tool call that completes a numbered step or sub-step, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, on a Bash result, or on a status message, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. This applies to ALL step boundaries from Step 0 through Step 5, and to ALL sub-step transitions within Step 3's review loop (3a→3b→3c→3d→3e→3f→loop back to Step 1). **Critical: in diff mode, the review loop (Steps 1→2→3) repeats until convergence (0 findings) or the 7-round safety limit — completing one round's fixes does NOT mean the review is done.** The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Flags**: Parse flags from `$ARGUMENTS`. Flags may appear in any order; stop at the first non-flag token. After stripping all flags, the remainder (joined as a single string) is the **positional description** — it activates description mode. **All flags MUST appear before the positional description.** Because the parser stops at the first non-flag token, any flag-looking token appearing AFTER the positional description is silently absorbed into the description text rather than parsed as a flag — there is no warning. Example correct order: `/review --no-issues my description`. **All boolean flags default to `false`. Only set a flag to `true` when its `--flag` token is explicitly present in the arguments. Flags are independent — the presence of one flag must not influence the default value of any other flag.**

- `--diff`: Set a mental flag `diff_mode=true`. Activates **diff mode** (branch diff vs `main`). Mutually exclusive with positional description text. Default: `diff_mode=false`.
- `--no-issues`: Set a mental flag `no_issues=true`. Suppresses issue filing in description mode. In diff mode, silently ignored (diff mode never files issues). Default: `no_issues=false`.
- `--session-env <path>`: Set `SESSION_ENV_PATH` to the given path. This file contains already-discovered session values from a caller skill (e.g., `/implement`) including reviewer health state (`CODEX_HEALTHY`, `CURSOR_HEALTHY`). If not provided, `SESSION_ENV_PATH` is empty (standalone invocation — full health probe at Step 0).
- `--step-prefix <prefix>`: Encodes both numeric prefix and textual breadcrumb path using `::` delimiter — see `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for the full encoding spec. Examples: `"5.::code review"` (numeric `5.`, path `code review`), `"5."` (numeric only, backward compat). Default: empty (standalone numbering). Internal orchestration flag.

## Mode activation

Mode is determined by the parser state machine (fail-closed, evaluated in order):

1. If `--diff` present AND positional description text present → **ERROR**: print `**⚠ --diff cannot be combined with a description. Use --diff alone for branch diff review, or provide a description without --diff. Aborting.**` and exit.
2. If `--diff` present (no positional text) → **diff mode**. Reviews current branch diff vs `main`, implements accepted suggestions. No issue filing.
3. If positional description text present (no `--diff`) → **description mode**. Resolves description to a canonical file list, reviews existing code, files accepted findings as GitHub issues by default (`--no-issues` suppresses). Security-tagged findings are never filed publicly (held locally per SECURITY.md).
4. If neither `--diff` nor positional description text → **ERROR**: print `**⚠ /review requires either --diff (branch diff review) or a description of what to review. Examples: /review --diff, /review implementation of auth module, /review --no-issues error handling in scripts/. Aborting.**` and exit.

**Description mode** replaces the former "slice mode": Step 1 replaces `gather-branch-context.sh` with a description-resolve step, Step 2 reviewer prompts use description-mode bodies, Step 3 skips the implement-fixes path, and Step 4 emits a `### review-result` KV footer. Issue filing via `/umbrella` is the default unless `--no-issues` is set.

**Diff mode** reviews the current branch diff vs `main`, implements accepted fixes in a recursive loop, and does not file issues.

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

### Reviewer status table

After launching all reviewers (Step 2), maintain a mental tracker of each reviewer's status. Print a compact table after EACH status change:

```
📊 Reviewers: | Structure: ✅ 3m12s | Correctness: ⏳ | Testing: ✅ 2m45s | Security: ⏳ | Edge-cases: ✅ 4m30s | Codex: ⏳ |
```

Icons: ✅ done (with elapsed time since launch), ⏳ pending/in-progress, ❌ failed/timeout (with elapsed time since launch), ⊘ skipped (unavailable). See `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md` for elapsed time and step start formatting rules.

**Status table updates**: (1) Print initial table after launching all reviewers (all ⏳ or ⊘). (2) Update after `collect-agent-results.sh` returns (all external reviewers resolved).

Use empty `description` parameter on Bash tool calls and terse 3-5 word descriptions on Agent tool calls. Do not produce explanatory prose between tool call outputs — only print: step breadcrumb lines (start `🔶`, completion `✅`, skip `⏩`), all warning/error lines (`**⚠ ...`), structured summaries (voting tallies, scoreboards, round summaries, findings lists, final summary), and the reviewer status table.

## Description Mode

When positional description text is present (no `--diff`), `/review` operates in **description mode** instead of diff mode:

- Step 1 (Gather Context): replaced by a **description-resolve** step that maps the verbal description to a canonical file list at `$REVIEW_TMPDIR/scope-files.txt` via Glob/Grep/Read. The canonical list anchors OOS classification.
- Step 2 (Launch Reviewers): reviewer prompts instruct the panel to review the canonical file list (existing code, not a diff). Reviewers may explore further via Glob/Grep/Read for context but OOS classification is anchored to the canonical list.
- Step 3 (Review Cycle): runs ONE round only (no recursive re-review loop). After voting, compose a findings batch and invoke `/umbrella` via the Skill tool (default), or just print the findings (if `--no-issues`).
- Step 3e (Implement Fixes): SKIPPED in description mode — description mode is read-only review for issue filing, not implement-fixes.
- Step 4 (Final Summary): writes accepted security findings to `$REVIEW_TMPDIR/security-findings.md` (printed to terminal before cleanup; never filed publicly per SECURITY.md); emits a `### review-result` KV footer.

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

### Diff mode (`--diff`)

Run the gather script to collect the diff and context:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/gather-branch-context.sh --output-dir "$REVIEW_TMPDIR"
```

Parse the output for `DIFF_FILE`, `FILE_LIST_FILE`, and `COMMIT_LOG_FILE`. Read these files to get the full diff, file list, and commit log — you will pass these to each subagent.

### Description mode (positional description text)

Skip `gather-branch-context.sh`. Resolve the verbal description to a canonical file list:

1. **Load the verbal description**: use `DESCRIPTION_TEXT` (the positional remainder captured by the flag parser, joined as a single string).
2. **Resolve to canonical file list**: use `Glob`, `Grep`, and `Read` tools to identify the files that match the verbal description. The orchestrating agent applies semantic judgment — for "implementation of /research skill", that means `skills/research/SKILL.md` and `skills/research/references/*.md` and any sibling scripts; for "all hook scripts under hooks/", that means `hooks/*.sh` and `hooks/hooks.json`; for "complete contents of foo library", that means every file under `foo/`.
3. **Write to `$REVIEW_TMPDIR/scope-files.txt`**: one file path (repo-relative) per line. This file is the **canonical anchor for OOS classification** — reviewers MUST treat this as the authoritative scope for the description.
4. If the resolved file list is empty, print `**⚠ Description resolved to zero files. Nothing to review. Exiting.**`, emit a `### review-result` footer with `PARSE_STATUS=ok ISSUES_CREATED=0 ISSUES_DEDUPLICATED=0 ISSUES_FAILED=0 SECURITY_FINDINGS_HELD=0`, and proceed to Step 5 (cleanup).

Set `DIFF_FILE` to empty (no diff in description mode). Set `FILE_LIST_FILE` to `$REVIEW_TMPDIR/scope-files.txt`. Set `COMMIT_LOG_FILE` to empty.

## Step 2 — Launch Reviewer Panel in Parallel

### Reviewer panel composition

The panel has 6 reviewers: **5 specialist reviewers** + **1 generic Codex reviewer**. Each specialist concentrates on a narrow focus area using personality definitions from `${CLAUDE_PLUGIN_ROOT}/agents/reviewer-*.md`, rendered into tool-specific prompts by `${CLAUDE_PLUGIN_ROOT}/scripts/render-specialist-prompt.sh`.

The 5 specialists and their attribution labels:

| Specialist | Agent file | Attribution label |
|---|---|---|
| Structure/KISS/Maintainability | `agents/reviewer-structure.md` | `Structure` |
| Correctness/Logic/Error-paths | `agents/reviewer-correctness.md` | `Correctness` |
| Tests/CI/Regression | `agents/reviewer-testing.md` | `Testing` |
| Security/Trust-boundaries | `agents/reviewer-security.md` | `Security` |
| Edge-cases/Failure-recovery | `agents/reviewer-edge-cases.md` | `Edge-cases` |

The generic reviewer uses attribution label `Codex`.

**Description mode is unchanged**: single round, no implement loop, not affected by the round-state machine below. Description mode always launches the full 6-reviewer panel for its single round.

### Fallback matrix

| Cursor | Codex | Specialist slots (5) | Generic slot (1) | Total |
|---|---|---|---|---|
| ✅ | ✅ | 5x Cursor specialist (`cursor-specialist-{name}-output.txt`) | 1x Codex generic (`codex-output.txt`) | 6 |
| ❌ | ✅ | 5x Codex specialist (`codex-specialist-{name}-output.txt`) | 1x Codex generic (`codex-output.txt`) | 6 |
| ✅ | ❌ | 5x Cursor specialist (`cursor-specialist-{name}-output.txt`) | 1x Claude generic (Agent tool, `larch:code-reviewer`, `"sonnet"`) | 6 |
| ❌ | ❌ | — | 1x Claude generic (Agent tool, `larch:code-reviewer`, `"sonnet"`) | 1 |

**Partial specialist failure**: if `collect-agent-results.sh` reports `STATUS != OK` for an individual specialist slot, follow Runtime Timeout Fallback for that slot's tool only — flip the tool to unavailable for the session. The round proceeds with whichever specialists returned valid output. Do NOT retry individual slots within the same round.

### Launch procedure

Launch **all reviewers in a single message**. Spawn order: specialist slots first (slowest), then generic slot.

**5 specialist slots** — for each specialist (`structure`, `correctness`, `testing`, `security`, `edge-cases`), determine which tool to use per the fallback matrix and invoke the appropriate launch wrapper. The wrappers handle prompt rendering (`render-specialist-prompt.sh`), model args (`agent-model-args.sh`), and prompt wrapping (`cursor-wrap-prompt.sh` for Cursor) internally:

**Cursor specialist** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/launch-cursor-review.sh --output "$REVIEW_TMPDIR/cursor-specialist-<name>-output.txt" --timeout 1800 --agent-file "${CLAUDE_PLUGIN_ROOT}/agents/reviewer-<name>.md" --mode <diff|description> [--description-text "${DESCRIPTION_TEXT}" --scope-files "$REVIEW_TMPDIR/scope-files.txt"] --competition-notice
```

**Codex specialist** (fallback when `cursor_available` is false, `codex_available` is true):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/launch-codex-review.sh --output "$REVIEW_TMPDIR/codex-specialist-<name>-output.txt" --timeout 1800 --agent-file "${CLAUDE_PLUGIN_ROOT}/agents/reviewer-<name>.md" --mode <diff|description> [--description-text "${DESCRIPTION_TEXT}" --scope-files "$REVIEW_TMPDIR/scope-files.txt"] --competition-notice
```

Use `run_in_background: true` and `timeout: 1860000` on each specialist Bash tool call.

**1 generic Codex slot** (if `codex_available`):

**Diff mode**:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/launch-codex-review.sh --output "$REVIEW_TMPDIR/codex-output.txt" --timeout 1800 --prompt "Review all code changes on the current branch vs main. Run git diff main...HEAD to see changes and git log main...HEAD --oneline for commits. For each changed file, read the full file for context. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Return numbered findings with focus-area tag, file:line, issue, and suggested fix. If NO issues, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level."
```

**Description mode**:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/launch-codex-review.sh --output "$REVIEW_TMPDIR/codex-output.txt" --timeout 1800 --prompt "Review existing code described as: '${DESCRIPTION_TEXT}'. The canonical file list is at $REVIEW_TMPDIR/scope-files.txt — read that file first to see exactly which files are in scope. Read each listed file in full. You may also explore via Glob/Grep/Read for additional context, but in-scope vs out-of-scope (OOS) classification MUST be anchored to the canonical file list — findings about files NOT in scope-files.txt are OOS, even if they look related. Walk five focus areas: (1) Code Quality: bugs, logic, reuse, tests, backward compat, style. (2) Risk/Integration: breaking changes, side effects, thread safety, deployment risks, regressions, CI. (3) Correctness: logic errors, off-by-one, nil handling, type mismatches, races, error paths. (4) Architecture: separation of concerns, contract boundaries, invariants, semantic boundaries. (5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs. Tag each finding with its focus area (one of code-quality / risk-integration / correctness / architecture / security). Mark any finding about a file NOT in scope-files.txt as OOS. Return findings in two clearly delimited sections: a section starting with the line '### In-Scope Findings' for findings about files in scope-files.txt, and a section starting with the line '### Out-of-Scope Observations' for findings about files NOT in scope-files.txt. Each finding: focus-area tag, file:line, issue, and suggested fix. If you have neither in-scope findings nor out-of-scope observations, output exactly NO_ISSUES_FOUND. Do NOT modify files. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1860000`.

**Generic Codex fallback** (if `codex_available` is false): Launch a Claude Code Reviewer subagent via the Agent tool (subagent_type: `larch:code-reviewer`, model: `"sonnet"`) with the same code-review context. Use the Code Reviewer archetype from `${CLAUDE_PLUGIN_ROOT}/skills/shared/reviewer-templates.md` with mode-appropriate `{REVIEW_TARGET}` and `{CONTEXT_BLOCK}`, and the competition notice appended.

**Both-down path** (both `cursor_available` and `codex_available` are false): Launch only 1 Claude Code Reviewer subagent (generic, no specialists). Print: `**⚠ Both Cursor and Codex unavailable. Proceeding with 1 Claude generic reviewer. Voting will be skipped (insufficient reviewers).**`

Append the following competition context to each reviewer's prompt (specialist and generic, all modes):

> **Competition notice**: Your findings will be voted on by a 3-agent panel (Claude Code Reviewer subagent, Codex, Cursor) using YES/NO/EXONERATE. Each finding that receives 2+ YES votes earns you +1 point. Findings with exactly 1 YES earn 0 points. Findings with 0 YES but at least 1 EXONERATE earn 0 points (the panel recognized your concern as legitimate). Findings with 0 YES and 0 EXONERATE cost you -1 point. Focus on high-quality, actionable findings. Out-of-scope observations use **asymmetric scoring** — accepted OOS items (2+ YES) earn +1 point and are filed as GitHub issues; all other OOS outcomes (including unanimous rejection) score 0.

### Collecting External Reviewer Results

External reviewer output collection, validation, and retry are handled by the shared collection script — see the **Collecting External Reviewer Results** section in `${CLAUDE_PLUGIN_ROOT}/skills/shared/external-reviewers.md`. The explicit `collect-agent-results.sh` invocation is in Step 3a below.

## Step 3 — Collect, Deduplicate, and Implement (Recursive Loop in diff mode; ONE round in description mode)

**MANDATORY — READ ENTIRE FILE** before executing any sub-step of Step 3: `${CLAUDE_PLUGIN_ROOT}/skills/review/references/domain-rules.md`. It contains the Settings.json permissions ordering rule and the skill/script genericity rule that the orchestrating agent applies when evaluating findings and reviewing the diff/description across Step 3 (collect, dedup, voting, fix application). Loaded unconditionally on every Step 3 entry.

### Round-state machine (diff mode)

**In diff mode**, this step repeats until reviewers find no more issues or the round cap is hit. Track the current **round number** starting at 1.

| Rounds | Reviewer panel | Voting | OOS collection | Stop condition |
|--------|---------------|--------|----------------|----------------|
| 1-3 | Full 6-reviewer panel (5 specialists + 1 generic) | 3-voter panel (Claude + Codex + Cursor) each round | Yes | 0 findings accepted by vote, OR round 3 reached |
| 4-7 | Single Cursor generic (Codex → Claude fallback) | No voting (auto-accept) | No | 0 findings, OR round 7 reached |

**Description mode is unchanged**: single round, no implement loop. After Step 3d's round summary, jump directly to Step 4 (skip Step 3e implement-fixes and Step 3f re-review).

### 3a — Collect

**Rounds 1-3 (full 6-reviewer panel):** Collect and validate all external reviewer outputs using the shared collection script. Include output paths for all specialist and generic reviewers that were actually launched:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-agent-results.sh --timeout 1860 --substantive-validation --validation-mode [--write-health "${SESSION_ENV_PATH}.health"] \
  "$REVIEW_TMPDIR/cursor-specialist-structure-output.txt" \
  "$REVIEW_TMPDIR/cursor-specialist-correctness-output.txt" \
  "$REVIEW_TMPDIR/cursor-specialist-testing-output.txt" \
  "$REVIEW_TMPDIR/cursor-specialist-security-output.txt" \
  "$REVIEW_TMPDIR/cursor-specialist-edge-cases-output.txt" \
  "$REVIEW_TMPDIR/codex-output.txt"
```

Only include `--write-health` if `SESSION_ENV_PATH` is non-empty. Only include output paths for reviewers that were actually launched as external tools (adjust paths per the fallback matrix — e.g., `codex-specialist-*` when Cursor is down). If the generic slot is a Claude fallback (both-down or Codex-down path), process its Agent tool output directly — do not include it in `collect-agent-results.sh`.

Parse the structured output for each reviewer's `STATUS` and `REVIEWER_FILE`. For any reviewer with `STATUS` not `OK`, follow the **Runtime Timeout Fallback** procedure. Read valid output files. **In description mode**, reviewers produce **dual-list output** with '### In-Scope Findings' and '### Out-of-Scope Observations' section headers — parse both sections. Section-header fail-open rules: (1) if exactly one section header is present, the missing section is interpreted as empty (NOT a parse error); (2) if both section headers are absent AND the entire output is the literal 'NO_ISSUES_FOUND', the reviewer reported nothing — proceed; (3) if both section headers are absent AND the output is not 'NO_ISSUES_FOUND' (legacy unsectioned output), treat the entire body as in-scope. **In diff mode**, external reviewers produce **single-list output** — treat their entire output as in-scope findings.

Merge findings from all 6 reviewers, attributing each finding to its specialist label (`Structure`, `Correctness`, `Testing`, `Security`, `Edge-cases`, or `Codex`). When deduplicating, credit all proposing reviewers. If the same issue appears in both in-scope and OOS from different reviewers, merge under in-scope.

**Rounds 4-7 (diff mode only, single generic reviewer):** Launch a single Cursor generic reviewer (if `cursor_available`; else Codex generic if `codex_available`; else Claude Code Reviewer subagent). Collect its output via `collect-agent-results.sh` with a single output path. If `STATUS` is not `OK`, follow Runtime Timeout Fallback and retry the round with the next available tool in the chain.

OOS observations are only collected in rounds 1-3 — rounds 4-7 use a single generic reviewer without OOS collection.

### 3b — Check for Zero Findings

If **all reviewers** report no issues (e.g., "No issues found.", "No in-scope issues found.", "NO_ISSUES_FOUND"), the loop is done — IMMEDIATELY skip to **Step 4** without writing a summary or status message. If reviewers DID find issues, IMMEDIATELY continue to Step 3c (Deduplicate) — do NOT print a summary or stop.

### 3c — Deduplicate

Merge findings from all reviewers into a single deduplicated list, grouped by file. If two reviewers flag the same issue, keep the more specific suggestion. Assign each deduplicated finding a stable sequential ID (`FINDING_1`, `FINDING_2`, etc. for in-scope; `OOS_1`, `OOS_2`, etc. for OOS) and note which reviewer(s) proposed each.

### 3c.1 — Voting Panel (rounds 1-3)

**In rounds 1-3**: **MANDATORY — READ ENTIRE FILE** `${CLAUDE_PLUGIN_ROOT}/skills/review/references/voting.md` and execute its body — three-voter setup with proportionality guidance, ballot file handling rule (Write tool, not `cat`-heredoc), parallel launch order (Cursor → Codex → Claude subagent), threshold rules + competition scoring per `${CLAUDE_PLUGIN_ROOT}/skills/shared/voting-protocol.md`, the zero-accepted-findings short-circuit to **Step 4**, the OOS-accepted-by-vote artifact write to `$(dirname "$SESSION_ENV_PATH")/oos-accepted-review.md` (only when `SESSION_ENV_PATH` is non-empty AND description mode is OFF — description mode bypasses this artifact and files directly via /umbrella at Step 4), and the save-not-accepted-IDs rule used to suppress re-raised findings in rounds 4+ (diff mode only).

**In rounds 4-7 (diff mode only)**: Skip voting — accept all single-reviewer findings directly, **except** findings that match findings rejected or exonerated by voting in rounds 1-3. **Do NOT load** `${CLAUDE_PLUGIN_ROOT}/skills/review/references/voting.md` in rounds 4+ — the body is for rounds 1-3 and would waste tokens. Same `Do NOT load` guidance applies on the Step 3b zero-findings short-circuit.

### 3d — Print Round Summary

Print to the user:
- `## Review Round {N}` header
- Bullet list of **accepted** findings with reviewer attribution (`Structure` / `Correctness` / `Testing` / `Security` / `Edge-cases` / `Codex`, or `Claude` for the both-down fallback)
- If rounds 1-3: vote counts per finding, accepted OOS items, and any findings not accepted by vote
- Total count of accepted findings for this round

After printing the round summary, IMMEDIATELY continue. **In diff mode**: if 0 findings were accepted this round, skip to Step 4; if >0 findings were accepted, proceed to Step 3e (Implement Fixes). **In description mode**: always skip to Step 4 after 3d (Step 3e is read-only skipped). Do NOT treat the summary as a stopping point.

### 3e — Implement Fixes

**SKIPPED in description mode.** Description mode is read-only — proceed directly to Step 4 after Step 3d.

**In diff mode**, for each **accepted in-scope** finding (`FINDING_*` items only — exclude `OOS_*` items, which are processed separately for issue filing by `/implement`):

1. Apply the suggested fix by editing the relevant file.
2. If the fix involves creating new tests, write them.
3. If the fix involves CI workflow changes, edit the workflow YAML.

> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill (Step 3f or Step 4) — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

After all fixes are applied, invoke `/relevant-checks` via the Skill tool to run validation checks. If checks fail, diagnose and fix the issue, then re-invoke `/relevant-checks` to confirm. When `/relevant-checks` returns successfully, IMMEDIATELY continue to Step 3f — do NOT end the turn, write a summary, or treat successful checks as a stopping point.

### 3f — Re-review

> **CRITICAL: Fixing findings does NOT mean the review has converged.** Convergence requires the reviewers to report no new issues in a fresh round — not just the orchestrator believing its fixes are clean. After implementing fixes, you MUST re-launch reviewers to verify. Do NOT skip this step.

**SKIPPED in description mode.** Proceed to Step 4.

**In diff mode**, increment the round number. IMMEDIATELY re-execute **Step 1** (gather the updated diff) then **Step 2** (launch reviewers again) then **Step 3** (collect, deduplicate, vote/evaluate, implement) as a fresh iteration of the review loop — do NOT halt, summarize, or wait for user input between rounds. The loop continues until reviewers report 0 findings (convergence) or the safety limit is reached (Step 3g).

**Rounds 2-3 (full panel)**: Re-launch the full 6-reviewer panel per Step 2's launch procedure. Voting runs per Step 3c.1. The competition notice is included. This ensures multi-round specialist coverage with proper adjudication. If voting accepts 0 findings in any of rounds 1-3, the review loop terminates early.

**Rounds 4-7 (single generic reviewer)**: Only launch **Cursor generic** (if `cursor_available`; else Codex generic if `codex_available`; else 1 Claude Code Reviewer subagent as fallback). Use the same generic diff-mode prompt from Step 2 (without the competition notice — there is no voting panel in rounds 4+). In rounds 4-7 Step 3a, collect from whichever single reviewer was launched: external output via `collect-agent-results.sh` (with Runtime Timeout Fallback on failure — retry the round with the next tool in the chain), or Claude subagent output directly. Findings that were rejected or exonerated by voting in rounds 1-3 are suppressed per Step 3c.1.

### 3g — Safety Limit

**Diff mode only.** If the loop has run **7 rounds** without converging (3 full-panel rounds + 4 single-reviewer rounds), stop and print a warning, then IMMEDIATELY proceed to Step 4 — do NOT halt or wait for user input.

## Step 4 — Final Summary (and description-mode /umbrella filing)

### 4a — Print summary (both modes)

Print a final summary:
- Total number of review rounds (always 1 in description mode)
- Findings per round (with per-reviewer breakdown: `Structure` / `Correctness` / `Testing` / `Security` / `Edge-cases` / `Codex`, or `Claude` for fallback)
- Voting summary (rounds 1-3): total findings voted on, accepted (2+ YES), neutral (1 YES), exonerated (0 YES + 1+ EXONERATE), rejected (0 YES + 0 EXONERATE)
- Reviewer Competition Scoreboard (cumulative across all voted rounds, with 6 independent players)
- Total fixes applied across all rounds (diff mode only)
- Build/test status (pass/fail)
- **External reviewer warnings** (repeat any preflight or runtime warnings from Codex/Cursor here so they are visible at the end)

### 4b — Description-mode /umbrella filing (default in description mode; skipped when --no-issues)

If description mode is OFF or `no_issues=true`, skip this sub-step.

Compose a findings batch markdown at `$REVIEW_TMPDIR/findings-batch.md`. Include:
- For each in-scope-accepted finding (2+ YES): a generic `### <terse title>` block with `**Description**`, `**File**`, `**Reviewer**`, `**Focus area**`, `**Problem**`, `**Suggested fix**` body.
- For each OOS-accepted finding (2+ YES, NOT focus-area=security): an OOS schema block per `/issue`'s OOS-format parser:
  ```markdown
  ### OOS_N: <short title>
  - **Description**: <full description>
  - **Reviewer**: <attribution>
  - **Vote tally**: <YES/NO/EXONERATE counts>
  - **Phase**: review
  ```
- **Exclude** any finding tagged `security` — those are handled by Step 4c.

If the batch is empty (zero accepted findings, or all accepted findings were security-tagged), skip the `/umbrella` invocation. Set `ISSUES_CREATED=0`, `ISSUES_DEDUPLICATED=0`, `ISSUES_FAILED=0` for the KV footer.

Otherwise, compose a 1-2 sentence umbrella summary paragraph at `$REVIEW_TMPDIR/umbrella-summary.txt` derived from the review context (description text + accepted-finding count + reviewer attribution summary). The summary becomes the lead paragraph of the umbrella issue body if `/umbrella` produces one (≥2 distinct resolved children). **Apply compose-time sanitization** before writing — the umbrella body becomes a public GitHub issue:

- Strip ASCII control characters (except whitespace `\t`, `\n` is already disallowed by the line grammar).
- Replace newlines and tabs with single spaces; collapse internal whitespace runs to one space.
- Redact secrets / API keys / OAuth / JWT / passwords / certificates → `<REDACTED-TOKEN>`.
- Redact internal hostnames / URLs / private IPs → `<INTERNAL-URL>`.
- Redact PII (emails, account IDs tied to a real user) → `<REDACTED-PII>`.
- Cap at ~200 characters (truncate at a word boundary if longer).

Then invoke `/umbrella` via the Skill tool:

> **Continue after child returns.** When `/umbrella` returns, parse its stdout machine lines per `/umbrella`'s Step 4 emit-output grammar — `UMBRELLA_VERDICT=`, `CHILDREN_CREATED=`, `CHILDREN_DEDUPLICATED=`, `CHILDREN_FAILED=`, `UMBRELLA_NUMBER=`, `UMBRELLA_URL=` (and optional `UMBRELLA_DOWNGRADE=`, `UMBRELLA_FAILURE_REASON=`) — and continue to Step 4c — do NOT end the turn or write a summary. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

**Compose `pieces.json` for inter-finding dependency edges**: before invoking `/umbrella`, build a `pieces.json` at `$REVIEW_TMPDIR/pieces.json` encoding inter-finding `depends_on` edges derived from file-overlap metadata. For each accepted finding, the `**File**` field names one or more paths. Two findings have a dependency edge when: (a) they share at least one overlapping file path (after canonicalizing paths — strip leading `./`, resolve `..` segments, case-preserve), AND (b) one finding's description or suggested fix explicitly references sequential dependency on the other (e.g., "this requires the refactor in finding N to land first", "depends on the API change above", "must run after the schema migration"). File overlap alone is necessary but NOT sufficient — it indicates potential conflict, not proven dependency. The `depends_on` array for each piece uses 1-based indices matching the batch markdown's `### <title>` order. Write the JSON array to `$REVIEW_TMPDIR/pieces.json` using the Write tool. If no inter-finding dependencies are detected (common case — most review findings are independent), write a JSON array with empty `depends_on` arrays for each entry and still pass `--pieces-json` (the validator accepts all-empty deps).

Skill invocation:
- Try skill `"umbrella"` first (bare name). If no skill matches, try `"larch:umbrella"`.
- args: `--input-file $REVIEW_TMPDIR/findings-batch.md --umbrella-summary-file $REVIEW_TMPDIR/umbrella-summary.txt --pieces-json $REVIEW_TMPDIR/pieces.json`

Do NOT forward `--auto`, `--merge`, or other flags `/umbrella` does not accept.

Parse `/umbrella`'s stdout. Map to the review-result counters (per dialectic DECISION_2 — uniform "any GitHub issue created counts" semantic — see Step 4d below for the footer schema):

- `ISSUES_CREATED` = `CHILDREN_CREATED` + (1 if `UMBRELLA_NUMBER` is non-empty else 0)
- `ISSUES_DEDUPLICATED` = `CHILDREN_DEDUPLICATED`
- `ISSUES_FAILED` = `CHILDREN_FAILED` + (1 if `UMBRELLA_VERDICT=multi-piece` AND `UMBRELLA_NUMBER` is empty AND `CHILDREN_FAILED=0` else 0).

The umbrella-failure structural signal is `UMBRELLA_VERDICT=multi-piece` AND `UMBRELLA_NUMBER` empty AND `CHILDREN_FAILED=0` (umbrella creation was actually attempted and failed). The `CHILDREN_FAILED=0` gate is essential: per `/umbrella`'s Step 3B.2 abort condition (`skills/umbrella/SKILL.md`), when `ISSUES_FAILED >= 1` from the `/issue` batch, `/umbrella` skips Step 3B.3 entirely (umbrella creation never attempted) and emits `UMBRELLA_VERDICT=multi-piece` plus an empty `UMBRELLA_NUMBER`. Without the gate, `/review` would double-count: N child failures plus a phantom +1 for an umbrella that was never attempted. We do NOT key off `UMBRELLA_FAILURE_REASON` presence — `/umbrella` documents that field as optional even on real umbrella-create failures. Save the mapped counters for the KV footer at Step 4d.

Print an informational line summarizing the outcome (above the KV footer): `filed N children + umbrella #M (<url>)` (when umbrella created), `filed N child issue(s)` (one-shot path), `all findings deduped to existing issues` (downgrade), or omit (empty batch).

### 4c — Write security findings (description mode only)

If description mode is ON, collect any accepted security-tagged findings (focus-area=security; both in-scope-accepted and OOS-accepted with 2+ YES). Write them verbatim to `$REVIEW_TMPDIR/security-findings.md` (printed verbatim to terminal before tmpdir cleanup). Security-tagged findings are NEVER filed publicly via `/umbrella` or `/issue` (per SECURITY.md).

Format each entry:
```markdown
### <focus-area=security> — <short title>
- **File**: <path:line>
- **Reviewer(s)**: <attribution>
- **Vote tally**: <YES/NO/EXONERATE>
- **Concern**: <full description>
- **Suggested fix**: <full text>
```

Set `SECURITY_FINDINGS_HELD` = number of entries written. After writing, IMMEDIATELY continue to the terminal print and then Step 4d — do NOT halt after writing the file.

Print the file's contents verbatim to terminal under a clearly-labeled block:

```
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security-tagged findings (held locally per SECURITY.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
<contents of security-findings.md>
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
```

Then print: `**⚠ Handle these findings per SECURITY.md's vulnerability-disclosure procedure. They are NOT filed as public GitHub issues.**` IMMEDIATELY continue to Step 4d — do NOT halt after the security warning.

### 4d — Description-mode KV footer (description mode only)

Print the `### review-result` KV footer immediately before exiting Step 4.

```
### review-result
ISSUES_CREATED=<n>
ISSUES_DEDUPLICATED=<n>
ISSUES_FAILED=<n>
SECURITY_FINDINGS_HELD=<n>
PARSE_STATUS=ok
```

Substitute `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED` from Step 4b (or zero each if Step 4b was skipped — i.e., `no_issues=true` or the findings batch was empty). Substitute `SECURITY_FINDINGS_HELD` from Step 4c independently (zero only if Step 4c found no security findings — Step 4c always runs in description mode regardless of whether Step 4b ran). `PARSE_STATUS=ok` always (any error path emits a different `PARSE_STATUS` value or aborts before reaching here). After printing the KV footer, IMMEDIATELY continue to Step 5 (Cleanup) — do NOT halt after the footer.

## Step 5 — Cleanup

### 5a — Update Health Status File

Health status file updates are handled automatically by `collect-agent-results.sh --write-health` during reviewer collection (Step 3a). No additional cleanup-time write is needed unless a reviewer was marked unhealthy outside of a `collect-agent-results.sh` call. If `SESSION_ENV_PATH` is non-empty and any such untracked health change occurred, re-write the health status file at `${SESSION_ENV_PATH}.health` with the final health state before cleanup.

### 5b — Remove Temp Directory

Remove the session temp directory and all files within it:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$REVIEW_TMPDIR"
```
