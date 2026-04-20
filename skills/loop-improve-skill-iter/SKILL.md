---
name: loop-improve-skill-iter
description: "Use when running one improvement iteration for a target skill as part of /loop-improve-skill's outer loop; invokes /skill-judge then /design then /im, writes a per-substep sentinel ledger, emits ITER_STATUS to the caller tmpdir."
argument-hint: "<skill-name> <target-skill-path> <iter-num> <issue-num> <loop-tmpdir>"
allowed-tools: Bash, Skill, Read
---

# loop-improve-skill-iter

Runs one `/skill-judge` → post comment → `/design` → post plan → `/im` iteration exactly, then returns with a machine-readable status line and a completion sentinel. Invoked only by `/loop-improve-skill` (the outer orchestrator) via the Skill tool — never directly by end users.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/skill-judge`, `/design`, `/im`) returns, IMMEDIATELY continue with this skill's NEXT numbered sub-step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step 4`, `bail to cleanup`, `jump to exit`). A normal sequential continuation is the default this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

## Arguments

`$ARGUMENTS` is a space-separated list of five positional tokens: `<skill-name> <target-skill-path> <iter-num> <issue-num> <loop-tmpdir>`.

- `<skill-name>` — target skill short name (e.g., `alias`), already validated by the outer.
- `<target-skill-path>` — absolute path to the target's `SKILL.md`, resolved by the outer.
- `<iter-num>` — integer in `[1, 10]`. Outer enforces the range; inner re-validates defensively.
- `<issue-num>` — the tracking issue number created by the outer's Step 2.
- `<loop-tmpdir>` — absolute path to the outer's session tmpdir under `/tmp` or `/private/tmp`.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 1 | parse-args |
| 2 | setup paths |
| 3.j | judge |
| 3.d | design |
| 3.i | im |
| 4 | inner close-out |

## Step 1 — Parse and Validate Arguments

Parse `$ARGUMENTS` into `SKILL_NAME`, `TARGET_SKILL_PATH`, `ITER`, `ISSUE_NUM`, `LOOP_TMPDIR`.

Validate:
- `SKILL_NAME` matches `^[a-z][a-z0-9-]*$`.
- `TARGET_SKILL_PATH` is absolute and ends in `/SKILL.md`.
- `ITER` is an integer and `1 <= ITER <= 10`.
- `ISSUE_NUM` is a positive integer.
- `LOOP_TMPDIR` is absolute AND begins with `/tmp/` OR `/private/tmp/` AND is an existing directory.

If any check fails, print `**⚠ 1: parse-args — invalid arguments (<specific failure>). Aborting.**` and exit with `printf 'ITER_STATUS=%s\n' 'bad_args' > "$LOOP_TMPDIR/iter-${ITER}-status.txt" 2>/dev/null || true`. Do NOT write the completion sentinel. The outer's mechanical gate will flag this as a halt-equivalent failure.

The `LOOP_TMPDIR` prefix guard (`/tmp/` or `/private/tmp/`) is the skill's sole security boundary against arbitrary-path writes if the inner is ever invoked outside the outer orchestrator. Keep the check literal; do NOT introduce relative paths or canonicalization beyond this prefix test.

Print: `✅ 1: parse-args — ITER=${ITER}, target=/${SKILL_NAME}`

## Step 2 — Set Up Per-Iteration File Paths

Establish canonical per-iteration file names under `$LOOP_TMPDIR`:
- `JUDGE_OUT="$LOOP_TMPDIR/iter-${ITER}-judge.txt"`
- `DESIGN_OUT="$LOOP_TMPDIR/iter-${ITER}-design.txt"`
- `IM_OUT="$LOOP_TMPDIR/iter-${ITER}-im.txt"`
- `STATUS_FILE="$LOOP_TMPDIR/iter-${ITER}-status.txt"`
- `DONE_SENTINEL="$LOOP_TMPDIR/iter-${ITER}-done.sentinel"`

## Step 3.j — Run /skill-judge

Print: `> **🔶 3.j: judge**`

**Idempotency short-circuit.** If `$LOOP_TMPDIR/iter-${ITER}-3j.done` already exists and is non-empty, print `⏩ 3.j: judge — already done (idempotent resume)` and skip to Step 3.d.

Invoke the Skill tool with skill `"skill-judge"` (bare name first). On "no matching skill", retry with `"skill-judge:skill-judge"`. Pass the following string as args so the judge reads the current on-disk contents from the path resolved by the outer:

```
${SKILL_NAME} (absolute SKILL.md path: ${TARGET_SKILL_PATH}) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.
```

> **Continue after child returns.** When `/skill-judge` returns, execute 3.j's post-call gh-comment Bash block immediately, then proceed to Step 3.d — do NOT end the turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Transcribe the judge's response to `$JUDGE_OUT` (full body, one write via the Bash tool).

Post the captured judgment to the tracking issue (single Bash block):

