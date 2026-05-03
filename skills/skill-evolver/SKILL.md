---
name: skill-evolver
description: "Use when evolving an existing larch skill — runs /research on sibling skills + reputable external sources (Anthropic, OpenAI, DeepMind, top OSS), then delegates actionable findings to /umbrella to file GitHub issues."
argument-hint: "<skill-name>"
allowed-tools: Bash, Read, Skill
---

# skill-evolver

Plan improvements for an existing larch skill in a single research-and-file-issues pass. Take a mandatory `<skill-name>` (must already exist under `skills/<name>/` or `.claude/skills/<name>/` in the current plugin repo), invoke `/research` via the Skill tool against repo-local sibling skills + reputable external sources (Anthropic, OpenAI, DeepMind, ≥500-star OSS), and — if the research lane surfaces ≥1 actionable improvement with citations — invoke `/umbrella` via the Skill tool to file the resulting GitHub issue(s). `/research` runs the fixed 4 research + 3 validation lane shape internally. `/umbrella` runs its own one-shot vs multi-piece classifier on the distilled task description.

The skill itself does NOT modify the target skill's files. Implementation of each improvement happens later via `/fix-issue`. This skill is research-and-file-issues only.

Example: `/skill-evolver design` or `/skill-evolver review`.

> **Before editing**, read `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` (full file). Section III mechanical rules A/B/C override general writing-style guidance on conflict.

## Prerequisites

`/skill-evolver` delegates to two sibling skills via the Skill tool. Both must be present in the loaded plugin/session:

- **`/research`** — ships with this plugin under `${CLAUDE_PLUGIN_ROOT}/skills/research/` (always available when the larch plugin is loaded).
- **`/umbrella`** — ships with this plugin under `${CLAUDE_PLUGIN_ROOT}/skills/umbrella/` (always available when the larch plugin is loaded).

