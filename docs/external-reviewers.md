# External Reviewers

Codex and Cursor participate alongside Claude subagents as both reviewers and voters in the Larch workflow. This document covers the shared integration procedures.

## Availability Checks

At the start of each skill, a binary check determines which external tools are installed:

- If **Codex** is not found, a warning is printed and the skill proceeds without it
- If **Cursor** is not found, a warning is printed and the skill proceeds without it

Skills gracefully degrade when external tools are unavailable. When Codex or Cursor is not found, Claude replacement subagents fill their slots to maintain per-skill lane counts across most phases. The counts are: 3 for plan/code review (1 Claude + 1 Codex + 1 Cursor) and `/research --scale=standard` (default — both phases); 5 for `/research --scale=deep` (research phase = Claude inline + 2 Cursor slots + 2 Codex slots with diversified angle prompts; validation phase = 3 Claude + 1 Cursor + 1 Codex with `Code-Sec` / `Code-Arch` lane-local emphasis on the unified Code Reviewer archetype) and the `/design` sketch phase; K=3 homogeneous Claude lanes for `/research --quick` (no externals to begin with — the K=3 lanes are all Claude subagents launched via the Agent tool, validation phase skipped); 3 for voting panels and for the `/design` dialectic judge panel. `/loop-review` post-overhaul (PR #434) delegates to per-slice `/review --slice-file` subprocesses — its per-slice lane counts are governed by `/review`'s standard 3-lane Voting Protocol panel, not by a top-level `/loop-review` panel. Voting uses a step-function threshold: 3 voters require 2+ YES votes, 2 voters require unanimous YES, and fewer than 2 eligible voters causes voting to be skipped with all findings accepted automatically.

**Exception: dialectic debate buckets (`/design` Step 2a.5) do NOT use replacement-first.** When the assigned external tool (Cursor for odd-indexed decisions, Codex for even) is unavailable, the bucket is **skipped entirely** and a `Disposition: bucket-skipped` resolution is written — Claude subagents are never substituted into the debate path. This carve-out applies only to the **debate execution phase** of dialectic; the post-debate **judge panel** uses replacement-first normally. See [Dialectic-specific behavior](#dialectic-specific-behavior) below and `skills/shared/dialectic-protocol.md` for the full rationale.

## Trust boundary (filesystem access)

External reviewers in `/research` and `/loop-review` launch directly against the working tree (`cursor agent ... --workspace "$PWD"`, `codex exec --full-auto -C "$PWD"`) and inherit the user's filesystem privileges. The reviewer prompt asks them not to modify files, but this is a behavioral constraint, not a sandbox. The `/research` skill carries a skill-scoped `PreToolUse` hook (`scripts/deny-edit-write.sh`) that mechanically guards Claude's own `Edit | Write | NotebookEdit` tool surface to canonical `/tmp` only; the hook does **not** cover Bash or subprocess-spawned external reviewers. `/loop-review` has no skill-scoped hook — its orchestrator is expected to write the repo (filing issues via `/issue`, writing session artifacts). See [`SECURITY.md` § External reviewer write surface in /research and /loop-review](../SECURITY.md#external-reviewer-write-surface-in-research-and-loop-review) for the full trust-model framing and [`docs/review-agents.md` § External reviewer trust boundary](review-agents.md#external-reviewer-trust-boundary-skills-using-cursor--codex-against-pwd) for the skill-author-facing summary.

## Launching External Reviewers

External reviewers are launched via the `run-external-reviewer.sh` wrapper script, which provides:

- **Timeout enforcement** — Kills the process after a configurable timeout
- **Sentinel file creation** — Writes a `.done` file containing the exit code when the process completes
- **Output capture** — Captures stdout to a specified output file
- **Elapsed time tracking** — Reports how long the review took

During review and voting phases, reviewers are launched with `run_in_background: true` so they run concurrently with other work. (Negotiation rounds in `/research` and `/loop-review` run synchronously.)

## Launch Order

External reviewers are always launched in a specific order to maximize parallelism — **slowest first**:

1. **Cursor** (slowest) — launched first
2. **Codex** — launched second
3. **Claude subagents** (fastest) — launched last

All launches happen in a single message to ensure true parallel execution.

## Sentinel File Monitoring

The wrapper script writes a `.done` sentinel file when the process completes. This is the only reliable way to detect completion:

- **Do not read output files until the sentinel exists** — Cursor buffers all stdout until exit, so its output file is empty until the process finishes
- **Poll for sentinels** using the `wait-for-reviewers.sh` script, which checks every 5 seconds and prints compact progress dots
- Sentinel files contain the exit code (e.g., `0` for success)

## Output Validation

After the sentinel file exists, the output is validated:

1. Read the output file
2. Check that it is non-empty and contains substantive content (numbered findings or `NO_ISSUES_FOUND`)
3. If empty despite exit code 0, **retry once** with a fresh invocation (output file gets a `-retry` suffix)
4. If still empty after retry, or if the exit code is non-zero, print a warning and proceed without that reviewer's findings

## Timeout Handling

External reviewers have configurable timeouts (typically 600-900 seconds). If a reviewer exceeds its timeout:

- The process is killed by the wrapper script
- The sentinel file records a non-zero exit code
- A warning is printed and the skill proceeds without that reviewer

## Roles Across the Workflow

External reviewers participate in multiple phases:

| Phase | Role | Skills | Fallback behavior |
|---|---|---|---|
| [Collaborative sketches](collaborative-sketches.md) | Propose architectural approaches | `/design` | Replacement-first (Claude subagent fills slot) |
| Plan review | Review implementation plans | `/design` | Replacement-first |
| Code review | Review code changes | `/review` | Replacement-first |
| [Voting](voting-process.md) | Vote on findings | `/design`, `/review` | Replacement-first |
| Negotiation | Multi-round dispute resolution | `/research`, `/loop-review` | Replacement-first |
| **Dialectic debate** (`/design` Step 2a.5) | Defend / attack contested decisions | `/design` | **Bucket skipped — no Claude substitution** |
| Dialectic judge panel (`/design` Step 2a.5) | Adjudicate between pre-authored defenses | `/design` | Replacement-first (panel stays at 3) |

## Dialectic-specific behavior

`/design` Step 2a.5 runs a **dialectic debate + judge panel** phase whose fallback semantics differ from every other reviewer phase. Both the debate phase and the judge panel are specified in detail at `skills/shared/dialectic-protocol.md`; the integration points with the shared external-reviewer infrastructure are:

1. **Debaters never fall back to Claude** (carve-out): Cursor runs both sides of odd-indexed decisions; Codex runs both sides of even-indexed decisions; if the assigned tool is unavailable at launch time, the bucket is skipped and a `Disposition: bucket-skipped` resolution is written — the synthesis decision stands for that point. This is intentional divergence (see GitHub issue #98): debater outputs are adversarial prose whose style can leak tool identity; substituting a Claude subagent into the debate path would bias the downstream judge panel.
2. **Dialectic-scoped shadow flags**: the dialectic phase uses `dialectic_codex_available` / `dialectic_cursor_available` flags snapshotted at entry. These flags are **never written back** to the orchestrator-wide `codex_available` / `cursor_available` flags. A Cursor or Codex timeout during a dialectic debate therefore does not lock that tool out of Step 3 plan review.
3. **`--write-health /dev/null`**: every `collect-reviewer-results.sh` invocation in the dialectic phase (both debate collection and judge collection) passes `--write-health /dev/null` so the dialectic phase **never updates** `${SESSION_ENV_PATH}.health`. Debate-time failures stay scoped to this phase.
4. **Judge panel uses replacement-first**: when Cursor or Codex is unhealthy at judge launch time, a Claude Code Reviewer subagent replaces that slot so the panel is always 3 judges. Judges adjudicate between pre-authored defenses and don't write adversarial prose, so the debater carve-out doesn't apply here.
5. **Judge-phase health re-probe**: `scripts/check-reviewers.sh --probe` is run synchronously immediately before launching judges. Debate-time failures must not lock a tool out of the judge role — judgment happens minutes after debate, and tool state can recover.

### Regression guard

`scripts/dialectic-smoke-test.sh` is the offline regression guard for the dialectic parser, tally rules, and structural invariants documented in `skills/shared/dialectic-protocol.md`. Fixtures live under `tests/fixtures/dialectic/`. Run locally via `make smoke-dialectic`; CI runs the same command in the `smoke-dialectic` job. When changing the protocol's Parser tolerance or Threshold Rules sections, update the smoke test and/or fixtures in the same PR.
