---
name: alias
description: "Use when creating shortcut aliases for existing larch skills with preset flags. Generates a project-level skill in .claude/skills/ that forwards to the target skill."
argument-hint: "<alias-name> <target-skill> [preset-flags...]"
allowed-tools: Bash, Read, Write, Grep, Glob
---

# Alias Skill

Create a project-level alias skill in `.claude/skills/` that forwards to an existing larch skill with preset flags.

Example: `/alias i implement --merge` creates `/.claude/skills/i/SKILL.md` so that `/i <feature>` is equivalent to `/implement --merge <feature>`.

## Step 1 — Parse Arguments

Parse `$ARGUMENTS`:
- First token = **alias name**
- Second token = **target skill name** (without `/` prefix)
- Remainder = **preset flags** (may be empty — a pure rename shortcut is valid)

If fewer than 2 tokens are provided, print: `**ERROR: Usage: /alias <alias-name> <target-skill> [preset-flags...]**` and abort.

## Step 2 — Validate

All validation uses Bash since `${CLAUDE_PLUGIN_ROOT}` is a shell variable not resolvable in Read/Glob.

1. **Alias name format**: Verify alias name matches `^[a-z][a-z0-9-]*$` (lowercase, alphanumeric + hyphens, must start with a letter).
   - If invalid, print: `**ERROR: Alias name '<name>' is invalid. Must start with a lowercase letter and contain only lowercase letters, digits, and hyphens.**` and abort.

2. **Reserved name check**: Reject if alias name matches any of: `design`, `implement`, `review`, `research`, `loop-review`, `alias`, `relevant-checks`, `bump-version`, `fix-issue`.
   - If reserved, print: `**ERROR: Cannot create alias '<name>' — this name is reserved (it matches an existing larch or common project-level skill). Choose a different name.**` and abort.

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

## Step 3 — Resolve Skill Invocation

The generated alias SKILL.md instructs the agent to invoke the target skill via the Skill tool. It tries the bare skill name first (e.g., `"implement"`), then falls back to `"larch:<name>"` (fully-qualified plugin name) if the bare name does not match an available skill. This avoids hardcoding a namespace assumption.

## Step 4 — Generate SKILL.md Content

Read the current plugin version:
```bash
grep '"version"' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json" | sed 's/.*"version": *"\([^"]*\)".*/\1/'
```

Generate the SKILL.md content via the helper script:
```bash
${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh \
  --name <alias-name> \
  --target <target-skill> \
  --flags "<preset-flags>" \
  --version <current-version>
```

Capture the script's stdout as the generated SKILL.md content.

## Step 5 — Write the File

Create the directory and write the file:
```bash
mkdir -p ".claude/skills/<alias-name>"
```

Write the generated content to `.claude/skills/<alias-name>/SKILL.md` using the Write tool.

## Step 6 — Stage and Commit

Stage and commit using the wrapper script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/git-commit.sh \
  -m "Add /<alias-name> alias for /<target-skill> <preset-flags>" \
  ".claude/skills/<alias-name>/SKILL.md"
```

If `<preset-flags>` is empty (a pure rename alias), omit the trailing flags from the commit message: `"Add /<alias-name> alias for /<target-skill>"`.

## Step 7 — Confirm

If `<preset-flags>` is non-empty, print: `Alias /<alias-name> created -> /<target-skill> <preset-flags>. Committed on current branch.`

If `<preset-flags>` is empty, print: `Alias /<alias-name> created -> /<target-skill>. Committed on current branch.`
