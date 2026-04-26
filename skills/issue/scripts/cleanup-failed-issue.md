# cleanup-failed-issue.sh contract

**Purpose**: best-effort close an orphan GitHub issue when /issue's dep-wiring path exhausts retries via `add-blocked-by.sh`, so the orphan does not persist in the repo without its declared blockers.

**Caller**: `/issue` SKILL.md Step 6 (per-item create loop), invoked once on the failure path of dependency wiring after `add-blocked-by.sh` returns `BLOCKED_BY_FAILED=true`.

**Invariants**:

- Single attempt. No retry. If the close fails (permissions, lock, transient API), /issue surfaces the orphan issue URL on stderr so the operator can close manually.
- `--reason "not planned"` is used to distinguish auto-cleanup from organic closure (the issue exists on GitHub but was never wired into the planned dep graph).
- Always exits 0; caller distinguishes outcome via `CLOSED=true|false` on stdout.
- Stderr from `gh` is captured and routed through `${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh` before being included in `ERROR=` to prevent token leak from auth-failure messages.

**Edit-in-sync rules**:

- The single-attempt-no-retry policy is intentional. Adding retries here would mask the operator-facing signal that the orphan needs manual attention.
- The `--reason "not planned"` argument is pinned by SKILL.md prose for orphan distinguishability. Any change to the reason value requires updating SKILL.md and operator-facing docs.

**Test coverage**: covered indirectly by `test-add-blocked-by.sh`'s exhaustion-path fixture, which can stub `gh issue close` to verify the orchestrator invokes this helper correctly. A dedicated `test-cleanup-failed-issue.sh` is not added — the helper is small enough that its contract is its test.

**Output schema** (key=value on stdout):

| Field | Always emitted | Meaning |
|---|---|---|
| `CLOSED=true` | on success | `gh issue close` returned 0 |
| `CLOSED=false` | on failure | the issue remains open; ERROR populated |
| `ISSUE=<N>` | always | echoes input |
| `ERROR=<redacted-msg>` | failure only | flattened, redacted, capped at 500 chars |

**Exit code**: always 0.
