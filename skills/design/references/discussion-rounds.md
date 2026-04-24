# Discussion Rounds Reference

**Consumer**: `/design` Steps 1c, 1d, 3.5, and the `auto_mode=false AND (qa_happened OR dialectic_adjudicated)` branch of Step 3a.

**Contract**: owns the four discussion-round bodies (Step 1c clarifying questions, Step 1d round 1, Step 3.5 round 2, Step 3a post-review confirmation) with their decision-tree walks, question caps, output schemas (`$DESIGN_TMPDIR/discussion-round1.md`, `$DESIGN_TMPDIR/discussion-round2.md`), the terse-answer rule, and the `$DESIGN_TMPDIR/user-qa-happened.md` sentinel write (touched by Steps 1c/1d/3.5 whenever at least one `AskUserQuestion` actually asks the user a question; absent when a step short-circuits without asking). SKILL.md retains the `auto_mode` gate + skip breadcrumbs inline; this file owns body content only.

**When to load**: once the calling step in SKILL.md has passed its `auto_mode=false` gate (and, for Step 3a, additionally confirmed `qa_happened OR dialectic_adjudicated`). Do NOT load when `auto_mode=true` at Steps 1c/1d/3.5/3a, or when Step 3a's "no Q/A and no dialectic adjudication" short-circuit fires.

**Binding convention**: single normative source for discussion-round behavior (decision-tree walk, question caps, output schemas, terse-answer rule, sentinel file) and the Step 3a interactive-approval body. Each consumer step in SKILL.md performs its own `auto_mode=false` gate (and for Step 3a additionally the `qa_happened OR dialectic_adjudicated` gate) before dispatching here; this file assumes the caller has already passed those gates. The `auto_mode=true` skip breadcrumb and (for Step 3a) the "no Q/A and no dialectic adjudication" skip breadcrumb remain inline in SKILL.md so they are emitted without loading this file.

---

## Step 1c — Clarifying Questions (auto_mode=false body)

Before launching the expensive collaborative sketch phase, use `AskUserQuestion` to clarify any ambiguities in the feature description. This is the highest-value question point — answers here reshape what the sketch agents explore.

Consider asking about:
- **Scope boundaries**: What is explicitly in-scope vs. out-of-scope? Are there related changes the user does NOT want?
- **Key decisions**: When there are meaningful alternatives (e.g., different architectural approaches, different file organization), present the options and ask which direction to take.
- **Unclear requirements**: Any aspect of the feature description that is vague, could be interpreted multiple ways, or has implicit assumptions.

**Guidelines**:
- Only ask questions when there is genuine ambiguity — do NOT ask trivially answerable questions or re-confirm what is already clear.
- Batch questions into a single `AskUserQuestion` call with 1-4 questions rather than multiple sequential calls.
- If the feature description is clear and unambiguous, print `✅ 1c: questions — no clarifying questions needed (<elapsed>)` and proceed to Step 1d. Do NOT write the sentinel on this path — no Q/A occurred.

After the user responds, incorporate their answers into your understanding of the feature for all subsequent steps.

### Sentinel — record that Q/A occurred

