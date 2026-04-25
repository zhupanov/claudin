# /research Evaluation Set

**Consumer**: `scripts/eval-research.sh` — the offline harness reads this catalog, parses each entry's fields, runs `/research` once per entry under the configured scale, and scores the output against the entry's expectations.

**Contract**: Frozen registry of representative `/research` evaluation questions. Twenty entries balanced across five categories (`lookup`, `architecture`, `external-comparison`, `risk-assessment`, `feasibility`). Each entry declares an `id` (kebab-case, unique), a verbatim `question` string, a `category` from the enum above, an `expected_provenance_count` integer (minimum file/path/URL citations a passing answer should contain), an `expected_keywords` comma-separated list (case-insensitive substrings a good synthesis should mention), and a `notes` line for human grading guidance. Two entries are flagged adversarial in their notes — one targets a fictitious mechanism, one targets a data-absence question — to test over-claiming. The catalog is human-edited; mechanical schema validation is performed by `scripts/eval-research.sh --smoke-test` and `scripts/test-eval-set-structure.sh`. Authors editing this file must follow the global reference rules enforced by `scripts/test-references-headers.sh` (see its sibling contract for details on the Contract-paragraph and header-triplet checks).

**When to load**: When iterating on a `/research` prompt or harness change. The harness is the only programmatic consumer; humans read this file when authoring new evaluation questions or interpreting harness output. Not loaded by `/research` itself or by any other skill at runtime.

**Source**: Anthropic's *How we built our multi-agent research system* and *Building Effective Agents* describe small-sample (~20-case) rubric-based LLM-as-judge evaluation as the substrate for prompt-side iteration. This catalog is the local instantiation.

---

## Entries

### eval-1: where-defined-rebase-push
- **question**: Where is `rebase-push.sh` defined in this repository, what does its `--skip-if-pushed` flag do, and which scripts consume it?
- **category**: lookup
- **expected_provenance_count**: 3
- **expected_keywords**: rebase-push.sh, --skip-if-pushed, SKIPPED_ALREADY_PUSHED, scripts/
- **notes**: Lookup; should cite `scripts/rebase-push.sh` plus at least two consumers (the Rebase Checkpoint Macro in `/implement` and any Step 1 / Step 1.m caller).

### eval-2: deny-edit-write-hook-contract
- **question**: How does the `/research` skill's best-effort read-only contract partition mechanically enforced versus prompt-enforced perimeters, what hook backs the mechanical tier, and what tools fall under the prompt-enforced tier?
- **category**: lookup
- **expected_provenance_count**: 2
- **expected_keywords**: deny-edit-write.sh, /tmp, PreToolUse, best-effort, Bash, external reviewers, SECURITY.md
- **notes**: Lookup; should cite `scripts/deny-edit-write.sh` for the mechanical tier (Edit/Write/NotebookEdit confined to canonical `/tmp`), name Bash + external Cursor/Codex reviewers as the prompt-enforced tier, and reference the SECURITY.md residual-risk framing.

### eval-3: anchor-section-slugs
- **question**: What are the 8 canonical anchor section slugs in `/implement`, in assembly order, and which script defines them?
- **category**: lookup
- **expected_provenance_count**: 1
- **expected_keywords**: SECTION_MARKERS, plan-goals-test, run-statistics, anchor-section-markers.sh
- **notes**: Lookup; should list all 8 slugs verbatim and cite `scripts/anchor-section-markers.sh`. A correct answer reproduces the array order from the canonical script.

### eval-4: eval-baseline-q1-2026
- **question**: What was the result of the `/research` evaluation harness's 2026-Q1 baseline run, and what were the per-entry judge scores?
- **category**: lookup
- **expected_provenance_count**: 0
- **expected_keywords**: no data, schema-only stub, baseline.json, eval-research
- **notes**: ADVERSARIAL — data-absence. The harness landed in this PR; no Q1-2026 baseline run exists. `eval-baseline.json` is committed as a schema-only stub with `entries: []`. A correct answer says "no data — the harness was added in PR closing #419 and the baseline file is currently a schema-only stub awaiting a follow-up populate run." A failing answer invents numeric scores or claims a prior run.

### eval-5: dialectic-protocol-resolution
- **question**: How does the dialectic protocol resolve contested decisions in `/design` Step 2a.5, and how does the bucket-assignment rule prevent a single-tool outage from blocking debate?
- **category**: architecture
- **expected_provenance_count**: 2
- **expected_keywords**: dialectic-protocol.md, Disposition, voted, bucket-skipped, dialectic_codex_available
- **notes**: Architecture; should explain bucket assignment (decisions 1/3/5 → Cursor, 2/4 → Codex), the shadow-flag pattern that protects orchestrator-wide availability, and the four Disposition values (`voted`, `fallback-to-synthesis`, `bucket-skipped`, `over-cap`).

