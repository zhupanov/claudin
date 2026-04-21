---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop tracked in a GitHub issue; delegates each iteration to /loop-improve-skill-iter with per-iteration sentinel verification; runs up to 10 rounds."
argument-hint: "<skill-name>"
allowed-tools: Bash, Skill, Read
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then delegates up to 10 improvement rounds to `/loop-improve-skill-iter` via the Skill tool. After each iteration returns, the outer verifies a non-empty completion sentinel under `$LOOP_TMPDIR` via `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file` — a mechanical gate the outer cannot satisfy without the inner's side effect (closes #231).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Anti-halt continuation reminder.** After every child `Skill` tool call (`/loop-improve-skill-iter`, and the Step 5 final-judge `/skill-judge` invocation on the iter-cap path) returns, IMMEDIATELY continue with this skill's NEXT numbered sub-step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., loop exit on `grade A achieved`, infeasibility halt with justification, `max iterations (10) reached`, `iteration sentinel missing`, `bail to Step 4`). A normal sequential continuation is the default this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

**Termination contract: strive for grade A.** The loop's primary success exit is `ITER_STATUS=grade_a_achieved`, set by the inner at Step 3.j.v when `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` reports per-dimension grade A on every dimension D1..D8 (integer thresholds D1>=18/20, D2-D6+D8>=14/15, D7>=9/10; equivalent to score/max >= 0.90 each). The loop continues iterating until either (a) grade A is achieved on all dimensions, or (b) further automated progress toward grade A is genuinely infeasible (no_plan / design_refusal / im_verification_failed) and the inner has written a justification to `$LOOP_TMPDIR/iter-${ITER}-infeasibility.md`, or (c) the 10-iteration cap is reached. Token/context budget is NOT a valid exit condition.

Authoritative loop exits fall into two categories, each triggering one of the Step 4.v branches below:

1. **Sentinel verified** (`VERIFIED=true`): the inner reached its Step 4 close-out and wrote `iter-${ITER}-status.txt`. Read that file to learn `ITER_STATUS`. Branch on value:
   - `completed`: happy path, loop on.
   - `grade_a_achieved`: terminal happy-path exit — break to Step 5 with `EXIT_REASON="grade A achieved on all dimensions at iteration ${ITER}"`.
   - `no_plan`, `design_refusal`, `im_verification_failed`: infeasibility halts — break to Step 5 with the corresponding category-specific `EXIT_REASON`. The inner has already written `iter-${ITER}-infeasibility.md` with the justification; Step 5 embeds it in the close-out comment.
   - any other value: defensive — `EXIT_REASON="inner returned unexpected ITER_STATUS=<value> at iteration ${ITER}"`, break to Step 5.
2. **Sentinel missing** (`VERIFIED=false`): the inner halted partway through an iteration. The outer writes a diagnostic `EXIT_REASON="iteration sentinel missing — ..."` and breaks to Step 5. This is the mechanical halt-detection branch that fixes #231.

Additionally, after a successful iteration the outer increments `ITER` and compares against the 10-round cap; exceeding it sets `EXIT_REASON="max iterations (10) reached"` and breaks to Step 5 — Step 5 then runs one final `/skill-judge` to capture the post-iter-cap grade and auto-generate an infeasibility justification listing the remaining non-A dimensions (or, if the final judge shows grade A, reclassifies the exit as a happy-path post-cap A exit).

Token/context budget is NOT a valid loop exit; the split-skill structure converts the old self-curtailment failure mode into an observable missing-sentinel diagnostic.

## Arguments

`$ARGUMENTS` is a single positional token: `<skill-name>`.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 1 | parse args |
| 2 | session setup |
| 3 | create issue |
| 4 | loop |
| 4.i | iter |
| 4.v | verify |
| 5 | close out |
| 6 | cleanup |

## Step 1 — Parse Arguments and Resolve Target Skill

Read `$ARGUMENTS` as `SKILL_NAME`. Strip a single leading `/`.

Validate:
- Non-empty.
- Matches `^[a-z][a-z0-9-]*$`.

If invalid, print `**⚠ 1: parse args — invalid or missing <skill-name>. Usage: /loop-improve-skill <skill-name>**` and abort.

Resolve the target skill path. Determine the current repo root via `REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)`. Probe in this order (first match wins) and save as an absolute path in `TARGET_SKILL_PATH`:

