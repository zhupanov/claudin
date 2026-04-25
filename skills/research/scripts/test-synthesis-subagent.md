# test-synthesis-subagent.sh — contract

**Consumer**: `make lint` (via the `test-synthesis-subagent` Makefile target).

**Purpose**: offline structural pin for the /research Step 1.5 synthesis-subagent contract introduced by issue #507 and the Step 2 Finalize Validation revision-subagent contract. The harness greps `skills/research/references/research-phase.md` and `skills/research/references/validation-phase.md` for the load-bearing prose introduced by #507; it does NOT execute the subagents (that requires a live Claude Agent context that CI cannot reach).

**Wired into**: `Makefile` `test-harnesses` target via `test-synthesis-subagent` target. Both `.PHONY` (line 4) and the `test-harnesses` dependency list (line 14) carry the target name.

**Pins enforced**:

1. **Subagent invocation in 4 non-quick branches** — Standard `RESEARCH_PLAN=false`, Standard `RESEARCH_PLAN=true`, Deep `RESEARCH_PLAN=false`, Deep `RESEARCH_PLAN=true` MUST each contain (a) "synthesis subagent" / "Agent subagent" / "Invoke the synthesis subagent" prose, (b) a `compute-degraded-banner.sh` fork reference, (c) "structural validator" gate prose, (d) "fallback" / "falling back to inline" prose.

2. **Quick branch unchanged** — §1.5 Quick branch MUST NOT contain Agent invocation or validator prose; MUST retain the "Single-lane confidence" disclaimer.

3. **5 body markers mandated** — §1.5 prose MUST mandate the 5 body markers (`### Agreements`, `### Divergences`, `### Significance`, `### Architectural patterns`, `### Risks and feasibility`).

4. **Per-subquestion regex anchor mandated** — §1.5 prose MUST contain the literal `^### Subquestion [0-9]+:` (the anchored regex used by the validator's RESEARCH_PLAN=true counting rule).

5. **`### Per-angle highlights` mandated in Deep+plan** — §1.5 Deep `RESEARCH_PLAN=true` MUST mandate `### Per-angle highlights`.

6. **`### Cross-cutting findings` mandated in plan branches** — both Standard `RESEARCH_PLAN=true` and Deep `RESEARCH_PLAN=true` MUST mandate `### Cross-cutting findings`.

7. **4 angle names mandated in Deep branches** — §1.5 Deep MUST name all 4 angles in synthesis prose: `architecture & data flow`, `edge cases & failure modes`, `external comparisons`, `security & threat surface`.

8. **Finalize Validation routes revision to a subagent** — `validation-phase.md` `## Finalize Validation` MUST contain (a) "revision subagent" prose, (b) `revision-raw.txt` capture path, (c) "atomically rewrite" / "atomic rewrite" / "mktemp + mv" prose for `research-report.txt`, (d) "structural validator" prose, (e) "inline revision" / "Inline-revision fallback" prose.

9. **Helper script presence + executability** — `skills/research/scripts/compute-degraded-banner.sh` MUST exist AND be executable.

**Edit-in-sync surfaces**: this harness pins prose-level contracts. When editing `research-phase.md` §1.5 or `validation-phase.md` Finalize Validation, run this harness to verify the load-bearing prose remains present. The harness does NOT pin specific wording beyond the load-bearing literals; rephrasing the surrounding prose is allowed as long as the regex/grep targets remain present.

**Stdout contract**:

- On success: `PASS: test-synthesis-subagent.sh — <N> assertions passed` (single line, exit 0).
- On any failure: per-pin diagnostic lines on stderr, summary line `test-synthesis-subagent.sh — <P> passed, <F> failed` on stderr, exit 1.

**Maintenance**:

- When changing the 5 body markers: update `REQUIRED_MARKERS` in this harness AND the prompt prose in `research-phase.md` §1.5.
- When changing the angle names: update `ANGLE_NAMES` in this harness AND the prompt prose in `research-phase.md` §1.5 Deep branches AND `SKILL.md` Step 1 mandatory-read directive.
- When renaming `compute-degraded-banner.sh`: update `HELPER_SCRIPT` in this harness AND the corresponding fork references in `research-phase.md` §1.5 prose.
- When renaming `revision-raw.txt`: update Pin 7b grep target.
