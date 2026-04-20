# Sub-skill Invocation Conventions

Canonical style guide for larch skills that delegate to other skills via the `Skill` tool. Cited throughout by `/create-skill`'s scaffold and by `AGENTS.md`. When you author a new skill that invokes another skill, follow the patterns below. When you change a convention here, update the cited source-example skills in the same PR (or file a follow-up issue) so the examples stay in sync with the rules.

## Two invocation patterns

Every larch skill that invokes another skill uses exactly one of two first-class shapes. Pick the one that matches your intent.

### Pattern A — Pure delegator (bulleted)

Used when the parent skill mostly forwards to a child with preset flags or light argument assembly. Appears in `skills/im/SKILL.md § Behavior`, `skills/imaq/SKILL.md § Behavior`, `skills/alias/SKILL.md § Step 3 — Delegate to /implement`, and `skills/create-skill/SKILL.md § Step 3 — Delegate to /implement`. Canonical form:

```
Invoke the Skill tool:
- Try skill: "implement" first (bare name). If no skill matches, try skill: "larch:implement" (fully-qualified plugin name).
- args: --merge $ARGUMENTS
```

Keep the block together. The bare-name-first rule is important — see `## Bare-name-then-fully-qualified fallback` below.

### Pattern B — Stateful orchestrator (inline)

Used when the parent runs setup, forwards `--session-env`, invokes the child, and then parses structured output to continue. Appears in `skills/fix-issue/SKILL.md § Step 6 — Implement` (parent step heading + explicit "Invoke `/implement` via the Skill tool" line + SIMPLE/HARD variant bullets) and in `skills/implement/SKILL.md § Step 1 — Ensure Design Plan Exists`, `§ Step 5 — Code Review`, `§ Step 8 — Version Bump` (around `/design`, `/review`, `/bump-version` calls). Canonical form:

```
Invoke `/implement` via the Skill tool:

- **SIMPLE**: `/implement --auto --quick --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
- **HARD**:   `/implement --auto --merge --session-env $FIX_ISSUE_TMPDIR/session-env.sh <feature description>`
```

The step heading + explicit Skill-tool line + variant bullets shape makes the invocation impossible to miss and keeps the argument list scannable. Do **not** collapse Pattern B into a single paragraph — see `## Avoid conditional phrasing for sub-skill invocations` below.

## allowed-tools narrowing heuristic

Set `allowed-tools` to the minimum needed by the parent skill itself — never mirror the child skill's broader tool set. Three tiers cover every larch skill:

| Tier | `allowed-tools` | Example (with stable anchor) |
|---|---|---|
| Pure delegator | `Skill` | `skills/im/SKILL.md` frontmatter (allowed-tools line) — forwards only |
| Delegator that validates first | `Bash, Skill` | `skills/alias/SKILL.md`, `skills/create-skill/SKILL.md` frontmatter — runs validation scripts before delegating |
| Hybrid orchestrator | `Skill` plus whatever the parent needs | `skills/implement/SKILL.md`, `skills/fix-issue/SKILL.md`, `skills/loop-review/SKILL.md`, `skills/review/SKILL.md` — parent runs setup, file I/O, git ops, etc. |

`allowed-tools: Skill` alone is **neither necessary nor sufficient** to classify a skill as a pure delegator — some delegators need `Bash` for input validation. Conversely, a skill with `Skill` in its allowed list is not automatically a delegator; hybrid orchestrators include `Skill` as one tool among many.

When in doubt, start narrow and widen only for tools the parent actually uses. If your skill adds `Skill` to `allowed-tools`, also confirm the frontmatter includes every other tool your parent invokes (Bash, Read, Edit, Glob, Grep, etc.). Omitting a needed tool produces silent runtime denials — not error messages — so the narrowing heuristic must be paired with a concrete accounting of parent tool usage.

## Post-invocation verification

**Scope**: this rule applies to **orchestrators that continue execution based on a child skill's side effects** — e.g., a parent that reads the child's output to decide the next step. Pure forwarders (`/im`, `/imaq`, `/alias`, `/create-skill`) are exempt — once they delegate, they do nothing further, so there is nothing to verify.

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

