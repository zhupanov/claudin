# test-token-tally.sh contract

**Sibling script**: `scripts/test-token-tally.sh`.

**Purpose**: Offline regression harness for `scripts/token-tally.sh`. Asserts byte-exact behavior of all three subcommands (`write`, `report`, `check-budget`) plus contract behavior under malformed inputs, path-validation, missing directories, and unknown-token handling.

**Sole consumer**: invoked by the Makefile `test-token-tally:` target (and transitively by `test-harnesses:`, which CI runs).

## Test cases

| # | Subcommand | Scenario | Assertion |
|---|------------|----------|-----------|
| 1 | report | empty dir | stdout contains "no measurements available" |
| 2 | report | 4 sidecars across 3 phases | aggregate total = sum, all phase rows present, "## Token Spend" header present |
| 3 | report | `--planner true` with planner sidecar | planner sidecar counted in research total |
| 4 | report | mix of measured + `TOTAL_TOKENS=unknown` | total reflects only measured; coverage line includes "unmeasur" fragment |
| 5 | report | `LARCH_TOKEN_RATE_PER_M=15` env set | `$` column appears in output |
| 6 | report | `LARCH_TOKEN_RATE_PER_M` unset | `$` column absent |
| 7 | check-budget | sum < budget | exit 0 |
| 8 | check-budget | sum > budget | exit 2 with `BUDGET_EXCEEDED=true MEASURED=<N>` |
| 9 | write | malformed `--total-tokens=foo` | exit 1 |
| 10 | write | `--total-tokens=unknown` | exit 0; sidecar contains `TOTAL_TOKENS=unknown` |
| 11 | (all) | `--dir /home/nonsense` (non-/tmp path) | exit 1 across `write` / `report` / `check-budget` |
| 12 | report | dir removed before invocation | exit 0; stdout contains "token telemetry unavailable" AND subtitle "Claude tokens only" (consistency with populated path — review FINDING_4) |
| 6b | report | `LARCH_TOKEN_RATE_PER_M=0` and `0.0` | `$` column omitted in both cases (review FINDING_1 — zero is treated as unset per docs) |
| 13 | report | standard scale with no research sidecars | Research row still renders with "all unmeasurable" framing (review FINDING_9 — phase rows render from phase state, not sidecar presence) |
| 14 | report | `--budget-aborted true` + `--adjudicate true` + no adjudication sidecars | Adjudication row reads "skipped … aborted before Step 2.5" (review FINDING_10) |
| 15 | (all) | `--dir /tmp/../etc` (path-escape attempt) | exit 1 (review FINDING_2 — `..` segments rejected) |
| 16 | check-budget | `--dir` points at non-existent directory | success line includes `BUDGET=<N>` (review FINDING_3 — uniform success-line shape across missing-dir and present-dir paths) |

Total: 34 individual assertions across 17 test cases (12 original + 5 new from review-round-1 fixes; Test 6 split into 6 and 6b; T15 covers all 3 subcommands per round-2 review nit).

## Invariants

- All test fixtures use `mktemp -d "/tmp/test-token-tally.XXXXXX"` to satisfy the `--dir` path-prefix guard. Fixtures are removed at the end of each test (`rm -rf "$T"`).
- The harness uses three assertion helpers: `assert_exit_code`, `assert_stdout_contains`, `assert_stdout_not_contains`. Failures collect into `FAIL_DETAILS` and print at the end.
- Exit code 1 on any failure; exit code 0 only when all assertions pass.

## Wiring

Run via `make test-token-tally` (single harness) or `make test-harnesses` (full CI batch). The harness must be listed in three places in the Makefile:

1. The `.PHONY` declaration line (top of file).
2. The `test-harnesses:` prerequisite list (CI target).
3. A dedicated `test-token-tally:` recipe target with `bash scripts/test-token-tally.sh`.

## Edit-in-sync rules

Any change to `token-tally.sh`'s subcommand interface, sidecar schema, or path-validation behavior MUST be reflected in this harness in the same PR. If the harness's pass count changes, update the count in this contract.
