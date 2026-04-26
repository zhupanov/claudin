# helpers.sh — sibling contract

Consolidated `/umbrella` helpers, exposed as three subcommands.

## `check-cycle --existing-edges FILE --candidate BLOCKER:BLOCKED`

Pure-logic DAG cycle test. `FILE` is a TSV of `<blocker>\t<blocked>` edges. The candidate adds `BLOCKER -> BLOCKED`. Stdout: `CYCLE=true|false`. Self-loops (`BLOCKER == BLOCKED`) are always cycles. The forward-reachability check from the new BLOCKED node looks for the new BLOCKER as an ancestor; reaching it means the new edge would close a cycle. Independently testable via `test-helpers.sh`.

## `wire-dag --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run]`

Coordinator: feature-detect the GitHub blocked-by dependency API (probe `/repos/<repo>/issues/<umbrella>/dependencies/blocked_by`), enumerate existing edges per child, cycle-check each proposed edge, add survivors, then post back-link comments on each child unless the umbrella is already in the child's blocked_by list (native umbrella relationship).

Stdout grammar: `EDGES_ADDED=<N>`, per-edge `EDGE_<j>_BLOCKER=<N>` / `EDGE_<j>_BLOCKED=<M>`, `EDGES_REJECTED_CYCLE=<N>`, `EDGES_SKIPPED_EXISTING=<N>`, `EDGES_SKIPPED_API_UNAVAILABLE=<N>`, `BACKLINKS_POSTED=<N>`, `BACKLINKS_SKIPPED_NATIVE=<N>`. Stderr: warning when the API surface is unavailable repo-wide (fail-open — back-links via comments still run).

## `emit-output --kv-file FILE`

Validate the LLM-supplied `output.kv` (no malformed lines, no duplicate keys) and stream it to stdout. Defense-in-depth on top of the `SKILL.md` Step 4 grammar. For `emit-output` specifically, stderr is reserved for parse/validation/usage errors only — the human summary breadcrumb is emitted by the orchestrator at SKILL.md Step 4 (single emission point), not by this script. (This scoping is local to `emit-output`; `wire-dag`'s documented stderr warning behavior above is unaffected.)

### Edit-in-sync rules

Changes to any subcommand's stdout grammar require a same-PR update to `SKILL.md` Steps 3B.4 (`wire-dag`) and 4 (`emit-output`). Cycle-check semantic changes require regenerating the `test-helpers.sh` harness expectations.

### GitHub dependency-API note

The `/repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by` REST endpoint surface evolved during 2024-2026 (sub-issues vs blocked-by, REST vs GraphQL surfaces). `wire-dag` is fail-open by design: when the probe fails, all proposed edges land in `EDGES_SKIPPED_API_UNAVAILABLE` and back-links via plain `gh issue comment` still proceed.
