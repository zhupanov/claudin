# Triage and Classification

**Consumer**: `/fix-issue` Steps 4 (Triage) and 5 (Classify Intent and Complexity).

**Contract**: Authoritative detail for the triage checks, the not-material closure flow, the intent dimension (PR vs NON_PR) with its "default to PR when uncertain" rule, and the complexity dimension (SIMPLE vs HARD, evaluated only when `INTENT=PR`) with its "default to HARD when uncertain" rule. SKILL.md carries the step-level breadcrumbs, the `issue-lifecycle.sh close` / `post-issue-slack.sh` invocations, and the `Print ✅ 5: classify — INTENT=$INTENT [COMPLEXITY=$COMPLEXITY]` line; this file carries the judgment-heavy detail that would bloat the main-file knowledge delta.

**When to load**: before executing Step 4 (Triage) OR Step 5 (Classify). Load once — the two step-bodies consume the same detail. **Do NOT load** in any other step — Steps 0 / 1 / 2 / 3 / 6 / 7 / 8 / 9 do not consume this content. **Do NOT load** when the Step 1 `fetch-eligible-issue.sh` call returned exit 1 (no approved issues found) or exit 2+ (error) — Steps 4 and 5 are skipped on those paths.

**Sibling**: `skills/fix-issue/references/non-pr-execution.md` owns the NON_PR-path execution detail consumed by Step 6b.

---

## Step 4 — Triage detail

Read the issue details from Step 3. Explore the codebase using Read, Grep, and Glob to determine if the issue is still actual — that is, whether it describes a real problem that still needs fixing.

Check for:

- Has the issue already been fixed by recent commits?
- Is the code/feature the issue references still present?
- Is the issue a valid bug/feature request, or was it filed in error?
- For investigation/review-only issues (whose deliverable is research findings or new issues rather than code changes): is the **task itself** still relevant — are the targets, scope, and constraints it describes still meaningful — rather than "is the referenced bug still in code"?

### Not-material closure flow

If the issue is no longer material (already fixed, invalid, or no longer relevant):

1. Compose a detailed explanation of why the issue is no longer material. Include a summary of the research performed: which files were checked, what recent commits were examined, and what evidence led to the conclusion. This explanation is written into the issue body so that anyone reviewing the closed issue can understand the rationale without re-investigating.
2. SKILL.md Step 4 invokes `issue-lifecycle.sh close` with the detailed explanation as the `--comment` value.
3. SKILL.md Step 4 invokes `post-issue-slack.sh` with a one-sentence reason summarizing the closure (only when `slack_available=true`).
4. SKILL.md Step 4 prints the not-material breadcrumb and skips to Step 9.

If the issue is still actual, SKILL.md Step 4 prints the active breadcrumb and continues to Step 5.

## Step 5 — Classification detail

Based on the issue details and codebase exploration from Step 4, determine two independent dimensions.

### Dimension 1 — Intent

Does this issue prescribe work that should produce a pull request?

- **PR**: The issue prescribes a code change — bug fix, refactor, new feature, documentation edit, prompt/skill edit, config change, test addition, etc. — whose natural output is a pull request against the current repository.
- **NON_PR**: The issue prescribes an investigative or review task whose natural output is something other than a PR: new GitHub issues summarizing research findings, new GitHub issues flagging code-review problems, a written report, or similar. Typical signals: the issue body contains phrases like "research and summarize", "investigate and report", "code-review this module and file issues", "do not create a PR", or otherwise makes clear that the deliverable is issues/reports rather than code changes.

**Default to `PR` when uncertain.** The `PR` path is the pre-existing behavior; misclassifying a borderline `NON_PR` as `PR` is recoverable (`/implement`'s `/review` phase surfaces the mismatch) while misclassifying a `PR` as `NON_PR` could silently skip real work.

### Dimension 2 — Complexity (evaluated only when `INTENT=PR`)

- **SIMPLE**: Isolated fix in 2 or fewer files. Obvious solution with no architectural decisions needed. Examples: typo fix, small bug with clear root cause, config change.
- **HARD**: Everything else. Multi-file changes, new features, architectural decisions, unclear root cause, or any uncertainty.

**Default to HARD when uncertain.** A HARD classification uses the full `/design` + `/review` pipeline, which is safer for non-trivial changes.

When `INTENT=NON_PR`, complexity is not meaningful — leave `COMPLEXITY` unset and skip the SIMPLE/HARD determination. SKILL.md Step 5 prints the classification breadcrumb (omitting the `COMPLEXITY=` segment when `INTENT=NON_PR`) and proceeds to Step 6.
