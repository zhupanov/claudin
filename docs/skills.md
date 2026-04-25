# Skills

Reference for every slash command shipped by the larch plugin. Each section below covers one skill: invocation, arguments, behavior, and links to the canonical `SKILL.md` source.

- [`/alias`](#alias)
- [`/compress-skill`](#compress-skill)
- [`/create-skill`](#create-skill)
- [`/design`](#design)
- [`/fix-issue`](#fix-issue)
- [`/implement`](#implement)
- [`/improve-skill`](#improve-skill)
- [`/issue`](#issue)
- [`/loop-improve-skill`](#loop-improve-skill)
- [`/loop-review`](#loop-review)
- [`/relevant-checks`](#relevant-checks)
- [`/research`](#research)
- [`/review`](#review)
- [`/simplify-skill`](#simplify-skill)

## `/alias`

**Arguments**: `[--merge] [--no-slack] <alias-name> <target-skill> [preset-flags...]`

**Source**: [`skills/alias/SKILL.md`](../skills/alias/SKILL.md)

Create a project-level alias for a larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR). `--merge` also merges the PR. `--no-slack` (when placed before the first positional) forwards to the `/implement` invocation so the alias-creation PR does NOT post to Slack; `--no-slack` placed after the first positional is passed through verbatim as a preset flag for the generated alias. Example: `/alias i implement --merge` creates `/i` as a shortcut for `/implement --merge`.

## `/compress-skill`

**Arguments**: `[--debug] [--no-slack] <skill-name-or-path>`

**Source**: [`skills/compress-skill/SKILL.md`](../skills/compress-skill/SKILL.md)

Compress an existing skill's Markdown prose to reduce size while preserving meaning. Discovers the transitive `.md` set (restricted to the skill's own directory tree — shared docs and sub-skills are excluded), snapshots baseline sizes, and delegates a behavior-preserving prose rewrite to `/imaq` applying Strunk & White's *Elements of Style* adapted for technical writing. Structural elements (YAML frontmatter, fenced code blocks, headings, link targets, inline code, file paths, numeric values) are preserved verbatim; only prose is rewritten. PR body includes a `## Token budget` section with per-file before/after byte and line deltas. `--no-slack` forwards to `/imaq` (and thence to `/implement`) so the compression run does NOT post a Slack announcement.

## `/create-skill`

**Arguments**: `[--plugin] [--multi-step] [--merge] [--debug] [--no-slack] <skill-name> <description>`

**Source**: [`skills/create-skill/SKILL.md`](../skills/create-skill/SKILL.md)

Scaffold a new larch-style skill from a name and description. Validates the name (regex + reserved-name union + case-insensitive collision) and the description (length + XML / shell-dangerous pattern rejection), then delegates to `/im --quick --auto` which writes the scaffold via `skills/create-skill/scripts/render-skill-md.sh` and auto-merges the PR (via `/im`'s `--merge` pre-set). Default target is `.claude/skills/<name>/` (consumer mode); `--plugin` writes to `skills/<name>/`. `--multi-step` emits a multi-step scaffold; default is minimal. `--merge` is accepted as a backward-compat no-op since `/im` already auto-merges. `--no-slack` forwards to `/im` (and thence to `/implement`) so the scaffold run does NOT post a Slack announcement. See `skills/shared/skill-design-principles.md`.

## `/design`

**Arguments**: `[--auto] [--debug] <feature description>`

**Source**: [`skills/design/SKILL.md`](../skills/design/SKILL.md) · [Diagram](../skills/design/diagram.svg)

Design an implementation plan with collaborative multi-reviewer review. 5 sketch agents (1 Claude + 2 Cursor + 2 Codex) independently propose architectural approaches, then a **dialectic debate + 3-judge binary panel** resolves up to 5 contested decisions (bucketed Cursor/Codex debaters with bucket-skip fallback; Claude/Cursor/Codex judges with replacement-first fallback; attribution-stripped ballot with position rotation — see `skills/shared/dialectic-protocol.md`), then a 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor) validates the full plan. `--auto` suppresses all interactive question checkpoints. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/fix-issue`

**Arguments**: `[--debug] [--no-slack] [<number-or-url>]`

**Source**: [`skills/fix-issue/SKILL.md`](../skills/fix-issue/SKILL.md)

Process one approved GitHub issue per invocation. Step 0 (`find-lock-issue.sh`) atomically finds an eligible candidate (open, with `GO` sentinel comment as last comment, no managed lifecycle title prefix, not already locked, no open blocking dependencies via GitHub's native blocked-by API plus conservative prose-keyword scanning — `Depends on #N`, `Blocked by #N`, etc., with fail-open posture), acquires the comment lock, and renames the title to `[IN PROGRESS]` so the visual lifecycle reflects the active run immediately. Triages, and classifies intent (PR/NON_PR) and — for PR tasks — complexity (SIMPLE/HARD). PR tasks delegate to `/implement` with `--issue $ISSUE_NUMBER` forwarded so the queue issue is adopted as the tracking issue (no separate tracking issue is created); NON_PR tasks run inline (typically filing findings via `/issue`) and never call `/implement`. With a number or URL argument, targets a specific issue instead of auto-picking. Single-iteration design — the caller handles repetition. `--no-slack` is forwarded to the delegated `/implement` run (suppressing its Step 16a issue Slack post) AND suppresses `/fix-issue`'s own Step 7 NON_PR-path Slack announcement. Default (no `--no-slack`): both paths post per `/implement`'s default-on behavior (gated on Slack env vars).

## `/implement`

**Arguments**: `[--quick] [--auto] [--merge | --draft] [--no-slack] [--debug] [--issue <N>] <feature description>`

**Source**: [`skills/implement/SKILL.md`](../skills/implement/SKILL.md) · [Diagram](../skills/implement/diagram.svg)

Full end-to-end feature workflow — design, implement, PR, issue Slack announce (on by default when Slack env vars are configured). `--quick` skips `/design` and uses a simplified single-reviewer loop of up to 7 rounds with a per-round `Cursor → Codex → Claude Code Reviewer subagent` fallback chain (no voting panel; main agent unilaterally accepts or rejects each finding). `--auto` suppresses all interactive question checkpoints. `--merge` additionally runs the CI+rebase+merge loop, local branch cleanup, and main verification (without `--merge`, the PR is created and the workflow stops after the initial CI wait and reports). `--draft` creates the PR in draft state and skips local cleanup so the branch is kept for further iteration; mutually exclusive with `--merge`. Near the end of every run (Step 16a), a single status message about the tracking issue is posted to Slack: `<emoji> <GitHub link|Issue #N> (<title>) — <status>`. Emoji: ✅ closed (PR merged + issue auto-closed), 📝 PR opened but not merged (`--merge` not set or `--draft`), ❌ blocked (CI failure, merge failure, or Step 12d bail), ❓ needs user input (auto-mode conflict bail). The post uses the git user identity (`git config user.name` → Slack `username`). Requires `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID`. Pass `--no-slack` to opt out. `--issue <N>` attaches `/implement` to an existing tracking issue (Step 0.5 adoption); otherwise a fresh tracking issue is created at Step 0.5 Branch 4. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/improve-skill`

**Arguments**: `[--no-slack] [--issue <N>] <skill-name>`

**Source**: [`skills/improve-skill/SKILL.md`](../skills/improve-skill/SKILL.md)

Run exactly one iteration of the iterative skill-improvement pipeline against an existing larch skill: `/skill-judge` → grade parse → `/design` → `/larch:im`. Each child skill runs as a fresh `claude -p` subprocess invoked by the shared bash kernel at `skills/improve-skill/scripts/iteration.sh` — the same kernel `/loop-improve-skill` reuses once per round of its up-to-10 loop. The amended `/design` prompt carries a **narrow per-finding pushback carve-out**: `/design` may include a `## Pushback on judge findings` subsection in the plan to argue specific `/skill-judge` findings are erroneous, provided each pushback entry identifies the finding, explains why it is misapplied, and cites concrete codebase evidence (file:line). The carve-out is strictly per-finding — the plan must still address every undisputed non-A dimension, and the existing three directives (no-self-curtail on minor/cosmetic findings, no-self-curtail on token/budget grounds, no no-plan sentinels when findings exist) remain in force. `--issue <N>` adopts an existing tracking issue instead of creating a new one (used by `/loop-improve-skill`'s driver to accumulate all 10 iterations' comments on one issue). `--no-slack` is forwarded to the `/larch:im` invocation so the iteration's `/implement` run does NOT post a Slack announcement (default: posts per `/implement`'s default-on behavior when Slack env vars are configured). On exit, the kernel emits a 9-key KV footer (`### iteration-result` block with `ITER_STATUS` / `EXIT_REASON` / `PARSE_STATUS` / `GRADE_A` / `NON_A_DIMS` / `TOTAL_NUM` / `TOTAL_DEN` / `ITERATION_TMPDIR` / `ISSUE_NUM`) — guaranteed via EXIT trap so parsers see a result even on abnormal abort. Example: `/improve-skill design` or `/improve-skill --issue 391 design`.

## `/issue`

**Arguments**: `[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [<issue description>]`

**Source**: [`skills/issue/SKILL.md`](../skills/issue/SKILL.md)

Create one or more GitHub issues with LLM-based semantic duplicate detection. Two modes: single (free-form description) and batch (`--input-file`). 2-phase dedup against open + recently-closed issues (default 90-day window). `/implement` Step 9a.1 calls this skill in batch mode to file OOS issues. `--go` posts a final `GO` comment on each newly-created issue so it becomes eligible for `/fix-issue` automation; works in both single and batch modes (duplicates, failed creates, and dry-run items never receive a GO comment). In single mode, if the sole item resolves to a duplicate, `--go` errors out; in batch mode, per-item duplicates are simply skipped for the GO comment.

## `/loop-improve-skill`

**Arguments**: `[--no-slack] <skill-name>`

**Source**: [`skills/loop-improve-skill/SKILL.md`](../skills/loop-improve-skill/SKILL.md)

Iteratively improve an existing larch skill. Creates a tracking GitHub issue, then runs up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` via the shared `/improve-skill` iteration kernel at `skills/improve-skill/scripts/iteration.sh`, invoked once per round by the driver via direct bash call (not via nested `claude -p`). Halt class eliminated by construction: the kernel spawns each child skill as a fresh `claude -p` subprocess, and the driver → kernel edge is a plain bash call. Termination contract: strives for grade A on every `/skill-judge` dimension (D1..D8); exits happy when achieved, with written infeasibility justification when `/design` produces no plan, `/design` refuses, or `/im` cannot be verified, or with auto-generated infeasibility justification (post-iter-cap final `/skill-judge` re-evaluation listing remaining non-A dimensions) when the 10-iteration cap is reached. Justification is appended to the close-out tracking-issue comment. The driver passes `--work-dir $LOOP_TMPDIR --iter-num $ITER --issue $ISSUE_NUM` to the kernel so all iteration artifacts accumulate in one work-dir and one tracking issue. `--no-slack` is propagated to every iteration's `/larch:im` invocation so no iteration's `/implement` run posts to Slack; default: each iteration posts per `/implement`'s default-on behavior, up to 10 Slack posts per loop. Example: `/loop-improve-skill design`.

## `/loop-review`

**Arguments**: `[--debug] [partition criteria]`

**Source**: [`skills/loop-review/SKILL.md`](../skills/loop-review/SKILL.md) · [Diagram](../skills/loop-review/diagram.svg)

Systematic code review of entire repository by partitioning into slices, reviewing each with a 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor, if available), and filing every actionable finding as a deduplicated GitHub issue via `/issue --input-file --label loop-review`. Uses the Negotiation Protocol to merge per-slice reviewer findings. Security-tagged findings are held locally per SECURITY.md. Batches accumulate up to 3 slices per `/issue` flush so its 2-phase LLM dedup runs once per batch. The optional argument specifies how to partition the codebase (e.g., by directory, by file type). The `loop-review` label should be pre-created in the target repository — `/issue` silently drops unknown labels with a stderr warning.

## `/relevant-checks`

**Arguments**: *(none)*

**Source**: [`.claude/skills/relevant-checks/SKILL.md`](../.claude/skills/relevant-checks/SKILL.md)

Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint, gitleaks) scoped to changed files (except gitleaks, which always scans the full working tree; see the relevant-checks skill). Invoked automatically by `/implement` and `/review` after code changes. **Not part of the plugin surface; each consuming repo provides its own.**

## `/research`

**Arguments**: `[--debug] [--plan] [--scale=quick|standard|deep] [--adjudicate] <research question or topic>`

**Source**: [`skills/research/SKILL.md`](../skills/research/SKILL.md) · [Diagram](../skills/research/diagram.svg)

Collaborative best-effort read-only research with a scale-aware lane shape selected by `--scale=quick|standard|deep` (default `standard`).

- `--scale=standard` (default): 3 research agents (Cursor + Codex + Claude inline) **angle-differentiated per lane** (Cursor → `RESEARCH_PROMPT_ARCH` for architecture; Codex → `RESEARCH_PROMPT_EDGE` for edge cases by default or `RESEARCH_PROMPT_EXT` for external comparisons when `external_evidence_mode=true`; Claude inline → `RESEARCH_PROMPT_SEC` for security) + 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant when an external tool is unavailable; the fallback subagent carries the same angle prompt the failed lane would have run.
- `--scale=quick`: 1 inline Claude lane only (single-lane confidence — fastest, lowest assurance); Step 2 (the validation panel) does not run, but the final report still renders a 0-reviewer Validation phase placeholder line so the report shape is uniform across scales. Synthesis carries an explicit "single-lane confidence" disclaimer. Useful for trivial single-fact lookups; avoid when correctness or completeness matter.
- `--scale=deep`: 5 research lanes (Claude inline running baseline `RESEARCH_PROMPT_BASELINE` + 2 Cursor slots and 2 Codex slots carrying the four diversified angle prompts `RESEARCH_PROMPT_ARCH` / `RESEARCH_PROMPT_EDGE` / `RESEARCH_PROMPT_EXT` / `RESEARCH_PROMPT_SEC` for architecture / edge cases / external comparisons / security) + 5-reviewer validation panel (the standard 3 plus 2 extra Claude Code Reviewer subagents `Code-Sec` and `Code-Arch` carrying lane-local emphasis on the unified Code Reviewer archetype — NOT new agent slugs). The synthesis must explicitly name the four diversified angles so the operator can see they were genuinely covered.

**Optional `--plan` (planner pre-pass — supported with `--scale=standard` or `--scale=deep`)**: when set, a single Claude Agent subagent decomposes `RESEARCH_QUESTION` into 2–4 focused subquestions before the lane fan-out. Each lane researches its assigned subquestion(s) under a per-scale assignment table:

- **Standard scale** (3 lanes): N=2 → all lanes get the union; N=3 → one per lane; N=4 → lane 1 (Cursor) gets two, lanes 2 (Codex) and 3 (Claude inline) get one each. Synthesis is organized by `### Subquestion N` sub-sections + a final `### Cross-cutting findings` sub-section.
- **Deep scale** (5 lanes — issue #519): a balanced partial-matrix ring rotation across the 4 named-angle slots (Cursor-Arch, Cursor-Edge, Codex-Ext, Codex-Sec) — angle lane k gets `s_{((k-1) mod N)+1}, s_{(k mod N)+1}` — plus a Claude-inline integrator lane (lane 5) that unions all subquestions. At N=2 the ring degenerates to full union; at N=3/4 every subquestion appears in at least one named-angle lane plus the integrator. Synthesis is organized by `### Subquestion N` sub-sections + a `### Per-angle highlights` sub-section that names the four canonical angles (architecture & data flow, edge cases & failure modes, external comparisons, security & threat surface) + a `### Cross-cutting findings` sub-section. Each lane's existing angle base prompt is augmented with the per-lane subquestion suffix — angle identity is preserved alongside the planner subquestion focus.

Falls back cleanly to single-question mode on any planner failure (count out of [2,4], empty output, prose-only reply, timeout) with a visible warning. Standard-mode fallback uses each lane's existing angle base prompt (Cursor → `RESEARCH_PROMPT_ARCH`, Codex → `RESEARCH_PROMPT_EDGE` or `_EXT`, Claude inline → `RESEARCH_PROMPT_SEC`) with no per-lane suffix — exactly the existing standard-mode lane shape. Deep-mode fallback uses the existing angle base prompts on the 4 external slots and baseline `RESEARCH_PROMPT_BASELINE` on Claude-inline — exactly the pre-#519 deep-mode shape (the planner failure path does NOT collapse to a generic baseline prompt on the angle slots, in either standard or deep mode). Default off — byte-equivalent to pre-#420 behavior on the no-`--plan` path. **Not applicable to `--scale=quick`** (single lane → no decomposition benefit); the incompatible combination downgrades `--plan` to off with a visible warning at the start of Step 1.

All scales produce a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict (the report's lane-count headers reflect the configured scale dynamically). With `--adjudicate` (default off, composes with any `--scale` and with `--plan`), runs an additional 3-judge dialectic adjudication step (Step 2.5) over reviewer findings the orchestrator rejected during validation merge/dedup; majority binds, with reinstated findings folded into the validated synthesis before the report renders — see [`skills/research/references/adjudication-phase.md`](../skills/research/references/adjudication-phase.md). When `--scale=quick` is set, Step 2 is skipped so there are no rejections to adjudicate and Step 2.5 short-circuits cleanly. Tracked repo files are not modified by the Claude `Edit | Write | NotebookEdit` tool surface — scratch writes are permitted only under canonical `/tmp` (enforced mechanically by the skill-scoped `scripts/deny-edit-write.sh` PreToolUse hook). Bash and external Cursor/Codex reviewers run with full filesystem access and are prompt-enforced only — see [`SECURITY.md` § External reviewer write surface in /research and /loop-review](../SECURITY.md#external-reviewer-write-surface-in-research-and-loop-review). `/issue` may be invoked via the Skill tool to file research-result issues.

## `/review`

**Arguments**: `[--debug]`

**Source**: [`skills/review/SKILL.md`](../skills/review/SKILL.md) · [Diagram](../skills/review/diagram.svg)

Code review current branch changes with a 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor, if available), implementing accepted suggestions in a recursive loop (up to 5 rounds). Reviews the diff between main and HEAD.

## `/simplify-skill`

**Arguments**: `[--debug] [--no-slack] <skill-name>`

**Source**: [`skills/simplify-skill/SKILL.md`](../skills/simplify-skill/SKILL.md)

Refactor an existing larch skill for stronger adherence to `skills/shared/skill-design-principles.md` and to reduce SKILL.md token footprint. Resolves the target skill directory (plugin tree first, then consumer `.claude/skills/`), enumerates every `.md` file under it (excluding `scripts/` and `tests/`), does NOT follow sub-skills invoked via the `Skill` tool, and delegates the refactor to `/im` with a pinned behavior-preserving feature description that requires a `## Token budget` section in the PR body. `--no-slack` forwards to `/im` (and thence to `/implement`) so the refactor run does NOT post a Slack announcement. Example: `/simplify-skill implement`.
