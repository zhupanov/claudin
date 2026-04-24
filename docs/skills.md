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

**Arguments**: `[--merge] [--slack] <alias-name> <target-skill> [preset-flags...]`

**Source**: [`skills/alias/SKILL.md`](../skills/alias/SKILL.md)

Create a project-level alias for a larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (code review, version bump, PR). `--merge` also merges the PR. `--slack` (when placed before the first positional) forwards to the `/implement` invocation so the alias-creation PR posts to Slack; `--slack` placed after the first positional is passed through verbatim as a preset flag for the generated alias. Example: `/alias i implement --merge` creates `/i` as a shortcut for `/implement --merge`.

## `/compress-skill`

**Arguments**: `[--debug] [--slack] <skill-name-or-path>`

**Source**: [`skills/compress-skill/SKILL.md`](../skills/compress-skill/SKILL.md)

Compress an existing skill's Markdown prose to reduce size while preserving meaning. Discovers the transitive `.md` set (restricted to the skill's own directory tree — shared docs and sub-skills are excluded), snapshots baseline sizes, and delegates a behavior-preserving prose rewrite to `/imaq` applying Strunk & White's *Elements of Style* adapted for technical writing. Structural elements (YAML frontmatter, fenced code blocks, headings, link targets, inline code, file paths, numeric values) are preserved verbatim; only prose is rewritten. PR body includes a `## Token budget` section with per-file before/after byte and line deltas. `--slack` forwards to `/imaq` (and thence to `/implement`) so the compression PR posts to Slack.

## `/create-skill`

**Arguments**: `[--plugin] [--multi-step] [--merge] [--debug] [--slack] <skill-name> <description>`

**Source**: [`skills/create-skill/SKILL.md`](../skills/create-skill/SKILL.md)

Scaffold a new larch-style skill from a name and description. Validates the name (regex + reserved-name union + case-insensitive collision) and the description (length + XML / shell-dangerous pattern rejection), then delegates to `/im --quick --auto` which writes the scaffold via `skills/create-skill/scripts/render-skill-md.sh` and auto-merges the PR (via `/im`'s `--merge` pre-set). Default target is `.claude/skills/<name>/` (consumer mode); `--plugin` writes to `skills/<name>/`. `--multi-step` emits a multi-step scaffold; default is minimal. `--merge` is accepted as a backward-compat no-op since `/im` already auto-merges. `--slack` forwards to `/im` (and thence to `/implement`) so the scaffold PR posts to Slack. See `skills/shared/skill-design-principles.md`.

## `/design`

**Arguments**: `[--auto] [--debug] <feature description>`

**Source**: [`skills/design/SKILL.md`](../skills/design/SKILL.md) · [Diagram](../skills/design/diagram.svg)

Design an implementation plan with collaborative multi-reviewer review. 5 sketch agents (1 Claude + 2 Cursor + 2 Codex) independently propose architectural approaches, then a **dialectic debate + 3-judge binary panel** resolves up to 5 contested decisions (bucketed Cursor/Codex debaters with bucket-skip fallback; Claude/Cursor/Codex judges with replacement-first fallback; attribution-stripped ballot with position rotation — see `skills/shared/dialectic-protocol.md`), then a 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor) validates the full plan. `--auto` suppresses all interactive question checkpoints. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/fix-issue`

**Arguments**: `[--debug] [--slack] [<number-or-url>]`

**Source**: [`skills/fix-issue/SKILL.md`](../skills/fix-issue/SKILL.md)

Process one approved GitHub issue per invocation. Fetches open issues with a `GO` sentinel comment, skips any blocked by an open dependency (GitHub's native blocked-by API plus conservative prose-keyword scanning of the body and comments — `Depends on #N`, `Blocked by #N`, etc., with fail-open posture), triages, and classifies intent (PR/NON_PR) and — for PR tasks — complexity (SIMPLE/HARD). PR tasks delegate to `/implement` with `--issue $ISSUE_NUMBER` forwarded so the queue issue is adopted as the tracking issue (no separate tracking issue is created); NON_PR tasks run inline (typically filing findings via `/issue`) and never call `/implement`. With a number or URL argument, targets a specific issue instead of auto-picking. Single-iteration design — the caller handles repetition. `--slack` is forwarded to the delegated `/implement` run so the PR posts to Slack; without it, the delegated run does not post to Slack (the NON_PR path's own Slack announcement is unaffected).

## `/implement`

**Arguments**: `[--quick] [--auto] [--merge | --draft] [--slack] [--debug] [--issue <N>] <feature description>`

