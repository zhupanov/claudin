---
name: loop-improve-skill
description: "Use when iteratively improving an existing skill via a judge-design-implement loop in a GitHub issue; bash driver invokes /skill-judge, /design, /im as fresh `claude -p` subprocesses; runs up to 10 rounds."
argument-hint: "<skill-name>"
allowed-tools: Bash
---

# loop-improve-skill

Iteratively improve an existing skill. Creates a tracking GitHub issue, then runs up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` — each invoked as a fresh `claude -p` subprocess by the driver. Halt class eliminated by construction: each child's report is its subprocess's output, so there is no post-child-return model turn that can halt (closes #273).

Example: `/loop-improve-skill design` or `/loop-improve-skill /design`.

**Termination contract: strive for grade A.** The loop's primary success exit is when `${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh` reports per-dimension grade A on every D1..D8. The loop continues iterating until (a) grade A is achieved, (b) further automated progress is genuinely infeasible (no_plan / design_refusal / im_verification_failed, with written justification), or (c) the 10-iteration cap is reached (final re-judge captures post-cap grade). Token/context budget is NOT a valid exit condition.

## Driver

Execution is delegated to the bash driver at `${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh`. The driver owns loop control, subprocess invocation, grade parsing, audit-trail posting, infeasibility detection, close-out composition, and cleanup. See `driver.sh` source for the loop semantics.

```bash
"${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh" $ARGUMENTS
```

## Verification

The driver's structural and behavioral contracts are regression-guarded by `${CLAUDE_PLUGIN_ROOT}/scripts/test-loop-improve-skill-driver.sh` (wired into `make lint` via the `test-loop-improve-skill-driver` target). On success the driver posts a close-out comment to the tracking issue containing a `## Grade History` section and (for non-grade-A exits) an `## Infeasibility Justification` section — reviewing that comment is the user-visible verification that the loop ran to an authoritative exit.