**Anti-halt continuation reminder.** After every child `Skill` tool call (`/research`, `/umbrella`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (`exit cleanly`, `skip to Step N`). See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

## Anti-patterns

- **NEVER modify the target skill's files from inside this skill.** Why: the contract is research-and-file-issues only. Editing `<SKILL_DIR>/` here would bypass the umbrella + child-issue tracking, the per-change `/review` panel, and the `/fix-issue` lifecycle that downstream agents depend on. Implementation lands later via `/fix-issue`.
- **NEVER inline the target SKILL.md body into the `/research` prompt.** Why: deep-mode fan-out spawns 5 research lanes + 5 validation lanes — each receives the full prompt. Inlining the target body multiplies token cost by 10× without benefit; the lanes have full Read/Grep/Glob access and should read `<SKILL_DIR>/SKILL.md` themselves. Pass the **path**, not the contents.
- **NEVER pass the verbatim `/research` report as the `/umbrella` task description.** Why: `/umbrella`'s classifier expects a multi-piece task description naming distinct phases, not a multi-section research narrative with reviewer commentary and validation tables. Distill the actionable improvements into a numbered phase list (one phase per improvement, citations preserved) before invoking `/umbrella`.
- **NEVER call `/umbrella` when `/research` returns zero actionable improvements.** Why: an empty umbrella creates a tracking issue with no children — pure noise. Print the canonical Step 3 zero-branch message (the `**ℹ /skill-evolver: …**` line whose verbatim text lives in Step 3) and exit cleanly.
- **NEVER accept a target skill name without verifying the SKILL.md exists.** Why: a typo (`/skill-evolver dezign`) would otherwise burn a full deep-mode `/research` run on a nonexistent target before failing at the umbrella step. `validate-args.sh` checks `skills/<name>/SKILL.md` and `.claude/skills/<name>/SKILL.md` and aborts before any `/research` call.

## Step 1 — Validate Arguments

```bash
${CLAUDE_PLUGIN_ROOT}/skills/skill-evolver/scripts/validate-args.sh $ARGUMENTS
```

Parse stdout key=value lines: `VALID` (`true|false`), `SKILL_NAME` (canonical kebab name, leading `/` stripped), `SKILL_DIR` (absolute path to the target skill's directory), `DEBUG` (`true|false`), `ERROR` (only when `VALID=false`).

If `VALID=false`: print the `ERROR=` message and abort cleanly — do NOT proceed to Step 2. (`validate-args.sh` always exits 0 by contract; `VALID=false` on stdout is the branch signal, parallel to the convention in `skills/create-skill/scripts/validate-args.sh`. Parse stdout only — do not branch on the exit code.)

The validator enforces:
- `<skill-name>` matches `^[a-z][a-z0-9-]*$`, length ≤ 64. Leading `/` is stripped before validation.
- CWD is a larch plugin repo (`.claude-plugin/plugin.json` + `skills/implement/SKILL.md` present).
- Target skill exists at `skills/<name>/SKILL.md` (preferred — plugin tree) or `.claude/skills/<name>/SKILL.md` (project-local fallback).

The full stdout grammar, error contract, positional-argument rules, and edit-in-sync obligations live in the sibling contract at `${CLAUDE_PLUGIN_ROOT}/skills/skill-evolver/scripts/validate-args.md`.

Save `SKILL_NAME`, `SKILL_DIR`, `DEBUG` for Steps 2 and 3.

## Step 2 — Run /research

Compose the research prompt by substituting `<SKILL_NAME>` and `<SKILL_DIR>` into the template below. Verify both substitutions before invoking `/research`. The lanes have full `Read | Grep | Glob | Bash` and can read the target skill themselves — pass the **path**, not the contents.

### Prompt template

```
Research concrete actionable improvements to the existing larch skill `/<SKILL_NAME>` located at `<SKILL_DIR>/SKILL.md`.

Read `<SKILL_DIR>/SKILL.md` and any helper scripts under `<SKILL_DIR>/scripts/` to understand the current capability surface, mechanical contracts, and design choices.

What I want from this research:

1. **Repo-local survey.** Read every other SKILL.md under `skills/` and `.claude/skills/`. Identify capabilities, prompt patterns, mechanical-rule applications (Section III A/B/C), anti-pattern formulations, progressive-disclosure techniques (Section II), or freedom-calibration choices (Section VII) present in sibling skills that `/<SKILL_NAME>` could adopt to improve quality, robustness, or token efficiency. Each comparison must cite the specific sibling skill and a `file:line` reference.

2. **External literature survey.** Search reputable sources for skill-design patterns, agent orchestration techniques, or prompt-engineering refinements relevant to `/<SKILL_NAME>`'s role. Bias toward Anthropic documentation (claude.com, docs.anthropic.com, engineering.anthropic.com), OpenAI cookbook + agents documentation, DeepMind / Gemini agent literature, and open-source GitHub repositories with ≥500 stars on agent skills, SKILL.md authoring, or prompt engineering. Each external comparison must cite a specific URL.

3. **Concrete, actionable improvements for `/<SKILL_NAME>`.** Each finding must specify: (a) the exact file path inside the target skill that should change; (b) what to modify; (c) the cited evidence (sibling skill `file:line` or external URL); (d) a one-paragraph proposed implementation that a `/fix-issue` agent can execute without re-doing this research. Vague suggestions ("improve clarity", "add more examples", "consider refactoring") are explicitly out of scope.

Out of scope:
- Changes requiring new external dependencies the larch plugin does not already use.
- Cosmetic refactors that don't change behavior or a measurable quality metric.
- Changes to skills OTHER than `/<SKILL_NAME>`.
- Implementation work itself — this is research-only.

Output: a structured `## Research Report` with one numbered finding per improvement, each carrying citations and a proposed implementation paragraph. The report MUST end with exactly one machine-readable line of the form `ACTIONABLE_IMPROVEMENTS_COUNT=<integer>` on its own line — `<integer>` is the count of findings that satisfy the (a)/(b)/(c)/(d) shape above (or `0` if none). The orchestrator's Step 3 branch reads this single line; do not embed the count in surrounding prose.
```

### Invocation

Invoke the Skill tool:
- Try skill `"research"` first (bare name). If no skill matches, try `"larch:research"` (fully-qualified plugin name).
- args: `--no-issue <substituted-prompt>`. `--no-issue` suppresses `/research`'s automatic issue creation — `/skill-evolver` delegates issue filing to `/umbrella` in Step 3, not to `/research`'s auto-issue.

After `/research` returns, read its `## Research Report` from conversation context. The report is followed by an optional `## Citation Validation` block when `/research`'s sidecar exists (Step 3 splice in `skills/research/SKILL.md`), so the literal last line of the combined output is NOT necessarily the count. Parse the **last line of the file matching `^ACTIONABLE_IMPROVEMENTS_COUNT=`**, ignoring any trailing `## Citation Validation` content. The integer on that line drives Step 3.

If no such line is present (the `/research` lane synthesis dropped the requested footer), fall back to a deterministic count: scan the `## Research Report` body for findings shaped per the (a)/(b)/(c)/(d) template above (each item must explicitly cite both (a) a target file path AND (c) cited evidence — sibling-skill `file:line` or external URL — to count). Bind the resulting integer to `ACTIONABLE_IMPROVEMENTS_COUNT` and proceed. If the report is empty, malformed, or contains no shape-conformant findings, treat the count as `0` (Step 3 zero branch) — do NOT abort the skill on a missing count line.

## Step 3 — Decide and Delegate to /umbrella

**Branch on `ACTIONABLE_IMPROVEMENTS_COUNT`**:

- **`= 0`**: print this exact line verbatim (canonical zero-branch message — the anti-pattern bullet above also points here):

  ```
  **ℹ /skill-evolver: /research surfaced no actionable improvements for /<SKILL_NAME>. Exiting cleanly without filing issues.**
  ```

  and exit. Do NOT delegate to `/umbrella` with an empty task description.

- **`>= 1`**: compose a multi-piece umbrella task description by distilling the research findings. Each improvement becomes one numbered phase: `Phase N: <one-line summary>. <file path to modify>. <cited evidence>. <proposed implementation paragraph>.` Preserve the citations (sibling-skill `file:line` references and external URLs) so each child issue carries the evidence the lane found — `/umbrella` forwards the description verbatim into `/issue`'s child bodies.

  Then invoke the Skill tool:
  - Try skill `"umbrella"` first (bare name). If no skill matches, try `"larch:umbrella"`.
  - args: `--label evolved-by:skill-evolver --label skill:<SKILL_NAME> --title-prefix "[skill-evolver:<SKILL_NAME>] " <umbrella-task-description>`.

  After `/umbrella` returns, branch on its `UMBRELLA_VERDICT` line (per `skills/umbrella/SKILL.md` Step 4 stdout grammar — `UMBRELLA_NUMBER` and `UMBRELLA_URL` are emitted only on the multi-piece success path; one-shot success emits `CHILD_1_URL` instead; failure paths omit `UMBRELLA_NUMBER` and `UMBRELLA_URL` entirely; `CHILDREN_CREATED=<N>` and `CHILDREN_DEDUPLICATED=<N>` are emitted on every multi-piece path AND on the one-shot path — consumers must branch on these counters to distinguish a newly-filed issue from one deduplicated to an existing GitHub issue, since `CHILD_1_URL` is populated in both cases per `/umbrella`'s renormalized `CHILD_*` set rule):
  - `UMBRELLA_VERDICT=multi-piece` AND `UMBRELLA_URL` present: print `✅ /skill-evolver: filed umbrella #<UMBRELLA_NUMBER> at <UMBRELLA_URL> with <CHILDREN_CREATED> child issues.`
  - `UMBRELLA_VERDICT=one-shot` AND `CHILDREN_CREATED=1` AND `CHILD_1_URL` present: print `✅ /skill-evolver: filed as a single issue at <CHILD_1_URL> (one-shot per /umbrella's classifier — see /umbrella's UMBRELLA_RATIONALE for the classification reason).` Note: `UMBRELLA_VERDICT=one-shot` does NOT mean `ACTIONABLE_IMPROVEMENTS_COUNT=1` — `/umbrella`'s classifier may downgrade a multi-finding task description to one-shot when decomposition produces fewer than two pieces (see `skills/umbrella/SKILL.md` UMBRELLA_DOWNGRADE=decomposition-lt-2 path). Do NOT claim "single actionable improvement" in the success line — the runtime predicate is the verdict, not the count.
  - `UMBRELLA_VERDICT=one-shot` AND `CHILDREN_CREATED=0` AND `CHILDREN_DEDUPLICATED=1` AND `CHILD_1_URL` present: print `**ℹ /skill-evolver: dedup'd to existing issue at <CHILD_1_URL> (one-shot per /umbrella's classifier — no new issue created; see /umbrella's UMBRELLA_RATIONALE for the classification reason).**` The `CHILDREN_CREATED=0` predicate makes this branch mutually exclusive with the filed branch — on the `UMBRELLA_DOWNGRADE=created-eq-1` bypass path, `/umbrella` emits both `CHILDREN_CREATED=1` AND `CHILDREN_DEDUPLICATED=<D>` simultaneously (see `skills/umbrella/SKILL.md` Step 3B.2 created-eq-1 bypass), in which case the filed branch fires (correct: a new issue WAS created; deduplicated siblings are secondary).
  - Any other shape (failure, dry-run, partial): print `**⚠ /skill-evolver: /umbrella did not return a recognized success shape. See /umbrella's stdout above for status.**` Do NOT fabricate a URL. Continue cleanly.

## What this skill does NOT do

- Does not modify `<SKILL_DIR>/` files. Implementation happens later via `/fix-issue` (per child issue).
- Does not run benchmarks, quality scoring, or grading.
- Does not iterate. One invocation = one `/research` invocation (which fans out to 4 research + 3 validation lanes internally) + one (conditional) `/umbrella`. Re-run `/skill-evolver` after children land if you want a fresh research pass against the evolved skill.
