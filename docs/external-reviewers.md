# External Reviewers

Codex and Cursor participate alongside Claude subagents as both reviewers and voters in the Claudin2 workflow. This document covers the shared integration procedures.

## Availability Checks

At the start of each skill, a binary check determines which external tools are installed:

- If **Codex** is not found, a warning is printed and the skill proceeds without it
- If **Cursor** is not found, a warning is printed and the skill proceeds without it

Skills gracefully degrade when external tools are unavailable. During [sketch and research phases](collaborative-sketches.md), Claude replacement agents are used to maintain the 5-agent invariant. During review and voting phases, the skill simply operates with fewer participants and adjusts voting thresholds accordingly.

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

| Phase | Role | Skills |
|---|---|---|
| [Collaborative sketches](collaborative-sketches.md) | Propose architectural approaches | `/design`, `/research` |
| Plan review | Review implementation plans | `/design` |
| Code review | Review code changes | `/review` |
| [Voting](voting-process.md) | Vote on findings | `/design`, `/review` |
| Negotiation | Multi-round dispute resolution | `/research`, `/loop-review` |
