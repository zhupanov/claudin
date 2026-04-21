---
name: alias
description: "Use when creating shortcut aliases (wrappers) for existing larch skills with preset flags. Generates a project-level skill in .claude/skills/ via /implement delegation that forwards to the target skill, optionally with --merge passthrough."
argument-hint: "[--merge] <alias-name> <target-skill> [preset-flags...]"
allowed-tools: Bash, Skill
---

# Alias Skill

Skill follow Process pattern: numbered steps, checkpointed delegation, fail-closed verification.

Make project-level alias skill in `.claude/skills/` forward to existing larch skill with preset flags. Delegate to `/implement --quick --auto` for full pipeline (implementation, code review, version bump, PR), then verify artifact land on disk.

Example: `/alias i implement --merge` make `.claude/skills/i/SKILL.md` so `/i <feature>` same as `/implement --merge <feature>`.

Example with merge: `/alias --merge i implement --merge` make same alias AND merge PR after CI pass.

## NEVER

1. **NEVER make alias target `/alias`** — no alias-to-alias recursion. **Why:** multiply indirection, break flat forward contract. Step 2 check #5 enforce.
2. **NEVER let alias name shadow existing larch skill** — not `skills/` (public) nor `.claude/skills/` (dev-only). **Why:** shadow silent reroute `/<name>` invocation. Step 2 check #2 enforce via dynamic probe.
3. **NEVER auto-remediate when `VERIFIED=false` in Step 4** — do NOT retry `/implement`, roll back, or delete PR. **Why:** under `--merge` PR maybe already merged; retry make divergent PR. Human judgment need.
4. **NEVER assume success on `VERIFIED=false` just because `/implement` return.** **Why:** `/implement` can return clean while write file wrong path, skip generator, or fail silent — sentinel-file gate only authoritative signal.
5. **NEVER parse `--merge` token after first positional arg as flag for `/alias`.** **Why:** `--merge` dual role (consume by `/alias` when before first positional; pass through to alias preset flags else); conflate two = silent footgun.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/implement`) return, IMMEDIATELY continue with this skill NEXT numbered step — do NOT end turn on child cleanup output. Rule strict subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `bail`, `skip to Step N`). Normal sequential `proceed to Step N+1` instruction = default continuation this rule reinforce, NOT exception. Every `/relevant-checks` invocation anywhere in file covered by rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for canonical rule. **Do NOT load** that reference for routine invocation — inline rule above enough. Load only when debug child-Skill halt symptom or when add new child-Skill invocation to file.

## Step 1 — Parse Arguments

Parse flag from start of `$ARGUMENTS` before treat remainder as positional arg. Stop at first non-flag token (token not start with `--`). Only `--merge` appear before first positional arg consumed as flag for `/alias` self; any `--merge` in preset-flags remainder pass through verbatim to alias.

- `--merge`: Set `alias_merge=true`. Default: `alias_merge=false`. When true, `--merge` forward to `/implement` invocation so result PR also merge.

**`--merge` dual-role reference**:

| Position | Meaning |
|----------|---------|
| Before first positional token | Consumed by /alias (sets `alias_merge=true`) |
| After first positional token | Pass-through to the generated alias's preset flags |

After flag strip, parse remain positional arg:
- First token = **alias name**
- Second token = **target skill name** (no `/` prefix)
- Remainder = **preset flags** (can empty — pure rename shortcut valid)

If fewer than 2 positional token given, print: `**ERROR: Usage: /alias [--merge] <alias-name> <target-skill> [preset-flags...]**` and abort.

## Step 2 — Validate

All validation use Bash since `${CLAUDE_PLUGIN_ROOT}` = shell variable not resolvable in Read/Glob.

| # | Check | Rule | On fail |
|---|-------|------|---------|
| 1 | Alias name format | Must match `^[a-z][a-z0-9-]*$` (lowercase, alphanumeric + hyphens, must start with a letter) | `E_ALIAS_NAME` |
| 2 | Reserved name (dynamic probe) | `${CLAUDE_PLUGIN_ROOT}` must be set; alias name must not collide with any directory under `${CLAUDE_PLUGIN_ROOT}/skills/<alias-name>` OR `${CLAUDE_PLUGIN_ROOT}/.claude/skills/<alias-name>`. See `### Check 2` block below. | `E_PLUGIN_ROOT_UNSET` or `E_SHADOW` |
| 3 | Target name format | Must match `^[a-z][a-z0-9-]*$` (same format as alias names) | `E_TARGET_NAME` |
| 4 | Target skill exists | `test -f "${CLAUDE_PLUGIN_ROOT}/skills/<target>/SKILL.md"`; if missing, also run `ls "${CLAUDE_PLUGIN_ROOT}/skills/"` for discoverability | `E_TARGET_MISSING` |
| 5 | Target is not `alias` | Forbid alias-to-alias recursion | `E_RECURSION` |
| 6 | Collision check | `test -d ".claude/skills/<alias-name>"` must be false | `E_COLLISION` |

### Check 2 — reserved-name dynamic probe

Fail-closed on unset `${CLAUDE_PLUGIN_ROOT}`, then probe both plugin-tree root for directory collision:

```bash
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  echo "**ERROR: CLAUDE_PLUGIN_ROOT is unset — cannot probe larch skill tree for reserved-name collision.**"
  exit 1
fi
# probe BOTH roots: skills/ (public) and .claude/skills/ (dev-only: bump-version, relevant-checks)
if test -d "${CLAUDE_PLUGIN_ROOT}/skills/<alias-name>" \
  || test -d "${CLAUDE_PLUGIN_ROOT}/.claude/skills/<alias-name>"; then
  echo "**ERROR: alias name '<alias-name>' shadows an existing larch skill.**"
  exit 1
fi
```

One conceptual rule — "alias cannot shadow any larch skill" — replace prior static enumeration that drift as new skills ship.

### Error strings (reference)

| ID | Printed string |
|----|----------------|
| `E_ALIAS_NAME` | `**ERROR: Alias name '<name>' is invalid. Must start with a lowercase letter and contain only lowercase letters, digits, and hyphens.**` |
| `E_PLUGIN_ROOT_UNSET` | `**ERROR: CLAUDE_PLUGIN_ROOT is unset — cannot probe larch skill tree for reserved-name collision.**` |
| `E_SHADOW` | `**ERROR: alias name '<alias-name>' shadows an existing larch skill.**` |
| `E_TARGET_NAME` | `**ERROR: Target name '<target>' is invalid. Must contain only lowercase letters, digits, and hyphens.**` |
| `E_TARGET_MISSING` | `**ERROR: Target skill '<target>' does not exist.**` (then run `ls "${CLAUDE_PLUGIN_ROOT}/skills/"` and abort) |
| `E_RECURSION` | `**ERROR: Cannot create an alias that targets /alias (no alias-to-alias recursion).**` |
| `E_COLLISION` | `**ERROR: '.claude/skills/<alias-name>/' already exists. Remove it first or choose a different name.**` |

## Step 3 — Delegate to /implement

### Before delegating, ask

- **What `/implement` need to build this deterministic?** `/implement` no codebase context about `/alias` — will research and guess unless feature description cite generator script path, require flags, version source, write target. Explicit recipe below supply all four.
- **What could make Step 4 verification silent pass when should not?** Nothing — `verify-skill-called.sh --sentinel-file` gate read child-produced artifact (`.claude/skills/<alias-name>/SKILL.md`) that outer orchestrator cannot synthesize. Parent-writable gate not load-bearing.
- **Why no retry on `VERIFIED=false`?** Under `--merge` PR maybe already merged by time control return; any auto retry make divergent PR. Step 4 surface branch-specific diagnostic message instead, leave recovery to human judgment.

Build explicit feature description for `/implement`. Description MUST cite generator script path, require flags, version source, write target so `/implement` have complete, deterministic build recipe — no codebase research need:

```
Add /<alias-name> alias for /<target-skill> <preset-flags>.

Generate the alias skill by running:
  mkdir -p .claude/skills/<alias-name>
  "${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh" \
    --name "<alias-name>" \
    --target "<target-skill>" \
    --flags "<preset-flags>" \
    --version "$(jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")" \
    > ".claude/skills/<alias-name>/SKILL.md"

If jq fails or plugin.json is malformed, proceed with an empty --version value (the generator handles this — the footer simply omits the vX.Y.Z suffix).
```

Omit `<preset-flags>` segment from lead sentence when empty (pure rename shortcut).

Print: `**Alias /<alias-name> -> /<target-skill> <preset-flags> — delegating to /implement --quick --auto [--merge]**` (omit `<preset-flags>` and `--merge` parts if empty/false).

Invoke Skill tool:
- Try skill: `"implement"` first (bare name). If no skill match, try skill: `"larch:implement"` (full-qualified plugin name).
- args: `"--quick --auto [--merge] <feature-description>"`

Only include `--merge` in args if `alias_merge=true`.

> **Continue after child returns.** When `/implement` return, execute Step 4 — do NOT end turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder. **Do NOT load** that reference for routine `/implement` return — load only when add new child-Skill invocation to file or debug halt symptom.

## Step 4 — Verify

After `/implement` return, verify alias SKILL.md actual land on disk. Run from repo root (resolve robust regardless of agent cwd):

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
  --sentinel-file "${REPO_ROOT}/.claude/skills/<alias-name>/SKILL.md"
```

Parse stdout for `VERIFIED=true|false` and `REASON=<token>`.

- **If `VERIFIED=true`**: print `✅ /alias — created .claude/skills/<alias-name>/SKILL.md` and exit 0.
- **If `VERIFIED=false`**: print fail-closed error and exit 1. Branch message on `alias_merge`:
  - **If `alias_merge=false`** (PR created but not merged):
    ```
    **ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. Inspect the PR/branch manually — /implement may have written the file elsewhere, skipped the generator, or failed silently.**
    ```
  - **If `alias_merge=true`** (PR may already be merged):
    ```
    **ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). The PR may have already been merged — do not assume success. Inspect the PR/branch/merged-main manually; a revert or follow-up PR may be required.**
    ```
  No auto-remediation — `/implement` already create (and maybe merge) PR, so any recovery need human judgment.

### Authoritative exit states

| State | Condition | Printed string (summary) |
|-------|-----------|--------------------------|
| Success | `VERIFIED=true` | `✅ /alias — created .claude/skills/<alias-name>/SKILL.md` |
| Validation fail | Any Step 2 check fails | one of the `E_*` strings from the Step 2 `Error strings (reference)` table |
| Verify fail (unmerged) | `VERIFIED=false` AND `alias_merge=false` | `**ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. ...**` (full string above) |
| Verify fail (merged) | `VERIFIED=false` AND `alias_merge=true` | `**ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). The PR may have already been merged ...**` (full string above) |