### eval-6: parent-issue-sentinel-branches
- **question**: What is the relationship between `/implement` Step 0.5 Branches 1 through 4 and the `parent-issue.md` sentinel file, and how does the sentinel preserve idempotency across resumed runs?
- **category**: architecture
- **expected_provenance_count**: 2
- **expected_keywords**: parent-issue.md, ADOPTED, Branch 1, Branch 4, Load-Bearing Invariant, ANCHOR_COMMENT_ID
- **notes**: Architecture; should cover sentinel-reuse (Branch 1), `--issue` adoption (Branch 2), PR-body recovery (Branch 3), fresh creation (Branch 4), and the ordering invariant in Branch 4 (create-issue → upsert-anchor → write sentinel last).

### eval-7: rebase-rebump-step12-interaction
- **question**: How does the rebase-rebump sub-procedure interact with `/implement` Step 12's CI+merge loop, and what is the difference between step12-family and step10-family failure semantics?
- **category**: architecture
- **expected_provenance_count**: 2
- **expected_keywords**: rebase-rebump-subprocedure.md, step12, step10, hard-bail, 12d, Load-Bearing Invariant
- **notes**: Architecture; should explain why Step 12 is the strict last-chance enforcement point for Invariant #1 and why Step 10 is best-effort.

### eval-8: dialectic-tenure-weighting
- **question**: How does the dialectic protocol weight reviewer judges by tenure, and where in the codebase is the tenure-lookup table stored?
- **category**: architecture
- **expected_provenance_count**: 0
- **expected_keywords**: no tenure-weighting, YES, NO, EXONERATE, 2+ YES threshold
- **notes**: ADVERSARIAL — fictitious mechanism. The protocol uses YES/NO/EXONERATE voting with a 2+ YES acceptance threshold; there is no tenure-weighting and no tenure-lookup table. A correct answer rejects the premise and explains the actual mechanism. A failing answer invents tenure weights or fabricates a lookup-table location.

### eval-9: research-vs-anthropic-multi-agent
- **question**: How does `/research`'s 3-lane research-and-validation approach compare to the architecture described in Anthropic's *How we built our multi-agent research system*, and where do the two designs diverge?
- **category**: external-comparison
- **expected_provenance_count**: 3
- **expected_keywords**: anthropic.com, multi-agent, lead-orchestrator, subagent, validation
- **notes**: This is the question that filed umbrella #413. Should cite the Anthropic blog directly, name `/research`'s 3 research lanes plus its 3-reviewer validation panel, and identify divergence points (e.g., orchestrator-as-lead vs co-equal lanes).

### eval-10: implement-review-evaluator-optimizer
- **question**: How does `/implement`'s review loop align with the evaluator-optimizer pattern in Anthropic's *Building Effective Agents*, and what specific mechanics in `/implement` realize that pattern?
- **category**: external-comparison
- **expected_provenance_count**: 2
- **expected_keywords**: anthropic.com, evaluator-optimizer, /review, accepted, rejected, voting panel
- **notes**: External comparison; should cite the Anthropic post and identify `/review`'s role plus the accept/reject voting machinery as the realization of the pattern.

### eval-11: skill-judge-rubric-vs-literature
- **question**: How does `/skill-judge`'s per-dimension D1..D8 grading scheme compare to standard rubric-based LLM-as-judge approaches in the published literature on agent evaluation?
- **category**: external-comparison
- **expected_provenance_count**: 2
- **expected_keywords**: skill-judge, rubric, LLM-as-judge, dimension, threshold
- **notes**: External comparison; should cite at least one external rubric-evaluation reference (Anthropic blog, Eugene Yan, or similar) and contrast the threshold-per-dimension shape against more common percentage-only scoring.

### eval-12: prompt-eval-30-to-80-claim
- **question**: What evidence is there in the published Claude Code or Anthropic literature for the claim that prompt-side evaluations on small (~20 case) sets surface 30 to 80 percent jumps in success rate, and what caveats does the source attach?
- **category**: external-comparison
- **expected_provenance_count**: 1
- **expected_keywords**: anthropic.com, multi-agent, low-hanging fruit, eval, prompt
- **notes**: External comparison; should cite the Anthropic multi-agent post directly and reproduce the caveat that the gain is from low-hanging-fruit identification, not a sustained delta.