1. `${REPO_ROOT}/skills/${SKILL_NAME}/SKILL.md` — plugin-dev mode.
2. `${REPO_ROOT}/.claude/skills/${SKILL_NAME}/SKILL.md` — project-local.
3. `${CLAUDE_PLUGIN_ROOT}/skills/${SKILL_NAME}/SKILL.md` — plugin-installation fallback.

If none exist, print `**⚠ 1: parse args — no skill found. Probed: ${REPO_ROOT}/skills/${SKILL_NAME}/, ${REPO_ROOT}/.claude/skills/${SKILL_NAME}/, ${CLAUDE_PLUGIN_ROOT}/skills/${SKILL_NAME}/. Aborting.**` and abort.

Print: `✅ 1: parse args — target /${SKILL_NAME} at ${TARGET_SKILL_PATH}`

## Step 2 — Session Setup

Establish a session tmpdir under canonical `/tmp` for the per-iteration sentinel ledger. The inner skill validates that `LOOP_TMPDIR` begins with `/tmp/` or `/private/tmp/` and rejects anything else, so the path handed over must come from `session-setup.sh` (which uses `mktemp` under `/tmp`).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix claude-loop-improve --skip-branch-check --skip-slack-check --skip-repo-check
```

Parse `SESSION_TMPDIR` from stdout and save as `LOOP_TMPDIR`. If `session-setup.sh` exits non-zero, print `**⚠ 2: session setup — failed. Aborting.**` and abort (no tmpdir to clean up yet).

Print: `✅ 2: session setup — LOOP_TMPDIR=${LOOP_TMPDIR}`

## Step 3 — Create Tracking GitHub Issue

Compose the issue body: one short paragraph describing the loop (up to 10 iterations of `/skill-judge` → `/design` → `/im`, exit when no plan materializes), plus a line with the target skill path.

```bash
ISSUE_BODY_FILE="$LOOP_TMPDIR/issue-body.md"
{
  printf 'Iteratively improve /%s via /loop-improve-skill. Runs up to 10 rounds of /skill-judge + /design + /im, delegated to /loop-improve-skill-iter. Exits when every /skill-judge dimension reaches grade A, or when an infeasibility halt (no_plan / design_refusal / im_verification_failed, with written justification appended below) or the 10-iteration cap is reached.\n\n' "${SKILL_NAME}"
  printf 'Target: %s\n' "${TARGET_SKILL_PATH}"
} > "$ISSUE_BODY_FILE"
gh issue create --title "Improve /${SKILL_NAME} skill via loop-improve-skill" --body-file "$ISSUE_BODY_FILE"
```

Parse the returned URL, extract the trailing issue number into `ISSUE_NUM`. If `gh issue create` fails or no number is captured, print `**⚠ 3: create issue — gh issue create failed. Aborting.**` and skip to Step 6 (cleanup).

Print: `✅ 3: create issue — #${ISSUE_NUM}`

## Step 4 — Loop

Initialize `ITER=1` and `EXIT_REASON=""`.

Loop while `ITER <= 10`:

Print: `> **🔶 4: loop — iteration ${ITER}**`

### 4.i — Invoke /loop-improve-skill-iter

Invoke the Skill tool with skill `"loop-improve-skill-iter"` (bare name first). On "no matching skill", retry with `"larch:loop-improve-skill-iter"`. Pass the five required values as flag-style args (order not significant, but flag-style is load-bearing — `TARGET_SKILL_PATH` and `LOOP_TMPDIR` may contain spaces on macOS user paths, and positional parsing would silently mis-split):

```
--skill-name ${SKILL_NAME} --target-skill-path ${TARGET_SKILL_PATH} --iter ${ITER} --issue-num ${ISSUE_NUM} --loop-tmpdir ${LOOP_TMPDIR}
```

> **Continue after child returns.** When `/loop-improve-skill-iter` returns, execute the 4.v mechanical gate immediately, then either increment `ITER` and loop or fall through to Step 5 — do NOT end the turn.

### 4.v — Verify Iteration Sentinel (mechanical gate)

