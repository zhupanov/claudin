# Sub-skill Invocation Conventions

Canonical style guide for larch skills that delegate to other skills via the `Skill` tool. Cited throughout by `/create-skill`'s scaffold and by `AGENTS.md`. When you author a new skill that invokes another skill, follow the patterns below. When you change a convention here, update the cited source-example skills in the same PR (or file a follow-up issue) so the examples stay in sync with the rules.

## Two invocation patterns

Every larch skill that invokes another skill uses exactly one of two first-class shapes. Pick the one that matches your intent.

### Pattern A — Pure delegator (bulleted)

Used when the parent skill mostly forwards to a child with preset flags or light argument assembly. Appears in `skills/im/SKILL.md § Behavior`, `skills/imaq/SKILL.md § Behavior`, and `skills/create-skill/SKILL.md § Step 3 — Delegate to /im`. Canonical form:

```
Invoke the Skill tool:
- Try skill: "implement" first (bare name). If no skill matches, try skill: "larch:implement" (fully-qualified plugin name).
- args: --merge $ARGUMENTS
```

Keep the block together. The bare-name-first rule is important — see `## Bare-name-then-fully-qualified fallback` below.

Note: `/create-skill` forwards to `/im` (not directly to `/implement`); `/im` in turn forwards to `/implement --merge` per its own Pattern A definition. The chained delegation gives `/create-skill` auto-merge semantics while keeping each hop as a minimal pure forwarder.

### Pattern B — Stateful orchestrator (inline)

Used when the parent runs setup, forwards `--session-env`, invokes the child, and then parses structured output to continue. Appears in `skills/fix-issue/SKILL.md § Step 5 — Execute` (parent step heading + explicit "Invoke `/implement` via the Skill tool" line + SIMPLE/HARD variant bullets) and in `skills/implement/SKILL.md § Step 1 — Ensure Design Plan Exists`, `skills/implement/SKILL.md § Step 5 — Code Review`, `skills/implement/SKILL.md § Step 8 — Version Bump` (around `/design`, `/review`, `/bump-version` calls). Canonical form:

```
Invoke `/implement` via the Skill tool:

- **SIMPLE**: `/implement --auto --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
- **HARD**:   `/implement --auto --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
```

The step heading + explicit Skill-tool line + variant bullets shape makes the invocation impossible to miss and keeps the argument list scannable. Do **not** collapse Pattern B into a single paragraph — see `## Avoid conditional phrasing for sub-skill invocations` below.

`scripts/lint-skill-invocations.py` mechanically enforces line-local co-location: every direct-invocation line that says ``Invoke `/<name>`'' (with optional `the` and a bounded `**bold-span**`) must also contain `via the Skill tool` on the same line.

## allowed-tools narrowing heuristic

Set `allowed-tools` to the minimum needed by the parent skill itself — never mirror the child skill's broader tool set. Three tiers cover every larch skill:

| Tier | `allowed-tools` | Example (with stable anchor) |
|---|---|---|
| Pure delegator | `Skill` | `skills/im/SKILL.md` frontmatter (allowed-tools line) — forwards only |
| Delegator that validates first | `Bash, Skill` | `skills/create-skill/SKILL.md` frontmatter — runs validation scripts before delegating |
| Hybrid orchestrator | `Skill` plus whatever the parent needs | `skills/implement/SKILL.md`, `skills/fix-issue/SKILL.md`, `skills/review/SKILL.md`, `skills/alias/SKILL.md`, `skills/research/SKILL.md` — parent runs setup, file I/O, git ops, and in `/alias`'s case a post-delegation sentinel-file verification. |

`allowed-tools: Skill` alone is **neither necessary nor sufficient** to classify a skill as a pure delegator — some delegators need `Bash` for input validation. Conversely, a skill with `Skill` in its allowed list is not automatically a delegator; hybrid orchestrators include `Skill` as one tool among many.

