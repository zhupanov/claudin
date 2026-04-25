# skills/fix-issue/scripts/test-fix-issue-step-order.sh — contract

`skills/fix-issue/scripts/test-fix-issue-step-order.sh` is the regression harness pinning the `/fix-issue` Step 1 = lock, Step 2 = setup ordering established by closes #445 (the fetch → lock → setup reorder, shipped in PR #468). It is offline, hermetic, and runs against the committed `SKILL.md` — no network, no git state change, no mocks. The harness guards against accidental reversion of the reorder or stale renumbering of the breadcrumbs.

Nine assertions against `skills/fix-issue/SKILL.md`:

1. Step Name Registry contains `| 1 | lock |`.
2. Step Name Registry contains `| 2 | setup |`.
3. Section heading `## Step 1 — Lock Issue` present.
4. Section heading `## Step 2 — Setup` present.
5. Anti-pattern #1 contains `treat Step 1 as structural`.
6. Lock success breadcrumb literal `✅ 1: lock` present.
7. Lock failure breadcrumb literal `⚠ 1: lock` present.
8. No stale `✅ 2: lock` breadcrumb remains.
9. No stale `⚠ 2: lock` breadcrumb remains.

The harness is wired into `make lint` via the `test-fix-issue-step-order` target in `Makefile`. It is added to `agent-lint.toml`'s `exclude` list alongside this sibling contract because agent-lint's dead-script and S030/orphaned-skill-files rules do not follow Makefile-only references.

Edit-in-sync: if the Step Name Registry order changes, the section headings rename, anti-pattern #1 reverts, or any lock breadcrumb literal moves, update both this harness and this contract in the same PR.
