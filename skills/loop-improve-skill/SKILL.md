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

**Anti-self-curtailment.** Token/context budget is NOT a valid loop exit condition. The loop driver and its children MUST NOT end iteration based on their own judgment about token usage, context size, or perceived budget pressure. Only these four authoritative exits end the loop: (1) `ITER > 10` (max iterations); (2) `$DESIGN_OUT` is empty; (3) the tightened no-plan sentinel detector fires (see Step 3.d — sentinel match on the first non-blank line AND no structured plan marker follows); (4) `/design` returns an explicit refusal or error. If any child self-curtails citing tokens/budget and returns prose without plan shape, treat that output as ambiguous and route it through the Step 3.d rescue path — do NOT exit the loop on self-judged budget grounds.

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

**Loop-exit reminder.** The only authoritative exits are the four enumerated in the top-of-file Anti-self-curtailment banner. Token/context budget is NOT one of them. Proceed to the next iteration regardless of perceived token pressure; only the four defined exits may end the loop.

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

Invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`). Pass a prompt asking for an improvement plan for `/${SKILL_NAME}` that addresses the `skill-judge` findings just captured. The prompt MUST include these three contract clauses verbatim so `/design` produces a plan even for minor findings and never self-curtails on budget:

- `/design` MUST produce a concrete, implementable plan for ANY actionable `/skill-judge` finding — including findings classified "minor", "nit", or cosmetic. Treat "minor" as "small plan", not as "no plan".
- `/design` MUST NOT self-curtail citing token/context budget. Under any perceived pressure, narrow scope to the single highest-leverage finding and emit a compressed micro-plan that still conforms to the standard `/design` plan schema (`## Implementation Plan` with `Files to modify/create`, `Approach`, `Edge cases`, `Failure modes`, `Testing strategy`) — never emit a no-plan sentinel on budget grounds.
- `/design` MUST NOT emit any of the no-plan sentinel phrases (`no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`) when `/skill-judge` surfaced any actionable finding. Sentinels are reserved for the genuine case where no improvement is warranted.

The prompt should also explicitly name `TARGET_SKILL_PATH` as the absolute path of the SKILL.md to modify, so the plan references the file at that resolved path (whichever Step 1 probe matched — repo-local when available, plugin-installation when only probe 3 hit) when `/im` consumes it. This is best-effort guidance to `/design` (and in turn `/im` / `/implement`) — whether `/implement` honors an absolute path in the plan over other resolution heuristics depends on that skill's own behavior. Capture the full response to `$DESIGN_OUT` via the Skill tool call.

> **Continue after child returns.** When `/design` returns, run the tightened no-plan detector below, then the rescue path (when applicable), and then either post the plan and continue to 3.i or exit the loop — do NOT end the turn. **Token/context budget is NOT a valid exit condition**; only the four authoritative exits in the top-of-file Anti-self-curtailment banner end the loop.

**No-plan detection (tightened).** Exit the loop cleanly if any of:

- `$DESIGN_OUT` is empty.
- The first non-blank line of `$DESIGN_OUT`, trimmed and case-folded, matches one of these exact sentinels: `no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`, **AND** no structured plan marker appears on any subsequent line of `$DESIGN_OUT`. Match the sentinels against the whole trimmed first non-blank line only — do NOT substring-search the body (a legitimate plan may mention any of these phrases in prose). A **structured plan marker** is any line matching one of these anchored regexes (line-start only — do NOT match mid-line occurrences):
  - `^#{1,6}\s` — markdown heading (1-6 leading `#` followed by whitespace).
  - `^[1-9]\d?\.\s` — numbered list counter from 1 through 99, then `.` and whitespace. This deliberately excludes 3+ digit prefixes so calendar-year-prefixed prose (a 4-digit year followed by `.` and a roadmap blurb) does NOT count as a plan marker.
  - `^[-*+]\s` — bulleted list item (`-`, `*`, or `+` followed by whitespace).

  If ANY line after the sentinel-matching first line matches one of the marker regexes, the sentinel match does NOT fire; `$DESIGN_OUT` is treated as a legitimate plan (proceed past the rescue-and-detector block to the "Otherwise, post the plan" block below).
- `/design` returned an explicit refusal or error (a structured error response from the Skill tool, or a prose response whose entire body clearly says `/design` could not run — distinct from a plan that merely lacks content).

**Rescue re-invocation of /design (at most one per iteration).** When the tightened no-plan detector does NOT fire but `$DESIGN_OUT` appears ambiguous or budget-curtailed, run a single rescue `/design` call before accepting or exiting. Rescue triggers when ALL four conditions hold:

- `$DESIGN_OUT` is non-empty.
- The tightened sentinel check above did NOT fire.
- `/design` did NOT return an explicit refusal or error.
- `$DESIGN_OUT` contains NO structured plan markers anywhere — none of the three anchored regexes (`^#{1,6}\s`, `^[1-9]\d?\.\s`, `^[-*+]\s`) matches any line.

That is: prose-only output with no plan shape — the characteristic pattern when `/design` self-curtailed, returned a budget excuse, or emitted a weak non-sentinel reply.

When rescue fires, re-invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`) and pass args `--quick --auto <rescue prompt>`. `--quick` skips `/design`'s expensive 5-agent sketch phase and 3-reviewer voting panel so rescue stays cheap; `--auto` suppresses `/design`'s interactive `AskUserQuestion` checkpoints so rescue runs fully autonomously. The rescue prompt MUST require `/design`'s standard plan schema (a top-level `## Implementation Plan` section with the headings `Files to modify/create`, `Approach`, `Edge cases`, `Failure modes`, `Testing strategy`), focused exclusively on the single highest-leverage `/skill-judge` finding from this iteration, and MUST forbid preamble prose, budget excuses, and all no-plan sentinels. Capture the rescue response and OVERWRITE `$DESIGN_OUT` with it.

Re-run the tightened no-plan detector on the (new) `$DESIGN_OUT`. If it fires this time, exit the loop per the detector rules above. Do NOT chain a second rescue — at most one rescue per iteration. If the four rescue conditions did not hold in the first place, skip the rescue entirely.

**Ordering invariant for Step 3.d.** Within a single iteration, these actions occur in exactly this order, with no exceptions:

1. Invoke `/design` via the Skill tool (the first call).
2. Run the tightened no-plan detector on `$DESIGN_OUT`.
3. If the four rescue conditions hold, invoke `/design --quick --auto` via the Skill tool (the rescue call) and OVERWRITE `$DESIGN_OUT` with the rescue output.
4. Re-run the tightened no-plan detector on the (now-overwritten) `$DESIGN_OUT`.
5. If the detector fired (in step 2 for the original, or in step 4 for the rescue), proceed to the no-plan exit below.
6. Otherwise, post exactly ONE plan comment (the `gh issue comment` block below) using the final `$DESIGN_OUT` (the rescue output if rescue ran, else the original).
7. Continue to 3.i with the same final `$DESIGN_OUT`.

At most one `gh issue comment` plan-body post is made per iteration — never post both the original and the rescue output.

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
