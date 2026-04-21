# Bump Verification STATUS Handling

**Consumer**: `/implement` Step 8 post-check (`bump-verification.md` Block α) and Rebase + Re-bump Sub-procedure step 4 post-check (Block β) — the authoritative `check-bump-version.sh --mode post` STATUS-handling matrix for the two callers.

**Contract**: Byte-preserving extraction from `skills/implement/SKILL.md` L522–528 (Block α, Step 8) and L828–858 (Block β, sub-procedure step 4). Do NOT synthesize or merge — the two blocks have distinct caller-family semantics (Step 8 permissive; sub-procedure step12-family strict). The #172 fail-closed invariant is authoritative: `STATUS != ok` forces `VERIFIED=false` at the script level.

**When to load**: before executing Step 8 step 3 (Block α) or the sub-procedure step 4 post-verification block (Block β). Do NOT load when `HAS_BUMP=false` (the bump is skipped entirely), or when the sub-procedure's pre-check `STATUS != ok` (the numeric post-check is already bypassed upstream).

---

## Block α — Step 8 post-check STATUS handling (from SKILL.md L522–528)

   **First**: if the pre-check STATUS was non-`ok` (baseline untrustworthy per the warning above), skip the numeric-comparison branches below — the `EXPECTED = COMMITS_BEFORE + 1` arithmetic is built on a coerced 0 baseline, so any mismatch with the true `COMMITS_AFTER` is meaningless. Log `**⚠ 8: version bump — pre-check was degraded; skipping post-check numeric verification. Step 12 will re-verify under strict semantics.**` to `Warnings` and continue to Step 8a.

   Otherwise (pre-check `STATUS=ok`), parse the post-check output for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, and `STATUS`. `STATUS != ok` (the #172 fail-closed invariant) forces `VERIFIED=false` at the script level independently of the numeric comparison — do not try to second-guess it. Handling:
   - **`STATUS=git_error`**: print `**⚠ 8: version bump — post-check STATUS=git_error, commit count untrustworthy. Continuing (Step 12 will re-verify under strict semantics).**`, log to `Warnings`, and continue. Do NOT treat this as a bump failure requiring manual intervention.
   - **`STATUS=missing_main_ref`**: same handling as `git_error` — log warning, continue.
   - **`STATUS=ok` AND `VERIFIED=false`**: the normal "wrong commit count" path — print `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`.
   - **`STATUS=ok` AND `VERIFIED=true`**: proceed.

---

## Block β — Rebase + Re-bump Sub-procedure step 4 post-check STATUS handling (from SKILL.md L828–858)

     Parse `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, and `STATUS`. **Evaluate `STATUS` FIRST** — before the `VERIFIED`/`COMMITS` comparison. A non-`ok` status means the count is 0-by-coercion (not a legitimate "0 commits ahead" result), and `VERIFIED` has already been forced to `false` by the script itself. Do not route such cases through the numeric-comparison branches below, which would emit a misleading "BUMP_TYPE=NONE or missing main ref" message when the true cause is a transient git error:

     - **`STATUS=git_error`** (rev-list failed against a valid base ref — corrupted pack, shallow-clone object boundary, permission error):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=git_error after re-bump (git rev-list failed against a valid base ref). Cannot verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. Rationale: Step 12 is the last-chance enforcement point for the version bump freshness invariant; a transient git error that masks the count means we cannot guarantee the merged version is correct.
       - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=git_error after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, then proceed directly to step 5 (rebased history must be force-pushed). Skip ahead past the numeric-comparison branches below to step 6 and step 7.

     - **`STATUS=missing_main_ref`** (neither local `main` nor `origin/main` exists):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=missing_main_ref after re-bump (no base ref to classify against). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warning `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=missing_main_ref after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, proceed to step 5 and skip ahead to step 6/7.

     **Only if `STATUS=ok`**, use the commit-count delta to detect the outcome — this is the reliable structured signal when the count is trustworthy:

     - **`VERIFIED=true`** (a new commit was created — the common case): proceed to step 5.

     - **`VERIFIED=false` AND `COMMITS_AFTER == COMMITS_BEFORE`** (zero new commits — `/bump-version` ran a `BUMP_TYPE=NONE` no-op path, because `classify-bump.sh` detected HEAD is already a bump commit). This normally happens when `drop-bump-commit.sh` reported `DROPPED=false` (e.g., Guard 4 refused the drop because the bump commit touched files beyond `.claude-plugin/plugin.json`) and the stale bump commit survived the rebase unchanged. Caller-family handling:
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — /bump-version created 0 new commits after rebase (BUMP_TYPE=NONE). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warning `**⚠ 10: CI monitor — /bump-version created 0 new commits (BUMP_TYPE=NONE). Proceeding to Step 11. Step 12 will re-attempt.**` to `Warnings`, then proceed directly to step 5 (the rebased history still needs to be force-pushed). Step 10 can afford to be permissive here because Step 12 re-runs the sub-procedure under strict semantics and will bail then if the drop still cannot happen.

     - **`VERIFIED=false` AND `COMMITS_AFTER != COMMITS_BEFORE`** (unexpected state — `/bump-version` created more than one commit, or somehow decreased the count):
       - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version created wrong commit count (expected $EXPECTED, got $COMMITS_AFTER). Bailing to 12d.**` Bail to 12d.
       - **step10 family**: log warning and break to Step 11.

     After the commit-delta check completes (regardless of VERIFIED outcome above), also run the reasoning-file sentinel check (per #160 — mirrors Step 8 step 3b). **Guard on non-empty path** — see Step 8 step 3b for the full rationale:
     ```bash
     if [[ -n "$BUMP_REASONING_FILE" ]]; then
       ${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$BUMP_REASONING_FILE"
     fi
     ```
     where `$BUMP_REASONING_FILE` is the `REASONING_FILE=<path>` value parsed from this sub-procedure's `/bump-version` invocation's stdout. When invoked, parse for `VERIFIED` and `REASON`. If `VERIFIED=false` or the guard skipped the helper (empty path), print `**⚠ 12: CI+merge loop — bump sentinel check failed (REASON=<token> or skipped for empty path). Continuing.**` (or the step10 equivalent) and log to `Warnings`. **Do NOT bail** — the commit-delta check is the hard gate; the sentinel is advisory. The commit-delta check can also report zero new commits when `classify-bump.sh` chose a no-op path (e.g., `BUMP_TYPE=NONE`) or when a base ref is missing; the sentinel is an orthogonal artifact-presence signal, not a branch of the commit-delta script.
