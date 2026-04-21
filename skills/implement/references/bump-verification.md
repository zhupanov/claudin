# Bump Verification STATUS Handling

**Consumer**: `/implement` Step 8 post-check (`bump-verification.md` Block α) and Rebase + Re-bump Sub-procedure step 4 post-check (Block β) — authoritative `check-bump-version.sh --mode post` STATUS-handling matrix for two callers.

**Contract**: Byte-preserve extract from `skills/implement/SKILL.md` L522–528 (Block α, Step 8) and L828–858 (Block β, sub-procedure step 4). No synthesize, no merge — two blocks have distinct caller-family semantics (Step 8 permissive; sub-procedure step12-family strict). #172 fail-closed invariant authoritative: `STATUS != ok` force `VERIFIED=false` at script level.

**When to load**: before Step 8 step 3 (Block α) or sub-procedure step 4 post-verify block (Block β). No load when `HAS_BUMP=false` (bump skip entire), or when sub-procedure pre-check `STATUS != ok` (numeric post-check already bypass upstream).

---

## Block α — Step 8 post-check STATUS handling (from SKILL.md L522–528)

   **First**: if pre-check STATUS non-`ok` (baseline untrust per warn above), skip numeric-compare branch below — `EXPECTED = COMMITS_BEFORE + 1` math built on coerce 0 baseline, so any mismatch with true `COMMITS_AFTER` meaningless. Log `**⚠ 8: version bump — pre-check was degraded; skipping post-check numeric verification. Step 12 will re-verify under strict semantics.**` to `Warnings` and continue to Step 8a.

   Else (pre-check `STATUS=ok`), parse post-check output for `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, `STATUS`. `STATUS != ok` (#172 fail-closed invariant) force `VERIFIED=false` at script level independent of numeric compare — no second-guess. Handle:
   - **`STATUS=git_error`**: print `**⚠ 8: version bump — post-check STATUS=git_error, commit count untrustworthy. Continuing (Step 12 will re-verify under strict semantics).**`, log to `Warnings`, continue. No treat as bump fail need manual fix.
   - **`STATUS=missing_main_ref`**: same as `git_error` — log warn, continue.
   - **`STATUS=ok` AND `VERIFIED=false`**: normal "wrong commit count" path — print `**⚠ /bump-version did not create exactly one commit. Expected $EXPECTED, got $COMMITS_AFTER.**`.
   - **`STATUS=ok` AND `VERIFIED=true`**: proceed.

---

## Block β — Rebase + Re-bump Sub-procedure step 4 post-check STATUS handling (from SKILL.md L828–858)

     Parse `VERIFIED`, `COMMITS_AFTER`, `EXPECTED`, `STATUS`. **Eval `STATUS` FIRST** — before `VERIFIED`/`COMMITS` compare. Non-`ok` status mean count 0-by-coerce (not legit "0 commits ahead" result), and `VERIFIED` already force to `false` by script itself. No route such cases through numeric-compare branch below — would emit mislead "BUMP_TYPE=NONE or missing main ref" message when true cause transient git error:

     - **`STATUS=git_error`** (rev-list fail against valid base ref — corrupt pack, shallow-clone object boundary, permission error):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=git_error after re-bump (git rev-list failed against a valid base ref). Cannot verify bump freshness. Bailing to 12d.**` Log to `$IMPLEMENT_TMPDIR/execution-issues.md` under `CI Issues`. Why: Step 12 last-chance enforce point for version bump freshness invariant; transient git error mask count mean cannot guarantee merged version correct.
       - **step10 family**: log warn `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=git_error after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, then go direct to step 5 (rebased history must force-push). Skip past numeric-compare branch below to step 6 and step 7.

     - **`STATUS=missing_main_ref`** (no local `main` nor `origin/main`):
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — check-bump-version.sh reported STATUS=missing_main_ref after re-bump (no base ref to classify against). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warn `**⚠ 10: CI monitor — check-bump-version.sh reported STATUS=missing_main_ref after re-bump. Proceeding to Step 11. Step 12 will re-verify.**` to `CI Issues`, proceed to step 5 and skip to step 6/7.

     **Only if `STATUS=ok`**, use commit-count delta to detect outcome — this reliable structured signal when count trust:

     - **`VERIFIED=true`** (new commit made — common case): proceed to step 5.

     - **`VERIFIED=false` AND `COMMITS_AFTER == COMMITS_BEFORE`** (zero new commits — `/bump-version` ran `BUMP_TYPE=NONE` no-op path, because `classify-bump.sh` detect HEAD already bump commit). Normally happen when `drop-bump-commit.sh` report `DROPPED=false` (e.g., Guard 4 refuse drop because bump commit touch files beyond `.claude-plugin/plugin.json`) and stale bump commit survive rebase unchanged. Caller-family handle:
       - **step12 family**: **HARD FAILURE** — bail to 12d. Print `**⚠ 12: CI+merge loop — /bump-version created 0 new commits after rebase (BUMP_TYPE=NONE). Cannot verify bump freshness. Bailing to 12d.**` Log to `CI Issues`.
       - **step10 family**: log warn `**⚠ 10: CI monitor — /bump-version created 0 new commits (BUMP_TYPE=NONE). Proceeding to Step 11. Step 12 will re-attempt.**` to `Warnings`, then go direct to step 5 (rebased history still need force-push). Step 10 can afford permissive here because Step 12 re-runs sub-procedure under strict semantics and will bail then if drop still cannot happen.

     - **`VERIFIED=false` AND `COMMITS_AFTER != COMMITS_BEFORE`** (unexpected state — `/bump-version` made more than one commit, or somehow drop count):
       - **step12 family**: **HARD FAILURE**. Print `**⚠ 12: CI+merge loop — /bump-version created wrong commit count (expected $EXPECTED, got $COMMITS_AFTER). Bailing to 12d.**` Bail to 12d.
       - **step10 family**: log warn and break to Step 11.

     After commit-delta check done (regardless of VERIFIED outcome above), also run reasoning-file sentinel check (per #160 — mirror Step 8 step 3b). **Guard on non-empty path** — see Step 8 step 3b for full rationale:
     ```bash
     if [[ -n "$BUMP_REASONING_FILE" ]]; then
       ${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$BUMP_REASONING_FILE"
     fi
     ```
     where `$BUMP_REASONING_FILE` is `REASONING_FILE=<path>` value parsed from this sub-procedure `/bump-version` invocation stdout. When invoked, parse for `VERIFIED` and `REASON`. If `VERIFIED=false` or guard skip helper (empty path), print `**⚠ 12: CI+merge loop — bump sentinel check failed (REASON=<token> or skipped for empty path). Continuing.**` (or step10 equivalent) and log to `Warnings`. **No bail** — commit-delta check is hard gate; sentinel advisory. Commit-delta check can also report zero new commits when `classify-bump.sh` chose no-op path (e.g., `BUMP_TYPE=NONE`) or when base ref missing; sentinel is orthogonal artifact-presence signal, not branch of commit-delta script.
