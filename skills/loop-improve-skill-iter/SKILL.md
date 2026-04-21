---
name: loop-improve-skill-iter
description: "Use when running one improvement iteration for a target skill as part of /loop-improve-skill's outer loop; invokes /skill-judge then /design then /im, writes a per-substep sentinel ledger, emits ITER_STATUS to the caller tmpdir."
argument-hint: "--skill-name <name> --target-skill-path <path> --iter <N> --issue-num <N> --loop-tmpdir <path>"
allowed-tools: Bash, Skill, Read
---

# loop-improve-skill-iter

Runs one `/skill-judge` → post comment → `/design` → post plan → `/im` iteration exactly, then returns with a machine-readable status line and a completion sentinel. Invoked only by `/loop-improve-skill` (the outer orchestrator) via the Skill tool — never directly by end users.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/skill-judge`, `/design`, `/im`) returns, IMMEDIATELY continue with this skill's NEXT numbered sub-step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step 4`, `bail to cleanup`, `jump to exit`). A normal sequential continuation is the default this rule reinforces, NOT an exception. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

## Arguments

`$ARGUMENTS` is a flag-style argument list consumed as five required `--flag value` pairs. Flag order is not significant, but every flag is required. Flag-style parsing is load-bearing — `TARGET_SKILL_PATH` and `LOOP_TMPDIR` come from `git rev-parse --show-toplevel` and `mktemp` respectively, either of which may contain spaces on macOS user home paths, so positional parsing would silently mis-split fields.

- `--skill-name <name>` — target skill short name (e.g., `alias`), already validated by the outer.
- `--target-skill-path <path>` — absolute path to the target's `SKILL.md`, resolved by the outer.
- `--iter <N>` — integer in `[1, 10]`. Outer enforces the range; inner re-validates defensively.
- `--issue-num <N>` — the tracking issue number created by the outer's Step 3.
- `--loop-tmpdir <path>` — absolute path to the outer's session tmpdir under `/tmp` or `/private/tmp`. Must NOT contain `..` path components.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 1 | parse-args |
| 2 | setup paths |
| 3.j | judge |
| 3.j.v | grade parse |
| 3.d | design |
| 3.i | im |
| 4 | inner close-out |

## Step 1 — Parse and Validate Arguments

Parse `$ARGUMENTS` flag-style into `SKILL_NAME`, `TARGET_SKILL_PATH`, `ITER`, `ISSUE_NUM`, `LOOP_TMPDIR`. Reject unknown flags, missing flags, and duplicate flags.

Validate:
- `SKILL_NAME` matches `^[a-z][a-z0-9-]*$`.
- `TARGET_SKILL_PATH` is absolute and ends in `/SKILL.md`.
- `ITER` is an integer and `1 <= ITER <= 10`.
- `ISSUE_NUM` is a positive integer.
- `LOOP_TMPDIR` is absolute AND begins with `/tmp/` OR `/private/tmp/` AND does NOT contain `..` as a path component (reject any occurrence of the literal `/..` or a trailing `..`; the `..` rejection closes the `/tmp/../etc/...` traversal bypass — a prefix check alone is insufficient) AND is an existing directory.

If any check fails, print `**⚠ 1: parse-args — invalid arguments (<specific failure>). Aborting.**` and abort **without writing any file** through `LOOP_TMPDIR`. Writing a `bad_args` status file through an untrusted path would defeat the validation itself — the outer's `verify-skill-called.sh --sentinel-file` gate already catches this case as `REASON=missing_path` when the completion sentinel is absent, which the outer maps to the generic "iteration sentinel missing" halt-detected EXIT_REASON. That diagnostic is sufficient; a dedicated `bad_args` status file is unnecessary and security-adverse.

The `LOOP_TMPDIR` prefix guard (`/tmp/` or `/private/tmp/`) plus the `..` rejection together form the skill's security boundary against arbitrary-path writes if the inner is ever invoked outside the outer orchestrator. Keep the checks literal; do NOT introduce broader canonicalization — the lightweight combined check is proportionate for an inner skill whose sole caller (`/loop-improve-skill`) controls its own input via `mktemp`.

Print: `✅ 1: parse-args — ITER=${ITER}, target=/${SKILL_NAME}`

## Step 2 — Set Up Per-Iteration File Paths

