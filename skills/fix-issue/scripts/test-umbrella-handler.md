# skills/fix-issue/scripts/test-umbrella-handler.sh — contract

Offline regression harness for `skills/fix-issue/scripts/umbrella-handler.sh`. PATH-prepended `gh` stub validates the three subcommands (`detect`, `list-children`, `pick-child`) without any network or repo state mutation.

## Test scope

- **Title-only detection** (post-#846): fixture 1 pins the #753 regression — body contains the literal `Umbrella tracking issue.` while the title is plain → `IS_UMBRELLA=false`. Fixtures 2 (bare `Umbrella: ...` title → umbrella) and 3 (no marker → not umbrella) pin the basic title-only contract.
- **Title bracket-prefix grammar** (#819): fixtures 14-20 pin the post-#819 `is_umbrella_title` peel-prefix loop. F14 (`[IN PROGRESS] Umbrella: foo` → umbrella) and F15 (`[IN PROGRESS] (urgent) Umbrella: foo` → umbrella) cover positive bracket-prefix cases. F16 (`[IN PROGRESS] Do something umbrella related` → not umbrella) and F17 (`/umbrella ...` → not umbrella) cover the negative cases the issue's "too broad" complaint targets. F18 (`[unclosed Umbrella: foo`) and F19 (`(unclosed Umbrella: foo`) pin the fail-closed-on-unbalanced-bracket invariant. F20 (17 `[.]` blocks before `Umbrella:`) pins the iteration-cap=16 defensive guard.
- **Task-list grammar** (DECISION_3): fixtures 4 (`/umbrella`-rendered children), 5 (operator-checklist with prose), 6 (cross-repo `owner/repo#N` rejected), 7 (self-reference filtered), 8 (prose-only body produces empty CHILDREN).
- **`pick-child` eligibility edge cases**: fixtures 9 (first eligible child happy path), 10 (locked child via `IN PROGRESS` last-comment skipped), 11 (managed-prefix child skipped), 12 (`ALL_CLOSED` with parsed children).
- **`pick-child` zero-children invariant** (FINDING_3): fixture 13 — zero parseable children emit `NO_ELIGIBLE_CHILD=true BLOCKING_REASON=no parseable children found in umbrella body`, NOT vacuous-truth `ALL_CLOSED=true`.
- **`pick-child` prose-blocker iteration** (issue #768): fixture 21 — first child has `Depends on #N` (with #N OPEN), second is ready; `pick-child` returns the second child via the full `all_open_blockers` check inside `child_eligible`. Asserts `STUB_LOG` shows the prose state-lookup gh call fired (FINDING_5 — proves the prose path actually exercised, not silently fail-opened).
- **`pick-child` prose-blocker fail-open invariant** (issue #768 negative): fixture 22 — first child mentions `Depends on #N` but the gh `issue view N --json state` lookup fails (`ISSUE_<N>_VIEW_FAIL=true`); the per-ref state lookup fail-opens to "no prose blocker known" so the child remains eligible (`pick-child` does NOT turn into a fail-closed gate).

## Stub contract

The PATH-prepended `gh` stub reads its per-fixture state from `$STUB_STATE_FILE` (key=value lines sourced as bash). Per-issue state uses indirect-expansion variables: `ISSUE_<N>_TITLE`, `ISSUE_<N>_BODY`, `ISSUE_<N>_STATE`, `ISSUE_<N>_COMMENTS`. ANSI-C `$'...'` quoting is required for body strings containing newlines (the task-list parser's `^[[:space:]]*- \[[ xX]\]` regex needs actual newlines to anchor at line starts).

The stub responds to:
- `gh repo view --json nameWithOwner` → `stub/repo`
- `gh issue view <N> --json title,body,state` (or any subset including `createdAt`) → JSON object built via `jq -n --arg`. Honors `--jq <expr>` (issue #768): the constructed JSON is piped through `jq -r "$expr"` before emission, so callers like `prose_open_blockers`'s `gh issue view <ref> --json state --jq '.state'` receive the bare state string rather than the full JSON object. Without this, fail-open posture would silently mask a real prose-blocker into "not blocking" (which makes a positive prose-skip fixture pass for the wrong reason).
- `gh issue view <N>` returns non-zero with no stdout when `ISSUE_<N>_VIEW_FAIL=true` is set in the fixture state file. Used by fixture 22 to inject a per-ref state-lookup failure and exercise `prose_open_blockers`'s fail-open boundary.
- `gh api .../comments` → contents of `ISSUE_<N>_COMMENTS` env var (default `[[]]`)
- `gh api .../blocked_by` → empty (no native blockers — out-of-scope for this harness; covered by `test-find-lock-issue.sh`'s blocker fixtures and by `test-parse-prose-blockers.sh`)

## Wired into Makefile

Run via `make test-umbrella-handler` (under `test-harnesses` target). Both `test-umbrella-handler.sh` and `test-umbrella-handler.md` are excluded from `agent-lint.toml` per the Makefile-only-reference pattern (the harness is referenced only from the Makefile and this contract file).

## Edit-in-sync rules

- When adding new subcommand outcomes to `umbrella-handler.sh`, add corresponding fixture(s) here.
- The title-only detection grammar (`Umbrella:` / `Umbrella —` after the #819 bracket-prefix peel; body content NOT consulted post-#846) is byte-pinned across fixtures 1-3 and 14-20. Detection-grammar changes (new bracket-block forms, marker variants, cap changes, fail-closed semantics) require coordinated fixture updates.
- The task-list regex (`^[[:space:]]*- \[[ xX]\] .*#([0-9]+)`) is byte-pinned in fixture 4. Grammar widening (e.g., to support tables) requires coordinated fixture additions.
