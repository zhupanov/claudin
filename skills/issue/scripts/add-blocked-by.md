# add-blocked-by.sh contract

**Purpose**: apply a single GitHub-native blocker dependency between two issues by POSTing to the Issue Dependencies REST API, with retry-3-times-with-10s/30s-sleeps and fail-closed semantics. The write counterpart to `skills/fix-issue/scripts/find-lock-issue.sh`'s read-side use of the same endpoint family.

**Caller**: `/issue` SKILL.md Step 6 (per-item create loop). Invoked once per dependency edge — one for each `ITEM_<i>_BLOCKED_BY=<entry>` and one for each `ITEM_<i>_BLOCKS=<entry>` (in the latter case, the just-created issue is the blocker, an existing issue is the client).

**Invariants**:

- POST endpoint: `/repos/{owner}/{repo}/issues/{client_number}/dependencies/blocked_by` with body `{"issue_id": <blocker numeric id>}`. The body field is the blocker's **internal numeric id**, not its display number — see `gh api /repos/.../issues/N --jq .id`.
- Retry schedule: attempt 1 immediate; sleep 10s; attempt 2; sleep 30s; attempt 3. No additional retries.
- Idempotency on 422: when the response message contains "already exists" / "already tracked" / "already added" / "duplicate dependency" (case-insensitive substring match), treat as `BLOCKED_BY_ADDED=true` and exit 0. Other 422 variants (permissions, validation) remain failures and consume a retry slot.
- 404 on the dependencies sub-resource → fail immediately with `ERROR=feature-unavailable: ...`. No retry. Distinguishable on stdout for `/issue` to surface a feature-availability message.
- All redaction goes through `${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh` on the failure path. Helper failure → exit 3 with `ERROR=redaction:...`.

**Edit-in-sync rules**:

- The 422-idempotent message-fragment list (`already exists` / `already tracked` / `already added` / `duplicate dependency`) is pinned to `add-blocked-by.sh`'s `attempt_post()` regex. Any change to the GitHub API's idempotent-response phrasing requires updating both the script regex AND the `test-add-blocked-by.sh` fixture rows.
- The retry schedule (10s/30s sleeps before retries 1 and 2) is pinned by issue #546's hard-fail-with-retries constraint. Any change requires user approval.
- The fail-closed semantics on the WRITE side intentionally diverge from `skills/fix-issue/scripts/find-lock-issue.sh`'s fail-open posture on the READ side. Do NOT "harmonize" them — the divergence is a feature contract, not an oversight.

**Test harness**: `test-add-blocked-by.sh` (sibling). Wired into `make lint` via the `test-harnesses` target. Mocks `gh` with a function-shadow approach (matching the pattern in `test-redact-secrets.sh`) and covers: 200-success path, idempotent-422 with each pinned message fragment, non-idempotent 422 → retry → exhaustion, 5xx → retry → success on attempt 2, 5xx → exhaustion → exit 2, 404 → immediate fail with feature-unavailable, secret-leak in error response → redacted output.

**Known limitation (not a bug)**: a successful 200 response does not guarantee the dependency is actually applied if the user's gh-CLI auth token lacks the required scope. GitHub's API response shape doesn't expose scope mismatches at this layer. Operators who suspect silent failure can verify via `gh api /repos/.../issues/N/dependencies/blocked_by`. This is documented per /issue plan-review FINDING_14 (rejected as too speculative for a code change but worth surfacing in the contract).

**Output schema** (key=value on stdout):

| Field | When | Meaning |
|---|---|---|
| `BLOCKED_BY_ADDED=true` | success or idempotent | the link exists at the API layer |
| `BLOCKED_BY_FAILED=true` | failure | retries exhausted or non-retryable error |
| `CLIENT=<N>` | always | echoes input — issue that gets the blocker relationship |
| `BLOCKER=<M>` | always | echoes input — issue that does the blocking |
| `ERROR=<redacted-msg>` | failure only | flattened, redacted, capped at 500 chars |

**Exit codes**: 0 on success; 1 on usage error; 2 on API failure; 3 on redaction-helper failure.
