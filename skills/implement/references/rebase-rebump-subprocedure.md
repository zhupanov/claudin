# Rebase + Re-bump Sub-procedure

**Consumer**: `/implement` Steps 10 and 12 — shared sub-procedure invoked from `ACTION=rebase`, `ACTION=rebase_then_evaluate`, and Phase 4 exit-0 paths. Includes the "Continue after child returns" anti-halt micro-reminder that travels with the `/bump-version` Skill-tool call per `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md`.

**Contract**: Authoritative source for the drop/rebase/fast-forward/bump/push/PR-body-refresh sequence. All `caller_kind` tokens (`step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`, `step10_rebase`, `step10_rebase_then_evaluate`) are contract tokens — do NOT rename. The #172 STATUS-first evaluation ordering is the degraded-git fail-closed enforcement point for Step 12 (Load-Bearing Invariant #3 in SKILL.md).

**When to load**: before invoking the sub-procedure from Step 10 (any `ACTION=rebase*` return from `ci-wait.sh`), before invoking from Step 12a (any `ACTION=rebase*` return), or at the entry of Step 12 Phase 4's `rebase-push.sh --continue` exit-0 handler. Do NOT load when Step 12's `merge=false` or `repo_unavailable=true` early-exits fire, or when Step 10's `ACTION=merge` / `already_merged` / `evaluate_failure` / `bail` is returned.

---

After the initial version bump in Step 8, every subsequent rebase of the feature branch onto latest `origin/main` must be followed by a fresh `/bump-version` run so the merged state reflects the version in latest main **at merge time**, not at PR-creation time. This sub-procedure consolidates the drop/rebase/fast-forward/bump/push/refresh sequence so that Steps 10 and 12 can invoke it from multiple places without duplication.

