---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop tracked in a GitHub issue; runs up to 10 iterations or stops when no plan materializes."
argument-hint: "<skill-name>"
allowed-tools: Bash, Skill, Read
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then runs up to 10 rounds of: `/skill-judge` → post judgment → `/design` → (stop if no plan) → post plan → `/im`.

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Anti-halt continuation reminder.** After every child `Skill` tool call (`/skill-judge`, `/design`, `/im`) returns, IMMEDIATELY continue with this skill's NEXT numbered sub-step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., loop exit on "no plan", `max iterations reached`). A normal sequential continuation is the default this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

## Arguments

`$ARGUMENTS` is a single positional token: `<skill-name>`.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 1 | parse args |
| 2 | create issue |
| 3 | loop |
| 3.j | judge |
| 3.d | design |
| 3.i | im |
| 4 | close out |

## Step 1 — Parse Arguments and Resolve Target Skill

Read `$ARGUMENTS` as `SKILL_NAME`. Strip a single leading `/`.

Validate:
- Non-empty.
- Matches `^[a-z][a-z0-9-]*$`.

If invalid, print `**⚠ 1: parse args — invalid or missing <skill-name>. Usage: /loop-improve-skill <skill-name>**` and abort.

Resolve the target skill path. Determine the current repo root via `REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)`. The `pwd -P` fallback resolves symlinks and guarantees an absolute path even when the process was launched with a relative `$PWD` or inside a symlinked working directory, so `TARGET_SKILL_PATH` below is always a usable absolute path when passed to child skills.

Probe in this order (first match wins) and save as an absolute path in `TARGET_SKILL_PATH`:
1. `${REPO_ROOT}/skills/${SKILL_NAME}/SKILL.md` — plugin-dev mode: the current checkout IS the larch plugin (or another plugin repo).
2. `${REPO_ROOT}/.claude/skills/${SKILL_NAME}/SKILL.md` — project-local skill defined in the current repo.
3. `${CLAUDE_PLUGIN_ROOT}/skills/${SKILL_NAME}/SKILL.md` — plugin-installation fallback (read-only source of truth when the current repo is NOT a larch clone).

**Why repo-local wins**: `/loop-improve-skill` is an iterative loop. Inside it, `/im` modifies the skill file in the current repo. If the probe order preferred the plugin-installation path (e.g., a pristine `larch1` clone) over the current repo (e.g., a working `larch3` clone being mutated by `/im`), every iteration after the first would re-judge the frozen plugin-dir copy instead of the latest modified contents — defeating the purpose of the loop.

If none of the three paths exist, print `**⚠ 1: parse args — no skill found. Probed: ${REPO_ROOT}/skills/${SKILL_NAME}/, ${REPO_ROOT}/.claude/skills/${SKILL_NAME}/, ${CLAUDE_PLUGIN_ROOT}/skills/${SKILL_NAME}/. Aborting.**` and abort.

Print: `✅ 1: parse args — target /${SKILL_NAME} at ${TARGET_SKILL_PATH}`

## Step 2 — Create Tracking GitHub Issue

Compose the issue body: one short paragraph describing the loop (up to 10 iterations of `/skill-judge` → `/design` → `/im`, exit when no plan materializes), plus a line with the target skill path.

Create the issue:

```bash
gh issue create --title "Improve /${SKILL_NAME} skill via loop-improve-skill" --body-file "$ISSUE_BODY_FILE"
```

Parse the returned URL, extract the trailing issue number into `ISSUE_NUM`. If `gh issue create` fails or no number is captured, print `**⚠ 2: create issue — gh issue create failed. Aborting.**` and abort.

Print: `✅ 2: create issue — #${ISSUE_NUM}`

## Step 3 — Loop

Initialize `ITER=1`. Loop while `ITER <= 10`:

Print: `> **🔶 3: loop — iteration ${ITER}**`

### 3.j — Run /skill-judge

Invoke the Skill tool with skill `"skill-judge"` (bare name first). On "no matching skill", retry with `"skill-judge:skill-judge"`. Pass the following string as args so the judge reads the current on-disk contents from the repo-local path resolved in Step 1 rather than whatever default resolution `/skill-judge` would otherwise perform:

