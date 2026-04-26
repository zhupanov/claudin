# skills/fix-issue/scripts/test-fix-issue-step-order.sh — contract

`skills/fix-issue/scripts/test-fix-issue-step-order.sh` is the regression harness pinning the `/fix-issue` Step 0 = find & lock, Step 1 = setup structure established by the fold-find-and-lock refactor (closes #496). It is offline, hermetic, and runs against the on-disk `skills/fix-issue/SKILL.md` at harness invocation time — typically the commit checked out in CI, but local developer runs see the working tree. No network, no git state change, no mocks. The harness guards against accidental reversion of the fold or stale renumbering of the breadcrumbs. (Throughout this contract, "preamble" means the YAML front matter, the H1 title, and any body text that appears before the first flush-left line matching `^##` followed by a space (the harness uses a strict line-anchored prefix; CommonMark-style indented level-2 ATX is deliberately not matched, since SKILL.md headings are always flush-left) — not just YAML.)

Thirteen assertions against `skills/fix-issue/SKILL.md` — ten textual literal pins (1-9, 13) plus three operational ordering pins (10-12) via awk-scoped block extraction:

1. Step Name Registry contains `| 0 | find & lock |`.
2. Step Name Registry contains `| 1 | setup |`.
3. Section heading `## Step 0 — Find and Lock` present.
4. Section heading `## Step 1 — Setup` present.
5. Anti-pattern #1 contains `treat Step 0 as structural`.
6. Find & lock success breadcrumb literal `✅ 0: find & lock` present.
7. Find & lock failure breadcrumb literal `⚠ 0: find & lock` present.
8. No stale `1: lock` breadcrumb remains (catches both `✅ 1: lock` and `⚠ 1: lock` patterns).
9. No stale `2: lock` breadcrumb remains.
10. The Step 0 block contains the `find-lock-issue.sh` invocation.
11. The Step 0 block does NOT contain `session-setup.sh` (operational ordering).
12. The Step 1 block contains `session-setup.sh --prefix claude-fix-issue --skip-branch-check`.
13. File-preamble Anti-halt rule contains `child Bash tool calls into the canonical` — proves the rule is broadened beyond the original Skill-only scope (closes #530). The check is scoped to the file preamble (start of file through the first `##` heading) so the assertion enforces the locational claim, not just substring presence anywhere in the file. The Bash-call coverage is load-bearing for the Step 6 → Step 7 → Step 8 terminal chain and for the parallel close/announce/cleanup tails in Step 3's not-material closure flow and the Step 6b → Step 7b → Step 8 NON_PR close path; each of those tails has no intervening Skill tool call. The harness diagnoses three distinct preamble-extraction failure modes separately: (a) no flush-left line matching `^##` followed by a space anywhere in the file (preamble end boundary missing), (b) first matching heading on line 1 (preamble is empty), (c) heading exists past line 1 but preamble does not contain the broadening literal.

Block extraction boundaries for assertions 10-12: `## Step 0 — Find and Lock` (start, exact line match) through `## Step 1 — Setup` (end, exact line match) for Step 0; `## Step 1 — Setup` (start) through `## Step 2` (end, prefix match — heading is `## Step 2 — Read Issue Details`) for Step 1. Assertion 13 uses a separate preamble extraction: line 1 through (but not including) the first line matching `^##` followed by a space. The block-scoped assertions are the load-bearing guard against a regression where a future edit keeps the registry rows, headings, and breadcrumbs intact while moving the matched literal out of its expected location.

The harness uses an accumulator pattern (`fail=1` set on each failure, exit at end) so all failures are reported in a single run. Exits 0 when all 13 assertions pass; exits 1 after running every assertion if any failed.

The harness is wired into `make lint` via the `test-fix-issue-step-order` target in `Makefile`. It is added to `agent-lint.toml`'s `exclude` list alongside this sibling contract because agent-lint's dead-script and S030/orphaned-skill-files rules do not follow Makefile-only references.

Edit-in-sync: if the Step Name Registry order changes, the section headings rename, anti-pattern #1 reverts, any find & lock breadcrumb literal moves, the find-lock-issue.sh invocation form changes, the setup-script invocation form changes, or the file-preamble anti-halt phrase `child Bash tool calls into the canonical` is reworded, update both this harness and this contract in the same PR. The block-extraction boundaries are pinned to the exact heading literals `## Step 0 — Find and Lock`, `## Step 1 — Setup`, and `## Step 2` (prefix); a Step 2 heading rename is the most likely silent breakage and is itself caught by assertion (3) / (4) on the start side, but the Step 2 prefix boundary should be re-pinned in the same PR if Step 2's heading changes.
