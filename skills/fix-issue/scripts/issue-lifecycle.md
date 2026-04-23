# skills/fix-issue/scripts/issue-lifecycle.md — contract

`skills/fix-issue/scripts/issue-lifecycle.sh` is the subcommand-based GitHub-issue lifecycle script invoked by `/fix-issue` Steps 2 (`comment --lock`), 4 (`close` for not-material issues), and 7 (`close` for DONE). Three subcommands: `comment`, `close`, `update-body`.

## Subcommands

- **`comment --issue N --body TEXT [--lock]`** — post a comment. With `--lock`: atomic-ish GO→IN PROGRESS lock acquisition (delete the GO sentinel comment, post IN PROGRESS, post-check for concurrent duplicates). Stdout: `LOCK_ACQUIRED=true` (on success with `--lock`) + `COMMENTED=true`, or `LOCK_ACQUIRED=false` + `ERROR=` on failure.
- **`close --issue N [--comment TEXT] [--pr-url URL]`** — close an issue with optional DONE comment and optional PR-link body backfill. **Idempotent**: if the issue is already CLOSED (e.g., GitHub auto-closed it via `Closes #<N>` on PR merge), the `gh issue close` call is skipped but the DONE comment and `--pr-url` body backfill still run; a stderr note (`INFO: issue #N already closed; backfilling DONE metadata only`) is emitted and `CLOSED=true` is printed so callers cannot distinguish the two paths. Fatal on probe failure (`gh issue view --json state`): emits `CLOSED=false` + `ERROR=Failed to read state for issue #N` and exits 1.
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

`skills/fix-issue/scripts/test-issue-lifecycle.sh` is the offline regression harness for the `close` idempotency behavior. It uses a PATH-prepended stub `gh` under `$TMPDIR` to cover: OPEN (no --pr-url), CLOSED (no --pr-url), CLOSED with --pr-url, OPEN with --pr-url (parity), and probe-failure. The harness is self-contained (no network, no repo state changes) and is wired into `make lint` via the `test-issue-lifecycle` target under `test-harnesses`. CI runs `make test-harnesses` directly. `agent-lint.toml` excludes the harness path because agent-lint's dead-script rule does not follow Makefile-only references; the skill-local `.md` exclusion block covers this file.

## Edit-in-sync rules

Changes to `cmd_close`'s stdout contract (including the `CLOSED=true` key, the `CLOSED=false` + `ERROR=` pattern, or the `INFO:` stderr note) MUST update this file in the same PR and MUST add / update a corresponding fixture in `test-issue-lifecycle.sh`. Changes to `cmd_update_body`'s stdout keys (`UPDATED=`, `SKIPPED=`) are caller-visible only when the subcommand is invoked directly (not via `cmd_close`, which suppresses this output).
