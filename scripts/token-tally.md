# token-tally.sh contract

**Sibling script**: `scripts/token-tally.sh`.

**Purpose**: Per-run token-cost telemetry helper for `/research`. Implements the three subcommands consumed by `/research` Step 4 and the between-phase budget gates: `write` (record one per-lane sidecar), `report` (render the `## Token Spend` section), and `check-budget` (sum measured tokens, exit 2 on overage). See GitHub issue #518 for the umbrella feature; #512 for the umbrella tracking issue.

**Sole owner of the `## Token Spend` section**: `report` emits the full section (header + body). SKILL.md just calls the script and prints its stdout. Do NOT emit a duplicate `## Token Spend` header from the caller — designating one owner avoids drift if the script's section structure later changes.

## Subcommands

### `write --phase <p> --lane <l> --tool <t> --total-tokens <N|unknown> --dir <d>`

Records one per-lane sidecar file at `<d>/lane-tokens-<phase>-<safe-lane>.txt`, where `<safe-lane>` is the lane label lowercased with non-alphanumeric runs replaced by `-`.

- `--phase` must be `research`, `validation`, or `adjudication`. Other values exit 1.
- `--lane` is the stable slot name (e.g., `Cursor`, `Codex`, `Code`, `Code-Sec`, `Code-Arch`, `planner`). Slot names mirror the Step 3 reviewer-attribution conventions in `skills/research/SKILL.md` (`render-deep-lane-status.sh` line 247) — kept stable across pre-launch fallbacks AND runtime-timeout replacements.
- `--tool` is currently always `claude` (only Claude subagent invocations have measurable usage). Reserved for future expansion if external tools ever expose token counts.
- `--total-tokens` is a non-negative integer OR the literal `unknown`. Other values exit 1. Use `unknown` when the orchestrator could not parse `total_tokens:` from the Agent tool's `<usage>` block.
- `--dir` MUST be under `/tmp/` or `/private/tmp/`. Any other path exits 1 (defense in depth; mirrors `cleanup-tmpdir.sh:36-40`).

Sidecar schema:

```
PHASE=<phase>
LANE=<lane>
TOOL=<tool>
TOTAL_TOKENS=<integer or unknown>
```

### `report --dir <d> --scale <quick|standard|deep> --adjudicate <true|false> [--planner true|false] [--budget-aborted true|false]`

Globs `<d>/lane-tokens-*.txt`, aggregates by phase, and emits the `## Token Spend` section to stdout.

- `--dir` MUST be under `/tmp/` or `/private/tmp/`. If the directory does not exist (e.g., already cleaned by `cleanup-tmpdir.sh`), the script emits a graceful placeholder (`_(token telemetry unavailable: $RESEARCH_TMPDIR was already removed)_`) and exits 0 — `/research` Step 4's reorder fix prevents this in the normal path, but the placeholder keeps `report` safe to call from any control-flow position.
- `--scale` informs zero-measurement labelling for quick mode (where the only research-phase agent is Claude inline, which is unmeasurable).
- `--adjudicate` selects whether the Adjudication row is rendered as a separate phase or as `skipped`.
- `--planner` (default `false`): currently informational only. The planner subagent writes its own sidecar via `write --phase research --lane planner`, so `report` picks it up automatically through the glob — `--planner` is reserved for future per-phase formatting tweaks.
- `--budget-aborted` (default `false`): when `true`, appends `**Run aborted: --token-budget exceeded.**` to the report. Used by SKILL.md Step 4's budget-abort branch.

**Cost column** (optional `$` column): rendered only when `LARCH_TOKEN_RATE_PER_M` is set to a positive number (USD per million tokens). When unset, malformed, or zero, the `$` column is omitted entirely. Both `total=` and the per-phase rows show the cost. Cost is computed via `awk` floating-point: `(total * rate) / 1_000_000`. Per /research issue #518's dialectic resolution, this is a single combined rate (Anthropic's Agent-tool API returns only `total_tokens`, no input/output split — the `LARCH_TOKEN_RATE_INPUT_PER_M` / `LARCH_TOKEN_RATE_OUTPUT_PER_M` aspirational env vars from the issue prompt collapse to one variable v1).

**Coverage line**: every phase row includes a coverage parenthetical: `(<lane-count> lanes, <measured> measured[, <unknown> unmeasurable])`. The unmeasurable fragment is omitted when zero.

