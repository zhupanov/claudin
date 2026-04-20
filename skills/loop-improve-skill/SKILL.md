---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop tracked in a GitHub issue; delegates each iteration to /loop-improve-skill-iter with per-iteration sentinel verification; runs up to 10 rounds."
argument-hint: "<skill-name>"
allowed-tools: Bash, Skill, Read
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then delegates up to 10 improvement rounds to `/loop-improve-skill-iter` via the Skill tool. After each iteration returns, the outer verifies a non-empty completion sentinel under `$LOOP_TMPDIR` via `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file` — a mechanical gate the outer cannot satisfy without the inner's side effect (closes #231).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Anti-halt continuation reminder.** After every child `Skill` tool call (`/loop-improve-skill-iter`) returns, IMMEDIATELY continue with this skill's NEXT numbered sub-step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., loop exit on `no plan`, `max iterations reached`, `bail to Step 4`, `iteration sentinel missing`). A normal sequential continuation is the default this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

The four authoritative loop exits: (1) `ITER > 10` (max iterations reached); (2) inner returns `ITER_STATUS=no_plan`; (3) inner returns `ITER_STATUS=design_refusal`; (4) outer's `verify-skill-called.sh --sentinel-file` gate returns `VERIFIED=false` (halt detected). Token/context budget is NOT a valid loop exit; the split-skill structure converts the old self-curtailment failure mode into an observable missing-sentinel diagnostic.

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
  printf 'Iteratively improve /%s via /loop-improve-skill. Runs up to 10 rounds of /skill-judge + /design + /im, delegated to /loop-improve-skill-iter. Exits early when /design produces no plan.\n\n' "${SKILL_NAME}"
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

Invoke the Skill tool with skill `"loop-improve-skill-iter"` (bare name first). On "no matching skill", retry with `"larch:loop-improve-skill-iter"`. Pass args:

```
${SKILL_NAME} ${TARGET_SKILL_PATH} ${ITER} ${ISSUE_NUM} ${LOOP_TMPDIR}
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
  - `no_plan`: set `EXIT_REASON="no plan at iteration ${ITER}"` and break to Step 5.
  - `design_refusal`: set `EXIT_REASON="/design refusal or error at iteration ${ITER}"` and break to Step 5.
  - `im_verification_failed`: set `EXIT_REASON="/im did not reach canonical completion line at iteration ${ITER}"` and break to Step 5.
  - `bad_args`: set `EXIT_REASON="inner rejected arguments at iteration ${ITER}"` and break to Step 5.
  - any other value: set `EXIT_REASON="inner returned unexpected ITER_STATUS=<value> at iteration ${ITER}"` and break to Step 5.

- **`VERIFIED=false`**: the halt-detected branch. Set `EXIT_REASON="iteration sentinel missing — iter ${ITER} did not complete (REASON=<token>)"` and break to Step 5. This path catches the case where the inner halted partway through an iteration (never reached its Step 4) — the exact failure mode of #231, now mechanically detected at the outer's gate.

### 4.n — Iteration Advance

Increment `ITER`. If the new `ITER > 10`, set `EXIT_REASON="max iterations (10) reached"` and break to Step 5 — this is the normal-completion exit.

Otherwise, loop back to the `## Step 4 — Loop` header for the next iteration.

## Step 5 — Close Out

Post a final summary comment. Do NOT close the issue.

```bash
IT=$(( ITER > 10 ? 10 : ITER ))
gh issue comment "${ISSUE_NUM}" --body "Loop finished. Iterations run: ${IT}. Exit reason: ${EXIT_REASON}."
printf 'done\n' > "$LOOP_TMPDIR/closeout.sentinel"
```

Print: `✅ 5: close out — issue #${ISSUE_NUM}, exit: ${EXIT_REASON}`

## Step 6 — Cleanup

**This step ALWAYS runs**, regardless of the outcome of prior steps (success, failure, early exit, or abort).

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$LOOP_TMPDIR"
```

Print: `✅ 6: cleanup — loop-improve-skill complete!`
