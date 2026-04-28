# Bump Verification STATUS Handling

**Consumer**: `/implement` Step 8 post-check (Block α), Step 8 step 3b sentinel defense-in-depth (Block γ), and Rebase + Re-bump Sub-procedure step 4 post-check (Block β) — the authoritative `check-bump-version.sh --mode post` STATUS-handling matrix and reasoning-file sentinel contract for all callers.

**Contract**: Authoritative source for post-`/bump-version` verification. The two callers have distinct failure semantics — Block α is Step 8's permissive pre-PR handling; Block β is the sub-procedure's strict step12-family handling (with step10-family degraded-graceful variant and step8b-family strict-but-stall-routed variant). Block γ covers the reasoning-file sentinel check (#160 defense-in-depth). The #172 fail-closed invariant is authoritative across all blocks: `STATUS != ok` forces `VERIFIED=false` at the script level. Do NOT synthesize or merge the α/β caller-family semantics.

**When to load**: before executing Step 8 step 3 post-verification (Block α + Block γ) or the sub-procedure step 4 post-verification (Block β + Block γ). Do NOT load when `HAS_BUMP=false` (bump skipped entirely) or when the sub-procedure's pre-check `STATUS != ok` (numeric post-check is already bypassed upstream).

---

## Block α — Step 8 post-check STATUS handling

   **First**: if the pre-check STATUS was non-`ok` (baseline untrustworthy per the warning above), skip the numeric-comparison branches below — the `EXPECTED = COMMITS_BEFORE + 1` arithmetic is built on a coerced 0 baseline, so any mismatch with the true `COMMITS_AFTER` is meaningless. Log `**⚠ 8: version bump — pre-check was degraded; skipping post-check numeric verification. Step 12 will re-verify under strict semantics.**` to `Warnings` and continue to Step 8a.

   Otherwise (pre-check `STATUS=ok`), parse the post-check output for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, and `STATUS`. `STATUS != ok` (the #172 fail-closed invariant) forces `VERIFIED=false` at the script level independently of the numeric comparison — do not try to second-guess it. Handling:
   - **`STATUS=git_error`**: print `**⚠ 8: version bump — post-check STATUS=git_error, commit count untrustworthy. Continuing (Step 12 will re-verify under strict semantics).**`, log to `Warnings`, and continue. Do NOT treat this as a bump failure requiring manual intervention.
   - **`STATUS=missing_main_ref`**: same handling as `git_error` — log warning, continue.
   - **`STATUS=ok` AND `VERIFIED=false`**: the normal "wrong commit count" path — print `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`.
   - **`STATUS=ok` AND `VERIFIED=true`**: proceed.

---

## Block β — Rebase + Re-bump Sub-procedure step 4 post-check STATUS handling

     Parse `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, and `STATUS`. **Evaluate `STATUS` FIRST** — before the `VERIFIED`/`COMMITS` comparison. A non-`ok` status means the count is 0-by-coercion (not a legitimate "0 commits ahead" result), and `VERIFIED` has already been forced to `false` by the script itself. Do not route such cases through the numeric-comparison branches below, which would emit a misleading "BUMP_TYPE=NONE or missing main ref" message when the true cause is a transient git error:

     - **`STATUS=git_error`** (rev-list failed against a valid base ref — corrupted pack, shallow-clone object boundary, permission error):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=git_error after re-bump (git rev-list failed against a valid base ref). Cannot verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. Rationale: Step 12 is the last-chance enforcement point for the version bump freshness invariant; a transient git error that masks the count means we cannot guarantee the merged version is correct.
       - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=git_error after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, then proceed directly to step 5 (rebased history must be force-pushed). Skip ahead past the numeric-comparison branches below to step 6 and step 7.
       - **step8b family**: **HARD FAILURE** — set `STALL_TRACKING=true` in parent scope and skip to Step 18. Print `**⚠ 8b: rebase — check-bump-version.sh reported STATUS=git_error after re-bump (git rev-list failed against a valid base ref). Cannot verify bump freshness. Setting STALL_TRACKING=true and skipping to Step 18.**` Log to `CI Issues`. Rationale: Step 8b is the practical last enforcement point before PR creation (manual / `--merge=false` runs never reach Step 12 to re-verify), so a transient git error fails closed at this gate.

     - **`STATUS=missing_main_ref`** (neither local `main` nor `origin/main` exists):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=missing_main_ref after re-bump (no base ref to classify against). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=missing_main_ref after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, proceed to step 5 and skip ahead to step 6/7.
       - **step8b family**: **HARD FAILURE** — set `STALL_TRACKING=true` and skip to Step 18. Print `**⚠ 8b: rebase — check-bump-version.sh reported STATUS=missing_main_ref after re-bump (no base ref to classify against). Cannot verify bump freshness. Setting STALL_TRACKING=true and skipping to Step 18.**` Log to `CI Issues`.

     **Only if `STATUS=ok`**, use the commit-count delta to detect the outcome — this is the reliable structured signal when the count is trustworthy:

     - **`VERIFIED=true`** (a new commit was created — the common case): proceed to step 5.

     - **`VERIFIED=false` AND `COMMITS_AFTER == COMMITS_BEFORE`** (zero new commits — `/bump-version` ran a `BUMP_TYPE=NONE` no-op path, because `classify-bump.sh` detected HEAD is already a bump commit). This normally happens when `drop-bump-commit.sh` reported `DROPPED=false` (e.g., Guard 4 refused the drop because the bump commit touched files beyond `.claude-plugin/plugin.json`) and the stale bump commit survived the rebase unchanged. Caller-family handling:
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — /bump-version created 0 new commits after rebase (BUMP_TYPE=NONE). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warning `**⚠ 10: CI monitor — /bump-version created 0 new commits (BUMP_TYPE=NONE). Proceeding to Step 11. Step 12 will re-attempt.**` to `Warnings`, then proceed directly to step 5 (the rebased history still needs to be force-pushed). Step 10 can afford to be permissive here because Step 12 re-runs the sub-procedure under strict semantics and will bail then if the drop still cannot happen.
       - **step8b family**: **HARD FAILURE** — set `STALL_TRACKING=true` and skip to Step 18. Print `**⚠ 8b: rebase — /bump-version created 0 new commits after rebase (BUMP_TYPE=NONE). Cannot verify bump freshness. Setting STALL_TRACKING=true and skipping to Step 18.**` Log to `CI Issues`.

     - **`VERIFIED=false` AND `COMMITS_AFTER != COMMITS_BEFORE`** (unexpected state — `/bump-version` created more than one commit, or somehow decreased the count):
       - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version created wrong commit count (expected $EXPECTED, got $COMMITS_AFTER). Bailing to 12d.**` Bail to 12d.
       - **step10 family**: log warning and break to Step 11.
       - **step8b family**: **HARD FAILURE** — set `STALL_TRACKING=true` and skip to Step 18. Print `**⚠ 8b: rebase — /bump-version created wrong commit count (expected $EXPECTED, got $COMMITS_AFTER). Setting STALL_TRACKING=true and skipping to Step 18.**` Log to `CI Issues`.

     After the commit-delta check completes (regardless of VERIFIED outcome above), also run the reasoning-file sentinel check (per #160 — mirrors Step 8 step 3b; see Block γ below for the full rationale and invocation).

---

## Block γ — Reasoning-file sentinel defense-in-depth (Step 8 step 3b + sub-procedure step 4)

Runs **after** the commit-delta check in both Block α (Step 8) and Block β (sub-procedure step 4). Complementary to the commit-delta check: Block γ catches the case where `/bump-version` silently no-ops without writing its reasoning artifact, whereas the commit-delta check catches the case where no commit was created. Both checks run unconditionally; neither short-circuits the other.

**Guard on non-empty path**: `verify-skill-called.sh --sentinel-file` rejects an empty path as an argument error (exit 1), so only invoke the helper when `$BUMP_REASONING_FILE` is non-empty. If `$BUMP_REASONING_FILE` is empty (the caller's step 2 failed to parse `REASONING_FILE=<path>` from `/bump-version`'s stdout), treat that as equivalent to a failed sentinel check: print a warning (`**⚠ /bump-version sentinel check skipped — BUMP_REASONING_FILE is empty. Continuing.**` for Step 8; the sub-procedure uses the caller-family-appropriate prefix), append to `$IMPLEMENT_TMPDIR/execution-issues.md` under `Warnings`, and do not invoke the helper.

    if [[ -n "$BUMP_REASONING_FILE" ]]; then
      ${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$BUMP_REASONING_FILE"
    fi

`$BUMP_REASONING_FILE` is the `REASONING_FILE=<path>` value parsed from the caller's `/bump-version` invocation's stdout. When the helper is invoked, parse for `VERIFIED` and `REASON`.

- **Step 8 (Block α caller)**: If `VERIFIED=false`, print `**⚠ /bump-version sentinel check failed (REASON=<token>). Continuing.**` and append the warning to `Warnings`. **Do NOT bail** — the commit-delta check (step 3) is the hard gate; the sentinel is advisory.
- **Sub-procedure step 4 (Block β caller)**: If `VERIFIED=false` or the guard skipped the helper (empty path), print `**⚠ 12: CI+merge loop — bump sentinel check failed (REASON=<token> or skipped for empty path). Continuing.**` (step12 family), the step10 equivalent, or the step8b equivalent (`**⚠ 8b: rebase — bump sentinel check failed (REASON=<token> or skipped for empty path). Continuing.**`), and log to `Warnings`. **Do NOT bail** — the commit-delta check is the hard gate; the sentinel is advisory. The commit-delta check can also report zero new commits when `classify-bump.sh` chose a no-op path (e.g., `BUMP_TYPE=NONE`) or when a base ref is missing; the sentinel is an orthogonal artifact-presence signal, not a branch of the commit-delta script.

**Freshness limitation**: the sentinel check is only meaningful when `BUMP_REASONING_FILE` was freshly parsed from the current `/bump-version` invocation's stdout — a stale file from a prior run at the same path would satisfy the check. This is the intended scope (the goal is to catch "skill totally skipped", not "skill reused stale artifact").
