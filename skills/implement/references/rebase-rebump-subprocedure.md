# Rebase + Re-bump Sub-procedure

**Consumer**: `/implement` Steps 10 and 12 — shared sub-procedure invoke from `ACTION=rebase`, `ACTION=rebase_then_evaluate`, Phase 4 exit-0 paths.

**Contract**: Byte-preserving extract from `skills/implement/SKILL.md` L758–898 include "Continue after child returns" anti-halt reminder at original L821 (travel with `/bump-version` Skill-tool call per intent of `skills/shared/subskill-invocation.md`). All `caller_kind` tokens (`step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`, `step10_rebase`, `step10_rebase_then_evaluate`) contract tokens — do NOT rename. #172 STATUS-first evaluation order = degraded-git fail-closed enforce point for Step 12 (Load-Bearing Invariant #3 in SKILL.md).

**When to load**: before invoke sub-procedure from Step 10 (any `ACTION=rebase*` return from `ci-wait.sh`), before invoke from Step 12a (any `ACTION=rebase*` return), or at entry of Step 12 Phase 4 `rebase-push.sh --continue` exit-0 handler. Do NOT load when Step 12 `merge=false` or `repo_unavailable=true` early-exits fire, or when Step 10 `ACTION=merge` / `already_merged` / `evaluate_failure` / `bail` returned.

---

After initial version bump in Step 8, every later rebase of feature branch onto latest `origin/main` must follow with fresh `/bump-version` run so merged state reflect version in latest main **at merge time**, not at PR-create time. Sub-procedure consolidate drop/rebase/fast-forward/bump/push/refresh sequence so Steps 10 and 12 invoke from many places without duplicate.

## Inputs
- `rebase_already_done` — if `true`, steps 1–2 skip (rebase already happen and push by caller, e.g., Step 12 Phase 4 `rebase-push.sh --continue`). If `false`, sub-procedure do rebase itself.
- `caller_kind` — one of: `step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`, `step10_rebase`, `step10_rebase_then_evaluate`. Determine:
  1. **Post-return control flow** (re-invoke `ci-wait.sh`, fall through to 12c, fall through to Step 10 evaluate_failure handler, etc.)
  2. **Failure semantics** — group to two caller family:
     - **step12 family** (`step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`): any hard fail below bail to **Step 12d**. Step 12 = last-chance enforce point for version bump freshness invariant, must not silently proceed to merge.
     - **step10 family** (`step10_rebase`, `step10_rebase_then_evaluate`): any hard fail below log warning and **break out of Step 10 loop to Step 11**, match Step 10 existing "never block the pipeline" philosophy. Step 12 will re-run this sub-procedure under strict semantics before merge, so Step 10 fails degrade gracefully.
  3. **Conflict fallback path** — `step12_*` fall back to full `rebase-push.sh` + Conflict Resolution Procedure (Phase 1–4, defined in `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/conflict-resolution.md`) when `--no-push` exit 1 happens; `step10_*` log warning and break out of Step 10 to Step 11 (Step 10 no Phase 1–4).

## Happy path (`rebase_already_done=false`)

1. **Drop existing bump commit**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/drop-bump-commit.sh
   ```
   Parse `DROPPED`. If `DROPPED=false`, log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Warnings`: `Step <N> — drop-bump-commit.sh reported DROPPED=false before rebase; HEAD was not a bump commit (CI fix commit may have landed on top, worktree was dirty, or the commit touched files other than .claude-plugin/plugin.json). Re-bump will still run but branch history may temporarily contain two bump commits and the rebase may encounter a plugin.json conflict routed through Phase 1–3.` Continue to step 2. (Guard in `drop-bump-commit.sh` = defense-in-depth — sub-procedure not treat `DROPPED=false` as hard fail.)