```bash
JUDGE_COMMENT_FILE="$LOOP_TMPDIR/iter-${ITER}-judge-comment.md"
{ printf '## Iteration %s — skill-judge output\n\n' "${ITER}"; cat "$JUDGE_OUT"; } > "$JUDGE_COMMENT_FILE"
gh issue comment "${ISSUE_NUM}" --body-file "$JUDGE_COMMENT_FILE"
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3j.done"
```

The `printf 'done\n' > ...` (not `touch`) is load-bearing — `verify-skill-called.sh --sentinel-file` requires the file to be non-empty (`-s` check in `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh`). An empty sentinel would cause the outer's gate to misclassify this iteration as a halt.

## Step 3.d — Run /design

Print: `> **🔶 3.d: design**`

**Idempotency short-circuit.** If `$LOOP_TMPDIR/iter-${ITER}-3d-plan-post.done` already exists and is non-empty (plan already posted for this iteration in a prior partial run), print `⏩ 3.d: design — already done (idempotent resume)` and skip to Step 3.i.

Invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`). Pass a prompt asking for an improvement plan for `/${SKILL_NAME}` that addresses the `/skill-judge` findings just captured. The prompt MUST include these three contract clauses verbatim so `/design` produces a plan even for minor findings and never self-curtails on budget:

- `/design` MUST produce a concrete, implementable plan for ANY actionable `/skill-judge` finding — including findings classified "minor", "nit", or cosmetic. Treat "minor" as "small plan", not as "no plan".
- `/design` MUST NOT self-curtail citing token/context budget. Under any perceived pressure, narrow scope to the single highest-leverage finding and emit a compressed micro-plan that still conforms to the standard `/design` plan schema (`## Implementation Plan` with `Files to modify/create`, `Approach`, `Edge cases`, `Testing strategy`, and `Failure modes` when the change is non-trivial per `/design`'s own rules) — never emit a no-plan sentinel on budget grounds.
- `/design` MUST NOT emit any of the no-plan sentinel phrases (`no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`) when `/skill-judge` surfaced any actionable finding. Sentinels are reserved for the genuine case where no improvement is warranted.

The prompt MUST also explicitly name `TARGET_SKILL_PATH` as the absolute path of the SKILL.md to modify. Capture the full response to `$DESIGN_OUT` via a Bash write.

> **Continue after child returns.** When `/design` returns, run the tightened no-plan detector below, then the rescue path (when applicable), and then either post the plan and continue to 3.i or exit the loop with a no-plan status — do NOT end the turn. **Token/context budget is NOT a valid exit condition**; only the four authoritative exits end the iteration: empty `$DESIGN_OUT`, tightened no-plan sentinel match, explicit refusal/error from `/design`, or the outer's ITER>10 cap.

After the first `/design` returns, touch the pre-rescue-detector sentinel and run the detector:

```bash
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3d-pre-detect.done"
```

**No-plan detection (tightened).** Set `ITER_STATUS=no_plan` and skip to Step 4 if any of:

- `$DESIGN_OUT` is empty.
- The first non-blank line of `$DESIGN_OUT`, trimmed and case-folded, matches one of these exact sentinels: `no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`, **AND** no structured plan marker appears on any subsequent line of `$DESIGN_OUT`. Match sentinels against the whole trimmed first non-blank line only — do NOT substring-search the body. A **structured plan marker** is any line matching one of these anchored regexes (line-start only):
  - `^#{1,6}\s` — markdown heading (1-6 leading `#` followed by whitespace).
  - `^[1-9]\d?\.\s` — numbered list counter from 1 through 99, then `.` and whitespace.
  - `^[-*+]\s` — bulleted list item (`-`, `*`, or `+` followed by whitespace).

  If ANY line after the sentinel-matching first line matches one of the marker regexes, the sentinel match does NOT fire.

- `/design` returned an explicit refusal or error (a structured error response from the Skill tool, or a prose response whose entire body clearly says `/design` could not run). In this case set `ITER_STATUS=design_refusal` (not `no_plan`) and skip to Step 4.

**Rescue re-invocation of /design (at most one per iteration).** When the tightened no-plan detector does NOT fire but `$DESIGN_OUT` appears ambiguous or budget-curtailed, run a single rescue `/design` call. Rescue triggers when ALL four conditions hold:

- `$DESIGN_OUT` is non-empty.
- The tightened sentinel check above did NOT fire.
- `/design` did NOT return an explicit refusal or error.
- `$DESIGN_OUT` contains NO structured plan markers anywhere.

When rescue fires, re-invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`) and pass args `--auto <rescue prompt>`. The rescue prompt MUST require `/design`'s standard plan schema (a top-level `## Implementation Plan` section with the standard headings), focused exclusively on the single highest-leverage `/skill-judge` finding from this iteration, and MUST forbid preamble prose, budget excuses, and all no-plan sentinels. Capture the rescue response and OVERWRITE `$DESIGN_OUT` with it.