When in doubt, start narrow and widen only for tools the parent actually uses. If your skill adds `Skill` to `allowed-tools`, also confirm the frontmatter includes every other tool your parent invokes (Bash, Read, Edit, Glob, Grep, etc.). Omitting a needed tool produces silent runtime denials — not error messages — so the narrowing heuristic must be paired with a concrete accounting of parent tool usage.

## Post-invocation verification

**Scope**: this rule applies to **orchestrators that continue execution based on a child skill's side effects** — e.g., a parent that reads the child's output to decide the next step. Pure forwarders (`/im`, `/imaq`, `/create-skill`, `/simplify-skill`, `/compress-skill`) are exempt — once they delegate, they do nothing further, so there is nothing to verify.

For every mandatory sub-skill call inside an orchestrator's step, pair the call with a **mechanical check that the parent cannot satisfy without the child's side effects**. The check must read the filesystem, parse stdout, or compare counters — never rely on the child's prose acknowledgement. If the child silently skipped or internally bailed, the check must notice.

Canonical examples:

- **Commit-count delta around `/bump-version`** — the orchestrator captures a pre-count, invokes the skill, then compares with a post-count:

  ```bash
  ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode pre
  # Parse HAS_BUMP, COMMITS_BEFORE, STATUS from stdout.
  # Invoke /bump-version via the Skill tool.
  ${CLAUDE_PLUGIN_ROOT}/scripts/check-bump-version.sh --mode post --before-count "$COMMITS_BEFORE"
  # Parse VERIFIED, COMMITS_AFTER, EXPECTED, STATUS.
  # STATUS ∈ {ok, missing_main_ref, git_error}. MUST check STATUS=ok before trusting
  # the COMMITS_* counts — a non-ok STATUS means the count is 0-by-coercion, not
  # a legitimate "0 commits ahead" result (#172). --mode post already forces
  # VERIFIED=false when STATUS != ok, independent of the numeric comparison.
  ```

  See `skills/implement/SKILL.md § Step 8 — Version Bump` for the full recipe. `--mode post` **requires** `--before-count $COMMITS_BEFORE` — calling `--mode post` without it errors out at the script level.

- **Parsed stdout machine value after `/issue`** — the orchestrator reads `ISSUES_CREATED=<N>` / `ISSUES_FAILED=<N>` / per-issue `ISSUE_N_NUMBER`/`ISSUE_N_URL` lines from `/issue`'s stdout. Without those parsed values, the parent cannot file the created issue links into the PR body. See `skills/implement/SKILL.md § 9a.1 — Create OOS GitHub Issues`.

- **Sentinel file** — `/design` writes `$DESIGN_TMPDIR/accepted-plan-findings.md`; `/implement` reads it (or notices its absence) to know whether to reflect findings in the PR body.

