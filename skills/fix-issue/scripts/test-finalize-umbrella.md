# skills/fix-issue/scripts/test-finalize-umbrella.sh — contract

Offline regression harness for `skills/fix-issue/scripts/finalize-umbrella.sh`. PATH-prepended `gh` stub validates the `finalize` subcommand's idempotency guard (FINDING_2) and the rename → close composition.

## Test scope

5 fixtures cover the executed path and the three idempotency-guard signals:

1. **finalize-success** — open umbrella, no existing marker, rename + close succeed → `FINALIZED=true RENAMED=true CLOSED=true`.
2. **idempotent-when-marker-comment-exists** (FINDING_2) — comment stream contains the literal marker `<!-- larch:fix-issue:umbrella-finalized -->`, even when `state=OPEN` and title has no `[DONE]` prefix → `FINALIZED=false ALREADY_FINALIZED=true REASON=existing closing-comment marker detected`. This is the central anti-double-comment check; without the marker probe, two concurrent finalize attempts could each post the closing comment before either's `gh issue close` fired.
3. **idempotent-when-already-DONE-prefix** — title starts with the managed prefix `[DONE]` (followed by a space) → same idempotent emission with `REASON=title already prefixed [DONE]`.
4. **idempotent-when-already-CLOSED** — state is `CLOSED` (any title, any comments) → same idempotent emission with `REASON=already CLOSED`.
5. **rename-failed-but-close-success** — best-effort rename invariant: rename delegate fails (stubbed `gh issue edit` returns exit 1), but close succeeds → `FINALIZED=true RENAMED=false CLOSED=true` plus stderr WARNING surfacing the rename failure. The lock is the correctness boundary; the title prefix is a visual lifecycle marker.

## Stub contract

The PATH-prepended `gh` stub reads its per-fixture state from `$STUB_STATE_FILE`. State variables: `ISSUE_TITLE`, `ISSUE_STATE`, `ISSUE_BODY`, `ISSUE_COMMENTS` (a JSON string for the comment-stream stub), plus failure flags `RENAME_FAIL` / `COMMENT_FAIL` / `CLOSE_FAIL` to exercise the partial-failure paths. Single-issue scope (no per-issue indirection) — the harness only ever calls `finalize --issue 100` and the stub responds the same way for any issue number.

The stub responds to:
- `gh repo view` → `stub/repo`
- `gh issue view --json title,state,body,createdAt` → JSON object
- `gh issue close` → exit 0 (or 1 if `CLOSE_FAIL=true`)
- `gh issue comment --body ...` → exit 0 (or 1 if `COMMENT_FAIL=true`)
- `gh issue edit --title ...` → exit 0 (or 1 if `RENAME_FAIL=true`)
- `gh api .../comments` → contents of `ISSUE_COMMENTS` (or DELETE → exit 0)

## Wired into Makefile

Run via `make test-finalize-umbrella` (under `test-harnesses` target). Both `test-finalize-umbrella.sh` and `test-finalize-umbrella.md` are excluded from `agent-lint.toml` per the Makefile-only-reference pattern.

## Edit-in-sync rules

- **Marker literal** (`<!-- larch:fix-issue:umbrella-finalized -->`) is byte-pinned in fixture 2's `ISSUE_COMMENTS` JSON. If the marker changes in `finalize-umbrella.sh`, update the fixture in lockstep.
- **Stdout contract** (`FINALIZED` / `ALREADY_FINALIZED` / `REASON` / `RENAMED` / `CLOSED` / `ERROR`) is asserted across multiple fixtures; new contract keys require new fixtures or extended assertions.
- The "best-effort rename" invariant is asserted by fixture 5 — relaxing the invariant (e.g., aborting on rename failure) requires updating both the script and this fixture.
