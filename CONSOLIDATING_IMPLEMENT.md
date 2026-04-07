# Consolidating `/implement` and `/implement-and-merge`

## Goal

Collapse the two near-duplicate skills `/implement` and `/implement-and-merge` into a single skill named `/implement`. Today, `/implement-and-merge --no-merge` is functionally equivalent to `/implement` (see "Validation" below), and the only thing `/implement-and-merge` adds on top of `/implement` is the CI+rebase+merge loop, the `:merged:` Slack reaction, local branch cleanup, and a main-verification step. Keeping two skills imposes a maintenance tax on every change to the implementation pipeline.

After this consolidation, there will be **one** skill named `/implement` that performs the full design → implement → PR → CI → merge → cleanup workflow, gated by an optional `--no-merge` flag for the "create PR but don't merge" case.

## Validation of the core claim

> **Claim**: `/implement-and-merge --no-merge` does the same thing as `/implement` today.

**Verdict: TRUE** (with only cosmetic differences).

Tracing both paths against the current `SKILL.md` files:

| Behavior | `/implement` standalone | `/implement-and-merge --no-merge` |
|---|---|---|
| Session setup tmpdir | `claude-impl-*` (its own) | `claude-implement-and-merge-*` parent + `claude-impl-*` child (reused via `--caller-env`) |
| Branch creation / `/design` invocation | Yes (Step 1) | Yes — delegated to `/implement` (Step 1) |
| Implementation + first commit | Yes (Steps 2–4) | Yes — delegated |
| Code review + second commit | Yes (Steps 5–7) | Yes — delegated |
| Code Flow Diagram | Yes (Step 7a) | Yes — delegated |
| Version bump | Yes (Step 8) | Yes — delegated |
| Create PR | Yes (Step 9) | Yes — delegated |
| Monitor CI and fix failures | Yes (Step 10) | Yes — delegated |
| Slack announcement | Yes (Step 11) | Yes — delegated |
| Rejected findings report | Yes (Step 12) | Yes — delegated (printed by `/implement` Step 12) |
| CI + rebase + merge loop | **No** | **Skipped** (Step 2 short-circuited by `no_merge=true`) |
| `:merged:` emoji on Slack post | **No** | **Skipped** (Step 3 short-circuited by `no_merge=true`) |
| Local branch cleanup | **No** | **Skipped** (Step 4 short-circuited by `no_merge=true`) |
| Verify main HEAD | **No** | **Skipped** (Step 5 short-circuited by `no_merge=true`) |
| Tmpdir cleanup | Yes (Step 13) | Yes (Step 7) — both child and parent tmpdirs are cleaned |
| Final reminder line | "Implementation complete! PR created but not merged." | "**Note: --no-merge was set. PR was created but not merged. Merge manually when ready.**" |

The actual feature work performed (design, code, review, version bump, PR, CI, Slack) is **identical** in both paths because `/implement-and-merge --no-merge` does that work by invoking `/implement`. The differences are:

1. An extra parent session-setup wrapper (cosmetic — child reuses caller env).
2. An extra summary line in `/implement-and-merge` Step 6.
3. The wording of the final completion line.

These differences are not load-bearing. The claim is validated.

## Phases

This work is split into **three PRs**, one per phase. Each phase is small enough to land cleanly and reversibly. Documentation is updated in every phase.

### Phase 1 — Inline `/implement`'s contents into `/implement-and-merge` (this PR)

Replace `/implement-and-merge`'s "Step 1: Invoke `/implement`" with the **full inlined workflow** that `/implement` performs today: design (or quick-mode inline plan), implement, validate, commit, code review, validate, commit, code flow diagram, version bump, create PR, monitor CI, post Slack announcement. After Phase 1, `/implement-and-merge` will perform the entire workflow itself, and will no longer invoke `/implement` at all.

This **deliberately creates duplication** between `/implement` and `/implement-and-merge` because Phase 2 deletes `/implement` immediately after.

**Phase 1 task list:**

