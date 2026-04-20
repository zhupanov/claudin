---
name: create-skill
description: "Use when creating a new larch skill. Validates name and description, then delegates to /implement --quick --auto to scaffold via render-skill-md.sh. Writes under .claude/skills/ by default; --plugin writes under skills/."
argument-hint: "[--plugin] [--multi-step] [--merge] [--debug] <skill-name> <description>"
allowed-tools: Bash, Skill
---

# Create Skill

Scaffold a new larch-style skill and delegate to `/implement --quick --auto` for the full pipeline (implementation, code review, version bump, PR).

Example: `/create-skill foo "Use when doing X"` creates `.claude/skills/foo/SKILL.md` in the consumer repo. With `--plugin`, creates `skills/foo/SKILL.md` inside the larch plugin repo.

## Step 1 — Parse Arguments

Invoke the argument parser:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/parse-args.sh $ARGUMENTS
```

Parse the output for `NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`.

If the script exits non-zero or emits an `ERROR=` line, print the error and abort.

## Step 2 — Validate Arguments

Invoke the validator. Include `--plugin` only when `PLUGIN=true`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/validate-args.sh --name "$NAME" --description "$DESCRIPTION" [--plugin]
```

Parse the output for `VALID`. If `VALID=false` or the script exits non-zero, print the `ERROR=` message and abort.

The validator enforces:
- Name matches `^[a-z][a-z0-9-]*$`, length ≤ 64.
- Name is not in the reserved-name union: Anthropic reserved names + larch's static reserved list + existing plugin skills under `${CLAUDE_PLUGIN_ROOT}/skills` + existing project-local skills under the caller's `.claude/skills/` directory. Missing directories are treated as empty. Comparisons are case-insensitive.
- When `--plugin` is set, the CWD must be the larch plugin repo (`.claude-plugin/plugin.json` + `skills/implement/SKILL.md` present).
- Description is non-empty, ≤ 1024 chars, contains no XML tags, no backticks, no `$(`, no heredoc terminators or frontmatter breakers, no newlines or control characters.

## Step 3 — Delegate to /implement

Construct a concise feature description for `/implement`:

- Target directory (in consumer mode): `.claude/skills/<NAME>/`
- Target directory (plugin mode, `--plugin`): `skills/<NAME>/`
- Local path token (in consumer mode): the working-directory shell variable (the consumer-repo root).
- Local path token (plugin mode): `${CLAUDE_PLUGIN_ROOT}`
- Plugin path token (always): `${CLAUDE_PLUGIN_ROOT}`
- Template: `multi-step` if `MULTI_STEP=true`, else `minimal`.

Feature description template (fill placeholders from the parsed values):

```
Scaffold new skill /<NAME> at <TARGET_DIR>. Description: "<DESCRIPTION>". Path mode: <plugin-dev|consumer>. Template: <minimal|multi-step>.

Use ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/render-skill-md.sh to write the scaffold:
  render-skill-md.sh --name "<NAME>" --description "<DESCRIPTION>" \
    --target-dir "<TARGET_DIR>" \
    --local-token "<LOCAL_TOKEN>" --plugin-token "${CLAUDE_PLUGIN_ROOT}" \
    --multi-step <MULTI_STEP>

After scaffolding, run ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/post-scaffold-hints.sh --target-dir "<TARGET_DIR>" --plugin <PLUGIN> and include the hints in the PR body.

If --plugin, also:
  - Add a row for /<NAME> to README.md Skills catalog and feature matrix.
  - Add three permission entries to .claude/settings.json permissions.allow, then re-sort the whole permissions.allow block by strict ASCII code-point order (e.g. via `sort -u`) so the new entries interleave correctly with existing ones (do NOT assume the new entries always append; `Skill(larch:<NAME>)` may sort before `Skill(loop-review)`, `Skill(research)`, or `Skill(review)` depending on <NAME>):
      - Bash entry for the new skill's scripts directory (using the working-directory shell variable prefix + skills/<NAME>/scripts/*).
      - Skill(<NAME>) entry (bare name).
      - Skill(larch:<NAME>) entry (fully-qualified plugin name).
  - Rationale: larch's `.claude/settings.json` runs under `defaultMode: "bypassPermissions"` so both Skill forms are cosmetic in the plugin-dev harness, but they document the dual-form convention consumers running in strict permissions must adopt. See the README subsection "Strict-permissions consumers — Skill permission entries" for the consumer-side rationale and the canonical copy-paste block.
```

Print: `**Create-skill /<NAME> (<plugin-dev|consumer>, <minimal|multi-step>) — delegating to /implement --quick --auto [--merge] [--debug]**` (omit the optional flags that are `false`).

Invoke the Skill tool:
- Try skill: `"implement"` first (bare name). If no skill matches, try skill: `"larch:implement"` (fully-qualified plugin name).
- args: `"--quick --auto [--merge] [--debug] <feature-description>"` — include `--merge` only if `MERGE=true`, include `--debug` only if `DEBUG=true`.

The implementing agent will execute `render-skill-md.sh`, run validation checks, commit, review, bump the version, and create (and optionally merge) the PR.
