# External Reviewers

Codex and Cursor join Claude subagents as reviewers and voters in Larch workflow. Doc cover shared integration.

## Availability Checks

Start of each skill, binary check find which external tools installed:

- **Codex** not found → warning printed, skill proceed without
- **Cursor** not found → warning printed, skill proceed without

Skills degrade gracefully when external tools gone. When Codex or Cursor missing, Claude replacement subagents fill slots to keep per-skill lane counts across most phases. Counts: 3 for plan/code review (1 Claude + 1 Codex + 1 Cursor), `/research` (both phases), `/loop-review` (Negotiation Protocol, per slice); 5 for `/design` sketch phase; 3 for voting panels and `/design` dialectic judge panel. Voting use step-function threshold: 3 voters need 2+ YES, 2 voters need unanimous YES, fewer than 2 eligible voters → voting skipped, all findings auto-accepted.

**Exception: dialectic debate buckets (`/design` Step 2a.5) do NOT use replacement-first.** When assigned external tool (Cursor for odd-indexed decisions, Codex for even) gone, bucket **skipped entirely** and `Disposition: bucket-skipped` resolution written — Claude subagents never substituted into debate path. Carve-out apply only to **debate execution phase** of dialectic; post-debate **judge panel** use replacement-first normal. See [Dialectic-specific behavior](#dialectic-specific-behavior) below and `skills/shared/dialectic-protocol.md` for full reason.

## Launching External Reviewers

External reviewers launched via `run-external-reviewer.sh` wrapper script. Give:

- **Timeout enforcement** — kill process after configurable timeout
- **Sentinel file creation** — write `.done` file with exit code when process done
- **Output capture** — capture stdout to output file
- **Elapsed time tracking** — report how long review took

During review and voting phases, reviewers launched with `run_in_background: true` so run concurrent with other work. (Negotiation rounds in `/research` and `/loop-review` run sync.)

## Launch Order

External reviewers always launched in specific order to max parallelism — **slowest first**:

1. **Cursor** (slowest) — launched first
2. **Codex** — launched second
3. **Claude subagents** (fastest) — launched last

All launches in single message for true parallel execution.

## Sentinel File Monitoring

Wrapper script write `.done` sentinel file when process done. Only reliable way detect completion:

- **No read output files until sentinel exist** — Cursor buffer all stdout until exit, output file empty until process finish
- **Poll sentinels** with `wait-for-reviewers.sh` script, check every 5 seconds, print compact progress dots
- Sentinel files hold exit code (e.g., `0` for success)

## Output Validation

After sentinel file exist, output validated:

1. Read output file
2. Check non-empty and hold substantive content (numbered findings or `NO_ISSUES_FOUND`)
3. If empty despite exit code 0, **retry once** with fresh invocation (output file get `-retry` suffix)
4. If still empty after retry, or exit code non-zero, print warning and proceed without that reviewer findings

## Timeout Handling

External reviewers have configurable timeouts (typical 600-900 seconds). If reviewer exceed timeout:

- Process killed by wrapper script
- Sentinel file record non-zero exit code
- Warning printed, skill proceed without that reviewer

## Roles Across the Workflow

External reviewers join multiple phases:

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

`/design` Step 2a.5 run **dialectic debate + judge panel** phase. Fallback semantics differ from every other reviewer phase. Both debate phase and judge panel specified in detail at `skills/shared/dialectic-protocol.md`. Integration points with shared external-reviewer infrastructure:

1. **Debaters never fall back to Claude** (carve-out): Cursor run both sides of odd-indexed decisions; Codex run both sides of even-indexed decisions; if assigned tool gone at launch, bucket skipped, `Disposition: bucket-skipped` resolution written — synthesis decision stand for that point. Intentional divergence (see GitHub issue #98): debater outputs adversarial prose whose style leak tool identity; sub Claude subagent into debate path would bias downstream judge panel.
2. **Dialectic-scoped shadow flags**: dialectic phase use `dialectic_codex_available` / `dialectic_cursor_available` flags snapshotted at entry. These flags **never written back** to orchestrator-wide `codex_available` / `cursor_available` flags. Cursor or Codex timeout during dialectic debate therefore no lock that tool out of Step 3 plan review.
3. **`--write-health /dev/null`**: every `collect-reviewer-results.sh` call in dialectic phase (both debate collection and judge collection) pass `--write-health /dev/null` so dialectic phase **never update** `${SESSION_ENV_PATH}.health`. Debate-time failures stay scoped to this phase.
4. **Judge panel use replacement-first**: when Cursor or Codex unhealthy at judge launch, Claude Code Reviewer subagent replace that slot so panel always 3 judges. Judges adjudicate between pre-authored defenses and no write adversarial prose, so debater carve-out no apply here.
5. **Judge-phase health re-probe**: `scripts/check-reviewers.sh --probe` run sync right before launching judges. Debate-time failures must not lock tool out of judge role — judgment happen minutes after debate, tool state can recover.

### Regression guard

`scripts/dialectic-smoke-test.sh` is offline regression guard for dialectic parser, tally rules, and structural invariants in `skills/shared/dialectic-protocol.md`. Fixtures live under `tests/fixtures/dialectic/`. Run local via `make smoke-dialectic`; CI run same command in `smoke-dialectic` job. When change protocol Parser tolerance or Threshold Rules sections, update smoke test and/or fixtures in same PR.
