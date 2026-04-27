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
- probe failure (legacy `STUB_PROBE_RC=22` shorthand) → all proposed edges land in `EDGES_SKIPPED_API_UNAVAILABLE` (counter unchanged); after issue #728 the same input ALSO produces `PROBE_FAILED=1` on stdout and the new `wire-dag probe failed (HTTP network)` warning on stderr — coverage of those new outputs lives in the probe-classification suite below, not in test (i)
- dry-run → stdout includes `EDGES_FAILED=0`
- stub `gh` exits non-zero on POST while still emitting `-i` blob → classifier still routes correctly (proves `set +e`/`set -e` wrapper)
- blocker-id lookup failure → `EDGES_FAILED=1`, one redacted stderr line tagged `id-lookup`

**Coverage** — `wire-dag` transitive-closure regressions (issue #718):

- non-child intermediary cycle: per-node `STUB_BLOCKED_BY_<N>` setup constructs a graph where the cycle closes through a node that is not in `CHILDREN_FILE` (e.g., `STUB_BLOCKED_BY_21=50`, `STUB_BLOCKED_BY_50=20` for candidate `21\t20`); assert `EDGES_REJECTED_CYCLE=1`, `EDGES_ADDED=0`, no POST attempt. Pins the #718 fix.
- bound exhaustion: `WIRE_DAG_TRAVERSAL_NODE_CAP=2` forces truncation; assert `EDGES_FAILED=1`, the one-time `wire-dag traversal cap reached` stderr warning, and the per-edge `wire-dag edge X->Y failed (HTTP bound-exhausted)` warning. Verifies the fail-closed posture (DECISION_1, voted 3-0).
- transient `blocked_by` lookup failure: `STUB_BLOCKED_BY_<N>_RC=22` forces a single-node lookup failure; assert wire-dag completes, `EDGES_FAILED=0` (lookup failures are fail-open per FINDING_5 EXONERATE), and the one-time `wire-dag blocked_by lookup failed for #N` stderr warning fires.

**Coverage** — `wire-dag` back-link comment-existence idempotency (issue #716):

- existing back-link comment present: `STUB_LIST_COMMENTS_RESPONSE` returns a body containing `Part of umbrella #1 — Some title` (interleaved with unrelated comments) → assert `BACKLINKS_SKIPPED_EXISTING=1`, `BACKLINKS_POSTED=0`, and `STUB_COMMENT_LOG` records zero `gh issue comment` invocations.
- no matching back-link present: `STUB_LIST_COMMENTS_RESPONSE` returns comments without the umbrella prefix → assert `BACKLINKS_SKIPPED_EXISTING=0`, `BACKLINKS_POSTED=1`, and `STUB_COMMENT_LOG` records exactly one `gh issue comment` invocation.
- numeric prefix-collision guard: an unrelated `Part of umbrella #12 — ...` comment is present while looking up umbrella `#1` — assert the trailing ` — ` separator in the marker prevents the false-match (`BACKLINKS_POSTED=1`, exactly one post). Pins the literal-separator design from #716.
- fail-open posture: `STUB_LIST_COMMENTS_RC=22` simulates a transient `gh api` failure on the comments-list probe → assert `BACKLINKS_POSTED=1`, `BACKLINKS_SKIPPED_EXISTING=0`, exactly one `gh issue comment` invocation. Pins the documented fail-open contract: a transient probe failure must NOT silently suppress the back-link comment.

**Coverage** — `wire-dag --no-backlinks` (created-eq-1 bypass mode; closes #717):

- `--no-backlinks` probes the FIRST CHILD in `--children-file`, NOT the (empty) umbrella. Asserted via `UMBRELLA_PROBE_TARGET_FILE` capture: the file contains `/issues/<first-child>/dependencies/blocked_by` and does NOT contain `/issues/1/dependencies/blocked_by` (the would-be umbrella URL).
- `--no-backlinks` issues ZERO `gh issue comment` calls — the entire back-link emission loop is skipped, including both the comment-existence `gh api` lookup and the comment posting. Asserted via `STUB_COMMENT_LOG`: zero recorded comment-call lines.
- `--no-backlinks` + feature-missing 404 (fingerprinted body) → mode-aware legacy stderr: `Back-links suppressed (--no-backlinks).` AND `PROBE_FAILED=0`. Pins the issue #728 split: the legacy "API not available" warning is intentionally retained on the feature-missing path.
- `--no-backlinks` + transient probe failure (5xx on both attempts) → new probe-failed stderr: `wire-dag probe failed (HTTP 502)` AND `PROBE_FAILED=1`. Legacy `Back-links suppressed` warning is SUPPRESSED (would double-warn). Probe call count file asserts exactly 2 attempts (one retry).
- empty `--umbrella ''` WITHOUT `--no-backlinks` → script errors with `use --no-backlinks to omit it on the created-eq-1 bypass path` so callers don't accidentally bypass back-links via empty `--umbrella`.

**Coverage** — `wire-dag` probe classification (issue #728):

The probe classification suite uses the new per-attempt sequencing knobs (`STUB_PROBE_RESPONSE_<N>`, `STUB_PROBE_RC_<N>`, `PROBE_CALL_COUNT_FILE`) introduced for #728. The `run_probe_test` helper writes children/edges fixtures, sets per-attempt response env vars, runs `helpers.sh wire-dag`, and asserts on `PROBE_FAILED=<value>`, presence/absence of the legacy "API not available" warning, presence/absence of the new "wire-dag probe failed" warning, and the recorded probe attempt count. Test cases:

- `probe 404 feature-missing` → `PROBE_FAILED=0`, legacy warning fires, 1 attempt.
- `probe 502 then 200` (retry success) → `PROBE_FAILED=0`, no warning, 2 attempts.
- `probe 502 twice` → `PROBE_FAILED=1`, new probe-failed warning, 2 attempts.
- `probe empty-status twice` (no HTTP response on both attempts) → `PROBE_FAILED=1`, new warning, 2 attempts.
- `probe 403` → `PROBE_FAILED=1`, no retry (1 attempt) — clear HTTP response is not a transport blip.
- `probe 429` → `PROBE_FAILED=1`, no retry (1 attempt) — DECISION_1 simplification: all 429 are non-retriable, no Retry-After header parsing.
- `probe 404 ambiguous` (no fingerprint match) → `PROBE_FAILED=1`, new warning, 1 attempt.
- `probe 502 then feature-missing 404` (retry recovers to feature-missing) → `PROBE_FAILED=0`, legacy warning, 2 attempts.
- `--no-backlinks ambiguous-404 first-child` (stale child, non-fingerprint 404) → `PROBE_FAILED=1` (operational, not feature-off).
- `--no-backlinks empty CHILDREN_FILE` → `probe_target` is empty, no probe runs, `PROBE_FAILED=0`, no probe stderr.
- dry-run path → stdout includes `PROBE_FAILED=0` literal (initialized before `--dry-run` early-exit so `set -u` cannot trip).

The shared body fingerprint regex (`_wd_is_feature_missing_404`) is exercised at both call sites: the new probe-stage classifier AND the existing per-edge POST-stage 404 handler. The existing per-edge tests `(b)` and `(c)` continue to pin the per-edge fingerprint behavior; the probe-stage tests above mirror them at the probe stage. Drift between the two sites is structurally prevented by the shared shell function.

The wire-dag tests use a PATH-stub `gh` script written into `$TMP/bin/gh`, prepended to `PATH` for the duration of each scenario. The stub dispatches on argv pattern (probe vs blocker-id lookup vs POST vs `/comments` listing vs `gh issue comment`) and returns a per-test canned response selected via env vars. The `--no-backlinks` and back-link comment-existence suites use the instrumentation hooks `UMBRELLA_PROBE_TARGET_FILE` (set on the `wire-dag` invocation; `helpers.sh` writes the probed URL to it for assertion) and `STUB_COMMENT_LOG` (set on the stub's environment; the stub appends one line per `gh issue comment` invocation). The back-link comment-existence suite uses two additional env vars: `STUB_LIST_COMMENTS_RESPONSE` (newline-separated comment bodies returned by the `/comments` probe; default empty) and `STUB_LIST_COMMENTS_RC` (probe exit code, default 0; non-zero exercises the fail-open posture). The new `/comments` stub case-arm is placed BEFORE the generic `/issues/<N>` arm so the case-statement first-match order does not shadow it with the blocker-id lookup arm.

**Per-node `blocked_by` stub dispatch** (issue #718): the existing-edges lookup branch (matched by `--jq '.[].number'` in argv) extracts the issue number from the URL path and looks up `STUB_BLOCKED_BY_<N>` first. When that var is unset, falls back to the legacy global `STUB_EXISTING_BLOCKERS` (unset by default; pre-existing tests that relied on its empty-default behavior continue to work without modification). `STUB_BLOCKED_BY_<N>_RC` (default 0) overrides the lookup exit code per node — non-zero simulates a transient `gh` failure for that node. Multi-blocker values use space-separated lists in the env var (e.g., `STUB_BLOCKED_BY_20="100 101 102"`); the stub converts them to newline-separated to match production `gh api --jq '.[].number'` output shape.

**Per-attempt probe stub dispatch** (issue #728): the probe path (no POST, no `--jq`) supports per-attempt response sequencing for retry tests. Set `PROBE_CALL_COUNT_FILE` to an empty file path to enable counting; the stub increments the file on each call and uses `STUB_PROBE_RESPONSE_<attempt>` / `STUB_PROBE_RC_<attempt>` (1-based). When the per-attempt vars are unset, the stub falls back to the legacy `STUB_PROBE_RESPONSE` / `STUB_PROBE_RC` single-shot pattern. Default behavior (no env vars set) emits a 200 OK HTTP response so existing tests with `STUB_PROBE_RC=0` continue to see `api_available=true` on the new status-aware probe (preserves backward-compat without per-test changes). The dispatch also handles the new `gh api -i URL` invocation shape (URL at $3 instead of $2) by scanning all args for a `/repos/.../issues/...` path and binding the matched arg to a local `_stub_url` variable used in the case dispatch.

**Edit-in-sync**: any change to `helpers.sh check-cycle` or `wire-dag` stdout grammar / stderr contract requires a same-PR update to the assertion expectations here. Cycle-check semantic changes also require regenerating `test-helpers.sh` expectations.

**Out of scope**: `emit-output` subcommand. `emit-output` is a thin awk validator covered indirectly by SKILL.md integration; its Step 4 prose contract (orchestrator-attribution, single-emission-point, canonical breadcrumb shapes, stderr discipline) is structurally pinned by `test-umbrella-emit-output-contract.sh`.