**Source**: [`skills/implement/SKILL.md`](../skills/implement/SKILL.md) · [Diagram](../skills/implement/diagram.svg)

Full end-to-end feature workflow — design, implement, PR (Slack announce is opt-in via `--slack`). `--quick` skips `/design` and uses a simplified single-reviewer loop of up to 7 rounds with a per-round `Cursor → Codex → Claude Code Reviewer subagent` fallback chain (no voting panel; main agent unilaterally accepts or rejects each finding). `--auto` suppresses all interactive question checkpoints. `--merge` additionally runs the CI+rebase+merge loop, local branch cleanup, and main verification (without `--merge`, the PR is created and the workflow stops after the initial CI wait and reports). `--draft` creates the PR in draft state and skips local cleanup so the branch is kept for further iteration; mutually exclusive with `--merge`. `--slack` posts a PR announcement to Slack after PR creation, and (when combined with `--merge`) adds a `:merged:` emoji after merge; both require `LARCH_SLACK_BOT_TOKEN` and `LARCH_SLACK_CHANNEL_ID`. Without `--slack`, no Slack calls are made regardless of environment configuration. `--issue <N>` attaches `/implement` to an existing tracking issue (Step 0.5 adoption); otherwise fresh creation is deferred to Step 9a.1. `--debug` enables verbose output with detailed tool descriptions and explanatory prose (default is compact output).

## `/improve-skill`

**Arguments**: `[--slack] [--issue <N>] <skill-name>`

**Source**: [`skills/improve-skill/SKILL.md`](../skills/improve-skill/SKILL.md)

Run exactly one iteration of the iterative skill-improvement pipeline against an existing larch skill: `/skill-judge` → grade parse → `/design` → `/larch:im`. Each child skill runs as a fresh `claude -p` subprocess invoked by the shared bash kernel at `skills/improve-skill/scripts/iteration.sh` — the same kernel `/loop-improve-skill` reuses once per round of its up-to-10 loop. The amended `/design` prompt carries a **narrow per-finding pushback carve-out**: `/design` may include a `## Pushback on judge findings` subsection in the plan to argue specific `/skill-judge` findings are erroneous, provided each pushback entry identifies the finding, explains why it is misapplied, and cites concrete codebase evidence (file:line). The carve-out is strictly per-finding — the plan must still address every undisputed non-A dimension, and the existing three directives (no-self-curtail on minor/cosmetic findings, no-self-curtail on token/budget grounds, no no-plan sentinels when findings exist) remain in force. `--issue <N>` adopts an existing tracking issue instead of creating a new one (used by `/loop-improve-skill`'s driver to accumulate all 10 iterations' comments on one issue). `--slack` is forwarded to the `/larch:im` invocation so the iteration's PR posts to Slack. On exit, the kernel emits a 9-key KV footer (`### iteration-result` block with `ITER_STATUS` / `EXIT_REASON` / `PARSE_STATUS` / `GRADE_A` / `NON_A_DIMS` / `TOTAL_NUM` / `TOTAL_DEN` / `ITERATION_TMPDIR` / `ISSUE_NUM`) — guaranteed via EXIT trap so parsers see a result even on abnormal abort. Example: `/improve-skill design` or `/improve-skill --issue 391 design`.

## `/issue`

**Arguments**: `[--input-file FILE] [--title-prefix P] [--label L]... [--body-file F] [--dry-run] [--go] [<issue description>]`

**Source**: [`skills/issue/SKILL.md`](../skills/issue/SKILL.md)

Create one or more GitHub issues with LLM-based semantic duplicate detection. Two modes: single (free-form description) and batch (`--input-file`). 2-phase dedup against open + recently-closed issues (default 90-day window). `/implement` Step 9a.1 calls this skill in batch mode to file OOS issues. `--go` posts a final `GO` comment on each newly-created issue so it becomes eligible for `/fix-issue` automation; works in both single and batch modes (duplicates, failed creates, and dry-run items never receive a GO comment). In single mode, if the sole item resolves to a duplicate, `--go` errors out; in batch mode, per-item duplicates are simply skipped for the GO comment.

## `/loop-improve-skill`

**Arguments**: `[--slack] <skill-name>`

**Source**: [`skills/loop-improve-skill/SKILL.md`](../skills/loop-improve-skill/SKILL.md)

