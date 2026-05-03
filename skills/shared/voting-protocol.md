# Voting Protocol

Shared voting protocol for adjudicating review findings. Used by `/design` (plan review) and `/review` (code review). This protocol **replaces** the Negotiation Protocol for `/design` and `/review`. `/research` continues using the Negotiation Protocol in `external-reviewers.md`.

## Overview

After reviewers submit findings and findings are deduplicated, a 3-agent voting panel votes YES/NO/EXONERATE on each finding. Findings with 2+ YES votes are accepted; others are not implemented. Original reviewers earn competition points based on how their findings perform in voting. EXONERATE is a third option meaning "legitimate concern, but not worth implementing in this PR" — it spares the proposing reviewer from losing a point on in-scope findings. (OOS observations use asymmetric reward-only scoring — see [OOS Scoring](#oos-scoring) below — so OOS rejection carries no penalty regardless.)

## Ballot Format

Before sending to voters, assign each deduplicated finding a stable sequential ID. Format the ballot as:

```
## Findings Ballot

Vote YES, NO, or EXONERATE on each finding. A finding should receive YES if it is correct, important, and worth implementing. Vote NO if the finding is incorrect, trivial, or would cause more harm than good. Vote EXONERATE if the finding raises a legitimate concern worth noting, but is not worth implementing in this PR — this spares the proposing reviewer from a penalty on in-scope findings (OOS items use reward-only scoring — rejection carries no penalty regardless).

FINDING_1: <reviewer attribution> — <finding description>
FINDING_2: <reviewer attribution> — <finding description>
...
```

Include the reviewer attribution so voters have context, but instruct voters to evaluate each finding on its merits regardless of who proposed it. Attribution labels are skill-specific: `/design` uses `Code` / `Codex` / `Cursor` (3-reviewer panel); `/review` uses specialist labels (`Structure`, `Correctness`, `Testing`, `Security`, `Edge-cases`, `Codex`) for its 6-reviewer panel. `/research` does not participate in voting — it uses the Negotiation Protocol instead.

## Voter Output Format

Each voter must output one line per ballot item, **using the same ID that appears on the ballot** — `FINDING_N` for in-scope items and `OOS_N` for out-of-scope items:

```
FINDING_1: YES — <one-line rationale>
FINDING_2: NO — <one-line rationale>
FINDING_3: EXONERATE — <one-line rationale>
OOS_1: YES — <one-line rationale>
OOS_2: NO — <one-line rationale>
...
```

Valid vote tokens are `YES`, `NO`, and `EXONERATE`. If a voter's output contains valid votes for some findings but is missing votes for others, use the valid votes and treat only the missing findings as abstentions (reduce the voter pool size for those findings). Treat the entire output as unparseable only if zero findings can be matched to the expected format — in that case, treat all their votes as abstentions.

## Threshold Rules

| Eligible Voters | YES Votes Required | Notes |
|---|---|---|
| 3 | 2+ | Standard majority |
| 2 | 2 (unanimous) | When one voter unavailable/timed out |
| 1 | Skip voting | Fall back to accepting all findings |
| 0 | Skip voting | Fall back to accepting all findings |

When voting is skipped due to insufficient voters, print: `**⚠ Voting skipped (<N> voter(s) available, minimum 2 required). All findings accepted.**`

## Voter Panel Composition

**For plan review** (`/design` Step 3):
- **Voter 1**: Claude Code Reviewer subagent — launched as a fresh Agent tool invocation (subagent_type: `larch:code-reviewer`) with a focused voting prompt (separate from the reviewer subagents)
- **Voter 2**: Codex — via `run-external-agent.sh`
- **Voter 3**: Cursor — via `run-external-agent.sh`

**For code review** (`/review` Step 3):
- **Voter 1**: Claude Code Reviewer subagent — launched as a fresh Agent tool invocation (subagent_type: `larch:code-reviewer`)
- **Voter 2**: Codex — via `run-external-agent.sh`
- **Voter 3**: Cursor — via `run-external-agent.sh`

All voters vote on **all** findings — no self-voting exclusion. Voters are instructed to evaluate each finding objectively regardless of who proposed it.

## Voter Prompt Template

Customize the `{VOTER_ROLE}` and `{REVIEW_CONTEXT}` per skill:

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

Launch all 3 voters **in parallel** (in a single message). When external tools are unavailable, launch Claude replacement voters instead so the total voter count always remains 3. Spawn order: Cursor first (slowest), then Codex, then Claude subagent (fastest).

**Cursor voter** (if `cursor_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool cursor --output "<tmpdir>/cursor-vote-output.txt" --timeout 1200 --capture-stdout -- \
  cursor agent -p --force --trust $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool cursor --with-effort) --workspace "$PWD" \
    "$("${CLAUDE_PLUGIN_ROOT}/scripts/cursor-wrap-prompt.sh" "<voter prompt with ballot>. Work at your maximum reasoning effort level.")"
```

Use `run_in_background: true` and `timeout: 1260000`.

**Cursor voter replacement** (if `cursor_available` is false): Launch a Claude subagent voter via the Agent tool with the voter prompt. This replacement ensures the total voter count always remains 3.

**Codex voter** (if `codex_available`):

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/run-external-agent.sh --tool codex --output "<tmpdir>/codex-vote-output.txt" --timeout 1200 -- \
  codex exec --full-auto -C "$PWD" $("${CLAUDE_PLUGIN_ROOT}/scripts/agent-model-args.sh" --tool codex --with-effort) \
    --output-last-message "<tmpdir>/codex-vote-output.txt" \
    "<voter prompt with ballot>. Work at your maximum reasoning effort level."
```

Use `run_in_background: true` and `timeout: 1260000`.

**Codex voter replacement** (if `codex_available` is false): Launch a Claude subagent voter via the Agent tool with the voter prompt. This replacement ensures the total voter count always remains 3.

**Claude voter**: Launch via Agent tool with the voter prompt.

Wait for external voter sentinels using `wait-for-reviewers.sh` (use the same tmpdir as the review phase — do not create a new temp directory for voting). Only include sentinel paths for voters that were actually launched:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/wait-for-reviewers.sh --timeout 1260 \
  "<tmpdir>/cursor-vote-output.txt.done" \
  "<tmpdir>/codex-vote-output.txt.done"
```

Use `timeout: 1260000` on the Bash tool call. **Do NOT** set `run_in_background: true` — this call must block. Note: voter output files use the `-vote-` infix to avoid collision with reviewer output files (`-plan-output` or `-output`).

**Collecting voter results**: Use `collect-agent-results.sh` to validate external voter outputs (same as for reviewer outputs). Parse `STATUS` and `FAILURE_REASON` for each voter. If a voter fails (`STATUS != OK`), print: `**⚠ <Voter> voter failed — <FAILURE_REASON>. Proceeding with <N> voters (<remaining voter names>).**` Always include the `FAILURE_REASON` so the user can see why the voter failed (e.g., timeout, crash, empty output). Reduce the eligible voter count accordingly and apply the threshold rules above.

## Competition Scoring

After tallying votes, compute a score for each **original reviewer** (not voters):

| Vote Result | Points | Description |
|---|---|---|
| Finding accepted (2+ YES) | +1 | Reviewer's finding was validated by the panel |
| Finding got exactly 1 YES | 0 | Neutral — not enough support but not rejected |
| Finding got 0 YES but 1+ EXONERATE | 0 | Exonerated — legitimate concern, not actionable now |
| Finding got 0 YES and 0 EXONERATE | -1 | Rejected — finding was unanimously dismissed |

If a deduplicated finding was proposed by multiple reviewers (merged during deduplication), **all** contributing reviewers receive the same points for that finding.

## Scoreboard

After voting, print a scoreboard to the session:

```
## Reviewer Competition Scoreboard

| Reviewer | Findings | Accepted | Neutral (1 YES) | Exonerated (0 YES, 1+ EXON.) | Rejected (0 YES, 0 EXON.) | OOS Proposed | OOS Accepted | Score |
|----------|----------|----------|-----------------|-------------------------------|---------------------------|--------------|--------------|-------|
| _label1_ | 3        | 2        | 1               | 0                             | 0                         | 1            | 0            | +2    |
| _label2_ | 2        | 1        | 0               | 1                             | 0                         | 0            | 0            | +1    |
| _label3_ | 2        | 1        | 1               | 0                             | 0                         | 0            | 0            | +1    |

Attribution labels are skill-specific (e.g., `/design` uses `Code`/`Codex`/`Cursor`; `/review` uses `Structure`/`Correctness`/`Testing`/`Security`/`Edge-cases`/`Codex`). One row per independent reviewer. In future iterations, token allocation will be weighted proportionally to reviewer scores.
```

## Out-of-Scope Observations

Reviewers may return a second list of **out-of-scope observations** — pre-existing issues or concerns beyond the PR's scope that are worth surfacing for future attention. These are handled alongside in-scope findings but with different semantics:

### OOS on the Ballot

Out-of-scope items are deduplicated separately from in-scope findings and assigned IDs with an `OOS_` prefix (e.g., `OOS_1`, `OOS_2`). They are included on the same ballot as in-scope findings, labeled with `[OUT_OF_SCOPE]`:

```
OOS_1: [OUT_OF_SCOPE] Code — <description of pre-existing issue>
```

### OOS Vote Semantics

For out-of-scope items, the vote meanings are:
- **YES**: This observation deserves a GitHub issue for future attention.
- **NO**: Not worth tracking — the observation is trivial or incorrect.
- **EXONERATE**: Legitimate observation worth documenting, but not worth filing a GitHub issue.

If an OOS item receives 2+ YES votes, it is **accepted** and will be filed as a GitHub issue by `/implement`. In `/review` description mode, accepted OOS items are filed by `/review` Step 4b directly via `/umbrella` (default behavior; suppressed by `--no-issues`), not by `/implement`. Otherwise it remains an observation reported in the PR body.

**OOS items are never implemented in the current PR** — accepted OOS items result in issue creation only. This cleanly separates "fix now" (in-scope findings) from "fix later" (OOS observations).

### OOS Scoring

Out-of-scope items use **asymmetric reward-only scoring** — accepted OOS earns +1, and all other outcomes score 0 so reviewers are never penalized for surfacing observations in good faith:

| OOS Vote Result | Points | Description |
|---|---|---|
| OOS accepted (2+ YES) | +1 | Reviewer surfaced an issue worth tracking |
| OOS neutral (exactly 1 YES) | 0 | Insufficient support, but not dismissed |
| OOS exonerated (0 YES, 1+ EXONERATE) | 0 | Legitimate observation, but not worth an issue |
| OOS rejected (0 YES, 0 EXONERATE) | 0 | No penalty — reviewers are encouraged to surface observations freely |

### OOS Scoreboard

The scoreboard includes additional columns for OOS items:

```
| Reviewer | ... | OOS Proposed | OOS Accepted | ...
```

### OOS Reporting

OOS items are **not** written to `rejected-findings.md`. They follow a separate pipeline:

- **Accepted OOS items — reviewer voting path** (2+ YES): Written to an artifact file (`oos-accepted-design.md` or `oos-accepted-review.md`) in `$IMPLEMENT_TMPDIR` during the voting phase.
- **Accepted OOS items — main-agent dual-write path** (no vote required): Written to `oos-accepted-main-agent.md` in `$IMPLEMENT_TMPDIR` by the main agent at discovery time, every time it logs a `Pre-existing Code Issues` entry to `execution-issues.md`. This is the mechanical enforcement of `/implement`'s Follow-up Work Principle for the `Pre-existing Code Issues` category — see `/implement` SKILL.md → "Follow-up Work Principle" and "Mechanical enforcement of the principle: `Pre-existing Code Issues` dual-write". Durable follow-up work outside that category is not auto-filed via this path — the main agent files it manually via `/issue` per the principle. This path is unconditional and runs in every mode (`--quick`, `--auto`, `--merge`, `--draft`, `--no-merge`, or any future flag). It does NOT pass through a voting panel — main-agent classification is the policy gate.
- **Unified filing**: `/implement` Step 9a.1 reads all three artifacts, deduplicates across phases, and creates GitHub issues via `/issue` (batch mode) with LLM-based semantic duplicate detection against open + recently-closed GitHub issues. All three artifacts share the same `### OOS_N:` schema (Description, Reviewer, Vote tally, Phase). Main-agent items use Reviewer=`Main agent`, Vote tally=`N/A — auto-filed per policy`, Phase=`implement`.
- **Non-accepted OOS items**: Collected and reported in a dedicated `<details><summary>Out-of-Scope Observations</summary>` section in the PR body for future reference.

External reviewers (Codex, Cursor) **in diff mode** use single-list prompts and do not produce OOS items — their entire output is treated as in-scope findings. **In `/review` description mode**, external reviewers produce **dual-list output** matching the Claude subagent contract (with `### In-Scope Findings` and `### Out-of-Scope Observations` section headers) and contribute OOS items via voting — see `${CLAUDE_PLUGIN_ROOT}/skills/review/SKILL.md` Step 3a. Claude subagent reviewers (which use the dual-list templates from `reviewer-templates.md`) produce OOS items via voting in both modes; the main agent's dual-write path produces OOS items without voting.

## Zero Accepted Findings

If voting filters out **all** in-scope findings (every in-scope finding rejected by the panel), print: `**ℹ Voting panel rejected all in-scope findings. No changes to implement.**` and skip the implementation/revision step. Proceed directly to the rejected findings report. (OOS items accepted for issue filing are processed separately — by `/implement` Step 9a.1, or by `/review` Step 4b via `/umbrella` in description mode (default; suppressed by `--no-issues`) — and do not count as implementation work.)
