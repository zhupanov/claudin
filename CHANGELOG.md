# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [7.4.17] - 2026-04-25

### Fixed

- `scripts/build-research-adjudication-ballot.sh` attribution scrubber now strips the deep-mode reviewer attributions `Code-Sec` and `Code-Arch` (introduced by `/research --scale=deep`) at anchored prefix/suffix positions, in addition to the standard `Cursor|Codex|Claude|Code|orchestrator|Code Reviewer` set. Without this, a deep-mode reviewer's rejected finding carried into adjudication preserved its leading `Code-Sec:` / `Code-Arch:` attribution inside `<defense_content>`, breaking the anonymous-Defense-A/B guarantee since judges could infer which deep-mode lane authored the defense. The two new tokens precede `Code` in the alternation so the longer deep-mode names match before the shorter prefix (POSIX ERE leftmost-longest within an alternation is unreliable across awk implementations; explicit ordering is portable). The script's file-header comment block documenting the regex literal and the sibling contract `scripts/build-research-adjudication-ballot.md` (Anchored-only attribution stripping section, Regex applied block, fixture-case table, deterministic-ordering inequality chain) are updated in lockstep. The harness `scripts/test-research-adjudication.sh` adds Test 11 covering anchored prefix stripping (`Code-Sec:` / `Code-Arch:`), anchored suffix stripping (`(Code-Sec)` / `— Code-Arch`), and mid-content preservation. Closes #461.

## [7.4.16] - 2026-04-25

### Fixed

- `scripts/build-research-adjudication-ballot.sh` `emit_failure` now writes `FAILED=true` / `ERROR=<msg>` to stderr (fd 2) instead of stdout (fd 1). The two `emit_failure` calls in the Phase 3 `base64 -d` failure paths are inside the `{ ... } > "$OUTPUT"` brace group; with the former stdout output, the failure lines were redirected into the ballot file, leaving the caller (`scripts/run-research-adjudication.sh`) with no `ERROR=` line to extract via `grep -E '^ERROR='` and forcing it to fall back to a hardcoded "Ballot builder failed" message. The in-repo caller already merges streams via `2>&1`, so its existing extraction continues to work after the fix. Header docstring, `usage()` heredoc, and sibling contract `scripts/build-research-adjudication-ballot.md` updated to describe the split-stream output contract. New regression Test 10 in `scripts/test-research-adjudication.sh` asserts `ERROR=` lands on stderr (not stdout) under separated-stream capture, with a parallel assertion that caller-style `2>&1` merge still surfaces the line. Pre-existing OOS surfaced during PR #420 review; not introduced by #420 (the ballot builder was added in PR #443). Closes #463.

## [7.4.15] - 2026-04-25

### Changed

- `skills/fix-issue/SKILL.md` Known Limitations — extended the "Lock-before-setup behavioral delta" bullet to explicitly cite preflight `git fetch origin main` (run by `session-setup.sh` via `preflight.sh` before mktemp) as the network-bound, transient Step 2 failure most likely to leave a stale `IN PROGRESS` lock under the `fetch → lock → setup` ordering introduced by PR #468, alongside the existing non-network `REPO_UNAVAILABLE=true` example. Adds an editorial note recording that the design panel for the related reorder voted 3 EXONERATE on the heavier "split `session-setup.sh` into pre-lock preflight + post-lock setup" mitigation (judging the structural split heavier than warranted), so the documented failure mode is the accepted trade-off rather than a deferred bug. Documentation-only; no `session-setup.sh` / `preflight.sh` code changes, no step reordering, no new test harness. Closes #471.

## [7.4.14] - 2026-04-25

### Fixed

- `scripts/test-research-structure.sh` Check 12 — replaced the two-grep AND (`grep -Fq "Aborting" && grep -Fq "must be one of quick|standard|deep"`) with a single `grep -Fq` of the full composite literal `must be one of quick|standard|deep (got: foo). Aborting.`, the intended `--scale=foo` error sentence in `skills/research/SKILL.md`. The prior two-grep form succeeded if either substring appeared anywhere in the file, so an unrelated `Aborting` elsewhere could satisfy it spuriously. Failure message and the sibling contract assertion (12) in `scripts/test-research-structure.md` updated to reference the composite literal. Pre-existing OOS surfaced during PR #420 review. Closes #460.

## [7.4.13] - 2026-04-25

### Fixed

- `skills/research/SKILL.md` — aligned two outlier prose statements with the canonical "always-print-with-zero-marker" rule for quick mode's report-publication layer. Line 17 (overview) previously said "skips the validation phase entirely"; line 139 (Step 0b) previously said Step 3 "omits the validation-phase line entirely". Both contradicted the Step 3 Quick branch (lines 226-233) which sets `VALIDATION_HEADER="0 reviewers (validation phase skipped — see synthesis disclaimer)"` and explicitly states "the validation-phase line is still rendered ... so the report template's structure is preserved", and the unconditional report template at line 252 (`**Validation phase**: <VALIDATION_HEADER>`). The fix disambiguates two surfaces: (a) execution layer — Step 2 (validation panel) does not run in quick mode; (b) publication layer — the report still renders a `**Validation phase**: 0 reviewers (...)` placeholder line so the template shape is uniform across scales. Edit 2's parenthetical uses a section-heading anchor rather than approximate line numbers (per /design plan-review FINDING_1). Closes #449.

## [7.4.12] - 2026-04-25

### Fixed

- `scripts/validate-research-output.sh` exit-4 diagnostic now reads `file missing or not readable: <path>` instead of `file not found: <path>`. The predicate gating exit 4 is `[[ ! -r "$INPUT" ]]`, which is true for both a nonexistent file and an existing-but-permission-denied file, so the original "file not found" wording silently mis-described the second case. The combined wording matches the existing repo convention used in `scripts/render-reviewer-prompt.sh:86`. Header-comment contract lines documenting exit 4 and the sibling `scripts/validate-research-output.md` updated in lockstep; the regression test `scripts/test-validate-research-output.sh` case 15 only asserts exit code 4, not the diagnostic text, so no test edits were required (38/38 cases still pass). Closes #459.

## [7.4.11] - 2026-04-25

### Fixed

- `scripts/test-research-adjudication.md` — corrected the contract heading from "Scope (seven assertions)" to "Scope (nine assertions)" and added bullets describing Test 8 (multi-line Finding/rationale round-trip via the FS sentinel substitution) and Test 9 (literal-tab round-trip via the GS sentinel substitution + tr-decode). Extended the Edit-in-sync invariants subsection with FS-sentinel and GS-sentinel substitution rules so future edits to those encoders surface the matching test updates. `scripts/test-research-adjudication.sh` header (lines 5-15) — replaced the stale 7-item listing with a 9-item listing that mirrors the actual test order in the script (1: empty input; 2: deterministic ordering; 3: DECISION renumbering; 4: position rotation; 5: anchored-only attribution stripping; 6: `<defense_content>` wrapping; 7: ballot header text; 8: multi-line round-trip; 9: literal-tab round-trip). Pure documentation drift fix; no behavioral change to the harness. Pre-existing OOS surfaced during PR #420 review; not introduced by #420. Closes #457.

## [7.4.10] - 2026-04-25

### Changed

- `scripts/build-research-adjudication-ballot.sh`'s `strip_attribution()` awk END block dropped the dead `prefix_re` variable assignment. Only `prefix_re_short` was ever read (applied to the first non-empty line); the unused `prefix_re` was a maintenance/clarity hazard for future regex tweaks. `prefix_re_short` and `suffix_re` remain unchanged. Pre-existing OOS surfaced during issue #420 review. Closes #458.

## [7.4.8] - 2026-04-25

### Fixed

- `SECURITY.md` line 70 — corrected the `tracking-issue-write.sh` outbound-path subsection's count from "nine assertion categories" to "eleven assertion categories (a)–(k)", matching the canonical (a)–(k) ID table in `scripts/test-tracking-issue-write.md` and the `Eleven assertion categories (a-k)` header comment in `scripts/test-tracking-issue-write.sh`. Added an inline pointer from the SECURITY.md sentence to the canonical ID table so future drift between the count word and the table is caught at edit-time. Pre-existing OOS surfaced during PR #420 review (Cursor); not introduced by #420. Closes #456.

## [7.4.7] - 2026-04-25

### Fixed

- `scripts/validate-research-output.sh` provenance probe 1 (line 182) now broadens the recognized extension list from 13 to 51 entries (adding `tsx`, `jsx`, `vue`, `html`, `css`, `scss`, `rb`, `java`, `c`, `cpp`, `h`, `kt`, `swift`, `php`, `cs`, `lua`, `r`, `m`, `scala`, `dart`, `gradle`, `mk`, `cfg`, `ini`, `env`, `lock`, `proto`, plus a few other common forms) and requires a trailing-token boundary so the extension cannot bleed into adjacent path-token characters. Boundary class `[^A-Za-z0-9_:/-]` excludes alnum, `_`, `-`, `:`, and `/`; `.` IS a valid boundary so sentence-ending periods (`See foo.sh.`) and compound-extension forms (`Cargo.lock.bak`, `bundle.js.map`) match by substring evidence, while bypass forms (`file.mdjunk:42`, `file.md:garbage`, `file.md/child`) are rejected. Alternation is ordered longest-first within each prefix-conflict family (`cc|cfg|cjs|cpp|css|csv|cs|c`, `html|htm|hpp|h`, `json|jsx|js`, `mjs|mk|mm|md|m`, `rb|rs|r`, `tsx|tsv|ts`) so `grep -E` on BSD/macOS does not depend on backtracking-through-alternation to satisfy the trailing-boundary constraint. Updates lock down behavior across `scripts/validate-research-output.sh` (probe 1 regex + the script-header extension list which feeds `--help`), the sibling contract `scripts/validate-research-output.md` (extension list, boundary semantics, documented limitations: bare hidden-file forms `.env:7` / `.gitignore:5` not matched; underscore-glued prose like `file.md_for` not matched; short / generic-English extensions like `lock`/`env`/`txt`/`r`/`m` may false-positive on prose tokens), the regression test `scripts/test-validate-research-output.sh` (38 cases — added 25-30 for broadened extensions, 31-32 for fake-citation bypass rejection, 33-34 for happy-path / prose-glued comma, 35 for compound-extension acceptance, 36 for sentence-ending period acceptance, 37-38 for `:garbage` / `/child` bypass rejection; harness header listing extended to 1-38), and `docs/linting.md` (case count 24 → 38). Closes #447.

## [7.4.6] - 2026-04-25

### Changed

- `scripts/test-design-structure.sh` now pins the Step-3a removal that landed in PR #454 with two additional structural assertions: Check 5 grep-walks the entire `skills/design/` tree (SKILL.md and `references/**`) for the residue tokens `Step 3a`, `Post-Review Confirmation`, `user-qa-happened`, `qa_happened`, `dialectic_adjudicated` and fails on any match; Check 6 verifies that `skills/design/SKILL.md`'s Step 3 ("all reviewers OK") branch and Step 3.5 auto-mode branch both forward to `Step 3b` (literal-match `or Step 3b if auto_mode=true` and `and proceed to Step 3b` respectively). The success line now reports "all 6 structural invariants hold". `scripts/test-design-structure.md` documents Checks 5 and 6 in the contract per the AGENTS.md per-script-contracts rule. No Makefile changes — the existing `test-design-structure` `make lint` target continues to wire the harness in. Closes #453.

## [7.4.5] - 2026-04-25

### Added

- `skills/fix-issue/scripts/test-fix-issue-step-order.sh` — offline regression harness pinning the `/fix-issue` Step 1 = lock, Step 2 = setup ordering established by PR #468 (closes #445). Twelve assertions over `skills/fix-issue/SKILL.md`: nine textual literal pins (Step Name Registry rows, section headings, anti-pattern #1 wording, lock breadcrumb literals positive/negative) plus three operational ordering pins (`awk`-scoped block extraction asserting that the Step 1 block contains the `issue-lifecycle.sh ... --lock` invocation, the Step 1 block does NOT contain `session-setup.sh`, and the Step 2 block contains `session-setup.sh --prefix claude-fix-issue --skip-branch-check`). The block-scoped assertions are the load-bearing guard against a future edit that keeps headings/registry/breadcrumbs intact while moving setup back into the lock block. Sibling contract `skills/fix-issue/scripts/test-fix-issue-step-order.md` documents the assertion list and edit-in-sync rules. Wired into `make lint` via the `test-fix-issue-step-order` target under `test-harnesses`; both the `.sh` and the sibling `.md` are added to `agent-lint.toml`'s `exclude` lists, matching the same Makefile-only-reference pattern used by `test-fix-issue-bail-detection`. Co-evolved with the PR review process: 1 round of /review surfaced FINDING_1 (header-comment / accumulator-pattern accuracy) and FINDING_2 (operational ordering not pinned by literal-only assertions); both accepted by 2-1 vote and applied before merge. Closes #445 follow-up.

## [7.4.4] - 2026-04-25

### Changed

