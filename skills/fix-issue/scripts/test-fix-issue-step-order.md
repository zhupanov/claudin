# skills/fix-issue/scripts/test-fix-issue-step-order.sh — contract

`skills/fix-issue/scripts/test-fix-issue-step-order.sh` is the regression harness pinning the `/fix-issue` Step 1 = lock, Step 2 = setup ordering established by closes #445 (the fetch → lock → setup reorder, shipped in PR #468). It is offline, hermetic, and runs against the committed `SKILL.md` — no network, no git state change, no mocks. The harness guards against accidental reversion of the reorder or stale renumbering of the breadcrumbs.

Twelve assertions against `skills/fix-issue/SKILL.md` — nine textual literal pins (1-9) plus three operational ordering pins (10-12) via awk-scoped block extraction:

1. Step Name Registry contains `| 1 | lock |`.
2. Step Name Registry contains `| 2 | setup |`.
3. Section heading `## Step 1 — Lock Issue` present.
4. Section heading `## Step 2 — Setup` present.
5. Anti-pattern #1 contains `treat Step 1 as structural`.
6. Lock success breadcrumb literal `✅ 1: lock` present.
7. Lock failure breadcrumb literal `⚠ 1: lock` present.
8. No stale `✅ 2: lock` breadcrumb remains.
9. No stale `⚠ 2: lock` breadcrumb remains.
10. The Step 1 block contains the issue-lifecycle.sh `--lock` call.
11. The Step 1 block does NOT contain `session-setup.sh` (operational ordering).
12. The Step 2 block contains `session-setup.sh --prefix claude-fix-issue --skip-branch-check`.

Block extraction boundaries for assertions 10-12: `## Step 1 — Lock Issue` (start, exact line match) through `## Step 2 — Setup` (end, exact line match) for Step 1; `## Step 2 — Setup` (start) through `## Step 3` (end, prefix match — heading is `## Step 3 — Read Issue Details`) for Step 2. The block-scoped operational assertions are the load-bearing guard against the regression Codex flagged in /review FINDING_2: a future edit could otherwise keep the registry rows, headings, and breadcrumbs intact while moving `session-setup.sh` back into Step 1's body.

The harness uses an accumulator pattern (`fail=1` set on each failure, exit at end) so all failures are reported in a single run. Exits 0 when all 12 assertions pass; exits 1 after running every assertion if any failed.

The harness is wired into `make lint` via the `test-fix-issue-step-order` target in `Makefile`. It is added to `agent-lint.toml`'s `exclude` list alongside this sibling contract because agent-lint's dead-script and S030/orphaned-skill-files rules do not follow Makefile-only references.

Edit-in-sync: if the Step Name Registry order changes, the section headings rename, anti-pattern #1 reverts, any lock breadcrumb literal moves, the lock-script invocation form changes, or the setup-script invocation form changes, update both this harness and this contract in the same PR. The block-extraction boundaries are pinned to the exact heading literals `## Step 1 — Lock Issue`, `## Step 2 — Setup`, and `## Step 3` (prefix); a Step 3 heading rename is the most likely silent breakage and is itself caught by assertion (3) / (4) on the start side, but the Step 3 prefix boundary should be re-pinned in the same PR if Step 3's heading changes.
