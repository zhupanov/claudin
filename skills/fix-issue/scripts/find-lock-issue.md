# skills/fix-issue/scripts/find-lock-issue.sh — contract

`skills/fix-issue/scripts/find-lock-issue.sh` is the combined Find + Lock + Rename pipeline invoked by `/fix-issue` Step 0. It supersedes the prior two-step `fetch-eligible-issue.sh` (Find) + `issue-lifecycle.sh comment --lock` (Lock) sequence: the title rename to `[IN PROGRESS]` is now applied immediately on lock acquisition rather than minutes later when `/implement` Step 0.5 Branch 2 ran.

## Three operations, in order

1. **Find** — eligibility scan (auto-pick mode) or explicit-issue verification. Existing logic preserved byte-for-byte for the non-umbrella path: open state, GO sentinel as last comment, no `IN PROGRESS` lock present, no managed lifecycle title prefix (`[IN PROGRESS]` / `[DONE]` / `[STALLED]`), and no open blocking dependencies (native + prose).

   **Umbrella detection** (explicit-issue path only — auto-pick never selects umbrellas, per the umbrella-PR design dialectic's DECISION_1): runs BEFORE the GO-tail check via `umbrella-handler.sh detect`. If the issue is an umbrella, the GO-tail check is BYPASSED (the umbrella body / title prefix is the approval signal; children inherit approval from the umbrella's existence). The umbrella's own blocker check still applies — a blocked umbrella exits 2 just like a blocked ordinary issue — but parsed children of the umbrella are filtered out of the **native** blocker set first, then unioned with the **prose** blocker set before the eligibility decision. Per #716, `/umbrella` wires native `child→umbrella` edges (each child blocks the umbrella), so every open child would otherwise mark the umbrella blocked and deadlock its own dispatch path; the umbrella is meant to be GATED on its children (and `handle_umbrella` dispatches them), not deadlocked by them. The umbrella branch deliberately bypasses `all_open_blockers` — that helper short-circuits on any native blocker without ever consulting prose, so an umbrella with native child blockers + a separate prose blocker would otherwise have its prose path silently skipped after children-filtering stripped the natives (review-phase Codex finding). Instead the umbrella branch calls `native_open_blockers` and `prose_open_blockers` independently, applies the children-filter only to the native set, then unions the filtered native set with prose. Children are enumerated via `umbrella-handler.sh list-children --issue $UMBRELLA_NUM`; a list-children failure emits a `WARNING:` line on stderr (so support / debugging can distinguish "real external blockers" from "could not read umbrella body to filter children") and degrades to the pre-#716 logic (no children filtered).

