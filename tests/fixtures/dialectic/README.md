# Dialectic Smoke Test Fixtures

Offline golden fixtures for `scripts/dialectic-smoke-test.sh` (via `make smoke-dialectic`). Each fixture hit specific protocol branch of `/design` Step 2a.5.

## Protocol coverage matrix

| Fixture | Protocol sections covered |
|---|---|
| `happy-path-5-decisions/` | Parser tolerance § (full parse); Threshold Rules § (3 voters → 2+ majority and 3-0 unanimous); Attribution stripping § (ballot anonymity); Ballot Format § (5-decision cap boundary) |
| `two-judge-quorum/` | Parser tolerance § (STATUS=ERROR whole-output ineligibility, `dialectic-protocol.md` "Eligible" note under Threshold Rules); Threshold Rules § (2 voters unanimous → `voted` AND 2 voters 1-1 tie → `fallback-to-synthesis`) |
| `bucket-skipped/` | Disposition Enum § (`bucket-skipped`); Ballot Format § (ballot omits skipped decisions) |
| `over-cap/` | Disposition Enum § (`over-cap`); Step 2a.5 top-`min(5, N)` cap |
| `fallback-quorum-failure/` | Parser tolerance § (5-required-tags gate); Disposition Enum § (`fallback-to-synthesis`) |
| `parser-tolerance/` | Parser tolerance § (em-dash OR hyphen rationale separator; duplicate `DECISION_N` line → first valid + warning; missing `DECISION_N` line → per-decision abstention only, not whole-output ineligibility) |

## Manifest schema (`expected.txt`)

Each fixture `expected.txt` declare expected parser outcome for every `DECISION_N` present:

```
# comments start with #
skip_debater_validation=true        # optional; opt out of structural debater check
skip_ballot_anonymity=true          # optional; opt out of ballot attribution-leak check

DECISION_1 expected_disposition=voted expected_tally=THESIS=3,ANTI_THESIS=0
DECISION_2 expected_disposition=fallback-to-synthesis expected_tally=THESIS=1,ANTI_THESIS=1
DECISION_3 expected_disposition=bucket-skipped
```

- `expected_disposition` ∈ `{voted, fallback-to-synthesis, bucket-skipped, over-cap}` — four canonical values per `skills/shared/dialectic-protocol.md` Consumer Contract.
- `expected_tally` required when `expected_disposition=voted`; optional else (for `fallback-to-synthesis` may match actual 2-voter 1-1 case).
- For `bucket-skipped` and `over-cap`, smoke test accept 0/0 no-vote computed state as equivalent (orchestrator-level decisions not derivable from judge votes alone).

## Non-runtime surface

`tests/` **not** part of plugin runtime surface (AGENTS.md declare `skills/`, `agents/`, `hooks/`, `scripts/`, `.claude-plugin/` as runtime; "everything else is supplementary"). Fixtures pure data; edit them no effect on consumer behavior.