- **Sentinel file (defense in depth) — `/research` → `/issue`** — when `/research` invokes `/issue` to file findings as GitHub issues, `/issue` writes a small KV sentinel at `$RESEARCH_TMPDIR/issue-completed.sentinel` (path supplied by `/research` via `/issue`'s narrow `--sentinel-file <path>` flag — NOT `--session-env`). `/research` runs the canonical `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file "$RESEARCH_TMPDIR/issue-completed.sentinel"` post-return and aborts on `VERIFIED=false`. Defense-in-depth precedence: **stdout parsing of `ISSUES_*` (the immediately-prior bullet) is the primary post-`/issue` mechanical check** for any caller; this sentinel-file gate is `/research`-specific defense-in-depth on top of stdout parsing, not a replacement. Both apply for `/research`. The sentinel proves *execution* (gate: `ISSUES_FAILED=0 AND !dry_run`), not creation count — the all-dedup outcome (`ISSUES_CREATED=0`, `ISSUES_DEDUPLICATED>=1`, `ISSUES_FAILED=0`) writes the sentinel and continues normally. See `skills/research/SKILL.md § Filing findings as issues` for the numbered procedure and `skills/issue/SKILL.md § Sentinel file (post-success)` for `/issue`'s side of the contract.

If you cannot name a concrete mechanical check, the call is not actually mandatory — reclassify it as Pattern A (pure delegation) or restructure so the child's side effect is observable.

See `## Anti-halt continuation reminder` below — the two sections govern the same call-site boundary from complementary directions (verification asks "did the child run?"; anti-halt asks "did the parent continue?").

## Anti-halt continuation reminder

**Scope**: this rule applies to the same orchestrator set as `## Post-invocation verification` above — stateful orchestrators (`/fix-issue`, `/implement`, `/review`, `/alias`, `/research`) that run additional steps after a child `Skill` tool call returns. Pure forwarders (`/im`, `/imaq`, `/create-skill`, `/simplify-skill`, `/compress-skill`) are exempt — once they delegate, they do nothing further. The two sections are complementary: `## Post-invocation verification` asks **"did the child run?"**; this section asks **"did the parent continue?"** Both failure modes are distinct and real (see GitHub issue #177 for the originating report).

**The rule**: after every child `Skill` tool call (`/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns, the main agent MUST immediately continue with the parent skill's NEXT step. The child's cleanup / summary output is NOT end-of-turn. Likewise, a summary, handoff, status recap, or "returning to parent" turn-ending message is a halt in disguise, not a valid continuation. In long sessions where the child produces many tokens (e.g., `/design` with 3 reviewers + voting easily produces 15k+ tokens), the main agent's attention can drift to the child's local "mission accomplished" framing and lose the parent orchestration frame. A short, standardized banner at the top of every orchestrator plus short per-Skill-call-site micro-reminders reinforce the rule where attention is most at risk.

**Carve-out (critical)**: the rule is strictly subordinate to any explicit non-sequential control-flow directive in the parent skill — including `skip to Step N`, `bail to cleanup`, `jump back to Step Na`, `loop back to Step 3a`, `fall through to 12c`, `break out of the loop`, or any other explicit redirect. A normal numerically-sequential `proceed to Step N+1` directive is the default continuation path that anti-halt reinforces — NOT an exception.

**Loop-internal carve-out**: when an orchestrator's step explicitly loops (a hypothetical Skill-tool call inside a loop body), the "next step" of the parent IS the loop-continuation directive, not the first textually-following section header. Use the loop-aware micro-reminder variant at loop-internal child-Skill call sites.

**Generic `/relevant-checks` clause**: every `/relevant-checks` invocation anywhere in an orchestrator SKILL.md is covered by this rule without requiring a per-site micro-reminder at every call site. The parent must resume after `/relevant-checks` returns — whether that means advancing to the next numbered step, re-running `/relevant-checks` after a fix, or committing the fixed files.

### Canonical banner (top of each orchestrator SKILL.md, after the title body, before `## Progress Reporting`)

````markdown
**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.
````

The substring `**Anti-halt continuation reminder.**` is a contract token asserted by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh`.

### Canonical micro-reminder (per Skill-tool call site — branch-specific placement)

Place the micro-reminder **inside the specific branch that actually invokes the child** — not at the top of a step whose body may skip the invocation on some branches (e.g., `/implement` Step 1 quick-mode skips `/design`; Step 5 quick-mode skips `/review`; Step 8 `HAS_BUMP=false` skips `/bump-version`). The reminder belongs next to the real Skill-tool call, inside the branch that emits it.

Standard variant:

````markdown
> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.
````

Loop-aware variant (for loop-internal Skill-tool call sites in orchestrators with explicit loop bodies):

````markdown
> **Continue after child returns (loop-internal).** When the child Skill returns, continue the loop per the parent's explicit loop-back directive — do NOT exit the loop unless the exit condition fires, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.
````

The substring `Continue after child returns` is a contract token asserted by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh` (matches both the standard and loop-internal variants).

### Scope list

The banner MUST appear in these orchestrator SKILL.md files:

- `skills/fix-issue/SKILL.md`
- `skills/implement/SKILL.md`
- `skills/review/SKILL.md`
- `skills/alias/SKILL.md`
- `skills/research/SKILL.md`

The banner MUST NOT appear in pure-delegator SKILL.md files:

- `skills/im/SKILL.md`
- `skills/imaq/SKILL.md`
- `skills/create-skill/SKILL.md`
- `skills/simplify-skill/SKILL.md`
- `skills/compress-skill/SKILL.md`

Both presence and absence are enforced by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh`, wired into `make lint` via the `test-anti-halt` target.

## Session-env handoff

Environment variables **do not propagate reliably across `Skill` invocations** — treat every `Skill` call as a fresh bash environment. For any state that must cross skill boundaries (reviewer health flags, repo name, slack-ok, session tmpdir), use a session-env file:

1. The parent writes a `session-env.sh` file via `${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$PARENT_TMPDIR/session-env.sh" --slack-ok <v> --repo <v> ...`.
2. The parent passes `--session-env "$PARENT_TMPDIR/session-env.sh"` to the child.
3. The child reads the file via `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh ... --caller-env "$SESSION_ENV_PATH"`.

Canonical producers and consumers in the live tree:

- `skills/fix-issue/SKILL.md § Step 1 — Setup` writes `$FIX_ISSUE_TMPDIR/session-env.sh` and passes it to `/implement` (Step 0 acquires the `IN PROGRESS` comment lock and applies the `[IN PROGRESS]` title prefix before the tmpdir / session-env exist).
- `skills/implement/SKILL.md § Step 0 — Session Setup` accepts `--session-env` from its parent and propagates a fresh `$IMPLEMENT_TMPDIR/session-env.sh` to `/design` and `/review` via `--session-env` on each invocation.
- `skills/design/SKILL.md § Step 0 — Session Setup` and `skills/review/SKILL.md § Step 0 — Session Setup` both accept `--session-env` as an `--caller-env` forward.

### Security — never `source` a session-env file

**Do NOT `source` `session-env.sh`.** Parse it line-by-line with `KEY=VALUE` matching. The file crosses a trust boundary (written by one skill, consumed by another), so `source` would execute arbitrary shell if any line contained `$(...)`, backticks, or command substitution. The canonical safe-parse pattern lives in `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh` (the `--caller-env` reader).

Note: the current writer (`${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh`) does **not** perform value-side escaping — it emits raw `KEY=value` lines. Safety today depends on (a) the safe line-by-line parser on the read side and (b) a narrowly-constrained value set (fixed schema of known keys: `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`, each drawn from a bounded domain). When your skill adds new fields to a session-env file, constrain the value set at the source (e.g., boolean flags, validated owner/repo strings) rather than relying on parser hardening — and never widen the writer to emit arbitrary user-supplied text without explicit escaping + regression coverage.

When your skill consumes a session-env file, always route through `session-setup.sh --caller-env` rather than ad-hoc `while read` loops so the safe-parse invariant is centralized.

### Health sidecar

Cross-skill reviewer health state uses a `.health` sidecar next to `session-env.sh`. Child skills that run external reviewers (`/design`, `/review`) update the sidecar via `collect-agent-results.sh --write-health "${SESSION_ENV_PATH}.health"`; the parent reads it after each `Skill` return and re-writes `session-env.sh` to persist any newly-unhealthy flags. See `skills/implement/SKILL.md § Cross-Skill Health Propagation`.

## Avoid conditional phrasing for sub-skill invocations

**Scope**: this rule targets the **Skill-tool invocation itself** — not orchestration preconditions. Guards like "If `slack_available=false`, skip Slack" and "If `merge=false`, skip the merge loop" are normal orchestration preconditions and remain fine; the rule below is specifically about how you render a sub-skill invocation.

The worst shape, and the one that gets skipped most often, is a single-line conditional paragraph like:

> If the classification is HARD, call `/implement --auto --merge --session-env $TMPDIR/session-env.sh <description>`; otherwise call `/implement --auto --quick --merge --session-env $TMPDIR/session-env.sh <description>`.

Prose conditionals bury the invocation and reliably slip past the executing model — especially mid-run. Rewrite as an explicit two-branch step, each branch its own numbered sub-step with its own `🔶` breadcrumb (or as Pattern B's heading + variant bullets shape), so the Skill-tool call is the visual center of the step.

## Bare-name-then-fully-qualified fallback

Skill resolution from a consumer repo differs from resolution inside the larch plugin repo itself. In a consumer repo with the plugin installed, `"implement"` resolves correctly — but in a repo where the plugin is installed under a different namespace, the bare name may miss. Always use the two-step fallback:

- **First**: try the bare name — `"implement"`, `"design"`, `"review"`.
- **Second** (only if no skill matched): try the fully-qualified name — `"larch:implement"`, `"larch:design"`, `"larch:review"`.

Never start with the fully-qualified name — it couples the caller to the plugin namespace and breaks in repos that install the plugin under a different name. The alias generator at `${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh` emits this fallback automatically for every alias — see the generated `## Behavior` section inside the `HEREDOC_BODY` block (lines 72-86) of that script; follow the same shape when authoring an invocation by hand.

## Agent-type qualified-name-first fallback

Agent resolution differs from skill resolution. Plugin-defined agents (e.g., `agents/code-reviewer.md`) are namespaced at runtime as `<plugin-name>:<agent-name>` — the bare name does **not** resolve. This is the opposite of the skill-name pattern, where bare names resolve first.

- **First**: try the fully-qualified name — `"larch:code-reviewer"`.
- **Second** (only if not found): try the bare name — `"code-reviewer"`.

All `subagent_type` references in larch skills use the qualified name `larch:code-reviewer`. If a consumer installs the plugin under a different namespace, the bare-name fallback activates.

---

## Cross-references

- `AGENTS.md § Canonical sources` — lists this file as a canonical source (update triggers live at the bottom of this file).
- `skills/shared/progress-reporting.md` — adjacent contract for step-progress formatting.
- `skills/shared/reviewer-templates.md` — canonical source for the Code Reviewer archetype (parallel shared-doc pattern).

## Update triggers

This file is the canonical source for sub-skill invocation conventions (Pattern A bulleted vs Pattern B inline, `allowed-tools` narrowing heuristic, post-invocation verification for orchestrators, anti-halt continuation reminder for orchestrators (closes #177), `session-env` handoff and safe-parse rule, anti-conditional-phrasing for Skill-tool calls, bare-name-then-fully-qualified fallback, agent-type qualified-name-first fallback). Runtime surface (ships to consumers under `skills/`). No generated artifact — update directly. Update trigger: when a cited source-example skill (`/im`, `/imaq`, `/alias`, `/create-skill`, `/fix-issue`, `/implement`, `/review`) changes its invocation pattern or its anti-halt banner/micro-reminder, update the corresponding example in the guide in the same PR. `skills/create-skill/scripts/render-skill-md.sh` emits a `## Sub-skill Invocation` reminder block referencing this file into every scaffolded skill; `skills/create-skill/scripts/test-render-skill-md.sh` is the regression harness guarding that emission (wired into `make lint` via the `test-render-skill` target). `scripts/test-anti-halt-banners.sh` is the paired regression harness for the anti-halt banner and micro-reminder — it asserts banner presence in the five orchestrator SKILL.md files (`/fix-issue`, `/implement`, `/review`, `/alias`, `/research`), absence in the five pure-delegator SKILL.md files (`/im`, `/imaq`, `/create-skill`, `/simplify-skill`, `/compress-skill`), and micro-reminder presence in each of the orchestrators. `/alias` is classified as an orchestrator because its Step 4 runs a sentinel-file verification after `/implement` returns. `/research` is classified as an orchestrator because it may invoke `/issue` via the Skill tool and continue to its report/cleanup steps. Wired into `make lint` via the `test-anti-halt` target.
