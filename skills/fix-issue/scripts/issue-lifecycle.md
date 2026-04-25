# skills/fix-issue/scripts/issue-lifecycle.md — contract

`skills/fix-issue/scripts/issue-lifecycle.sh` is the subcommand-based GitHub-issue lifecycle script. Three subcommands: `comment`, `close`, `update-body`. Callers:

- **`comment --lock`** — invoked by `skills/fix-issue/scripts/find-lock-issue.sh` at `/fix-issue` Step 0 (combined Find + Lock + Rename).
- **`close`** — invoked by `/fix-issue` Step 3 (close for not-material issues) and Step 6 (close for DONE).
- **`update-body`** — called internally by `cmd_close` when `--pr-url` is provided.

## Subcommands

- **`comment --issue N --body TEXT [--lock]`** — post a comment. With `--lock`: atomic-ish GO→IN PROGRESS lock acquisition (delete the GO sentinel comment, post IN PROGRESS, post-check for concurrent duplicates). Stdout: `LOCK_ACQUIRED=true` (on success with `--lock`) + `COMMENTED=true`, or `LOCK_ACQUIRED=false` + `ERROR=` on failure.
- **`close --issue N [--comment TEXT] [--pr-url URL]`** — close an issue with optional DONE comment and optional PR-link body backfill. **Idempotent**: if the issue is already CLOSED (e.g., GitHub auto-closed it via `Closes #<N>` on PR merge), the `gh issue close` call is skipped but the DONE comment and `--pr-url` body backfill still run; a stderr note (`INFO: issue #N already closed; backfilling DONE metadata only`) is emitted and `CLOSED=true` is printed — **the stdout contract is identical across the open and already-closed paths**, so parsers reading only stdout cannot distinguish them (stderr is a side channel used for diagnostic signals).

  **Probe-failure fallback**: if the state probe (`gh issue view --json state`) fails transiently, `close` logs a `WARNING: failed to probe state for issue #N; attempting close anyway` to stderr and falls through to `gh issue close`. This preserves the pre-idempotency OPEN-path reliability — a read-side blip must not abort a close that the write-side would otherwise succeed on. A fatal error is reported only if the subsequent `gh issue close` ALSO fails (`CLOSED=false` + `ERROR=Failed to close issue #N`, exit 1).

  **Partial-success semantics**: the `--comment` (DONE) post and the `--pr-url` body backfill run BEFORE the state probe. On probe-AND-close failure (Fixture 6 in the harness), the comment and body edits may have already been applied to the issue — the caller sees `CLOSED=false` but GitHub state shows a backfilled issue body and a DONE comment on a still-open issue. This is the same partial-success class that existed pre-idempotency (comment + body could already succeed before a fatal `gh issue close`); the idempotency change does not introduce a new partial-success mode.
- **`update-body --issue N --pr-url URL`** — append a PR link to the issue body. Idempotent via substring check. Stdout: `UPDATED=true` (+ optional `SKIPPED=already_present`) on success, `UPDATED=false` + `ERROR=` on failure. Note: `cmd_close` suppresses this subcommand's stdout when it calls it internally so only `CLOSED=true` (or `CLOSED=false` + `ERROR=`) ever appears on `close`'s stdout.

## Stdout contract

- `close` success: `CLOSED=true` (single line on stdout; any INFO note goes to stderr).
- `close` failure: `CLOSED=false` + `ERROR=<reason>` (two lines on stdout; exit code 1).
- `comment` success: `COMMENTED=true` (plus `LOCK_ACQUIRED=true` with `--lock`).
- `update-body` success: `UPDATED=true` (plus `SKIPPED=already_present` when the PR URL is already in the body).

`/fix-issue` Step 7 reads stdout loosely (substring match), so additional `INFO:` lines on stderr do not affect callers. The stdout contract is byte-stable across the OPEN and CLOSED idempotency branches.

## Exit codes

- `0` — success.
- `1` — lock verification failed, state read failed, gh call failed, or API error.
- `2` — usage error.

## Test harness

`skills/fix-issue/scripts/test-issue-lifecycle.sh` is the offline regression harness for the `close` idempotency behavior. It uses a PATH-prepended stub `gh` under `$TMPDIR` to cover: OPEN (no --pr-url), CLOSED (no --pr-url), CLOSED with --pr-url, OPEN with --pr-url (parity), probe-failure with close succeeding (fallback exercised), and probe-failure with close also failing (fatal). The harness is self-contained (no network, no repo state changes) and is wired into `make lint` via the `test-issue-lifecycle` target under `test-harnesses`. CI runs `make test-harnesses` directly. `agent-lint.toml` excludes the harness path because agent-lint's dead-script rule does not follow Makefile-only references; the skill-local `.md` exclusion block covers this file.

## Edit-in-sync rules

Changes to `cmd_close`'s stdout contract (including the `CLOSED=true` key, the `CLOSED=false` + `ERROR=` pattern, or the `INFO:` stderr note) MUST update this file in the same PR and MUST add / update a corresponding fixture in `test-issue-lifecycle.sh`. Changes to `cmd_update_body`'s stdout keys (`UPDATED=`, `SKIPPED=`) are caller-visible only when the subcommand is invoked directly (not via `cmd_close`, which suppresses this output).