Establish canonical per-iteration file names under `$LOOP_TMPDIR`:
- `JUDGE_OUT="$LOOP_TMPDIR/iter-${ITER}-judge.txt"`
- `GRADE_OUT="$LOOP_TMPDIR/iter-${ITER}-grade.txt"`
- `DESIGN_OUT="$LOOP_TMPDIR/iter-${ITER}-design.txt"`
- `IM_OUT="$LOOP_TMPDIR/iter-${ITER}-im.txt"`
- `STATUS_FILE="$LOOP_TMPDIR/iter-${ITER}-status.txt"`
- `INFEASIBILITY_FILE="$LOOP_TMPDIR/iter-${ITER}-infeasibility.md"`
- `DONE_SENTINEL="$LOOP_TMPDIR/iter-${ITER}-done.sentinel"`

## Step 3.j — Run /skill-judge

Print: `> **🔶 3.j: judge**`

**Idempotency decision (three-state machine, closes #262).** On entry to Step 3.j, evaluate the on-disk ledger in this order and branch accordingly. This replaces the earlier single-state short-circuit: prior halt between Skill-tool return and the post-call Bash block would have re-run the Skill-tool call on resume, duplicating expensive judge work and producing a duplicate `gh issue comment`.

- **State A (already done)** — if `[[ -s "$LOOP_TMPDIR/iter-${ITER}-3j.done" ]]` (the completion sentinel exists AND is non-empty), print `⏩ 3.j: judge — already done (idempotent resume)` and skip to Step 3.j.v (NOT directly to 3.d — the new grade-A short-circuit lives in 3.j.v and must run on every resume).

- **State B (rescue path)** — if `[[ -e "$LOOP_TMPDIR/iter-${ITER}-3j-armed.marker" ]]` AND `[[ ! -s "$LOOP_TMPDIR/iter-${ITER}-3j.done" ]]` AND `[[ -s "$JUDGE_OUT" ]]`, the Skill-tool call ran previously and its response was transcribed to `$JUDGE_OUT` before the halt. Print `⏩ 3.j: judge — rescue path (reusing captured judge output; skipping Skill-tool call)`, skip directly to the post-call Bash block below, and do NOT re-run the Skill tool. Residual caveat: if the prior halt occurred after the `gh issue comment` was already posted but before `iter-${ITER}-3j.done` was written, the rescue path will re-post the same comment body — this narrower halt window is tracked as a follow-up OOS.

- **State C (full path)** — otherwise, run the pre-invocation Bash block, the Skill-tool call, the transcription, and the post-call Bash block in source order.

**Ordering invariant (State C).** Within a single iteration's full-path execution of Step 3.j, the armed-marker write MUST precede the Skill-tool call, which MUST precede the `$JUDGE_OUT` transcription, which MUST precede the post-call Bash block. The armed-marker-before-Skill-call half of this invariant is mechanically enforced by the line-order assertion in `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-continuation.sh` (armed-marker literal must appear on a lower line number than the bare-name Skill invocation literal in inner SKILL.md source order).

**Pre-invocation Bash block (State C only).** Write the armed marker immediately before invoking `/skill-judge`, in its own fenced block separate from the post-call block:

```bash
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3j-armed.marker"
```

Invoke the Skill tool with skill `"skill-judge"` (bare name first). On "no matching skill", retry with `"skill-judge:skill-judge"`. Pass the following string as args so the judge reads the current on-disk contents from the path resolved by the outer:

```
${SKILL_NAME} (absolute SKILL.md path: ${TARGET_SKILL_PATH}) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.
```

> **Continue after child returns.** When `/skill-judge` returns, transcribe its response to `$JUDGE_OUT` immediately, then execute 3.j's post-call gh-comment Bash block, then proceed to Step 3.j.v (the new grade-parse sub-step) — do NOT end the turn and do NOT skip directly to 3.d. The grade-A short-circuit and grade-history append both live in 3.j.v; bypassing it would silently break the strive-for-grade-A termination contract. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

Transcribe the judge's response to `$JUDGE_OUT` (full body, one write via the Bash tool). A single `>` redirect, never append — State B's reuse gate depends on `$JUDGE_OUT` being non-empty if and only if a prior full-path transcription completed.

**Post-call Bash block (runs after both State B rescue and State C full paths):**

```bash
JUDGE_COMMENT_FILE="$LOOP_TMPDIR/iter-${ITER}-judge-comment.md"
{ printf '## Iteration %s — skill-judge output\n\n' "${ITER}"; cat "$JUDGE_OUT"; } > "$JUDGE_COMMENT_FILE"
gh issue comment "${ISSUE_NUM}" --body-file "$JUDGE_COMMENT_FILE"
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3j.done"
```

The `printf 'done\n' > ...` (not `touch`) is load-bearing — `verify-skill-called.sh --sentinel-file` requires the file to be non-empty (`-s` check in `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh`). An empty sentinel would cause the outer's gate to misclassify this iteration as a halt. The same `printf 'done\n' > ...` convention applies to the armed marker written in the pre-invocation Bash block above, keeping sentinel culture uniform across the Step 3.j ledger even though no `verify-skill-called.sh --sentinel-file` check currently targets the armed marker directly.

## Step 3.j.v — Grade Parse (grade-A short-circuit)

Print: `> **🔶 3.j.v: grade parse**`

**Idempotency short-circuit.** If `$LOOP_TMPDIR/iter-${ITER}-3jv.done` already exists and is non-empty, print `⏩ 3.j.v: grade parse — already done (idempotent resume)`, read cached `$GRADE_OUT` to recover `GRADE_A` / `NON_A_DIMS` / `PARSE_STATUS`, and branch as below without re-invoking the parser.

This is the new grade-gated termination point. Parse `$JUDGE_OUT` for per-dimension scores via the shared parser:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh "$JUDGE_OUT" > "$GRADE_OUT"
```

Read `$GRADE_OUT` for `PARSE_STATUS`, `GRADE_A`, `NON_A_DIMS`, `TOTAL_NUM`, `TOTAL_DEN`, and per-dim `D<N>_NUM` / `D<N>_DEN`. The parser is fail-closed: any non-ok `PARSE_STATUS` forces `GRADE_A=false`, so the loop continues iterating rather than exiting on a parse failure.

Append one line to `$LOOP_TMPDIR/grade-history.txt`:

- When `PARSE_STATUS=ok`: `iter=${ITER} total=${TOTAL_NUM}/${TOTAL_DEN} non_a=${NON_A_DIMS} parse_status=ok`
- When `PARSE_STATUS!=ok`: `iter=${ITER} total=N/A non_a=N/A parse_status=${PARSE_STATUS}` (literal `N/A` — the parser does not emit `TOTAL_NUM` / `TOTAL_DEN` / `NON_A_DIMS` on non-ok statuses).

Write the per-substep sentinel **before** branching (so both grade-A short-circuit and grade-non-A continuation paths execute the write unconditionally — no path can skip the sentinel by jumping to Step 4 prematurely):

```bash
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3jv.done"
```

The `printf 'done\n'` (not `touch`) is load-bearing for the same reason as the 3.j sentinel — non-empty file required for any future verify-skill-called.sh check.

Branch on `GRADE_A`:

- **`GRADE_A=true`**: the target skill already grades A on every dimension D1..D8. Set `ITER_STATUS=grade_a_achieved` and skip directly to Step 4 (bypass 3.d and 3.i — there is nothing to improve this iteration). The outer's Step 4.v will recognize `grade_a_achieved` as a terminal happy-path exit and break out of the loop.
- **`GRADE_A=false`**: continue to Step 3.d. The Non-A dimensions (`NON_A_DIMS`) and per-dim deficits will be passed to /design's prompt (see Step 3.d below) so /design focuses its plan on the specific point shortfalls — this directly counters the historical failure mode where Non-A findings were deemed "not worth implementing".

## Step 3.d — Run /design

Print: `> **🔶 3.d: design**`

**Idempotency short-circuit.** If `$LOOP_TMPDIR/iter-${ITER}-3d-plan-post.done` already exists and is non-empty (plan already posted for this iteration in a prior partial run), print `⏩ 3.d: design — already done (idempotent resume)` and skip to Step 3.i.

Invoke the Skill tool with skill `"design"` (bare name first; fallback `"larch:design"`). Pass a prompt asking for an improvement plan for `/${SKILL_NAME}` that addresses the `/skill-judge` findings just captured.

**Non-A dimensions focus block (conditional).** When the Step 3.j.v parse succeeded (`PARSE_STATUS=ok`) AND `GRADE_A=false`, the prompt MUST also include this block listing the specific point deficits that block grade A:

```
Non-A dimensions from this iteration's /skill-judge: ${NON_A_DIMS}.
Per-dimension deficits (current/required):
  D<N> at <D<N>_NUM>/<D<N>_DEN> (needs >=<threshold> for A; short by <delta>)
  ... (one line per dim in NON_A_DIMS)
Focus this iteration's plan on raising these dimensions to grade A.
Treat this deficit list as the canonical set of must-address findings — do
NOT self-curtail on the grounds that these are "minor". The loop's
termination contract requires per-dimension A on ALL D1..D8; any non-A
dimension is load-bearing for forward progress.
```

This block directly addresses the historical failure mode where /design declared "no plan" on Non-A findings deemed not worth implementing — the new termination contract treats every non-A dimension as load-bearing.

The prompt MUST include these three contract clauses verbatim so `/design` produces a plan even for minor findings and never self-curtails on budget:

- `/design` MUST produce a concrete, implementable plan for ANY actionable `/skill-judge` finding — including findings classified "minor", "nit", or cosmetic. Treat "minor" as "small plan", not as "no plan".
- `/design` MUST NOT self-curtail citing token/context budget. Under any perceived pressure, narrow scope to the single highest-leverage finding and emit a compressed micro-plan that still conforms to the standard `/design` plan schema (`## Implementation Plan` with `Files to modify/create`, `Approach`, `Edge cases`, `Testing strategy`, and `Failure modes` when the change is non-trivial per `/design`'s own rules) — never emit a no-plan sentinel on budget grounds.
- `/design` MUST NOT emit any of the no-plan sentinel phrases (`no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`) when `/skill-judge` surfaced any actionable finding. Sentinels are reserved for the genuine case where no improvement is warranted.

The prompt MUST also explicitly name `TARGET_SKILL_PATH` as the absolute path of the SKILL.md to modify. Capture the full response to `$DESIGN_OUT` via a Bash write.

> **Continue after child returns.** When `/design` returns, run the tightened no-plan detector below, then the rescue path (when applicable), and then either post the plan and continue to 3.i or exit the loop with a no-plan status — do NOT end the turn. **Token/context budget is NOT a valid exit condition**; only the four authoritative exits end the iteration: empty `$DESIGN_OUT`, tightened no-plan sentinel match, explicit refusal/error from `/design`, or the outer's ITER>10 cap.

After the first `/design` returns, touch the pre-rescue-detector sentinel and run the detector:

```bash
printf 'done\n' > "$LOOP_TMPDIR/iter-${ITER}-3d-pre-detect.done"
```

**No-plan detection (tightened).** Set `ITER_STATUS=no_plan`, run the **Infeasibility justification write** sub-procedure documented before Step 4 below, and skip to Step 4 if any of:

- `$DESIGN_OUT` is empty.
- The first non-blank line of `$DESIGN_OUT`, trimmed and case-folded, matches one of these exact sentinels: `no plan`, `no improvements`, `nothing to improve`, `already optimal`, `skill is already high quality`, **AND** no structured plan marker appears on any subsequent line of `$DESIGN_OUT`. Match sentinels against the whole trimmed first non-blank line only — do NOT substring-search the body. A **structured plan marker** is any line matching one of these anchored regexes (line-start only):
  - `^#{1,6}\s` — markdown heading (1-6 leading `#` followed by whitespace).
  - `^[1-9]\d?\.\s` — numbered list counter from 1 through 99, then `.` and whitespace.
  - `^[-*+]\s` — bulleted list item (`-`, `*`, or `+` followed by whitespace).

  If ANY line after the sentinel-matching first line matches one of the marker regexes, the sentinel match does NOT fire.

- `/design` returned an explicit refusal or error (a structured error response from the Skill tool, or a prose response whose entire body clearly says `/design` could not run). In this case set `ITER_STATUS=design_refusal` (not `no_plan`), run the **Infeasibility justification write** sub-procedure, and skip to Step 4.

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

Re-run the tightened no-plan detector on the (new) `$DESIGN_OUT`. If it fires, set `ITER_STATUS=no_plan` (or `ITER_STATUS=design_refusal` if rescue returned an explicit refusal/error), run the **Infeasibility justification write** sub-procedure, and skip to Step 4. Do NOT chain a second rescue — at most one rescue per iteration. If the four rescue conditions did not hold in the first place, skip the rescue entirely but still touch the post-rescue-detector sentinel (so the ledger is uniform — the sentinel means "the post-rescue-detector branch ran to completion", not "the rescue fired").

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

- **`VERIFIED=false`**: `/im` did not reach its canonical completion line (either halted, bailed internally, or the capture failed). Set `ITER_STATUS=im_verification_failed`, run the **Infeasibility justification write** sub-procedure documented before Step 4 below, and proceed to Step 4. Do NOT write the 3.i sentinel — the absent sentinel is an observable ledger state the outer (or a follow-up run) can use to diagnose.

The `verify-skill-called.sh --stdout-line` gate is load-bearing: it is the only mechanism in the loop that verifies `/im` ran by reading a child-produced string rather than a parent-written artifact. Do NOT replace it with a `touch`-only fallback — per the Post-invocation verification rule in `subskill-invocation.md`, gates the parent can satisfy without the child's side effects are not real gates.

## Infeasibility justification write (sub-procedure)

Invoked from the three halt paths above (no_plan / design_refusal / im_verification_failed) BEFORE falling through to Step 4. Writes a structured markdown justification to `$INFEASIBILITY_FILE` so the outer's Step 5 close-out can embed it in the final tracking-issue comment. The outer's "strive for grade A" termination contract requires that any non-grade-A exit explain why further automated progress toward A is blocked.

Compose the file in a single Bash block (heredoc; one redirect, no partial writes). Substitute the iteration's actual `ITER_STATUS`, `PARSE_STATUS`, `GRADE_A`, and `NON_A_DIMS` values captured at Step 3.j.v (recover from `$GRADE_OUT` if not in scope):

```bash
{
  printf '## Infeasibility Justification — iteration %s\n\n' "${ITER}"
  printf '**Status**: %s\n\n' "${ITER_STATUS}"
  printf '**Reason**: <status-specific reason. For no_plan: "/design emitted no-plan sentinel despite Non-A dimensions ${NON_A_DIMS}". For design_refusal: "/design returned structured refusal: <one-line excerpt from $DESIGN_OUT>". For im_verification_failed: "/im did not reach its canonical completion line — see iter-${ITER}-im.txt; the iteration produced design output (iter-${ITER}-design.txt) but the implementation pipeline could not be verified as complete.">\n\n'
  printf '**Context**:\n'
  printf -- '- Grade parse at start of iteration: PARSE_STATUS=%s, GRADE_A=%s, non-A dimensions: %s\n' "${PARSE_STATUS}" "${GRADE_A}" "${NON_A_DIMS}"
  printf -- '- Judge output: iter-%s-judge.txt\n' "${ITER}"
  printf -- '- Design output (if any): iter-%s-design.txt\n' "${ITER}"
  printf -- '- /im output (if any): iter-%s-im.txt\n\n' "${ITER}"
  printf '**Why this blocks reaching grade A**: <one-paragraph justification tying the halt to why further automated progress toward grade A is blocked at this iteration. For no_plan: /design could not articulate a plan for the listed Non-A dimensions despite the Step 3.d focus block — without a plan there is no implementation candidate. For design_refusal: /design itself failed to run, so no plan could be produced. For im_verification_failed: a plan was produced but could not be landed safely (CI failure, merge conflict, or pipeline halt) — the failed plan would need a different approach to make progress.>\n'
} > "$INFEASIBILITY_FILE"
```

Substitute concrete prose for the three angle-bracketed `<...>` placeholders based on which halt path invoked this sub-procedure. The outer's Step 5 close-out reads `$INFEASIBILITY_FILE` verbatim into the final comment under a `## Infeasibility Justification` heading. If the file write fails for any reason, the inner still falls through to Step 4 — the outer's Step 5 detects a missing file with infeasibility ITER_STATUS and uses fallback text citing the existing per-iter tmp files.

## Step 4 — Inner Close-Out

If `ITER_STATUS` is unset by this point, default it to `completed` (the happy path all through 3.j/3.d/3.i).

Write the status file and the outer-visible completion sentinel:

```bash
printf 'ITER_STATUS=%s\n' "${ITER_STATUS}" > "$STATUS_FILE"
printf 'ITER=%s\n' "${ITER}" > "$DONE_SENTINEL"
```

The `$DONE_SENTINEL` is non-empty by design so `verify-skill-called.sh --sentinel-file` in the outer's mechanical gate returns `VERIFIED=true`. The `ITER=` body also gives a forensic breadcrumb in case a directory of sentinels needs to be reconstructed after a crash.

Print: `✅ 4: inner close-out — ITER=${ITER}, status=${ITER_STATUS}`
