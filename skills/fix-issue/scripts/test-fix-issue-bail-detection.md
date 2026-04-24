# skills/fix-issue/scripts/test-fix-issue-bail-detection.sh — contract

`skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` is the regression harness for the Phase 4 bail-detection prose in `skills/fix-issue/SKILL.md` Step 6a (Phase 4 of umbrella #348). It is offline, hermetic, and runs against the committed `SKILL.md` — no network, no git state change, no mocks. The harness guards against accidental removal of five load-bearing literals inside the Step 6a block:

- `--issue $ISSUE_NUMBER` in the SIMPLE bullet (forwarded to `/implement` so it adopts the queue issue via Phase 3 Branch 2).
- `--issue $ISSUE_NUMBER` in the HARD bullet (same rationale).
- `IMPLEMENT_BAIL_REASON=adopted-issue-closed` — the exact machine token `/implement` emits when the adopted issue is CLOSED; `/fix-issue` scans captured output for this literal.
- `/implement bailed: issue #` — the user-visible warning prefix printed on the bail branch.
- `Do NOT call` — directive fragment that prevents silent re-routing of the bail path back to Step 7's close call.
- `Skip to Step 9` — cleanup redirect on the bail branch.

Extraction boundary: `^### 6a` (start, prefix match) through `^## Step 7` (end, prefix match; the real heading is `## Step 7 — Close Issue`). This scopes the assertions to Step 6a so stray mentions of these literals elsewhere in `SKILL.md` cannot false-pass the harness.

The harness is wired into `make lint` via the `test-fix-issue-bail-detection` target in `Makefile`. It is added to `agent-lint.toml`'s `exclude` list alongside its sibling contract `.md` because agent-lint's dead-script and S030/orphaned-skill-files rules do not follow Makefile-only references. The paired token-literal assertion on the emitter side lives in `scripts/test-implement-structure.sh` (pins the same token in `skills/implement/SKILL.md`); a rename of the bail token is therefore a dual-repo change caught by CI.

Edit-in-sync: if the Step 6a narrative rewords any of the five load-bearing literals or restructures the bail branch, update this harness and this contract in the same PR.
