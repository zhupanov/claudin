# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
