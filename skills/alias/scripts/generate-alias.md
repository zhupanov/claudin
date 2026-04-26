# generate-alias.sh — Contract

Renders the complete `SKILL.md` content for a new alias skill. Owned by `skills/alias/SKILL.md` Step 3 (the `/implement` feature description embeds an invocation of this script).

## CLI

```
generate-alias.sh --name <alias-name> --target <target-skill> --flags "<preset-flags>" --version <version>
```

| Flag | Required? | Meaning |
|------|-----------|---------|
| `--name <alias-name>` | yes | The slash-command name of the new alias (e.g., `i`, `f`). Lowercase + hyphens; matches `^[a-z][a-z0-9-]*$` (validated at the SKILL.md call site, not here). |
| `--target <target-skill>` | yes | The skill the alias forwards to (e.g., `implement`, `fix-issue`). No leading slash. |
| `--flags "<preset-flags>"` | no | Preset flags to forward to the target. Empty string is valid (pure rename shortcut). May contain multiple flags separated by spaces (e.g., `"--merge --auto"`). The string is YAML-escaped and inlined into the rendered description. |
| `--version <version>` | no | Plugin semver string for the footer (e.g., `2.1.4`). Omit or pass empty when `jq` cannot read `plugin.json` — the footer simply omits the `vX.Y.Z` suffix. |

## Output

Stdout: the complete `SKILL.md` content for the alias skill, ready to redirect into `<TARGET_DIR>/SKILL.md`. Includes:

- YAML frontmatter (`name`, `description`, `argument-hint`, `allowed-tools: Skill`).
- Auto-generated body explaining how the alias forwards (Skill-tool invocation with bare-name fallback).
- Version footer.

The output is path-style-agnostic — it does NOT contain `${CLAUDE_PLUGIN_ROOT}/...` or `$PWD/...` references, because the body only invokes the Skill tool with the target skill name (bare name first, then `larch:<target>` fallback). This means the same generator output is correct for both plugin-skill (`skills/<n>/SKILL.md`) and dev-only (`.claude/skills/<n>/SKILL.md`) targets — the routing decision is owned by the parent `/alias` skill via `resolve-target.sh`, not by this generator.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success; `SKILL.md` content on stdout |
| 1 | Invalid args (missing `--name` or `--target`, or unknown flag) |

## Edit-in-sync rules

When modifying `generate-alias.sh`:

1. Update this contract doc to reflect the new CLI / output shape.
2. Update `skills/alias/SKILL.md` Step 3 if the recipe must change.
3. Run `bash scripts/test-alias-target-resolution.sh` (helper-script harness — does not exercise this generator directly, but verifies the upstream resolver contract this generator depends on).
4. Add a regression harness for this generator if its CLI grammar changes materially. Today the generator has no dedicated harness; the AGENTS.md "Per-script contracts live beside the script" rule is satisfied by this contract doc.

## agent-lint.toml registration

This sibling `.md` is registered in `agent-lint.toml`'s `exclude` block under the skill-local-sibling pattern (co-located contract docs not cited from SKILL.md by design — contributors discover them by editing the sibling `.sh`).