2. **Rebase without push**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push
   ```
   - **Exit 0** (rebase clean, branch local-only fresh — may include `SKIPPED_ALREADY_FRESH=true`): proceed to step 3.
   - **Exit 1** (conflict; `--no-push` already call `git rebase --abort`, so no rebase in progress — two invocations independent, any fallback call restart fresh fetch + rebase):
     - **step12 family**: **fall back to full `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh`** (without `--no-push`). Enumerate all four exit codes of fallback call:
       - **Fallback exit 0**: rebase succeed clean AND branch force-pushed by fallback call. Proceed to step 3. Note: `rebase_already_done` NOT set here — flag only gate sub-procedure steps 1–2 at entry, and by this point those steps already ran. Step 5 push land new bump commit on top of fallback push (intended double-push for conflict-fallback path, necessarily two pushes because fallback call cannot avoid pushing).
       - **Fallback exit 1**: conflict; rebase in progress. Enter **Conflict Resolution Procedure** (Phase 1–4, defined in `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/conflict-resolution.md`). **Phase 4 `rebase-push.sh --continue` exit-0 handler (at end of Conflict Resolution Procedure) itself dispatch this sub-procedure with `rebase_already_done=true, caller_kind=step12_phase4`** — i.e., post-conflict re-bump owned entirely by Phase 4. **Control transfer terminal**: moment Phase 1 enter, current (fallback) sub-procedure invocation conceptually suspended and remaining steps 3–7 NOT execute. All further action for this rebase (Phase 2, Phase 3, Phase 4, and sub-procedure dispatched by Phase 4 exit-0 handler) run under Phase 4 ownership. When Phase 4 complete (success or bail), return control directly to Step 12 outer loop via own caller-return path — NOT return back into current invocation. Do NOT continue execute steps 3–7 of current invocation, regardless of Phase 4 succeed or bail.
       - **Fallback exit 2**: `force-with-lease` push fail after successful rebase. Rebase complete locally but branch NOT pushed. Do NOT skip steps 3–4: proceed to step 3 (fast-forward local main), then step 4 (re-bump), then step 5 (will try push re-bumped branch and apply own fetch + compare + retry + bail recovery on any later push fail). Set `rebase_already_done` NOT appropriate here because step 5 still need push. This = only way to guarantee freshness invariant enforced — skip straight to step 5 recovery would push rebased-but-unbumped branch, silently violate invariant.
       - **Fallback exit 3**: non-conflict rebase fail; rebase already aborted. Read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase conflict, deferring to Step 12. Proceeding to Step 11.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. **Break out of Step 10 loop and proceed to Step 11.**
   - **Exit 3** (non-conflict rebase fail in `--no-push` mode; rebase already aborted):
     - **step12 family**: read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase failed: $REBASE_ERROR. Proceeding to Step 11.**` Log to `CI Issues`. Break to Step 11.

