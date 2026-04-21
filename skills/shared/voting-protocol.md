# Voting Protocol

Shared voting protocol for adjudicate review findings. Used by `/design` (plan review) and `/review` (code review). This protocol **replace** Negotiation Protocol for `/design` and `/review`. `/loop-review` and `/research` keep Negotiation Protocol in `external-reviewers.md`.

## Overview

After reviewers submit findings and dedup done, 3-agent voting panel vote YES/NO/EXONERATE on each finding. Findings with 2+ YES accepted; others not implemented. Original reviewers earn competition points based on how findings perform. EXONERATE = third option mean "legit concern, but not worth implement in this PR" — spare proposing reviewer from losing point on in-scope findings. (OOS observations use asymmetric reward-only scoring — see [OOS Scoring](#oos-scoring) below — so OOS rejection no penalty anyway.)

## Ballot Format

Before send to voters, assign each deduped finding stable sequential ID. Format ballot as:

```
## Findings Ballot

Vote YES, NO, or EXONERATE on each finding. A finding should receive YES if it is correct, important, and worth implementing. Vote NO if the finding is incorrect, trivial, or would cause more harm than good. Vote EXONERATE if the finding raises a legitimate concern worth noting, but is not worth implementing in this PR — this spares the proposing reviewer from a penalty on in-scope findings (OOS items use reward-only scoring — rejection carries no penalty regardless).

FINDING_1: <reviewer attribution> — <finding description>
FINDING_2: <reviewer attribution> — <finding description>
...
```

Include reviewer attribution (`Code`, `Codex`, or `Cursor`) so voters have context, but tell voters evaluate each finding on merits regardless of proposer. Same three-attribution shape across all reviewer panels: `/design` and `/review` (Voting Protocol), plus `/loop-review` and `/research` (Negotiation Protocol). `/loop-review` and `/research` no vote — use Negotiation Protocol instead.

## Voter Output Format

Each voter must output one line per ballot item, **use same ID from ballot** — `FINDING_N` for in-scope, `OOS_N` for out-of-scope:

```
FINDING_1: YES — <one-line rationale>
FINDING_2: NO — <one-line rationale>
FINDING_3: EXONERATE — <one-line rationale>
OOS_1: YES — <one-line rationale>
OOS_2: NO — <one-line rationale>
...
```

Valid vote tokens: `YES`, `NO`, `EXONERATE`. If voter output have valid votes for some findings but miss others, use valid votes and treat only missing as abstentions (shrink voter pool for those). Treat entire output unparseable only if zero findings match expected format — then treat all votes as abstentions.

## Threshold Rules

| Eligible Voters | YES Votes Required | Notes |
|---|---|---|
| 3 | 2+ | Standard majority |
| 2 | 2 (unanimous) | When one voter unavailable/timed out |
| 1 | Skip voting | Fall back to accepting all findings |
| 0 | Skip voting | Fall back to accepting all findings |

When voting skipped due to not enough voters, print: `**⚠ Voting skipped (<N> voter(s) available, minimum 2 required). All findings accepted.**`

## Voter Panel Composition

**For plan review** (`/design` Step 3):
- **Voter 1**: Claude Code Reviewer subagent — launched as fresh Agent tool invocation (subagent_type: `code-reviewer`) with focused voting prompt (separate from reviewer subagents)
- **Voter 2**: Codex — via `run-external-reviewer.sh`
- **Voter 3**: Cursor — via `run-external-reviewer.sh`

**For code review** (`/review` Step 3):
- **Voter 1**: Claude Code Reviewer subagent — launched as fresh Agent tool invocation (subagent_type: `code-reviewer`)
- **Voter 2**: Codex — via `run-external-reviewer.sh`
- **Voter 3**: Cursor — via `run-external-reviewer.sh`

All voters vote on **all** findings — no self-voting exclusion. Voters told to evaluate each finding objectively regardless of proposer.

## Voter Prompt Template

Customize `{VOTER_ROLE}` and `{REVIEW_CONTEXT}` per skill:

```
You are a {VOTER_ROLE} participating in a voting panel. You will be presented with a list of proposed changes to {REVIEW_CONTEXT}. For each finding, vote YES, NO, or EXONERATE:
- **YES**: The finding is correct, important, and worth implementing.
- **NO**: The finding is incorrect, trivial, duplicative, or would cause more harm than good.
- **EXONERATE**: The finding raises a legitimate concern worth noting, but is not worth implementing in this PR. This spares the proposing reviewer from a penalty on in-scope findings.

Be scrupulous — only vote YES for findings that genuinely improve the {REVIEW_CONTEXT}. Use EXONERATE when a concern is valid but not actionable now.

**For items prefixed with `[OUT_OF_SCOPE]`:** These are pre-existing issues beyond this PR's scope. Vote YES if the observation deserves a GitHub issue for future tracking. Vote NO if it is not worth tracking. Vote EXONERATE if the concern is legitimate but not worth filing a GitHub issue. OOS items are never implemented in this PR — YES means "file an issue," not "implement now." Vote YES only when the observation is concrete and important enough to justify a durable GitHub issue (typical signals: specific file:line or a reproducible failure mode); use EXONERATE for legitimate concerns that are not issue-worthy, and NO for trivial or incorrect observations.

{BALLOT}

For each ballot item, output exactly one line using the same ID from the ballot (FINDING_N or OOS_N):
FINDING_N: YES — <one-line rationale>
or
FINDING_N: NO — <one-line rationale>
or
FINDING_N: EXONERATE — <one-line rationale>
or
OOS_N: YES — <one-line rationale>
or
OOS_N: NO — <one-line rationale>
or
OOS_N: EXONERATE — <one-line rationale>

You must vote on every item. Do NOT skip any. Do NOT modify files.
```

## Launching Voters

Launch all 3 voters **in parallel** (single message). When external tools unavailable, launch Claude replacement voters instead so total voter count always stay 3. Spawn order: Cursor first (slowest), then Codex, then Claude subagent (fastest).

**Cursor voter** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool cursor --output "<tmpdir>/cursor-vote-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "<voter prompt with ballot>. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1260000`.

**Cursor voter replacement** (if `cursor_available` false): Launch Claude subagent voter via Agent tool with voter prompt. Replacement keep total voter count at 3.

**Codex voter** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh --tool codex --output "<tmpdir>/codex-vote-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/reviewer-model-args.sh" --tool codex --with-effort) \
    --output-last-message "<tmpdir>/codex-vote-output.txt" \
    "<voter prompt with ballot>. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1260000`.

**Codex voter replacement** (if `codex_available` false): Launch Claude subagent voter via Agent tool with voter prompt. Replacement keep total voter count at 3.

**Claude voter**: Launch via Agent tool with voter prompt.

Wait for external voter sentinels via `wait-for-reviewers.sh` (use same tmpdir as review phase — no new temp dir for voting). Only include sentinel paths for voters actually launched:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/wait-for-reviewers.sh --timeout 1260 \
  "<tmpdir>/cursor-vote-output.txt.done" \
  "<tmpdir>/codex-vote-output.txt.done"
```

Use `timeout: 1260000` on Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Note: voter output files use `-vote-` infix to avoid collision with reviewer output files (`-plan-output` or `-output`).

**Collecting voter results**: Use `collect-reviewer-results.sh` to validate external voter outputs (same as reviewer outputs). Parse `STATUS` and `FAILURE_REASON` per voter. If voter fail (`STATUS != OK`), print: `**⚠ <Voter> voter failed — <FAILURE_REASON>. Proceeding with <N> voters (<remaining voter names>).**` Always include `FAILURE_REASON` so user see why voter failed (e.g., timeout, crash, empty output). Shrink eligible voter count and apply threshold rules above.

## Competition Scoring

After tally votes, compute score for each **original reviewer** (not voters):

| Vote Result | Points | Description |
|---|---|---|
| Finding accepted (2+ YES) | +1 | Reviewer's finding was validated by the panel |
| Finding got exactly 1 YES | 0 | Neutral — not enough support but not rejected |
| Finding got 0 YES but 1+ EXONERATE | 0 | Exonerated — legitimate concern, not actionable now |
| Finding got 0 YES and 0 EXONERATE | -1 | Rejected — finding was unanimously dismissed |

If deduped finding proposed by multiple reviewers (merged during dedup), **all** contributing reviewers get same points for that finding.

## Scoreboard

After voting, print scoreboard to session:

```
## Reviewer Competition Scoreboard

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | OOS Proposed | OOS Accepted | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|--------------|--------------|-------|
| Code   | 3        | 2        | 1               | 0                             | 0                         | 1            | 0            | +2    |
| Codex  | 2        | 1        | 0               | 1                             | 0                         | 0            | 0            | +1    |
| Cursor | 2        | 1        | 1               | 0                             | 0                         | 0            | 0            | +1    |

Note: In future iterations, token allocation will be weighted proportionally
to reviewer scores — higher-scoring reviewers will receive more tokens.
```

## Out-of-Scope Observations

Reviewers may return second list of **out-of-scope observations** — pre-existing issues or concerns beyond PR scope worth surface for future. Handled alongside in-scope findings but different semantics:

### OOS on the Ballot

Out-of-scope items deduped separately from in-scope findings and assigned IDs with `OOS_` prefix (e.g., `OOS_1`, `OOS_2`). Included on same ballot as in-scope findings, labeled with `[OUT_OF_SCOPE]`:

```
OOS_1: [OUT_OF_SCOPE] Code — <description of pre-existing issue>
```

### OOS Vote Semantics

For OOS items, vote meanings:
- **YES**: Observation deserve GitHub issue for future attention.
- **NO**: Not worth track — observation trivial or wrong.
- **EXONERATE**: Legit observation worth document, but not worth file GitHub issue.

If OOS item get 2+ YES votes, **accepted** and will be filed as GitHub issue by `/implement`. Else stay as observation reported in PR body.

**OOS items never implemented in current PR** — accepted OOS items result in issue creation only. Clean separate "fix now" (in-scope findings) from "fix later" (OOS observations).

### OOS Scoring

Out-of-scope items use **asymmetric reward-only scoring** — accepted OOS earn +1, all other outcomes score 0 so reviewers never penalized for surface observations in good faith:

| OOS Vote Result | Points | Description |
|---|---|---|
| OOS accepted (2+ YES) | +1 | Reviewer surfaced an issue worth tracking |
| OOS neutral (exactly 1 YES) | 0 | Insufficient support, but not dismissed |
| OOS exonerated (0 YES, 1+ EXONERATE) | 0 | Legitimate observation, but not worth an issue |
| OOS rejected (0 YES, 0 EXONERATE) | 0 | No penalty — reviewers are encouraged to surface observations freely |

### OOS Scoreboard

Scoreboard add columns for OOS items:

```
| Reviewer | ... | OOS Proposed | OOS Accepted | ...
```

### OOS Reporting

OOS items **not** written to `rejected-findings.md`. Separate pipeline:

- **Accepted OOS items — reviewer voting path** (2+ YES): Written to artifact file (`oos-accepted-design.md` or `oos-accepted-review.md`) in `$IMPLEMENT_TMPDIR` during voting phase.
- **Accepted OOS items — main-agent dual-write path** (no vote required): Written to `oos-accepted-main-agent.md` in `$IMPLEMENT_TMPDIR` by main agent at discovery time, every time it log `Pre-existing Code Issues` entry to `execution-issues.md`. This mechanical enforcement of `/implement`'s Follow-up Work Principle for `Pre-existing Code Issues` category — see `/implement` SKILL.md → "Follow-up Work Principle" and "Mechanical enforcement of the principle: `Pre-existing Code Issues` dual-write". Durable follow-up work outside that category not auto-filed via this path — main agent file manually via `/issue` per principle. This path unconditional, run in every mode (`--quick`, `--auto`, `--merge`, `--draft`, `--debug`, `--no-merge`, or any future flag). NOT pass through voting panel — main-agent classification is policy gate.
- **Unified filing**: `/implement` Step 9a.1 read all three artifacts, dedup across phases, create GitHub issues via `/issue` (batch mode) with LLM-based semantic dup detection against open + recently-closed GitHub issues. All three artifacts share same `### OOS_N:` schema (Description, Reviewer, Vote tally, Phase). Main-agent items use Reviewer=`Main agent`, Vote tally=`N/A — auto-filed per policy`, Phase=`implement`.
- **Non-accepted OOS items**: Collected and reported in dedicated `<details><summary>Out-of-Scope Observations</summary>` section in PR body for future reference.

External reviewers (Codex, Cursor) use single-list prompts and do not produce OOS items — entire output treated as in-scope findings. Only Claude subagent reviewers (which use dual-list templates from `reviewer-templates.md`) produce OOS items via voting; main agent's dual-write path produce OOS items without voting.

## Zero Accepted Findings

If voting filter out **all** in-scope findings (every in-scope finding rejected by panel), print: `**ℹ Voting panel rejected all findings. No changes to implement.**` and skip implementation/revision step. Proceed directly to rejected findings report. (OOS items accepted for issue filing processed separately by `/implement` and do not count as implementation work.)