2. **Lock** — branches on whether the candidate is an ordinary issue or an umbrella-dispatched child:
   - **Ordinary issue**: delegates to `skills/fix-issue/scripts/issue-lifecycle.sh comment --issue $N --body "IN PROGRESS" --lock`. Same byte-for-byte behavior as before.
   - **Umbrella child**: delegates to `skills/fix-issue/scripts/issue-lifecycle.sh comment --issue $C --body "IN PROGRESS" --lock-no-go`. The child does NOT have a GO comment (children inherit approval from the umbrella). The `--lock-no-go` mode refuses if the tail is already `IN PROGRESS`, snapshots a duplicate-detection anchor BEFORE posting (last-comment timestamp, or issue's `createdAt` for zero-comment children — FINDING_4), excludes the runner's own just-posted comment id from the post-check, and uses `>= snapshot_ts` for the comparator (distinct from `--lock`'s strict `>` because `--lock` deletes its anchor while `--lock-no-go` keeps it). See `issue-lifecycle.md` for the full contract.

   The lock is the **correctness invariant** in both cases: it serializes concurrent `/fix-issue` runners. Lock semantics live in `issue-lifecycle.sh`'s `cmd_comment` and are NOT re-implemented here.

3. **Rename** — best-effort delegation to `scripts/tracking-issue-write.sh rename --issue $N --state in-progress` (or, on the umbrella-dispatch path, `--issue $C` for the chosen child). Applied AFTER the lock. Rename failure does NOT undo the lock (no compensating rollback) — the script still exits 0 with `LOCK_ACQUIRED=true RENAMED=false`. `/implement` Step 0.5 Branch 2's idempotent rename re-attempts on the next run-segment.

4. **Umbrella outcomes** (umbrella explicit-issue path only): when the explicit issue is detected as an umbrella, two non-lock outcomes are possible in addition to the dispatch-then-lock path:
   - **All children CLOSED** → exit 4. SKILL.md Step 0 invokes `finalize-umbrella.sh` (rename umbrella to `[DONE]`, post closing comment, close).
   - **No eligible child** (some open children exist but none pickable; OR zero parseable children — FINDING_3) → exit 5. SKILL.md Step 0 prints a warning and skips to Step 8.

## Stdout contract

KEY=value lines on stdout. The script captures delegate stdout into local shell variables and parses key-by-key — never streams. Only the keys below appear on stdout; auxiliary delegate keys (`COMMENTED`, `FAILED`, `NEW_TITLE`, etc.) are filtered.

| Key | Emitted when | Value |
|-----|--------------|-------|
| `ELIGIBLE` | always | `true` (eligibility pass) or `false` (no candidate / error) |
| `ISSUE_NUMBER` | `ELIGIBLE=true` | the candidate issue number. **On the umbrella-dispatch path (`UMBRELLA_ACTION=dispatched`, exit 0), this is the CHOSEN CHILD's number — not the umbrella's.** On the umbrella-complete path (exit 4), `ISSUE_NUMBER` is the umbrella's own number (the operator targeted the umbrella, and the next stage is finalizing it). On exit 5 (`UMBRELLA_ACTION=no-eligible-child`), `ISSUE_NUMBER` is omitted — `UMBRELLA_NUMBER` carries the umbrella's identity. |
| `ISSUE_TITLE` | `ELIGIBLE=true` | the candidate issue title (chosen child's title on dispatch; umbrella's own title on complete). |
| `LOCK_ACQUIRED` | `ELIGIBLE=true` | `true` (exit 0 — child or non-umbrella issue locked) or `false` (exit 3 — child lock failed; or exit 4 — umbrella complete, no lock attempted). |
| `RENAMED` | `LOCK_ACQUIRED=true` | `true` (rename succeeded) or `false` (idempotent no-op OR rename API failure — distinguished only by stderr WARNING). |
| `ERROR` | `ELIGIBLE=false` (exit 2 / exit 5) or `LOCK_ACQUIRED=false` (exit 3) | the failure reason. On umbrella exit-3 paths, `ERROR` includes the umbrella context (e.g., `Failed to lock chosen child #C of umbrella #U: <reason>`). |
| `IS_UMBRELLA` | only on umbrella paths (exit 0 dispatch / exit 3 child-lock-fail / exit 4 complete / exit 5 no-eligible-child / exit 2 umbrella-blocked) | `true`. **Absent on non-umbrella explicit-issue paths AND on all auto-pick paths** (FINDING_1 invariant). |
| `UMBRELLA_NUMBER` | only when `IS_UMBRELLA=true` | the umbrella issue number. |
| `UMBRELLA_TITLE` | only when `IS_UMBRELLA=true` AND the umbrella was successfully detected (exit 0/3/4 paths; absent on exit-2-blocked-umbrella path because the title isn't load-bearing for that error) | the umbrella's title. |
| `UMBRELLA_ACTION` | only when `IS_UMBRELLA=true` AND not exit 2 | one of `dispatched` (exit 0 — child locked), `complete` (exit 4 — finalize), `no-eligible-child` (exit 5 — skip). |

Stderr carries diagnostics (skipping-blocked-by messages, deprecated-flag warning, rename-failure WARNING — for both ordinary issues and umbrella children) and is not part of the stdout contract.

## Exit codes

| Exit | Meaning |
|------|---------|
| `0` | Eligible issue found AND comment lock acquired. Rename may have succeeded or failed best-effort — `RENAMED=true` vs `RENAMED=false` distinguishes. **Umbrella sub-case** (`UMBRELLA_ACTION=dispatched`): `ISSUE_NUMBER` refers to the chosen CHILD; `UMBRELLA_NUMBER` carries the umbrella's identity for downstream Step 6 finalization hooks in `/fix-issue` SKILL.md. |
| `1` | No eligible issues (auto-pick mode only). Auto-pick mode never selects umbrellas — DECISION_1 from the umbrella-PR design dialectic. |
| `2` | Error: `gh` CLI failure, or explicit-issue request rejected (not open, has managed prefix, last comment is not `GO` for ordinary issues, blocked by open dependencies — INCLUDING the umbrella's own blockers when the explicit target is an umbrella). |
| `3` | Eligibility passed but comment lock could not be acquired. For ordinary issues: concurrent runner won the race, GO sentinel changed mid-flight, or `gh` API failure during lock acquisition. **Umbrella sub-case**: child lock (`--lock-no-go`) failed; `ERROR` carries `Failed to lock chosen child #C of umbrella #U: <reason>`. See "Recovery semantics on exit 3" below. |
| `4` | **Umbrella complete**: the explicit issue is an umbrella, all parsed children are `CLOSED`, AND at least one child was parsed (zero-children does NOT trigger this — see FINDING_3 in the umbrella-PR plan review; that case routes to exit 5). `ELIGIBLE=true`, `LOCK_ACQUIRED=false`, `UMBRELLA_ACTION=complete`. SKILL.md Step 0 invokes `finalize-umbrella.sh finalize --issue $UMBRELLA_NUMBER`. |
| `5` | **Umbrella has no eligible child**: explicit issue is an umbrella with at least one open child, but none are pickable (all blocked / locked / managed-prefixed) — OR zero parseable children were found in the umbrella body (FINDING_3). `ELIGIBLE=false`, `UMBRELLA_ACTION=no-eligible-child`, `ERROR` carries the blocking reason. SKILL.md Step 0 prints a warning and skips to Step 8. |

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