3. **Fast-forward local `main` to `origin/main`**:
   `rebase-push.sh` refresh `origin/main` via `git fetch`, but local `main` not auto-update. `classify-bump.sh` prefer local `main` for `merge-base` compute, so without this step `BASE` could point to older commit than one branch just rebased onto, cause classifier diff to include commits belong to main (not feature).
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/git-sync-local-main.sh
   ```
   Wrapper silent no-op when local `main` ref not exist (expected in that case — `classify-bump.sh` has `origin/main` fallback). Refuse to run if caller accidentally on `main` (exit 1) — defense against accidental self-update. Parse `RESULT=updated|absent|already_current` from stdout for telemetry.

4. **Re-bump**:
   Follow same sequence as Step 8, with caller-family-specific error handling:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode pre
   ```
   Parse `HAS_BUMP`, `COMMITS_BEFORE`, and `STATUS`. `STATUS=ok|missing_main_ref|git_error` field (#172) = authoritative for degraded-git detect — do NOT grep stderr for old `WARN: ... neither local 'main' nor 'origin/main' exists` line.

   **Pre-check STATUS guard (#172)**: If pre-check `STATUS != ok`, `COMMITS_BEFORE` = script coerced 0 value, not trustworthy baseline count. Later post-check that recover to `STATUS=ok` with correct bump commit would compute `EXPECTED = 0 + 1 = 1` but see true `COMMITS_AFTER = N_prior + 1`, route sub-procedure to bogus "wrong commit count" hard-bail. Prevent mis-diagnosis:
   - **step12 family**: **HARD FAILURE** — bail to 12d immediately. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported pre-check STATUS=$STATUS (baseline untrustworthy). Cannot safely verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. Rationale: without trustworthy baseline, post-check compare meaningless — merged version cannot guarantee correct.
   - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported pre-check STATUS=$STATUS (baseline untrustworthy). Skipping numeric-delta verification; Step 12 will re-verify.**` to `CI Issues`, then:
     - **If `HAS_BUMP=false`** (no `/bump-version` skill installed): skip `/bump-version` invocation entirely and proceed direct to step 5 (push) → step 6 → step 7 — same as `HAS_BUMP=false` path under `STATUS=ok` below. Do NOT try call skill that not exist.
     - **If `HAS_BUMP=true`**: invoke `/bump-version` via Skill tool anyway (rebase still need re-bump commit), but **SKIP post-check commit-delta verification below** since baseline untrustworthy. After `/bump-version` return, skip direct to step 5 (push) → step 6 (PR body refresh) → step 7 (return to caller). Post-check `STATUS`-first branches below and numeric-compare branches both rely on trustworthy pre-check baseline this invocation not have.

   Only if pre-check `STATUS=ok`, proceed with bump workflow below:
   - **If `HAS_BUMP=false`**:
     - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version not found, cannot re-bump. Bailing to 12d.**` Bail to 12d.
     - **step10 family**: Print `**⚠ 10: CI monitor — /bump-version not found, skipping re-bump. Proceeding to Step 11.**` Log to `Warnings`. Skip ahead to step 5 — push still need happen because rebase in step 2 rewrote branch history, and rewrote history must force-push so remote PR branch reflect new base (just no new bump commit stack on top). Then fall through to step 6 (PR body refresh — nothing new to refresh) and step 7 (return to caller).
   - **If `HAS_BUMP=true`**:

     > **Continue after child returns.** When `/bump-version` returns, execute the NEXT steps of this sub-procedure in order — do NOT end the turn. The first mandatory action is the post-verification block immediately below (commit-delta check via `check-bump-version.sh --mode post`, then the sentinel-file check); only after those gates pass do you proceed to step 4a's CHANGELOG re-apply, step 5's push, step 6's PR body refresh, and step 7's return to caller. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

     Invoke `/bump-version` via Skill tool. If skill invocation itself fail (return error, or bail internally):
     - **step12 family**: hard fail — bail to 12d.
     - **step10 family**: log warning and break out of Step 10 to Step 11.
     After skill return successfully, run post-verification — see `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/bump-verification.md` Block β for full STATUS-handle matrix (step12 vs step10 family, STATUS-first order, sentinel-file defense-in-depth):
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
     ```
     Apply Block β decision matrix from `bump-verification.md`, then proceed to step 4a.

   **Rationale**: Step 8 permissive warnings safe because Step 8 = pre-PR — no merge can happen based on missing bump. Step 12 = pre-merge — missing bump mean stale merge. Step 10 = post-PR but pre-merge (Step 12 do the merge) — any bump fail in Step 10 recoverable by Step 12 mandatory re-bump, so Step 10 can afford permissive. **Step 12 = last-chance enforce point; Step 10 = best-effort optimize that improve freshness during Slack-wait phase.**

4a. **Re-apply CHANGELOG update** (mirror Step 8a):
   If `CHANGELOG.md` exist in project root (check via Read tool) and new bump commit created (`VERIFIED=true` from step 4), update CHANGELOG entry to reflect new version from re-bump. Follow same logic as Step 8a: read `CHANGELOG.md`, compose entry with `NEW_VERSION` from re-bump and same Summary bullets, insert (or replace existing entry for prior version if present), stage, and amend bump commit via `${CLAUDE_PLUGIN_ROOT}/scripts/git-amend-add.sh CHANGELOG.md`. If CHANGELOG.md not exist or bump skipped, skip sub-step silently. **Best-effort and non-blocking** — fail to update CHANGELOG not affect bump or push.

5. **Push with recovery**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/git-force-push.sh
   ```
   Wrapper do `git push --force-with-lease` with full recovery logic internal: on fail, refresh local tracking ref, compare local HEAD vs `origin/<branch>`, return success if match (race landed), else sleep 5s and retry push once. Parse stdout for `PUSHED=true|false` and `STATUS=pushed|noop_same_ref|diverged_retry_failed`. Exit code 0 on success (PUSHED=true), exit code 1 on `diverged_retry_failed`.

   - **On `STATUS=pushed` or `STATUS=noop_same_ref`** (PUSHED=true): proceed to step 6.
   - **On `STATUS=diverged_retry_failed`** (PUSHED=false): log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`: `Step <N> — force-with-lease push failed twice; local and remote feature branches diverge after re-bump.` Then:
     - **step12 family**: bail to 12d with error `12: CI+merge loop — re-bump push failed twice, remote diverged. Manual intervention required.`
     - **step10 family**: print `**⚠ 10: CI monitor — re-bump push failed twice. Proceeding to Step 11 (may be stale).**` Break to Step 11.

   **Critical (step12 family only)**: Do NOT simply "log and return to caller" on push fail. That would let merge loop proceed to `ACTION=merge` on remote branch that NOT contain fresh bump commit, violate feature core invariant. `ci-wait.sh` and `merge-pr.sh` operate on remote PR state only; cannot see unpushed local commits.

6. **Refresh PR body Version Bump Reasoning block**:
   After `/bump-version` run in step 4 above, capture new reasoning-file path from its `REASONING_FILE=<path>` output line and use as `$BUMP_REASONING_FILE` (same semantics as Step 8 — see that step for details on why path must parse from stdout rather than construct from `$IMPLEMENT_TMPDIR`). If `$BUMP_REASONING_FILE` exist and non-empty:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md`, replace entire inner content of `<details><summary>Version Bump Reasoning</summary>...</details>` block with current contents of `$BUMP_REASONING_FILE` (preserve blank lines after open tag and before close `</details>` for GitHub Markdown render — see `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/pr-body-template.md` for template). Write result to `$IMPLEMENT_TMPDIR/pr-body.md` (same file Step 11 write to, so later refreshes operate on fresh canonical copy). Then:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```
   If `<details><summary>Version Bump Reasoning</summary>` marker not found in fetched body, print `**⚠ Step <N> — Version Bump Reasoning block not found in live PR body. Skipping refresh.**` and skip update. Log to `Warnings`. **PR body refresh fail NOT hard fail** — bump already pushed and merge will be correct; stale body = documentation-only.

7. **Return to caller based on `caller_kind`**:
   - **`step12_rebase`** (from 12a `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30` (give GitHub CI time to register force-push before poll again), then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_phase4`** (from Phase 4 exit-0): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_rebase_then_evaluate`** (from 12a `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to 12c** to evaluate CI fail. Do NOT re-invoke `ci-wait.sh` and do NOT sleep — 12c handle own timing.
   - **`step10_rebase`** (from Step 10 `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 10.
   - **`step10_rebase_then_evaluate`** (from Step 10 `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to Step 10 `ACTION=evaluate_failure` handler**. Do NOT re-invoke `ci-wait.sh` and do NOT sleep.

## Phase 4 caller path (`rebase_already_done=true`, `caller_kind=step12_phase4`)

Phase 4 enter sub-procedure AFTER `rebase-push.sh --continue` already pushed resolved rebase. **Skip steps 1–2 entirely.** Still run steps 3 (fast-forward local main), 4 (re-bump with step12 hard-fail semantics), 5 (push with recovery), 6 (PR body refresh), 7 (return with `step12_phase4`). This path necessarily double-push (Phase 4 pushed rebase, then step 5 push new bump), but Conflict Resolution Procedure rare enough that second push cost acceptable.