After the rescue Skill returns (if it ran), touch the post-rescue-detector sentinel:

```bash
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3d-post-detect.done"
```

Re-run the tightened no-plan detector on the (new) `$DESIGN_OUT`. If it fires, set `ITER_STATUS=no_plan` (or `ITER_STATUS=design_refusal` if rescue returned an explicit refusal/error) and skip to Step 4. Do NOT chain a second rescue — at most one rescue per iteration. If the four rescue conditions did not hold in the first place, skip the rescue entirely but still touch the post-rescue-detector sentinel (so the ledger is uniform — the sentinel means "the post-rescue-detector branch ran to completion", not "the rescue fired").

**Ordering invariant for Step 3.d.** Within a single iteration, these actions occur in exactly this order, with no exceptions:

1. Invoke `/design` via the Skill tool (the first call).
2. Write pre-rescue-detector sentinel.
3. Run the tightened no-plan detector on `$DESIGN_OUT`.
4. If the four rescue conditions hold, invoke `/design --auto` via the Skill tool (the rescue call) and OVERWRITE `$DESIGN_OUT` with the rescue output.
5. Write post-rescue-detector sentinel.
6. Re-run the tightened no-plan detector on the (now-overwritten) `$DESIGN_OUT`.
7. If the detector fired (in step 3 for the original, or in step 6 for the rescue), proceed to Step 4 (no-plan / refusal exit).
8. Otherwise, post exactly ONE plan comment using the final `$DESIGN_OUT` and write the plan-post sentinel.

At most one `gh issue comment` plan-body post is made per iteration — never post both the original and the rescue output.

Post the plan (single Bash block, only on the happy path — no-plan / refusal paths skip this):

```bash
PLAN_COMMENT_FILE="$LOOP_TMPDIR/iter-${ITER}-plan-comment.md"
{ printf '## Iteration %s — design plan\n\n' "${ITER}"; cat "$DESIGN_OUT"; } > "$PLAN_COMMENT_FILE"
gh issue comment "${ISSUE_NUM}" --body-file "$PLAN_COMMENT_FILE"
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3d-plan-post.done"
```

## Step 3.i — Run /im

Print: `> **🔶 3.i: im**`

**Idempotency short-circuit.** If `$LOOP_TMPDIR/iter-${ITER}-3i.done` already exists and is non-empty, print `⏩ 3.i: im — already done (idempotent resume)` and skip to Step 4.

Invoke the Skill tool with skill `"im"` (bare name first; fallback `"larch:im"`). Pass the full plan text (from `$DESIGN_OUT`) as args so `/im` runs the design + implement + review + version bump + PR + merge pipeline on the plan.

> **Continue after child returns.** When `/im` returns, capture its completion evidence, run the mechanical gate, and proceed to Step 4 — do NOT end the turn.

After `/im` returns, transcribe its completion output to `$IM_OUT` via the Bash tool (at minimum, the final `✅ 18: cleanup` line and any preceding PR-merged confirmation). Then run the mechanical gate:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --stdout-line '^✅ 18: cleanup' --stdout-file "$IM_OUT"
```

Parse `VERIFIED` and `REASON` from stdout. Behavior:

- **`VERIFIED=true`**: `/im` completed its pipeline. Write the 3.i sentinel:
  ```bash
  printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3i.done"
  ```
  Set `ITER_STATUS=completed` and proceed to Step 4.

- **`VERIFIED=false`**: `/im` did not reach its canonical completion line (either halted, bailed internally, or the capture failed). Set `ITER_STATUS=im_verification_failed` and proceed to Step 4. Do NOT write the 3.i sentinel — the absent sentinel is an observable ledger state the outer (or a follow-up run) can use to diagnose.

The `verify-skill-called.sh --stdout-line` gate is load-bearing: it is the only mechanism in the loop that verifies `/im` ran by reading a child-produced string rather than a parent-written artifact. Do NOT replace it with a `touch`-only fallback — per the Post-invocation verification rule in `subskill-invocation.md`, gates the parent can satisfy without the child's side effects are not real gates.

## Step 4 — Inner Close-Out

If `ITER_STATUS` is unset by this point, default it to `completed` (the happy path all through 3.j/3.d/3.i).

Write the status file and the outer-visible completion sentinel:

```bash
printf 'ITER_STATUS=%s\n' "${ITER_STATUS}" > "$STATUS_FILE"
printf 'ITER=%s\n' "${ITER}" > "$DONE_SENTINEL"
```

The `$DONE_SENTINEL` is non-empty by design so `verify-skill-called.sh --sentinel-file` in the outer's mechanical gate returns `VERIFIED=true`. The `ITER=` body also gives a forensic breadcrumb in case a directory of sentinels needs to be reconstructed after a crash.

Print: `✅ 4: inner close-out — ITER=${ITER}, status=${ITER_STATUS}`