This is the single mechanical post-invocation gate that converts the old "parent halted after child returned" failure mode (issue #231) into an observable missing-sentinel diagnostic. The outer cannot satisfy this gate without the inner's side effect — the inner writes a non-empty `$LOOP_TMPDIR/iter-${ITER}-done.sentinel` only when it reaches its Step 4 close-out.

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$LOOP_TMPDIR/iter-${ITER}-done.sentinel"
```

Parse `VERIFIED` and `REASON` from stdout. Branch:

- **`VERIFIED=true`**: read the status file:
  ```bash
  cat "$LOOP_TMPDIR/iter-${ITER}-status.txt"
  ```
  Parse `ITER_STATUS=<value>`. Branch on value:
  - `completed`: happy path. Increment `ITER` (see 4.n below).
  - `grade_a_achieved`: terminal happy-path exit. Set `EXIT_REASON="grade A achieved on all dimensions at iteration ${ITER}"` and break to Step 5. The skill graded A on every dimension D1..D8 at this iteration's `/skill-judge` run; no further automated work is needed.
  - `no_plan`: set `EXIT_REASON="no plan at iteration ${ITER}"` and break to Step 5. The inner has written `iter-${ITER}-infeasibility.md`; Step 5 will embed it in the close-out comment.
  - `design_refusal`: set `EXIT_REASON="/design refusal or error at iteration ${ITER}"` and break to Step 5.
  - `im_verification_failed`: set `EXIT_REASON="/im did not reach canonical completion line at iteration ${ITER}"` and break to Step 5.
  - any other value: set `EXIT_REASON="inner returned unexpected ITER_STATUS=<value> at iteration ${ITER}"` and break to Step 5.

  The inner's argument-validation failure path (`bad_args`) does NOT surface here because the inner deliberately does not write the completion sentinel when argument validation fails (writing through an unvalidated `LOOP_TMPDIR` would defeat the security check). That case collapses to the `VERIFIED=false` branch below as `REASON=missing_path`, which is the correct diagnostic.

- **`VERIFIED=false`**: the halt-detected branch. Set `EXIT_REASON="iteration sentinel missing — iter ${ITER} did not complete (REASON=<token>)"` and break to Step 5. This path catches both the case where the inner halted partway through an iteration (never reached its Step 4) — the exact failure mode of #231, now mechanically detected at the outer's gate — and the case where the inner aborted during argument validation (per the note above).

### 4.n — Iteration Advance

Increment `ITER`. If the new `ITER > 10`, set `EXIT_REASON="max iterations (10) reached"` and break to Step 5 — this is the normal-completion exit.

Otherwise, loop back to the `## Step 4 — Loop` header for the next iteration.

## Step 5 — Close Out

Post a final multi-section summary comment to the tracking issue. Do NOT close the issue. The close-out body composes (in order): a one-line summary, a `## Grade History` section from `$LOOP_TMPDIR/grade-history.txt`, a `## Infeasibility Justification` section (only on infeasibility/iter-cap exits), and an optional `## Final Assessment` pointer (iter-cap path only).

Set `IT` once for use throughout this step:

```bash
IT=$(( ITER > 10 ? 10 : ITER ))
```

### 5a — Final /skill-judge re-evaluation (iter-cap path only)

If `EXIT_REASON="max iterations (10) reached"`, run one final `/skill-judge` so the close-out comment reflects the post-iter-cap grade (the last in-loop iteration's judge ran against the skill state BEFORE that iter's `/im` landed; on iter-cap there is no next iteration to re-judge).

Invoke `/skill-judge` via the Skill tool (bare name first; on "no matching skill", retry with `"skill-judge:skill-judge"`). Pass the same prompt template the inner uses at Step 3.j:

```
${SKILL_NAME} (absolute SKILL.md path: ${TARGET_SKILL_PATH}) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.
```

> **Continue after child returns.** When `/skill-judge` returns, transcribe its full response to `$LOOP_TMPDIR/final-judge.txt` via a single Bash write, run `parse-skill-judge-grade.sh`, parse the KV output, and continue to 5b — do NOT end the turn.

Capture the response and parse:

```bash
# Transcribe the final judge's full response to final-judge.txt via a single Bash write.
cat > "$LOOP_TMPDIR/final-judge.txt" <<'JUDGE_EOF'
<paste the verbatim /skill-judge response here>
JUDGE_EOF
${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh "$LOOP_TMPDIR/final-judge.txt" > "$LOOP_TMPDIR/final-grade.txt"
```

Parse `$LOOP_TMPDIR/final-grade.txt` for `PARSE_STATUS`, `GRADE_A`, `NON_A_DIMS`, `TOTAL_NUM`, `TOTAL_DEN`, per-dim values. Append a final line to `$LOOP_TMPDIR/grade-history.txt` tagged `iter=final`:

- When `PARSE_STATUS=ok`: `iter=final total=${TOTAL_NUM}/${TOTAL_DEN} non_a=${NON_A_DIMS} parse_status=ok`
- When `PARSE_STATUS!=ok`: `iter=final total=N/A non_a=N/A parse_status=${PARSE_STATUS}`

Reclassification: if final-judge `PARSE_STATUS=ok` AND `GRADE_A=true`, override `EXIT_REASON="grade A achieved after final post-iter-cap re-evaluation"` — the iteration-cap was reached but the final state actually grades A on every dimension (rare but possible when the 10th iter's `/im` improved the skill enough to push it over the threshold).

### 5b — Compose close-out body

Compose `$LOOP_TMPDIR/closeout-body.md` in a single Bash block. The body has four sections (3 always present, 1 conditional):

```bash
{
  printf 'Loop finished. Iterations run: %s. Exit reason: %s.\n\n' "${IT}" "${EXIT_REASON}"

  printf '## Grade History\n\n'
  if [[ -s "$LOOP_TMPDIR/grade-history.txt" ]]; then
    printf '```\n'
    cat "$LOOP_TMPDIR/grade-history.txt"
    printf '```\n\n'
  else
    printf '(no grade parses captured)\n\n'
  fi

  # Infeasibility Justification section: present on infeasibility ITER_STATUS
  # exits, on iteration-sentinel-missing exits, and on iter-cap WHERE the
  # final-judge re-evaluation did NOT show grade A. Absent on grade_a_achieved
  # (terminal happy) and the reclassified post-cap A exit.
  case "$EXIT_REASON" in
    "grade A achieved on all dimensions at iteration "*|"grade A achieved after final post-iter-cap re-evaluation")
      : # no Infeasibility Justification section
      ;;
    "max iterations (10) reached")
      printf '## Infeasibility Justification\n\n'
      printf 'After 10 iterations the skill still does not achieve grade A on every dimension.\n\n'
      if [[ -s "$LOOP_TMPDIR/final-grade.txt" ]] && LC_ALL=C grep -q '^PARSE_STATUS=ok$' "$LOOP_TMPDIR/final-grade.txt"; then
        FINAL_NON_A="$(LC_ALL=C grep '^NON_A_DIMS=' "$LOOP_TMPDIR/final-grade.txt" | head -1 | cut -d= -f2-)"
        printf 'Non-A dimensions in the final post-iter-cap /skill-judge: %s.\n\n' "${FINAL_NON_A}"
        printf 'See `final-judge.txt` (captured at Step 5a) and `grade-history.txt` for the per-iteration trajectory — whether the loop plateaued, regressed, or improved monotonically without reaching A informs whether the remaining gap is likely to yield to additional iterations or requires structural redesign.\n\n'
      else
        printf 'Final /skill-judge assessment unavailable: see Grade History above for the last successful judge parse. Last in-loop judge: `iter-%s-judge.txt`.\n\n' "${IT}"
      fi
      ;;
    *)
      printf '## Infeasibility Justification\n\n'
      if [[ -s "$LOOP_TMPDIR/iter-${IT}-infeasibility.md" ]]; then
        cat "$LOOP_TMPDIR/iter-${IT}-infeasibility.md"
        printf '\n'
      else
        printf 'Iteration %s did not produce a written justification (the inner skill may have halted before writing `iter-%s-infeasibility.md`). See `iter-%s-design.txt` and `iter-%s-im.txt` for context.\n\n' "${IT}" "${IT}" "${IT}" "${IT}"
      fi
      ;;
  esac
} > "$LOOP_TMPDIR/closeout-body.md"
```

### 5c — Post the comment

Post the close-out body. If the `gh` post fails for any reason, print a warning and continue to Step 6 — never skip cleanup:

```bash
if ! gh issue comment "${ISSUE_NUM}" --body-file "$LOOP_TMPDIR/closeout-body.md"; then
  printf '**⚠ 5: close out — gh comment failed (exit %s). Continuing to cleanup.**\n' "$?"
fi
printf 'done\n' > "$LOOP_TMPDIR/closeout.sentinel"
```

Print: `✅ 5: close out — issue #${ISSUE_NUM}, exit: ${EXIT_REASON}`

## Step 6 — Cleanup

**This step ALWAYS runs**, regardless of the outcome of prior steps (success, failure, early exit, or abort).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$LOOP_TMPDIR"
```

Print: `✅ 6: cleanup — loop-improve-skill complete!`