If at least one question was actually asked via `AskUserQuestion` in this step, write the Q/A sentinel (used by Step 3a's gate to decide whether a post-review confirmation is warranted):

```bash
touch "$DESIGN_TMPDIR/user-qa-happened.md"
```

Skip the `touch` on the short-circuit path above (feature clear, no questions asked).

---

## Step 1d — Design Discussion Round 1 (auto_mode=false body)

Before launching the expensive collaborative sketch phase, stress-test the feature's scope and requirements by walking through the decision tree one question at a time. This is a deeper, sequential interrogation that resolves dependencies between decisions — each answer may reshape subsequent questions.

### Behavior

The orchestrator identifies key **scope and requirements decisions** from the feature description by exploring the codebase (Read/Grep/Glob). It builds a mental decision tree covering:
- **Scope boundaries**: What is explicitly in-scope vs. out-of-scope?
- **Hard constraints**: What must not break? What existing behavior must be preserved?
- **Non-goals**: What does the user explicitly NOT want?
- **Must-have requirements**: What is the minimum viable outcome?

Then walk each branch one question at a time via sequential `AskUserQuestion` calls, providing a **recommended answer** for each question. If a question can be answered by exploring the codebase, do so and report the finding instead of asking the user.

**Explicit prohibition**: Do NOT ask about implementation approach, architectural preferences, library choices, or file organization. Those decisions belong to the sketch phase (Step 2a). Round 1 is strictly requirements/scope clarification.

### Short-circuit

If the feature is straightforward with fewer than 2 scope decision branches, print `⏩ 1d: discussion r1 — no scope decisions require discussion (<elapsed>)` and proceed to Step 2a.

### Output

Write resolved decisions to `$DESIGN_TMPDIR/discussion-round1.md` using a simple Q&A format:

```markdown
### Decision 1: <short title>
- **Question**: <the question asked>
- **Resolution**: <the answer — from user or codebase>
- **Source**: user / codebase
```

This file captures scope boundaries and hard constraints only — NOT architectural preferences.

### Cap

At most **7 `AskUserQuestion` calls** in this step. If more than 7 decision branches remain after 7 questions, print: `⏩ Remaining scope questions deferred to implementation.` and proceed.

### Terse answers

If the user gives a terse or non-responsive answer (e.g., "I don't know", "your recommendation is fine", "sure"), accept the recommended answer and move on without re-asking.

### Sentinel — record that Q/A occurred

If at least one question was actually asked via `AskUserQuestion` in this step (i.e., the user was prompted at least once — terse answers still count as Q/A because the user was asked), write the Q/A sentinel (used by Step 3a's gate to decide whether a post-review confirmation is warranted):

```bash
touch "$DESIGN_TMPDIR/user-qa-happened.md"
```

Skip the `touch` on the short-circuit path (fewer than 2 scope decision branches — no questions asked).

Print: `✅ 1d: discussion r1 — <N> decisions resolved (<elapsed>)`

---

## Step 3.5 — Design Discussion Round 2 (auto_mode=false body)

After the plan has been reviewed and revised, stress-test the remaining design decisions that were either (a) not covered in Round 1, or (b) deemed suboptimal by reviewers, or (c) introduced by the plan itself (decisions that didn't exist at the feature-description stage).

### Inputs

Read the following artifacts:
- `$DESIGN_TMPDIR/discussion-round1.md` — If it exists and is non-empty, use it to identify decisions already covered in Round 1 (avoid re-asking). **If it does not exist or is empty** (Round 1 short-circuited or was skipped), treat all candidate decisions as uncovered by Round 1 and proceed normally.
- `$DESIGN_TMPDIR/accepted-plan-findings.md` — If it exists and is non-empty, use it to identify decisions that reviewers challenged as suboptimal or that required plan revision.
- `$DESIGN_TMPDIR/contested-decisions.md` — Decisions that sketch agents disagreed on.
- `$DESIGN_TMPDIR/dialectic-resolutions.md` — How contested decisions were resolved.

Also reference the revised (or original) implementation plan from Step 3's output visible in conversation context above.

### Behavior

Identify decisions in the implementation plan that meet any of these criteria:
1. **Not covered in Round 1** — decisions that emerged from the plan design, not from the original feature description.
2. **Challenged by reviewers** — decisions that appear in `accepted-plan-findings.md` (reviewers found them suboptimal and the plan was revised).
3. **Still contested** — decisions whose `dialectic-resolutions.md` entry matches any of the following (per the protocol in `${CLAUDE_PLUGIN_ROOT}/skills/shared/dialectic-protocol.md`):
   - `Disposition: voted` AND `Vote tally` shows a close 2-1 split (the minority 1 vote signals substantive disagreement).
   - `Disposition: fallback-to-synthesis` (the dialectic layer could not resolve).
   - `Disposition: bucket-skipped` (no debate occurred — tool was unavailable).
   - `Disposition: over-cap` (no debate occurred — decision ranked outside the top-5 dialectic cap).

Walk each uncovered branch one question at a time via sequential `AskUserQuestion` calls, providing a **recommended answer** for each question. If a question can be answered by exploring the codebase, do so and report the finding instead of asking the user.

Unlike Round 1, Round 2 MAY ask about architectural decisions and implementation approach — the sketch phase has already provided divergent perspectives, so anchoring is no longer a concern at this stage.

### Short-circuit

If all plan decisions are already covered by Round 1, no reviewer findings challenged them, and no decisions in `dialectic-resolutions.md` match the still-contested criteria above (no close 2-1 voted splits, no fallback-to-synthesis, no bucket-skipped, no over-cap entries), print `⏩ 3.5: discussion r2 — no additional decisions require discussion (<elapsed>)` and proceed to Step 3a.

### Output

Write resolved decisions to `$DESIGN_TMPDIR/discussion-round2.md` using the same format as Round 1:

```markdown
### Decision 1: <short title>
- **Question**: <the question asked>
- **Resolution**: <the answer — from user or codebase>
- **Source**: user / codebase
```

**Auto-revise**: Update the implementation plan in-place based on answers. Print the revised plan only if substantive changes were made.

### Cap

At most **7 `AskUserQuestion` calls** in this step. If more than 7 decision branches remain, print: `⏩ Remaining design questions deferred to implementation.` and proceed.

### Terse answers

If the user gives a terse or non-responsive answer, accept the recommended answer and move on without re-asking.

### Sentinel — record that Q/A occurred

If at least one question was actually asked via `AskUserQuestion` in this step (terse answers still count as Q/A), write the Q/A sentinel (used by Step 3a's gate to decide whether a post-review confirmation is warranted):

```bash
touch "$DESIGN_TMPDIR/user-qa-happened.md"
```

Skip the `touch` on the short-circuit path (all decisions already covered — no questions asked).

Print: `✅ 3.5: discussion r2 — <N> decisions resolved (<elapsed>)`

---

## Step 3a — Post-Review Confirmation (auto_mode=false AND (qa_happened OR dialectic_adjudicated) body)

Use `AskUserQuestion` to confirm the plan addresses the user's original intent, now that the design stage has engaged the user or resolved contested opinions. Present a brief summary tailored to what triggered this step, then ask the user to approve or reject:

- **If `qa_happened`**: one-line summary of the user decisions captured in `$DESIGN_TMPDIR/discussion-round1.md` and/or `$DESIGN_TMPDIR/discussion-round2.md` (whichever exist and are non-empty), plus the clarifying answers from Step 1c if the feature was shaped by those.
- **If `dialectic_adjudicated`**: one-line summary of the adjudicated decisions in `$DESIGN_TMPDIR/dialectic-resolutions.md` (only entries with `Disposition: voted` or `Disposition: fallback-to-synthesis`).
- **If both**: cover both.
- **If the plan was also revised by reviewers**: additionally note what reviewers changed.

**This step is strictly approval-only** — the user confirms the plan is acceptable to proceed with implementation. No substantive plan changes are accepted at this point — the reviewed/voted plan is the canonical artifact. If the user rejects the plan, print a warning and proceed anyway (the plan has already been reviewed and voted on; the user can adjust during implementation or in a follow-up PR).