Iteratively improve an existing larch skill. Creates a tracking GitHub issue, then runs up to 10 improvement rounds of `/skill-judge` → `/design` → `/im` via the shared `/improve-skill` iteration kernel at `skills/improve-skill/scripts/iteration.sh`, invoked once per round by the driver via direct bash call (not via nested `claude -p`). Halt class eliminated by construction: the kernel spawns each child skill as a fresh `claude -p` subprocess, and the driver → kernel edge is a plain bash call. Termination contract: strives for grade A on every `/skill-judge` dimension (D1..D8); exits happy when achieved, with written infeasibility justification when `/design` produces no plan, `/design` refuses, or `/im` cannot be verified, or with auto-generated infeasibility justification (post-iter-cap final `/skill-judge` re-evaluation listing remaining non-A dimensions) when the 10-iteration cap is reached. Justification is appended to the close-out tracking-issue comment. The driver passes `--work-dir $LOOP_TMPDIR --iter-num $ITER --issue $ISSUE_NUM` to the kernel so all iteration artifacts accumulate in one work-dir and one tracking issue. `--slack` is propagated to every iteration's `/larch:im` invocation so each PR posts to Slack; note that up to 10 iterations can produce up to 10 Slack posts, so opt in only when desired. Example: `/loop-improve-skill design`.

## `/loop-review`

**Arguments**: `[--debug] [partition criteria]`

**Source**: [`skills/loop-review/SKILL.md`](../skills/loop-review/SKILL.md) · [Diagram](../skills/loop-review/diagram.svg)

Systematic code review of entire repository by partitioning into slices, reviewing each with a 3-reviewer panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor, if available), and filing every actionable finding as a deduplicated GitHub issue via `/issue --input-file --label loop-review`. Uses the Negotiation Protocol to merge per-slice reviewer findings. Security-tagged findings are held locally per SECURITY.md. Batches accumulate up to 3 slices per `/issue` flush so its 2-phase LLM dedup runs once per batch. The optional argument specifies how to partition the codebase (e.g., by directory, by file type). The `loop-review` label should be pre-created in the target repository — `/issue` silently drops unknown labels with a stderr warning.

## `/relevant-checks`

**Arguments**: *(none)*

**Source**: [`.claude/skills/relevant-checks/SKILL.md`](../.claude/skills/relevant-checks/SKILL.md)

Run pre-commit linters (shellcheck, markdownlint, jsonlint, actionlint, gitleaks) scoped to changed files (except gitleaks, which always scans the full working tree; see the relevant-checks skill). Invoked automatically by `/implement` and `/review` after code changes. **Not part of the plugin surface; each consuming repo provides its own.**

## `/research`

**Arguments**: `[--debug] <research question or topic>`

**Source**: [`skills/research/SKILL.md`](../skills/research/SKILL.md) · [Diagram](../skills/research/diagram.svg)

Collaborative read-only research using 3 research agents (Claude inline + Cursor + Codex, uniformly briefed) then a 3-reviewer validation panel (1 Claude Code Reviewer subagent + 1 Codex + 1 Cursor). Claude Code Reviewer subagent fallbacks preserve the 3-lane invariant when an external tool is unavailable. Produces a structured report with findings, risk assessment, difficulty estimates, and feasibility verdict. Does not modify the repo: scratch writes are permitted only under canonical `/tmp` (enforced mechanically by the skill-scoped `scripts/deny-edit-write.sh` PreToolUse hook), and `/issue` may be invoked via the Skill tool to file research-result issues.

## `/review`

**Arguments**: `[--debug]`

**Source**: [`skills/review/SKILL.md`](../skills/review/SKILL.md) · [Diagram](../skills/review/diagram.svg)

Code review current branch changes with a 3-reviewer panel (1 Claude Code Reviewer + 1 Codex + 1 Cursor, if available), implementing accepted suggestions in a recursive loop (up to 5 rounds). Reviews the diff between main and HEAD.

## `/simplify-skill`

**Arguments**: `[--debug] [--slack] <skill-name>`

**Source**: [`skills/simplify-skill/SKILL.md`](../skills/simplify-skill/SKILL.md)

Refactor an existing larch skill for stronger adherence to `skills/shared/skill-design-principles.md` and to reduce SKILL.md token footprint. Resolves the target skill directory (plugin tree first, then consumer `.claude/skills/`), enumerates every `.md` file under it (excluding `scripts/` and `tests/`), does NOT follow sub-skills invoked via the `Skill` tool, and delegates the refactor to `/im` with a pinned behavior-preserving feature description that requires a `## Token budget` section in the PR body. `--slack` forwards to `/im` (and thence to `/implement`) so the refactor PR posts to Slack. Example: `/simplify-skill implement`.
