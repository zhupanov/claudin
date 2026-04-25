# test-run-research-planner.sh — Contract

**Purpose**: offline regression harness for `run-research-planner.sh`. Pins the validator's exit-code + stdout-token contract documented in `run-research-planner.md` against canned planner outputs covering the success boundaries, failure boundaries, and argument-error cases.

**Wiring**: invoked by `make lint` via the `test-run-research-planner` target in the root `Makefile`. NOT invoked at runtime by `/research` itself.

**Invocation**:

```bash
bash skills/research/scripts/test-run-research-planner.sh
```

Exits 0 if every case passes; exits 1 with a `FAIL: ...` diagnostic on stderr otherwise. The harness creates its own scratch directory under `$TMPDIR` and removes it on EXIT.

## Coverage

The harness exercises:

- **Success path** (count 2 / 3 / 4 plain; leading bullets `-` and `*` stripped; whitespace-only padding trimmed; empty lines dropped between question lines; prose preamble line dropped because it lacks `?`; numeric-prefix text preserved as a deliberate defensive simplification; control characters stripped).
- **Validation failure path** (empty file → `REASON=empty_input`; whitespace-only → `REASON=count_below_minimum`; count=1 → `REASON=count_below_minimum`; count=5 / count=6 → `REASON=count_above_maximum`; pure prose with no `?` → `REASON=count_below_minimum`).
- **Argument-error path** (missing `--raw` → `REASON=missing_arg`, exit 2; missing `--output` → `REASON=missing_arg`, exit 2; nonexistent `--raw` file → `REASON=empty_input`, exit 1; missing `--output` parent directory → `REASON=bad_path`, exit 2).
- **Output content** (after a known-good run, `--output` file contains exactly the retained question lines, one per line, with a trailing newline).

## Edit-in-sync rules

- **`REASON` token vocabulary** in `run-research-planner.md` MUST stay in lockstep with the regex patterns in this harness. Adding a new token (or renaming an existing one) without updating both files breaks `make lint`.
- **Validation rules** (count bounds, sanitization steps, question heuristic) — every change to the validator script's behavior MUST be reflected in a matching test case here, OR an existing case MUST be updated to cover the new rule.
- **Stdout schema** (`COUNT=` / `OUTPUT=` / `REASON=`) — any change to which lines appear on stdout (or in what order) MUST update both this harness and the orchestrator's stdout-parsing instruction in `skills/research/references/research-phase.md` Step 1.1.