```
${SKILL_NAME} (absolute SKILL.md path: ${TARGET_SKILL_PATH}) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.
```

The explicit absolute-path directive is load-bearing for two reasons: (1) the **probe order** in Step 1 prefers the repo-local copy when one exists (see "Why repo-local wins"); (2) passing that absolute path into `/skill-judge`'s args is what prevents `/skill-judge` from resolving the target by name and falling back to the plugin-installation copy — this matters regardless of which probe matched, because even when only probe 3 (plugin-installation) matched, the judge still reads the exact resolved file rather than re-resolving via a potentially different search path.

Capture the full response to `$JUDGE_OUT` (a temp file).

> **Continue after child returns.** When `/skill-judge` returns, execute 3.j's post-call step (gh comment) and then 3.d — do NOT end the turn.

Post the captured judgment to the tracking issue:

```bash
{ printf '## Iteration %s — skill-judge output\n\n' "${ITER}"; cat "$JUDGE_OUT"; } > "$JUDGE_COMMENT_FILE"
gh issue comment "${ISSUE_NUM}" --body-file "$JUDGE_COMMENT_FILE"
```

### 3.d — Run /design

Invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`). Pass a prompt asking for an improvement plan for `/${SKILL_NAME}` that addresses the `skill-judge` findings just captured. The prompt should explicitly name `TARGET_SKILL_PATH` as the absolute path of the SKILL.md to modify, so the plan references the file at that resolved path (whichever Step 1 probe matched — repo-local when available, plugin-installation when only probe 3 hit) when `/im` consumes it. This is best-effort guidance to `/design` (and in turn `/im` / `/implement`) — whether `/implement` honors an absolute path in the plan over other resolution heuristics depends on that skill's own behavior. Capture the full response to `$DESIGN_OUT` via the Skill tool call.

> **Continue after child returns.** When `/design` returns, execute the no-plan detector and then either exit the loop or continue to 3.i — do NOT end the turn.

**No-plan detection.** Exit the loop cleanly if any of:
- `$DESIGN_OUT` is empty.
- The first non-blank line of `$DESIGN_OUT`, trimmed and case-folded, matches one of these exact sentinels: `no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`. Match the whole trimmed line only — do NOT substring-search the body (a legitimate plan may mention any of these phrases in prose).
- `/design` returned an explicit refusal or error.

On no-plan exit, set `EXIT_REASON="no plan at iteration ${ITER}"` and proceed directly to Step 4 — Step 4 posts the single summary comment; do not post a separate "no plan materialized" comment here.

Otherwise, post the plan to the issue:

```bash
{ printf '## Iteration %s — design plan\n\n' "${ITER}"; cat "$DESIGN_OUT"; } > "$PLAN_COMMENT_FILE"
gh issue comment "${ISSUE_NUM}" --body-file "$PLAN_COMMENT_FILE"
```

### 3.i — Run /im

Invoke the Skill tool with skill `"im"` (bare name first; fallback `"larch:im"`) via the Skill tool. Pass the full plan text (from `$DESIGN_OUT`) as args so `/im` runs the design + implement + review + version bump + PR + merge pipeline on the plan. Because the plan composed in 3.d names `TARGET_SKILL_PATH`, `/im`'s implementation step is likely to edit the file at that resolved path; however, this is soft guidance — the final target is determined by `/implement`'s own path resolution.

> **Continue after child returns.** When `/im` returns, increment the iteration counter and decide whether to loop or exit — do NOT end the turn.

### 3.next — Iterate

Increment `ITER`. If `ITER > 10`, set `EXIT_REASON="max iterations (10) reached"` and proceed to Step 4 — Step 4 posts the single summary comment.

Otherwise, continue at 3.j with the new iteration.

## Step 4 — Close Out

Post a final summary comment. Do not close the issue.

```bash
gh issue comment "${ISSUE_NUM}" --body "Loop finished. Iterations run: $(( ITER > 10 ? 10 : ITER )). Exit reason: ${EXIT_REASON}."
```

Print: `✅ 4: close out — issue #${ISSUE_NUM}, exit: ${EXIT_REASON}`
