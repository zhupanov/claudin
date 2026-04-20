---
name: alias
description: "Use when creating shortcut aliases for existing larch skills with preset flags. Generates a project-level skill in .claude/skills/ via /implement delegation that forwards to the target skill, optionally with --merge passthrough."
argument-hint: "[--merge] <alias-name> <target-skill> [preset-flags...]"
allowed-tools: Bash, Skill
---

# Alias Skill

Create a project-level alias skill in `.claude/skills/` that forwards to an existing larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (implementation, code review, version bump, PR), then verifies the artifact landed on disk.

Example: `/alias i implement --merge` creates `.claude/skills/i/SKILL.md` so that `/i <feature>` is equivalent to `/implement --merge <feature>`.

Example with merge: `/alias --merge i implement --merge` creates the same alias AND merges the PR after CI passes.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `bail`, `skip to Step N`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule.

## Step 1 — Parse Arguments

Parse flags from the start of `$ARGUMENTS` before treating the remainder as positional arguments. Stop at the first non-flag token (a token not starting with `--`). Only `--merge` appearing before the first positional argument is consumed as a flag for `/alias` itself; any `--merge` in the preset-flags remainder is passed through verbatim to the alias.

- `--merge`: Set `alias_merge=true`. Default: `alias_merge=false`. When true, `--merge` is forwarded to the `/implement` invocation so the resulting PR is also merged.

**`--merge` dual-role reference**:

| Position | Meaning |
|----------|---------|
| Before first positional token | Consumed by /alias (sets `alias_merge=true`) |
| After first positional token | Pass-through to the generated alias's preset flags |

After flag stripping, parse the remaining positional arguments:
- First token = **alias name**
- Second token = **target skill name** (without `/` prefix)
- Remainder = **preset flags** (may be empty — a pure rename shortcut is valid)

If fewer than 2 positional tokens are provided, print: `**ERROR: Usage: /alias [--merge] <alias-name> <target-skill> [preset-flags...]**` and abort.

## Step 2 — Validate

All validation uses Bash since `${CLAUDE_PLUGIN_ROOT}` is a shell variable not resolvable in Read/Glob.

1. **Alias name format**: Verify alias name matches `^[a-z][a-z0-9-]*$` (lowercase, alphanumeric + hyphens, must start with a letter).
   - If invalid, print: `**ERROR: Alias name '<name>' is invalid. Must start with a lowercase letter and contain only lowercase letters, digits, and hyphens.**` and abort.

2. **Reserved name check (dynamic probe — shadows any larch skill)**. Fail-closed on unset `${CLAUDE_PLUGIN_ROOT}`, then probe both plugin-tree roots for a directory collision:
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
   One conceptual rule — "alias cannot shadow any larch skill" — replacing the prior static enumeration that was drifting as new skills shipped.

3. **Target name format**: Verify target skill name matches `^[a-z][a-z0-9-]*$` (same format as alias names).
   - If invalid, print: `**ERROR: Target name '<target>' is invalid. Must contain only lowercase letters, digits, and hyphens.**` and abort.

4. **Target skill exists**: Verify target skill exists:
   ```bash
   test -f "${CLAUDE_PLUGIN_ROOT}/skills/<target>/SKILL.md"
   ```
   - If not found, print: `**ERROR: Target skill '<target>' does not exist.**` Then list valid targets:
     ```bash
     ls "${CLAUDE_PLUGIN_ROOT}/skills/"
     ```
     and abort.

5. **Target is not "alias"**: Forbid alias-to-alias recursion.
   - If target is "alias", print: `**ERROR: Cannot create an alias that targets /alias (no alias-to-alias recursion).**` and abort.

6. **Collision check**: Verify `.claude/skills/<alias-name>/` does not already exist in the current project:
   ```bash
   test -d ".claude/skills/<alias-name>"
   ```
   - If it exists, print: `**ERROR: '.claude/skills/<alias-name>/' already exists. Remove it first or choose a different name.**` and abort.

## Step 3 — Delegate to /implement

Construct an explicit feature description for `/implement`. The description MUST cite the generator script path, its required flags, the version source, and the write target so `/implement` has a complete, deterministic build recipe — no codebase research required:

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

Omit the `<preset-flags>` segment from the leading sentence when empty (pure rename shortcut).

Print: `**Alias /<alias-name> -> /<target-skill> <preset-flags> — delegating to /implement --quick --auto [--merge]**` (omit `<preset-flags>` and `--merge` parts if empty/false respectively).

Invoke the Skill tool:
- Try skill: `"implement"` first (bare name). If no skill matches, try skill: `"larch:implement"` (fully-qualified plugin name).
- args: `"--quick --auto [--merge] <feature-description>"`

Only include `--merge` in the args if `alias_merge=true`.

> **Continue after child returns.** When `/implement` returns, execute Step 4 — do NOT end the turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder.

## Step 4 — Verify

After `/implement` returns, verify the alias SKILL.md actually landed on disk. Run from repo root (resolved robustly regardless of agent cwd):

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
  --sentinel-file "${REPO_ROOT}/.claude/skills/<alias-name>/SKILL.md"
```

Parse stdout for `VERIFIED=true|false` and `REASON=<token>`.

- **If `VERIFIED=true`**: print `✅ /alias — created .claude/skills/<alias-name>/SKILL.md` and exit 0.
- **If `VERIFIED=false`**: print a fail-closed error and exit 1:
  ```
  **ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. Inspect the PR/branch manually — /implement may have written the file elsewhere, skipped the generator, or failed silently.**
  ```
  Do not attempt auto-remediation — `/implement` has already created (and possibly merged) the PR, so any recovery requires human judgment.
