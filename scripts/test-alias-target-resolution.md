# test-alias-target-resolution.sh — Contract

Test harness for `skills/alias/scripts/resolve-target.sh`. Exercises the script's plugin-detection and `--private` semantics across six cases plus an alias-name validation case.

## Purpose

Pin the behavior contract documented in `skills/alias/scripts/resolve-target.md` so future edits to `resolve-target.sh` cannot regress the matrix `(plugin-detect × --private × git-state)` without CI failing.

## Cases

| Case | git repo? | `.claude-plugin/plugin.json`? | `skills/implement/SKILL.md`? | `--private`? | Expected `PLUGIN_REPO` | Expected `TARGET_DIR` |
|------|-----------|-------------------------------|------------------------------|--------------|------------------------|------------------------|
| A | yes | yes | yes | no | `true` | `$REPO_ROOT/skills/<n>` |
| B | yes | yes | yes | yes | `true` | `$REPO_ROOT/.claude/skills/<n>` |
| C | yes | no | no | no | `false` | `$REPO_ROOT/.claude/skills/<n>` |
| D | yes | no | no | yes | `false` | `$REPO_ROOT/.claude/skills/<n>` |
| E | no | — | — | — | (exit 1, ERROR on stderr) | (no stdout) |
| F | yes | yes | no | no | `false` | `$REPO_ROOT/.claude/skills/<n>` |

Plus a defense-in-depth assertion: invalid `--alias-name` (`"Bad-Name"`) → exit 1 + `ERROR` on stderr.

Cases A-D are the core 2×2. Case E covers fail-closed git-rev-parse semantics. Case F covers the two-file predicate's strict-AND rule (mere presence of `.claude-plugin/plugin.json` does not flip `PLUGIN_REPO=true` — `skills/implement/SKILL.md` must also be present, matching `validate-args.sh:133`).

## Isolation

Each case runs in its own `mktemp -d` sub-directory with a fresh `git init`. The host repo's `.claude-plugin/plugin.json` and `skills/implement/SKILL.md` do NOT influence the test. Cleanup via `trap "rm -rf $TMPROOT" EXIT`.

`pwd -P` canonicalization is applied to expected `REPO_ROOT` / `TARGET_DIR` values so the script's `git rev-parse --show-toplevel` output (which canonicalizes `/private/var/...` symlinks on macOS) matches.

## Makefile wiring

Wired into the `test-harnesses` target via `make test-alias-target-resolution`. See `docs/linting.md` Makefile Targets table.

## agent-lint.toml registration

This script is referenced only by `Makefile` (not by any `SKILL.md`), so it is added to `agent-lint.toml`'s `exclude` block under the existing test-harness pattern. The sibling `test-alias-target-resolution.md` (this file) is similarly excluded under the skill-local-sibling-style block.

## Edit-in-sync rules

When modifying `skills/alias/scripts/resolve-target.sh`:

1. Update `skills/alias/scripts/resolve-target.md` (contract).
2. Update this test harness if the case matrix shifts (e.g., a new flag, a new return key).
3. Run the harness: `bash scripts/test-alias-target-resolution.sh`.
4. Run `/relevant-checks` to confirm `pre-commit` + `agent-lint` are green.
