# Sub-skill Invocation Conventions

Canonical style guide for larch skills delegate to other skills via `Skill` tool. Cited throughout by `/create-skill` scaffold and `AGENTS.md`. When author new skill invoke another skill, follow patterns below. When change convention here, update cited source-example skills in same PR (or file follow-up issue) so examples stay in sync with rules.

## Two invocation patterns

Every larch skill invoke another skill use exactly one of two first-class shapes. Pick one match intent.

### Pattern A — Pure delegator (bulleted)

Use when parent skill mostly forward to child with preset flags or light argument assembly. Appear in `skills/im/SKILL.md § Behavior`, `skills/imaq/SKILL.md § Behavior`, and `skills/create-skill/SKILL.md § Step 3 — Delegate to /im`. Canonical form:

```
Invoke the Skill tool:
- Try skill: "implement" first (bare name). If no skill matches, try skill: "larch:implement" (fully-qualified plugin name).
- args: --merge $ARGUMENTS
```

Keep block together. Bare-name-first rule important — see `## Bare-name-then-fully-qualified fallback` below.

Note: `/create-skill` forward to `/im` (not directly to `/implement`); `/im` in turn forward to `/implement --merge` per own Pattern A definition. Chained delegation give `/create-skill` auto-merge semantics while keep each hop minimal pure forwarder.

### Pattern B — Stateful orchestrator (inline)

Use when parent run setup, forward `--session-env`, invoke child, then parse structured output to continue. Appear in `skills/fix-issue/SKILL.md § Step 6 — Execute` (parent step heading + explicit "Invoke `/implement` via the Skill tool" line + SIMPLE/HARD variant bullets) and `skills/implement/SKILL.md § Step 1 — Ensure Design Plan Exists`, `skills/implement/SKILL.md § Step 5 — Code Review`, `skills/implement/SKILL.md § Step 8 — Version Bump` (around `/design`, `/review`, `/bump-version` calls). Canonical form:

```
Invoke `/implement` via the Skill tool:

- **SIMPLE**: `/implement --auto --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
- **HARD**:   `/implement --auto --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
```

Step heading + explicit Skill-tool line + variant bullets shape make invocation impossible miss and keep argument list scannable. Do **not** collapse Pattern B into single paragraph — see `## Avoid conditional phrasing for sub-skill invocations` below.

`scripts/lint-skill-invocations.py` mechanically enforce line-local co-location: every direct-invocation line say ``Invoke `/<name>`'' (with optional `the` and bounded `**bold-span**`) must also contain `via the Skill tool` on same line.

## allowed-tools narrowing heuristic

Set `allowed-tools` to minimum need by parent skill itself — never mirror child skill's broader tool set. Three tiers cover every larch skill:

| Tier | `allowed-tools` | Example (with stable anchor) |
|---|---|---|
| Pure delegator | `Skill` | `skills/im/SKILL.md` frontmatter (allowed-tools line) — forwards only |
| Delegator that validates first | `Bash, Skill` | `skills/create-skill/SKILL.md` frontmatter — runs validation scripts before delegating |
| Hybrid orchestrator | `Skill` plus whatever the parent needs | `skills/implement/SKILL.md`, `skills/fix-issue/SKILL.md`, `skills/loop-review/SKILL.md`, `skills/review/SKILL.md`, `skills/alias/SKILL.md`, `skills/research/SKILL.md` — parent runs setup, file I/O, git ops, and in `/alias`'s case a post-delegation sentinel-file verification. |

`allowed-tools: Skill` alone **neither necessary nor sufficient** classify skill as pure delegator — some delegators need `Bash` for input validation. Conversely, skill with `Skill` in allowed list not automatically delegator; hybrid orchestrators include `Skill` as one tool among many.

When in doubt, start narrow and widen only for tools parent actually use. If skill add `Skill` to `allowed-tools`, also confirm frontmatter include every other tool parent invoke (Bash, Read, Edit, Glob, Grep, etc.). Omit needed tool produce silent runtime denials — not error messages — so narrowing heuristic must pair with concrete accounting of parent tool usage.

## Post-invocation verification

**Scope**: rule apply to **orchestrators continue execution based on child skill's side effects** — e.g., parent read child's output decide next step. Pure forwarders (`/im`, `/imaq`, `/create-skill`, `/loop-improve-skill`) exempt — once delegate, do nothing further, so nothing verify.

For every mandatory sub-skill call inside orchestrator's step, pair call with **mechanical check parent cannot satisfy without child's side effects**. Check must read filesystem, parse stdout, or compare counters — never rely on child's prose acknowledgement. If child silently skip or internally bail, check must notice.

Canonical examples:

- **Commit-count delta around `/bump-version`** — orchestrator capture pre-count, invoke skill, then compare with post-count:

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

  See `skills/implement/SKILL.md § Step 8 — Version Bump` for full recipe. `--mode post` **requires** `--before-count $COMMITS_BEFORE` — call `--mode post` without it error out at script level.

