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

The wire-dag tests use a PATH-stub `gh` script written into `$TMP/bin/gh`, prepended to `PATH` for the duration of each scenario. The stub dispatches on argv pattern (probe vs blocker-id lookup vs POST vs `gh issue comment`) and returns a per-test canned `-i` response selected via env vars.

**Edit-in-sync**: any change to `helpers.sh check-cycle` or `wire-dag` stdout grammar / stderr contract requires a same-PR update to the assertion expectations here. Cycle-check semantic changes also require regenerating `test-helpers.sh` expectations.

**Out of scope**: `emit-output` subcommand. `emit-output` is a thin awk validator covered indirectly by SKILL.md integration; its Step 4 prose contract (orchestrator-attribution, single-emission-point, canonical breadcrumb shapes, stderr discipline) is structurally pinned by `test-umbrella-emit-output-contract.sh`.
