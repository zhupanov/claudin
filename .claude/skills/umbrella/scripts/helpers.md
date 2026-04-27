# helpers.sh — sibling contract

Consolidated `/umbrella` helpers, exposed as three subcommands.

## `check-cycle --existing-edges FILE --candidate BLOCKER:BLOCKED`

Pure-logic DAG cycle test. `FILE` is a TSV of `<blocker>\t<blocked>` edges. The candidate adds `BLOCKER -> BLOCKED`. Stdout: `CYCLE=true|false`. Self-loops (`BLOCKER == BLOCKED`) are always cycles. The forward-reachability check from the new BLOCKED node looks for the new BLOCKER as an ancestor; reaching it means the new edge would close a cycle. Independently testable via `test-helpers.sh`.

## `wire-dag --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run]`

Coordinator: feature-detect the GitHub blocked-by dependency API (probe `/repos/<repo>/issues/<umbrella>/dependencies/blocked_by`), enumerate existing edges per child, cycle-check each proposed edge, add survivors, then post back-link comments on each child unless the umbrella is already in the child's blocked_by list (native umbrella relationship).

Per-edge POST body uses the canonical `{"issue_id": <internal numeric id>}` shape matching `skills/issue/scripts/add-blocked-by.sh:170-183`. Blocker internal ids are resolved via `gh api /repos/<repo>/issues/<N> --jq .id` and cached per run.

Stdout grammar: `EDGES_ADDED=<N>`, per-edge `EDGE_<j>_BLOCKER=<N>` / `EDGE_<j>_BLOCKED=<M>`, `EDGES_REJECTED_CYCLE=<N>`, `EDGES_SKIPPED_EXISTING=<N>` (already-present edges, including idempotent 422 already-exists responses per `add-blocked-by.sh:193-196`), `EDGES_SKIPPED_API_UNAVAILABLE=<N>` (repo-wide probe failure OR per-edge feature-missing 404 — both mean "the GitHub dependency surface is not available here"), `EDGES_FAILED=<N>` (per-edge operational failures: rate-limit, permission denied, ambiguous 404, other 4xx, 5xx, request-shape mismatches, blocker-id lookup failure, network — failures that do NOT match the feature-missing fingerprint), `BACKLINKS_POSTED=<N>`, `BACKLINKS_SKIPPED_NATIVE=<N>`.

Stderr: one warning when the API surface is unavailable repo-wide (fail-open — back-links via comments still run); plus one redacted single-line warning per `EDGES_FAILED` event of the form `**⚠ /umbrella: wire-dag edge BLOCKER->BLOCKED failed (HTTP STATUS): REASON**`. The reason snippet is piped through `scripts/redact-secrets.sh` (canonical secret scrubber) when present; a degraded-layout fallback flattens to `tr | head -c 200` and emits a one-time process-local notice.

**Residual redaction risk**: `scripts/redact-secrets.sh` covers token-shaped secrets (API keys, JWTs, PEM blocks, common provider key prefixes) but does NOT cover PII, internal hostnames, opaque bearer tokens, or DB connection strings (see the script's header for the explicit non-coverage list). Operators should treat these warnings like any other internal log line — best-effort secret scrubbing is not comprehensive PII protection.

**Semantic migration note (issue #720)**: Before this change, post-probe per-edge POST failures (HTTP 429 rate-limit, 403 permission denied, ambiguous 404, 5xx, request-shape mismatches) silently incremented `EDGES_SKIPPED_API_UNAVAILABLE` and emitted no diagnostic. They now increment `EDGES_FAILED` and emit one redacted stderr warning each. Dashboards or playbooks keyed on the old counter as a "benign skip volume" gauge will see a drop in `EDGES_SKIPPED_API_UNAVAILABLE` matched by a corresponding rise in `EDGES_FAILED`, plus new stderr noise — both intentional. The previous broken POST body shape (`-f issue_number=<display>`) was simultaneously fixed to the canonical `issue_id` form, so `EDGES_ADDED` should also see a corresponding rise on repos where the dependencies feature is enabled.

## `emit-output --kv-file FILE`

Validate the LLM-supplied `output.kv` (no malformed lines, no duplicate keys) and stream it to stdout. Defense-in-depth on top of the `SKILL.md` Step 4 grammar. For `emit-output` specifically, stderr is reserved for parse/validation/usage errors only — the human summary breadcrumb is emitted by the orchestrator at SKILL.md Step 4 (single emission point), not by this script. (This scoping is local to `emit-output`; `wire-dag`'s documented stderr warning behavior above is unaffected.)

### Edit-in-sync rules

Changes to `wire-dag` stdout keys consumed by orchestrator emit-output (i.e., keys that flow through `output.kv` per SKILL.md Step 4) require a same-PR update to `SKILL.md` Step 4 AND Step 3B.4. New `wire-dag` stdout keys consumed only for orchestrator parsing / session state (NOT propagated through `output.kv`) require updates only to `SKILL.md` Step 3B.4 + this file's stdout-grammar paragraph above. Today the `output.kv`-propagated set is `EDGES_ADDED`, `EDGE_<j>_BLOCKER`, `EDGE_<j>_BLOCKED`, `BACKLINKS_POSTED`; the parse-only set is `EDGES_REJECTED_CYCLE`, `EDGES_SKIPPED_EXISTING`, `EDGES_SKIPPED_API_UNAVAILABLE`, `EDGES_FAILED`, `BACKLINKS_SKIPPED_NATIVE`.

Changes to `emit-output`'s stdout grammar require a same-PR update to `SKILL.md` Step 4. Cycle-check semantic changes require regenerating the `test-helpers.sh` harness expectations.

### GitHub dependency-API note

The `/repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by` REST endpoint surface evolved during 2024-2026 (sub-issues vs blocked-by, REST vs GraphQL surfaces). `wire-dag` is fail-open by design: when the probe fails, all proposed edges land in `EDGES_SKIPPED_API_UNAVAILABLE` and back-links via plain `gh issue comment` still proceed.
