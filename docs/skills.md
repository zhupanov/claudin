# Skills

Reference for every slash command shipped by the larch plugin. Each section below covers one skill: invocation, arguments, behavior, and links to the canonical `SKILL.md` source.

- [`/alias`](#alias)
- [`/compress-skill`](#compress-skill)
- [`/create-skill`](#create-skill)
- [`/design`](#design)
- [`/fix-issue`](#fix-issue)
- [`/implement`](#implement)
- [`/issue`](#issue)
- [`/relevant-checks`](#relevant-checks)
- [`/research`](#research)
- [`/review`](#review)
- [`/simplify-skill`](#simplify-skill)
- [`/umbrella`](#umbrella)

## `/alias`

**Arguments**: `[--merge] [--no-slack] [--private] <alias-name> <target-skill> [preset-flags...]`

**Source**: [`skills/alias/SKILL.md`](../skills/alias/SKILL.md)

Create an alias for a larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR). `--merge` also merges the PR.

**Target directory** is auto-resolved: inside a Claude plugin source repo (detected by the two-file predicate `.claude-plugin/plugin.json` AND `skills/implement/SKILL.md` at the git repo root), the alias is generated under `skills/<alias-name>/SKILL.md` (exported plugin skill, ships with the plugin); anywhere else, it's generated under `.claude/skills/<alias-name>/SKILL.md` (dev-only repo-private). `--private` forces `.claude/skills/<alias-name>/` even inside a plugin repo (escape hatch); in non-plugin repos it's a no-op.

`--no-slack` (when placed before the first positional) forwards to the `/implement` invocation so the alias-creation PR does NOT post to Slack; `--no-slack` placed after the first positional is passed through verbatim as a preset flag for the generated alias.

Example (in a plugin repo): `/alias i implement --merge` creates `<repo-root>/skills/i/SKILL.md` so that `/i <feature>` is equivalent to `/implement --merge <feature>`.

Example with `--private` or in a consumer repo: `/alias i implement --merge` creates `<repo-root>/.claude/skills/i/SKILL.md` (dev-only).

## `/compress-skill`

**Arguments**: `[--debug] [--no-slack] <skill-name-or-path>`

**Source**: [`skills/compress-skill/SKILL.md`](../skills/compress-skill/SKILL.md)

Compress an existing skill's Markdown prose to reduce size while preserving meaning. Discovers the transitive `.md` set (restricted to the skill's own directory tree — shared docs and sub-skills are excluded), snapshots baseline sizes, and delegates a behavior-preserving prose rewrite to `/imaq` applying Strunk & White's *Elements of Style* adapted for technical writing. Structural elements (YAML frontmatter, fenced code blocks, headings, link targets, inline code, file paths, numeric values) are preserved verbatim; only prose is rewritten. PR body includes a `## Token budget` section with per-file before/after byte and line deltas. `--no-slack` forwards to `/imaq` (and thence to `/implement`) so the compression run does NOT post a Slack announcement.

## `/create-skill`

**Arguments**: `[--plugin] [--multi-step] [--merge] [--debug] [--no-slack] <skill-name> <description>`

**Source**: [`skills/create-skill/SKILL.md`](../skills/create-skill/SKILL.md)

Scaffold a new larch-style skill from a name and description. Validates the name (regex + reserved-name union + case-insensitive collision) and the description (length + XML / shell-dangerous pattern rejection), then delegates to `/im --quick --auto` which writes the scaffold via `skills/create-skill/scripts/render-skill-md.sh` and auto-merges the PR (via `/im`'s `--merge` pre-set). Default target is `.claude/skills/<name>/` (consumer mode); `--plugin` writes to `skills/<name>/`. `--multi-step` emits a multi-step scaffold; default is minimal. `--merge` is accepted as a backward-compat no-op since `/im` already auto-merges. `--no-slack` forwards to `/im` (and thence to `/implement`) so the scaffold run does NOT post a Slack announcement. See `skills/shared/skill-design-principles.md`.

## `/design`

**Arguments**: `[--auto] [--quick] [--debug] <feature description>`

**Source**: [`skills/design/SKILL.md`](../skills/design/SKILL.md) · [Diagram](../skills/design/diagram.svg)

Design an implementation plan with collaborative multi-reviewer review. 9 sketch agents in regular mode (1 Claude + 4 Cursor + 4 Codex, one per personality per tool), or 3 in quick mode (1 Claude + 1 Cursor-Generic + 1 Codex-Generic), independently propose architectural approaches, then a **dialectic debate + 3-judge binary panel** resolves up to 5 contested decisions (bucketed Cursor/Codex debaters with bucket-skip fallback; Claude/Cursor/Codex judges with replacement-first fallback; attribution-stripped ballot with position rotation — see `skills/shared/dialectic-protocol.md`), then a 6-reviewer panel (1 Claude Code Reviewer + 1 Codex generic + 4 Cursor archetypes) validates the full plan. `--auto` suppresses all interactive question checkpoints. `--quick` runs the 3-agent sketch phase instead of 9. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/fix-issue`

**Arguments**: `[--debug] [--no-slack] [--no-admin-fallback] [<number-or-url>]`

**Source**: [`skills/fix-issue/SKILL.md`](../skills/fix-issue/SKILL.md)

Process one approved GitHub issue per invocation. Step 0 (`find-lock-issue.sh`) atomically finds an eligible candidate (open, with `GO` sentinel comment as last comment, no managed lifecycle title prefix, not already locked, no open blocking dependencies via GitHub's native blocked-by API plus conservative prose-keyword scanning — `Depends on #N`, `Blocked by #N`, etc., with fail-open posture), acquires the comment lock, and renames the title to `[IN PROGRESS]` so the visual lifecycle reflects the active run immediately. Triages, and classifies intent (PR/NON_PR) and — for PR tasks — complexity (SIMPLE/HARD). PR tasks delegate to `/implement` with `--issue $ISSUE_NUMBER` forwarded so the queue issue is adopted as the tracking issue (no separate tracking issue is created); NON_PR tasks run inline (typically filing findings via `/issue`) and never call `/implement`. With a number or URL argument, targets a specific issue instead of auto-picking. Single-iteration design — the caller handles repetition. `--no-slack` is forwarded to the delegated `/implement` run (suppressing its Step 16a issue Slack post) AND suppresses `/fix-issue`'s own Step 7 NON_PR-path Slack announcement. Default (no `--no-slack`): both paths post per `/implement`'s default-on behavior (gated on Slack env vars). `--no-admin-fallback` is forwarded to the delegated `/implement` run on both SIMPLE and HARD paths so the run bails to Step 12d on branch-protection denial instead of retrying with `--admin`.

**Umbrella support (explicit-target only)**: when `/fix-issue <umbrella#>` is invoked on an umbrella issue (detected post-#846 by title-only — title prefix `Umbrella:` / `Umbrella —` after stripping leading bracket-blocks per #819; body content is NOT consulted), `/fix-issue` dispatches to the umbrella's next eligible child instead of working on the umbrella body itself. Neither the umbrella nor the chosen child needs a `GO` comment — the umbrella's existence is the approval signal and children inherit approval. Children are parsed from markdown task-list items (`- [ ] #N — ...`) in body order; cross-repo references (`owner/repo#N`) and prose `#N` mentions are NOT considered children. When all parsed children close, the umbrella is automatically renamed to `[DONE]`, gets a closing comment posted, and is closed (idempotent: concurrent finalize attempts won't double-comment). Auto-pick mode (no positional argument) NEVER selects umbrellas — the umbrella state machine is opt-in only via explicit positional argument; the auto-pick scan keeps its `GO`-tail invariant unchanged. See `skills/fix-issue/SKILL.md` Known Limitations for the full umbrella contract.

## `/implement`

**Arguments**: `[--quick] [--auto] [--merge | --draft] [--no-slack] [--no-admin-fallback] [--debug] [--issue <N>] <feature description>`

**Source**: [`skills/implement/SKILL.md`](../skills/implement/SKILL.md) · [Diagram](../skills/implement/diagram.svg)

Full end-to-end feature workflow — design, implement, PR, issue Slack announce (on by default when Slack env vars are configured). `--quick` skips `/design` and uses a simplified single-reviewer loop of up to 7 rounds with a per-round `Cursor → Codex → Claude Code Reviewer subagent` fallback chain (no voting panel; main agent unilaterally accepts or rejects each finding). `--auto` suppresses all interactive question checkpoints. `--merge` additionally runs the CI+rebase+merge loop, local branch cleanup, and main verification (without `--merge`, the PR is created and the workflow stops after the initial CI wait and reports). `--draft` creates the PR in draft state and skips local cleanup so the branch is kept for further iteration; mutually exclusive with `--merge`. Near the end of every run (Step 16a), a single status message about the tracking issue is posted to Slack: `<emoji> <GitHub link|Issue #N> (<title>) — <status>`. Emoji: ✅ closed (PR merged + issue auto-closed), 📝 PR opened but not merged (`--merge` not set or `--draft`), ❌ blocked (CI failure, merge failure, or Step 12d bail), ❓ needs user input (auto-mode conflict bail). The post uses the git user identity (`git config user.name` → Slack `username`). Requires `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID`. Pass `--no-slack` to opt out. `--no-admin-fallback` opts out of the silent `--admin` retry on branch-protection denial — when set, `merge-pr.sh` returns `MERGE_RESULT=policy_denied` instead of invoking `gh pr merge --admin`, and `/implement` bails to Step 12d. Default behavior is unchanged when not set; when `--admin` does fire (default path), Step 12b posts a best-effort PR comment recording the bypass. `--issue <N>` attaches `/implement` to an existing tracking issue (Step 0.5 adoption); otherwise a fresh tracking issue is created at Step 0.5 Branch 4. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/issue`

**Arguments**: `[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [<issue description>]`

**Source**: [`skills/issue/SKILL.md`](../skills/issue/SKILL.md)

Create one or more GitHub issues with LLM-based semantic duplicate detection. Two modes: single (free-form description) and batch (`--input-file`). 2-phase dedup against open + recently-closed issues (default 90-day window). `/implement` Step 9a.1 calls this skill in batch mode to file OOS issues. `--go` posts a final `GO` comment on each newly-created issue so it becomes eligible for `/fix-issue` automation; works in both single and batch modes (duplicates, failed creates, and dry-run items never receive a GO comment). In single mode, if the sole item resolves to a duplicate, `--go` errors out; in batch mode, per-item duplicates are simply skipped for the GO comment.

**Always-on inter-issue blocker-dependency analysis** (issue #546): every invocation analyzes the new item(s) against existing OPEN issues and applies hard GitHub-native blocker dependencies via the Issue Dependencies REST API on detected pairs (merge-conflict risk or "must land first"). Hard-fail with retries (3 tries, 10s/30s sleeps); on retry exhaustion the failed item is rolled back (orphan close) — when multiple items are processed, unrelated items continue — and the run exits non-zero if any item failed, yielding a clean "create-then-close" recovery rather than a dangling issue with missing dependency wiring.

## `/relevant-checks`

**Arguments**: *(none)*

**Source**: [`.claude/skills/relevant-checks/SKILL.md`](../.claude/skills/relevant-checks/SKILL.md)

Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint, gitleaks) scoped to changed files (except gitleaks, which always scans the full working tree; see the relevant-checks skill). Invoked automatically by `/implement` and `/review` after code changes. **Not part of the plugin surface; each consuming repo provides its own.**

## `/research`

**Arguments**: `[--debug] [--plan] [--interactive] [--scale=quick|standard|deep] [--adjudicate] [--keep-sidecar[=PATH]] [--token-budget=N] [--no-issue] <research question or topic>`

**Source**: [`skills/research/SKILL.md`](../skills/research/SKILL.md) · [Diagram](../skills/research/diagram.svg)

Collaborative best-effort read-only research with a scale-aware lane shape. **Adaptive scaling is the default**: a deterministic shell classifier (`skills/research/scripts/classify-research-scale.sh`) inspects the question at Step 0.5 and picks `quick|standard|deep` automatically; `--scale=quick|standard|deep` is a manual override (e.g., for CI/eval determinism), and on classifier failure `RESEARCH_SCALE` falls back to `standard`.

- `--scale=standard` (manual override; also the classifier-fallback bucket): 3 research agents (Cursor + Codex + Claude inline) **angle-differentiated per lane** (Cursor → `RESEARCH_PROMPT_ARCH` for architecture; Codex → `RESEARCH_PROMPT_EDGE` for edge cases by default or `RESEARCH_PROMPT_EXT` for external comparisons when `external_evidence_mode=true`; Claude inline → `RESEARCH_PROMPT_SEC` for security) + 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant when an external tool is unavailable; the fallback subagent carries the same angle prompt the failed lane would have run.
- `--scale=quick`: **K=3 homogeneous Claude Agent-tool lanes with vote-merge synthesis** (issue #520 — evolved from 1 inline lane). Same `RESEARCH_PROMPT_BASELINE` across K lanes; diversity comes from natural variability across parallel Agent-tool returns, not from cross-tool diversity (all lanes are Claude). Step 2 (the validation panel) does not run, but the final report still renders a 0-reviewer Validation phase placeholder line so the report shape is uniform across scales. Synthesis carries a "K-lane voting confidence" disclaimer that explicitly names correlated-error risk (same model + same prompt — voting catches independent stochastic errors only); partial failure (`LANES_SUCCEEDED == 1`) falls back to the existing "single-lane confidence" disclaimer; total failure (`LANES_SUCCEEDED == 0`) hard-fails the research phase. Useful for cheap lookups where K-lane voting absorbs single-lane variance; avoid for security-sensitive questions (use `--scale=standard` or `--scale=deep`).
- `--scale=deep`: 5 research lanes (Claude inline running baseline `RESEARCH_PROMPT_BASELINE` + 2 Cursor slots and 2 Codex slots carrying the four diversified angle prompts `RESEARCH_PROMPT_ARCH` / `RESEARCH_PROMPT_EDGE` / `RESEARCH_PROMPT_EXT` / `RESEARCH_PROMPT_SEC` for architecture / edge cases / external comparisons / security) + 5-reviewer validation panel (the standard 3 plus 2 extra Claude Code Reviewer subagents `Code-Sec` and `Code-Arch` carrying lane-local emphasis on the unified Code Reviewer archetype — NOT new agent slugs). The synthesis must explicitly name the four diversified angles so the operator can see they were genuinely covered.

**Optional `--plan` (planner pre-pass — supported with `--scale=standard` or `--scale=deep`)**: when set, a single Claude Agent subagent decomposes `RESEARCH_QUESTION` into 2–4 focused subquestions before the lane fan-out. Each lane researches its assigned subquestion(s) under a per-scale assignment table:

- **Standard scale** (3 lanes): N=2 → all lanes get the union; N=3 → one per lane; N=4 → lane 1 (Cursor) gets two, lanes 2 (Codex) and 3 (Claude inline) get one each. Synthesis is organized by `### Subquestion N` sub-sections + a final `### Cross-cutting findings` sub-section.
- **Deep scale** (5 lanes — issue #519): a balanced partial-matrix ring rotation across the 4 named-angle slots (Cursor-Arch, Cursor-Edge, Codex-Ext, Codex-Sec) — angle lane k gets `s_{((k-1) mod N)+1}, s_{(k mod N)+1}` — plus a Claude-inline integrator lane (lane 5) that unions all subquestions. At N=2 the ring degenerates to full union; at N=3/4 every subquestion appears in at least one named-angle lane plus the integrator. Synthesis is organized by `### Subquestion N` sub-sections + a `### Per-angle highlights` sub-section that names the four canonical angles (architecture & data flow, edge cases & failure modes, external comparisons, security & threat surface) + a `### Cross-cutting findings` sub-section. Each lane's existing angle base prompt is augmented with the per-lane subquestion suffix — angle identity is preserved alongside the planner subquestion focus.

Falls back cleanly to single-question mode on any planner failure (count out of [2,4], empty output, prose-only reply, timeout) with a visible warning. Standard-mode fallback uses each lane's existing angle base prompt (Cursor → `RESEARCH_PROMPT_ARCH`, Codex → `RESEARCH_PROMPT_EDGE` or `_EXT`, Claude inline → `RESEARCH_PROMPT_SEC`) with no per-lane suffix — exactly the existing standard-mode lane shape. Deep-mode fallback uses the existing angle base prompts on the 4 external slots and baseline `RESEARCH_PROMPT_BASELINE` on Claude-inline — exactly the pre-#519 deep-mode shape (the planner failure path does NOT collapse to a generic baseline prompt on the angle slots, in either standard or deep mode). Default off — byte-equivalent to pre-#420 behavior on the no-`--plan` path. **Not applicable to `--scale=quick`** (single lane → no decomposition benefit); the incompatible combination downgrades `--plan` to off with a visible warning at the start of Step 1.

**Optional `--interactive` (operator review of subquestions — issue #522, requires `--plan`)**: when set, pauses Step 1.1 after the planner pre-pass and prints the proposed 2–4 subquestions for operator review. Operator presses Enter to proceed, types `edit` to revise the list (via `$EDITOR` if set, or stdin fallback otherwise), or types `abort` to exit cleanly with `cleanup-tmpdir.sh` ran. Operator edits are re-validated through `run-research-planner.sh` (same `?`-suffix, 2–4 count, and `||`-rejection rules as planner output) with one bounded retry on failure. Hard-fails BEFORE the planner subagent runs when stdin is not a TTY (CI environments — operator opted into interactive mode but the environment doesn't support it). Deep mode confirms only the subquestion list — the per-lane subq×angle pairing (ring-rotation matrix in Step 1.2) stays mechanical regardless. **Not applicable to `--scale=quick`**: when `--plan` is auto-disabled by `--scale=quick`, `--interactive` becomes a no-op with a visible "ignored" notice and the run continues. SIGINT (Ctrl-C) does NOT run the cleanup recipe — only typed `abort` does (operators wanting cleanup on Ctrl-C should use `abort` instead). Default off — byte-equivalent to pre-#522 behavior on the no-`--interactive` path.

**Step 2.7 — Citation Validation (issue #516, unconditional)**: between Step 2.5 (adjudication) and Step 3 (final report) the deterministic shell validator `skills/research/scripts/validate-citations.sh` extracts cited URLs / DOIs / file:line references from the synthesis, HEAD-fetches URLs under SSRF guards (HTTPS-only, `--max-redirs 0`, `--noproxy '*'`, RFC1918/IPv6 link-local/RFC6598 hostname pre-rejection, DNS resolved-IP private-range check, connection-pinning via `--resolve` to mitigate rebinding TOCTOU), validates DOIs syntactically + via `doi.org` HEAD, and spot-checks file:line ranges against the git tree (with `realpath` containment). Output is a 3-state ledger (PASS / FAIL / UNKNOWN with reason classifier) sidecar at `$RESEARCH_TMPDIR/citation-validation.md` that Step 3 splices as a `## Citation Validation` section into `research-report-final.md`. Fail-soft: per-claim failures surface as advisory warnings only; the validator always exits 0; Step 3 is never blocked. Domain-credibility heuristic is advisory only — never flips PASS to FAIL. The validator costs zero measurable Claude tokens (shell only) and runs on every scale (quick / standard / deep).

All scales produce a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict (the report's lane-count headers reflect the configured scale dynamically). With `--adjudicate` (default off, composes with any `--scale` and with `--plan`), runs an additional 3-judge dialectic adjudication step (Step 2.5) over reviewer findings the orchestrator rejected during validation merge/dedup; majority binds, with reinstated findings folded into the validated synthesis before the report renders — see [`skills/research/references/adjudication-phase.md`](../skills/research/references/adjudication-phase.md). When `--scale=quick` is set, Step 2 is skipped so there are no rejections to adjudicate and Step 2.5 short-circuits cleanly.

**Token telemetry and budget** (`--token-budget=N`): Step 4 always renders a `## Token Spend` section before tmpdir cleanup, summarizing per-phase Claude subagent tokens (lanes whose Agent-tool return carries `<usage>total_tokens: N</usage>`). Claude inline (orchestrator) and external lanes (Cursor/Codex) are unmeasurable and excluded from the totals; the report labels itself "Claude tokens only" so the operator sees the coverage honestly. Optional `--token-budget=N` enforces a cap between phases (after Steps 1, 2, 2.5) — on overage, the run aborts before the next phase, skips Step 3 entirely, and renders the partial token report with the `(aborted: budget exceeded)` completion suffix. Budget governs measurable Claude subagent tokens only; unmeasurable lanes are reported separately. When env var `LARCH_TOKEN_RATE_PER_M` is set (USD per million tokens), the report includes a `$` cost column. See [`scripts/token-tally.md`](../scripts/token-tally.md) for the helper contract. Tracked repo files are not modified by the Claude `Edit | Write | NotebookEdit` tool surface — scratch writes are permitted only under canonical `/tmp` (enforced mechanically by the skill-scoped `scripts/deny-edit-write.sh` PreToolUse hook). Bash and external Cursor/Codex reviewers run with full filesystem access and are prompt-enforced only — see [`SECURITY.md` § External reviewer write surface in /research](../SECURITY.md#external-reviewer-write-surface-in-research). Step 3.5 auto-archives the full report as a GitHub issue on each successful run (via `/issue` single mode); `--no-issue` skips this step. `/issue` may also be invoked when the research brief calls for filing findings as issues.

## `/review`

**Arguments**: `[--debug]`

**Source**: [`skills/review/SKILL.md`](../skills/review/SKILL.md) · [Diagram](../skills/review/diagram.svg)

Code review current branch changes with a 6-reviewer specialist panel (5 Cursor specialists + 1 Codex generic), implementing accepted suggestions in a recursive loop (up to 7 rounds: 3 full-panel rounds with voting, then up to 4 single-reviewer rounds). Reviews the diff between main and HEAD.

## `/simplify-skill`

**Arguments**: `[--debug] [--no-slack] <skill-name>`

**Source**: [`skills/simplify-skill/SKILL.md`](../skills/simplify-skill/SKILL.md)

Refactor an existing larch skill for stronger adherence to `skills/shared/skill-design-principles.md` and to reduce SKILL.md token footprint. Resolves the target skill directory (plugin tree first, then consumer `.claude/skills/`), enumerates every `.md` file under it (excluding `scripts/` and `tests/`), does NOT follow sub-skills invoked via the `Skill` tool, and delegates the refactor to `/im` with a pinned behavior-preserving feature description that requires a `## Token budget` section in the PR body. `--no-slack` forwards to `/im` (and thence to `/implement`) so the refactor run does NOT post a Slack announcement. Example: `/simplify-skill implement`.

## `/skill-evolver`

**Arguments**: `[--debug] <skill-name>`

**Source**: [`skills/skill-evolver/SKILL.md`](../skills/skill-evolver/SKILL.md)

Evolve an existing larch skill by researching concrete improvements and filing them as GitHub issues. Validates `<skill-name>` against `^[a-z][a-z0-9-]*$` and resolves it to `skills/<name>/SKILL.md` (plugin tree) or `.claude/skills/<name>/SKILL.md` (project-local fallback); aborts cleanly if the target does not exist. Then invokes `/research --scale=deep` with a templated prompt that asks the lane fan-out (5 research lanes + 5 validation lanes) to produce concrete actionable improvements with citations — repo-local sibling-skill comparisons via `file:line` references and reputable external sources (Anthropic / OpenAI / DeepMind / ≥500-star OSS) via URLs. If the research lane surfaces ≥1 actionable improvement, distills the findings into a task description and delegates to `/umbrella` with `--label evolved-by:skill-evolver --label skill:<name>` and `--title-prefix "[skill-evolver:<name>] "`. `/umbrella` runs its own one-shot-vs-multi-piece classifier on the distilled task description: multi-piece yields an umbrella tracking issue + one child per piece (very small items may be bundled into a single composed piece per Step 3B.1's bundling rule); one-shot yields a single issue (no umbrella). `/skill-evolver`'s `--label evolved-by:skill-evolver --label skill:<name>` and title-prefix tag whatever issue(s) `/umbrella` actually files (a single issue on the one-shot path; the umbrella plus all children on the multi-piece path). Zero improvements → clean exit, no issues filed. The skill itself does NOT modify the target skill's files — implementation lands later via `/fix-issue` (per child). Example: `/skill-evolver design`.

## `/umbrella`

**Arguments**: `[--label L]... [--title-prefix P] [--repo OWNER/REPO] [--closed-window-days N] [--dry-run] [--go] [--debug] <task description or empty to deduce from context>`

**Source**: [`skills/umbrella/SKILL.md`](../skills/umbrella/SKILL.md)

Plan-to-issues orchestrator. Takes a task description (or deduces it from session context), classifies it as one-shot or multi-piece, and delegates GitHub issue creation to `/issue` — adding native blocked-by dependencies to form an execution DAG and back-linking children to the umbrella when multi-piece. Typically invoked transitively by `/review --create-issues` (slice-mode finding filing) and `/skill-evolver` (research-finding filing) rather than called directly by humans, though direct invocation is supported. The one-shot path emits a single child issue and skips umbrella creation; the multi-piece path emits an umbrella tracking issue plus one child per piece (very small items may be bundled into a single composed piece per Step 3B.1's bundling rule), with `Closes #<umbrella>` blocked-by edges wired between children and the umbrella. `--dry-run` previews the proposed batch without GitHub mutations; `--go` posts a `GO` sentinel comment on each successfully-created child to make them eligible for `/fix-issue` automation. Example: `/umbrella refactor the auth subsystem in three phases: schema, middleware, tests`.
