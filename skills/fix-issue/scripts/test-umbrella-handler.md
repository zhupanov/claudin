# skills/fix-issue/scripts/test-umbrella-handler.sh — contract

Offline regression harness for `skills/fix-issue/scripts/umbrella-handler.sh`. PATH-prepended `gh` stub validates the three subcommands (`detect`, `list-children`, `pick-child`) without any network or repo state mutation.

## Test scope

- **Detection priority** (FINDING_13 — body-primary, title-fallback): fixtures 1 (body literal), 2 (title prefix fallback), 3 (non-umbrella).
- **Task-list grammar** (DECISION_3): fixtures 4 (`/umbrella`-rendered children), 5 (operator-checklist with prose), 6 (cross-repo `owner/repo#N` rejected), 7 (self-reference filtered), 8 (prose-only body produces empty CHILDREN).
- **`pick-child` zero-children invariant** (FINDING_3): fixture 13 — zero parseable children emit `NO_ELIGIBLE_CHILD=true BLOCKING_REASON=no parseable children found in umbrella body`, NOT vacuous-truth `ALL_CLOSED=true`.

Pre-existing fixture coverage that the harness does NOT yet exercise but COULD (left as straightforward extensions):
- Pick-child eligibility edge cases (locked child via `IN PROGRESS` last-comment, managed-prefix child, closed child counts toward `ALL_CLOSED`).
- `gh` API failure handling (a failing `gh issue view` causes detection / list-children / pick-child to fail-closed with `ERROR=...`).

## Stub contract

The PATH-prepended `gh` stub reads its per-fixture state from `$STUB_STATE_FILE` (key=value lines sourced as bash). Per-issue state uses indirect-expansion variables: `ISSUE_<N>_TITLE`, `ISSUE_<N>_BODY`, `ISSUE_<N>_STATE`, `ISSUE_<N>_COMMENTS`. ANSI-C `$'...'` quoting is required for body strings containing newlines (the task-list parser's `^[[:space:]]*- \[[ xX]\]` regex needs actual newlines to anchor at line starts).

The stub responds to:
- `gh repo view --json nameWithOwner` → `stub/repo`
- `gh issue view <N> --json title,body,state` (or any subset including `createdAt`) → JSON object built via `jq -n --arg`
- `gh api .../comments` → contents of `ISSUE_<N>_COMMENTS` env var (default `[[]]`)
- `gh api .../blocked_by` → empty (no native blockers — out-of-scope for this harness; covered by `test-find-lock-issue.sh`'s blocker fixtures and by `test-parse-prose-blockers.sh`)

## Wired into Makefile

Run via `make test-umbrella-handler` (under `test-harnesses` target). Both `test-umbrella-handler.sh` and `test-umbrella-handler.md` are excluded from `agent-lint.toml` per the Makefile-only-reference pattern (the harness is referenced only from the Makefile and this contract file).

## Edit-in-sync rules

- When adding new subcommand outcomes to `umbrella-handler.sh`, add corresponding fixture(s) here.
- The detection priority literal pattern (`Umbrella tracking issue.` body-primary, `Umbrella:`/`Umbrella —` title-fallback) is byte-pinned in fixtures 1-3. Detection-grammar changes require coordinated fixture updates.
- The task-list regex (`^[[:space:]]*- \[[ xX]\] .*#([0-9]+)`) is byte-pinned in fixture 4. Grammar widening (e.g., to support tables) requires coordinated fixture additions.