### `check-budget --budget <N> --dir <d>`

Sums `TOTAL_TOKENS` across all sidecars in `<d>` (skipping `unknown` values) and compares to `<N>`. Exit codes:

- `0`: under budget. Stdout: `BUDGET_EXCEEDED=false MEASURED=<N> UNKNOWN_LANES=<count> BUDGET=<N>`.
- `2`: over budget. Stdout: `BUDGET_EXCEEDED=true MEASURED=<N> UNKNOWN_LANES=<count> BUDGET=<N>`.
- `1`: validation failure (malformed `--budget`, non-`/tmp` `--dir`, etc.). Stderr carries diagnostic.

`<N>` MUST be a positive integer; `<= 0` exits 1. `--dir` MUST be under `/tmp/`.

**Caller integration**: SKILL.md captures the exit code via `... ; rc=$?` or `... || rc=$?` to avoid `set -e` propagation aborting on exit 2 (which is the budget-overage signal, not an error). On `rc=2`, SKILL.md sets `BUDGET_ABORTED=true`, skips remaining phases, jumps to Step 4. See `skills/research/SKILL.md` budget-gate sites for the exact pattern.

**Unknown-lane semantics**: `TOTAL_TOKENS=unknown` is treated as 0-contribution to the sum. This is the documented design trade-off (per /design Step 3 FINDING_5): a parser-broken `<usage>` block does NOT silently fail the gate — the unknown count is surfaced explicitly in the start-of-run notice (`budget enforced over N measured lanes; M unmeasurable lanes excluded`) AND in the budget-overage message. Operators can audit the unmeasurable lanes via the sidecar files directly when in doubt.

## Sidecar file naming

`<dir>/lane-tokens-<phase>-<safe-lane>.txt` where `<safe-lane>` is `lane | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g'`. Multi-lane filenames in deep mode (e.g., `code-sec`) collapse to single-token `code-sec` after sanitization. Repeated `write` calls for the same `<phase>+<lane>` overwrite — the orchestrator's last call for a given lane is the canonical reading.

## Path validation

All three subcommands validate `--dir` is under `/tmp/` or `/private/tmp/` (matching `cleanup-tmpdir.sh:36-40`). This is defense in depth: although the orchestrator only ever passes `$RESEARCH_TMPDIR` (always under `/tmp/`), a misinvocation or future caller mistake could otherwise glob and read filenames from any user-supplied directory. Reject early with exit 1.

## Test harness

`scripts/test-token-tally.sh` is the offline regression harness. Test cases:

1. `report` empty dir → "(no measurements available)" placeholder.
2. `report` populated fixtures across all 3 phases → expected aggregate.
3. `report` with planner sidecar → planner counted in research phase.
4. `report` with `unknown` sidecar → coverage line shows unmeasurable count.
5. `report` with `LARCH_TOKEN_RATE_PER_M` set → `$` column appears.
6. `report` without env var → `$` column omitted.
7. `check-budget` under → exit 0.
8. `check-budget` over → exit 2 with `BUDGET_EXCEEDED=true`.
9. `write` malformed `--total-tokens` → exit 1.
10. `write --total-tokens=unknown` → succeeds.
11. Path validation: `--dir /home/foo` → exit 1 across all subcommands.
12. `report` after dir removed → graceful placeholder.

Wired into Makefile via `.PHONY` line, the `test-harnesses:` prerequisite list, and a dedicated `test-token-tally:` recipe.

## Edit-in-sync rules

When editing `token-tally.sh`:

1. **Test harness**: update `scripts/test-token-tally.sh` to add or modify regression cases for new behavior. Run it locally before commit.
2. **SKILL.md and references**: `skills/research/SKILL.md` Step 0 / between-phase gates / Step 4 invoke `token-tally.sh`. The three reference files (`skills/research/references/research-phase.md`, `validation-phase.md`, `adjudication-phase.md`) call `write` after each Claude subagent return.
3. **Sidecar schema changes**: any new `KEY=` field or any rename requires updating both this contract and the test fixtures. The schema is small enough that a parallel parser in `report` and `check-budget` is acceptable; if the schema grows, consider extracting a shared parser sub-helper.
4. **Cost-column changes**: `LARCH_TOKEN_RATE_PER_M` is documented in `docs/configuration-and-permissions.md`; any addition of input/output split (when Agent tool exposes it) must update both this contract AND the docs entry.
