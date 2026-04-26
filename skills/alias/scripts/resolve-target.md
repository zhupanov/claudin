# resolve-target.sh — Contract

Resolves the target directory for a new alias skill (the file path under which `/alias` should write the generated `SKILL.md`). Owned by `skills/alias/SKILL.md` Step 2.

## CLI

```
resolve-target.sh --alias-name <name> [--private]
```

- `--alias-name <name>` (required): the alias being created. Validated against `^[a-z][a-z0-9-]*$` as a defense-in-depth check (SKILL.md Step 2 Check 1 already validates, but the helper is a public surface and keeps its own gate).
- `--private` (optional flag, no value): force the dev-only `.claude/skills/<name>/` target even when running inside a Claude plugin source repo. In non-plugin repos this flag is a no-op (the default is already `.claude/skills/`).

## Stdout schema (machine-readable)

Exactly three `KEY=VALUE` lines, in this order, on success:

```
REPO_ROOT=<absolute path to git repo root>
PLUGIN_REPO=true|false
TARGET_DIR=<absolute path>
```

Stdout MUST stay machine-stable. No additional lines, no decorative output. All diagnostics go to stderr.

### Caller parsing requirement (NON-EVAL)

Callers MUST parse this stdout with a non-`eval` line-by-line loop and an explicit allowlist of keys. The recommended pattern:

```bash
while IFS='=' read -r key val; do
  case "$key" in
    REPO_ROOT|PLUGIN_REPO|TARGET_DIR) declare "$key=$val" ;;
  esac
done < <("${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/resolve-target.sh" --alias-name "$NAME" $([ "$alias_private" = true ] && echo --private))
```

Do NOT use `eval "$(resolve-target.sh ...)"` — `eval` of a path that contains shell metacharacters (spaces, `$(...)`, backticks) introduces shell injection risk if the script's stdout contract ever drifts. The allowlist case-statement is the safe parsing primitive used here.

## Plugin-repo detection (two-file predicate)

`PLUGIN_REPO=true` iff BOTH files exist at `$REPO_ROOT`:

1. `.claude-plugin/plugin.json`
2. `skills/implement/SKILL.md`

This matches the predicate at `skills/create-skill/scripts/validate-args.sh:133`. The two-file rule guards against routing arbitrary Claude plugin repos (which may contain only `plugin.json`) to the larch `skills/<n>/` tree — only the larch plugin source repo, or a structurally-identical fork, gets the public-skill routing.

## Fail-closed semantics

- `git rev-parse --show-toplevel` failure (e.g., not in a git repo, git binary missing): exit 1 with `ERROR: not in a git repository` on stderr. Do NOT fall back to `$PWD` — `$PWD`-rooted detection would route to a different path than callers expecting git-toplevel semantics, creating silent divergence between Step 2 (this helper) and any caller that re-derives a root.
- Missing or invalid `--alias-name`: exit 1 with usage error on stderr.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success — three KEY=VALUE lines on stdout |
| 1 | Usage error OR git rev-parse failure (fail-closed) |

## Edit-in-sync rules

This script is the **single source of truth** for `(plugin-detect, --private) → TARGET_DIR` resolution. The values it emits are threaded through `skills/alias/SKILL.md` Steps 2 (collision check), 3 (`/implement` recipe `mkdir -p` + redirect path + announce line), and 4 (verify-skill-called.sh `--sentinel-file` argument). Any change to the stdout schema or the plugin-detect predicate MUST be mirrored in:

- `skills/alias/SKILL.md` Step 2 (parser), Step 3 (recipe + announce), Step 4 (sentinel)
- `scripts/test-alias-target-resolution.sh` (test harness — six cases A-F)
- `scripts/test-alias-structure.sh` (structural pin on SKILL.md $TARGET_DIR threading)

## Test harness

`scripts/test-alias-target-resolution.sh` covers six cases:

| Case | git repo? | `.claude-plugin/plugin.json`? | `skills/implement/SKILL.md`? | `--private`? | Expected `PLUGIN_REPO` | Expected `TARGET_DIR` |
|------|-----------|-------------------------------|------------------------------|--------------|------------------------|------------------------|
| A | yes | yes | yes | no | `true` | `$REPO_ROOT/skills/<n>` |
| B | yes | yes | yes | yes | `true` | `$REPO_ROOT/.claude/skills/<n>` |
| C | yes | no | no | no | `false` | `$REPO_ROOT/.claude/skills/<n>` |
| D | yes | no | no | yes | `false` | `$REPO_ROOT/.claude/skills/<n>` |
| E | no | — | — | — | (exit 1) | (no stdout — error to stderr) |
| F | yes | yes | no | no | `false` | `$REPO_ROOT/.claude/skills/<n>` |

Cases A-D are the core 2×2 (plugin-detect × `--private`). Case E exercises fail-closed git-rev-parse. Case F exercises the two-file predicate's strict-AND semantics (only `.claude-plugin/plugin.json` present, no `skills/implement/SKILL.md` → `PLUGIN_REPO=false`).