### eval-13: fix-issue-implement-concurrency
- **question**: What concurrency hazards exist when `/fix-issue` and `/implement` run against the same tracking issue, and how does the IN PROGRESS comment lock interact with the `parent-issue.md` sentinel?
- **category**: risk-assessment
- **expected_provenance_count**: 2
- **expected_keywords**: IN PROGRESS, find-lock-issue.sh, single-runner, sentinel, ADOPTED
- **notes**: Risk; should describe the comment-stream locking pattern, the duplicate-creation mode if Branch 4 is interrupted between issue-create and sentinel-write, and the Known Limitations note about single-runner assumption.

### eval-14: implement-cursor-timeout-mid-sketch
- **question**: What happens to a `/implement` run if `/design`'s Cursor sketch lane times out mid-sketch, and how do `cursor_available` versus `dialectic_cursor_available` differ in their session scope?
- **category**: risk-assessment
- **expected_provenance_count**: 2
- **expected_keywords**: Runtime Timeout Fallback, dialectic_cursor_available, snapshot, Option B
- **notes**: Risk; should explain the orchestrator-wide flip that affects subsequent steps versus the dialectic-scoped shadow flag that does NOT mutate the orchestrator-wide flag.

### eval-15: rebase-rebump-failure-modes
- **question**: What are the failure modes of `/implement`'s Step 12 rebase-rebump sub-procedure, and how does each map to step12-family hard-bail versus step10-family graceful-degrade behavior?
- **category**: risk-assessment
- **expected_provenance_count**: 2
- **expected_keywords**: rebase-push.sh, check-bump-version.sh, VERIFIED, hard-bail, 12d, step10
- **notes**: Risk; should enumerate at least three failure modes (rebase conflict, push rejection, post-check `STATUS != ok`) and pair each with the correct caller-family disposition.

### eval-16: deny-edit-write-bypass-blast-radius
- **question**: What is the security blast-radius if `/research`'s deny-edit-write hook is bypassed, what mechanisms in the repo backstop the hook, and what residual risk is documented?
- **category**: risk-assessment
- **expected_provenance_count**: 2
- **expected_keywords**: deny-edit-write.sh, allowed-tools, SECURITY.md, no mechanical fallback
- **notes**: Risk; should identify the hook as the sole mechanical enforcement, note that `allowed-tools` declares the surface but does not confine writes, and quote the residual-risk language from SECURITY.md or the SKILL.md contract paragraph.

### eval-17: research-structured-output-feasibility
- **question**: Could `/research` be extended to produce a structured machine-readable output alongside the current human-readable Research Report without breaking existing consumers, and what would the migration shape look like?
- **category**: feasibility
- **expected_provenance_count**: 2
- **expected_keywords**: Research Report, Step 3, JSON, validation-phase.md, backward compat
- **notes**: Feasibility; should reference the current Step 3 template, identify the consumer boundary (today: human + this eval harness), and propose a side-by-side emission shape.

### eval-18: implement-fully-offline
- **question**: Is it feasible to run `/implement` entirely offline with no GitHub API and no Slack, what subset of features survives, and which load-bearing invariants would degrade?
- **category**: feasibility
- **expected_provenance_count**: 3
- **expected_keywords**: repo_unavailable, slack_available, deferred, parent-issue.md, Known Limitations
- **notes**: Feasibility; should walk the `repo_unavailable=true` and `slack_enabled=false` paths and identify which steps degrade or skip cleanly versus which break.

### eval-19: research-plan-flag-issue-420
- **question**: How feasible is adding a `--plan` flag to `/research` per issue #420, and what dependencies does that work have on this evaluation harness or on issue #418 (the `--scale` flag)?
- **category**: feasibility
- **expected_provenance_count**: 2
- **expected_keywords**: --plan, --scale, planner pre-pass, eval-set, dependency
- **notes**: Feasibility; should describe the planner-pre-pass concept, identify the eval-harness dependency for measuring the planner's marginal benefit (from issue #420 itself), and note that #418 `--scale` is parallel work, not a hard prerequisite.

### eval-20: pairwise-blinded-eval-extension
- **question**: How feasible is extending the `/research` evaluation harness to support a blinded pairwise comparison mode for the `--baseline` workflow, where the judge sees two anonymized syntheses and ranks them, and what published evidence supports preferring relative over absolute judgments?
- **category**: feasibility
- **expected_provenance_count**: 2
- **expected_keywords**: blinded, pairwise, --baseline, eval-research.sh, judge
- **notes**: Feasibility; should describe the harness change shape (a second judge prompt that swaps left/right, paired with a counterbalanced second call), and cite at least one external source on pairwise vs absolute evaluation stability.