- [x] Validate the "`/implement-and-merge --no-merge` ≈ `/implement`" claim by tracing both `SKILL.md` files.
- [x] Author this plan doc (`CONSOLIDATING_IMPLEMENT.md`) at the repo root with all three phases.
- [x] Inline the contents of `/implement` Steps 1–13 into `/implement-and-merge` `SKILL.md` in place of the existing Step 1 ("invoke `/implement`"), renumbering steps so the merged file has a single contiguous step sequence.
- [x] Update the emoji palette and Progress Reporting section in `/implement-and-merge` to cover all the inlined steps (design, implement, validate, commit, review, version bump, PR, CI, Slack) in addition to the existing CI+rebase+merge loop, `:merged:` emoji, cleanup, and verify-main steps.
- [x] Adjust internal references inside the new merged `SKILL.md` so that variable names, tmpdir names, and "see Step N" cross-references all point at the renumbered steps.
- [x] Switch the inlined PR-creation step to read `IMPLEMENT_AND_MERGE_TMPDIR` (the parent skill's tmpdir variable) instead of `IMPL_TMPDIR`. Likewise for `rejected-findings.md`, `pr-body.md`, `execution-issues.md`, `live-body.md`, and `session-env.sh`.
- [x] Keep **both** CI-monitoring loops in the merged skill: the inlined "Step 10" CI monitor (initial wait for green, so the Slack post in Step 11 links to a PR with passing CI) and the inlined "Step 12" CI+rebase+merge loop (handles main advancement and the actual merge). This preserves the exact behavior of the current `/implement-and-merge`-invokes-`/implement` chain (Slack sees a green PR), at the cost of two CI-poll passes. The user explicitly said not to worry about duplication. Phase 2 or 3 may collapse these into a single loop if desired.
- [x] Reference the helper script `.claude/skills/implement/scripts/check-review-changes.sh` from inside `/implement-and-merge` (the script lives under `/implement/` for now; Phase 2 will move/delete it).
- [x] Phase 1 PR runs through the new inlined `/implement-and-merge` itself (dogfooding) — it must successfully open a PR, monitor CI, rebase as needed, and merge.
- [x] Mark Phase 1 tasks complete in this doc as part of the Phase 1 PR.

**Phase 1 explicitly does NOT do:**

- Delete `/implement` (Phase 2 does that).
- Rename `/implement-and-merge` to `/implement` (Phase 3 does that).
- Update `/implement-and-merge`'s top-level description, allowed-tools, or `--no-merge` semantics — those still work the same way.
- Update other docs (`README.md`, `docs/workflow-lifecycle.md`, `docs/agents.md`, `docs/review-agents.md`, `.claude/skills/loop-review/SKILL.md`, `.claude/skills/design/SKILL.md`) beyond what is strictly necessary for Phase 1's correctness, because those references still describe a true state of the world (`/implement` still exists and is still callable). They will be cleaned up in Phases 2 and 3.

**Phase 1 acceptance criteria:**

- `/implement-and-merge` `SKILL.md` no longer contains the literal text "Invoke the `/implement` skill" anywhere in its workflow body.
- `/implement-and-merge` `SKILL.md` contains the full design+implement+review+PR workflow inline.
- `/implement` `SKILL.md` is **unchanged** (still exists, still callable standalone).
- The Phase 1 PR is created via the new inlined skill and merges green.

### Phase 2 — Delete `/implement` (next PR)

Delete the now-unused `/implement` skill and its helper script. Update all docs and cross-references.

**Phase 2 task list:**

- [ ] Delete `.claude/skills/implement/SKILL.md`.
- [ ] Delete `.claude/skills/implement/diagram.svg`.
- [ ] Move `.claude/skills/implement/scripts/check-review-changes.sh` to `.claude/skills/implement-and-merge/scripts/check-review-changes.sh` (or inline it into `/implement-and-merge` if it is small enough; decide during Phase 2).
- [ ] Update the Phase-1-inlined `SKILL.md` to point at the new script location.
- [ ] Delete the entire `.claude/skills/implement/` directory.
- [ ] Update `.claude/settings.json` to drop the `Bash($PWD/.claude/skills/implement/scripts/*)` permission (or update the path to point at the new location).
- [ ] Update `README.md`:
  - Remove `/implement` from the dependency chain (lines ~96–100).
  - Remove `/implement` from the skills table.
  - Update "Invoked automatically by `/implement` and `/review`" → "Invoked automatically by `/implement-and-merge` and `/review`" (or wait until Phase 3 when `/implement-and-merge` is renamed).
  - Update the Slack-integration bullet that mentions `/implement` posting PR announcements.
- [ ] Update `docs/workflow-lifecycle.md`:
  - Remove the `/implement-and-merge → /implement` arrow from the diagram.
  - Update the prose explanation of the chain.
  - Update the flag table to remove `/implement` as a row.
  - Update the "Skills can be used independently" section to remove the `/implement` standalone usage example (or replace it with `/implement-and-merge --no-merge`).
- [ ] Update `docs/agents.md` to remove the `/implement` example.
- [ ] Update `docs/review-agents.md` to remove the `/implement (quick mode)` row from the table.
- [ ] Update `.claude/skills/design/SKILL.md` to remove "(e.g., `/implement`)" examples and the "Run /implement to proceed" final printout.
- [ ] Update `.claude/skills/loop-review/SKILL.md` to remove `/implement` from the autonomous-skill chain enumeration in Step 0.
- [ ] Update `.claude/scripts/generic/larch/session-setup.sh` header comment to drop `/implement` from the list of callers.
- [ ] Update `.claude/scripts/generic/larch/rebase-push.sh` header comments to drop `/implement` references (or rephrase them to point at `/implement-and-merge`).
- [ ] Update `.claude/scripts/generic/larch/post-pr-announce.sh` header comment.
- [ ] Update `.claude/skills/shared/larch/voting-protocol.md` to point at `/implement-and-merge` Step 9a instead of `/implement` Step 9a.
- [ ] Update `tests/test-setup-larch.sh` if it specifically asserts the existence of the `/implement` skill directory.
- [ ] Update `.claude/skills/implement-and-merge/diagram.svg` if it depicts the now-merged subgraph (remove the "via `/implement`" caption).
- [ ] Update `.claude/skills/loop-review/diagram.svg` similarly.
- [ ] Update the Phase-1-inlined `SKILL.md` to remove the now-stale comment that says "this script lives under `/implement/` for now".
- [ ] Remove the "compatibility" `--no-merge` strip-and-print branch from anywhere it still lives.
- [ ] Mark Phase 2 tasks complete in this doc as part of the Phase 2 PR.

**Phase 2 acceptance criteria:**

- `.claude/skills/implement/` directory does not exist.
- No file in the repo (other than this plan doc and possibly `git log` history) references `/implement` as a callable skill name distinct from `/implement-and-merge`.
- `grep -rn "/implement\b" .claude docs README.md` returns either zero matches or only matches inside `/implement-and-merge` references.
- Phase 2 PR is created via `/implement-and-merge` and merges green.

### Phase 3 — Rename `/implement-and-merge` to `/implement` (final PR)

Rename the now-only skill from `/implement-and-merge` to `/implement`.

**Phase 3 task list:**

- [ ] Rename `.claude/skills/implement-and-merge/` to `.claude/skills/implement/`.
- [ ] Update the `name:` frontmatter in `SKILL.md` from `implement-and-merge` to `implement`.
- [ ] Update the `description:` frontmatter to drop the "via /implement" parenthetical and to mention `--no-merge` as an opt-out.
- [ ] Update the title heading inside `SKILL.md` from "Implement-and-Merge Skill" to "Implement Skill".
- [ ] Rename the tmpdir variable from `IMPLEMENT_AND_MERGE_TMPDIR` to a shorter name (e.g., `IMPLEMENT_TMPDIR` or just `TMPDIR`).
- [ ] Update the `session-setup.sh --prefix` argument from `claude-implement-and-merge` to `claude-implement` (or similar).
- [ ] Update `.claude/skills/implement-and-merge/diagram.svg` filename and contents to match the new skill name.
- [ ] Update `.claude/scripts/generic/larch/session-setup.sh` header comment.
- [ ] Update `README.md` table row and dependency chain.
- [ ] Update `docs/workflow-lifecycle.md` (skill name throughout, diagrams, flag table).
- [ ] Update `docs/agents.md`, `docs/review-agents.md`.
- [ ] Update `.claude/skills/loop-review/SKILL.md` and `diagram.svg` — every `/implement-and-merge` reference becomes `/implement`.
- [ ] Update `.claude/skills/design/SKILL.md` references.
- [ ] Update `.claude/skills/shared/larch/voting-protocol.md` references.
- [ ] Update `.claude/scripts/generic/larch/post-pr-announce.sh` header.
- [ ] Update `tests/test-setup-larch.sh` to assert the new symlink path/name.
- [ ] Update `.claude/settings.json` paths if any reference the old skill name (e.g., the helper script path from Phase 2).
- [ ] Search for any remaining literal `implement-and-merge` (with or without leading slash) and update or remove.
- [ ] Mark Phase 3 tasks complete in this doc as part of the Phase 3 PR.
- [ ] Delete `CONSOLIDATING_IMPLEMENT.md` itself in the Phase 3 PR (the work is complete and the doc is no longer load-bearing).

**Phase 3 acceptance criteria:**

- `.claude/skills/implement-and-merge/` directory does not exist.
- `.claude/skills/implement/` directory exists and contains the merged skill.
- `grep -rn "implement-and-merge" .` returns zero matches.
- `/implement` is callable as a slash command and performs the full workflow with optional `--no-merge`.
- Phase 3 PR is created via the renamed `/implement` and merges green.

## Risks and rollback

- **Phase 1 risk**: The inlined CI loop reconciliation is the one non-trivial step. If the merge-aware CI loop misbehaves after the merge, dogfooding the Phase 1 PR will surface it before merge.
- **Phase 2 risk**: Stale references to `/implement` in any forgotten file will cause future invocations to fail at skill-resolution time. Phase 2's acceptance check (`grep -rn "/implement\b"`) catches this.
- **Phase 3 risk**: Renaming a skill while preserving git history is straightforward (`git mv`), but cross-references in non-source files (diagrams, settings.json) must all be updated atomically.
- **Rollback strategy**: Each phase is one PR. If a phase introduces a regression, revert that PR. Phase 1 is the largest by line count but the least risky semantically (it is mostly copy-paste). Phase 2 is the most invasive in terms of file count but the smallest in semantic change. Phase 3 is purely a rename.