- **Parsed stdout machine value after `/issue`** — orchestrator read `ISSUES_CREATED=<N>` / `ISSUES_FAILED=<N>` / per-issue `ISSUE_N_NUMBER`/`ISSUE_N_URL` lines from `/issue` stdout. Without parsed values, parent cannot file created issue links into PR body. See `skills/implement/SKILL.md § 9a.1 — Create OOS GitHub Issues`.

- **Sentinel file** — `/design` write `$DESIGN_TMPDIR/accepted-plan-findings.md`; `/implement` read it (or notice absence) to know whether reflect findings in PR body.

If cannot name concrete mechanical check, call not actually mandatory — reclassify as Pattern A (pure delegation) or restructure so child's side effect observable.

See `## Anti-halt continuation reminder` below — two sections govern same call-site boundary from complementary directions (verification ask "did child run?"; anti-halt ask "did parent continue?").

## Anti-halt continuation reminder

**Scope**: rule apply to same orchestrator set as `## Post-invocation verification` above — stateful orchestrators (`/fix-issue`, `/implement`, `/review`, `/loop-review`, `/alias`, `/research`) run additional steps after child `Skill` tool call return. Pure forwarders (`/im`, `/imaq`, `/create-skill`, `/loop-improve-skill`) exempt — once delegate, do nothing further. (`/loop-improve-skill` classified as pure delegator because runtime driver live in `skills/loop-improve-skill/scripts/driver.sh` — subprocess-driven bash driver not use `Skill` tool chain children.) Two sections complementary: `## Post-invocation verification` ask **"did child run?"**; this section ask **"did parent continue?"** Both failure modes distinct and real (see GitHub issue #177 for originating report).

**The rule**: after every child `Skill` tool call (`/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) return, main agent MUST immediately continue with parent skill's NEXT step. Child's cleanup / summary output NOT end-of-turn. In long sessions where child produce many tokens (e.g., `/design` with 3 reviewers + voting easily produce 15k+ tokens), main agent's attention can drift to child's local "mission accomplished" framing and lose parent orchestration frame. Short standardized banner at top of every orchestrator plus short per-Skill-call-site micro-reminders reinforce rule where attention most at risk.

**Carve-out (critical)**: rule strictly subordinate to any explicit non-sequential control-flow directive in parent skill — include `skip to Step N`, `bail to cleanup`, `jump back to Step Na`, `loop back to Step 3a`, `fall through to 12c`, `break out of the loop`, or any other explicit redirect. Normal numerically-sequential `proceed to Step N+1` directive default continuation path anti-halt reinforces — NOT exception.

**Loop-internal carve-out**: when parent's step explicitly loop (e.g., `/loop-review`'s Step 3f → 3g → 3a slice loop), "next step" of parent IS loop-continuation directive, not first textually-following section header. Use loop-aware micro-reminder variant at loop-internal child-Skill call sites.

**Generic `/relevant-checks` clause**: every `/relevant-checks` invocation anywhere in orchestrator SKILL.md covered by rule without require per-site micro-reminder at every call site. Parent must resume after `/relevant-checks` return — whether mean advance to next numbered step, re-run `/relevant-checks` after fix, or commit fixed files.

### Canonical banner (top of each orchestrator SKILL.md, after the title body, before `## Progress Reporting`)

````markdown
**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/design`, `/review`, `/relevant-checks`, `/bump-version`, `/issue`, `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `skip to Step N`, `bail to cleanup`, `jump back`, `loop back`, `fall through`, `break out`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.
````

Substring `**Anti-halt continuation reminder.**` contract token assert by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh`.

### Canonical micro-reminder (per Skill-tool call site — branch-specific placement)

Place micro-reminder **inside specific branch actually invoke child** — not at top of step whose body may skip invocation on some branches (e.g., `/implement` Step 1 quick-mode skip `/design`; Step 5 quick-mode skip `/review`; Step 8 `HAS_BUMP=false` skip `/bump-version`). Reminder belong next to real Skill-tool call, inside branch emit it.

Standard variant:

````markdown
> **Continue after child returns.** When the child Skill returns, execute the NEXT step of this skill — do NOT end the turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.
````

Loop-aware variant (for loop-internal call sites like `/loop-review`'s `/issue` batch flush):

````markdown
> **Continue after child returns (loop-internal).** When the child Skill returns, continue the loop per the parent's explicit loop-back directive — do NOT exit the loop unless the exit condition fires. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.
````

Substring `Continue after child returns` contract token assert by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh` (match both standard and loop-internal variants).

### Scope list

Banner MUST appear in these orchestrator SKILL.md files:

- `skills/fix-issue/SKILL.md`
- `skills/implement/SKILL.md`
- `skills/review/SKILL.md`
- `skills/loop-review/SKILL.md`
- `skills/alias/SKILL.md`
- `skills/research/SKILL.md`

Banner MUST NOT appear in pure-delegator SKILL.md files:

- `skills/im/SKILL.md`
- `skills/imaq/SKILL.md`
- `skills/create-skill/SKILL.md`
- `skills/loop-improve-skill/SKILL.md`

Both presence and absence enforce by `${CLAUDE_PLUGIN_ROOT}/scripts/test-anti-halt-banners.sh`, wired into `make lint` via `test-anti-halt` target.

## Session-env handoff

Environment variables **do not propagate reliably across `Skill` invocations** — treat every `Skill` call as fresh bash environment. For any state must cross skill boundaries (reviewer health flags, repo name, slack-ok, session tmpdir), use session-env file:

1. Parent write `session-env.sh` file via `${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$PARENT_TMPDIR/session-env.sh" --slack-ok <v> --repo <v> ...`.
2. Parent pass `--session-env "$PARENT_TMPDIR/session-env.sh"` to child.
3. Child read file via `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh ... --caller-env "$SESSION_ENV_PATH"`.

Canonical producers and consumers in live tree:

- `skills/fix-issue/SKILL.md § Step 0 — Setup` write `$FIX_ISSUE_TMPDIR/session-env.sh` and pass to `/implement`.
- `skills/implement/SKILL.md § Step 0 — Session Setup` accept `--session-env` from parent and propagate fresh `$IMPLEMENT_TMPDIR/session-env.sh` to `/design` and `/review` via `--session-env` on each invocation.
- `skills/design/SKILL.md § Step 0 — Session Setup` and `skills/review/SKILL.md § Step 0 — Session Setup` both accept `--session-env` as `--caller-env` forward.

### Security — never `source` a session-env file

**Do NOT `source` `session-env.sh`.** Parse line-by-line with `KEY=VALUE` matching. File cross trust boundary (written by one skill, consumed by another), so `source` would execute arbitrary shell if any line contain `$(...)`, backticks, or command substitution. Canonical safe-parse pattern live in `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh` (the `--caller-env` reader).

Note: current writer (`${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh`) does **not** perform value-side escaping — emit raw `KEY=value` lines. Safety today depend on (a) safe line-by-line parser on read side and (b) narrowly-constrained value set (fixed schema of known keys: `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`, each drawn from bounded domain). When skill add new fields to session-env file, constrain value set at source (e.g., boolean flags, validated owner/repo strings) rather than rely on parser hardening — and never widen writer emit arbitrary user-supplied text without explicit escaping + regression coverage.

When skill consume session-env file, always route through `session-setup.sh --caller-env` rather than ad-hoc `while read` loops so safe-parse invariant centralized.

### Health sidecar

Cross-skill reviewer health state use `.health` sidecar next to `session-env.sh`. Child skills run external reviewers (`/design`, `/review`) update sidecar via `collect-reviewer-results.sh --write-health "${SESSION_ENV_PATH}.health"`; parent read it after each `Skill` return and re-write `session-env.sh` persist any newly-unhealthy flags. See `skills/implement/SKILL.md § Cross-Skill Health Propagation`.

## Avoid conditional phrasing for sub-skill invocations

**Scope**: rule target **Skill-tool invocation itself** — not orchestration preconditions. Guards like "If `slack_available=false`, skip Slack" and "If `merge=false`, skip the merge loop" normal orchestration preconditions and remain fine; rule below specifically about how render sub-skill invocation.

Worst shape, and one get skipped most often, single-line conditional paragraph like:

> If the classification is HARD, call `/implement --auto --merge --session-env $TMPDIR/session-env.sh <description>`; otherwise call `/implement --auto --quick --merge --session-env $TMPDIR/session-env.sh <description>`.

Prose conditionals bury invocation and reliably slip past executing model — especially mid-run. Rewrite as explicit two-branch step, each branch own numbered sub-step with own `🔶` breadcrumb (or as Pattern B's heading + variant bullets shape), so Skill-tool call visual center of step.

## Bare-name-then-fully-qualified fallback

Skill resolution from consumer repo differ from resolution inside larch plugin repo itself. In consumer repo with plugin installed, `"implement"` resolve correctly — but in repo where plugin installed under different namespace, bare name may miss. Always use two-step fallback:

- **First**: try bare name — `"implement"`, `"design"`, `"review"`.
- **Second** (only if no skill matched): try fully-qualified name — `"larch:implement"`, `"larch:design"`, `"larch:review"`.

Never start with fully-qualified name — couple caller to plugin namespace and break in repos install plugin under different name. Alias generator at `${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh` emit fallback automatically for every alias — see generated `## Behavior` section inside `HEREDOC_BODY` block (lines 72-86) of script; follow same shape when author invocation by hand.

---

## Cross-references

- `AGENTS.md § Editing rules` — declare this file as canonical source for sub-skill invocation conventions.
- `skills/shared/progress-reporting.md` — adjacent contract for step-progress formatting.
- `skills/shared/reviewer-templates.md` — canonical source for Code Reviewer archetype (parallel shared-doc pattern).
