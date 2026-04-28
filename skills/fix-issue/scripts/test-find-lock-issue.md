# skills/fix-issue/scripts/test-find-lock-issue.sh — contract

`skills/fix-issue/scripts/test-find-lock-issue.sh` is the offline regression harness for `skills/fix-issue/scripts/find-lock-issue.sh` (the combined Find + Lock + Rename pipeline introduced by the fold-find-and-lock refactor closing #496). It uses a PATH-prepended `gh` stub under a per-fixture tmpdir to validate the script's exit-code matrix and unified stdout contract without any network or git-state mutation.

## Ten executed fixtures plus one deferred-coverage note

1. **Eligible + lock OK + rename OK** → exit 0; `ELIGIBLE=true`, `ISSUE_NUMBER=N`, `LOCK_ACQUIRED=true`, `RENAMED=true`. Auxiliary delegate keys (`COMMENTED`, `NEW_TITLE`) are filtered from stdout.
2. **Eligible + lock fail** → exit 3; `ELIGIBLE=true LOCK_ACQUIRED=false ERROR=...`. Simulated by failing the IN PROGRESS comment post inside `cmd_comment` (a stateless-stub-friendly approximation of the duplicate-IN-PROGRESS detection path; both produce the same `exit 1` from `cmd_comment` → `exit 3` from `find-lock-issue.sh`).
3. **Eligible + lock OK + rename fails best-effort** → exit 0; `LOCK_ACQUIRED=true RENAMED=false` + stderr `WARNING: title rename failed`. Validates that a rename API failure does not undo the lock and is surfaced as a non-fatal warning.
4. **Idempotent rename no-op** — coverage deferred to `scripts/test-tracking-issue-write.sh` (which exercises the rename subcommand directly). The eligibility filter in `find-lock-issue.sh` rejects `[IN PROGRESS]`-prefixed titles before the rename call is ever made in production, so the idempotent-no-op path is unreachable from `find-lock-issue.sh`'s contract surface.
5. **Ineligible (managed prefix in explicit `--issue` mode)** → exit 2; `ELIGIBLE=false ERROR=Issue #N has a managed lifecycle title prefix...`. Lock is never attempted (`LOCK_ACQUIRED` absent from stdout).
6. **Auto-pick mode + no eligible candidates** → exit 1; `ELIGIBLE=false`. Empty open-issues list.
7. **Auto-pick mode + Urgent preference** → exit 0; `ISSUE_NUMBER=20`. Five open issues (#5 "Fix non-urgent cleanup" substring trap, #10 non-Urgent oldest, #20 lowercase "urgent", #30 non-Urgent, #40 uppercase "URGENT"); the picker selects #20, verifying all three behaviors: word-boundary regex (so #5 is REJECTED — `non-urgent` does not match `\burgent\b` despite containing the letters), Urgent-tier comes before non-Urgent-tier (so #20 beats #10 despite #10 being older), AND oldest-first holds within the Urgent tier (so #20 beats #40). Case-insensitive matching is exercised by the lowercase / uppercase mix.
8. **Auto-pick mode + no Urgent → oldest-first preserved** → exit 0; `ISSUE_NUMBER=10`. Three non-Urgent open issues; the picker selects the oldest, confirming the Urgent preference is a soft signal that does not alter ordering when no Urgent candidate exists.
9. **Explicit-issue mode with a GHE-style host** → exit 0; `ISSUE_NUMBER=55 LOCK_ACQUIRED=true RENAMED=true`. The script is invoked with a full URL whose host is `ghe.example.com` (not `github.com`); the repo-ownership parser must accept any `https://<host>/<owner>/<repo>/issues/<n>` (the `gh` CLI always emits `https://`, so the production regex pins that scheme literally) as long as `<owner>/<repo>` matches the current repo. Closes #766. Fixture-controlled via `ISSUE_URL_HOST` in the stub state file.
10. **Explicit-target umbrella with `[IN PROGRESS]` managed-prefix title** → exit 5; `ELIGIBLE=false IS_UMBRELLA=true UMBRELLA_ACTION=no-eligible-child UMBRELLA_NUMBER=N`. Closes #819. Pins the explicit-target reorder (umbrella detection runs BEFORE the managed-prefix early-reject) — pre-#819 this title would have failed the managed-prefix gate without ever consulting `umbrella-handler.sh detect`. Slimmer NO_ELIGIBLE_CHILD design (per #819 plan-review FINDING_7): title-only umbrella with no body literal and no parseable task-list children — `handle_umbrella` emits exit 5 + `UMBRELLA_ACTION=no-eligible-child` without invoking `issue-lifecycle.sh` lock-no-go, isolating the regression to the reorder. Asserts both the positive shape (`IS_UMBRELLA=true`, `UMBRELLA_ACTION=no-eligible-child`, `UMBRELLA_NUMBER=50`) AND the absence of the managed-prefix rejection error message (`managed lifecycle title prefix`) so a regression in the reorder cannot pass with bare `IS_UMBRELLA=true`.

## Stub design

The stub `gh` dispatches on positional + `--json` args. Each fixture writes a stub state file under a per-fixture tmpdir; the stub `source`s the file to decide what to emit. State variables:

- `ISSUE_STATE` — fixture-controlled value for `gh issue view --json state`.
- `ISSUE_TITLE` — fixture-controlled value for `gh issue view --json title`.
- `ISSUE_URL_HOST` — fixture-controlled host (defaults to `github.com`) embedded in the `url` field returned by `gh issue view --json url`. Used by Fixture 9 to exercise host-generic URL parsing for GitHub Enterprise / self-hosted GHE deployments.
- `COMMENTS_JSON` — page-array JSON for `gh api --paginate --slurp .../comments`. Single-quoted in the state file so JSON braces survive `source`.
- `OPEN_ISSUES_JSON` — JSONL for `gh api repos/.../issues?state=open`.
- `RENAME_FAIL=true` — makes `gh issue edit --title` exit non-zero (used by Fixture 3).
- `COMMENT_FAIL=true` — makes `gh issue comment --body` exit non-zero (used by Fixture 2).

The stub emits an unhandled-invocation diagnostic to stderr and exits 99 if it sees a `gh` shape outside the supported subcommand set. This catches upstream call-shape changes that would otherwise silently break the harness.

## Out-of-scope coverage

- End-to-end gh API behavior (rate limits, auth flow, real network).
- Stateful concurrent-runner race conditions (the duplicate-IN-PROGRESS post-check inside `cmd_comment` uses `sleep 1` + re-fetch). The stub returns the same comment list per call; full coverage of the race path is exercised in production logs and via the indirect harness `test-issue-lifecycle.sh`.
- Title-prefix idempotency — covered by `scripts/test-tracking-issue-write.sh`.

## Wiring

The harness is wired into `make lint` via the `test-find-lock-issue` target in `Makefile`. Both `.sh` and `.md` are added to `agent-lint.toml`'s `exclude` list because agent-lint's dead-script and S030/orphaned-skill-files rules do not follow Makefile-only references.

## Edit-in-sync

If `find-lock-issue.sh`'s stdout contract gains new keys, change exit-code semantics, or alters the delegate-stdout filtering policy, update this harness AND this contract in the same PR. If the delegate scripts (`issue-lifecycle.sh comment --lock`, `tracking-issue-write.sh rename`) gain new stdout keys that need explicit filtering at the `find-lock-issue.sh` boundary, extend the relevant fixture's `assert_not_contains` set.
