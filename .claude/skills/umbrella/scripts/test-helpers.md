# test-helpers.sh — sibling contract

Regression harness for `helpers.sh check-cycle` (pure logic, no network) and `helpers.sh wire-dag` (PATH-stub `gh`, no real network). Self-contained: creates an ephemeral `mktemp` dir for edge fixtures and a stub `gh` script, runs each assertion, prints a `✅`/`❌` line, exits non-zero on any failure.

**Run manually**: `bash .claude/skills/umbrella/scripts/test-helpers.sh`.

**Wired into `make lint`**: the top-level `Makefile` defines a `test-umbrella-helpers` target that runs this harness; it is a dep of `test-harnesses` (and therefore `lint`), so CI's `test-harnesses` job catches any regression.

**Coverage** — `check-cycle`:

- empty graph + simple candidate
- self-loop (always cycle)
- 2-cycle from new edge
- independent candidate
- 3-cycle close on a linear chain
- parallel forward edge in a chain (still a DAG)
- diamond cycle close (4→1)
- diamond cross-edge (still a DAG)
- disconnected components
- error paths: missing flags, malformed candidate, non-numeric candidate

**Coverage** — `wire-dag` (PATH-stub `gh`; categorization tests for issue #720):

- probe ok + 200 OK on per-edge POST → `EDGES_ADDED=1`, no stderr warning
- probe ok + 404 with feature-missing body fingerprint → `EDGES_SKIPPED_API_UNAVAILABLE=1`, no stderr warning
- probe ok + 404 with ambiguous body (e.g., stale-child issue-not-found) → `EDGES_FAILED=1`, one redacted stderr line
- probe ok + 429 (rate-limit) → `EDGES_FAILED=1`, one redacted stderr line
- probe ok + 403 (permission denied) → `EDGES_FAILED=1`, one redacted stderr line
- probe ok + 5xx → `EDGES_FAILED=1`, one redacted stderr line
- probe ok + 422 with already-exists body → `EDGES_SKIPPED_EXISTING=1` (idempotent per `add-blocked-by.sh:193-196`)
- probe ok + 422 non-idempotent → `EDGES_FAILED=1`
- probe failure (existing repo-wide path unchanged) → all proposed edges land in `EDGES_SKIPPED_API_UNAVAILABLE`
- dry-run → stdout includes `EDGES_FAILED=0`
- stub `gh` exits non-zero on POST while still emitting `-i` blob → classifier still routes correctly (proves `set +e`/`set -e` wrapper)
- blocker-id lookup failure → `EDGES_FAILED=1`, one redacted stderr line tagged `id-lookup`

**Coverage** — `wire-dag` transitive-closure regressions (issue #718):

- non-child intermediary cycle: per-node `STUB_BLOCKED_BY_<N>` setup constructs a graph where the cycle closes through a node that is not in `CHILDREN_FILE` (e.g., `STUB_BLOCKED_BY_21=50`, `STUB_BLOCKED_BY_50=20` for candidate `21\t20`); assert `EDGES_REJECTED_CYCLE=1`, `EDGES_ADDED=0`, no POST attempt. Pins the #718 fix.
- bound exhaustion: `WIRE_DAG_TRAVERSAL_NODE_CAP=2` forces truncation; assert `EDGES_FAILED=1`, the one-time `wire-dag traversal cap reached` stderr warning, and the per-edge `wire-dag edge X->Y failed (HTTP bound-exhausted)` warning. Verifies the fail-closed posture (DECISION_1, voted 3-0).
- transient `blocked_by` lookup failure: `STUB_BLOCKED_BY_<N>_RC=22` forces a single-node lookup failure; assert wire-dag completes, `EDGES_FAILED=0` (lookup failures are fail-open per FINDING_5 EXONERATE), and the one-time `wire-dag blocked_by lookup failed for #N` stderr warning fires.

The wire-dag tests use a PATH-stub `gh` script written into `$TMP/bin/gh`, prepended to `PATH` for the duration of each scenario. The stub dispatches on argv pattern (probe vs blocker-id lookup vs POST vs `gh issue comment`) and returns a per-test canned `-i` response selected via env vars.

**Per-node `blocked_by` stub dispatch** (issue #718): the existing-edges lookup branch (matched by `--jq '.[].number'` in argv) extracts the issue number from the URL path and looks up `STUB_BLOCKED_BY_<N>` first. When that var is unset, falls back to the legacy global `STUB_EXISTING_BLOCKERS` (unset by default; pre-existing tests that relied on its empty-default behavior continue to work without modification). `STUB_BLOCKED_BY_<N>_RC` (default 0) overrides the lookup exit code per node — non-zero simulates a transient `gh` failure for that node. Multi-blocker values use space-separated lists in the env var (e.g., `STUB_BLOCKED_BY_20="100 101 102"`); the stub converts them to newline-separated to match production `gh api --jq '.[].number'` output shape.

**Edit-in-sync**: any change to `helpers.sh check-cycle` or `wire-dag` stdout grammar / stderr contract requires a same-PR update to the assertion expectations here. Cycle-check semantic changes also require regenerating `test-helpers.sh` expectations.

**Out of scope**: `emit-output` subcommand. `emit-output` is a thin awk validator covered indirectly by SKILL.md integration; its Step 4 prose contract (orchestrator-attribution, single-emission-point, canonical breadcrumb shapes, stderr discipline) is structurally pinned by `test-umbrella-emit-output-contract.sh`.