## Inputs
- `rebase_already_done` — if `true`, steps 1–2 are skipped (the rebase has already happened and been pushed by the caller, e.g., Step 12 Phase 4's `rebase-push.sh --continue`). If `false`, the sub-procedure performs the rebase itself.
- `caller_kind` — one of: `step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`, `step10_rebase`, `step10_rebase_then_evaluate`. Determines:
  1. **Post-return control flow** (re-invoke `ci-wait.sh`, fall through to 12c, fall through to Step 10's evaluate_failure handler, etc.)
  2. **Failure semantics** — grouped into two caller families:
     - **step12 family** (`step12_rebase`, `step12_rebase_then_evaluate`, `step12_phase4`): any hard failure below bails to **Step 12d**. Step 12 is the last-chance enforcement point for the version bump freshness invariant, so it must not silently proceed to merge.
     - **step10 family** (`step10_rebase`, `step10_rebase_then_evaluate`): any hard failure below logs a warning and **breaks out of Step 10's loop to Step 11**, matching Step 10's existing "never block the pipeline" philosophy. Step 12 will re-run this sub-procedure under strict semantics before merging, so Step 10 failures degrade gracefully.
  3. **Conflict fallback path** — `step12_*` falls back to a full `rebase-push.sh` + the Conflict Resolution Procedure (Phase 1–4, defined in `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/conflict-resolution.md`) when `--no-push` exit 1 happens; `step10_*` logs a warning and breaks out of Step 10 to Step 11 (Step 10 has no Phase 1–4).

## Happy path (`rebase_already_done=false`)

1. **Drop existing bump commit**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/drop-bump-commit.sh
   ```
   Parse `DROPPED`. If `DROPPED=false`, log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Warnings`: `Step <N> — drop-bump-commit.sh reported DROPPED=false before rebase; HEAD was not a bump commit (CI fix commit may have landed on top, worktree was dirty, or the commit touched files other than .claude-plugin/plugin.json). Re-bump will still run but branch history may temporarily contain two bump commits and the rebase may encounter a plugin.json conflict routed through Phase 1–3.` Continue to step 2. (The guard in `drop-bump-commit.sh` is defense-in-depth — the sub-procedure does not treat `DROPPED=false` as a hard failure.)

2. **Rebase without pushing**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh --no-push
   ```
   - **Exit 0** (rebase clean, branch is local-only fresh — may include `SKIPPED_ALREADY_FRESH=true`): proceed to step 3.
   - **Exit 1** (conflict; `--no-push` has already called `git rebase --abort`, so no rebase is in progress — the two invocations are independent, any fallback call restarts a fresh fetch + rebase):
     - **step12 family**: **fall back to full `${CLAUDE_PLUGIN_ROOT}/scripts/rebase-push.sh`** (without `--no-push`). Enumerate all four exit codes of the fallback call:
       - **Fallback exit 0**: rebase succeeded cleanly AND the branch was force-pushed by the fallback call. Proceed to step 3. Note: `rebase_already_done` is NOT set here — that flag only gates sub-procedure steps 1–2 at entry, and by this point those steps have already executed. Step 5's push will land the new bump commit on top of the fallback's push (the intended double-push for the conflict-fallback path, necessarily two pushes because the fallback call couldn't avoid pushing).
       - **Fallback exit 1**: conflict; rebase is in progress. Enter the **Conflict Resolution Procedure** (Phase 1–4, defined in `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/conflict-resolution.md`). **Phase 4's `rebase-push.sh --continue` exit-0 handler (at the end of the Conflict Resolution Procedure) itself dispatches this sub-procedure with `rebase_already_done=true, caller_kind=step12_phase4`** — i.e., the post-conflict re-bump is owned entirely by Phase 4. **Control transfer is terminal**: the moment Phase 1 is entered, the current (fallback) sub-procedure invocation is conceptually suspended and its remaining steps 3–7 are NOT executed. All further action for this rebase (Phase 2, Phase 3, Phase 4, and the sub-procedure dispatched by Phase 4's exit-0 handler) runs under Phase 4's ownership. When Phase 4 completes (success or bail), it returns control directly to Step 12's outer loop via its own caller-return path — it does NOT return back into the current invocation. Do NOT continue executing steps 3–7 of the current invocation, regardless of whether Phase 4 succeeds or bails.
       - **Fallback exit 2**: `force-with-lease` push failure after a successful rebase. The rebase is complete locally but the branch has NOT been pushed. Do NOT skip steps 3–4: proceed to step 3 (fast-forward local main), then step 4 (re-bump), then step 5 (which will try to push the re-bumped branch and apply its own fetch + compare + retry + bail recovery on any subsequent push failure). Setting `rebase_already_done` is NOT appropriate here because step 5 still needs to push. This is the only way to guarantee the freshness invariant is enforced — skipping straight to step 5's recovery would push a rebased-but-unbumped branch, silently violating the invariant.
       - **Fallback exit 3**: non-conflict rebase failure; rebase already aborted. Read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase conflict, deferring to Step 12. Proceeding to Step 11.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. **Break out of Step 10's loop and proceed to Step 11.**
   - **Exit 3** (non-conflict rebase failure in `--no-push` mode; rebase already aborted):
     - **step12 family**: read `REBASE_ERROR` and bail to 12d.
     - **step10 family**: print `**⚠ 10: CI monitor — rebase failed: $REBASE_ERROR. Proceeding to Step 11.**` Log to `CI Issues`. Break to Step 11.

3. **Fast-forward local `main` to `origin/main`**:
   `rebase-push.sh` refreshes `origin/main` via `git fetch`, but local `main` is not automatically updated. `classify-bump.sh` prefers local `main` for its `merge-base` computation, so without this step `BASE` could point to an older commit than the one the branch was just rebased onto, causing the classifier's diff to include commits that belong to main (not the feature).
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/git-sync-local-main.sh
   ```
   The wrapper silently no-ops when the local `main` ref does not exist (expected in that case — `classify-bump.sh` has an `origin/main` fallback). It refuses to run if the caller is accidentally on `main` (exit 1) — defense against accidental self-update. Parse `RESULT=updated|absent|already_current` from stdout for telemetry.

4. **Re-bump**:
   Follow the same sequence as Step 8, with caller-family-specific error handling:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode pre
   ```
   Parse `HAS_BUMP`, `COMMITS_BEFORE`, and `STATUS`. The `STATUS=ok|missing_main_ref|git_error` field (#172) is authoritative for degraded-git detection — do NOT grep stderr for the old `WARN: ... neither local 'main' nor 'origin/main' exists` line.

   **Pre-check STATUS guard (#172)**: If pre-check `STATUS != ok`, `COMMITS_BEFORE` is the script's coerced 0 value, not a trustworthy baseline count. A subsequent post-check that recovers to `STATUS=ok` with a correct bump commit would compute `EXPECTED = 0 + 1 = 1` but would see the true `COMMITS_AFTER = N_prior + 1`, routing the sub-procedure to a bogus "wrong commit count" hard-bail. To prevent this mis-diagnosis:
   - **step12 family**: **HARD FAILURE** — bail to 12d immediately. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported pre-check STATUS=$STATUS (baseline untrustworthy). Cannot safely verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. Rationale: without a trustworthy baseline, the post-check comparison is meaningless — the merged version cannot be guaranteed correct.
   - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported pre-check STATUS=$STATUS (baseline untrustworthy). Skipping numeric-delta verification; Step 12 will re-verify.**` to `CI Issues`, then:
     - **If `HAS_BUMP=false`** (no `/bump-version` skill installed): skip the `/bump-version` invocation entirely and proceed directly to step 5 (push) → step 6 → step 7 — same as the `HAS_BUMP=false` path under `STATUS=ok` below. Do NOT attempt to call a skill that does not exist.
     - **If `HAS_BUMP=true`**: invoke `/bump-version` via the Skill tool anyway (the rebase still needs its re-bump commit), but **SKIP the post-check commit-delta verification below** since the baseline is untrustworthy. After `/bump-version` returns, skip directly to step 5 (push) → step 6 (PR body refresh) → step 7 (return to caller). The post-check `STATUS`-first branches below and the numeric-comparison branches both rely on a trustworthy pre-check baseline that this invocation does not have.

   Only if pre-check `STATUS=ok`, proceed with the bump workflow below:
   - **If `HAS_BUMP=false`**:
     - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version not found, cannot re-bump. Bailing to 12d.**` Bail to 12d.
     - **step10 family**: Print `**⚠ 10: CI monitor — /bump-version not found, skipping re-bump. Proceeding to Step 11.**` Log to `Warnings`. Skip ahead to step 5 — the push still needs to happen because the rebase in step 2 rewrote branch history, and that rewritten history must be force-pushed so the remote PR branch reflects the new base (there is just no new bump commit stacked on top). Then fall through to step 6 (PR body refresh — nothing new to refresh) and step 7 (return to caller).
   - **If `HAS_BUMP=true`**:

     > **Continue after child returns.** When `/bump-version` returns, execute the NEXT steps of this sub-procedure in order — do NOT end the turn. The first mandatory action is the post-verification block immediately below (commit-delta check via `check-bump-version.sh --mode post`, then the sentinel-file check); only after those gates pass do you proceed to step 4a's CHANGELOG re-apply, step 5's push, step 6's PR body refresh, and step 7's return to caller. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

     Invoke `/bump-version` via the Skill tool. If the skill invocation itself fails (returns an error, or bails internally):
     - **step12 family**: hard failure — bail to 12d.
     - **step10 family**: log warning and break out of Step 10 to Step 11.
     After the skill returns successfully, run the post-verification — see `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/bump-verification.md` Block β for the full STATUS-handling matrix (step12 vs step10 family, STATUS-first ordering, sentinel-file defense-in-depth):
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode post --before-count $COMMITS_BEFORE
     ```
     Apply the Block β decision matrix from `bump-verification.md`, then proceed to step 4a.

   **Rationale**: Step 8's permissive warnings are safe because Step 8 is pre-PR — no merge can happen based on a missing bump. Step 12 is pre-merge — missing bump means stale merge. Step 10 is post-PR but pre-merge (Step 12 does the merge) — any bump failure in Step 10 is recoverable by Step 12's mandatory re-bump, so Step 10 can afford to be permissive. **Step 12 is the last-chance enforcement point; Step 10 is best-effort optimization that improves freshness during the CI-wait phase (which also covers any `--slack` announcement).**

4a. **Re-apply CHANGELOG update** (mirrors Step 8a):
   If `CHANGELOG.md` exists in the project root (check via Read tool) and a new bump commit was created (`VERIFIED=true` from step 4), update the CHANGELOG entry to reflect the new version from the re-bump. Follow the same logic as Step 8a: read `CHANGELOG.md`, compose an entry with the `NEW_VERSION` from the re-bump and the same Summary bullets, insert it (or replace the existing entry for the prior version if present), stage, and amend the bump commit via `${CLAUDE_PLUGIN_ROOT}/scripts/git-amend-add.sh CHANGELOG.md`. If CHANGELOG.md does not exist or the bump was skipped, skip this sub-step silently. **This is best-effort and non-blocking** — failure to update CHANGELOG does not affect the bump or push.

5. **Push with recovery**:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/git-force-push.sh
   ```
   The wrapper performs `git push --force-with-lease` with the full recovery logic internally: on failure, it refreshes the local tracking ref, compares local HEAD vs `origin/<branch>`, returns success if they match (race landed), otherwise sleeps 5s and retries the push once. Parse stdout for `PUSHED=true|false` and `STATUS=pushed|noop_same_ref|diverged_retry_failed`. Exit code 0 on success (PUSHED=true), exit code 1 on `diverged_retry_failed`.

   - **On `STATUS=pushed` or `STATUS=noop_same_ref`** (PUSHED=true): proceed to step 6.
   - **On `STATUS=diverged_retry_failed`** (PUSHED=false): log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`: `Step <N> — force-with-lease push failed twice; local and remote feature branches diverge after re-bump.` Then:
     - **step12 family**: bail to 12d with error `12: CI+merge loop — re-bump push failed twice, remote diverged. Manual intervention required.`
     - **step10 family**: print `**⚠ 10: CI monitor — re-bump push failed twice. Proceeding to Step 11 (may be stale).**` Break to Step 11.

   **Critical (step12 family only)**: Do NOT simply "log and return to caller" on push failure. That would let the merge loop proceed to `ACTION=merge` on a remote branch that does NOT contain the fresh bump commit, violating the feature's core invariant. `ci-wait.sh` and `merge-pr.sh` operate on remote PR state only; they cannot see unpushed local commits.

6. **Refresh PR body Version Bump Reasoning block**:
   After `/bump-version` runs in step 4 above, capture the new reasoning-file path from its `REASONING_FILE=<path>` output line and use it as `$BUMP_REASONING_FILE` (same semantics as Step 8 — see that step for details on why the path must be parsed from stdout rather than constructed from `$IMPLEMENT_TMPDIR`). If `$BUMP_REASONING_FILE` exists and is non-empty:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-read.sh --pr <PR_NUMBER> --output "$IMPLEMENT_TMPDIR/live-body.md"
   ```
   Read `$IMPLEMENT_TMPDIR/live-body.md`, replace the entire inner content of the `<details><summary>Version Bump Reasoning</summary>...</details>` block with the current contents of `$BUMP_REASONING_FILE` (preserving blank lines after the opening tag and before the closing `</details>` for GitHub Markdown rendering — see `${CLAUDE_PLUGIN_ROOT}/skills/implement/references/pr-body-template.md` for the template). Write the result to `$IMPLEMENT_TMPDIR/pr-body.md` (same file Step 11 writes to, so subsequent refreshes operate on the fresh canonical copy). Then:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/gh-pr-body-update.sh --pr <PR_NUMBER> --body-file "$IMPLEMENT_TMPDIR/pr-body.md"
   ```
   If the `<details><summary>Version Bump Reasoning</summary>` marker is not found in the fetched body, print `**⚠ Step <N> — Version Bump Reasoning block not found in live PR body. Skipping refresh.**` and skip the update. Log to `Warnings`. **PR body refresh failure is NOT a hard failure** — the bump is already pushed and the merge will be correct; the stale body is documentation-only.

7. **Return to caller based on `caller_kind`**:
   - **`step12_rebase`** (from 12a `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30` (give GitHub CI time to register the force-push before polling again), then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_phase4`** (from Phase 4 exit-0): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 12.
   - **`step12_rebase_then_evaluate`** (from 12a `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to 12c** to evaluate the CI failure. Do NOT re-invoke `ci-wait.sh` and do NOT sleep — 12c handles its own timing.
   - **`step10_rebase`** (from Step 10 `ACTION=rebase`): increment `rebase_count`, `iteration`, reset `transient_retries`, **sleep 30s** via `${CLAUDE_PLUGIN_ROOT}/scripts/sleep-seconds.sh 30`, then re-invoke `ci-wait.sh` in Step 10.
   - **`step10_rebase_then_evaluate`** (from Step 10 `ACTION=rebase_then_evaluate`): increment `rebase_count`, `iteration`, reset `transient_retries`, then **fall through to Step 10's `ACTION=evaluate_failure` handler**. Do NOT re-invoke `ci-wait.sh` and do NOT sleep.

## Phase 4 caller path (`rebase_already_done=true`, `caller_kind=step12_phase4`)

Phase 4 enters the sub-procedure AFTER `rebase-push.sh --continue` has already pushed the resolved rebase. **Skip steps 1–2 entirely.** Still run steps 3 (fast-forward local main), 4 (re-bump with step12 hard-failure semantics), 5 (push with recovery), 6 (PR body refresh), 7 (return with `step12_phase4`). This path necessarily double-pushes (Phase 4 pushed the rebase, then step 5 pushes the new bump), but the Conflict Resolution Procedure is rare enough that the second push cost is acceptable.
