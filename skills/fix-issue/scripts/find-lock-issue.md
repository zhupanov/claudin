# skills/fix-issue/scripts/find-lock-issue.sh — contract

`skills/fix-issue/scripts/find-lock-issue.sh` is the combined Find + Lock + Rename pipeline invoked by `/fix-issue` Step 0. It supersedes the prior two-step `fetch-eligible-issue.sh` (Find) + `issue-lifecycle.sh comment --lock` (Lock) sequence: the title rename to `[IN PROGRESS]` is now applied immediately on lock acquisition rather than minutes later when `/implement` Step 0.5 Branch 2 ran.

## Three operations, in order

1. **Find** — eligibility scan (auto-pick mode) or explicit-issue verification. Existing logic from `fetch-eligible-issue.sh` is preserved byte-for-byte: open state, GO sentinel as last comment, no `IN PROGRESS` lock present, no managed lifecycle title prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`), and no open blocking dependencies (native + prose).
2. **Lock** — delegates to `skills/fix-issue/scripts/issue-lifecycle.sh comment --issue $N --body "IN PROGRESS" --lock`. The lock is the **correctness invariant**: it serializes concurrent `/fix-issue` runners. Lock semantics (GO tail re-verification, GO comment deletion, IN PROGRESS post, sleep + post-check duplicate detection) live in `issue-lifecycle.sh`'s `cmd_comment` and are NOT re-implemented here.
3. **Rename** — best-effort delegation to `scripts/tracking-issue-write.sh rename --issue $N --state in-progress`. Applied AFTER the lock so `has_managed_prefix` correctly excludes the candidate before it is locked. A rename failure does NOT undo the lock (no compensating rollback) — the script still exits 0 with `LOCK_ACQUIRED=true RENAMED=false`. `/implement` Step 0.5 Branch 2's idempotent rename re-attempts on the next run-segment.

## Stdout contract

KEY=value lines on stdout. The script captures delegate stdout into local shell variables and parses key-by-key — never streams. Only the keys below appear on stdout; auxiliary delegate keys (`COMMENTED`, `FAILED`, `NEW_TITLE`, etc.) are filtered.

| Key | Emitted when | Value |
|-----|--------------|-------|
| `ELIGIBLE` | always | `true` (eligibility pass) or `false` (no candidate / error) |
| `ISSUE_NUMBER` | `ELIGIBLE=true` | the candidate issue number |
| `ISSUE_TITLE` | `ELIGIBLE=true` | the candidate issue title |
| `LOCK_ACQUIRED` | `ELIGIBLE=true` | `true` (exit 0) or `false` (exit 3) |
| `RENAMED` | `LOCK_ACQUIRED=true` | `true` (rename succeeded) or `false` (idempotent no-op OR rename API failure — distinguished only by stderr WARNING) |
| `ERROR` | `ELIGIBLE=false` (exit 2) or `LOCK_ACQUIRED=false` (exit 3) | the failure reason |

Stderr carries diagnostics (skipping-blocked-by messages, deprecated-flag warning, rename-failure WARNING) and is not part of the stdout contract.

## Exit codes

| Exit | Meaning |
|------|---------|
| `0` | Eligible issue found AND comment lock acquired. Rename may have succeeded or failed best-effort — `RENAMED=true` vs `RENAMED=false` distinguishes. |
| `1` | No eligible issues (auto-pick mode only). |
| `2` | Error: `gh` CLI failure, or explicit-issue request rejected (not open, has managed prefix, last comment is not `GO`, blocked by open dependencies, etc.). |
| `3` | Eligibility passed but comment lock could not be acquired. Concurrent runner won the race, the GO sentinel changed between eligibility scan and lock attempt, OR a `gh` API failure mid-sequence (after GO delete but before IN PROGRESS post — see "Recovery semantics on exit 3" below). `LOCK_ACQUIRED=false ERROR=...` on stdout. |

## Recovery semantics on exit 3

Exit 3 spans three sub-cases that differ in remote-state mutation. The script does NOT differentiate them on stdout — operators should consult `skills/fix-issue/SKILL.md` Known Limitations "Stale IN PROGRESS lock" for the per-case recovery flow.

- **Pre-write GO-tail re-check failure** — `cmd_comment` reads the comment list, sees the tail is no longer `GO`, and exits before mutating any remote state. Comment stream UNCHANGED. Recovery: re-add `GO` if desired (the candidate has been claimed by another runner OR the operator changed the sentinel mid-flight).
- **Post-failure mid-write** — `cmd_comment` deletes the `GO` comment, then `gh issue comment --body "IN PROGRESS"` fails. Comment stream MUTATED — `GO` is gone, no `IN PROGRESS` posted. Recovery: manually re-add `GO`. The issue is no longer pickable by `/fix-issue` until `GO` is restored.
- **Duplicate-IN-PROGRESS post-check** — `cmd_comment` succeeds at delete + post, but its post-write re-fetch detects 2+ `IN PROGRESS` comments after the deleted-`GO` timestamp (concurrent runner race). Comment stream MUTATED — `GO` is gone, `IN PROGRESS` is present (twice). Recovery: manually delete the duplicate `IN PROGRESS` comments and re-add `GO`.

## set -e / set -o pipefail propagation

The script runs with `set -euo pipefail`. The two delegate calls are wrapped with `|| <var>=$?` so a non-zero exit from `issue-lifecycle.sh` or `tracking-issue-write.sh` does NOT prematurely abort `find-lock-issue.sh` before its unified contract is emitted. The `lock_exit` and `rename_exit` variables capture the delegate exit codes for downstream conditional logic.

This is load-bearing: without the guard, a `LOCK_ACQUIRED=false` outcome would not produce stdout at all, leaving `/fix-issue`'s Step 0 parser with empty input.

## Best-effort rename rationale

The rename failure mode is non-fatal because:
- The comment lock is the actual concurrency invariant; the title prefix is a visual-display lifecycle.
- `/implement` consistently treats title renames as best-effort across Step 0.5 Branches 1/2/3, Step 12a/12b (terminal `[DONE]`), and Step 18 (terminal `[STALLED]`), all logging to `Tool Failures` and continuing on rename failure.
- `/implement` Step 0.5 Branch 2's idempotent rename serves as the safety net: when `/fix-issue` invokes `/implement` with `--issue $ISSUE_NUMBER`, Branch 2 re-attempts the rename and short-circuits with `RENAMED=false` if the title is already prefixed.
- A compensating rollback (delete IN PROGRESS, restore GO) would itself involve more `gh` API writes that can fail, widening the failure surface to fix a cosmetic inconsistency.

## Edit-in-sync rules

- If `issue-lifecycle.sh comment --lock`'s stdout contract changes (e.g., new keys added beyond `LOCK_ACQUIRED` / `COMMENTED` / `ERROR`), update the awk-based key extraction in `lock_and_rename_then_emit`.
- If `tracking-issue-write.sh rename`'s stdout contract changes (e.g., new keys beyond `RENAMED` / `NEW_TITLE` / `FAILED` / `ERROR`), update the awk-based key extraction.
- If the unified stdout contract grows (new keys), update SKILL.md Step 0's parser, the new test harness `test-find-lock-issue.sh`, and this contract file in lockstep.
- The exit-3 reservation (lock-acquired-false-after-eligibility-pass) is consumed by `skills/fix-issue/SKILL.md` Step 0; both must change together if the meaning shifts.

## Test harness

`skills/fix-issue/scripts/test-find-lock-issue.sh` is the offline regression harness. PATH-prepended `gh` stub. Five executed fixtures + one deferred-coverage note: ok (lock + rename); lock-fail (exit 3); rename-fail best-effort (exit 0, RENAMED=false, stderr WARNING); rename idempotent no-op coverage deferred to `scripts/test-tracking-issue-write.sh` (idempotent state unreachable from this harness's contract surface — the eligibility filter rejects `[IN PROGRESS]`-prefixed titles before the rename call); ineligible managed prefix (exit 2); auto-pick no candidate (exit 1). Wired into `make lint` via the `test-find-lock-issue` target. Both `.sh` and `.md` are in `agent-lint.toml`'s `exclude` list per the Makefile-only-reference pattern.