- **Parsed stdout machine value after `/issue`** — the orchestrator reads `ISSUES_CREATED=<N>` / `ISSUES_FAILED=<N>` / per-issue `ISSUE_N_NUMBER`/`ISSUE_N_URL` lines from `/issue`'s stdout. Without those parsed values, the parent cannot file the created issue links into the PR body. See `skills/implement/SKILL.md § Step 9a.1 — Create OOS GitHub Issues`.

- **Sentinel file** — `/design` writes `$DESIGN_TMPDIR/accepted-plan-findings.md`; `/implement` reads it (or notices its absence) to know whether to reflect findings in the PR body.

If you cannot name a concrete mechanical check, the call is not actually mandatory — reclassify it as Pattern A (pure delegation) or restructure so the child's side effect is observable.

## Session-env handoff

Environment variables **do not propagate reliably across `Skill` invocations** — treat every `Skill` call as a fresh bash environment. For any state that must cross skill boundaries (reviewer health flags, repo name, slack-ok, session tmpdir), use a session-env file:

1. The parent writes a `session-env.sh` file via `${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh --output "$PARENT_TMPDIR/session-env.sh" --slack-ok <v> --repo <v> ...`.
2. The parent passes `--session-env "$PARENT_TMPDIR/session-env.sh"` to the child.
3. The child reads the file via `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh ... --caller-env "$SESSION_ENV_PATH"`.

Canonical producers and consumers in the live tree:

- `skills/fix-issue/SKILL.md § Step 0 — Setup` writes `$FIX_ISSUE_TMPDIR/session-env.sh` and passes it to `/implement`.
- `skills/implement/SKILL.md § Step 0 — Session Setup` accepts `--session-env` from its parent and propagates a fresh `$IMPLEMENT_TMPDIR/session-env.sh` to `/design` and `/review` via `--session-env` on each invocation.
- `skills/design/SKILL.md § Step 0 — Session Setup` and `skills/review/SKILL.md § Step 0` both accept `--session-env` as an `--caller-env` forward.

### Security — never `source` a session-env file

**Do NOT `source` `session-env.sh`.** Parse it line-by-line with `KEY=VALUE` matching. The file crosses a trust boundary (written by one skill, consumed by another), so `source` would execute arbitrary shell if any line contained `$(...)`, backticks, or command substitution. The canonical safe-parse pattern lives in `${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh` (the `--caller-env` reader).

Note: the current writer (`${CLAUDE_PLUGIN_ROOT}/scripts/write-session-env.sh`) does **not** perform value-side escaping — it emits raw `KEY=value` lines. Safety today depends on (a) the safe line-by-line parser on the read side and (b) a narrowly-constrained value set (fixed schema of known keys: `SLACK_OK`, `SLACK_MISSING`, `REPO`, `REPO_UNAVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY`, each drawn from a bounded domain). When your skill adds new fields to a session-env file, constrain the value set at the source (e.g., boolean flags, validated owner/repo strings) rather than relying on parser hardening — and never widen the writer to emit arbitrary user-supplied text without explicit escaping + regression coverage.

When your skill consumes a session-env file, always route through `session-setup.sh --caller-env` rather than ad-hoc `while read` loops so the safe-parse invariant is centralized.

### Health sidecar

Cross-skill reviewer health state uses a `.health` sidecar next to `session-env.sh`. Child skills that run external reviewers (`/design`, `/review`) update the sidecar via `collect-reviewer-results.sh --write-health "${SESSION_ENV_PATH}.health"`; the parent reads it after each `Skill` return and re-writes `session-env.sh` to persist any newly-unhealthy flags. See `skills/implement/SKILL.md § Cross-Skill Health Propagation`.

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

---

## Cross-references

- `AGENTS.md § Editing rules` — declares this file as the canonical source for sub-skill invocation conventions.
- `skills/shared/progress-reporting.md` — adjacent contract for step-progress formatting.
- `skills/shared/reviewer-templates.md` — canonical source for the Code Reviewer archetype (parallel shared-doc pattern).
