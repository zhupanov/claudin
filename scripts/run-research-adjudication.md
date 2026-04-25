# run-research-adjudication.sh contract

## Purpose

Pre-launch coordinator for `/research --adjudicate`. Wraps the three otherwise-consecutive Bash actions that precede the parallel 3-judge launch:

1. Empty-check on `$RESEARCH_TMPDIR/rejected-findings.md` — detects the no-rejections short-circuit.
2. Invoke `scripts/build-research-adjudication-ballot.sh` — produces the ballot file.
3. Run `scripts/check-reviewers.sh --probe` — refreshes judge availability immediately before the panel launch.

This consolidates three Bash tool calls into one per `skills/shared/skill-design-principles.md` Section III rule C ("No consecutive Bash tool calls — combine into a coordinator `.sh`"). The reference file `skills/research/references/adjudication-phase.md` Step 2.5.1 issues exactly one Bash tool call to this script and parses the structured stdout.

The coordinator does NOT launch the 3-judge panel itself — judge launches mix `Bash` (Cursor/Codex) and `Agent` (Claude code-reviewer subagent) tool calls, which cannot be issued from a shell script. The orchestrator owns the parallel launch step. The coordinator's scope ends at "ballot is built, fresh judge availability is known."

## Interface

```
run-research-adjudication.sh --rejected-findings <path> --tmpdir <path>
```

Both flags are required.

- `--rejected-findings <path>` — Source: `$RESEARCH_TMPDIR/rejected-findings.md` written unconditionally by `validation-phase.md` Sites A and B. Empty/absent file → `RAN=false` short-circuit.
- `--tmpdir <path>` — Session tmpdir (`$RESEARCH_TMPDIR`). Used as the working directory and as the ballot's destination directory. The ballot is written to `<tmpdir>/research-adjudication-ballot.txt`.

### Stdout contract

```
Always emitted:
  RAN=true|false

When RAN=true:
  BALLOT_PATH=<path>          # always <tmpdir>/research-adjudication-ballot.txt
  DECISION_COUNT=<N>          # number of DECISION_<N> entries on the ballot (>= 1)
  JUDGE_CODEX_AVAILABLE=true|false
  JUDGE_CURSOR_AVAILABLE=true|false

When RAN=false (short-circuit success):
  REASON=<single-line message>

On failure:
  RAN=false
  FAILED=true
  ERROR=<single-line message>
```

`RAN=false` short-circuit reasons (informational; not failures):

- `rejected-findings file does not exist` — Site A and Site B never captured anything (no orchestrator rejections occurred this session).
- `rejected-findings file is empty` — file exists but is zero-byte.
- `rejected-findings file has no parseable blocks` — file is non-empty but contains no `### REJECTED_FINDING_<N>` headers.
- `ballot builder produced 0 decisions (input blocks were incomplete)` — file had headers but every block was structurally incomplete (missing Reviewer, Finding, or Rejection rationale field).

### Exit codes

- `0` — Success on either path (`RAN=true` OR `RAN=false` short-circuit).
- `1` — Invocation / usage error (missing flag, unknown argument).
- `2` — I/O failure or downstream-script failure (input doesn't exist, ballot builder exits non-zero, probe helper exits non-zero, sibling helper missing or not executable).

## Two-key rule for judge availability

Per `skills/shared/external-reviewers.md`'s Binary Check and Health Probe section, a tool is launch-eligible only when BOTH `*_AVAILABLE=true` (binary on PATH) AND `*_HEALTHY=true` (passed the trivial health probe). The coordinator applies this rule when emitting `JUDGE_CODEX_AVAILABLE` and `JUDGE_CURSOR_AVAILABLE`, so callers never need to combine the two raw probe outputs.

A tool that is installed but unhealthy (`*_HEALTHY=false`) is treated as **unavailable** for judge-panel purposes and replaced by a Claude code-reviewer subagent per `dialectic-protocol.md`'s replacement-first pattern.

## Edit-in-sync invariants

- The empty-check semantics (cases enumerated above) must stay aligned with the schema written by `validation-phase.md` Sites A and B. If those sites change the block header format from `### REJECTED_FINDING_<N>`, update the grep pattern here AND in `scripts/build-research-adjudication-ballot.sh`'s parser.
- The two-key rule mirrors `session-setup.sh`'s pre-launch derivation. If `external-reviewers.md`'s probe semantics change (e.g., a new `*_DEGRADED` axis is added), update this script in lockstep.
- The ballot output filename `research-adjudication-ballot.txt` is referenced by `skills/research/references/adjudication-phase.md` (judge prompts must reference this filename, NOT the design-context `dialectic-ballot.txt`). Renaming this filename requires a same-PR update to `adjudication-phase.md`.

## Test harness

This coordinator is exercised end-to-end by the offline harness `scripts/test-research-adjudication.sh` via fixture inputs. The harness validates:
- Empty-input short-circuit (`RAN=false` with the expected `REASON=` message).
- Successful path (`RAN=true` with a non-empty `BALLOT_PATH` and `DECISION_COUNT > 0`).
- Probe-helper failure handling (when the probe binary is unavailable).

Wired into `make test-harnesses` (NOT `make lint`, NOT `make smoke-dialectic`).