- `skills/shared/dialectic-protocol.md` is now caller-neutral: every `$DESIGN_TMPDIR` placeholder in the Overview, Ballot Format, Judge Prompt Template, judge-launch bash blocks, and the Writing dialectic-resolutions.md section was renamed to a generic `$DIALECTIC_TMPDIR` placeholder, and a new `## Caller Binding` section near the top documents that callers MUST substitute the literal `$DIALECTIC_TMPDIR` token with their own session-tmpdir path at prompt-construction time (a *prompt-construction substitution rule, not a shell-level variable export* — external CLIs do not expand shell variables in prompt arguments). The two known callers were updated in lockstep with caller-binding paragraphs: `skills/design/references/dialectic-execution.md` documents `DIALECTIC_TMPDIR ↔ $DESIGN_TMPDIR` (semantic correspondence — the file's bash continues to use `$DESIGN_TMPDIR` directly); `skills/research/references/adjudication-phase.md` documents `DIALECTIC_TMPDIR ↔ $RESEARCH_TMPDIR` (body uses `$RESEARCH_TMPDIR` directly with research-context basenames `research-adjudication-ballot.txt` / `adjudication-resolutions.md`). The adjudication-phase.md substitution-note paragraph (line 13) was rewritten to drop the now-inaccurate "$RESEARCH_TMPDIR substituted for $DESIGN_TMPDIR" framing and replace the implementer checklist with three distinct, non-self-matching grep entries scoped to executable bash code-fenced blocks — items 1, 2, 3 cover the design-context tmpdir variable, ballot filename, and resolutions filename respectively, each describing the failure mode the grep catches without spelling the literal token in checklist prose. Closes #440.

## [7.4.3] - 2026-04-25

### Changed

- `/fix-issue` now acquires the `IN PROGRESS` comment lock at Step 1, immediately after Step 0 fetches an eligible issue, before Step 2 session setup. The prior `fetch → setup → lock` ordering left a TOCTOU window between candidate selection and lock acquisition; the new `fetch → lock → setup` ordering narrows that window. Trade-off: a Step 2 setup failure (e.g. `REPO_UNAVAILABLE=true`) can now strand the issue locked with `IN PROGRESS` rather than leaving the `GO` sentinel intact — recovery is the same manual `IN PROGRESS` clearance + re-add `GO` flow as any other post-lock failure, documented in Known Limitations under "Lock-before-setup behavioral delta". `issue-lifecycle.sh` resolves repo identity itself via `gh repo view`, so the lock script does not depend on session-setup state. Cross-doc renumbering: `skills/fix-issue/SKILL.md` Step Name Registry, anti-pattern 1, Mindset crash-locus bullet, Step 0 / Step 9 cross-references, Known Limitations, the triage-classification reference's `Do NOT load` early-exit list; `skills/fix-issue/scripts/fetch-eligible-issue.sh` header comment; `skills/fix-issue/scripts/issue-lifecycle.md` contract preamble; `skills/shared/subskill-invocation.md` session-env handoff bullet; `scripts/tracking-issue-write.md` distinction-from-comment-lock note; `agent-lint.toml` parser-and-harness exclusion comments.

## [7.4.2] - 2026-04-25

### Fixed

- `scripts/eval-research.sh validate_eval_set()` now rejects entries whose id does not match `^[a-z0-9-]+$` (lowercase letters, digits, and hyphens only) and tracks duplicate ids across the eval set, so duplicates and path-like ids fail fast under `--smoke-test` before `run_one_research()` uses the raw id as `$WORK_DIR/$id` (closes #442). The duplicate-detection `case` is gated on format-validity so glob metacharacters (`*`, `?`, `[`) in a malformed id cannot leak into the case pattern. The structural lint harness `scripts/test-eval-set-structure.sh` gains a Check 5b mirroring the same rule via a single awk pass over `### eval-N: <id>` headings, so duplicate / path-like ids are also rejected at `make lint` time. Sibling contracts updated in lockstep per AGENTS.md: `scripts/eval-research.md` authoring section adds the id rule; `scripts/test-eval-set-structure.md` adds the 5b assertion.

## [7.4.1] - 2026-04-25

### Fixed

- `/research` Deep mode's Step 1.4 collection block now passes `--substantive-validation` to `collect-reviewer-results.sh`, matching Standard mode (closes #446). Previously the `### Deep (RESEARCH_SCALE=deep)` block at `skills/research/references/research-phase.md` invoked the collector without the flag while the `### Standard` block had it, so external lanes that returned thin or uncited prose received `STATUS=OK` (instead of `STATUS=NOT_SUBSTANTIVE`) and slipped silently into synthesis. The runtime-fallback prose in the same Deep block now lists `NOT_SUBSTANTIVE` alongside `STATUS != OK` as a trigger for tool-flag flipping, mirroring Standard. `scripts/test-research-structure.sh` Check 16 was tightened in the same PR: a single whole-file grep had been masking the omission because Standard's flag presence satisfied it. The check now narrows extraction to the `## 1.4 — Wait and Validate Research Outputs` window first, then runs separate awk-scoped greps for the per-scale `### Standard` and `### Deep` collection subsections (terminating at the next `^###`) so neither the Step 1.3 launch sections nor a Standard ↔ Deep substitution can satisfy the pin. Both per-section greps anchor on the literal bash-invocation prefix `${CLAUDE_PLUGIN_ROOT}/scripts/` so prose paragraphs that mention both `collect-reviewer-results.sh` and `--substantive-validation` on the same line cannot satisfy the assertion. The sibling contract at `scripts/test-research-structure.md` was updated in lockstep to describe the new shape of Check 16. Validation-phase.md's single (scale-agnostic) collection block keeps the whole-file pin, reusing the same invocation-anchored pattern. Closes #446.

## [7.4.0] - 2026-04-25

### Added

- `/research --plan` flag enables an optional planner pre-pass before the lane fan-out (closes #420). When `--plan` is set with `--scale=standard` (the default), a single Claude Agent subagent decomposes `RESEARCH_QUESTION` into 2–4 focused subquestions before the 3 lanes launch; each lane researches its assigned subquestion(s) (deterministic assignment by lane order: N=2 union, N=3 one-each, N=4 lane #1 gets two and lanes #2/#3 each get one); synthesis is organized by subquestion sub-section + a final `### Cross-cutting findings` sub-section. Two-step planner dance: orchestrator (`skills/research/references/research-phase.md` Step 1.1) invokes the Agent subagent (no `subagent_type`, since the `code-reviewer` archetype's dual-list output shape conflicts with the planner's prose-list output) and captures raw output to `$RESEARCH_TMPDIR/planner-raw.txt`; new helper `skills/research/scripts/run-research-planner.sh` validates count `2 ≤ N ≤ 4`, applies a question-shape heuristic (each retained line must end with `?` — fail-closed against prose preambles like "Here are the subquestions:"), strips bullet prefixes and control characters, and persists `subquestions.txt`. Falls back cleanly to single-question mode on any planner failure (count out of range, empty output, prose-only reply) with a visible `**⚠ ...**` warning. New Step 1.2 (lane-assignment) computes per-lane subquestions and persists `$RESEARCH_TMPDIR/lane-assignments.txt` (`LANE<k>_SUBQUESTIONS=<subq1>||<subq2>` lines, quoted heredoc) so Step 1.4's runtime-timeout fallback rehydrates the per-lane prompt for any replacement subagent. Per-lane suffix wraps subquestion text in `<reviewer_subquestions>` tags with a "treat as data" instruction to harden against prompt-injection (mirrors the reviewer archetype convention). `--plan` is incompatible with `--scale=quick` (single lane → no decomposition benefit) and `--scale=deep` (deep mode's 4 named angle prompts already differentiate per-lane focus; combining is documented as future work) — both incompatible combinations downgrade `--plan` to off with a visible warning at the start of Step 1. Step renumbering in `research-phase.md`: new 1.1 (planner pre-pass) and 1.2 (lane assignment) inserted before former 1.2; existing 1.2/1.3/1.4 shifted to 1.3/1.4/1.5. Cross-references in `SKILL.md` (`(phases 1.2, 1.3, 1.4)` → `(phases 1.1 through 1.5)`), `validation-phase.md` (Step 1.3 → 1.4, Step 1.4 → 1.5), and inline references updated. New `skills/research/scripts/test-run-research-planner.sh` (22-case offline regression harness wired into `make lint` via `test-harnesses` target); `SECURITY.md` updated with planner-subagent residual-risk subsection. `docs/skills.md`, `README.md`, `docs/workflow-lifecycle.md` (skill docs + flags table) updated; the same flags-table edit also adds the `--adjudicate` row that was previously missing. Closes #420.

## [7.3.4] - 2026-04-25

### Removed

- `/design` Step 3a "Post-Review Confirmation" and all machinery whose sole consumer was that gate. The conditional second approval pause (gated on `qa_happened` from a `$DESIGN_TMPDIR/user-qa-happened.md` sentinel touched by Steps 1c/1d/3.5, OR `dialectic_adjudicated` from a `grep -qE '^\*\*Disposition\*\*:[[:space:]]+(voted|fallback-to-synthesis)[[:space:]]*$'` over `dialectic-resolutions.md`) is gone — once ambiguity-resolution Q/A in Steps 1c/1d/3.5 completes, the run proceeds straight to Step 3b (Architecture Diagram). Steps 1c/1d/3.5 ambiguity-resolution Q/A is preserved unchanged. The `--auto` flag is retained because it still suppresses 1c/1d/3.5. User-visible flow change: every `auto_mode=true` exit from Step 3 ("all reviewers OK") and Step 3.5 ("skipped" or short-circuit) that previously routed to Step 3a now routes directly to Step 3b. `skills/design/SKILL.md` drops the `| 3a | confirmation |` Step Name Registry row, narrows the `--auto` flag-table description to "(1c, 1d, 3.5)", redirects both Step 3 and Step 3.5 auto-mode branches to Step 3b, and deletes the entire `## Step 3a — Post-Review Confirmation` section. `skills/design/references/discussion-rounds.md` rewrites its Consumer/Contract/When-to-load/Binding-convention header for three bodies (1c/1d/3.5), removes the `1c/1d/3.5/3a` inline literal from When-to-load, deletes all three `### Sentinel — record that Q/A occurred` subsections (1c/1d/3.5), redirects the Step 3.5 short-circuit to Step 3b, and deletes the Step 3a body section. `skills/design/references/plan-review.md` drops `3a` from Do-NOT-load and redirects both `auto_mode=true` exit branches (lines 70, 100) to Step 3b. `skills/design/references/flags.md` narrows the `--auto` description. `skills/design/references/sketch-prompts.md` and `skills/design/references/sketch-launch.md` drop `3a` from their Do-NOT-load enumerations. No script or test-harness changes (`scripts/test-design-structure.sh` does not pin Step-3a content; CI's `.github/workflows/ci.yaml` focus-area enum lives in plan-review prompts and is untouched). A follow-up issue tracks adding `test-design-structure.sh` structural pins against accidental Step 3a reintroduction (filed as #453, not blocking). Closes #439.

## [7.3.3] - 2026-04-25

### Fixed

- `/research`'s validation-phase render-failure path now rewrites `lane-status.txt` so Step 3's final report cannot show a native pass for a lane that actually ran as a Claude fallback (closes #435). Previously, when `scripts/render-reviewer-prompt.sh` exited non-zero for a Cursor or Codex validation lane, `skills/research/references/validation-phase.md`'s "On non-zero exit" handlers flipped `cursor_available` / `codex_available` to `false` and launched a Claude Code Reviewer subagent fallback, but the `VALIDATION_<TOOL>_STATUS` keys in `$RESEARCH_TMPDIR/lane-status.txt` were never rewritten — so Step 3's `VALIDATION_HEADER` could render `Cursor: ✅` / `Codex: ✅` for a lane composed entirely of Claude output. Both render-failure handlers (Cursor ~line 77, Codex ~line 121) now surgically rewrite the `VALIDATION_*` slice (token: `fallback_runtime_failed`, sanitized REASON; collapse whitespace, strip `=` and `|`, trim, truncate to 80 chars) BEFORE launching the fallback so an abort after spawn still leaves Step 3 attribution honest, using the same quoted-heredoc / `mktemp` / atomic-`mv` pattern already established at Step 2 entry and Step 2.4. Step 2.4's "no update needed" comment is clarified to enumerate the new third path producing already-correct `VALIDATION_*` keys. Sibling contracts updated in lockstep: `scripts/render-lane-status.md` Consumers + Edit-in-sync rules now enumerate the render-failure-path rewrite as a third write site; `scripts/render-reviewer-prompt.md`'s Caller pattern note documents the lane-status rewrite as the first step on the non-zero-exit branch; `skills/research/SKILL.md` Step 0b extends its lane-status write-site enumeration. `scripts/test-render-reviewer-prompt.sh` gains two structural assertions (`VALIDATION_CURSOR_STATUS=fallback_runtime_failed` and `VALIDATION_CODEX_STATUS=fallback_runtime_failed`) so a future edit cannot silently remove the rewrite blocks. No new test harness needed — `scripts/test-render-lane-status.sh` already exercises the `fallback_runtime_failed` token. Closes #435.

## [7.3.2] - 2026-04-24

### Changed

- `/fix-issue` defers session setup until after `fetch-eligible-issue.sh` finds an eligible issue (issue #437). Previously Step 0 (setup) created a tmpdir, derived `REPO` via `gh repo view`, checked Slack config, and wrote `session-env.sh` unconditionally; when the subsequent fetch returned no eligible issue (the common cron-style invocation outcome), all of that work was wasted. Step 0 is now `Fetch Eligible Issue` and Step 1 is `Setup`; on `fetch-eligible-issue.sh` exit 1 / 2+, the skill skips directly to Step 9 with `FIX_ISSUE_TMPDIR` unset. Step 1 sets `FIX_ISSUE_TMPDIR=$SESSION_TMPDIR` immediately after parsing — before any abort branch — so a post-mktemp setup failure (e.g., `REPO_UNAVAILABLE=true`) still cleans up. Step 9 cleanup is now gated on `FIX_ISSUE_TMPDIR` being non-empty; the no-tmpdir path emits `⏭️ 9: cleanup — skipped (no temp dir created)` and proceeds to the standard completion breadcrumb. In-body breadcrumb literals in the new Step 0 fetch body renamed from `1: fetch issue` → `0: fetch issue` to match the swapped Step Name Registry. Cross-reference touch-ups: anti-pattern #1, positional-argument flag prose, Step 4 'Do NOT load' gate, Known Limitations blocked-by line, plus `skills/shared/subskill-invocation.md` and `skills/fix-issue/references/triage-classification.md`. Test-harness pins (`### 6a`, `## Step 7`, `Skip to Step 9`) unaffected — `test-fix-issue-bail-detection.sh` still passes 6/6 assertions. A follow-up `fetch → lock → setup` reorder (raised by Codex during plan review) was filed as a separate issue rather than expanded into this PR's scope.

## [7.3.1] - 2026-04-25

### Fixed

- `/implement`'s tracking-issue anchor comment no longer renders as visually empty in GitHub's UI when first planted (issue #431). Previously, Step 0.5's seed body was the first-line `<!-- larch:implement-anchor v1 issue=N -->` marker plus 8 `<!-- section:slug -->`/`<!-- section-end:slug -->` pairs with empty interiors — entirely HTML comments, which GitHub renders invisible. `scripts/assemble-anchor.sh` now runs an "all-empty" pre-pass over `SECTION_MARKERS` using the lenient predicate `grep -q '[^[:space:]]'` (a fragment is "empty" iff absent OR zero-byte OR whitespace-only); when every fragment is empty, the assembled body carries one extra italic-markdown placeholder line (`_/implement run in progress — sections below populate as the run proceeds._`) between the first-line marker and the first section open marker. As soon as any fragment has non-whitespace content, the placeholder is suppressed and the populated-anchor body is byte-for-byte unchanged from pre-fix output, so progressive upserts at Steps 1/2/5/7a/8/9a.1/11 and downstream parsers (truncation, hydration awk) are unaffected. The lenient-vs-strict predicate choice was resolved via dialectic adjudication (2-1) and confirmed by user in design discussion round 2. `scripts/test-assemble-anchor.sh` extended from 10 to 14 assertion categories — (a) bumped to 18 lines with a line-2 placeholder-literal assertion, plus new `(a2)` (placeholder-presence regression for empty-sections), `(a3)` (partial-fragment suppression), `(a4)` (lenient-predicate validation against whitespace-only fragments), and `(a5)` (nonexistent `--sections-dir` still fires the placeholder). New integration assertion `(k)` in `scripts/test-tracking-issue-write.sh` pins that the placeholder line survives the `upsert-anchor` redact + truncate pipeline verbatim and on its own line (line 2 of the captured outbound body, between the first-line anchor marker and the first `<!-- section:... -->` open marker). Sibling contracts updated in lockstep: `scripts/assemble-anchor.md` ("Seed-only visible placeholder" subsection + assertion catalog refreshed), `scripts/test-assemble-anchor.md` (assertion-table additions), `scripts/test-tracking-issue-write.md` (table extended to (a)-(k)), and `skills/implement/references/anchor-comment-template.md` (new "Seed-only visible placeholder line" subsection). `skills/implement/SKILL.md` Branch 2 (~line 271) and Branch 4 step 5 (~line 371) seed-anchor prose updated to mention the placeholder. Closes #431.

## [7.3.0] - 2026-04-24

### Added

- `/research --adjudicate` boolean flag (default off) runs an additional 3-judge dialectic adjudication step (Step 2.5) over reviewer findings the orchestrator REJECTED during validation merge/dedup, with reinstated findings folded into the validated synthesis before Step 3 renders. THESIS = "rejection stands"; ANTI_THESIS = "reinstate the reviewer's finding"; majority binds; ties fall back to rejection-stands. The 3-judge panel (1 Claude code-reviewer subagent + 1 Codex + 1 Cursor) uses the dialectic-protocol.md replacement-first pattern when externals are unhealthy at fresh re-probe time. Skips the `/design`-style adversarial debate fanout — both sides exist at merge time (orchestrator rejection rationale + reviewer's original finding), so the ballot builder reads them directly. Lands as a new third reference `skills/research/references/adjudication-phase.md` (3-reference progressive-disclosure topology, replacing the prior 2-reference layout); `scripts/test-research-structure.sh` rewritten to validate 3 references with reciprocal Do-NOT-load guards across all three on the same MANDATORY line, and extended from 17 to 18 structural assertions. Capture sites A and B in `skills/research/references/validation-phase.md` persist `(finding, rejection_rationale)` records to `$RESEARCH_TMPDIR/rejected-findings.md` unconditionally regardless of the flag — tmpdir-only, wiped at Step 4 cleanup. New `scripts/run-research-adjudication.sh` (pre-launch coordinator: empty-check + ballot-build + judge re-probe in one Bash call per `skill-design-principles.md` III.B/C) and `scripts/build-research-adjudication-ballot.sh` (deterministic ballot composer: sort by `(reviewer_attribution, sha256(finding_text))`, position rotation, anchored-only attribution stripping, FS/GS sentinel encoding for multi-line + tab-safe TSV). New `scripts/test-research-adjudication.sh` offline harness with 9 assertions (deterministic ordering, DECISION renumbering, position rotation, anchored attribution stripping with mid-content preservation, `<defense_content>` wrapping, multi-line round-trip, literal-tab round-trip). `skills/shared/dialectic-protocol.md` overview annex declares the protocol now serves both `/design` Step 2a.5 (decision adjudication) and `/research --adjudicate` (rejection adjudication) with token names unchanged. `SECURITY.md` adds residual-risk note for the `<defense_content>` wrapper inheriting the same prompt-injection caveat as `/design`'s existing dialectic ballot. `docs/voting-process.md`, `skills/shared/external-reviewers.md`, `README.md`, and `docs/skills.md` updated. Composes cleanly with `--scale=quick` (Step 2 skipped → no rejections → Step 2.5 short-circuits). Closes #424.

## [7.2.1] - 2026-04-24

### Added

- Substantive-content validator for `/research` outputs (Phase 3 of umbrella #413, closes #416). New `scripts/validate-research-output.sh` is a POSIX-shell filter that exits 0 when its file argument has at least N words of body text (default `--min-words 200`, fenced-code-block interiors excluded) AND (under `--require-citations`, the default) at least one provenance marker — file or `file:line` regex with extensions `{md, sh, py, ts, js, json, yaml, yml, toml, txt, sql, go, rs}` (extended to permit leading `.` for hidden files), extensionless `Makefile`/`Dockerfile`/`GNUmakefile`, fenced code block with ≥1 non-blank line, or URL — and exits non-zero with a one-line stdout diagnostic otherwise. A new `--validation-mode` preset accepts the literal `NO_ISSUES_FOUND` token (the explicit no-findings signal emitted by `scripts/render-reviewer-prompt.sh`) and lowers the default word-count floor to 30, tuned for `/research` Step 2.4 validation-phase outputs whose shape is short numbered findings rather than 2-3 paragraph prose. `scripts/collect-reviewer-results.sh` gains a default-OFF `--substantive-validation` flag that, after the existing non-empty + retry path settles, invokes the validator on each `STATUS=OK` entry and rewrites the result to `STATUS=NOT_SUBSTANTIVE | HEALTHY=false | FAILURE_REASON=<sanitized diagnostic>`, calling `set_tool_unhealthy` to preserve per-tool health monotonicity. Default-OFF preserves byte-identical behavior for `/loop-review`, `/review`, `/design`, `/implement`, and any other current callers; only `/research` opts in. `/research` enables the validator at both Step 1.3 (research collection) and Step 2.4 (validation collection, with `--validation-mode`). `skills/shared/external-reviewers.md` adds `STATUS=NOT_SUBSTANTIVE` to the Runtime Timeout Fallback trigger list (same Claude-subagent-fallback behavior as a timeout) and to the documented STATUS enum. `scripts/render-lane-status.md` documents the collector STATUS-to-render-token mapping (`NOT_SUBSTANTIVE` folds into the existing `fallback_runtime_failed` token; `FAILURE_REASON` carries operator-facing distinction). New regression test `scripts/test-validate-research-output.sh` covers 24 cases (happy path, empty file, short-but-cited, long-but-uncited, adversarial zero-citations, file:line / Makefile / fenced-code / URL / leading-dot citations, fence-stripping body word count, error paths, and the seven `--validation-mode` cases including `NO_ISSUES_FOUND` short-circuit and explicit `--min-words` override). Wired into `make test-harnesses` via the new `test-validate-research-output` Makefile target; harness excluded from agent-lint as Makefile-only. `scripts/test-research-structure.sh` extended with two new structural pins (checks 16 + 17) asserting `--substantive-validation` appears in both `/research` collector invocations and `STATUS=NOT_SUBSTANTIVE` is mapped in the lane-status update bullets. Sibling contract `scripts/validate-research-output.md`. `docs/linting.md` Makefile Targets table documents the new gate. Closes #416 under umbrella #413.

## [7.2.0] - 2026-04-24

### Added

- `/research --scale=quick|standard|deep` value flag (default `standard`, byte-equivalent to pre-#418 behavior) adapts the lane count to question complexity. `quick` runs 1 inline Claude lane and skips Step 2 validation entirely (single-lane confidence — fastest, lowest assurance; the synthesis carries an explicit single-lane disclaimer). `standard` runs the existing 3 research agents + 3-reviewer validation panel. `deep` runs 5 research lanes (Claude inline running baseline `RESEARCH_PROMPT` + 2 Cursor and 2 Codex slots carrying four diversified angle prompts `RESEARCH_PROMPT_ARCH` / `RESEARCH_PROMPT_EDGE` / `RESEARCH_PROMPT_EXT` / `RESEARCH_PROMPT_SEC`) and a 5-reviewer validation panel (the standard 3 plus 2 extra Claude code-reviewer subagents `Code-Sec` / `Code-Arch` carrying lane-local emphasis on the unified Code Reviewer archetype — NOT new agent slugs; both reuse the existing `<reviewer_research_question>` / `<reviewer_research_findings>` XML wrappers as defense-in-depth against prompt injection). `skills/research/SKILL.md` adds a value-flag class distinct from boolean flags, gates Step 2 with a `RESEARCH_SCALE=quick` skip emitted before the MANDATORY directive (preserving Check 3 of `test-research-structure.sh`), makes Step 1 / Step 2 completion breadcrumbs and Step 3 report counts dynamic, and branches Step 3 header rendering per scale (standard uses `render-lane-status.sh`; quick / deep emit literal headers). `skills/research/references/research-phase.md` and `skills/research/references/validation-phase.md` gain explicit `### Standard` (byte-stable) / `### Quick` / `### Deep` subsections; `### Standard` is byte-drift-guarded by new harness assertions on the existing `cursor-research-output.txt` / `codex-research-output.txt` / `cursor-validation-output.txt` / `codex-validation-output.txt` filename literals. `scripts/test-research-structure.sh` extended from 8 to 15 assertions (the four `RESEARCH_PROMPT_*` identifiers, the literal quick-mode skip breadcrumb, abort-on-invalid `--scale=foo`, flag order-independence, and the Standard byte-drift pins). Doc sweep: README, `docs/skills.md`, `docs/agents.md`, `docs/review-agents.md`, `docs/external-reviewers.md`, `docs/workflow-lifecycle.md`, `SECURITY.md` (explicit lower-assurance note for `--scale=quick`), `skills/research/diagram.svg` (scale-aware primary box labels), and `skills/shared/progress-reporting.md` (scale-conditional table examples). Closes #418.

## [7.1.0] - 2026-04-24

### Added

- `/loop-review` overhauled with inversion-of-control: `skills/loop-review/SKILL.md` is now a thin (~80-line) delegator (`allowed-tools: Bash, Monitor`) that background-launches the new bash driver at `skills/loop-review/scripts/driver.sh` and attaches Monitor to its log file. The driver invokes `claude -p` once with a partitioning prompt to enumerate 1–20 verbal slice descriptions (replacing the prior `.claude/loop-review-partitions.json` + auto-discovery), then loops invoking `claude -p /review --slice-file <path> --create-issues --label loop-review --security-output <path>` once per slice. Each per-slice `/review` runs the standard 3-reviewer panel under the Voting Protocol; accepted findings (in-scope-accepted AND OOS-accepted, 2+ YES) are filed inline via `/issue`. Halt class eliminated by construction. `/review` gains 5 new flags: `--slice <text>` / `--slice-file <path>` (mutually exclusive; activate slice mode), `--create-issues` (post-vote inline /issue call; requires slice mode), `--label <label>` (forwarded to /issue), `--security-output <path>` (where to write security-tagged findings; defaults to `$REVIEW_TMPDIR/security-findings.md`). Slice mode emits a `### slice-result` KV footer (mirrors `### iteration-result` from `improve-skill/iteration.sh`) for driver consumption. `/review`'s default behavior (no slice flag) is unchanged. New sibling contract `skills/loop-review/scripts/driver.md`. New regression harnesses `scripts/test-loop-review-driver.sh` and `scripts/test-loop-review-skill-md.sh` with sibling `.md` contracts, modeled on the loop-improve-skill pair and wired into `make lint`. `/loop-review` reclassified ORCHESTRATOR → DELEGATOR in `scripts/test-anti-halt-banners.sh` and `skills/shared/subskill-invocation.md`. `SECURITY.md` adds `/loop-review subprocess invocation` section documenting the bash-driver topology, `LOOP_TMPDIR` security boundary, driver log file retention pattern, and `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` test-only env var. Removed legacy `/loop-review` behaviors: sub-slicing >50 files, batched `/issue` flushes across slices, Negotiation Protocol, JSON partition config, auto-discovery — documented as intentional removals in `driver.md`. `skills/loop-review/scripts/init-session-files.sh` deleted. Docs updates to `docs/workflow-lifecycle.md` and `docs/review-agents.md`. Closes #423.

## [7.0.13] - 2026-04-24

### Added

- `/research` evaluation set + harness for measuring prompt-side improvements to `/research`. New `skills/research/references/eval-set.md` (frozen catalog of 20 questions across 5 categories — `lookup`, `architecture`, `external-comparison`, `risk-assessment`, `feasibility` — with 2 entries flagged adversarial: one fictitious-mechanism, one data-absence, to test over-claiming). New `scripts/eval-research.sh` (opt-in operator harness — runs each entry through `/research` as a fresh `claude -p --plugin-dir` subprocess matching the `iteration.sh` pattern; scores each output along deterministic axes — file:line + repo-path + URL provenance counters, case-insensitive substring keyword-coverage, length — plus a fail-closed LLM-as-judge rubric heredoc with required-field parser; `--smoke-test` for offline schema validation; `--baseline <ref>` regex-validated against shell injection). New `skills/research/references/eval-baseline.json` (committed schema-only stub; operator populates via `--write-baseline` after merge). New `scripts/test-eval-set-structure.sh` (offline structural regression — entry count, category coverage, schema validity, ≥2 adversarial entries with both fictitious and data-absence shapes, baseline JSON shape, harness self-test invocation). Both new scripts plus their sibling `.md` contracts (per AGENTS.md). `Makefile` adds `eval-research` and `test-eval-set-structure` standalone targets to `.PHONY` (NEITHER is a `test-harnesses` prerequisite — explicit "not a CI gate" carve-out, mirroring the `halt-rate-probe` pattern). `agent-lint.toml` excludes both new scripts (Makefile-only references). `docs/linting.md` documents both targets in the opt-in operator-tools table. Source: Anthropic's *How we built our multi-agent research system* — small-sample (~20-case) rubric-based LLM-as-judge evaluation as the substrate for prompt-side iteration. Closes #419 under umbrella #413.

## [7.0.12] - 2026-04-24

### Changed

- `/implement` Step 0.5 Branch 2 (`--issue` adoption, used by `/fix-issue` forwarding `--issue $ISSUE_NUMBER`), Branch 3 (PR-body recovery), and Branch 1 (sentinel-reuse resume safety net) now rename the adopted tracking issue's title to `[IN PROGRESS]` so the title-prefix lifecycle applies uniformly across fresh-created and adopted runs. Step 12a/12b (terminal `[DONE]`) and Step 18 (terminal `[STALLED]`) drop the `ADOPTED=false` guard so adopted issues also flip on completion / failure. The `ADOPTED=` sentinel field retains its created-vs-adopted metadata semantic but no longer gates the title prefix. `scripts/tracking-issue-write.md` updated to clarify the cross-skill policy (`/improve-skill` / `/loop-improve-skill` use a narrower lifecycle than `/implement`) and to extend the Step 18 summary to include Branch B (`[DONE]` on non-merge / draft completion). `skills/fix-issue/SKILL.md` Step 6a generic-failure message and a new "Title-prefix interaction on adopted-issue retry" Known Limitations entry document the manual-recovery flow — operators must clear the `[STALLED]` prefix before re-running `/fix-issue` against the same adopted issue. Closes #430.

## [7.0.11] - 2026-04-24

### Changed

- `skills/research/SKILL.md` Step 3 final-report header now distinguishes WHY each external lane fell back to a Claude subagent instead of collapsing to ✅/❌. Five canonical states render: `✅` (ran natively), `Claude-fallback (binary missing)`, `Claude-fallback (probe failed: <reason>)`, `Claude-fallback (runtime timeout)`, and `Claude-fallback (runtime failed: <reason>)`. Pre-launch state from `session-setup.sh --check-reviewers` (`*_AVAILABLE`/`*_HEALTHY`/`*_PROBE_ERROR`) and runtime state from `collect-reviewer-results.sh` (`STATUS`/`FAILURE_REASON`) accumulate into `$RESEARCH_TMPDIR/lane-status.txt` via surgical phase-local rewrites at Step 0b (init), Step 1.3 (research runtime), Step 2 entry (propagate research-phase fallbacks to validation lanes), and Step 2.4 (validation runtime). New `scripts/render-lane-status.sh` (with sibling `.md` contract and 10-fixture regression harness wired into `make lint`) parses the KV file at Step 3 and emits the rendered header lines; the Code (Claude code-reviewer subagent) lane is hard-coded `✅` (no fallback path). KV writes use quoted heredocs (`<<'EOF'`) to neutralize shell-injection vectors in untrusted probe-error text. `scripts/test-research-structure.sh` extended with two new structural pins (Step 3 references `render-lane-status.sh`; both phase references mention `lane-status.txt`). Closes #421.

## [7.0.10] - 2026-04-24

### Changed

- `skills/research/references/validation-phase.md`: Cursor and Codex external-reviewer lanes now render the unified Code Reviewer archetype from `skills/shared/reviewer-templates.md` via the new `scripts/render-reviewer-prompt.sh`, so all 3 lanes (Claude always-on + Cursor + Codex) walk the same five focus areas (code-quality / risk-integration / correctness / architecture / security) with XML-wrapped untrusted-context (`<reviewer_research_question>` + `<reviewer_research_findings>`) for prompt-injection hardening. Lanes use a foreground-render → background-launch pattern so render failure escalates synchronously to a Claude Code Reviewer subagent fallback (preserves the 3-lane invariant) rather than blocking on a missing `.done` sentinel. The helper applies a research-validation sentinel-override (`No in-scope issues found.` → `NO_ISSUES_FOUND`) and a section-keyed `{OUTPUT_INSTRUCTION}` expansion that instructs models to leave the OOS section empty for research validation — preserving `/research`'s negotiation-pipeline single-list contract. Adds `scripts/render-reviewer-prompt.{sh,md}` (sibling contract per AGENTS.md) and `scripts/test-render-reviewer-prompt.{sh,md}` (18 assertions: happy + 5 negative + 3 regression + 1 lane-specific integration). Updates `docs/review-agents.md` to retire the documented Codex/Cursor 4-perspectives asymmetry. Wires the new harness into `Makefile` `test-harnesses` and excludes it from `agent-lint.toml` G004/dead-script (Makefile-only invocation pattern, mirroring `test-research-structure.sh` siblings). `scripts/test-research-structure.sh` runs unchanged — Check 6 stays green via the unchanged Claude variable-binding section. Closes #417.

## [7.0.9] - 2026-04-24

### Changed

- Tighten `/research` safety claims to accurately partition mechanically-enforced (PreToolUse hook on `Edit|Write|NotebookEdit`, `/tmp`-only) vs prompt-enforced (Cursor/Codex external reviewers with `--workspace "$PWD"` / `-C "$PWD"`, Claude's own `Bash`, and Agent-tool fallbacks) perimeter. Replaces the dense "Read-only-repo contract" paragraph in `skills/research/SKILL.md` with a structured two-tier statement; promotes the externals + Bash write-surface content out of the long "External tool delegation" paragraph in `SECURITY.md` into a dedicated subsection ("External reviewer write surface in /research and /loop-review") with sub-bullets distinguishing `/research`'s hook-bounded orchestrator from `/loop-review`'s unconstrained write-capable surface; cross-links from `README.md`, `docs/review-agents.md`, `docs/external-reviewers.md`, `docs/skills.md`, and `docs/workflow-lifecycle.md` so the partition vocabulary stays consistent. Documentation-and-claims accuracy fix; no script or hook changes. Closes #422.

## [7.0.8] - 2026-04-24

### Changed

- `skills/research/references/research-phase.md`: Step 1.2 now carries an external-evidence trigger detector and a conditional `RESEARCH_PROMPT` branch (Phase 2 of umbrella #413). When `RESEARCH_QUESTION` matches a documented case-insensitive keyword list (`external`, `other repos`, `github`, `compare with`, `contrast`, `reputable sources`, `karpathy`, `anthropic`, `open source`, `oss`, `large amount of stars`, `high stars`, `star count`), `external_evidence_mode` flips to `true` and the prompt prepends an external-evidence stanza inviting `WebSearch` / `WebFetch` against reputable origins (vendor docs, well-known engineer blogs, high-star GitHub repos), with URL provenance required for every external claim. The 3-lane invariant holds at the prompt-text level; a residual asymmetry note documents that Cursor's `cursor agent` runtime does not expose web tools the way Claude does, so external-evidence yield is realized primarily through Codex + Claude-inline. SKILL.md Step 1 entry blurb updated to match. Closes #415.

## [7.0.7] - 2026-04-24

### Changed

- `skills/research/references/research-phase.md`: shared `RESEARCH_PROMPT` literal now mandates a provenance schema (Phase 1 of umbrella #413). Added clause (4) requiring every concrete claim to carry one of `file:line` / `file:line-range`, a fenced command + output snippet, or a URL; tightened the existing "Explore the codebase to ground your findings" sentence to point at clause (4). Phase 1 is schema-only — no validator change yet (Phase 3, #416). Closes #414.

## [7.0.6] - 2026-04-24

### Fixed

- `skills/fix-issue/scripts/fetch-eligible-issue.sh` explicit-issue path now emits a lock-specific error (`Issue #N is locked by another /fix-issue run (last comment: IN PROGRESS)`) when the requested issue's last comment is `IN PROGRESS`, instead of the misleading `not approved` framing. Mirrors the auto-pick path's existing `IN PROGRESS` skip; behavior is unchanged (already rejected via the GO check), only the message clarity improves. Closes #410.

## [7.0.5] - 2026-04-24

### Added

- Tracking-issue title-prefix lifecycle: `/implement`, `/improve-skill`, and `/loop-improve-skill` now create their tracking issues with `[IN PROGRESS]` in the title, rename to `[DONE]` on successful completion (right before merge for `/implement`; pre-closeout for `/loop-improve-skill`; both success exits for `/improve-skill`), and rename to `[STALLED]` on bail / failure paths. `/fix-issue` excludes issues whose titles start with any managed prefix from both auto-pick and explicit-issue selection, so tracking issues never appear as fix-issue candidates. New `tracking-issue-write.sh rename --issue N --state in-progress|done|stalled` subcommand is the single idempotent mutator (strip-exactly-one-then-prepend, redact parity with `create-issue`, char-oriented 256 truncation). Bash drivers (`iteration.sh`, `driver.sh`) install an EXIT trap with footer-first ordering so the KV footer contract is preserved even when the best-effort stall rename fails.

## [7.0.4] - 2026-04-24

### Changed

- `/issue` batch-mode `parse-input.sh` no longer emits long opaque base64-encoded `ITEM_<i>_BODY` lines on stdout — those strings were tripping Anthropic's Usage Policy classifier when the SKILL's Bash tool result entered the main agent's post-tool-use context. The script now requires `--output-dir DIR` and writes each item's body as plain text to `$OUTPUT_DIR/item-<i>-body.txt`; stdout carries `ITEM_<i>_BODY_FILE=<absolute-path>` in place of the former base64 line. No backwards-compatibility shim. Closes #402.
- `skills/issue/SKILL.md`: `$ISSUE_TMPDIR` creation moves from Step 4 to the top of Step 3 so both single and batch modes share one session tmpdir for bodies + Step 5 candidates + Step 6 OOS template wrap. Step 3 batch mode passes `--output-dir "$ISSUE_TMPDIR/bodies"` and mandatorily checks parser exit status, running `rm -rf "$ISSUE_TMPDIR"` on the abort path. Step 5 Phase 2 adds an explicit `cat "$ITEM_<i>_BODY_FILE"` preamble for non-malformed items so the LLM has body content for `<new_item_<i>>` dedup corpus. Step 6 CREATE passes `--body-file "$ITEM_<i>_BODY_FILE"` directly for generic items; OOS items `cat` the raw body file and compose the template wrap into `$ISSUE_TMPDIR/oos-body-<i>.txt`.
- `skills/issue/scripts/test-parse-input.sh`: `b64_decode` / `get_body` helpers replaced by `get_body_file_contents` (reads the file at `ITEM_<i>_BODY_FILE`); every `run_parser` call passes a per-case `--output-dir` so cases cannot stomp each other's body files. New regression guard inside `run_parser` greps stdout for `^ITEM_[0-9]+_BODY=` (extended regex) and aborts the suite on match — pins the "no base64 on stdout" invariant at the test layer. Two new negative tests: missing `--output-dir` must fail fast with usage error; unwritable `--output-dir` must fail under `set -euo pipefail`. 136/136 assertions pass.
- `skills/issue/scripts/parse-input.md`: contract doc expanded to describe file-based body emission, the required `--output-dir` flag, the non-zero-exit "ignore partial stdout" rule, and the test-layer regression guard.

## [7.0.3] - 2026-04-24

### Changed

- `/design` Step 3a — Post-Review Confirmation now fires only when `auto_mode=false` AND (`qa_happened` OR `dialectic_adjudicated`), replacing the prior `plan was revised` gate. `qa_happened` is recorded by Steps 1c/1d/3.5 via a `$DESIGN_TMPDIR/user-qa-happened.md` sentinel touched whenever an `AskUserQuestion` actually asks the user at least one question; `dialectic_adjudicated` is detected by grepping `$DESIGN_TMPDIR/dialectic-resolutions.md` for `**Disposition**: voted` or `**Disposition**: fallback-to-synthesis` lines (`bucket-skipped` / `over-cap` dispositions do not count — no adjudication occurred there). Reviewer-only plan revisions without Q/A and without dialectic no longer pause for a second approval; `/implement` proceeds straight to coding when Claude saw no ambiguity and no sketch-phase debate took place.

## [7.0.2] - 2026-04-24

### Changed

- `/loop-improve-skill` and `/improve-skill` retain `$LOOP_TMPDIR` / `$WORK_DIR` on any non-success iteration status (`no_plan`, `design_refusal`, `im_verification_failed`, `judge_failed`, subprocess exit non-zero, KV parse failure, iter-cap without grade-A reclassification) so per-iteration artifacts survive for post-mortem analysis. Cleanup still runs on `grade_a` / `ok`. The driver's close-out comment gains a `## Diagnostics` section with the retained path + a pointer list to the relevant per-iteration files, and the driver always emits `LOOP_TMPDIR=<path>` to stdout at EXIT. Closes #399.
- On any `invoke_claude_p` non-zero rc, both `driver.sh` and `iteration.sh` dump a redacted `── subprocess stderr (label=<label>) ──` banner + full stderr sidecar + last 50 lines of the subprocess stdout (tail sanitized via `sed 's/^### iteration-result/### (banner-redacted)/'` to prevent KV-footer spoofing) to stdout, so both the live Monitor stream and the retained driver log capture the verbatim error. Applied uniformly to judge / design / design-rescue / im / final re-judge subprocess sites plus helper-script failure sites (session-setup parse, standalone `gh issue create`, close-out `gh issue comment`, close-out `redact-secrets.sh`). Iteration-kernel helper-script failures signal cross-boundary retention to the driver via a `$WORK_DIR/preserve.sentinel` file that the driver's `cleanup_on_exit` reads.
- `SECURITY.md` and `skills/improve-skill/scripts/iteration.md` carve out the new post-failure diagnostic dump path in the Stdout discipline / KV-footer discipline sections.
- No `invoke_claude_p` timeout modified per user directive (judge 1200s / design 1800s / design-rescue 1800s / im 3600s / final re-judge 1200s — all ≥20 min).

## [7.0.1] - 2026-04-24

### Changed

- `/loop-improve-skill` and `/improve-skill` now print the tracking-issue URL as the final `✅` breadcrumb so the user gets a clickable link at the end of a run. `driver.sh` emits the URL after the Step 5 close-out comment; `iteration.sh` emits it from the EXIT trap in standalone mode (create OR `--issue <N>` adopt), gated on `OWNS_WORK_DIR=true` and a non-empty `ISSUE_URL`. Loop-mode invocations stay silent so `driver.sh` owns the final URL output.
- `iteration.sh` hydrates `ISSUE_URL` on the standalone `--issue <N>` adopt path via `gh issue view --json url --jq .url`. Graceful degradation: on `gh` failure `ISSUE_URL` stays empty, a warning is logged to stderr, and the EXIT trap's `-n` gate silently falls through.

## [7.0.0] - 2026-04-24

### Changed

- **BREAKING**: Rename `/implement`'s `--slack` flag to `--no-slack` and invert the default. Slack posting is now **on by default** when `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID` are configured; pass `--no-slack` to opt out. The old `--slack` flag is rejected (no deprecation shim — existing aliases that embed `--slack` must be updated).
- **BREAKING**: Remove all PR Slack posting. `/implement` no longer posts about the PR at Step 11 and no longer adds a `:merged:` emoji at Step 13 (both deleted). Replaced with a single **tracking-issue** Slack post at new Step 16a near the end of each run. Message body is a one-liner: `<emoji> <https://github.com/$REPO/issues/$N|Issue #$N> (<title>) — <status>[ — <detail>]`. Emoji: ✅ closed (PR merged and issue auto-closed via `Closes #N`), 📝 PR opened but not merged (`--merge` not set or `--draft`), ❌ blocked (CI failure, merge failure, Step 12d bail for non-user-input reason), ❓ needs user input (auto-mode conflict-resolution bail under `auto_mode=true`). `Issue #N` is a clickable GitHub link. The post identifies as the git user (`git config user.name` → Slack `chat.postMessage` `username` field), matching the identity the deleted PR-announce path used — not as the bot's display name.
- `/fix-issue` drops its own Slack post on the PR path (Step 8a deleted) — the delegated `/implement` run handles the Slack post via its Step 16a. The NON_PR path (Step 8b) still posts directly, now via the new shared `scripts/post-issue-slack.sh` and now gated on `--no-slack` in addition to `slack_available`. `/fix-issue` accepts `--no-slack` and forwards it to `/implement`.
- All downstream skills that forward the flag renamed `--slack` → `--no-slack`: `/alias` (dual-role preserved with the new name), `/simplify-skill`, `/compress-skill`, `/create-skill` (`SLACK=true|false` output key renamed to `NO_SLACK=true|false` in `scripts/parse-args.sh`), `/loop-improve-skill`, `/improve-skill`. Driver scripts updated: `skills/loop-improve-skill/scripts/driver.sh`, `skills/improve-skill/scripts/iteration.sh`.
- `scripts/post-issue-slack.sh` (new, at repo-root `scripts/`): thin composer that accepts `--issue-number --status --repo [--pr-url] [--detail] --token --channel-id`. Fetches issue title and URL via `gh issue view --repo` (scoped to the caller-supplied repo so gh's default-repo context cannot fetch the wrong issue). Falls back to `gh repo view --json url` to derive the GHE-safe host before hardcoding github.com. Escapes mrkdwn-reserved characters in both title and detail. Delegates the API call to `scripts/post-slack-message.sh --username "$(git config user.name)"`. Sibling contract at `scripts/post-issue-slack.md` documents the interface, invariants, and edit-in-sync triggers.
- `/implement` Step 12 now sets `pr_closed=true` on merge success (both Step 12b `MERGE_RESULT in (merged, admin_merged)` and `ACTION=already_merged`) so Step 16a's outcome state machine classifies externally-merged PRs as `closed` instead of `blocked`. Step 12d persists `FINAL_BAIL_REASON` into parent scope so the state machine has the bail reason available as the `--detail` tail.
- `/implement` conflict-resolution procedure Phase 2 sets `BAIL_NEEDS_USER_INPUT=true` when bailing under `auto_mode=true` due to low confidence. Step 16a's state machine checks this flag (not a free-form BAIL_REASON grep) to emit the ❓ emoji.

### Removed

- Scripts deleted as unused after the refactor: `scripts/post-pr-announce.sh`, `scripts/slack-announce.sh`, `scripts/post-merged-emoji.sh`, `scripts/add-merged-emoji.sh`, `scripts/add-slack-emoji.sh`, `scripts/parse-pr-summary.sh`, `skills/fix-issue/scripts/post-issue-slack.sh` (replaced by the repo-root version).
- `LARCH_SLACK_USER_ID` env var and `slack_user_id` userConfig entry removed — they were only used for `@-mentioning` in the deleted PR-announce message. `scripts/session-setup.sh` stops exporting `LARCH_SLACK_USER_ID` from `CLAUDE_PLUGIN_OPTION_SLACK_USER_ID`.

### Added

- `scripts/test-parse-args.sh` (new harness): 19 tests pinning the `skills/create-skill/scripts/parse-args.sh` stdout grammar (new `NO_SLACK` key), flag list, and error-message format. Wired into `make lint` via `Makefile` `test-parse-args` target + `test-harnesses` aggregate. Sibling `scripts/test-parse-args.md` contract.

## [6.3.1] - 2026-04-24

### Changed

- `/fix-issue` skill-judge dimensions D1/D2/D3/D5 raised to grade A via an additive/reorganizing change. Adds a `## Mindset` section (before-processing thinking framework for triage, classification, complexity, and crash-recovery questions), a `## Anti-patterns` section (6 NEVER rules with `**Why:**` + `**How to apply:**` lines distinguishing 4 CI-backed pins enforced by `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` from 2 editorial invariants), and a new `skills/fix-issue/references/` directory with two files — `triage-classification.md` (owns the Step 4 triage + Step 5 classification detail) and `non-pr-execution.md` (owns the Step 6b NON_PR path detail). Each reference carries the CI-mandated Consumer / Contract / When-to-load header triplet with explicit `Do NOT load` guards enforced by `scripts/test-references-headers.sh`. `skills/fix-issue/SKILL.md` Steps 4, 5, and 6b are slimmed to load the references via `MANDATORY — READ ENTIRE FILE` triggers. No behavior change, no script edits. The anti-halt banner, all 3 branch-specific micro-reminders, the Step 6a bail-detection awk window's 6 literals, the Step Name Registry, Known Limitations, frontmatter, and every script contract are preserved byte-for-byte. During review, the Mindset and Step 5 "default to PR" rule was softened across both SKILL.md and the reference to add an explicit carve-out: when the issue text explicitly forbids a PR or mandates research/issues as the deliverable, pick `NON_PR` regardless — `/implement`'s `/review` phase cannot reliably recover a shape-of-work mismatch. The `triage-classification.md` Not-material-closure-flow prose was also corrected from "written into the issue body" to "posted as the closing comment on the issue" to match the actual `issue-lifecycle.sh close --comment` wiring (inherited pre-existing inaccuracy from the original SKILL.md, fixed while the prose was migrating into the reference).

## [6.3.0] - 2026-04-24

### Added

- New `/improve-skill` skill (`skills/improve-skill/SKILL.md` + `scripts/iteration.sh` + `scripts/iteration.md`) runs **one iteration** of the judge → design → im pipeline against an existing larch skill. Standalone invocation creates its own GitHub tracking issue; `--issue <N>` adopts an existing one. The amended `/design` prompt carries a **narrow per-finding pushback carve-out**: `/design` may surface disagreement with specific `/skill-judge` findings via a dedicated `## Pushback on judge findings` subsection with detailed per-finding justification (dimension + excerpt + specific reasoning + `file:line` evidence). The carve-out is strictly per-finding — the existing rules 1-3 (no-minor-self-curtail, no-budget-self-curtail, no-no-plan-sentinel) remain byte-present and in force. SKILL.md ships the same Bash + Monitor live-streaming pattern as `/loop-improve-skill` (with `IMPROVE_SKILL_LOG_FILE` env override, `/tmp/`+`/private/tmp/` validation, `run_in_background` + persistent Monitor tail with the byte-verbatim filter regex).

### Changed

- `/loop-improve-skill`'s driver (`skills/loop-improve-skill/scripts/driver.sh`) shrank from ~780 lines to ~530: the per-iteration body (judge → grade-parse → design → im → verify) was factored out into the shared kernel at `skills/improve-skill/scripts/iteration.sh`, which the driver now invokes once per round via direct bash call (not nested `claude -p`) with `--work-dir $LOOP_TMPDIR --iter-num $ITER --issue $ISSUE_NUM`. Halt class stays eliminated by construction (closes #273). Per-iteration state flows from kernel to driver via a 9-key KV footer on iteration.sh stdout (`### iteration-result` delimited; emitted via EXIT trap so the driver always sees a result even on abnormal abort; keys: `ITER_STATUS`, `EXIT_REASON`, `PARSE_STATUS`, `GRADE_A`, `NON_A_DIMS`, `TOTAL_NUM`, `TOTAL_DEN`, `ITERATION_TMPDIR`, `ISSUE_NUM`). Driver retains a slim `invoke_claude_p_final` helper for the Step 5a post-iter-cap re-judge with FINDING_7/9/10 contracts preserved. KV-parse is scoped to post-`### iteration-result`-header lines so pre-block KEY=VAL diagnostics cannot spoof the parse. `LARCH_ITERATION_SCRIPT_OVERRIDE` env var documented in SECURITY.md as test-only (never set in production).
- Propagation across canonical registries: README.md features table (new `/improve-skill` row), `docs/skills.md` TOC + section, `docs/workflow-lifecycle.md` (prose + mermaid diagram updated for the new kernel delegation topology), `docs/configuration-and-permissions.md` strict-permissions allowlist, `docs/installation-and-setup.md` shipped-skill catalog, `SECURITY.md` (new `/improve-skill` subsection + `LARCH_ITERATION_SCRIPT_OVERRIDE` test-only note), `skills/shared/subskill-invocation.md` scope lists + exemption prose, `scripts/test-anti-halt-banners.sh` DELEGATORS array, `agent-lint.toml` dead-script exclusions, Makefile `test-harnesses` aggregate + `.PHONY` line, `.claude/settings.json` allow-list (`Skill(improve-skill)` + `Skill(larch:improve-skill)`). Loop SKILL.md's "byte-identical driver" paragraph revised to describe the factored-out topology while asserting the streaming contract (background Bash + Monitor tail + filter regex + breadcrumb prefixes) is unchanged from #291.
- Two new regression harnesses: `scripts/test-improve-skill-iteration.sh` (two-tier: structural asserts on the kernel + four behavioral fixtures stubbing claude/gh for grade_a / no_plan / design_refusal / im_verification_failed cases) and `scripts/test-improve-skill-skill-md.sh` (mirrors the `/loop-improve-skill` SKILL.md harness assertions A-F against the new SKILL.md). `scripts/test-loop-improve-skill-driver.sh` updated: iteration-body tokens removed (moved to the kernel harness); delegation + KV-parse + retained-slim-helper tokens added; Tier-2 fixtures use `LARCH_ITERATION_SCRIPT_OVERRIDE` to redirect iteration invocations at a deterministic stub shim.

## [6.2.14] - 2026-04-23

### Changed

- Remove `--auto` from the two `/implement` invocation examples in `skills/fix-issue/SKILL.md` Step 6a (closes #389). Both SIMPLE and HARD delegation paths now invoke `/implement` without `--auto`; all other flags (`--quick` on SIMPLE, `--merge`, `--session-env`, `--issue`, conditional `--slack`/`--debug`) and the `<feature description>` positional arg are unchanged. Surgical two-token prose edit; no behaviour gated on `--auto` elsewhere in `/fix-issue` was affected.

## [6.2.13] - 2026-04-23

### Changed

- Move `/implement` tracking-issue creation from Step 9a.1 to Step 0.5 Branch 4 so the tracking issue exists immediately on a fresh run. The issue body carries the original `FEATURE_DESCRIPTION` verbatim (after mandatory compose-time prompt-level sanitization — secrets / internal URLs / PII) wrapped in a blockquote for fence-injection safety. The anchor comment is now populated progressively as the run executes (`plan-goals-test` and `plan-review-tally` at Step 1, `code-review-tally` at Step 5, `diagrams` at Step 7a, `version-bump-reasoning` at Step 8, `oos-issues` + `run-statistics` at Step 9a.1, `execution-issues` at Step 11). Step 2 adds a new `Q/A` category to `execution-issues.md` with a progressive anchor upsert after each opportunistic question or mid-coding ambiguity, so Q/A appears on the issue live rather than batched until Step 11. Step 18 prints `📎 Tracking issue: <url>` at the end of the run (derived via `gh issue view --json url` so it works on GitHub Enterprise). Step 9a.1 no longer performs the first-remote-write (removed "Deferred-Creation" sub-step); it is OOS + run-stats only. Step 9a drops the `<PLACEHOLDER_TRACKING_ISSUE>` path entirely: the degraded run (create-issue failure or `repo_unavailable=true`) omits the `Closes` line and writes `_No tracking issue — auto-close N/A._` instead of a malformed `Closes #...` reference. Load-Bearing Invariant #4 text tightened: on Branch 4 first-creation, the sentinel is written ONLY after both `ISSUE_NUMBER` and `ANCHOR_COMMENT_ID` resolve to non-empty values; any create-issue or upsert-anchor failure flips to `deferred=true` and skips the sentinel. `scripts/tracking-issue-read.md`, `skills/implement/references/rebase-rebump-subprocedure.md`, `skills/implement/references/anchor-comment-template.md`, `skills/implement/references/pr-body-template.md`, `scripts/assemble-anchor.sh`, and `scripts/assemble-anchor.md` updated in sync. One follow-up OOS filed (Step 2 pre-existing ambiguity-log sanitization gap for entries that flow into the public anchor comment).

## [6.2.12] - 2026-04-23

### Changed

- Cleanup `README.md`: move full skill descriptions to a new `docs/skills.md` reference (skills table now shows command, arguments, and a one-line summary, with the command linking into the detailed doc); shorten the Features section to 1-2 line entries, each linking to the relevant in-repo doc; drop the redundant "Slash commands available in Claude Code sessions…" intro line; restructure the skills table as an HTML `<table>` with alternating Name+Arguments and full-width description rows separated by `<hr>` so argument lists no longer wrap awkwardly. Aliases table and other sections are unchanged. `scripts/test-quick-mode-docs-sync.sh` still passes (required `7 rounds`, `Cursor → Codex → Claude`, and `no voting panel` markers are retained in the `/implement` description cell).

## [6.2.11] - 2026-04-23

### Changed

- Extend `scripts/test-quick-mode-docs-sync.sh` with a target-specific cross-reference check guarding the Note A citation in `docs/review-agents.md` to `skills/shared/voting-protocol.md` (closes #377). The new `check_xref` function asserts both (a) the literal path is present in the doc (`grep -Fq`) AND (b) the path resolves to a regular file on disk (`[[ -f ]]`, directories deliberately rejected). Self-test is extended with three xref fixtures: `xref-good` (both assertions pass), `xref-bad-existence` (existence assertion only fires), and `xref-bad-grep` (grep assertion only fires) — symmetric guards so removal of either assertion is caught by exactly one bad fixture. Sibling `scripts/test-quick-mode-docs-sync.md` documents the two-assertion design, the substring-level scope limitation of assertion (a), and updated edit-in-sync rules for future rename / removal of the cited target. `docs/linting.md` row for `make test-quick-mode-docs-sync` refreshed to name the new check family.

## [6.2.10] - 2026-04-23

### Changed

- Note the `gitleaks` full-tree scan exception in the `README.md` `/relevant-checks` row (closes #378). The row previously said the checks were "scoped to files modified on the current branch," but `gitleaks` is configured with `pass_filenames: false` in `.pre-commit-config.yaml` and always scans the full working tree regardless — the consumer-surface `.claude/skills/relevant-checks/SKILL.md` already documented this exception, so the README is now aligned with it and no longer understates the `/relevant-checks` coverage.

## [6.2.9] - 2026-04-23

### Changed

- `.gitleaks.toml` path allowlist narrowed to scripts + config + tracking-issue-write contract docs (closes #375). The five high-churn documentation paths previously whole-file-exempted — `README.md`, `CHANGELOG.md`, `SECURITY.md`, `skills/issue/SKILL.md`, and `skills/issue/scripts/create-one.sh` — are now scanned by gitleaks in both pre-commit (`--no-git`) and CI (full-history) modes. Empirical finding inventory against the pinned `v8.18.4` engine reported 0 leaks across 290 commits after the narrowing, confirming the existing short-prefix mentions in those docs don't trigger default detectors; a canary synthetic `ghp_…` token in a non-allowlisted path correctly fires rule `github-pat`. `SECURITY.md` "Layered secret scanning" updated to reflect the narrower scope and the explicit gitleaks/trufflehog layer split — trufflehog `--only-verified` catches only live, authenticable credentials and is non-redundant with gitleaks for that reason, NOT a replacement for it; tokens whose format falls outside gitleaks' covered rule families may slip both Layer 1–2 and Layer 3, so contributors must not rely on scanner layers as a substitute for editorial discipline in docs. Out-of-scope files that retain whole-file allowlists — `scripts/redact-secrets.sh`, `scripts/test-redact-secrets.sh`, `scripts/tracking-issue-write.sh`, `scripts/tracking-issue-write.md`, `scripts/test-tracking-issue-write.md` — legitimately carry token-shaped strings throughout.

## [6.2.8] - 2026-04-23

### Fixed

- Align public `/implement --quick` descriptions in `README.md`, `docs/review-agents.md`, and `docs/workflow-lifecycle.md` with the current `skills/implement/SKILL.md` Step 5 contract (up to 7 rounds, per-round Cursor → Codex → Claude Code Reviewer subagent fallback chain, no voting panel). Add `scripts/test-quick-mode-docs-sync.sh` regression harness with a `--self-test` mode that proves the negative-check path fires, wired into `make lint` via the `test-harnesses` target. Closes #370.

## [6.2.7] - 2026-04-23

### Changed

- Phase 6 documentation polish (umbrella #348 closes #354): align public docs with shipped Phase 3-5 tracking-issue behavior. `README.md` adds `--issue <N>` to the `/implement` argument-hint, extends the description, adds a "Tracked runs" Features bullet, and rewrites the `/fix-issue` row to acknowledge INTENT (PR/NON_PR) classification and scope `--issue` forwarding to the PR path. `SECURITY.md` appends anchor body-level truncation posture (`BODY_CAP=60000`, `PER_SECTION_CAP=8000`, marker-preserving deterministic collapse, redaction-before-truncation) to the existing `tracking-issue-write.sh` subsection and corrects a stale "seven assertion categories" claim to nine. `docs/workflow-lifecycle.md` extends both `/implement` and `/fix-issue` bullets with Step 0.5, anchor-as-single-source-of-truth, and `--issue` forwarding semantics. `docs/review-agents.md` Output Format cross-references `workflow-lifecycle.md` for the anchor-comment routing contract. `scripts/test-tracking-issue-write.sh` header comment updated to match the sibling `.md`'s nine-category count.

## [6.2.6] - 2026-04-23

### Added

- Two-layer secret scanning: `gitleaks` as pre-commit hook (with an `entry` override to `gitleaks detect --no-git --source .` so the hook scans the working tree/staged content — upstream's default `protect --staged` scans zero commits on a clean tree) plus a dedicated CI job that installs the same pinned `v8.18.4` engine via SHA256-verified direct download and runs a full git-history scan. `trufflehog` as a CI-only job, pinned to commit SHA `1aa1871f9ae24a8c8a3a48a9345514acf42beb39` for `v3.82.13` with `version: 3.82.13` pinning the scanner Docker image and `--only-verified` for live credential verification.
- `.gitleaks.toml` path-based allowlist for files that legitimately contain token-shaped strings (test fixtures, regex-defining source, token-family documentation in release notes and security policy).
- `make gitleaks` and `make trufflehog` Makefile targets matching the existing per-hook one-liner pattern.
- `SECURITY.md` "Layered secret scanning" subsection documenting the three-layer model (Layer 1 commit-time working-tree scan, Layer 2 PR-gate git-history scan, Layer 3 PR-gate verified-only live check) and allowlist rationale. `docs/linting.md` updates gain a "CI secret scanning" subsection. `.claude/skills/relevant-checks/SKILL.md` documents the `pass_filenames: false` exception.

## [6.2.5] - 2026-04-23

### Changed

- Add `/loop-improve-skill` to the skills inventory in `docs/installation-and-setup.md` (closes #371). The skill is shipped at `skills/loop-improve-skill/` and documented in `README.md`, but was omitted from the "What the plugin provides" table when the setup docs were split out in 6fe1262.

## [6.2.4] - 2026-04-23

### Changed

- Phase 5 of umbrella #348 (closes #353): retarget the rebase-rebump sub-procedure's Version Bump Reasoning refresh from the PR body to the tracking-issue anchor's `version-bump-reasoning` section. Extract a shared anchor-body assembler (`scripts/assemble-anchor.sh` + `scripts/anchor-section-markers.sh`) so `tracking-issue-write.sh` and the assembly walk share one executable source of truth for the 8 canonical `SECTION_MARKERS`. `skills/implement/references/rebase-rebump-subprocedure.md` Step 6 now reads the tracking-issue sentinel, preserves the prior fragment on `HAS_BUMP=false` degraded paths (no placeholder overwrite), assembles via the shared helper, and upserts the anchor — with fail-soft skip semantics when the sentinel is unusable. `skills/implement/SKILL.md` routes all anchor assembly (Step 0.5 Branch 2/3 seed, Steps 1/5/7a/8/9a.1/11 progressive upserts) through the same helper. Doc sweep across `rebase-rebump-subprocedure.md`, `conflict-resolution.md`, `anchor-comment-template.md` retargets every "PR body refresh" mention. New test harnesses: `scripts/test-assemble-anchor.sh` (10 assertions — empty/partial/full fragment shapes, missing-helper fail-closed, non-directory `--sections-dir`, unreadable fragment, first-line marker, trailing-newline regression guard). `scripts/test-tracking-issue-write.sh` gains (h) missing-helper-contract + (i) `SECTION_MARKERS ⊆ COLLAPSE_PRIORITY` invariant. `scripts/test-implement-structure.sh` gains (11) sub-procedure reference set + (12) SSoT source-call invariant (now 12 structural invariants total).

## [6.2.3] - 2026-04-23

### Changed

- `/fix-issue` Step 6a now forwards `--issue $ISSUE_NUMBER` to `/implement` (both SIMPLE and HARD branches) so the child skill adopts the queue issue as its tracking issue via Phase 3 Branch 2, avoiding a duplicate tracking-issue on the `/fix-issue` path. On `IMPLEMENT_BAIL_REASON=adopted-issue-closed` (emitted when the adopted tracking issue is closed externally), Step 6a prints a specific warning and skips Step 7's `issue-lifecycle.sh close` call entirely — cleanup redirects straight to Step 9. Generic-failure path unchanged (IN PROGRESS retained as manual-intervention indicator). Phase 4 of umbrella #348 (closes #352). Adds two Known Limitations bullets (external-close recovery, token-never-seen caveat), a new offline regression harness `skills/fix-issue/scripts/test-fix-issue-bail-detection.sh` pinning six load-bearing literals inside the Step 6a block, a paired token-literal assertion in `scripts/test-implement-structure.sh` (now 10 structural invariants), and doc-only syncs in `skills/implement/SKILL.md` (line 247 parenthetical + `/fix-issue coordination` paragraph at lines 308-310) to reflect post-Phase-4 landed state.

## [6.2.2] - 2026-04-23

### Changed

- Slim `README.md` by factoring verbose reference sections into three new `docs/*.md` files — `docs/installation-and-setup.md`, `docs/configuration-and-permissions.md`, `docs/linting.md`. Adds a Table of Contents at the top of `README.md` in reader-journey order, alphabetizes the Skills table by slash-command name (case-insensitive), and drops the small Review Agents block (replaced by a TOC pointer to the canonical `docs/review-agents.md`). Downstream contracts retargeted in lockstep: `AGENTS.md` canonical-sources list, `SECURITY.md` strict-permissions pointer, `Makefile` halt-rate-probe comment, `skills/create-skill/scripts/post-scaffold-hints.{sh,md}` + `skills/create-skill/SKILL.md` strict-permissions pointer, `scripts/test-loop-improve-skill-halt-rate.{sh,md}` README references. Also adds a "Migration from legacy agent slugs" section to `docs/review-agents.md` preserving the `general-reviewer` / `deep-analysis-reviewer` → `code-reviewer` guidance formerly in README.

## [6.2.1] - 2026-04-23

### Changed

- `.claude/skills/bump-version/SKILL.md` Output contract aligned with the slim PR body that Phase 3 of umbrella #348 shipped (closes #364). The section no longer claims the reasoning log is embedded into the PR body under `<details><summary>Version Bump Reasoning</summary>` — that block does not exist in the post-Phase-3 PR body template. It now states that `/implement` Step 8 reads the reasoning log as source content for the `version-bump-reasoning` anchor-section fragment, which is upserted into the tracking issue's anchor comment via `tracking-issue-write.sh upsert-anchor` and is the canonical audit surface. The `classify-bump.sh REASONING_FILE=<path>` stdout guidance is unchanged.

## [6.2.0] - 2026-04-23

### Added

- `/implement --issue <N>` flag + new Step 0.5 "Resolve Tracking Issue" with 4-branch decision tree (sentinel reuse with hydration / `--issue` explicit adoption / PR-body-recovery from `Closes #<N>` / deferred-to-Step-9a.1). Step 9a.1 creates the tracking issue on the deferred path. Phase 3 of umbrella #348 (tracks #351).
- Anchor-section accumulation: each relevant step (1 / 5 / 7a / 8 / 9a.1 / 11) writes per-step fragments to `$IMPLEMENT_TMPDIR/anchor-sections/<slug>.md` and upserts a single canonical anchor comment on the tracking issue (via `scripts/tracking-issue-write.sh upsert-anchor`) as the single source of truth for voting tallies, diagrams, version-bump reasoning, OOS list, execution issues, and run statistics.
- Load-Bearing Invariant #4 (Tracking-Issue Sentinel Idempotency) — `$IMPLEMENT_TMPDIR/parent-issue.md` is the byte-exact session-scope guard against double-creation on retry.
- `SECURITY.md` documents the anchor comment as a durable public store, compose-time sanitization obligations, public-publication boundary, `repo_unavailable=true` audit-loss, and cross-session recovery via `Closes #<N>`.

### Changed

- `skills/implement/references/pr-body-template.md`: rewritten to the slim Phase 3 projection — Summary + Architecture Diagram + Code Flow Diagram + Test plan + `Closes #<N>` + Claude Code footer only. Rich report content lives in the anchor comment per `anchor-comment-template.md`. Step 11's post-execution refresh now targets the anchor's `execution-issues` section (was the PR body's `<details><summary>Execution Issues</summary>` block).
- `skills/implement/references/anchor-comment-template.md`: active-consumer status updated; the three load-bearing marker literals (`Accepted OOS (GitHub issues filed)`, `| OOS issues filed |`, `<details><summary>Execution Issues</summary>`) are now pinned here by `scripts/test-implement-structure.sh` assertion (9a). Step 9a.1 pipeline becomes canonical here.
- `scripts/test-implement-structure.sh` + sibling `.md`: `expected_refs` extended to 5 entries (adds `anchor-comment-template.md`); MANDATORY-occurrence floor raised to 5; assertion (9a) pins the 3 marker literals in `anchor-comment-template.md` (migrated from `pr-body-template.md`); assertion (9b) pins a new ≥3 reference floor for `anchor-comment-template.md` in SKILL.md (Step 0.5 MANDATORY + Step 9a.1 + Step 11); assertion (9c) lowers `pr-body-template.md` floor to ≥1 (just the Step 9a MANDATORY pointer).
- NEVER #5 renamed from "PR-body Accepted-OOS update" to "anchor-comment Accepted-OOS update"; "How to apply" clause retargeted to the anchor's `oos-issues` / `run-statistics` sections.
- `scripts/tracking-issue-read.md` `ADOPTED=` contract gets Phase 3 producer semantics pinned: `true` on Branches 2 & 3 (explicit-flag or PR-body-recovery adoption), `false` on Branch 4's deferred creation (new issue created, not adopted).

## [6.1.12] - 2026-04-23

### Changed

- `scripts/tracking-issue-read.sh` `--sentinel` mode: pinned the `ADOPTED=` field contract (closes #359) before Phase 3 (#351) wires the sentinel as its first consumer. Allowed values are now strictly `true` or `false` when the key is present with a valid value, or empty (key absent or explicit `ADOPTED=`). Empty means "sentinel unusable" — consumers MUST NOT treat empty as equivalent to `false` and MUST fall back to their fresh-creation path. Any other non-empty value (e.g. `TRUE`, `1`, `yes`, `true` with trailing whitespace) is rejected with `FAILED=true` / `ERROR=invalid ADOPTED value in sentinel: '<val>' (expected 'true' or 'false' or absent)` and exit 1. Parser hardening added at the same time: leading UTF-8 BOM is stripped before key extraction, trailing `\r` is stripped from extracted values (CRLF tolerance), column-0 keys only (indented lines treated as absent), first-match wins on duplicate keys, and an explicit `[[ -r "$SENTINEL" ]]` readability guard emits the `FAILED=true`/`ERROR=sentinel file not readable: <path>` envelope instead of silently tripping `set -e`. Contract pinned in `scripts/tracking-issue-read.md` and a focused regression harness `scripts/test-tracking-issue-read-sentinel.sh` (15 cases, 30 assertions) wired into `make lint` via `test-harnesses` locks the behavior against drift. `agent-lint.toml` exclusion mirrors the existing `test-tracking-issue-write.sh` Phase-1 pattern.

## [6.1.11] - 2026-04-23

### Fixed

- `scripts/tracking-issue-write.sh` `truncate_body` no longer leaks its `work_dir` (from `mktemp -d`) when an `awk` call fails mid-function under `set -e` (closes #360). The function body is now a subshell (`truncate_body() ( … )`) and installs `trap "rm -rf '$work_dir'" EXIT` immediately after `mktemp -d`, so cleanup is structurally scoped to the function's own subshell and fires on every exit path — not only the trailing success-path `rm -rf` that the previous code relied on. The subshell-body form also makes the cleanup contract robust to future refactors: callers no longer have to preserve the implicit "always invoke via `$(…)`" invariant for the EXIT trap to stay scoped. The misleading header comment claiming the caller's EXIT trap covered `work_dir` transitively is rewritten to reflect the new ownership (each per-subcommand EXIT trap only names `BODY_TMP`/`ERR_TMP`/`JSON_TMP`, never `work_dir`). Pure resource-management fix — no change to stdout contract, redaction ordering, truncation algorithm, or anchor skeleton preservation; `scripts/test-tracking-issue-write.sh`'s 43 assertions pass unchanged.

## [6.1.10] - 2026-04-23

### Added

- Phase 1 of umbrella #348 (tracking-issue lifecycle) — foundation helper scripts `scripts/tracking-issue-write.sh` (three subcommands `create-issue` / `append-comment` / `upsert-anchor`; KEY=value stdout envelope with the `FAILED=true` / `ERROR=` failure namespace distinct from `/issue`'s `ISSUE_FAILED=` prefix; fail-closed redaction via `scripts/redact-secrets.sh`; structural choke point `compose → redact → truncate`; two-pass truncation preserving the anchor HTML first-line marker and all eight section-open/section-end marker pairs; strict `<!-- larch:implement-anchor v1` version matching with fail-closed on multiple-anchor comment lists) and `scripts/tracking-issue-read.sh` (pure reader with three mutually-exclusive task-source branches `--issue + --prompt` / `--issue` alone / `--prompt` or stdin, fail-closed flag-combination matrix, `--sentinel` local-markdown parse mode, strict-v1 anchor-marker and `<!-- larch:lifecycle-marker:` filters, data-not-instructions `<external_issue_body>` / `<external_issue_comment id=>` envelope for fetched GitHub content, deterministic caps `--max-body-chars` / `--max-comments` / `--max-total-chars` with integer validation at parse time, lossless JSON-per-line comment transport via `jq '... | tojson'`, local gh-stderr redaction on all ERROR= emissions). New regression harness `scripts/test-tracking-issue-write.sh` with seven assertion categories (redaction, exit-3 fail-closed on missing helper, anchor + 8-section-marker preservation under body-level collapse, per-section 8000-cap inline marker on its own line, append-comment anchor isolation, single-anchor idempotency, multiple-anchor fail-closed, gh-failure stderr redaction) wired into `make test-harnesses`. New reference file `skills/implement/references/anchor-comment-template.md` carries the canonical 8-section anchor-comment template and the three load-bearing literals (`Accepted OOS (GitHub issues filed)`, `| OOS issues filed |`, `<details><summary>Execution Issues</summary>`) that Phase 3's `test-implement-structure.sh` migration will pin. `SECURITY.md` documents the new outbound and read-path security invariants; `agent-lint.toml` excludes the helper scripts and harness until Phase 3 wires the first consumer. All new scripts are Bash 3.2-compatible. No user-visible behavior changes — scripts ship unwired. Closes #349.

## [6.1.9] - 2026-04-23

### Changed

- `skills/fix-issue/scripts/issue-lifecycle.sh` `cmd_close` is now idempotent against an already-CLOSED issue (Phase 2 of umbrella #348; closes #350). Before invoking `gh issue close`, the subcommand probes current state via `gh issue view --json state`; on `CLOSED` it skips the close call and emits `INFO: issue #N already closed; backfilling DONE metadata only` on stderr while still printing `CLOSED=true` on stdout — the DONE comment and `--pr-url` body backfill still run in both branches. On probe failure the subcommand logs `WARNING: failed to probe state for issue #N; attempting close anyway` on stderr and falls through to `gh issue close`, preserving the pre-idempotency OPEN-path reliability (transient `gh issue view` blips no longer abort a close that the write-side would have succeeded on). Additionally tightened: `cmd_close` now suppresses the internal `cmd_update_body` stdout via `>/dev/null` so `UPDATED=`/`SKIPPED=` keys never leak into `cmd_close`'s stdout, making the `CLOSED=true` contract byte-stable across open and already-closed paths. Sibling contract doc `skills/fix-issue/scripts/issue-lifecycle.md` added per AGENTS.md. Offline PATH-stub regression harness `skills/fix-issue/scripts/test-issue-lifecycle.sh` (6 fixtures) added and wired into `make test-harnesses` via the new `test-issue-lifecycle` target; `agent-lint.toml` excludes updated for the new harness and its sibling `.md`.

## [6.1.8] - 2026-04-23

### Changed

- `skills/create-skill/SKILL.md` prose compressed via Strunk & White filler removal. Two sentence-level tweaks on line 10 drop "if you want to" and sentential "it is" from the `--merge` explicit-pass note. Net saving: 19 bytes (0.11% of file); 0 line-count delta. `scripts/parse-args.md` unchanged — every paragraph is already at or below the ~10% per-paragraph compression threshold, so meaning-preservation beats marginal compression. Zero structural changes: YAML frontmatter, fenced code blocks, headings, link targets, table structure, file paths, numeric values, flag names all byte-identical.

## [6.1.7] - 2026-04-23

### Changed

- `README.md` "Setting Up Claude, Codex, Cursor, etc." section intro rewritten to state explicitly that only `claude` is mandatory; `codex` and `cursor` are optional and are substituted with Claude subagents when missing or unauthenticated (deduplicated with `Prerequisites > Optional integrations` via cross-reference rather than restating). Adds a sentence clarifying that larch is agent-agnostic about authentication — each agent can be set up with either an API key or a subscription plan via web-based login; larch only needs the binary on `PATH` and a successful authenticated session.
- `README.md` Cursor-subsection `cli-config.json` note trimmed from a multi-sentence paragraph to the single sentence "Note — larch overrides the cli-config.json model for its own Cursor invocations." The `--model` precedence, `LARCH_CURSOR_MODEL` resolution, `composer-2` default, and max-mode prompt injection details are preserved in the `Environment Variables > LARCH_CURSOR_MODEL` section rather than being duplicated in the setup recipe.

## [6.1.6] - 2026-04-23

### Changed

- `skills/implement/SKILL.md` anti-halt banner at line 12 normalized to byte-match the canonical wording in `skills/shared/subskill-invocation.md:99` (closes #346). The abbreviated form — missing the `e.g.,` prefix in the tool-list parenthetical, `The rule is` / `any` prefixes and `directive` (singular) in the subordination clause, `instruction` in the default-continuation line, `anywhere in this file` and `by this rule` in the `/relevant-checks` sentence, and `for the canonical rule` in the trailing pointer — diverged from the canonical form used by every other orchestrator (`/fix-issue`, `/review`, `/loop-review`, `/alias`, `/research`). Concurrently-maintained divergence makes single-replacement-string sweeps (like PR #347's broadening) fragile; this restores the single-source-of-truth invariant. Contract token `**Anti-halt continuation reminder.**` unchanged — `scripts/test-anti-halt-banners.sh` passes unchanged.

## [6.1.5] - 2026-04-23

### Changed

- Broadened the anti-halt continuation prohibition across 6 orchestrator SKILL.md files and `skills/shared/subskill-invocation.md` to explicitly name "summary, handoff, status recap, or 'returning to parent' message" as halts-in-disguise — not just the prior narrower "child's cleanup output" phrasing. Motivation: PR #345 exposed a halt where `/fix-issue`'s agent wrote a "Returning to /fix-issue caller" handoff message after `/implement`'s Step 18 cleanup, forcing the user to type "continue" to resume Step 7. The PR adds new post-call blockquote directives at 3 heavy-child `Skill`-tool call sites naming the concrete next parent step: `/fix-issue` Step 6a (post-`/implement` → Step 7, success-path scoped), `/implement` Step 1 normal mode (post-`/design`), `/implement` Step 5 normal mode (post-`/review`); `/alias` Step 3's existing post-call reminder is broadened to match. The canonical source `skills/shared/subskill-invocation.md` is the single source of truth; all pre-existing per-call-site micro-reminders (9 locations across 5 files) were updated to include the new broadened clause for internal consistency. Both harness contract substrings (`**Anti-halt continuation reminder.**` and `Continue after child returns`) preserved byte-exact; `scripts/test-anti-halt-banners.sh` passes unchanged.

## [6.1.4] - 2026-04-23

### Added

- `scripts/test-references-headers.sh` gained a second assertion that rejects stale `L<digits>-<digits>` line-range citations inside the `**Contract**:` paragraph of every `skills/*/references/*.md` file (closes #322). The check extends the existing triplet-header scan: for each reference file, `awk` extracts the Contract paragraph (from `^**Contract**:` to the next whitespace-only line or the next anchored `**Consumer**:` / `**When to load**:` header), and `grep -E` rejects any word-bounded `L<digits>(-|–|—)<digits>` substring. All three dash forms (ASCII hyphen, en-dash, em-dash) are matched via alternation so the check stays locale-safe under `LC_ALL=C`. The v5.2.7 refactor had already eradicated such citations from the 4 `skills/implement/references/*.md` files (replacing them with range-free descriptions in FINDING_4); this regression guard prevents reintroduction in any current or future reference file. Sibling contract `scripts/test-references-headers.md` and the script's top-of-file comment updated in sync.

## [6.1.3] - 2026-04-23

### Changed

- `README.md` Cursor setup section gained a note clarifying that larch overrides `~/.cursor/cli-config.json` `modelId` via its own `--model $MODEL` flag, where `$MODEL` resolves from `LARCH_CURSOR_MODEL` or the plugin userConfig `cursor_model` (exported to subprocesses as `CLAUDE_PLUGIN_OPTION_CURSOR_MODEL`; default `composer-2`). Users pinning a specific Cursor model for larch should set `LARCH_CURSOR_MODEL` or the `cursor_model` userConfig rather than editing the JSON file. Also notes that larch enforces max-mode at the prompt level (`scripts/cursor-wrap-prompt.sh`), so `"maxMode": true` in the JSON is not required for larch-driven calls. Closes #334.

## [6.1.2] - 2026-04-23

### Fixed

- `skills/simplify-skill/scripts/build-feature-description.sh:134-135` now strips all whitespace from `wc -l` / `wc -c` output via `tr -d '[:space:]'` instead of only ASCII spaces. BSD `wc` pads its numeric output with whitespace that is not a plain space, so the previous `tr -d ' '` left stray characters concatenated into `SKILL_MD_LINES` / `SKILL_MD_CHARS`. Identical fix to the one already applied to `skills/compress-skill/scripts/build-feature-description.sh` for issue #311. Closes #328.

## [6.1.1] - 2026-04-23

### Added

- `scripts/test-implement-structure.sh` gained a 9th assertion that pins load-bearing marker literals inside the extracted `skills/implement/references/pr-body-template.md` reference (closes #323). (9a) Three byte-pinned markers — `Accepted OOS (GitHub issues filed)`, `| OOS issues filed |`, and `<details><summary>Execution Issues</summary>` — must remain in `pr-body-template.md`; these are parsed and rewritten at runtime by the Step 9a.1 OOS issue-filing pipeline (OOS placeholder + Run Statistics OOS cell) and the Step 11 post-execution PR-body refresh (Execution Issues details block), so a silent rename or removal would break runtime behavior with no test failure. Fixed-string matching because the literals contain regex metachars (`|`, `<`, `>`). (9b) `skills/implement/SKILL.md` must reference `pr-body-template.md` at least 3 times — Step 9a MANDATORY pointer + Step 9a.1 prose binding + Step 11 prose binding — guarding against a future edit that keeps the MANDATORY pointer (which assertion (4) already pins) but orphans Step 9a.1 or Step 11 from the extracted reference. Sibling contract `scripts/test-implement-structure.md` and the script's top-of-file comment updated in sync.

## [6.1.0] - 2026-04-23

### Added

- `--slack` opt-in flag forwarded to `/implement` from every skill that invokes it: `/fix-issue`, `/simplify-skill`, `/compress-skill`, `/create-skill`, `/alias`, and `/loop-improve-skill`. Each skill accepts `--slack` and threads it through to its `/implement` (or `/im` / `/imaq`) invocation; without `--slack`, the delegated run does not post to Slack regardless of Slack env-var presence. `/alias` treats `--slack` as a dual-role flag (consumed when before the first positional, passed through verbatim as a preset flag afterwards), matching the pre-existing `--merge` dual-role. `/loop-improve-skill` propagates `--slack` to every iteration's `/larch:im` prompt, so an opt-in loop can post up to 10 Slack announcements. `/create-skill`'s `parse-args.sh` now emits `SLACK=true|false` alongside the existing output keys; a new sibling contract `skills/create-skill/scripts/parse-args.md` documents the stdout grammar, error contract, and edit-in-sync obligations per AGENTS.md. `README.md` and `docs/workflow-lifecycle.md` updated (flag table, Slash Commands rows, Standalone Usage bullets).

## [6.0.10] - 2026-04-23

### Changed

- `.github/workflows/ci.yaml:36` comment no longer asserts a hardcoded harness count: the literal string `the 22 test-*` was replaced with `the test-*` so the phrase reads "the `test-*` bash scripts in Makefile". The count was already stale (the target lists 25+) and would keep drifting every time a harness is added; CI still runs `make test-harnesses`, the authoritative list. Cosmetic, no behavioral effect. Closes #319.

## [6.0.9] - 2026-04-23

### Changed

- `scripts/test-review-structure.sh` hardened with three line-scoped callsite pins (closes #318), pattern parallel to `test-research-structure.sh`'s reciprocal Do-NOT-load pins. New check (5) asserts that a single `skills/review/SKILL.md` line carries (5a) `MANDATORY — READ ENTIRE FILE` + `Step 3` + `references/domain-rules.md` together (Step 3 entry callsite pin); (5b) `MANDATORY — READ ENTIRE FILE` + `round 1` (case-insensitive) + `references/voting.md` together (round-1 branch callsite pin); (5c) `Do NOT load` + `references/voting.md` together (reciprocal rounds-2+ guard). Token boundaries are non-word-char-anchored so `Step 3a` / `Step 30` / `round 10` cannot false-pass. Old assertions (5)–(8) renumbered to (6)–(9); PASS line now reports 9 invariants. Sibling contract `scripts/test-review-structure.md` updated in parallel to document the new pins and boundary rationale.

## [6.0.8] - 2026-04-23

### Fixed

- `skills/create-skill/scripts/render-skill-md.sh` scaffold bullet 6 (Anti-halt continuation reminder) in both `MULTI_STEP_BODY` and `MINIMAL_BODY` heredocs no longer enumerates a hard-coded four-name pure-delegator list. It now points at `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section "Scope list" — the single source of truth already used by `scripts/test-anti-halt-banners.sh`'s `DELEGATORS` array. Eliminates the drift surface that had left newly-scaffolded skills with an outdated checklist missing `/simplify-skill` and `/compress-skill` (closes #327).

## [6.0.7] - 2026-04-23

### Changed

- `.agnix.toml` cleared four residual CI warnings with no behavioral change to any skill (closes #317). Added `XP-SK-001` to `disabled_rules` with a comment explaining that `argument-hint` is a Claude Code-supported field and intentional across every skill here. Added a top-level `exclude` list that preserves agnix's defaults (`node_modules/**`, `.git/**`, `target/**`) and adds `tests/fixtures/**` so deliberately-skeletal halt-rate fixtures (e.g. `tests/fixtures/loop-halt-rate/SKILL.md`) no longer trigger `AS-010`. Added a `[tool_versions]` section pinning `claude_code = "2.1.0"` to satisfy `VER-001`. `AGENTS.md` tightened `contributors developing in this repo should load larch as a plugin …` to `must` to clear `PE-003` in the critical "Editing rules" section.

## [6.0.6] - 2026-04-23

### Fixed

- `.github/workflows/ci.yaml` Node.js 20 deprecation and invalid `agent-lint` input (closes #316). Bumped `actions/checkout@v4` → `@v6`, `actions/setup-python@v5` → `@v6`, and `actions/cache@v4` → `@v5` — each major publishes a Node.js 24 entrypoint (runner v2.327.1+, already on `ubuntu-latest`). Replaced the silently-ignored `args: --pedantic` on `zhupanov/agent-lint@v2.3.2` with the documented `pedantic: true` input.

## [6.0.5] - 2026-04-23

### Changed

- Cursor default model flipped from `composer-2-fast` to `composer-2` in `scripts/reviewer-model-args.sh`, and every substantive Cursor invocation now wraps its prompt through new `scripts/cursor-wrap-prompt.sh`, which owns the single source of truth for the ` /max-mode on. Prompt: ` prefix that engages Cursor's max-mode. 12 wrapped launch strings in 11 files were updated: `skills/{research/references/{research-phase,validation-phase}.md, design/SKILL.md, design/references/{sketch-launch (x2), dialectic-execution}.md, shared/{voting-protocol,dialectic-protocol}.md, review/SKILL.md, implement/SKILL.md, loop-review/SKILL.md}` and `scripts/run-negotiation-round.sh`. `scripts/check-reviewers.sh` health probes are deliberately NOT wrapped (max-mode is unnecessary latency/cost for a `Respond with OK` reachability check; rationale comments added at both probe sites). `scripts/run-external-reviewer.sh` header example now references the wrapper. `README.md` External Reviewer Model Configuration and `.claude-plugin/plugin.json` `cursor_model` description document the new default; users can opt back into the previous behavior by setting `LARCH_CURSOR_MODEL=composer-2-fast`. Preflight confirmed the prefix engages max-mode (model self-reports `MAX_MODE=on` only when the wrapper is applied).

## [6.0.4] - 2026-04-23

### Changed

- `/issue --go` now works in both single and batch modes (closes #315). `skills/issue/SKILL.md` Step 1 no longer aborts when `--input-file` and `--go` are combined; Step 6's CREATE branch posts `gh issue comment ... --body "GO"` inline after each successful create for both modes, binding the per-iteration issue number from `create-one.sh`'s `ISSUE_NUMBER=<N>` output. A new per-item stdout line `ISSUE_<i>_GO_POSTED=true|false` is emitted only on the CREATE path (never for DUPLICATE, FAILED, or DRY_RUN items). GO-post failures are non-fatal: the stderr excerpt is redacted through `scripts/redact-secrets.sh` before surfacing in a per-item warning, the item still counts as CREATED, and the batch continues. The single-mode duplicate+`--go` pre-flight is explicitly scoped to `MODE=single`. The old Step 9 (single-mode GO post) is removed; its logic is unified inside Step 6 so Step 8's human summary now accurately branches on `ISSUE_1_GO_POSTED`. `README.md` skill catalog row and `SECURITY.md` updated: a new "`/issue --go` approval semantics" subsection documents the batch-approval widening, operator guidance to restrict `--go` callers, and the fail-open-dedup amplifier (a transient dedup-helper failure combined with batch `--go` can produce a burst of newly-created AND auto-approved issues for `/fix-issue`).

## [6.0.3] - 2026-04-23

### Changed

- `docs/workflow-lifecycle.md` Delegation Topology now includes `/compress-skill` — added to the intro "pure forwarders" list, the Delegation Topology mermaid diagram as a two-hop `COMPRESS → IMAQ → IMPLEMENT` chain mirroring the `/create-skill → /im → /implement` pattern, the Topology bullet list, and the "Pure forwarders are exempt..." sentence (closes #312). `skills/shared/subskill-invocation.md` extended in parallel: both exemption paragraphs (`## Post-invocation verification`, `## Anti-halt continuation reminder`) now list `/compress-skill` alongside `/im`, `/imaq`, `/create-skill`, `/loop-improve-skill`, `/simplify-skill`; the `The banner MUST NOT appear in pure-delegator SKILL.md files:` bullet list gains `skills/compress-skill/SKILL.md`; and the Update-triggers paragraph updated from "five pure-delegator SKILL.md files" to "six". `scripts/test-anti-halt-banners.sh` `DELEGATORS` array extended with `skills/compress-skill/SKILL.md` so banner-absence is enforced for this skill; harness passes 18 checks (6 orchestrators, 6 delegators, 6 micro-reminders). Doc/test-only change; no behavioral effect on plugin surface.

## [6.0.2] - 2026-04-23

### Fixed

- `/compress-skill` temp-file leak: `skills/compress-skill/scripts/build-feature-description.sh` emits `FEATURE_FILE` (a `mktemp -t` temp file under `$TMPDIR`) on stdout and exits without cleanup — by contract the caller owns the file's lifetime. `skills/compress-skill/SKILL.md` Step 2 was reading the contents into `FEATURE_DESCRIPTION` but never removing the file, so every `/compress-skill` invocation leaked one temp file (persists across reboots on macOS `/private/tmp` when `$TMPDIR` routes there, accumulates on long-running Linux containers/VMs). Adds `rm -f "$FEATURE_FILE"` to the STATUS=ok branch of Step 2 (only on the success path — failure paths abort before the rm so we never delete a file we could not confirm reading). Documents the caller-owns-lifetime invariant in the script's in-file header and the sibling contract `build-feature-description.md` in the same PR (per AGENTS.md's stdout-contract mirror rule). Closes #310.

## [6.0.1] - 2026-04-23

### Fixed

- `skills/compress-skill/scripts/build-feature-description.sh:153-154` — replaced `tr -d ' '` with `tr -d '[:space:]'` on both the `wc -c` and `wc -l` pipelines. The space-only strip failed to remove BSD `wc` leading/padding whitespace that is not a plain ASCII space on some platforms, letting stray whitespace flow into `TOTAL_BYTES` / `TOTAL_LINES` arithmetic and table cells. Restores the safer normalization the removed `measure-set.sh` previously used. Closes #311.

## [6.0.0] - 2026-04-23

### Changed

- **BREAKING:** `/implement` Slack posting is now opt-in. Added `--slack` flag to `skills/implement/SKILL.md`; default is `slack_enabled=false`. Step 11 (PR announcement) and Step 13 (`:merged:` emoji) now skip Slack API calls unless `--slack` is passed, even when `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID` are present. When `--slack` is passed but env vars are missing, the session-setup warning still prints; when `--slack` is omitted, no warning is printed. Consumers who previously relied on auto-posting based on env-var presence alone must now add `--slack` to their invocations. README.md and `docs/workflow-lifecycle.md` updated to document the new flag and opt-in semantics; the workflow-lifecycle mermaid diagram annotates Slack/`:merged:` nodes as conditional on `--slack`.

## [5.2.9] - 2026-04-23

### Changed

- README Installation section: replaced the enumerated list of slash commands ("/design, /implement, /review, /research, ...") with the generic "all larch skills (e.g., /implement)" to reduce doc maintenance as the skill catalog evolves, and added a new `### Setting Up Claude, Codex, Cursor, etc.` subsection with per-tool API key / env-var / settings-file / install-command instructions covering Claude Code, OpenAI Codex, and Cursor. Doc-only change; no behavioral effect on plugin surface.

## [5.2.8] - 2026-04-21

### Changed

- `/implement` SKILL.md refactored via progressive disclosure and prose compression. `skills/implement/SKILL.md` shrinks from 944 to 683 lines (-261 lines, -29 KB) by (a) compressing Section-I (knowledge-delta) prose across Load-Bearing Invariants, NEVER List, Progress Reporting, Verbosity Control, Execution Issues Tracking, and the per-step narratives, and (b) extracting two workflows into the existing `skills/implement/references/pr-body-template.md`: the full Step 9a.1 OOS GitHub issue creation pipeline (repo-unavailable early-exit, 3-artifact read, all-empty early-exit, idempotency sentinel recovery, cross-phase dedup, `/issue` batch-mode invocation, stdout parsing, PR body "Accepted OOS" placeholder replacement, Run Statistics `| OOS issues filed |` cell rewrite, sentinel write) and the Step 11 post-execution PR body refresh (fetch live body, replace `<details><summary>Execution Issues</summary>` block content, update via `gh-pr-body-update.sh`). Adds Block γ (reasoning-file sentinel defense-in-depth, #160) to `skills/implement/references/bump-verification.md`, consolidating the step-3b procedure previously duplicated inline. Updates `**Contract**:` fields in all 4 reference files to drop stale `SKILL.md L<range>` citations in favor of range-free descriptions. Behavior-preserving: all flags, exit codes, stdout contracts, sentinel-file names, Step Name Registry rows, NEVER-list titles, Rebase Checkpoint Macro invocation shape + M1-M4 body + call-site registry, 3 byte-pinned ⏩ verbosity literals, and Step 5 quick-mode Cursor/Codex Bash blocks (carrying the focus-area enum + `security` on same line that CI's `agent-sync` greps for) remain byte-identical. `scripts/test-implement-structure.sh` (9 assertions) and `scripts/test-implement-rebase-macro.sh` (A-I assertions) pass unchanged.

## [5.2.7] - 2026-04-21

### Added

- `scripts/test-references-headers.sh` + sibling contract `scripts/test-references-headers.md` — cross-skill structural regression guard for the progressive-disclosure Consumer/Contract/When-to-load header triplet (closes #308). Scans every `skills/*/references/*.md` via flat glob and enforces the triplet as anchored line-start patterns (`^\*\*Consumer\*\*:`, `^\*\*Contract\*\*:`, `^\*\*When to load\*\*:`) via `grep -Eq`. Fails closed on empty glob. Path-qualified failure messages.

### Changed

- `scripts/test-implement-structure.sh` narrowed from 9 to 8 assertions: the Consumer/Contract/When-to-load triplet check (formerly assertion 8, scoped to `skills/implement/references/` only) is retired. Cross-skill ownership now lives in `scripts/test-references-headers.sh`. The `/implement`-specific topology invariants (top-level headings, MANDATORY binding, CI-parity focus-area enum, the no-`see Step N below|above` ban in `references/*.md`) remain. PASS echo updated to "all 8 structural invariants hold". Sibling contract `scripts/test-implement-structure.md` rewritten to reflect the new 8-assertion list and cite `test-references-headers.md` as the new triplet owner.
- `scripts/test-research-structure.{sh,md}` Check 4 — the `/research`-local first-20-lines tightening — now uses anchored `grep -Eq` patterns (`^\*\*Consumer\*\*:` etc.) against `head -n 20`, so it actually layers on top of the anchored cross-skill presence check instead of relying on the looser `grep -Fq` substring match. Comment block updated to describe the rule as `/research`-local tightening on top of `scripts/test-references-headers.sh`.
- Backfilled `**Contract**:` + `**When to load**:` headers on 9 reference files under `skills/design/references/` (7 files) and `skills/review/references/` (2 files) so every `skills/*/references/*.md` complies with the new cross-skill triplet contract. `plan-review.md` already had Contract so only When-to-load was added. Existing `**Binding convention**:`, `**Delivery pattern**:`, `**Effort-suffix convention**:`, and `**Substitution placeholders**:` headers preserved in place — no renames.
- `skills/design/references/dialectic-execution.md`'s new `**When to load**:` paragraph now mirrors the caller contract at `skills/design/SKILL.md` Step 2a.5: on the zero-externals guardrail path, debate-execution mechanics MUST NOT fire but a one-time load to consult the `dialectic-resolutions.md` schema is acceptable when the orchestrator does not already have the schema in context.
- `Makefile`: new `test-references-headers` target wired into `.PHONY` and the `test-harnesses` aggregate.
- `agent-lint.toml`: new exclude entry for `scripts/test-references-headers.sh` with documenting comment block; existing `test-implement-structure.sh` comment retargeted to drop the triplet-ownership claim and cite the new harness.

## [5.2.6] - 2026-04-21

### Added

- `scripts/test-review-structure.sh` + sibling contract `scripts/test-review-structure.md` — structural regression guard for `skills/review/SKILL.md` and `skills/review/references/` (closes #306). Eight assertions: SKILL.md + references dir exist; baseline refs (`domain-rules.md`, `voting.md`) exist; every `references/*.md` file on disk is named on a `MANDATORY — READ ENTIRE FILE` line in SKILL.md via a `references/<basename>` path-token form with non-filename/EOL boundary (prevents suffix/name-containing-name false-pass); baseline refs appear on a MANDATORY line (distinct diagnostic); CI-parity focus-area enum check (every `code-quality / risk-integration / correctness / architecture` line also contains `security` — mirrors agent-sync `UNQUOTED_FILES` loop); anti-halt banner and micro-reminder substrings pinned (intentional overlap with `test-anti-halt-banners.sh` for single-file fail locality); each reference opens with `**Consumer**:` and `**Binding convention**:` in the first 20 lines (the `/review` native 2-line header schema, deliberately NOT the `/implement` triplet). Wired into `Makefile` `test-harnesses` target and `agent-lint.toml` exclude list.

## [5.2.5] - 2026-04-21

### Changed

- `/research` SKILL.md refactored via progressive disclosure. `skills/research/SKILL.md` shrinks from 357 to 174 lines (-183 lines, -14.1 KB) by extracting Step 1 and Step 2 bodies into new references: `skills/research/references/research-phase.md` owns the 3-lane research invariant banner, `RESEARCH_PROMPT` literal, Cursor/Codex launch blocks with per-slot Claude subagent fallbacks, Claude inline-research independence rule, Step 1.3 `COLLECT_ARGS` / zero-externals branch / Runtime Timeout Fallback pointer, and Step 1.4 synthesis requirements. `skills/research/references/validation-phase.md` owns the 3-lane validation invariant banner, Cursor/Codex validation launches with long reviewer prompts, the Claude Code Reviewer subagent archetype with research-validation variable bindings (`{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` XML wrap / `{OUTPUT_INSTRUCTION}`), process-Claude-findings-immediately rule, Step 2.4 collection / zero-externals / runtime-timeout replacement, negotiation delegation, and Finalize Validation procedure. Each reference is loaded via a single `MANDATORY — READ ENTIRE FILE` directive with reciprocal `Do NOT load` guard on the other phase's reference on the same line. Behavior-preserving: frontmatter, hooks, anti-halt banner (`**Anti-halt continuation reminder.**` + `Continue after child returns` substring), Step Name Registry, `RESEARCH_PROMPT` literal, and reviewer XML wrapper tags all preserved byte-identical and pinned by the new harness. Adds `scripts/test-research-structure.sh` (six assertions: reference files exist; each named on a `MANDATORY — READ ENTIRE FILE` line that also carries the reciprocal `Do NOT load` guard; each reference opens with the `**Consumer**:` / `**Contract**:` / `**When to load**:` header triplet in its first 20 lines; `RESEARCH_PROMPT` byte-pin; reviewer XML wrapper tags byte-pin) plus sibling contract `test-research-structure.md`. Wired into `Makefile` `test-harnesses` target and excluded from `agent-lint.toml` S030. Existing harnesses (`make test-anti-halt`, `make test-lint-skill-invocations`, `make test-deny-edit-write`, `make agent-lint`) pass unchanged.

## [5.2.4] - 2026-04-21

### Changed

- `/review` SKILL.md refactored via progressive disclosure. `skills/review/SKILL.md` shrinks from 298 to 259 lines (-39 lines, -3.8 KB) by extracting two cohesive blocks into new references: `skills/review/references/voting.md` owns the Step 3c.1 round-1 voting panel mechanics (3-voter setup, ballot file rule, threshold + competition scoring, OOS-accepted artifact write, save-not-accepted IDs) and is loaded via MANDATORY READ inside the round-1 branch with a Do-NOT-load guard for rounds 2+ and the Step 3b zero-findings short-circuit; `skills/review/references/domain-rules.md` owns the Settings.json permissions ordering and skill/script genericity rules and is loaded via MANDATORY READ at Step 3 entry unconditionally (the rules must remain visible during the zero-findings short-circuit). Behavior-preserving: all harness-asserted literals stay inline in SKILL.md byte-identical (`**Anti-halt continuation reminder.**` banner, `Continue after child returns` micro-reminder, the focus-area enum `code-quality / risk-integration / correctness / architecture / security` on both Cursor and Codex prompt lines that `.github/workflows/ci.yaml` greps for). Existing harnesses (`make test-anti-halt`, `make test-orchestrator-scope-sync`, the CI `agent-sync` job) pass unchanged.

## [5.2.3] - 2026-04-21

### Changed

- `/compress-skill` now delegates to `/imaq` so compression changes ship as a PR instead of being written to the working tree in place. `skills/compress-skill/SKILL.md` is rewritten as a thin delegator (parse args → build feature description → delegate to `/imaq`), mirroring the `/simplify-skill` pattern; the actual file-by-file prose rewrite happens inside `/implement`'s Step 2. Adds `skills/compress-skill/scripts/build-feature-description.sh` as the coordinator (resolver with four probe paths, transitive `.md` discovery via `discover-md-set.sh`, baseline byte/line snapshot, self-contained feature description embedding the Strunk & White style guide, anti-patterns, per-file judgment rules, and PR-body `## Token budget` requirement) plus its sibling contract `build-feature-description.md`. Deletes `setup.sh`, `measure-set.sh`, and `report-deltas.sh` (subsumed / no longer needed now that the delta report is produced inside the PR body). Updates `README.md` and `docs/workflow-lifecycle.md` catalog entries.

## [5.2.2] - 2026-04-21

### Changed

- Two prose paragraphs in `skills/implement/SKILL.md` compressed via Strunk & White rewrites (omit-needless-words). Affects the Cross-Skill Health Propagation trailer sentence and the `oos-accepted-main-agent.md` create-on-missing paragraph. Structure, code references, modals, and technical content preserved verbatim; -101 bytes, no line-count change.

## [5.2.1] - 2026-04-21

### Changed

- `/design` SKILL.md refactored via progressive disclosure. `skills/design/SKILL.md` shrinks from 655 to 431 lines (~34%) by: extracting the four external sketch-launch Bash blocks + spawn-order rule + per-slot fallback notes + Claude General sketch independence rule to new `skills/design/references/sketch-launch.md`; extracting the interactive-branch bodies of Steps 1c, 1d, 3.5, and 3a to new `skills/design/references/discussion-rounds.md` (loaded via MANDATORY only when `auto_mode=false`); absorbing the Step 3 Claude subagent archetype + Collecting External Reviewer Results + Voting Panel launch-order + Finalize Plan Review + Track Rejected Plan Review Findings sections into the existing `skills/design/references/plan-review.md`. Behavior-preserving: all harness-asserted literals preserved byte-identically (flag MANDATORY pointer above `## Step 0`, both Step 2a.5 Do-NOT-Load guards, Step Name Registry rows, Anti-patterns NEVER titles, `## Step 0 — Session Setup` heading, focus-area enum on SKILL.md). The two Step 3 external reviewer Bash blocks (Cursor + Codex) remain inline in SKILL.md because `.github/workflows/ci.yaml` greps them for the focus-area enum. `scripts/test-design-structure.sh` + `scripts/test-subskill-anchors.sh` pass unchanged.

## [5.2.0] - 2026-04-21

### Added

- `/compress-skill` — new skill that rewrites an existing skill's Markdown prose to reduce size while preserving meaning. Discovers the transitive `.md` set via BFS from `SKILL.md`, following both inline Markdown links and path-shaped backticked references (e.g. `` `${CLAUDE_PLUGIN_ROOT}/skills/<name>/references/foo.md` ``), restricted to the skill's own directory tree so shared docs and callee sub-skills are excluded. Applies Strunk & White's *Elements of Style* adapted for technical writing — preserves YAML frontmatter, fenced code blocks, headings, link targets, inline code, file paths, and numeric values verbatim; only prose is rewritten. Emits a per-file before/after byte and line delta report. Standalone skill — does not delegate to `/im`. Adds `skills/compress-skill/` with `SKILL.md` plus four scripts (`setup.sh`, `discover-md-set.sh`/`.py`, `measure-set.sh`, `report-deltas.sh`); wires `Skill(compress-skill)` / `Skill(larch:compress-skill)` / `Bash($PWD/skills/compress-skill/scripts/*)` into `.claude/settings.json`; updates `README.md` (installation blurb, Skills catalog row, strict-permissions example) and `docs/workflow-lifecycle.md` (Standalone Usage entry).

## [5.1.4] - 2026-04-21

### Fixed

- `/simplify-skill` resolver (`skills/simplify-skill/scripts/build-feature-description.sh`) now probes `$PWD/skills/<name>/SKILL.md` as priority 2, between the existing `${CLAUDE_PLUGIN_ROOT}/skills/` and `$PWD/.claude/skills/` probes. Previously, invoking `/simplify-skill` from inside the larch plugin repo itself (cwd is the plugin repo with a `skills/<name>/SKILL.md` layout, and `CLAUDE_PLUGIN_ROOT` unset in the helper subshell) failed with `STATUS=not_found`. The `STATUS=not_found` error message now lists all four probed paths. `skills/simplify-skill/SKILL.md` NEVER #2 prose is updated to name the three probe locations the resolver covers.

## [5.1.3] - 2026-04-21

### Changed

- `AGENTS.md` shrinks from 44k to 4.4k chars (10x reduction). Per-script and test-harness contract bullets under `## Editing rules` move verbatim to sibling `<basename>.md` files co-located with each primary script (e.g., `scripts/redact-secrets.md` beside `scripts/redact-secrets.sh`); 22 new sibling `.md` files are created under `scripts/`, `skills/issue/scripts/`, `skills/fix-issue/scripts/`, `skills/create-skill/scripts/`, and `skills/simplify-skill/scripts/`. AGENTS.md keeps only cross-cutting rules, Common editing tasks, the Canonical sources list (preserved verbatim to satisfy `scripts/test-post-scaffold-hints.sh`'s literal assertion), Conventions, plus a new co-location convention sentence under Editing rules. Canonical-.md-source bullets move into their respective canonical files as trailing "Update triggers" sections in `skills/shared/reviewer-templates.md`, `skills/shared/subskill-invocation.md`, and `skills/shared/skill-design-principles.md` — no sibling `.md` is created for an `.md` file. Stale prose pointers updated in `skills/shared/skill-design-principles.md:39` (owning-contract-doc pattern acknowledged), `skills/shared/subskill-invocation.md:191` (§ Editing rules → § Canonical sources), and 14 comment occurrences in `agent-lint.toml`. `scripts/test-implement-structure.sh` comments cite sibling `.md`. Five skill-local sibling `.md` files added to `agent-lint.toml` exclude list (S030/orphaned-skill-files).

## [5.1.2] - 2026-04-21

### Removed

- `CLAUDE.md`: delete the stale `All output caveman full.` instruction. The caveman plugin was uninstalled, so the directive no longer matches any available plugin and was incorrectly forcing caveman-style output in every session.

## [5.1.1] - 2026-04-21

### Changed

- CI split: `make lint` is now composed of two split targets, `lint-only` (pre-commit over all files) and `test-harnesses` (the 22 `test-*` bash regression harnesses). `.github/workflows/ci.yaml` replaces the single `lint` job with two parallel jobs (`lint` → `make lint-only` and `test-harnesses` → `make test-harnesses`) so harness regressions and linter regressions surface on independent job tiles and can be re-run independently. Local `make lint` behavior is unchanged.

## [5.1.0] - 2026-04-21

### Added

- `/simplify-skill <skill-name>` — new pure-delegator skill that refactors an existing larch skill for stronger adherence to `skills/shared/skill-design-principles.md` and reduced SKILL.md token footprint. Resolves the target skill directory, enumerates in-scope `.md` files (excluding `scripts/`, `tests/`, sibling sub-skills invoked via the `Skill` tool, and `skills/shared/`), and delegates a pinned behavior-preserving refactor feature description to `/im`. PR body includes a `## Token budget` section tracking SKILL.md line/char deltas.
- `skills/simplify-skill/scripts/build-feature-description.sh` — helper that validates the target name (bare form, no plugin-qualified `<a>:<b>` shape), resolves the target dir (plugin tree first, then consumer `.claude/skills/`, then `${CLAUDE_PLUGIN_ROOT}/.claude/skills/`), fail-closes on enumeration errors, and emits the full feature-description prose to a temp file. `/im` receives the prose as its `args`.

### Changed

- `scripts/test-anti-halt-banners.sh` `DELEGATORS` array + `skills/shared/subskill-invocation.md` `### Scope list` "banner MUST NOT appear" list + "Pure forwarders" parentheticals all extended with `skills/simplify-skill/SKILL.md`. Cross-validated by `scripts/test-orchestrator-scope-sync.sh`.
- `docs/workflow-lifecycle.md` Delegation Topology mermaid + bullet list + Standalone Usage bullet now document `/simplify-skill`. Exempt-list parentheticals also pick up `/loop-improve-skill` (pre-existing doc gap closed while that line was open for editing).

## [5.0.7] - 2026-04-21

### Changed

- Revert the bulk caveman-style prose compression released in 5.0.6 (restore ~50 `.md` files under `skills/`, `docs/`, `tests/fixtures/`, `.claude/skills/`, plus `AGENTS.md` and `README.md` to their pre-5.0.6 prose) and restore the stricter forms of the three accompanying harness loosenings: `scripts/lint-skill-invocations.py` again requires the canonical `Invoke the Skill tool` / `via the Skill tool` phrases (no shortened variants); `scripts/test-design-structure.sh` again requires `All 4 keys are required` with the `are` connective; `scripts/test-orchestrator-scope-sync.sh` again requires the `The` prefix on scope-list intro sentences. `agents/code-reviewer.md` is regenerated from the reverted (uncompressed) `skills/shared/reviewer-templates.md`. Additionally, the `caveman@caveman` plugin entry and the `caveman` entry in `extraKnownMarketplaces` are removed from `.claude/settings.json` (dev-only settings — no runtime surface impact).

## [5.0.6] - 2026-04-21

### Changed

- Bulk caveman-style prose compression across ~50 `.md` files under `skills/` (except `skills/implement/SKILL.md` and `skills/design/SKILL.md`, kept uncompressed for readability of the two critical orchestrator skills), `docs/`, `tests/fixtures/`, `.claude/skills/`, plus `AGENTS.md` and `README.md`. Technical content (code fences, URLs, frontmatter, file paths, quoted error strings) preserved verbatim. Accompanying harness loosenings keep CI green against the compressed forms: `scripts/lint-skill-invocations.py` accepts `Invoke Skill tool` / `Call the Skill tool` / `Call Skill tool` / `via Skill tool` variants in addition to the original canonical phrases; `scripts/test-design-structure.sh` accepts `All 4 keys required` without the `are` connective; `scripts/test-orchestrator-scope-sync.sh` accepts the scope-list intro sentences with or without the leading `The` prefix (case-insensitive `B|b`). `agents/code-reviewer.md` is regenerated from the unchanged `GENERATED_BODY` block of `skills/shared/reviewer-templates.md` (the template's surrounding prose is compressed, but the generator-extracted block is not — keeps the agent file byte-identical to generator output so the `agent-sync` CI gate stays green).

## [5.0.5] - 2026-04-21

### Changed

- `/loop-improve-skill`: stream driver output live via `Monitor` (closes #291). SKILL.md flips the synchronous foreground driver launch to `run_in_background=true` with combined stdout/stderr redirected to a stable log file under `/tmp/` (env-overridable via `LOOP_DRIVER_LOG_FILE`, validated to `/tmp/` or `/private/tmp/` prefix with `..`-component rejection), then attaches `Monitor` (`persistent: true`) tailing the file with `grep --line-buffered -E '^(✅|> **🔶|**⚠)'`. Log path is surfaced to the user via a visible `📄 Full driver log: <path>` line before Monitor attaches and re-emitted on completion, so the full unfiltered output stays accessible post-run. Path resolution uses a single synchronous Bash call emitting `RESOLVED_LOG_FILE=<path>` since Bash tool calls do not share shell state. Driver.sh is byte-identical; skill remains a pure DELEGATOR (anti-halt banner-free). Companion updates: `AGENTS.md` + `SECURITY.md` describe the new `Bash, Monitor` tool surface and log-file retention boundary (outside `LOOP_TMPDIR`, under `/tmp/` only); `scripts/test-loop-improve-skill-halt-rate.sh` extracts the driver-log path from `claude -p` stdout and reads breadcrumbs from that file via a new `extract_driver_log_path()` helper; new structural harness `scripts/test-loop-improve-skill-skill-md.sh` wired into `make lint` asserts frontmatter, visible log-path lines, the byte-verbatim filter literal, and filter/driver breadcrumb-helper parity; `agent-lint.toml` globally suppresses `tools-unknown` (S040) because agent-lint 2.3.2's registry predates the `Monitor` tool — removal trigger documented.

## [5.0.4] - 2026-04-21

### Changed

- `/create-skill`: prose-only improvement along six skill-judge dimensions of `skills/create-skill/SKILL.md`. Adds `## Design Mindset` (expert pre-scaffold prompts keyed to real forks), `## Anti-patterns` (8 NEVER bullets grounded in `/create-skill` pipeline failures), `## Decision Tables` (path mode + template + troubleshooting + skill-tool resolution), replaces the thin `## Principles` pointer with a `MANDATORY — READ ENTIRE FILE` directive plus two chronologically-ordered `Do NOT Load` branches, rewrites the frontmatter `description:` within the 250-char agent-lint cap, and trims the Step 3 `/im` feature-description template by dropping the `--plugin` enumeration block already emitted by `post-scaffold-hints.sh`. No scripts or references/ layer touched; Pattern A invocation block byte-stable (cited by `skills/shared/subskill-invocation.md`); delegator classification preserved.

## [5.0.3] - 2026-04-21

### Added

- `scripts/test-orchestrator-scope-sync.sh` — cross-validation harness that asserts exact set equality between the `ORCHESTRATORS`/`DELEGATORS` bash arrays in `scripts/test-anti-halt-banners.sh` and the bulleted scope lists under `### Scope list` in `skills/shared/subskill-invocation.md`. Fail-closed on empty parse; symmetric-diff output on drift. Wired into `make lint` via the `test-orchestrator-scope-sync` target (closes #285).

### Fixed

- `skills/shared/subskill-invocation.md`: aligned `## Post-invocation verification` pure-forwarders list (added `/loop-improve-skill`), `## Anti-halt continuation reminder` stateful-orchestrators list (added `/research`), and `## allowed-tools narrowing heuristic` hybrid-orchestrator example row (added `skills/research/SKILL.md`) with the `### Scope list` enumerations.
- `skills/create-skill/scripts/render-skill-md.sh`: added `/loop-improve-skill` to the pure-delegators exempt list in both scaffold variants (lines 157, 195).
- `AGENTS.md`: corrected the `test-anti-halt-banners.sh` orchestrator cardinality from "seven" to "six" to match the live `ORCHESTRATORS` array.

## [5.0.2] - 2026-04-21

### Changed

- `/fix-issue` Step 2 lock now deletes the `GO` comment (instead of leaving it alongside `IN PROGRESS`). `issue-lifecycle.sh comment --lock` captures the GO comment's id + `created_at`, deletes the comment via `DELETE /repos/{owner}/{repo}/issues/comments/{id}`, posts `IN PROGRESS`, and uses the captured timestamp (not a surviving GO anchor) for the concurrent-race duplicate-`IN PROGRESS` post-check. Recovery semantics updated for the crash-between-delete-and-post scenario.

## [5.0.1] - 2026-04-21

### Fixed

- `skills/loop-improve-skill/scripts/driver.sh`: derive `CLAUDE_PLUGIN_ROOT` from the script's own location when the harness did not export it, so the driver no longer aborts at Step 2 session-setup under `set -u` when invoked as a Skill (closes #288).

## [5.0.0] - 2026-04-21

### Changed

- `/loop-improve-skill` rewritten as bash-driver topology per umbrella #273. **BREAKING**: removes the inner skill `/loop-improve-skill-iter` (hard delete). Driver at `skills/loop-improve-skill/scripts/driver.sh` invokes each child skill (`/skill-judge`, `/design`, `/im`) as a fresh `claude -p` subprocess, eliminating the ~70%+ halt rate previously observed at inner Step 3.j between child-return and post-call Bash. Halt class eliminated by construction.

### Removed

- `skills/loop-improve-skill-iter/` — inner single-iteration skill superseded by bash driver (#273).
- `scripts/test-loop-improve-skill-continuation.sh` — regression harness for the split-skill topology, retired.

### Added

- `skills/loop-improve-skill/scripts/driver.sh` — bash driver owning loop control, subprocess invocation, grade parsing, audit-trail posting, infeasibility detection.
- `scripts/test-loop-improve-skill-driver.sh` — structural + behavioral regression harness for the driver, wired into `make lint` via `test-loop-improve-skill-driver` target.

### Notes

- Observability tradeoff: partial runs are no longer resumable via sentinel ledger (halt class eliminated → resume machinery unnecessary). See SECURITY.md and docs/workflow-lifecycle.md.

## [4.3.17] - 2026-04-21

### Added

- `scripts/test-loop-improve-skill-halt-rate.sh`, `scripts/lib-loop-improve-halt-ledger.sh`, `tests/fixtures/loop-halt-rate/`, plus `Makefile` `halt-rate-probe` / `test-lib-halt-ledger` targets and a README subsection — opt-in halt-rate regression harness for `/larch:loop-improve-skill` (closes #278 under halt-problem umbrella #273). Probe invokes the skill end-to-end N times against a throwaway fixture skill, parses outer's `✅ 5: close out` breadcrumb as primary classifier (filesystem sentinel forensics only for `halt_mid_turn` survivors), and emits `HALT_RATE` + `MEASURED_RUNS` + `PROBE_STATUS` + per-status + per-location breakdowns. Per-run isolation via `mktemp -d` scratch with bare-origin git provisioning and PATH-shimmed `gh`; `timeout --kill-after` wrapper handles both exit 124 and SIGKILL-escalation exit 137. Missing `claude` binary exits non-zero per #278 contract. Not wired into `make lint` (opt-in only).

## [4.3.16] - 2026-04-20

### Fixed

- `skills/loop-improve-skill-iter/SKILL.md` — Step 3.j now runs a three-state idempotency machine keyed on the on-disk ledger (State A `3j.done` non-empty skips entirely; State B armed-marker + `3j.done` absent + `$JUDGE_OUT` non-empty reuses captured judge output and runs only the post-call gh-comment + sentinel write; State C otherwise runs the full path, writing `iter-${ITER}-3j-armed.marker` in its own pre-invocation Bash block before the Skill-tool call). Previously a halt between Skill-tool return and the post-call Bash block that writes `3j.done` caused resume to re-invoke `/skill-judge` (duplicate expensive judge work + duplicate `gh issue comment`). `scripts/test-loop-improve-skill-continuation.sh` gains a line-order assertion that mechanically enforces the State C "armed marker before Skill call" invariant (needle anchored on the redirect-target shape `> "$LOOP_TMPDIR/iter-${ITER}-3j-armed.marker"`, unique to the pre-invocation printf write). `AGENTS.md` bullet enumerates the new sentinel and describes the ordering assertion. Closes #262.

## [4.3.14] - 2026-04-20

### Fixed

- `README.md` — `/loop-improve-skill` feature-matrix row loop-exit enumeration was missing the outer sentinel-gate `VERIFIED=false` halt-detected branch (handled in outer SKILL.md Step 4.v); `docs/workflow-lifecycle.md` line 41 was already complete. Appended one sentence citing `verify-skill-called.sh --sentinel-file` so the two enumerations agree. Closes #261.

## [4.3.13] - 2026-04-20

### Fixed

- `scripts/git-amend-add.sh` — header comment on line 5 carried a stale "/implement Step 8a + Rebase + Re-bump Sub-procedure step 4a" anchor pointing at the pre-extraction SKILL.md inline home. Appended the parenthetical `(skills/implement/references/rebase-rebump-subprocedure.md)` on the following line, matching the pattern used by the four headers fixed under #235. Closes #249.

## [4.3.12] - 2026-04-20

### Fixed

- `skills/loop-improve-skill/SKILL.md` — outer Step 4.v `VERIFIED=false` branch now scans `$LOOP_TMPDIR` for per-substep `.done` sentinels (`3j`, `3jv`, `3d-pre-detect`, `3d-post-detect`, `3d-plan-post`, `3i`) and emits an enriched `EXIT_REASON` with a 7-way halt-location clause pinpointing which substep the inner iteration halted at. Converts the previously-opaque "iteration sentinel missing" diagnostic into an observable halt-location surfaced in the close-out comment. The `LAST_COMPLETED=none` clause disambiguates halt-before-/skill-judge from argument-validation failure via REASON token. Harness extended to assert all 7 halt-location clauses against drift. Closes #247.

## [4.3.11] - 2026-04-20

### Fixed

- `scripts/test-implement-structure.sh` — assertion (8) previously iterated the hard-coded `expected_refs` array when checking the `**Consumer**:` / `**Contract**:` / `**When to load**:` header triplet, so a new `skills/implement/references/*.md` added without the triplet would slip through CI unvalidated. Replaced with the `shopt -s nullglob` + `"$REFS_DIR"/*.md` + basename-in-message pattern used by assertion (9), and added the parallel "no .md files found" guard. Assertion (7) (canonical four-file presence check) is unchanged. Header and block comments updated to drop the "four hard-coded" implication. Closes #252.

## [4.3.10] - 2026-04-20

### Changed

- `.claude/skills/relevant-checks/SKILL.md` — polish pass from `/loop-improve-skill` iter-3 (#245): `## Mindset` gains two additional paragraphs — a "doc DESCRIBES behavior, does NOT define policy" guardrail encoding the governing constraint explicitly, and a "Re-run after structural edits" frame capturing the full-repo-phase escalation discipline for cross-file invariants that the changed-file phase cannot detect. The third NEVER bullet's inline `(a)(b)(c)` enumeration of reduced-coverage exit-0 cases is converted to a 3-row micro-table (Case / Observable signal / Coverage implication) for triage-time scan-ability. Doc-only.

## [4.3.9] - 2026-04-20

### Fixed

- `scripts/test-implement-structure.sh` — assertion (9) regex `see Step [0-9]+[a-z.]* (below|above)` could not consume a digit after the `a.` segment, so dotted substep back-references like `see Step 9a.1 below` or `see Step 3c.2 above` evaded the guard (`/implement` already uses dotted substep numbering). Broaden the step-number token to `[0-9][0-9a-z.]*` so bare digits, letter-suffix forms, and dotted substep forms are all caught; the narrow guard (direction word required) is preserved. Closes #253.

## [4.3.8] - 2026-04-20

### Fixed

- `scripts/test-check-bump-version.sh` — Section 5 body comments cited `skills/implement/SKILL.md Rebase + Re-bump Sub-procedure step 4` (line 383 call-site example) and `SKILL.md step 4 "Pre-check STATUS guard"` (lines 430-431 test rationale), but PR #229 extracted the sub-procedure to `skills/implement/references/rebase-rebump-subprocedure.md`. Replace both with the canonical `rebase-rebump-subprocedure.md step 4` anchor. Prose-only; zero runtime behavior change. Same class of stale anchor as #235 (which targeted 4 script headers) but in a test-script body comment that was deliberately left out of #235's enumerated scope. Closes #248.

## [4.3.7] - 2026-04-20

### Changed

- `.claude/skills/relevant-checks/SKILL.md` — polish pass from `/loop-improve-skill` iter-2 (#245): frontmatter description gains `pre-commit` and `agent-lint` as explicit trigger tokens and scopes "modified files" to the pre-commit phase only; `## Mindset` gains a **Maintenance rule** paragraph covering observable banners, exit paths, `WARNING:`/`ERROR:` lines, and script comment labels / branch names (e.g., the `files[] empty but MODIFIED_FILES non-empty` branch); `## How it works` drops the inline 5-bullet linter roster (which was incomplete — missing `lint-skill-invocations` and `agent-lint`) in favour of a single pointer to `.pre-commit-config.yaml`. Doc-only; `scripts/run-checks.sh` untouched.

## [4.3.6] - 2026-04-20

### Changed

- `/loop-improve-skill` + `/loop-improve-skill-iter` — termination contract is now grade-gated: the loop strives for per-dimension grade A on every `/skill-judge` dimension D1..D8 (integer thresholds D1>=18/20, D2-D6+D8>=14/15, D7>=9/10) and exits happy when achieved. The three existing halt paths (`no_plan` / `design_refusal` / `im_verification_failed`) are now treated as infeasibility halts that MUST produce a written justification (`iter-${ITER}-infeasibility.md`); on iter-cap the outer's Step 5 runs one final `/skill-judge` for post-cap grade capture and may reclassify as a happy post-cap-A exit. The close-out tracking-issue comment becomes a multi-section body (summary + Grade History + Infeasibility Justification + Final Assessment). New shared parser `scripts/parse-skill-judge-grade.sh` (fail-closed contract: any non-ok PARSE_STATUS forces GRADE_A=false; bash 3.2 compatible) with companion 17-case harness `scripts/test-parse-skill-judge-grade.sh` wired into `make lint`. The `/design` prompt at Step 3.d now includes a Non-A dimensions focus block listing per-dim deficits when grade parsing succeeds — directly counters the historical failure mode where Non-A findings were deemed "not worth implementing". Preserves: iter cap 10, per-iter sentinel verification, security boundaries, exactly-one anti-halt banner per SKILL.md, #231 halt-detection, idempotent resume.

## [4.3.5] - 2026-04-20

### Changed

- `.claude/skills/relevant-checks/SKILL.md` — added `## Mindset` frame (phase-based changed-file vs full-repo split), `## Failure-mode taxonomy` 4-row decision table keyed to observable `run-checks.sh` banners and exit paths, and `## Anti-patterns (NEVER)` section with three bullets (no `--no-verify` bypass, deletions-only branches still run the full-repo phase, exit 0 does not guarantee every phase ran — enumerates the three reduced-coverage exit-0 outcomes). Trimmed the `/lint, /test, /format` migration note from the frontmatter description. Appended one sentence to `## How it works` naming `.pre-commit-config.yaml` as the authoritative hook catalogue. Doc-only — no changes to `scripts/run-checks.sh`. Part of the iterative `/loop-improve-skill` pass on `/relevant-checks` (closes #245).

## [4.3.4] - 2026-04-20

### Added

- `scripts/test-implement-structure.sh` — structural regression harness for `skills/implement/SKILL.md` and `skills/implement/references/` topology (closes #234). Nine assertions: three top-level headings (Load-Bearing Invariants / NEVER List / Rebase Checkpoint Macro), MANDATORY occurrence floor + per-reference filename binding, three byte-pinned verbosity literals, CI-parity focus-area enum check (mirrors `.github/workflows/ci.yaml` `agent-sync` job per-line enforcement), four expected `references/*.md` files exist, Consumer/Contract/When-to-load header triplet on every reference, and zero `see Step N below|above` patterns (case-insensitive) in any `references/*.md`. Wired into `make lint` via new `test-implement-structure` target. Companion to `scripts/test-implement-rebase-macro.sh`: macro harness owns Rebase Checkpoint Macro placement/registry; this harness owns top-level headings, MANDATORY ↔ reference binding, focus-area CI-parity, contract headers, and progressive-disclosure invariants in references/*.md.

## [4.3.3] - 2026-04-20

### Fixed

- `scripts/lib-count-commits.sh`, `scripts/check-bump-version.sh`, `scripts/git-force-push.sh`, `scripts/git-sync-local-main.sh` — header comments cited `skills/implement/SKILL.md` as the inline home of the Rebase + Re-bump Sub-procedure, but PR #229 extracted it to `skills/implement/references/rebase-rebump-subprocedure.md`. Append the reference-file path as a parenthetical anchor adjacent to each existing step-number citation (preserving step numbers 3/4/5 which map 1:1 to the extracted file's numbering). Prose-only; zero runtime behavior change. Also makes `check-bump-version.sh`'s header carry an explicit `step 4` anchor so it matches the `step N (path)` pattern of the other three headers (plan-review FINDING_2, 2 YES / 1 NO). Closes #235.

## [4.3.1] - 2026-04-20

### Fixed

- `.claude/skills/bump-version/scripts/classify-bump.sh` — fix silent SIGPIPE 141 abort on large SKILL.md files. The `extract_frontmatter` awk function exits after matching the closing `---` frontmatter delimiter; `printf '%s\n' "$FILE" | extract_frontmatter` then receives SIGPIPE while still writing hundreds of KB on large files. Under `set -euo pipefail` the pipefail-propagated 141 silently aborted the whole script with no stdout and no stderr, causing `/implement` Step 8 to misclassify the bump. Replaces the pipe with a herestring (`extract_frontmatter <<< "$FILE"`) so awk reads from stdin without an intermediate writer that can be SIGPIPE-killed; awk function body unchanged. The four subsequent `printf | awk` extractions for `OLD_NAME`/`NEW_NAME`/`OLD_ARG_HINT`/`NEW_ARG_HINT` operate on already-extracted small frontmatter blocks (well under the 64KB pipe buffer) and do not trigger the bug — left as-is. Closes #240.

## [4.3.0] - 2026-04-20

### Added

- `/loop-improve-skill-iter` — new inner skill that runs exactly one `/skill-judge` → `/design` → `/im` iteration for a target skill. Writes a per-substep `.done` sentinel ledger under a caller-supplied `LOOP_TMPDIR` (validated as under `/tmp/` or `/private/tmp/` with `..` rejection) and emits `ITER_STATUS=<value>` plus a non-empty completion sentinel. Invoked only by `/loop-improve-skill` via the Skill tool — not a standalone user-facing skill.

### Changed

- `/loop-improve-skill` — refactored into an outer loop controller that delegates each of up to 10 improvement rounds to `/loop-improve-skill-iter`. After each inner return, a mechanical `scripts/verify-skill-called.sh --sentinel-file` gate reads the inner's non-empty completion sentinel. This converts the old "parent halted after child returned" failure mode (issue #231) into an observable missing-sentinel diagnostic with a specific `EXIT_REASON`. New `scripts/test-loop-improve-skill-continuation.sh` structural lint (wired into `make lint`) asserts the split's gate + sentinel literals + banner-density cap in both SKILL.md files. `scripts/test-anti-halt-banners.sh` ORCHESTRATORS array and `skills/shared/subskill-invocation.md` Scope list updated with the new inner skill (D3-honoring Scope-list catalog sync — no new normative prose). Companion updates: `LARCH_RESERVED` in validate-args.sh, `.claude/settings.json` Skill permissions, README Skills catalog + strict-permissions snippet, `docs/workflow-lifecycle.md` topology, `AGENTS.md` canonical-source bullet, `agent-lint.toml` exclude. Closes #231.

## [4.2.14] - 2026-04-20

### Added

- `scripts/test-subskill-anchors.sh` — regression harness that verifies every backticked `` `<path>/SKILL.md § <heading>` `` citation in `skills/shared/subskill-invocation.md` resolves to a `## <heading>` or `### <heading>` line in the referenced file (exact string match via `grep -Fxq`, both `##` and `###` accepted, trailing whitespace tolerated on target lines). Fail-closed on parse/IO errors; fence-aware parser skips any 3+ backtick opener (including the doc's quadruple-backtick banner examples); minimum-citation floor of 10 guards against extractor regressions. Wired into `make lint` via a new `test-subskill-anchors` target; added to `agent-lint.toml` exclude list. Contract orthogonal to `scripts/lint-skill-invocations.py` (which enforces invocation wording). Also fixes 3 pre-existing citation drifts (`Step 6 — Implement` → `Step 6 — Execute`; `Step 9a.1 — Create OOS GitHub Issues` → `9a.1 — Create OOS GitHub Issues`; `Step 0` → `Step 0 — Session Setup`) and expands 2 continuation-shorthand citations to full-path form so all 14 citations resolve mechanically. Closes #236 (follow-up from #227 / PR #229).

## [4.2.13] - 2026-04-20

### Changed

- `/implement` — add `### Follow-up Work Principle` subsection at the top of `## Execution Issues Tracking` generalizing the rule: durable, actionable follow-up work identified during design, implementation, or review MUST be tracked as a GitHub issue (auto-filed via Step 9a.1 when the item fits the OOS pipeline, or manually via `/issue` otherwise) and the PR body references that issue — not buried as prose alone. Retitle the existing `Mandatory dual-write` subsection as `Mechanical enforcement of the principle: Pre-existing Code Issues dual-write` (schema, dedup rule, sanitize rule, worked example byte-identical); update two in-file cross-references to the new title. Add one reminder line pointing back to the principle inside the Implementation Deviations PR-body block (the three carve-out-covered blocks — Rejected Plan Review Suggestions, Rejected Code Review Suggestions, Non-accepted OOS observations — explicitly exclude the reminder to respect the voting panel's rejection decisions). Explicit carve-outs for non-accepted/rejected findings staying as PR-narrative, `repo_unavailable=true` as blocked-filing state for both auto and manual paths, and security findings routed exclusively through SECURITY.md's private disclosure flow. `skills/shared/voting-protocol.md:217` reframed to call the main-agent dual-write path the mechanical enforcement of the principle for the `Pre-existing Code Issues` category; trigger scope preserved (no mechanical extension). Closes #237.

## [4.2.12] - 2026-04-20

### Changed

- `/implement` — dedup 4 near-identical rebase-checkpoint blocks at Steps 1.r, 4.r, 7.r, 7a.r (~60 lines of duplication) into a single `## Rebase Checkpoint Macro` section parameterized on `<step-prefix>` and `<short-name>`. Each former block is now a single-line `Apply the Rebase Checkpoint Macro with ...` invocation. Preserves: uniform `debug_mode` gate at all 4 sites, three byte-pinned Verbosity Control literals, Step 7.r `FILES_CHANGED=true` guard at its call site, and byte-identical breadcrumb output (🔃 start, ⏩ debug, ✅ success). Macro procedure steps labeled M1-M4 to avoid collision with outer Step 0-18 numbering. New `scripts/test-implement-rebase-macro.sh` (wired into `make lint`) asserts 9 structural invariants (A-I) guarding the macro section, the 4 call-site registry rows, the 4 Apply invocations, the Verbosity Control literals, the Step 7.r guard placement, the macro placement between Verbosity Control and Step 0, the macro body's rebase-push invocation + bail string, the total rebase-push call-site counts (1 `--no-push --skip-if-pushed` + 2 plain `--no-push`), and the macro body's placeholder-pinned SKIPPED format strings. Closes #232 (follow-up to #227 / PR #229 FINDING_1).

## [4.2.11] - 2026-04-20

### Changed

- `/implement` — expand `description:` frontmatter with explicit trigger scenarios ("ship X", "land PR", "merge this"), keywords (CI-green squash-merge, version bump, Slack), and negative-space sibling pointers (`/research` read-only, `/design` plan, `/im` merge, `/imaq` auto-merge) to improve discoverability and disambiguate vs sibling skills. Stays within the 250-character S015 cap and preserves the "Use when..." trigger pattern required by agent-lint S017. `argument-hint:` and body retain full flag semantics (`--merge`, `--draft`). Closes #233 (follow-up to #227 / PR #229). No runtime behavior change.

## [4.2.10] - 2026-04-20

### Changed

- `/design` — strengthen `description:` frontmatter with additional trigger keywords (design, architecture planning, scope definition, approach validation) while preserving the "Use when..." trigger pattern required by agent-lint S017 and staying within the 250-character S015 cap. Closes the D4 Specification-Compliance nit from iteration-2 `/skill-judge` review (follow-up to PR #228; tracking issue #224). No runtime behavior change.

## [4.2.9] - 2026-04-20

### Changed

- `/design` — refactor SKILL.md per `/skill-judge` findings (Grade C → expected B). Three orthogonal edits: add a `## Design Mindset` section near the top transferring the orchestrator's thinking pattern via 5 "Before X, ask yourself" prompts; replace the 5 flag-description paragraphs with a compact 4-column table followed by a `MANDATORY` pointer to the new `skills/design/references/flags.md` (declared the single normative source), placed adjacent to the flag block before Step 0 so it is read before flag parsing begins; hybrid-extract Step 2a.5 — keep inline the GH#98 debate-phase carve-out, bucket assignment, and zero-externals guardrail while extracting per-decision rendering, parallel launch, collection, judge re-probe, ballot construction, judge launch, tally, and `dialectic-resolutions.md` writing to the new `skills/design/references/dialectic-execution.md`. Dual `Do NOT load` guards prevent debate-instruction leakage on the `NO_CONTESTED_DECISIONS` and zero-externals short-circuit paths. New `scripts/test-design-structure.sh` (wired into `make lint` via `test-design-structure`) asserts the four structural invariants: flag-MANDATORY placement before Step 0, dual skip-branch guards, `dialectic-execution.md` header MANDATORY naming `dialectic-debate.md`, and `references/flags.md` load-bearing literals (`--branch-info` 4-key rule + `--step-prefix` `::` delimiter). Updates `references/dialectic-debate.md` example line-refs from `SKILL.md:340` to `SKILL.md:1` (stable file-level pointer after refactor line drift).

## [4.2.8] - 2026-04-20

### Changed

- README.md — append a parenthetical pointer to `skills/shared/skill-design-principles.md` on the `/create-skill` catalog row so consumers reading the Skills feature matrix have a discovery path to the canonical skill-design principles doc. Closes #217.

## [4.2.7] - 2026-04-20

### Changed

- `/research` — relax the always-deny `scripts/deny-edit-write.sh` PreToolUse hook to a `/tmp`-only allow policy so `/research` may write scratch artifacts via `Write`/`Edit`/`NotebookEdit` and invoke `/issue` via the Skill tool (e.g., to file research-result issues). `allowed-tools` now lists `Skill, Write, Edit, NotebookEdit`; the hook is the sole mechanical enforcer of the `/tmp`-only confinement (residual risk if hook `permissionDecision` semantics vary by Claude Code version — see `SECURITY.md`). Hook mirrors `scripts/block-submodule-edit.sh`'s stdin-JSON / bounded-symlink-walk / `pwd -P` / jq-absent-printf-fallback discipline and handles macOS `/tmp` → `/private/tmp` aliasing; extraction uses a length-aware `map(select(type == "string" and length > 0))` selector so an empty `file_path` does not shadow a valid `notebook_path`. `/research` is registered as an orchestrator in `scripts/test-anti-halt-banners.sh` (banner + per-site micro-reminder). Updated `SECURITY.md`, `AGENTS.md`, `README.md`, `docs/workflow-lifecycle.md`. Test harness rewritten to a 13-case table-driven matrix (repo-deny, `/tmp` allow for new and existing files, traversal-deny, relative-deny, `notebook_path` allow/deny, empty-`file_path`-with-valid-`notebook_path` allow, fail-closed empty-path deny, malformed-JSON deny, idempotency, jq-absent byte-identity). Closes #215.

## [4.2.6] - 2026-04-20

### Changed

- `skills/create-skill/scripts/render-skill-md.sh` — emit a single-line pointer to `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` at the top of both scaffold body variants (multi-step and minimal), right after the opening TODO HTML comment, so scaffold authors encounter the canonical principles doc at creation time. `skills/create-skill/scripts/test-render-skill-md.sh` — add contract assertion (7) guarding regression and reusing the empty-plugin-token rooted-path guard. Closes #216.

## [4.2.5] - 2026-04-20

### Fixed

- `/loop-improve-skill` — prevent silent exit after iteration 1 on minor `/skill-judge` findings or self-judged token/context budget pressure (closes #214). Expanded top banner with an **Anti-self-curtailment** clause enumerating the four authoritative exits. Strengthened Step 3.d's `/design` prompt with three contract clauses requiring a plan for minor/nit findings, forbidding budget-based self-curtailment, and forbidding no-plan sentinels when findings exist. Tightened the no-plan sentinel detector so a first-line sentinel match is terminal only when no structured plan marker (`^#{1,6}\s`, `^[1-9]\d?\.\s`, `^[-*+]\s`) follows — the 5 sentinel strings remain byte-identical. Added a one-shot rescue re-invocation of `/design --auto` when the first response is non-empty, non-sentinel, non-refusal prose with no plan shape; replacement semantics ensure at most one plan comment per iteration. Added explicit Step 3.d ordering invariant and a dedicated `EXIT_REASON` for the `/design` refusal/error exit.

## [4.2.4] - 2026-04-20

### Changed

- `/create-skill` — factor the inline `## Principles` section into a new canonical doc at `skills/shared/skill-design-principles.md` (~120 lines, 9 sections) merging the battle-tested larch A/B/C mechanical rules with higher-level principles extrapolated from the `skill-judge` and `skill-creator` plugins (knowledge delta, progressive disclosure, anti-patterns with WHY, description-as-activation-surface, freedom calibration, pattern recognition, verifiable quality criteria). The new doc declares Section III (larch mechanical rules) overrides Section IV (general writing-style guidance) to resolve the collision between `skill-creator`'s "avoid rigid MUSTs" advice and larch's harness-enforced A/B/C invariants.
- `skills/create-skill/SKILL.md` — body `## Principles` shrinks to a pointer paragraph (heading preserved for grep friendliness); Step 3 `/im` feature-description template keeps the compact A/B/C one-liners (HYBRID resolution from dialectic — mechanical invariants survive context pressure) AND adds an explicit `MUST read skills/shared/skill-design-principles.md (full file) before writing any code` line; replaces the stale `sourced from /create-skill's ## Principles section` attribution with the full `${CLAUDE_PLUGIN_ROOT}` path to the new doc.
- `AGENTS.md` — add an Editing-rules bullet for `skills/shared/skill-design-principles.md` (scope, precedence, consumers, update trigger — Section III edits must mirror the Step 3 compact A/B/C excerpt in the same PR) and a Canonical-sources bullet. Generator path (`render-skill-md.sh`, `post-scaffold-hints.sh`) and README deliberately untouched — scaffold-pointer and README-link deferred to follow-up issues per dialectic DECISION_2. Closes #206.

## [4.2.3] - 2026-04-20

### Changed

- `/alias` reclassified from pure delegator to hybrid orchestrator: validates, delegates to `/implement`, then performs a mechanical sentinel-file verification (new Step 4 via `scripts/verify-skill-called.sh --sentinel-file`) that `.claude/skills/<alias-name>/SKILL.md` was actually written. `skills/alias/SKILL.md` Step 2.2 replaces the static 12-name reserved list with a dynamic two-root `test -d` probe against `${CLAUDE_PLUGIN_ROOT}/skills/<n>` and `${CLAUDE_PLUGIN_ROOT}/.claude/skills/<n>` (fail-closed on unset `CLAUDE_PLUGIN_ROOT`), eliminating drift when new skills ship. Step 3 replaces the "research the codebase and discover `generate-alias.sh`" hand-wave with an explicit generator contract naming the script path, its four required flags (`--name`, `--target`, `--flags`, `--version`), the pinned version source (`jq -r .version ${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json`), and the write target. Adds the canonical anti-halt banner + micro-reminder required of orchestrators. Step 4 emits branched fail-closed error text for the `--merge` vs non-`--merge` paths.
- `scripts/test-anti-halt-banners.sh` — move `skills/alias/SKILL.md` from `DELEGATORS` to `ORCHESTRATORS` to reflect the reclassification.
- `skills/shared/subskill-invocation.md` — remove `/alias` from pure-delegator lists (Pattern A example citation, allowed-tools tier, Post-invocation verification scope, Anti-halt scope, Scope list); add to orchestrator/hybrid category with sentinel-file verification as the concrete mechanical check.
- `skills/create-skill/scripts/render-skill-md.sh` — drop `/alias` from the two scaffold-emitted pure-delegator exemption checklists so newly scaffolded skills see accurate reminders.
- `skills/create-skill/scripts/validate-args.sh` — update the stale "mirrors skills/alias/SKILL.md Step 2" comment to describe the actual relationship (static pre-check before the dynamic plugin-skills probe); add `loop-improve-skill` to the static `LARCH_RESERVED` list; update the header comment's reserved-name enumeration.
- `docs/workflow-lifecycle.md` — update the Skill Orchestration Hierarchy intro, Delegation Topology prose, `/alias` bullet, and post-invocation-verification exemption paragraph to reflect `/alias`'s hybrid classification.
- `AGENTS.md` — update the `scripts/test-anti-halt-banners.sh` bullet counts (four→six orchestrators, four→three delegators) and note `/alias`'s reclassification rationale.

## [4.2.2] - 2026-04-20

### Changed

- `/design` — refactor for progressive disclosure: extract the 4 personality prompts (`ARCH_PROMPT`/`EDGE_PROMPT`/`INNOVATION_PROMPT`/`PRAGMATIC_PROMPT`) into `skills/design/references/sketch-prompts.md`, the Thesis/Antithesis debate templates into `skills/design/references/dialectic-debate.md`, and the Competition notice + voter prompts + ballot handling + FINDING_N/OOS/rejected-findings format blocks into `skills/design/references/plan-review.md`. Each reference file is loaded via a MANDATORY directive at the correct call site (Step 2a.2 for sketch prompts, between Step 2a.5 steps 5-6 for debate templates, top of Step 3 for plan-review artifacts). Reviewer launch shell blocks and numeric invariants remain inline in SKILL.md to preserve the CI agent-sync focus-area-enum check and `timeout: 1860000`/`--write-health "${SESSION_ENV_PATH}.health"` contracts. Byte-preserved all relocated prompt bodies, template bodies, and shell commands — zero behavioral change.
- `/design` — add consolidated `## Anti-patterns` section after Verbosity Control with 6 NEVER rules (skip Step 2a; substitute Claude into dialectic debate bucket; mutate orchestrator-wide `codex_available`/`cursor_available` inside Step 2a.5; pass `--caller-env`/`--write-health` to `session-setup.sh` when `SESSION_ENV_PATH` empty; call `collect-reviewer-results.sh` with zero positional args; conflate the sketch-phase vs. plan-review+dialectic timeout families). Each rule states the WHY so edits can respect the original constraint; inline step-local mentions remain where they carry load-bearing context.
- `/design` — strengthen frontmatter description with explicit "Use when..." trigger phrasing + 5-sketch + voting-panel keywords (within the 250-character agent-lint limit).

## [4.2.1] - 2026-04-20

### Changed

- `/create-skill` — delegate via `/im` instead of `/implement` so scaffold PRs auto-merge by default. `--merge` on `/create-skill` is now a backward-compat no-op (the flag still parses; the behavior change is in the default path). Switched the Skill tool call from `"implement"` / `"larch:implement"` to `"im"` / `"larch:im"`.
- `/create-skill` — add a `## Principles` section (A: express logic as bash scripts with shared/private reuse; B: no direct Bash commands — wrap in scripts; C: no consecutive Bash tool calls — combine via coordinator script). Principles are forwarded verbatim into the feature description handed to `/im` so they propagate to the implementing agent. Not mechanically enforced.
- `skills/create-skill/scripts/post-scaffold-hints.sh` — emit an expanded doc-sync reminder set for plugin-dev scaffolds: `docs/workflow-lifecycle.md` orchestration-hierarchy / delegation-topology / standalone-usage updates, `docs/agents.md` and `docs/review-agents.md` (with "when applicable" wording), and `AGENTS.md` Canonical sources (when the new skill introduces a shared script or is itself canonical). Existing README catalog + `.claude/settings.json` permission reminders unchanged.
- `scripts/test-post-scaffold-hints.sh` — add contract-token assertions for the new reminders and a negative assertion verifying the `--plugin false` branch does not leak them.
- `docs/workflow-lifecycle.md` — restructure the Skill Orchestration Hierarchy to include `/fix-issue` and `/loop-improve-skill` as orchestrators; add a new "Delegation Topology" subsection covering `/im`, `/imaq`, `/alias`, `/create-skill` as pure forwarders with their delegation edges; expand Standalone Usage with `/fix-issue`, `/loop-improve-skill`, `/create-skill`, `/issue`.
- `skills/shared/subskill-invocation.md` — update the Pattern A cited source-example citation from `/create-skill § Step 3 — Delegate to /implement` to `§ Step 3 — Delegate to /im`; add a note explaining the chained delegation.
- `skills/create-skill/scripts/parse-args.sh` — refresh the `--merge` header comment to state the flag is accepted for backward compatibility but no longer forwarded (since `/im` already prepends `--merge`).
- `README.md` — update the `/create-skill` skill-catalog row to describe the new `/im` delegation target and auto-merge default.
- `AGENTS.md` — expand the `skills/create-skill/scripts/post-scaffold-hints.sh` bullet to document the new reminder tokens and the paired harness contract.

## [4.2.0] - 2026-04-20

### Added

- `/implement --draft` — creates a draft PR and skips Step 14 local cleanup so the feature branch is retained for further iteration. Mutually exclusive with `--merge`. Forwarded from `create-pr.sh` to `gh pr create --draft`.

## [4.1.0] - 2026-04-20

### Added

- `/loop-improve-skill <skill-name>` — iteratively improve an existing larch skill. Creates a tracking GitHub issue, then loops `/skill-judge` → post judgment → `/design` → (exit if no plan materializes) → post plan → `/im`, up to 10 iterations. Each iteration's judgment and design plan are posted as issue comments for an audit trail. Registered in README Skills catalog, `.claude/settings.json` permissions, and the anti-halt banner harness.

## [4.0.21] - 2026-04-19

### Changed

- `.gitignore` — ignore `.agents/` and `skills-lock.json`.

## [4.0.20] - 2026-04-19

### Changed

- `.claude/settings.json` — enable `skill-judge` and `caveman` plugins; register `caveman` marketplace (`github:JuliusBrussee/caveman`).
- `CLAUDE.md` — set default caveman output mode to `full`.

## [4.0.19] - 2026-04-19

### Changed

- `skills/fix-issue/SKILL.md` — Step 5 now classifies each eligible issue along two independent dimensions: **intent** (PR-producing vs. non-PR task) and, only when `INTENT=PR`, complexity (SIMPLE vs. HARD). Step 6 branches on intent: `PR` delegates to `/implement` as before; `NON_PR` follows the issue's instructions inline using Read/Grep/Glob/Bash and `/issue` (batch mode for multi-issue output, with the `--input-file` markdown written under `$FIX_ISSUE_TMPDIR` — never inside the working tree). Steps 7 and 8 mirror the branching: `NON_PR` closes with a `WORK_SUMMARY` comment (no PR URL, no body update) and announces on Slack via the pre-existing `--message` free-form path. Default to `PR` when uncertain preserves pre-existing behavior for any issue where the intent is ambiguous. Step 4 triage gains an explicit guidance bullet that for investigation/review-only issues, "still relevant" means the **task** is still meaningful rather than "the referenced bug is still in code".

## [4.0.18] - 2026-04-19

### Fixed

- `skills/fix-issue/scripts/fetch-eligible-issue.sh` — the GO-sentinel check at two sites (explicit-issue path and auto-pick loop) used `gh api --paginate "repos/…/comments" --jq '.[-1].body // empty' | tail -1`. Because `--jq` runs per page, `.[-1]` returned the last element of each page, not the last of the full history — the `tail -1` was only accidentally correct (pages arrive in order, so the final page's last element coincides with the globally-last comment, but the logic is brittle to any jq/paginate behavior change and `tail -1` also truncates multi-line last comments to their final line). Both sites now use the `gh api --paginate --slurp … | jq -r 'add // [] | .[-1].body // empty'` pattern already used by `prose_open_blockers` at line 135-136 — `--slurp` concatenates all pages into one JSON array-of-arrays, `add // []` flattens to a single array, `.[-1].body` unambiguously addresses the globally-last comment. Closes #184.

## [4.0.17] - 2026-04-19

### Fixed

- Orchestrator SKILL.md files (`fix-issue`, `implement`, `review`, `loop-review`) now carry a prominent top-of-file "Anti-halt continuation reminder" banner plus per-Skill-call-site micro-reminders, so the main agent does not halt on a child skill's cleanup output and skip the parent's remaining steps. The canonical wording lives in `skills/shared/subskill-invocation.md`'s new "Anti-halt continuation reminder" section (complementary to the existing "Post-invocation verification" section — "did the child run?" vs "did the parent continue?"). The `skills/create-skill/scripts/render-skill-md.sh` scaffold checklist gains a 6th item so new orchestrators inherit the convention. New regression harness `scripts/test-anti-halt-banners.sh` asserts banner presence in the 4 orchestrators, absence in the 4 pure-delegator skills, and micro-reminder presence in each orchestrator — wired into `make lint` via the `test-anti-halt` target. Closes #177.

## [4.0.16] - 2026-04-19

### Changed

- `scripts/lint-skill-invocations.py` now enforces the sub-skill-invocation style guide at two levels (closes #180). The existing total-omission check is preserved unchanged. A new line-local per-invocation check flags lines matching `INVOCATION_LINE_REGEX` — direct imperative `Invoke`/`re-invoke` (optionally `the` + a bounded `**bold-span**`) immediately followed by a backticked `` `/<name>` ``, optionally followed by `skill` — that lack `via the Skill tool` on the same line. Sub-procedure references and helper-script citations are exempt by construction; lines inside fenced code blocks are exempt. Per-invocation messages emit absolute file line numbers (frontmatter offset preserved) so editor jump-to-line works. `lint_file()` returns `list[str]` instead of `str | None`; `extract_frontmatter_and_body()` additionally returns the body's absolute file start line.
- `scripts/test-lint-skill-invocations.sh` adds 9 black-box cases (m–u) covering pure Pattern A, Pattern B per-invocation passes, bare invoke with absolute line assertion, multiple violations, code-fence exemption, total-omission + per-invocation in same file, helper-script citation exemption, sub-procedure exemption, and `re-invoke` in scope.
- `skills/implement/SKILL.md` (8 lines) and `skills/loop-review/SKILL.md` (1 line) updated to add `via the Skill tool` to direct-invocation phrasings the new check surfaces. `AGENTS.md` documents the two-check contract; `skills/shared/subskill-invocation.md` carries a one-line note about line-local enforcement.

## [4.0.15] - 2026-04-19

### Changed

- `/fix-issue` now honors prose-stated dependency relationships in addition to GitHub's native `blocked_by` API. `skills/fix-issue/scripts/fetch-eligible-issue.sh` unions two blocker sources before declaring an issue eligible: (1) the existing native-dependencies check, and (2) a new `prose_open_blockers()` function that extracts same-repo issue numbers from the issue body and every comment body using the conservative case-insensitive keyword set (`Depends on #N`, `Blocked by #N`, `Blocked on #N`, `Requires #N`, `Needs #N`). A native-first short-circuit skips the prose path when the native check already flags the candidate, capping API volume at the cost of a documented diagnostic gap in skip/error messages. Every boundary is fail-open, mirroring the pre-existing native-dep contract. Motivating case: issue #152's body used `Depends on **#150 (bypass fix) only**` but the native `blocked_by` endpoint had no dependency registered, so `/fix-issue` picked it up as eligible despite the prose-declared open blocker.
- `skills/fix-issue/scripts/parse-prose-blockers.sh` is the new pure text-in / numbers-out parser (takes one document body at a time, no network). Emphasis wrappers (`*`, `_`) are normalized before matching so `**#150**` formatting is caught; link-target forms (`[#150](url)`) and cross-repo references (`owner/repo#N`) remain NON-matches by parser construction. `skills/fix-issue/scripts/test-parse-prose-blockers.sh` is its 43-assertion offline regression harness — wired into `make lint` via the new `test-parse-prose-blockers` target and added to `agent-lint.toml`'s exclude list per the Makefile-only harness convention. `skills/fix-issue/SKILL.md` Step 1 and Known Limitations are updated accordingly; `README.md`'s `/fix-issue` row is updated to mention both native and prose keyword scanning.

## [4.0.14] - 2026-04-19

### Fixed

- `.claude/settings.json` no longer mirrors the `PreToolUse` submodule-guard registration; `hooks/hooks.json` (with `${CLAUDE_PLUGIN_ROOT}` paths) is now the single source of truth, eliminating possible double-invocation, policy drift between the two copies, and the `$PWD`-vs-anchored path question. Contributors developing in this repo should load larch as a plugin (`claude --plugin-dir .` or the local marketplace) to pick up the guard — `AGENTS.md` carries a one-line note to that effect. Closes #152.

## [4.0.13] - 2026-04-19

### Fixed

- `.pre-commit-config.yaml`'s `shellcheck` hook gains `args: [-x]` so pre-commit instructs shellcheck to follow `source` directives, eliminating the SC1091 false-positive that fired when `/relevant-checks` (via `pre-commit run --files <subset>`) scoped shellcheck to consumers of `scripts/lib-count-commits.sh` (`scripts/check-bump-version.sh`, `scripts/verify-skill-called.sh`) without also including the library itself. CI's `make lint` (via `pre-commit run --all-files`) was unaffected because all files were always present. With `-x`, the file-subset path now matches the all-files behavior on source-following. Reproduces on unmodified main via `pre-commit run shellcheck --files scripts/check-bump-version.sh`. Closes #178.

## [4.0.12] - 2026-04-19

### Added

- `scripts/lint-skill-invocations.py` — minimal-guardrail lint that flags public and dev `SKILL.md` files which declare `Skill` in their `allowed-tools` frontmatter but omit both canonical invocation phrases (`Invoke the Skill tool`, `via the Skill tool`) anywhere in the body. Catches *total omission* only; per-invocation alignment is intentionally out of scope and tracked as follow-up issue #180. Accepts `--root <dir>` (defaults to the script's parent directory) so the regression harness can isolate fixtures under a temp tree. Uses `PyYAML` for frontmatter parsing, normalizes leading UTF-8 BOM and CRLF before the `---` prefix test, and distinguishes internal errors (unreadable or non-UTF-8 files → exit 2) from policy violations (→ exit 1); exit 2 takes priority when both occur.
- `scripts/test-lint-skill-invocations.sh` — 12-case black-box regression harness (a through l) covering Pattern A, Pattern B, YAML-list and quoted-string `allowed-tools` shapes, exact-token discipline (`SkillCheck` must not satisfy a `Skill` requirement), multi-violation runs, CRLF/BOM normalization, non-UTF-8 files exercising the exit-2 internal-error path, and the mixed error+violation priority rule. Wired into `make lint` via the new `test-lint-skill-invocations` target and added to `agent-lint.toml`'s exclude list.
- `.pre-commit-config.yaml` gains a `lint-skill-invocations` local hook with `additional_dependencies: ['pyyaml==6.0.2']`, `always_run: true`, `pass_filenames: false`. The hook runs in its own isolated venv and fires uniformly from `make lint`, `/relevant-checks`, and CI's existing lint job. `.github/workflows/ci.yaml`'s lint step additionally installs `pyyaml==6.0.2` into the ambient Python so the `test-lint-skill-invocations` harness (which invokes the script directly with `python3`, outside the pre-commit venv) can import it; the pyyaml version is pinned identically in both locations. Closes #159.

### Changed

- `skills/review/SKILL.md` Step 3e rewrites "invoke `/relevant-checks`" to "invoke `/relevant-checks` via the Skill tool" (Pattern B), addressing pre-existing non-compliance with the sub-skill invocation style guide that the new lint uncovers.

## [4.0.11] - 2026-04-19

### Fixed

- `scripts/check-bump-version.sh` now surfaces a `STATUS=ok|missing_main_ref|git_error` field on stdout in both `--mode pre` and `--mode post`, plumbed from `scripts/lib-count-commits.sh`'s `COUNT_COMMITS_STATUS_FILE` side channel. In `--mode post`, `VERIFIED=true` is emitted ONLY when `STATUS=ok` AND the numeric commit-delta matches — any non-`ok` status forces `VERIFIED=false` at the script level, closing the #172 silent-zero false-pass window where a symmetric `git rev-list` failure on both pre- and post-calls coerced counts to 0 on each side and spuriously matched. Any unknown or empty token received from the side channel is normalized to `STATUS=git_error` (fail-closed, mirrors `verify-skill-called.sh`'s default branch). Existing KEY=VALUE contract (HAS_BUMP, COMMITS_BEFORE, VERIFIED, COMMITS_AFTER, EXPECTED) is preserved — the new line is additive. `scripts/test-check-bump-version.sh` is the new 43-assertion black-box regression harness covering all three status paths × both modes, the `origin/main`-only fallback, unknown-token normalization, a pre-degraded + post-recovered caller sequence, and a dedicated fail-closed regression guard that proves delta-0 + expected-0 under non-ok STATUS cannot spuriously pass. Uses a PATH shim forcing `git rev-list` to fail while leaving `git rev-parse` intact as the deterministic git_error fixture. Wired into `make lint` via `test-check-bump-version`; added to `agent-lint.toml`'s exclude list. `skills/implement/SKILL.md` Step 8 and Rebase + Re-bump Sub-procedure step 4 restructure their VERIFIED/COMMITS decision trees so `STATUS != ok` is evaluated as prior branches BEFORE the numeric comparison: Step 12 (step12 family, pre-merge last-chance) hard-bails on non-`ok` STATUS from either the pre-check or the post-check with distinct actionable messages; Step 10 (step10 family) and Step 8 log warnings and proceed permissively per their existing semantics, with a HAS_BUMP=false short-circuit in the step10 pre-STATUS guard to avoid invoking a non-existent skill. The instruction to grep stderr for the `WARN: ... neither local 'main' nor 'origin/main' exists` line is removed — `STATUS=` is now authoritative. `skills/shared/subskill-invocation.md`'s `/bump-version` example is updated to parse STATUS and note the check-STATUS-before-counts rule. Closes #172.

## [4.0.10] - 2026-04-20

### Fixed

- `scripts/block-submodule-edit.sh` closes the cd-into-submodule bypass (#150): `REPO_ROOT` now resolves via a two-step anchor — try `CLAUDE_PROJECT_DIR` first, fall through to `$PWD` when the first attempt does not yield a git repo — so a session that has `cd`'d into a submodule still detects the superproject, and a stale/broken `CLAUDE_PROJECT_DIR` cannot silently downgrade the guard to fail-open when `$PWD` is a healthy superproject. `scripts/test-block-submodule-edit.sh` case 3 auto-flips from KNOWN-FAIL to PASS via the existing tri-state fingerprint (retained as defense-in-depth against future regressions); the harness also unsets any inherited `CLAUDE_PROJECT_DIR` at startup for hermeticity and gains new case 3b covering the broken-anchor + healthy-`$PWD` fallback scenario. `SECURITY.md` gains a one-paragraph note in the Trust Model section documenting the `CLAUDE_PROJECT_DIR` anchor and the bypass it closes. Closes #150.

## [4.0.9] - 2026-04-19

### Added

- `scripts/verify-skill-called.sh` — generic mechanical post-invocation verifier for `Skill` tool calls, with three mutually-exclusive modes: `--sentinel-file <path>` (file exists, regular, non-empty), `--stdout-line <regex> --stdout-file <path>` (captured stdout has a matching line via `LC_ALL=C grep -E -q -- …`; empty regex rejected as argument error; grep exit 2 treated as internal fault per fail-closed contract), and `--commit-delta <N> --before-count <B>` (commit count ahead of main increased by exactly N). Emits `VERIFIED=true|false` and `REASON=<token>` on stdout; exit 0 for pass/fail outcomes, exit 1 only for argument errors or internal faults. Reason tokens are a stable enum: `ok`, `missing_path`, `not_regular_file`, `empty_file`, `missing_stdout_file`, `no_match`, `commit_delta_mismatch`, `missing_main_ref`, `git_error`. Intended as a defense-in-depth gate for `Skill` calls whose child skills have no dedicated domain-specific verifier.
- `scripts/lib-count-commits.sh` — sourced-only shell library (no shebang, not invokable directly) extracting the shared `count_commits` function used by both `scripts/check-bump-version.sh` and the new verifier. Distinguishes `ok` / `missing_main_ref` / `git_error` via a file-based status side channel (`COUNT_COMMITS_STATUS_FILE`) so the `$(count_commits)` subshell's result can be classified without losing the status. Preserves the existing `WARN: check-bump-version.sh:` stderr prefix for log parity with operators' existing grep patterns. Explicitly documents that `.claude/skills/bump-version/scripts/classify-bump.sh`'s merge-base logic is a structurally different concept intentionally not migrated.
- `scripts/test-verify-skill-called.sh` — 53-assertion black-box regression harness covering all three modes' pass/fail paths, argument-error paths (exit 1 with no KEY=VALUE), stdout-contract assertions, exit-code assertions on every non-argument-error path, malformed-ERE regression (grep exit 2 → exit 1 fail-closed), and the cwd-neutral source chain via `check-bump-version.sh`. Wired into `make lint` via the new `test-verify-skill-called` target. Added to `agent-lint.toml`'s exclude list alongside `scripts/lib-count-commits.sh`.
- `skills/implement/SKILL.md` Step 8 and Step 12 Rebase + Re-bump Sub-procedure step 4 migrate to call `verify-skill-called.sh --sentinel-file "$BUMP_REASONING_FILE"` alongside the existing `check-bump-version.sh --mode post` commit-delta check, with an empty-path guard. The sentinel check is advisory (warn-and-continue; commit-delta remains the hard gate) and complementary. `scripts/check-bump-version.sh` refactored to source `lib-count-commits.sh`; no behavior change. Closes #160.

## [4.0.8] - 2026-04-19

### Added

- Canonical sub-skill invocation style guide: `skills/shared/subskill-invocation.md` documents the six conventions larch skills already follow implicitly — two first-class invocation patterns (Pattern A bulleted bare-name fallback, Pattern B inline "Invoke `/X` via the Skill tool"), the `allowed-tools` narrowing heuristic (pure delegator → `Skill` only, delegator-that-validates → `Bash, Skill`, hybrid orchestrator → `Skill` plus whatever the parent needs), post-invocation verification expectation (scoped to orchestrators that continue based on child side effects — pure forwarders exempt), session-env handoff with safe-parse rule (do NOT `source` the file; parse line-by-line; writer does not escape so constrain the value set at the source), anti-conditional-phrasing for Skill-tool calls, and the bare-name-then-fully-qualified (`larch:<name>`) fallback. `skills/create-skill/scripts/render-skill-md.sh` now emits a `## Sub-skill Invocation` checklist block unconditionally in both minimal and multi-step scaffold variants, placed after `## Progress Reporting` and before `## Step 0` in multi-step and at the bottom of MINIMAL_BODY, so every newly scaffolded skill inherits the conventions with a pointer to the canonical guide. `skills/create-skill/scripts/post-scaffold-hints.sh` gains a reminder line pointing at the guide. `skills/create-skill/scripts/test-render-skill-md.sh` is the new 3-case regression harness asserting `RENDERED=` stdout line, frontmatter name + YAML-quoted description, `## Sub-skill Invocation` section presence, a `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` citation with non-empty prefix (guards against empty `--plugin-token` producing a rooted path), and empty-`--plugin-token` rejection. Wired into `make lint` via the new `test-render-skill` target. `AGENTS.md` declares the shared file as canonical (Editing rules + Canonical sources). `agent-lint.toml` excludes the new harness from the G004/dead-script rule (Makefile-only reference, matching the `test-deny-edit-write.sh` precedent). Closes #158.

## [4.0.7] - 2026-04-19

### Fixed

- `scripts/block-submodule-edit.sh` now resolves `tool_input.file_path` through any symlink chain before repo classification, closing the bypass where a symlink in the superproject pointing into a submodule was allowed (the hook previously canonicalized only the containing directory via `pwd -P` and never resolved the `file_path` itself). Implementation is a bounded-depth (40-hop) pure-bash `readlink` loop inserted after `REPO_ROOT` canonicalization and before the ancestor walk — non-symlink inputs pass through unchanged, so all prior allow / deny behavior is preserved. macOS ships without `readlink -f` / `realpath` so the loop avoids them; relative readlink targets are rebased against the link's own directory. Fail-closed via the existing `block()` helper on depth-cap exhaustion (possible cycle), `readlink` failure, or empty target. `scripts/test-block-submodule-edit.sh` gains three strict regression cases: case 11 (absolute symlink into submodule → deny), case 12 (self-referential symlink cycle → deny via depth cap), case 13 (relative symlink into submodule → deny, exercises the `$(dirname "$resolved")/$target` rebasing branch); the top-of-file fixture comment block lists the three new symlinks. Closes #166.

## [4.0.6] - 2026-04-19

### Added

- Strict-permissions consumer guidance: README.md gains a `### Strict-permissions consumers — Skill permission entries` subsection documenting that `Skill(name)` is exact-match and does NOT authorize `Skill(larch:name)` (per Claude Code's official permissions docs), that `Skill(larch:*)` wildcards are not currently supported, and that consumers running without `"defaultMode": "bypassPermissions"` must grant both the bare and fully-qualified form for each larch skill. Includes a copy-paste `settings.allow` snippet covering all 11 public plugin skills in strict ASCII code-point order, the shadowing caveat (bare names may resolve to project-local skills before reaching the plugin), and links to upstream Claude Code docs. `skills/create-skill/SKILL.md` Step 3 and `skills/create-skill/scripts/post-scaffold-hints.sh` now emit both `Skill(<NAME>)` and `Skill(larch:<NAME>)` when scaffolding plugin-mode skills, with a cross-reference to the README subsection for rationale. `scripts/test-post-scaffold-hints.sh` is the new 20-assertion regression harness covering `--plugin true/false` branches, dual-Skill output, literal-`$PWD` Bash entry, `sort -u` instruction, and the single-line README subsection title (verified across a normal skill name and the ASCII-edge-case `loop-review`); wired into `make lint` via the new `test-post-scaffold-hints` target. `SECURITY.md` gains a one-sentence pointer to the new README subsection in the Trust Model section. `AGENTS.md` documents the harness contract alongside the other `test-*` entries. `agent-lint.toml` adds the new test script to the G004/dead-script exclude list (Makefile-only reference, matching the `test-deny-edit-write.sh` precedent). `README.md` install paragraph also gains the missing `/create-skill` entry in the slash-command list. Closes #161. Cross-references #158.

## [4.0.5] - 2026-04-19

### Added

- Skill-scoped PreToolUse deny hook for `/research`: `skills/research/SKILL.md` frontmatter now declares a `hooks:` block that registers a PreToolUse deny on `Edit|Write|NotebookEdit` matchers, executing the new `${CLAUDE_PLUGIN_ROOT}/scripts/deny-edit-write.sh`. The hook emits a fixed `hookSpecificOutput` JSON deny envelope and always exits 0 — when `jq` is on PATH it composes the JSON via `jq -cn`, otherwise it falls back to a byte-identical static `printf` (matches the precedent in `scripts/block-submodule-edit.sh`). This is a defense-in-depth second mechanical layer; the `allowed-tools` frontmatter omitting `Edit`/`Write`/`Skill` remains the primary mechanical control because hook JSON `permissionDecision` semantics may vary by Claude Code version. External Codex/Cursor reviewers and Bash-mediated writes from `/research` itself remain prompt-enforced — the issue text and SECURITY.md document this gap. `scripts/test-deny-edit-write.sh` is the 7-assertion regression harness (exit code, valid JSON, hookEventName, permissionDecision, permissionDecisionReason non-empty, idempotency, and `env -i PATH=$STUB_DIR` byte-identity check across the jq and printf branches), wired into `make lint` via the new `test-deny-edit-write` target. `agent-lint.toml` excludes the test script (Makefile-only reference, matches the `test-sessionstart-health.sh` precedent); the hook script itself is structurally referenced from the SKILL.md `hooks:` block. `SECURITY.md`, `AGENTS.md`, and `README.md` updated per repo convention. Closes #154.

## [4.0.4] - 2026-04-19

### Changed

- `scripts/block-submodule-edit.sh` deny channel now uses Anthropic's documented `hookSpecificOutput` JSON shape (`hookEventName=PreToolUse`, `permissionDecision=deny`, `permissionDecisionReason=<why>`) emitted on stdout with exit 0, replacing the prior exit-2 + stdout-reason behavior that directly contradicted the PreToolUse spec (where exit 2 routes stderr, not stdout, to Claude). `block()` is hardened with a static-JSON fallback for rare `jq` runtime failures so a broken `jq` never degrades to exit 0 + empty stdout (which the runtime interprets as allow, silently weakening the submodule-edit policy). The `jq` availability probe moves ahead of every `block()` call and emits a hardcoded deny JSON literal on the missing-`jq` path. `scripts/test-block-submodule-edit.sh` gains an `assert_deny_json` helper (with an empty-needle guard) and rewrites every deny-case assertion to parse stdout with `jq` and check all three fields; case 3's tri-state fingerprint is updated to match the new contract; case-7 mini-bin comments are rewritten to reflect the jq-first probe ordering. Closes #151.

## [4.0.3] - 2026-04-19

### Added

- `scripts/test-block-submodule-edit.sh` regression harness for `scripts/block-submodule-edit.sh` (the PreToolUse hook that denies edits to files inside submodules), covering 11 cases: allow (superproject, nested non-submodule repo, symlink, non-repo cwd, out-of-repo file_path), deny (submodule file, ancestor-walk into new subdir, non-absolute path, bad JSON, missing jq), and a known-failing bypass case (cwd inside submodule) whose tri-state fingerprint logic auto-flips to PASS when #150 lands. Wired into `make lint` via the new `test-block-submodule` target. `AGENTS.md` and `README.md` document the harness. `scripts/block-submodule-edit.sh` gains a header comment pointing at the test. Closes #149.

## [4.0.2] - 2026-04-19

### Added

- `scripts/audit-edit-write.sh` — dev-only opt-in `PostToolUse` audit hook that appends one JSONL line per `Edit` / `Write` tool invocation to `.claude/hook-audit.log`. Shipped in the plugin install tree but **not registered by default** in `hooks/hooks.json` or `.claude/settings.json`; contributors opt in locally via the gitignored `.claude/settings.local.json`. Uses `set -uo pipefail` (no `-e`), always exits 0, `|| true` on the append — a PostToolUse hook must never block Edit/Write, even on disk full / read-only fs. `jq -ec --arg ts … 'select(type=="object") | {ts, event, payload: .}'` composes the log line; empty / invalid / non-object stdin exits non-zero and the `|| true` swallows it, so no corrupted or empty-payload line is ever appended. `scripts/test-audit-edit-write.sh` is the 12-assertion regression harness (tmpdir + `CLAUDE_PROJECT_DIR` override, happy-path + append-order + empty-stdin + invalid-JSON-stdin coverage), wired into `make lint` via the new `test-audit-edit-write` phony target. `docs/dev-hook-audit.md` documents enable / rotate / privacy / concurrency with two enablement snippets (`$PWD/…` for in-repo dev, `${CLAUDE_PLUGIN_ROOT}/…` for plugin consumers). `SECURITY.md` gains a dev-only-audit-log subsection per AGENTS.md's security-documentation contract. `.gitignore` adds `.claude/hook-audit.log`. `agent-lint.toml` adds the two scripts to the G004/dead-script exclude list alongside the existing `scripts/test-sessionstart-health.sh` entry — all three are dev-infrastructure scripts structurally referenced from Makefile/docs/AGENTS.md but not from the SKILL.md / hooks.json / settings.json files agent-lint scans. Closes #155.

## [4.0.1] - 2026-04-19

### Added

- New `SessionStart` hook `scripts/sessionstart-health.sh` probes `jq` and `git` on `PATH` at session start/resume/clear/compact and injects a spec-compliant `hookSpecificOutput.additionalContext` advisory when either is missing. Non-blocking (always exits 0) and silent on the happy path — converts the existing reactive-block-at-first-edit pattern in `scripts/block-submodule-edit.sh` into a proactive session-start advisory. JSON is emitted via `printf` only (no `jq` dependency inside the hook) so the warning reaches Claude's session context even when `jq` itself is missing. Regression test `scripts/test-sessionstart-health.sh` covers 4 cases (both present, jq missing, git missing, both missing) using a stub-only PATH via `env -i PATH="$STUB_DIR" "$BASH_BIN"` for strict isolation. Wired into `make lint` via the new `test-sessionstart` target. README.md feature matrix updated; AGENTS.md editing rules updated with the fixed-ASCII-literal invariant. Closes #153.

## [4.0.0] - 2026-04-19

### Changed

- **BREAKING**: `/loop-review` now files GitHub issues via `/issue` instead of creating PRs via `/implement`. Every actionable finding becomes a deduplicated issue labeled `loop-review` (reusing `/issue`'s 2-phase LLM dedup against open + recently-closed issues). The IMPLEMENT/DEFER classification collapses into a single FILE gate; `LOOP_REVIEW_DEFERRED.md` is no longer created, maintained, or committed (legacy files in consumer repos are left untouched). `--debug` propagation to downstream skills is dropped (`/issue` has no such flag). Step Name Registry rewritten: Step 4 "Final Deferred Commit" removed; Step 3 renamed from "implement/defer" to "review + file issues". Downstream tooling that parsed loop-review's output expecting PR URLs, merge status, CI results, or the deferred-doc file will break — switch to the `label:loop-review` GitHub filter. Closes #148.
- Security-tagged findings are held locally in `$LR_TMPDIR/security-findings.md` (never auto-filed as public GitHub issues, per SECURITY.md's vulnerability-disclosure policy). Step 4 final summary prints the full contents of that file inline in the transcript so operators see them before Step 5 cleanup removes the tmpdir. All three reviewer lanes (Claude Code Reviewer subagent, Cursor, Codex) are now prompted with the same 5-focus-area taxonomy (including `security`) with EXACT-label tagging required, so security findings route consistently regardless of reviewer.
- `/loop-review` Step 0c adds a preflight check that the `loop-review` GitHub label exists in the target repo. Missing label → warning appended to `warnings.md` and surfaced in the final summary (issues are still filed, just unlabeled). Previously `/issue` emitted the label-drop warning only on stderr, which loop-review's stdout-only flush parser never saw.
- Partial `/issue` failures no longer silently drop loop-review findings. After each flush, loop-review parses per-item `ITEM_<i>_*` stdout lines and retains only unresolved entries (failed or missing) in `findings-accumulated.md` for the next flush.
- Tracking files in `skills/loop-review/scripts/init-session-files.sh` renamed: `deferred-accumulated.md`, `pr-count.txt`, `impl-count.txt`, `defer-count.txt` removed; `findings-accumulated.md`, `security-findings.md`, `issue-count.txt`, `issue-dedup-count.txt`, `issue-failed-count.txt` added.
- `SECURITY.md` documents the new hold-local policy for security-tagged findings in `/loop-review`.
- `docs/workflow-lifecycle.md` updated: mermaid edge now shows `/loop-review → /issue`; `/loop-review --debug` documented as local-only (no downstream propagation).
- `README.md` Features bullet and `/loop-review` skill-table row reworded from PR-creation to issue-filing.
- `skills/loop-review/diagram.svg` regenerated to match the new flow (review → classify → FILE gate → HOLD LOCAL / DROP / accumulate → `/issue` flush).
- `skills/issue/scripts/test-parse-input.sh` gains Case 16 (10 assertions) guarding the exact generic batch shape loop-review commits to. 121 → 133 assertions, all pass.

## [3.4.10] - 2026-04-19

### Fixed

- `skills/issue/scripts/parse-input.sh` no longer silently swallows an author-intended new item into an in-progress OOS body. When a plain `### <title>` line appears inside an OOS Description that has not yet seen a closing structured field (Reviewer / Vote tally / Phase), the parser now defers the absorb decision via a pending-heading state (`PENDING_HEADING` / `PENDING_BODY`). Resolution happens at the first disambiguating signal: Reviewer/Vote tally/Phase fires → `resolve_pending_foldback` merges pending content back into `CURRENT_BODY` (preserves the #129 `### Notes` subheading-absorption behavior byte-for-byte); `### OOS_N:` line or EOF arrives → `resolve_pending_split` emits the current OOS as MALFORMED with its non-empty body, then emits the pending heading + body as a new generic item. `emit_item` gains a `force_malformed` parameter so a MALFORMED item can carry a populated BODY. `flush_item` clears pending state alongside the other per-item resets. `skills/issue/SKILL.md` line 75 now describes the expanded MALFORMED trigger per unanimous dialectic vote. `test-parse-input.sh` rewrites case 6 from "documented absorb limitation" to the #138 contract and adds three regression locks: case 13 (multi-subheading OOS accumulation before Reviewer), case 14 (EOF split), case 15 (mid-stream `### OOS_N:` split). 83 → 121 assertions, all pass. Closes #138.

## [3.4.9] - 2026-04-19

### Fixed

- `skills/issue/scripts/create-one.sh` no longer merges `gh` stderr into the success-path variable used for URL extraction. Previously `ISSUE_URL=$(gh … 2>&1)` captured both stdout and stderr into one variable, and the downstream `grep -oE 'https?://…/issues/N'` parsed the combined blob; any future stderr line (progress or warning) on success could corrupt the extraction. The fix redirects stderr to a dedicated temp file (`ERR_TMP`) so `ISSUE_URL` holds only stdout on the success branch, and the failure branch reads `ERR_TMP` for the error message still piped through `redact`/flatten/`head -c 500`. `ERR_TMP` is registered in the existing `cleanup()` EXIT trap alongside `BODY_TMP`, so every exit path — including `emit_redaction_failure` on the no-URL branch — removes the stderr temp file, closing a potential durable-disk exposure for token-bearing error text. `scripts/test-redact-secrets.sh` grows a new section 3d case that stubs `gh` to emit a URL on stdout and a warning on stderr, asserting `ISSUE_NUMBER=137` is still extracted and stderr noise does not leak into `ISSUE_URL`. Closes #137.

## [3.4.8] - 2026-04-19

### Changed

- `skills/issue/scripts/test-parse-input.sh` is now wired into `make lint` via a new `test-parse-input` Makefile target, mirroring the existing `test-redact` target for `scripts/test-redact-secrets.sh`. The 83-assertion parser regression harness runs on every PR through the existing `lint` CI job in `.github/workflows/ci.yaml`, closing the gap where regressions in `skills/issue/scripts/parse-input.sh` could previously ship undetected. Documentation updated in `skills/issue/SKILL.md`, `AGENTS.md`, and the script header. Closes #136.

## [3.4.7] - 2026-04-19

### Fixed

- `scripts/test-redact-secrets.sh` no longer triggers GitHub secret-scanning's `sk-ant-*` heuristic as a false positive. The synthetic `SK_TOKEN` fixture on line 33 previously appeared as a contiguous `sk-ant-abcdefghijklmnopqrstuvwxyz0123456789ABCD` substring that GitHub's scanner flagged as an OpenAI API key (alert #1). The fix splits the `sk-ant-` prefix in the source via adjacent single-quoted bash strings (`'sk-''ant-…'`), which concatenate at runtime to the identical 47-character test value but contain no contiguous `sk-ant-` substring in the repo source. Three other sites in the same file that also contained contiguous `sk-ant-*` substrings (`dry_title_raw` literal on line 137, the `GHZERO` heredoc stub's `printf` on line 285, and the `assert_not_contains` needle on line 303) are likewise rewritten to build their token-shaped values from the canonical `SK_TOKEN` fixture via `${SK_TOKEN}` and `${SK_TOKEN:0:35}` expansions; the `GHZERO` heredoc is switched from quoted (`<<'GHZERO'`) to unquoted (`<<GHZERO`) with `\$1` escaping to allow the expansion. All 45 assertions still pass with byte-identical runtime values.

## [3.4.6] - 2026-04-19

### Fixed

- `skills/issue/scripts/parse-input.sh` applies the symmetric mode-guard to the OOS heading branch so that a literal `### OOS_N: ...` line inside a generic item's body is absorbed as body continuation rather than flushing the generic item and starting a new OOS item. Before this fix, the OOS-heading regex fired unconditionally — the #129 mode-guard only covered the plain `### <title>` branch, so pasting a nested OOS-shaped heading into a generic issue body silently split the item and mis-classified the body below. The new guard uses `CURRENT_MODE=generic && IN_BODY=true` plus a meaningful-body check (`${CURRENT_BODY//[[:space:]]/}` non-empty) to align semantics with the OOS→generic direction, where `IN_BODY=true` is always paired with non-whitespace content populated by `**Description**:`. Parameter expansion (not `=~`) is used so the outer OOS-heading regex's `BASH_REMATCH[1]` capture is not clobbered before the `else` branch reads it. `test-parse-input.sh` grows three cases: case 10 (nested `### OOS_42: nested example` inside real body prose — the #132 reproducer), case 11 (bodyless generic title immediately followed by a real OOS item — the degenerate split case), and case 12 (whitespace-only body followed by a real OOS item — the meaningful-body guard at work); 7 new assertions pass alongside the existing 76. In-branch comment documents the asymmetry rationale, the `BASH_REMATCH` clobbering caveat, and the deliberate difference between the absorb predicate (meaningful body) and `emit_item`'s MALFORMED predicate (`[[ -z "$body" ]]`). Fixes #132.

## [3.4.5] - 2026-04-19

### Changed

- Phase 4 cleanup for the dialectic debate overhaul: docs (`docs/voting-process.md`, `docs/agents.md`, `docs/external-reviewers.md`, `docs/workflow-lifecycle.md`, `README.md`) refreshed to reflect Phase 1-3 behavior — the 5-decision dialectic cap, external Cursor/Codex debaters with same-tool bucketing, bucket-skipped (no Claude substitution) debate semantics, 3-judge replacement-first panel, attribution-stripped ballot with position-order rotation, and the four-valued Disposition enum (`voted`, `fallback-to-synthesis`, `bucket-skipped`, `over-cap`). `docs/external-reviewers.md` gains an explicit Dialectic-specific behavior section cross-referencing `skills/shared/dialectic-protocol.md`. `docs/voting-process.md` gains a Relationship to Dialectic Protocol section that states semantic independence and the mechanical "no Claude debaters" rule (debate execution only, not judge adjudication).
- `skills/design/diagram.svg` redrawn: Step 2a.5 Dialectic Debate node expanded into a visual subgraph (contested decisions → bucketed Cursor/Codex debater pairs → attribution-stripped ballot → 3-judge panel → resolutions), and the stale plan-review label `(2 Claude + 2 Codex + Cursor)` corrected to `(1 Claude + 1 Codex + 1 Cursor)`.
- New offline regression guard: `scripts/dialectic-smoke-test.sh` is a bash-3.2-compatible fixture-driven parser/tally/structural-invariant validator. Loads fixtures from `tests/fixtures/dialectic/` (new top-level non-runtime tree), parses debater + ballot + judge artifacts, computes per-decision dispositions via the protocol's `Threshold Rules` matrix, and compares against a per-fixture `expected.txt` manifest. Six fixture variants cover: happy-path-5-decisions, two-judge-quorum (unanimous + 1-1 tie rows), bucket-skipped, over-cap, fallback-quorum-failure, and parser-tolerance (em-dash-or-hyphen separator, duplicate DECISION_N first-valid-wins, per-decision abstention). Validates ballot anonymity case-insensitively (`Cursor`/`Codex`/`Claude` must not appear anywhere in the body) and enforces a protocol drift guard that greps `skills/shared/dialectic-protocol.md` for the stable `Recognize exactly these four Disposition values` anchor and the four canonical values. `bucket-skipped` / `over-cap` dispositions require explicit structural absence (no debate-N files, no `DECISION_N:` in any judge file, no `### DECISION_N:` ballot heading) in addition to the 0/0 fallback tally, so a broken fixture cannot masquerade as correct coverage. Wired into the build as `make smoke-dialectic` and a dedicated `smoke-dialectic` CI job.

## [3.4.4] - 2026-04-19

### Fixed

- `skills/issue/scripts/parse-input.sh` Description bullet regex now accepts an empty inline value. Previously, `^-[[:space:]]+\*\*Description\*\*:[[:space:]]+(.+)$` required non-empty inline content, so a bullet written as `- **Description**:` with body on continuation lines only failed to match, `IN_BODY` never transitioned to `true`, and both the bullet line and all its continuations were silently dropped from `CURRENT_BODY`. The regex is relaxed to `^-[[:space:]]+\*\*Description\*\*:[[:space:]]*(.*)$` — both trailing quantifiers become zero-or-more, so an empty inline value captures as `""`, `IN_BODY` flips to `true`, and the existing fallback branch populates the body from subsequent continuation lines. `test-parse-input.sh` grows a new case 9 that feeds this shape (empty inline + multi-line continuation including a blank line) and asserts the decoded body, tallied vote count, reviewer, phase, and absence of `ITEM_1_MALFORMED`. Header grammar comment updated to document that the inline value may be empty. Closes #131.

## [3.4.3] - 2026-04-19

### Fixed

- Restored shell-layer secret redaction as defense-in-depth for `/issue` → `gh issue create` (closes #128). `skills/issue/scripts/create-one.sh` now pipes both the issue title (after `redact` + `emit_redaction_failure` split so ISSUE_FAILED/ISSUE_ERROR emissions reach the parent's stdout under command substitution) and the body (at a single structural choke point after all body-assembly paths converge) through the new `scripts/redact-secrets.sh` filter before invoking `gh`, and also redacts captured `gh` stderr on the failure-echo path so auth-failure output with embedded tokens cannot leak. The filter ports the six token families from the deleted `scripts/create-oos-issues.sh:redact_secrets()` — Anthropic/OpenAI `sk-*`, GitHub PATs (`ghp_`, `gho_`, `ghu_`, `ghs_`, `ghr_`, `github_pat_`), AWS long-term `AKIA…`, Slack `xox[baprs]-…`, generic JWT, PEM private keys — but fixes two latent bugs in the original: PEM handling now uses `awk` (not line-oriented `sed` that silently missed multi-line blocks) and the BEGIN/END markers tolerate leading whitespace and markdown `>` blockquote prefixes so indented/quoted keys are still redacted. Unterminated PEM blocks (BEGIN without END) fail-closed and emit a visible `[content truncated — unterminated PEM block…]` marker plus a stderr WARN for operator log visibility (previously the tail was dropped silently). Helper failure fail-closes with a new exit code 3 and `ISSUE_ERROR=redaction:…`. New `scripts/test-redact-secrets.sh` with 45 assertions (unit per family, idempotency, dry-run, end-to-end via stub `gh` covering both success and failure paths, indented/blockquoted PEM, unterminated PEM, missing helper, zero-URL multi-line output) is wired into `make lint` via a new `test-redact` prerequisite so the regression barrier runs on every local and CI invocation. `SECURITY.md` gains an outbound-redaction subsection documenting covered families and explicit non-coverage (AWS STS `ASIA…`, payment provider live keys, opaque bearer tokens, DB connection strings, private hostnames, PII).

## [3.4.2] - 2026-04-19

### Fixed

- `skills/issue/scripts/parse-input.sh` now tracks an explicit per-item `CURRENT_MODE` (`oos` / `generic` / empty) to prevent two bugs where OOS and generic item parsing conflated structure. (a) A markdown subheading like `### Notes` inside an OOS item's Description body no longer triggers a premature `flush_item`; the new generic-heading branch absorbs the line as body continuation when `CURRENT_MODE=oos` AND `IN_BODY=true`, so OOS descriptions may contain `### …` subheadings. (b) Bullet lines `- **Description**:`, `- **Reviewer**:`, `- **Vote tally**:`, and `- **Phase**:` inside a generic item's body are no longer parsed as OOS metadata; the four OOS field branches now fire only when `CURRENT_MODE=oos`, so in generic items those bullets fall through to the `IN_BODY` continuation branch and remain verbatim in `ITEM_<i>_BODY`. `flush_item` resets `CURRENT_MODE` so per-item mode never leaks across items. The top-of-file grammar comment is rewritten to document mode transitions, the `###` absorption rule inside OOS descriptions, and the documented boundary limitation (an incomplete OOS item — Description only, no trailing Reviewer/Vote tally/Phase — followed by a `### …` line absorbs the following line as continuation; feed well-formed 4-field OOS inputs to terminate the body explicitly). New self-contained regression harness at `skills/issue/scripts/test-parse-input.sh` with 8 cases covering both bug reproducers, three well-formed baselines (OOS, generic, mixed complete OOS + generic), a back-to-back complete OOS case (the primary `/implement` Step 9a.1 production shape), a back-to-back generic case, and an executable contract for the documented incomplete-OOS absorption behavior — 52 assertions, all passing. Harness uses a portable `b64_decode()` helper (`-d` / `-D` fallback for macOS BSD base64) and invokes the parser via `bash "$PARSER"` so the exec bit is not required. Not wired into automated CI (deferred as out-of-scope per plan and code review voting); developers run it manually via `bash ${CLAUDE_PLUGIN_ROOT}/skills/issue/scripts/test-parse-input.sh`. Fixes #129.

## [3.4.1] - 2026-04-18

### Changed

- `/design` Step 2a.5 (dialectic Phase 3) now delegates contested-decision adjudication to a **3-judge binary panel** (Claude Code Reviewer subagent + Codex + Cursor) replacing the orchestrator's prior "debate quorum + winner-selection" block (`skills/design/SKILL.md:457-491`). New shared protocol file `skills/shared/dialectic-protocol.md` is structurally parallel to `voting-protocol.md` but semantically independent — uses `DECISION_N` ballot IDs with binary `THESIS | ANTI_THESIS` tokens (no EXONERATE), attribution-stripped `Defense A / Defense B` labels with deterministic position-order rotation (odd decision index → `CHOSEN` is Defense A, even → `ALTERNATIVE` is Defense A), and binary thresholds (3 judges → 2+ majority; 2 judges → unanimous with 1-1 tie → synthesis fallback; <2 judges → synthesis fallback). Judge panel uses repo-wide replacement-first: Claude Code Reviewer subagent replaces any unhealthy external to keep the panel at 3 — the "no Claude substitution" rule applies only to debate execution, not to adjudication. Judge panel re-probes tool health via `scripts/check-reviewers.sh --probe` immediately before launching, with explicit two-key rule (`AVAILABLE=true AND HEALTHY=true`) and judge-local flags that never mutate orchestrator-wide availability. `dialectic-resolutions.md` schema rewritten with structured fields: `Resolution`, `Disposition` (`voted | fallback-to-synthesis | bucket-skipped | over-cap`), `Vote tally`, `Thesis summary`, `Antithesis summary`, and a disposition-specific `Why …` justification. Step 2b parser branches on `Disposition` (only `voted` is binding; other dispositions mean synthesis stands and no antithesis-engagement prose is fabricated). Step 3.5 "still contested" criterion is now Disposition-based (both Behavior block at line 677 and Short-circuit at line 685 updated). Zero-external-judges guard added to both protocol doc and SKILL.md so the all-Claude-inline fallback path does not invoke `collect-reviewer-results.sh` with zero positional args. `docs/collaborative-sketches.md` differentiates debate handling (no Claude substitution) from judge-panel handling (replacement-first at 3) and updates the "How It Works" narrative to reflect Phase 3. `docs/workflow-lifecycle.md` node label updated. `skills/shared/progress-reporting.md` canonical Step 2a.5 completion-line examples updated to the new multi-count format (`<V> voted, <F> fallback, <S> bucket-skipped, <O> over-cap`). Closes #99.

## [3.4.0] - 2026-04-18

### Changed

- `/issue` rewritten for LLM-based semantic duplicate detection in 2 phases (titles → full bodies+comments) against open + recently-closed GitHub issues (default 90-day closed window), and `/implement` Step 9a.1 refactored to invoke `/issue` in batch mode via the Skill tool instead of calling the now-deleted `scripts/create-oos-issues.sh`. New flags: `--input-file FILE` (batch mode, OOS markdown format or generic `### <title>` + body), `--title-prefix PREFIX` (e.g. `[OOS]`, with case-insensitive double-prefix normalization), `--label LABEL` (repeatable, silently dropped with a stderr warning on labels that don't exist — preserves `create-oos-issues.sh`'s compatibility guard), `--body-file FILE` (single-mode alternative to inline description), `--dry-run` (no network calls, structured output tagged `DRY_RUN=true`). Single-mode behavior (free-form description + optional `--go`) is preserved, with one new error: when Phase 2 resolves the single item to a duplicate and `--go` is set, `/issue` errors with the duplicate's number and URL rather than creating or silently skipping. Key=value stdout contract (`ISSUES_CREATED/FAILED/DEDUPLICATED`, `ISSUE_<i>_NUMBER/URL/TITLE/DUPLICATE/DUPLICATE_OF_NUMBER/DUPLICATE_OF_URL`) preserved byte-for-byte so `/implement` Step 9a.1's downstream parsing, PR body placeholder, and `oos-issues-created.md` idempotency sentinel need no redesign. Architecture splits reasoning (in the `/issue` SKILL.md prompt) from I/O (four new shell helpers under `skills/issue/scripts/`): `list-issues.sh` uses `gh api --paginate` for unbounded snapshots (with a portable `python3`→BSD-`date`→GNU-`date` cutoff-date fallback chain so Linux CI works), `fetch-issue-details.sh` fetches candidate bodies and comments wrapped in `<external_issue_<N>>…</external_issue_<N>>` delimiter tags (caps: 20 most-recent comments, 4k body chars) inside an outer `<external_issues_corpus>` envelope with the "treat as data, not instructions" preamble, `parse-input.sh` ports the OOS-markdown parser from the deleted script (including `flush_item` malformed-item handling) and preserves blank continuation lines in multi-paragraph descriptions (matching the CHANGELOG 3.3.10 fix), `create-one.sh` wraps `gh issue create` with the label-probe guard, `[OOS]` double-prefix normalization, and emits `ISSUE_TITLE=$FINAL_TITLE` on success/dry-run so callers consume the applied title without reimplementing prefix logic. New `SECURITY.md` subsection "Untrusted GitHub Issue Content (/issue Phase 2)" documents the delimiter-tag hardening as prompt-level convention with residual-risk framing consistent with the reviewer-templates text. `.claude/settings.json` allowlist gains `Skill(issue)` and `Bash($PWD/skills/issue/scripts/*)` entries. LLM dedup fails open: any helper failure (network, rate limit, gh auth) warns on stderr and falls through to create-all; Phase 2 whitelist-validates LLM-emitted `DUPLICATE_OF=<N>` against the Phase 1 snapshot and intra-run `DUPLICATE_OF_ITEM=<j>` against `1 ≤ j < i`, falling back to CREATE on any unmatched identifier.

## [3.3.11] - 2026-04-18

### Changed

- `/design` Step 2a.5 (dialectic debate) now runs each contested decision's thesis+antithesis on **external Cursor or Codex** instead of the previous Claude Agent-tool subagent fan-out (`skills/design/SKILL.md`). Cap raised from 3 to 5 (`min(5, |contested-decisions|)`); deterministic per-decision bucketing assigns odd-indexed decisions (1, 3, 5) to Cursor and even-indexed (2, 4) to Codex, with both sides of each decision sharing the assigned tool. When the assigned tool is unavailable, the bucket is **skipped entirely** and the Step 2a.4 synthesis decision stands — Claude subagents are never substituted into the dialectic debate path (intentional divergence from the repo-wide replacement-first fallback architecture; see `skills/shared/voting-protocol.md` and Step 3 fallbacks). Option B for the unhealthy-status cascade: dialectic-scoped shadow flags (`dialectic_codex_available`, `dialectic_cursor_available`) snapshot the orchestrator-wide `*_available` at entry; orchestrator-wide flags are never mutated, and the dialectic `collect-reviewer-results.sh` call uses `--write-health /dev/null` so Step 3 plan-review panel integrity is preserved by construction. Per-decision rendered prompts are written to files under `$DESIGN_TMPDIR` and referenced by path in the launch prompt (mirrors the voting-protocol pattern, avoids `cat`-based shell patterns that trigger Claude Code permission prompts). The quorum rule now has a mandatory STATUS pre-check that immediately fails any decision where either side returned `STATUS != OK` from the collector, preventing one-sided binding resolutions from partial-launch cases. Phase 1's tagged-output prompt template bodies, debate quorum rule, winner-selection rule, and `dialectic-resolutions.md` schema are preserved byte-for-byte. `docs/collaborative-sketches.md` is updated with the new cap (3→5), tool-routing description, and a new "Dialectic debate" row in the "Fallback Behavior by Phase" table that documents the no-Claude-substitution rule. Closes #98.

## [3.3.10] - 2026-04-18

### Fixed

- `scripts/create-oos-issues.sh` parser no longer silently drops blank lines inside a multi-line `Description` block. The continuation branch previously guarded on `[[ -n "${line// }" ]]`, which skipped every blank line — so any multi-paragraph OOS description produced by `/design`, `/review`, or (after #118 landed) main-agent dual-write collapsed into a single run-together paragraph in the filed issue body. `IN_DESCRIPTION` is already cleared only by a recognized field marker (`Reviewer:`, `Vote tally:`, `Phase:`) or a new `### OOS_N:` header, so removing the non-blank guard is sufficient to preserve paragraph breaks without capturing structural lines. Fixes #123.

## [3.3.9] - 2026-04-18

### Changed

- `/implement` now files GitHub issues for main-agent-discovered out-of-scope (OOS) pre-existing bugs unconditionally, regardless of mode (`--quick`, `--auto`, `--merge`, `--debug`, `--no-merge`). Previously Step 9a.1 was gated on `quick_mode=false`, so pre-existing code issues discovered by the main agent in quick mode (logged only to `execution-issues.md` under "Pre-existing Code Issues") got buried in the PR body's `<details><summary>Execution Issues</summary>` block and never reached the issue tracker (e.g., `scripts/drop-bump-commit.sh` Guard 4 bug discovered during `/fix-issue 110` / PR #115). The fix introduces a mandatory dual-write contract in `skills/implement/SKILL.md` "Execution Issues Tracking": whenever the main agent appends a `Pre-existing Code Issues` entry to `execution-issues.md`, it MUST also append a corresponding `### OOS_N:` block to a new artifact `oos-accepted-main-agent.md` carrying the same five-field schema (`title`, `Description` with file:line and reproduction context and suggested fix, `Reviewer: Main agent`, `Vote tally: N/A — auto-filed per policy`, `Phase: implement`) used by `/design` and `/review` for reviewer-voted OOS — converging the two pipelines into a single accepted-OOS path. The dual-write rule includes a MUST-strength in-file dedup guard (case-insensitive title match) before append and a MUST-strength sanitization rule for secrets, internal URLs, and PII; correction of an existing entry uses in-place replacement of the same `OOS_N` block, not a second append. Step 9a.1 now reads all three OOS artifacts (`oos-accepted-design.md`, `oos-accepted-review.md`, `oos-accepted-main-agent.md`), dedupes across phases by exact normalized title (matching `create-oos-issues.sh`'s `normalize_title()` algorithm), and feeds the merged set to `create-oos-issues.sh` which already handles dedup against open GitHub issues. The only legitimate hard-skip on Step 9a.1 is now `repo_unavailable=true`. Each early-exit branch (`repo_unavailable=true`, all-empty, idempotent rerun) updates the PR body's "Accepted OOS (GitHub issues filed)" subsection and `| OOS issues filed |` Run Statistics cell directly, eliminating the prior forward-reference bug where early exits left placeholders unfilled. Quick-mode PR body guidance for the Out-of-Scope Observations section is rewritten so the Accepted OOS subsection is populated from main-agent-surfaced items and the Non-accepted subsection carries generic boilerplate that no longer falsely claims items were filed when none existed. `scripts/create-oos-issues.sh` documents `Phase: design|review|implement` in its header (was `design|review`); the issue-body footer is reworded to source-agnostic ("surfaced as an out-of-scope observation during the workflow") instead of falsely asserting "received majority YES votes" for main-agent items; a new `redact_secrets()` shell helper provides a deterministic defense-in-depth backstop for common token patterns (`sk-*`, `ghp_*`, `AKIA*`, `xox*`, JWT, PEM private keys) before `gh issue create` runs. `skills/shared/voting-protocol.md` OOS Reporting bullet is split into two paths (reviewer-voting vs. main-agent dual-write) and a unified-filing summary so the protocol document no longer overstates the "2+ YES" gate as the only path to a filed OOS issue. `/design` and `/review` are unchanged — their existing structured discovery-time writes already follow the canonical pattern and standalone behavior is out of scope for this PR. Closes #118.

## [3.3.8] - 2026-04-18

### Fixed

- `scripts/drop-bump-commit.sh` Guard 4 `ALLOWED_TWO` constant reordered to match `sort`'s ASCII byte ordering (`.claude-plugin/plugin.json` before `CHANGELOG.md`, since `.`=0x2E < `C`=0x43), so the two-file bump+CHANGELOG shape produced by `/implement` Step 8a now matches and the `DROPPED=true` happy path is reachable. Previously the constant's letter-before-dot order meant Guard 4 always rejected two-file bump commits, forcing `/implement`'s Rebase + Re-bump Sub-procedure down the expensive `rebase-push.sh` + Phase 1–4 conflict fallback every time `main` advanced during the CI+merge loop. Also pins the `sort` invocation to `LC_ALL=C` so the documented ASCII-order invariant is enforced rather than assumed, adds a comment on the `ALLOWED_*` constants warning future editors not to "fix" the order back to alphabetical-by-filename, and updates the file header's Guard 4 bullet to state the real contract (`plugin.json`, optionally together with `CHANGELOG.md`). Fixes #117.

## [3.3.7] - 2026-04-18

### Changed

- `/design` Step 2a.5 dialectic debater prompts rewritten per research-backed best practices (Anthropic prompt-engineering docs, multi-agent-debate literature, Karpathy guidance). Each debater template now opens with a narrow role-with-stakes preamble; requires a steelman clause before arguing; demands `file:line` evidence grounding via Read/Grep/Glob at argument time; emits structured tagged output (`<claim>`, `<evidence>`, `<strongest_concession>`, `<counter_to_opposition>`, `<risk_if_wrong>`) with a terminal `RECOMMEND: THESIS|ANTI_THESIS` token; enforces a 250-word prose cap; names anti-patterns to avoid (sycophancy, consensus collapse, vagueness, straw-manning, speculative future-proofing); and tells debaters to "assume the opponent will read your argument." The antithesis template additionally carries the sharpened proportionality instruction. Both templates wrap `{SYNTHESIS_TEXT}` and `{DECISION_BLOCK}` in namespaced `<debater_synthesis>` / `<debater_decision>` delimiters (mirrors the existing `<reviewer_*>` convention) with a split three-clause instruction that preserves required output-tag emission while blocking copy-through from the reference blocks. The orchestrator quorum rule in Step 2a.5 now gates binding resolution on presence of all 5 tags, normalized `RECOMMEND:` line detection (trim + strip `**...**` / `__...__` wrappers before prefix match), case-insensitive enum check with underscore preservation, role-vs-RECOMMEND consistency, a `file:line` citation in `<evidence>`, and retained substantive-output predicate — all as a conjunct. A new winner-selection rule picks the side whose argument is more compelling; resolution maps THESIS→{CHOSEN}, ANTI_THESIS→{ALTERNATIVE}. Fallback warnings are reason-coded. `dialectic-resolutions.md` schema, `skills/shared/voting-protocol.md`, scripts, and all downstream consumers are unchanged. Closes #97.

## [3.3.6] - 2026-04-18

### Changed

- OOS (out-of-scope observation) scoring is now asymmetric (reward-only): accepted OOS items (2+ YES votes) still earn +1 point and file a GitHub issue, but unanimously-rejected OOS now scores 0 instead of -1. Aligns scoring with the reviewer-side instruction to "surface OOS freely" so reviewers are never penalized when voters dismiss an observation in good faith. Updates the canonical scoring table in `skills/shared/voting-protocol.md`, both narrative mirrors (`docs/point-competition.md`, `docs/voting-process.md`), and both runtime reviewer Competition notices (`skills/design/SKILL.md`, `skills/review/SKILL.md`). Also qualifies the EXONERATE "spares a penalty" wording across those files — penalty-sparing now applies only to in-scope findings. Adds a one-sentence OOS quality-gate hint to the voter prompt template so voters can distinguish file-worthy from dismissible observations. Fixes #102.

## [3.3.5] - 2026-04-18

### Changed

- Collapsed `/research` Step 2 (Findings Validation) and `/loop-review` Step 3c (Slice Review) from their dual-Codex / 5-reviewer panels to the canonical 3-reviewer panel used by `/design`, `/review`, and `/implement`: 1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor. `/loop-review` additionally gains a same-slice Runtime Timeout Fallback so a failed external is replaced in-slice (not just in future slices), and switches its collect call to the same dynamic `COLLECT_ARGS=()` pattern `/research` uses so unavailable externals no longer cause sentinel-wait timeouts. Output files consolidate to `codex-validation-output.txt` (research) and `codex-output-slice-N.txt` (loop-review); negotiation files become `codex-negotiation-*.txt` / `cursor-negotiation-*.txt`. Shared docs updated so every reviewer panel in the repo shares the `Code` / `Codex` / `Cursor` attribution shape. Closes #85.

## [3.3.4] - 2026-04-18

### Fixed

- `/fix-issue` auto-pick mode no longer silently caps candidate scanning at the first 100 open issues. `skills/fix-issue/scripts/fetch-eligible-issue.sh` now calls `gh api --paginate repos/{owner}/{repo}/issues?state=open&per_page=100`, filtering PRs out with `select(.pull_request == null)` and slurping the JSONL stream with `jq -s` before the oldest-first sort. Matches the pagination pattern already used by `open_blockers` and the comment fetchers in the same file. Fixes #110.

## [3.3.3] - 2026-04-18

### Fixed

- `docs/review-agents.md` Quality gate paragraph now faithfully summarizes the canonical uniform gate from `skills/shared/reviewer-templates.md` (applies to both In-Scope and Out-of-Scope findings; three-part check of justification, proportionality, and concrete evidence; plus an OOS-specific requirement of a concrete failure mode or breakage path). Previously the doc described the pre-Phase-1 behavior (in-scope only, OOS exempt), directly contradicting reviewer behavior. Closes #103.

## [3.3.2] - 2026-04-18

### Fixed

- `/issue` Step 6 now emits a dedicated URL-only success line (`✅ Created issue — <ISSUE_URL>`) when `gh issue view` fails to resolve the new issue's number. Previously the resolution-failure path routed to Step 6 with only `$ISSUE_URL` available, but all three existing variants embedded `#<ISSUE_NUMBER>` and produced a malformed `✅ Created issue # — <URL>` line. Step 4's cross-reference is updated to point at the new variant.

## [3.3.1] - 2026-04-18

### Changed

- Strengthened `/implement` Step 2 prompt with six research-backed edits to `skills/implement/SKILL.md`: (1) quick-mode inline plan schema at SKILL.md:185 now requires testing strategy and failure modes to match `/design`'s output; (2) new root-cause-discipline bullet in Step 2; (3) new incremental-`/relevant-checks` bullet in Step 2; (4) mode-aware Step 2 lead-in sentence; (5) auto-mode clause at SKILL.md:230 now instructs the agent to log mid-coding interpretations under the "Implementation Deviations" PR-body section; (6) TDD bullet tail now includes a concrete non-TDD verification fallback. Closes #96.

## [3.3.0] - 2026-04-18

### Added

- New `/create-skill` public slash command (`skills/create-skill/SKILL.md`) that scaffolds a new larch-style skill from a name and a description, then delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR). Default writes under `.claude/skills/<name>/` (consumer mode); `--plugin` writes under `skills/<name>/` for plugin-dev mode. `--multi-step` selects a multi-step scaffold template; default is minimal single-step. `--merge` and `--debug` forward to `/implement`.
- New scripts under `skills/create-skill/scripts/`: `parse-args.sh` (flag + positional parsing, leading-`/` strip), `validate-args.sh` (name regex + reserved-name union of Anthropic `{anthropic, claude}` ∪ larch's static list ∪ dynamic `${CLAUDE_PLUGIN_ROOT}/skills` ∪ dynamic `$PWD/.claude/skills`, all case-insensitive; description length, no XML tags, no backticks, no `$(...)`, no heredoc terminators, no newlines or control chars), `render-skill-md.sh` (heredoc-in-shell renderer with atomic `.tmp` + `mv`, two path tokens for consumer-vs-plugin mode, YAML-safe description escaping including backslashes), and `post-scaffold-hints.sh`.
- New entry in `SECURITY.md` documenting `/create-skill`'s description-sanitization design (which patterns are rejected and why they matter for YAML-frontmatter and heredoc-rendering safety).
- Two new permission entries in `.claude/settings.json` (`Bash($PWD/skills/create-skill/scripts/*)` and `Skill(create-skill)`) in strict ASCII code-point order.

### Changed

- `README.md` Skills catalog and feature matrix now list `/create-skill`.

## [3.2.0] - 2026-04-18

### Added

- New `§5 Security` focus area in the Code Reviewer archetype (`skills/shared/reviewer-templates.md` + generated `agents/code-reviewer.md`) covering injection, authN/authZ, secret scanning (with regex hints: `.env`, `AWS_`, `PRIVATE_KEY`, `sk-`, `Authorization: Bearer`), crypto, deserialization, SSRF, path traversal, and dependency CVEs. Review findings may now be tagged with a new `security` focus-area value, extending the enum from 4 to 5 tags (all four prior tags remain valid).
- New `## Adapt scope` section in the archetype instructing reviewers to tailor reviews to doc-only / test-only / revert / rename-only / large-diff / generated-code PRs, plus a security-elevation trigger for changes touching auth, secrets, shelling out, parsing, deserialization, permissions, network boundaries, cryptography, or untrusted input.
- New `## Calibration examples` section with two synthetic few-shot examples (one well-formed `**Important**` finding with evidence, one false-positive suppression) using fake `example://` paths and an explicit "evidence for real findings must come ONLY from the provided review context" instruction.
- New `scripts/generate-code-reviewer-agent.sh` bash generator that emits `agents/code-reviewer.md` from `skills/shared/reviewer-templates.md` (extracts body between `<!-- BEGIN/END GENERATED_BODY -->` markers, strips outer fence by position, substitutes `{REVIEW_TARGET}` = `"code, plans, or conflict resolutions"`, omits `{CONTEXT_BLOCK}`, and performs section-keyed replacement of the two `{OUTPUT_INSTRUCTION}` placeholders). Supports `--check` mode for CI drift detection.
- New `agent-sync` CI job in `.github/workflows/ci.yaml` that runs the generator in `--check` mode and asserts that both the backticked enum (in template + agent + `docs/review-agents.md`) and the unquoted slash-separated enum (in voting-panel SKILL.md prompts) include `security`.

### Changed

- `{CONTEXT_BLOCK}` is now wrapped in namespaced `<reviewer_*>` XML tags (`<reviewer_diff>`, `<reviewer_plan>`, `<reviewer_feature_description>`, `<reviewer_file_list>`, `<reviewer_commits>`, `<reviewer_research_question>`, `<reviewer_research_findings>`, `<reviewer_conflict_context>`) with a prepended instruction sentence that the tags are literal input delimiters. Applied at every call site in `skills/review/SKILL.md`, `skills/design/SKILL.md`, `skills/implement/SKILL.md` (quick-mode + conflict-review), and `skills/research/SKILL.md`. The wrapping is a model-level prompt-injection mitigation, not a parser-enforced security boundary — see `docs/review-agents.md` and `SECURITY.md` for the residual-risk discussion.
- `agents/code-reviewer.md` is now a **generated artifact** — hand edits are forbidden and CI enforces sync with `skills/shared/reviewer-templates.md`. `AGENTS.md` is updated to replace the previous "edit both files in lockstep" rule with "edit the template; regenerate the agent."
- `skills/review/SKILL.md`, `skills/design/SKILL.md`, and `skills/implement/SKILL.md` inline Cursor/Codex prompts now include `(5) Security: injection, authn/authz, secret handling, crypto, deserialization, SSRF, path traversal, dependency CVEs` and enumerate all five focus-area tags for reviewers.
- `docs/review-agents.md`, `docs/agents.md`, `README.md`, and `SECURITY.md` updated to document the new Security lane, the generator-enforced single source of truth, and the XML wrapping with its residual-risk framing.
- `skills/loop-review/SKILL.md` and `skills/research/SKILL.md` external-reviewer prose is intentionally left on the 4-perspective taxonomy (Negotiation Protocol) in this release; editorial rebalancing to the 5-tag vocabulary is tracked as a focused follow-up. The Claude subagent lanes in those skills inherit the 5-tag archetype automatically via `subagent_type: code-reviewer`.

## [3.1.1] - 2026-04-18

### Changed

- Raised the `/implement --quick` single-reviewer code-review loop cap from 5 rounds to 7. The quick-mode re-review gate (`skills/implement/SKILL.md` Step 5.8) now loops while `round_num <= 7` and prints the non-convergence warning when `round_num > 7`; the `--quick` flag description, Step 5 header, body, warning copy, execution-issues log text, and the quick-mode PR-body guidance for the Code Review Voting Tally are updated in lockstep. Reviews that previously exhausted the cap with unresolved findings now have two additional iterations to converge before the warning is emitted. `/review`'s independent normal-mode 5-round cap is unchanged.

## [3.1.0] - 2026-04-18

### Added

- New `/issue` skill (`skills/issue/SKILL.md`) that creates a GitHub issue in the current repository from a free-form description. With the optional `--go` flag, it additionally posts a final `GO` comment on the new issue so it becomes immediately eligible for `/fix-issue` automation without manual approval. `skills/alias/SKILL.md` now reserves the `issue` name so project-level aliases cannot collide with the shipped skill. README install blurb, Skills summary row, and skills table updated to document `/issue`.

## [3.0.7] - 2026-04-18

### Changed

- `/fix-issue` now skips candidates with currently-open blocking dependencies. After an issue passes the `GO` sentinel check, `fetch-eligible-issue.sh` queries GitHub's native issue-dependencies API (`repos/{owner}/{repo}/issues/{N}/dependencies/blocked_by`); if any blocker is still in the `open` state, auto-pick mode continues scanning and explicit `--issue` mode reports ineligible with the blocker list. The dependency lookup uses `gh api --paginate --jq` so results across multiple pages are merged correctly. API errors (404 on repos without the feature, 5xx, transient gh failures) degrade silently to the prior GO-only behavior so dependency-API availability never hard-blocks the automation; the degradation is documented under the skill's Known Limitations.

## [3.0.6] - 2026-04-18

### Changed

- Code Reviewer archetype (`agents/code-reviewer.md` and `skills/shared/reviewer-templates.md`) tuned with severity tags (`**Important**` / `**Nit**` / `**Latent**`, with a PR-introduced-defect tiebreaker), a conservatism header ("when in doubt, say nothing"), an explicit "Do NOT report" exclusion list, a context-sensitive proof-before-report clause for `**Important**` findings (failing scenario or concrete breakage path), a Nit cap of 5 with a required "count plus categories" overflow summary, a tightened Quality gate that applies uniformly to In-Scope and Out-of-Scope findings with review-mode-appropriate evidence (file:line for code review; plan/validation anchors otherwise), Style consistency and red-green-TDD-that-should-have-happened both demoted to `**Nit**`-only, Backward compatibility and Thread safety folded into §2 Breaking changes and §3 Race conditions via cross-references that preserve legacy vocabulary, and the 5-step "Review process" softened into "Review priorities (in order, not a sequence)" to reduce premature stopping or anchoring. Phase 1 is Claude-lane-only — external Codex/Cursor reviewers still run their inline prompts from the individual skill SKILL.md files, so severity tags and the conservatism/exclusion rules reach Claude reviewers and Claude fallbacks only; external-lane alignment is deferred to a follow-up phase. Closes #91.

## [3.0.5] - 2026-04-18

### Changed

- `/research` refactored from a 5+5 lane composition to 3+3. Phase 1 (Research) now launches 3 agents — Claude inline + Cursor + Codex — all running a single uniform `RESEARCH_PROMPT` that requires alternative perspectives, edge cases/gaps, architectural patterns, and risks/feasibility. Phase 2 (Validation) now launches 3 lanes — Codex deep + Codex broad + Cursor generic. Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant in each phase when an external tool is unavailable, with per-slot attribution (Cursor-unavailable → 1 generic Claude lane; Codex-unavailable → 2 Claude lanes, deep + broad). Both phases build a `COLLECT_ARGS` list from only actually-launched externals and skip `collect-reviewer-results.sh` entirely when zero externals are launched. Runtime external timeouts trigger an immediate same-phase Claude fallback so the 3-lane invariant holds at synthesis/negotiation time. Docs, diagram, and progress-reporting examples are synced across `README.md`, `docs/agents.md`, `docs/review-agents.md`, `docs/workflow-lifecycle.md`, `docs/external-reviewers.md`, `docs/collaborative-sketches.md`, `skills/shared/progress-reporting.md`, `skills/shared/voting-protocol.md`, and `skills/research/diagram.svg`.

## [3.0.4] - 2026-04-18

### Changed

- `/implement --quick` code review now uses a single-reviewer loop with the Cursor → Codex → Claude Code Reviewer subagent fallback chain, re-reviewing up to 5 rounds when a round's fixes introduce significant changes. Previously, quick mode ran a single Claude subagent for one round with no re-review. The fallback chain re-evaluates per round so runtime timeouts cascade to the next tier. Step 0 now explicitly sets the `cursor_available`/`codex_available` mental flags consumed by the new Step 5 selection logic.

## [3.0.3] - 2026-04-18

### Fixed

- `/implement` and `/bump-version` no longer touch `$PWD/.git/`. The classify-bump.sh reasoning-log default path moved from `$PWD/.git/bump-version-reasoning.md` to `${TMPDIR:-/tmp}/bump-version-reasoning.md`, and `/implement` Step 8 now parses the absolute path from `classify-bump.sh`'s `REASONING_FILE=<path>` stdout line instead of reconstructing it from `IMPLEMENT_TMPDIR`. Fixes a permission-prompt storm that occurred when the Skill tool invocation lost the env var and `/implement` fell back to copying the reasoning file out of `.git/`.

### Added

- Ten git wrapper scripts under `scripts/` that replace direct `git` commands in `skills/implement/SKILL.md`: `git-current-branch.sh`, `git-amend-add.sh`, `git-force-push.sh` (with internal fetch/compare/retry recovery), `git-sync-local-main.sh`, `git-rebase-skip.sh`, `git-conflict-files.sh`, `git-show-stage.sh`, `git-checkout-ours.sh`, `git-stage.sh`, and `git-push.sh`. Each is pre-approved by `settings.json`'s `Bash($PWD/scripts/*)` rule, so invoking them does not trigger per-command permission prompts. `skills/implement/SKILL.md` updated at every call site (Step 1 branch capture, Step 8a CHANGELOG amend, Rebase + Re-bump Sub-procedure steps 3/4a/5/6, Conflict Resolution Procedure Phase 1 + Phase 4 Exit 3, Step 10/12c CI fix handlers).

## [3.0.2] - 2026-04-18

### Changed

- Renamed the top-level heading in `KARPATHY_CLAUDE.md` from `# CLAUDE.md` to `# KARPATHY_CLAUDE.md` to match the filename.

## [3.0.1] - 2026-04-18

### Added

- `KARPATHY_CLAUDE.md` at repo root — verbatim copy of Andrej Karpathy's coding guidelines (Think Before Coding, Simplicity First, Surgical Changes, Goal-Driven Execution).
- `@KARPATHY_CLAUDE.md` include added to root `CLAUDE.md` after the existing `@AGENTS.md` include, loading the guidelines into developer context when working inside this repo.

## [3.0.0] - 2026-04-18

### Changed

- Reviewer consolidation: `/design` plan review, `/review` code review, and `/implement` Phase 3 conflict-review now run a unified 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor) instead of the previous 5-reviewer panel (2 Claude + 2 Codex + 1 Cursor). `/implement` quick-mode drops from 2 Claude subagents to 1.
- Sketch phase composition changed from 3 Claude + 1 Cursor + 1 Codex to 1 Claude General + 2 Cursor + 2 Codex. The four non-general personalities (Architecture/Standards, Edge-cases/Failure-modes, Innovation/Exploration, Pragmatism/Safety) now live on the external slots (Cursor: Arch + Edge; Codex: Innovation + Pragmatism), with per-slot Claude fallbacks preserving the 5-agent invariant when a tool is unavailable.
- Unified Code Reviewer archetype in `skills/shared/reviewer-templates.md` replaces the previous Reviewer A (General) and Reviewer B (Deep Analysis) archetypes. The new archetype covers code quality, risk/integration, correctness, and architecture in one prompt with mandatory per-finding focus-area tagging.
- Voter 1 canonical label is now `Claude Code Reviewer subagent` in both `/design` and `/review` (previously split between Deep Analysis and General names).
- Attribution strings in round summaries and reviewer competition scoreboards collapse from `General / Deep-Analysis / Codex-General / Codex-Deep-Analysis / Cursor` to `Code / Codex / Cursor`.
- Output file paths for the single Codex review launch are now `codex-plan-output.txt` (design) and `codex-output.txt` (review); the old `codex-general-*` / `codex-deep-*` names are no longer emitted by these skills.
- `skills/research/SKILL.md` and `skills/loop-review/SKILL.md` retained a 5-reviewer composition under the Negotiation Protocol at this version; their two Claude lanes are attributed as `Code Reviewer (broad perspective)` and `Code Reviewer (deep perspective)`, both invoking the unified archetype. (`/research` was later refactored to a 3-lane composition — see subsequent changelog entries.)
- `scripts/reviewer-model-args.sh` gained a `--with-effort` opt-in flag. When passed, it emits `-c model_reasoning_effort="$EFFORT"` for Codex, where EFFORT resolves from `LARCH_CODEX_EFFORT` → `CLAUDE_PLUGIN_OPTION_CODEX_EFFORT` → default `high`. Default (no flag) behavior is unchanged — health probes and negotiation callers do not pass `--with-effort` and therefore remain at Codex's default effort.
- `.claude-plugin/plugin.json` adds `codex_effort` userConfig (default `high`). The plugin-level description is updated to reflect the new reviewer composition.

### Added

- New `agents/code-reviewer.md` agent definition (unified Code Reviewer archetype, model: sonnet, Read/Grep/Glob tools).
- New `LARCH_CODEX_EFFORT` environment variable and `codex_effort` plugin userConfig knob.

### Removed

- `agents/general-reviewer.md` and `agents/deep-analysis-reviewer.md` — replaced by the unified `code-reviewer` agent. **Migration note**: consumers that referenced `general-reviewer` or `deep-analysis-reviewer` directly (via `--agents` or subagent_type references in downstream docs/scripts) must switch to `code-reviewer`.

## [2.3.5] - 2026-04-17

### Added

- Integrated agnix linter for AI agent configuration validation (pre-commit hook, Makefile target, CI job)
- Created `.agnix.toml` config suppressing file-length rules and false positives for this plugin repo
- Fixed all agnix warnings in `AGENTS.md` and `.claude/settings.json`
- Added hook timeout to shipped `hooks/hooks.json` for consumer parity

## [2.3.4] - 2026-04-16

### Changed

- Split `CLAUDE.md` into a thin `@AGENTS.md` include and a new `AGENTS.md` with terse agent-generic editing guidance
- Upgraded agent-lint from v2.2.4 to v2.3.2 and aligned pre-commit, CI, and config syntax (`ignore` → `suppress`)

## [2.3.3] - 2026-04-15

### Added

- Added `agent-lint` v2.2.4 as a pre-commit hook with `--pedantic` flag
- Added `agent-lint` Make target for standalone invocation
- Aligned `--pedantic` flag across all agent-lint invocations (CI action, `/relevant-checks` post-check)

## [2.3.2] - 2026-04-15

### Changed

- Dropped the Description column from the Aliases table in README.md for a leaner two-column layout

## [2.3.1] - 2026-04-15

### Changed

- Changed `/imaq` `argument-hint` from `<feature-description>` to `<arguments>` to match `/im`, signaling that extra flags are forwarded to `/implement`
- Fixed `generate-alias.sh` to emit `<arguments>` as the argument-hint for newly generated aliases

## [2.3.0] - 2026-04-15

### Changed

- Added `.diag` diagnostic files to `run-external-reviewer.sh` for timeout, failure, and empty output cases
- Health check failure banners in `session-setup.sh` now include the specific cause of failure
- `collect-reviewer-results.sh` emits `FAILURE_REASON` field explaining why each non-OK reviewer failed
- Updated `external-reviewers.md` and `voting-protocol.md` to instruct including failure reasons in all user-facing messages

## [2.2.0] - 2026-04-15

### Added

- Migrated `/im` and `/imaq` aliases from project-level (`.claude/skills/`) to plugin-exported (`skills/`) so they ship to all consumers
- Added `Aliases` subsection in README.md Skills section documenting both shortcuts
- Added `/im` and `/imaq` to all skill inventory locations (README, CLAUDE.md, settings.json)
- Added `im` and `imaq` to `/alias` reserved-name list

## [2.1.3] - 2026-04-15

### Added

- `/imaq` project-level alias for `/implement --merge --auto --quick`
- `argument-hint` field emission in `generate-alias.sh` for agent-lint compliance

## [2.1.2] - 2026-04-14

### Added

- `/im` project-level alias for `/implement --merge`
- `Skill(im)` permission entry in `.claude/settings.json` for development harness consistency

## [2.1.1] - 2026-04-14

### Changed

- `/fix-issue` now accepts issue number or URL as a positional argument (e.g., `/fix-issue 42`) instead of requiring the `--issue` flag
- Deprecated `--issue` flag with backward compatibility and runtime deprecation warning
- Added guard against multiple positional arguments in `fetch-eligible-issue.sh`

## [2.1.0] - 2026-04-14

### Changed

- `/alias` now delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR) instead of writing files directly
- Added `--merge` flag to `/alias` to optionally merge the PR after CI passes
- Renamed `claude-lint` CI job to `agent-lint` and upgraded to `zhupanov/agent-lint@v2`
- Renamed `claude-lint.toml` to `agent-lint.toml` and updated all references across codebase

## [2.0.10] - 2026-04-13

### Changed

- Replaced `▶` step start icon with `🔶` (large orange diamond) across all skills for improved visibility
- Added blockquote wrapping (`>`) to step start lines for color differentiation
- Updated all inline `Print:` directives to include full `> **🔶 ...**` format for consistency with the shared progress reporting contract

## [2.0.9] - 2026-04-13

### Changed

- Moved lock step before triage in `/fix-issue` (Step 2 → before read details and triage) to eliminate race conditions where concurrent runs could claim the same issue during triage
- Enhanced triage close to include detailed research summary explaining why the issue is no longer material
- Combined `update-body` + `close` into a single `issue-lifecycle.sh close --pr-url` call, eliminating a consecutive Bash call anti-pattern in Step 7
- Replaced saved `$SLACK_TOKEN`/`$SLACK_CHANNEL` variables with inline env var expansion to eliminate unnecessary env var resolution Bash call in Step 0
- Fixed `cmd_update_body` using `exit` instead of `return` for error paths, which would bypass `cmd_close`'s error guard when called as an internal function

## [2.0.8] - 2026-04-13

### Changed

- Replaced `▸` step start icon with `▶` (filled, more visible) across all skills
- Added 80-char `━` separator line and bold formatting for step start lines
- Expanded elapsed time to all terminal lines: `⏩`, `⏭️`, `❌` (status tables), and step-ending `⚠` — not just `✅`
- Clarified "step-ending ⚠" definition in progress reporting contract

## [2.0.7] - 2026-04-13

### Fixed

- Fixed multi-line description truncation in `scripts/create-oos-issues.sh` — the parser now accumulates continuation lines between `- **Description**:` and the next structured field, preserving full multi-line descriptions in filed GitHub issues

## [2.0.6] - 2026-04-13

### Changed

- Added elapsed time reporting to all `✅` completion indicators — step completion lines show `(<elapsed>)` and compact status tables show timing after each `✅`
- Defined elapsed time format rules in `skills/shared/progress-reporting.md` (central contract)
- Updated all `Print:` directives across all 7 skills to include `(<elapsed>)` placeholders

## [2.0.5] - 2026-04-13

### Changed

- Added deduplication to `create-oos-issues.sh` — fetches open issues before creating new ones and skips creation when a normalized-title match already exists
- Updated SKILL.md Step 9a.1 to document new `ISSUES_DEDUPLICATED` output field and dedup reporting in PR body

## [2.0.4] - 2026-04-13

### Changed

- Replaced OOS promotion with GitHub issue filing — accepted OOS items are filed as issues instead of being implemented in the PR
- Switched OOS scoring from floor-of-0 to symmetric -1/0/+1, matching in-scope finding scoring
- Added `scripts/create-oos-issues.sh` for automated OOS issue creation at PR time
- Updated voter prompt template with OOS-specific vote semantics and output format examples

## [2.0.3] - 2026-04-13

### Removed

- Deleted `scripts/validate-plugin-structure.sh` (25 bash validators) and `scripts/smoke-test.sh` wrapper, superseded by claude-lint
- Removed `plugin-structure` CI job; claude-lint is now the sole structural linter in CI
- Updated GitHub ruleset to require `claude-lint` instead of `plugin-structure`

## [2.0.2] - 2026-04-13

### Fixed

- Added 1-retry to Codex and Cursor health check probes to tolerate transient timeouts

## [2.0.1] - 2026-04-13

### Changed

- Added quality-improvement instructions across all reviewer archetypes: strengthened test coverage emphasis, TDD guidance for implementation, and a proportionality quality gate ("Is it justified? Is it over-engineered?") for reviewers, voters, and the antithesis agent

## [2.0.0] - 2026-04-13

### Changed

- **BREAKING**: Renamed `/fix-issues` skill to `/fix-issue` (singular) to match its single-iteration semantics
- Added `--issue <number-or-url>` flag to `/fix-issue` for targeting a specific GitHub issue instead of auto-picking the oldest eligible one

## [1.4.0] - 2026-04-13

### Added

- New `/fix-issues` skill that processes one approved GitHub issue per invocation: fetches issues with `GO` sentinel, triages against codebase, classifies complexity (SIMPLE/HARD), and delegates to `/implement`
- Added `claude-lint` to `/relevant-checks` validation pipeline (runs after plugin structure validation when available on PATH)

### Fixed

- Added explicit flag-parsing defaults to all 5 skill SKILL.md files to prevent cross-flag contamination where parsing one flag (e.g. `--merge`) could cause the agent to incorrectly set another (e.g. `auto_mode=true`). Each flag now has an explicit `Default:` sentinel and a shared preamble states all boolean flags default to `false` and are independent.

## [1.3.10] - 2026-04-13

### Fixed

- Fixed `mktemp`/`mv` failure when `--write-session-env /dev/null` or `--write-health /dev/null` is passed to session setup scripts. Both `mktemp` and `mv` fail on device nodes on macOS.

## [1.3.9] - 2026-04-13

### Changed

- Updated author/contact email from `sergey@zhupanov.com` to `zhupanov@yahoo.com` in plugin manifests and security policy.

## [1.3.8] - 2026-04-13

### Changed

- Cursor reviewer now defaults to `--model composer-2-fast` when `LARCH_CURSOR_MODEL` is unset, since `cursor agent` CLI does not honor `~/.cursor/cli-config.json` and would otherwise fall back to a potentially rate-limited model.

## [1.3.7] - 2026-04-13

### Added

- `LARCH_CURSOR_MODEL` and `LARCH_CODEX_MODEL` environment variables for controlling which models Cursor and Codex use as external reviewers.
- New `scripts/reviewer-model-args.sh` script that centralizes model flag injection for both tools.
- Plugin `userConfig` entries (`cursor_model`, `codex_model`) as alternative to environment variables.
- Prominent `═══` banner-style warnings in terminal output when Cursor or Codex health checks fail.

## [1.3.6] - 2026-04-13

### Fixed

- Resolved all claude-lint errors: added trigger context to skill descriptions (S017), shortened long descriptions to ≤250 chars (S015), and rewrote descriptions in third person (S016).
- Removed `continue-on-error: true` from claude-lint CI step now that all errors are resolved.

### Added

- `claude-lint.toml` config file disabling the `body-too-long` rule for intentionally long SKILL.md bodies.

## [1.3.5] - 2026-04-13

### Added

- CI job running `claude-lint` via `zhupanov/claude-lint@v1` GitHub Action with explicit `github-token` for version resolution.

## [1.3.4] - 2026-04-12

### Changed

- Replaced per-step emoji progress lines with breadcrumb-style step paths across all 5 skill SKILL.md files (e.g., `▸ 1.2a: design plan | sketches` instead of `🤝 Step 1.2a — Collaborative sketches...`).
- Created `skills/shared/progress-reporting.md` shared formatting contract defining icon taxonomy, breadcrumb format, and `--step-prefix` `::` encoding.
- Extended `--step-prefix` to carry both numeric prefix and textual breadcrumb path (e.g., `"1.::design plan"`), with backward-compatible fallback for numeric-only values.
- Added Step Name Registry tables (<=20-char short names per step) to all 5 skill SKILL.md files.
- Preserved `⏭️`/`⏩` semantic distinction for precondition vs. sub-step skips.

## [1.3.3] - 2026-04-12

### Changed

- Renamed "grilling"/"grill" terminology to "discussion"/"discuss" throughout `/design` skill, `docs/workflow-lifecycle.md`, and prior CHANGELOG entries for clarity.

## [1.3.2] - 2026-04-12

### Changed

- Consolidated skill setup: all 5 skills now call `session-setup.sh` with `--check-reviewers` instead of separate `create-session-tmpdir.sh` + `check-reviewers.sh` + health file write sequences.
- Created `collect-reviewer-results.sh` to consolidate post-launch reviewer output validation, retry, and health tracking across all skills.
- Extended `session-setup.sh` with `--skip-preflight`, `--check-reviewers`, `--write-health`, `--write-session-env` flags.
- Added `.meta` file support to `run-external-reviewer.sh` for retry capability in `collect-reviewer-results.sh`.

### Removed

- Deleted `create-session-tmpdir.sh` (all callers migrated to `session-setup.sh`).

## [1.3.1] - 2026-04-12

### Changed

- Removed pure "done" step-completion announcements from `/implement`, `/design`, and `/review`; only result-bearing completions (with counts/outcomes) and conditional-skip markers are preserved.
- Added internal `--step-prefix` flag to `/design` and `/review` for hierarchical step numbering when called from `/implement` (e.g., Step 1.0, Step 5.2).
- Added internal `--branch-info` flag to `/design` to skip redundant `create-branch.sh --check` when invoked from `/implement`.
- Suppressed rebase-skip messages (`⏩ Rebase skipped — ...`) in non-debug mode in `/implement`.

## [1.3.0] - 2026-04-12

### Added

- External reviewer health probe: `check-reviewers.sh --probe` sends a trivial prompt to each external reviewer (Codex/Cursor) with a 60-second timeout at session startup, catching outages before wasting time on long review timeouts.
- Runtime timeout fallback: when an external reviewer times out during any step, it is replaced by a Claude subagent with similar persona for all subsequent invocations in the session.
- Cross-skill health propagation: reviewer health state flows from `/implement` → `/design` → `/review` via `--session-env` and structured health status files.
- `--session-env <path>` flag for `/review` skill (MINOR: new flag in `argument-hint`).
- `--skip-codex-probe` / `--skip-cursor-probe` flags for `check-reviewers.sh` to avoid re-probing tools already known unhealthy.

### Changed

- `write-session-env.sh`: added `--codex-healthy`/`--cursor-healthy` flags, atomic writes via temp+mv, conditional health key emission.
- `session-setup.sh`: parses and re-emits `CODEX_HEALTHY`/`CURSOR_HEALTHY` from caller-env.
- `external-reviewers.md`: renamed "Binary Check" to "Binary Check and Health Probe", added "Runtime Timeout Fallback" section.

## [1.2.0] - 2026-04-12

### Added

- `--debug` flag for all 5 workflow skills (`/implement`, `/design`, `/review`, `/research`, `/loop-review`). Default (no `--debug`) uses compact output: empty Bash tool descriptions, suppressed explanatory prose, compact reviewer status tables. `--debug` restores verbose output.
- Compact reviewer status table in `/review`, `/design`, and `/research` — replaces per-reviewer individual completion messages with a single reprinted line showing all reviewer statuses.
- Progress Reporting sections for `/review` and `/loop-review` (previously missing).
- Auto-propagation: `/implement` forwards `--debug` to `/design` and `/review`; `/loop-review` forwards to `/implement`.

## [1.1.12] - 2026-04-12

### Added

- Two-round design discussion steps in `/design` skill: Step 1d (pre-sketch, scope/requirements interrogation) and Step 3.5 (post-review, covers decisions not addressed in round 1 or deemed suboptimal by reviewers). Both rounds walk the decision tree one question at a time with recommended answers, explore the codebase first, and are skipped in `--auto` mode.
- New `accepted-plan-findings.md` artifact written during plan review finalization, bridging Step 3 and Step 3.5.

### Changed

- Updated `docs/workflow-lifecycle.md` mermaid diagram to include both discussion nodes in the design phase.

## [1.1.11] - 2026-04-12

### Added

- Validators 24-25 in `validate-plugin-structure.sh`: every `userConfig` entry must have a non-empty `title` string field (V24) and a non-empty `type` string field (V25).

## [1.1.10] - 2026-04-12

### Fixed

- Added missing `title` and `type: "string"` fields to all three `userConfig` entries in `plugin.json` to conform to the Claude CLI plugin manifest schema.

## [1.1.9] - 2026-04-10

### Fixed

- Updated V19 header and function comments to include `LARCH_SLACK_USER_ID` (was stale after adding USER_ID to the loop).
- Moved V23 (`validate_userconfig_sensitive_type`) function definition to after V22 to match numeric and `main()` call order.
- Updated `smoke-test.sh` advisory comment to remove stale `$schema`/`description` examples.

## [1.1.8] - 2026-04-10

### Fixed

- V19: added `LARCH_SLACK_USER_ID` to Slack fallback consistency check (was only checking BOT_TOKEN and CHANNEL_ID).
- V23: extracted from V18 into standalone `validate_userconfig_sensitive_type()` function with own `main()` call, matching the 1-function-per-validator pattern.

### Removed

- Removed `$schema` and top-level `description` from `marketplace.json` — rejected by Claude CLI schema validator. Removed corresponding V12 checks.

## [1.1.7] - 2026-04-10

### Added

- Validators 19-23 in `validate-plugin-structure.sh`: Slack fallback consistency (V19), userConfig key→env var mapping (V20), bidirectional agent-template count (V21), docs file reference existence (V22), userConfig sensitive boolean type check (V23).

### Changed

- Enhanced V16 with bidirectional count check (reviewer-template sections must match agent file count).
- Enhanced V18 with `sensitive` field boolean type validation.
- Narrowed V22 scope to only the Canonical sources section of CLAUDE.md.
- Improved V20 key normalization to handle camelCase and kebab-case keys.

## [1.1.6] - 2026-04-09

### Added

- Four new validators (15-18) in `validate-plugin-structure.sh`: shared markdown reference integrity, agent-template alignment ("Derived from" marker), email format validation, userConfig structure validation.

### Changed

- Cleaned `.claude/settings.json`: removed repo-specific entries (gcloud, kubectl, argocd, K8S_WORK, KUBECONFIG, codeql, temporal, Go tooling, etc.) and PostToolUse auto-goimports hook. Kept `bypassPermissions` for development.
- Deduplicated CI: removed standalone `validate-plugin-structure.sh` step, kept only `smoke-test.sh` as sole entry point.
- Generified `loop-review/SKILL.md`: replaced Go-specific partition examples and file extensions with language-agnostic alternatives across both Step 1 discovery and Step 3b collection.

### Removed

- `scripts/auto-goimports.sh` — Go-specific PostToolUse hook no longer referenced.

## [1.1.5] - 2026-04-09

### Added

- Dialectic debate step (Step 2a.5) in `/design` skill: structured thesis/antithesis debates on contested decisions between synthesis and plan writing.
- Structured contested-decisions schema with `NO_CONTESTED_DECISIONS` sentinel, debate quorum rule, and binding resolution format.
- Documentation for the dialectic debate phase in `docs/collaborative-sketches.md` and `docs/workflow-lifecycle.md`.

## [1.1.4] - 2026-04-09

### Added

- Plugin store readiness: enriched `marketplace.json` (`$schema`, `description`, `owner.email`, `category`) and `plugin.json` (`author.email`, `userConfig` for Slack, enriched `keywords`).
- `SECURITY.md` with minimal security policy, trust model, and external tool delegation documentation.
- `scripts/smoke-test.sh` validation-only smoke test wrapping `validate-plugin-structure.sh` plus advisory `claude plugin validate .`.
- Three new validators (12-14) in `validate-plugin-structure.sh`: marketplace enriched metadata, plugin.json enriched metadata, SECURITY.md presence.
- Prerequisites section in `README.md` split by use case (installation, workflow automation, optional integrations, contributor development).
- `--admin` merge behavior documentation in `README.md` with safety invariants.
- `/relevant-checks` consumer dependency guidance with setup instructions in `README.md`.

### Changed

- Fixed fallback behavior documentation in `docs/external-reviewers.md` and `docs/collaborative-sketches.md` to accurately describe Claude replacement agents maintaining constant participant counts and step-function voting thresholds.
- Replaced dangling cross-references to non-existent `/admin-upgrade-clients` and `/admin-add-user` skills in `scripts/merge-pr.sh` and `skills/implement/SKILL.md` with canonical implementation notes.
- Added `CLAUDE_PLUGIN_OPTION_*` fallback to all Slack-related scripts (`session-setup.sh`, `slack-announce.sh`, `post-pr-announce.sh`, `add-merged-emoji.sh`, `post-merged-emoji.sh`) so plugin `userConfig` Slack tokens propagate end-to-end.
- Updated `CLAUDE.md` to reference 14 validators, document `SECURITY.md` as a protected file, and note `userConfig` env var convention.
- Emphasized Slack env var requirements in `README.md` Environment Variables section with `userConfig` alternative documentation.

## [1.1.3] - 2026-04-09

### Added

- `/implement` Step 8a: automatically updates `CHANGELOG.md` (if present) with a brief summary after the version bump, amending it into the bump commit.
- Backfilled CHANGELOG entries for versions 1.0.3 through 1.1.2.

### Changed

- Updated `drop-bump-commit.sh` Guard 4 to accept `CHANGELOG.md` alongside `plugin.json` in the bump commit, preventing re-bump failures when Step 8a has amended the changelog.
- Added CHANGELOG re-update (step 4a) to the Rebase+Re-bump sub-procedure so changelog entries survive rebases.

## [1.1.2] - 2026-04-09

### Changed

- Added `actions/cache@v4` for pre-commit tool cache in CI, reducing lint job time from ~44s to ~2s on cache hits.
- Flattened `skills/shared/larch/` to `skills/shared/` and updated all path references across 14 files.

## [1.1.1] - 2026-04-09

### Changed

- Increased external reviewer timeouts from 15 to 30 minutes (review/plan review) and 10 to 20 minutes (sketch/voting).
- Added Claude subagent fallbacks for all skills when Cursor/Codex are unavailable, ensuring total reviewer count (5) and voter count (3) remain constant.

## [1.1.0] - 2026-04-09

### Added

- `/alias` skill for creating project-level alias shortcuts that forward to existing larch skills with preset flags. Generates `.claude/skills/<name>/SKILL.md` and commits.

## [1.0.6] - 2026-04-09

### Changed

- Switched `.claude/settings.json` to `bypassPermissions` mode for local development.
- Fixed CLAUDE.md shipped-vs-runtime classification for supplementary files.

## [1.0.5] - 2026-04-09

### Added

- `CLAUDE.md` with editing-agent invariants, repository layout documentation, golden rules for edits, and canonical source references.

## [1.0.4] - 2026-04-09

### Changed

- `/implement` now re-runs `/bump-version` after every rebase in Steps 10 and 12 (the Rebase + Re-bump Sub-procedure), ensuring the merged version reflects `origin/main` at merge time rather than at PR-creation time.

## [1.0.3] - 2026-04-09

### Added

- Plugin structure validator (`scripts/validate-plugin-structure.sh`) with 11 validators covering manifests, frontmatter, path hygiene, script references, executability, and dead-script detection.
- Extended `/relevant-checks` to run the plugin structure validator after pre-commit passes.

## [1.0.2] - 2026-04-08

### Removed

- **Temporary compatibility symlinks introduced in v1.0.1.** Deleted `scripts/larch` (a directory of per-file symlinks pointing back into `../scripts/`, added so that cached skill-prompt references to `${CLAUDE_PLUGIN_ROOT}/scripts/larch/<script>.sh` would still resolve to `${CLAUDE_PLUGIN_ROOT}/scripts/<script>.sh` during the v1.0.1 migration session) and `.claude/scripts/generic/larch` (a symlink pointing at `../../../scripts`, added so that cached `.claude/settings.json` PreToolUse/PostToolUse hook command paths would keep resolving during the migration session). Also removed the now-empty parent directories `.claude/scripts/generic/` and `.claude/scripts/`. The `.claude/settings.json` hook commands were already rewritten in v1.0.1 to `$PWD/scripts/block-submodule-edit.sh` and `$PWD/scripts/auto-goimports.sh`, and all SKILL.md path references were flattened to `${CLAUDE_PLUGIN_ROOT}/scripts/` — so these compatibility shims have no remaining consumers once sessions have restarted. The v1.0.1 follow-up is now complete.
- Corresponding assertions in the `.github/workflows/ci.yaml` `plugin-structure` job that verified the existence of the two compatibility shims.

## [1.0.1] - 2026-04-08

### Added

- `/bump-version` private skill (`.claude/skills/bump-version/`). Classifies and applies a semantic version bump based on the branch diff against `origin/main`. **Only inspects the public plugin surface** (`skills/**` and `agents/**`); changes under `.claude/**`, `scripts/**`, `hooks/**`, `docs/**`, `.github/**`, `CHANGELOG.md`, etc. default to PATCH. Uses deterministic shell + `jq` heuristics (MAJOR on skill/agent deletion or rename, `name:` frontmatter change, or flag removal; MINOR on new skill/agent or new flag) with an **escalation-only** caveat clause: after the classifier runs, the main agent may escalate PATCH → MINOR → MAJOR if a behavioral change would be judged backward-incompatible by a reasonable client, but may never downgrade. The classifier is idempotent — it detects an already-bumped branch (via `^Bump version to X.Y.Z$` commit subject) and emits `BUMP_TYPE=NONE` to skip double-bumps. Writes decision reasoning to `${IMPLEMENT_TMPDIR:-$PWD/.git}/bump-version-reasoning.md` for embedding in the PR body.
- `<details><summary>Version Bump Reasoning</summary>` section in `/implement` Step 9a PR body template, populated from the reasoning file written by `/bump-version`.

### Changed

- **Flattened scripts layout.** Moved all 38 scripts from `scripts/larch/*` to `scripts/*` and rewrote every `${CLAUDE_PLUGIN_ROOT}/scripts/larch/` reference across skill docs (`skills/{design,implement,review,research,loop-review}/SKILL.md`), shared docs (`skills/shared/larch/{external-reviewers,voting-protocol}.md`), `hooks/hooks.json`, `.claude/settings.json`, and `.github/workflows/ci.yaml`. Added a temporary compatibility shim `scripts/larch/` (a directory of 38 per-file symlinks, each pointing back into `../scripts/` — e.g. `scripts/larch/session-setup.sh -> ../session-setup.sh`) to preserve path resolution for in-flight `/implement` sessions whose cached skill prompts still reference the old path. To be removed in a follow-up PR.
- **Removed legacy `.claude/` compatibility symlinks.** Deleted `.claude/skills/{design,implement,review,research,loop-review,shared}` and `.claude/agents/{deep-analysis-reviewer,general-reviewer}.md`. The plugin is discovered via `${CLAUDE_PLUGIN_ROOT}` when launched with `claude --plugin-dir .` or via the local marketplace, so these legacy symlinks are no longer load-bearing. `.claude/skills/` remains as a real directory for private repo-specific skills (`relevant-checks`, `bump-version`).
- **Repointed `.claude/scripts/generic/larch`** from `../../../scripts/larch` to `../../../scripts` so that cached hook command paths in the running Claude Code session (loaded at startup from `.claude/settings.json`) continue to resolve to `scripts/block-submodule-edit.sh` and `scripts/auto-goimports.sh` after the scripts migration. To be removed in a follow-up PR after all sessions have restarted.
- **Updated `.claude/settings.json`.** Rewrote PreToolUse/PostToolUse hook command paths from `$PWD/.claude/scripts/generic/larch/*` to `$PWD/scripts/*`. Consolidated the Bash permission allowlist: replaced `Bash($PWD/scripts/larch/*)` and `Bash($PWD/.claude/scripts/generic/larch/*)` with `Bash($PWD/scripts/*)`. Added `Skill(bump-version)` and `Bash($PWD/.claude/skills/bump-version/scripts/*)` for the new skill. Removed stale entries for `$PWD/.claude/skills/implement/scripts/*` and `$PWD/.claude/skills/loop-review/scripts/*` (the underlying symlinks were deleted).
- **Simplified CI `plugin-structure` job** (`.github/workflows/ci.yaml`). Removed the `.claude/skills/*` and `.claude/agents/*.md` symlink verification loop. Replaced the `scripts/larch/block-submodule-edit.sh` path check with `scripts/block-submodule-edit.sh`. Added checks for the two remaining compatibility symlinks (`scripts/larch` and `.claude/scripts/generic/larch`).
- **Updated `docs/agents.md` and `docs/review-agents.md`** to reference `agents/*.md` and `skills/shared/larch/reviewer-templates.md` instead of the deleted `.claude/*` paths.

## [1.0.0] - 2026-04-08

Initial release of larch as a Claude Code plugin.

### Added

- `.claude-plugin/plugin.json` manifest declaring the plugin name, version, and metadata.
- `.claude-plugin/marketplace.json` local marketplace catalog for `claude plugin marketplace add .`.
- `hooks/hooks.json` registering a PreToolUse hook that runs `block-submodule-edit.sh` for Edit and Write tool calls. The hook prevents Claude Code from editing files inside any git submodule of the user's repo.
- `CHANGELOG.md` (this file).
- New CI job `plugin-structure` that validates the plugin layout without requiring the `claude` CLI.

### Changed

- **Repo restructured for plugin layout.** Skills, agents, and scripts have moved from `.claude/` to the repo root:
  - `.claude/skills/{design,implement,review,research,loop-review,shared}` → `skills/{...}`
  - `.claude/agents/*.md` → `agents/*.md`
  - `.claude/scripts/generic/larch/*` → `scripts/larch/*`
  - Symlinks under `.claude/` (`.claude/skills/*`, `.claude/agents/*`, `.claude/scripts/generic/larch`) preserve the legacy paths for existing tooling and for the private `/relevant-checks` skill.
- Path references in plugin-exported SKILL.md files and shared docs rewritten from `$PWD/.claude/scripts/generic/larch/` and `` `.claude/skills/shared/larch/`` to `${CLAUDE_PLUGIN_ROOT}/scripts/larch/` and `${CLAUDE_PLUGIN_ROOT}/skills/shared/larch/`. Paths in `.claude/skills/implement/` and `.claude/skills/loop-review/` also switched to `${CLAUDE_PLUGIN_ROOT}/skills/{implement,loop-review}/scripts/`.
- `.claude/settings.json` gained three defensive Bash permissions to cover the new canonical script locations: `$PWD/scripts/larch/*`, `$PWD/skills/implement/scripts/*`, and `$PWD/skills/loop-review/scripts/*`.
- `README.md` installation section replaced with a plugin-based install flow covering GitHub and local development paths.

### Removed

- `setup-larch.sh` (legacy git-submodule installer, superseded by the Claude Code plugin flow).
- `tests/test-setup-larch.sh` integration test and the CI job that invoked it.

### Notes for contributors (repo self-use)

Contributors working on larch itself should launch Claude Code with `--plugin-dir .` from the repo root so that `${CLAUDE_PLUGIN_ROOT}` resolves to the repo root and plugin-exported skills can find their scripts:

```bash
cd larch
claude --plugin-dir .
```

Alternatively, register the repo as a local marketplace and install:

```bash
claude plugin marketplace add .
claude plugin install larch@larch-local
```

The private `/relevant-checks` skill (at `.claude/skills/relevant-checks/`) is intentionally not exported as part of the plugin; each consuming repo maintains its own version.
