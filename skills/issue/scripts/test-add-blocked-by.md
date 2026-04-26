# test-add-blocked-by.sh contract

**Purpose**: regression coverage for `add-blocked-by.sh`. Self-contained — uses a function-shadowed `gh` mock on `PATH` and a stub `sleep` to keep retry-path tests fast (avoids the real 10s+30s waits).

**Coverage**:

1. 200 success path emits `BLOCKED_BY_ADDED=true CLIENT=<N> BLOCKER=<M>` and exits 0.
2. Idempotent-422 with each pinned message fragment (`already exists`, `already tracked`, `already added`, `duplicate dependency`) → treated as success (`rc=0`, `BLOCKED_BY_ADDED=true`).
3. 5xx on attempt 1 → retry → success on attempt 2; emits `BLOCKED_BY_ADDED=true`; verifies POST count ≥ 2.
4. Non-idempotent 422 (e.g., `validation failed: locked issue`) → 3 attempts → exhaustion; `rc=2`, `BLOCKED_BY_FAILED=true`; verifies POST count = 3.
5. 404 feature-unavailable → immediate fail (no retry); `rc=2`, `BLOCKED_BY_FAILED=true ERROR=feature-unavailable...`; verifies POST count = 1.
6. `--blocker-id` skipped → script resolves number → id via `gh api` lookup; success path emits `BLOCKED_BY_ADDED=true`.
7. Secret leak (e.g., `ghp_...` token in error response) → not present in stdout `ERROR=` field (redaction works end-to-end).

**Mock shape**: a fake `gh` script in a tmpdir front of PATH dispatches on argv[1]:
- `gh repo view ...` → echoes `${MOCK_REPO_OUT:-owner/repo}` and exits 0.
- `gh api /repos/.../issues/N --jq .id` → echoes `${MOCK_BLOCKER_ID_OUT:-777}` and exits `${MOCK_BLOCKER_ID_RC:-0}`.
- `gh api /repos/.../issues/N/dependencies/blocked_by -X POST --input -` → increments a counter file at `$MOCK_POST_COUNT_FILE` and dispatches via `$MOCK_POST_BEHAVIOR` ∈ {`ok`, `404`, `422-already`, `422-tracked`, `422-added`, `422-duplicate`, `422-other`, `5xx-then-ok`, `secret-leak`}.

A stub `sleep` (no-op) is placed before the fake-gh dir on PATH for tests 3 and 4 so the retry path runs in milliseconds.

**Edit-in-sync rules**:

- The pinned-message-fragment list (`already exists` / `already tracked` / `already added` / `duplicate dependency`) is duplicated between `add-blocked-by.sh`'s `attempt_post()` regex and Test 2's variant loop. Any change to the regex must update both surfaces.
- The retry schedule (3 attempts) is asserted by Test 4's POST-count check (must equal 3). Any change to the retry count must update this assertion.
- The 404-no-retry rule is asserted by Test 5's POST-count check (must equal 1).

**Execution**: `bash skills/issue/scripts/test-add-blocked-by.sh` exits 0 on success, 1 on any failure. Wired into `make lint` via the `test-add-blocked-by` Makefile target → included in `test-harnesses` aggregate.

**Channel discipline**: stdout summarizes pass/fail per assertion + final tally; stderr from the helper-under-test is captured and inspected only when an assertion fails.
