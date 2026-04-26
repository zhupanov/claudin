# test-alias-structure.sh — Contract

Structural regression test for `skills/alias/SKILL.md`. Pins the prompt-side contract that target-dir resolution flows through a single `$TARGET_DIR` variable computed once at Step 2 by `resolve-target.sh` and threaded through Steps 2/3/4, never replaced by hardcoded `.claude/skills/<alias-name>` paths in any load-bearing site.

## Purpose

The plan's primary failure mode (#1) is silent drift between Step 2's resolved `$TARGET_DIR` and a hardcoded `.claude/skills/<alias-name>` path that survived in Step 3 (the `/implement` recipe) or Step 4 (the verify sentinel). A future edit could re-introduce such a hardcoded path in one site but not another, creating a path split where `/implement` writes one tree and `verify-skill-called.sh` checks a different tree. This harness catches that class of regression at CI time.

Companion to `scripts/test-alias-target-resolution.sh`: that harness tests the `resolve-target.sh` helper's behavior; this harness tests that `skills/alias/SKILL.md` actually USES the helper's output at all the right sites.

## Assertions

| ID | What |
|----|------|
| A | `resolve-target.sh` is referenced from SKILL.md (Step 2 invocation) |
| B | Step 1 documents `--private` as a parsed flag |
| C | Step 2 contains the canonical non-eval allowlist parser literal `REPO_ROOT\|PLUGIN_REPO\|TARGET_DIR` |
| D | Check 6 uses `test -e "$TARGET_DIR"` — and the old hardcoded `test -d ".claude/skills/<alias-name>"` is gone |
| E | `E_COLLISION` row interpolates `$TARGET_DIR` |
| F | Step 3 recipe uses `$TARGET_DIR` for both `mkdir` and the redirect path; old hardcoded paths gone |
| G | Step 3 announce line interpolates `$TARGET_DIR` |
| H | Step 4 sentinel uses `$TARGET_DIR/SKILL.md`; old `REPO_ROOT=$(git rev-parse ... \|\| pwd -P)` line is gone |
| I | NEVER list mentions `--private` (rule #5), TARGET_DIR threading (#6), and non-eval (#7) |
| J | Frontmatter `argument-hint` includes `[--private]` |
| K | Final structural sweep — load-bearing sites (D-neg, F-neg, H.2-neg) are checked above |

## Makefile wiring

Wired into the `test-harnesses` target via `make test-alias-structure`. See `docs/linting.md` Makefile Targets section.

## agent-lint.toml registration

Referenced only by `Makefile` (not from any `SKILL.md`). Listed in `agent-lint.toml`'s `exclude` block under the test-harness pattern.

## Edit-in-sync rules

When modifying `skills/alias/SKILL.md` Steps 2/3/4 or NEVER rules #5–#7:

1. Run this harness: `bash scripts/test-alias-structure.sh`.
2. Update assertion text here if structural literals shifted.
3. Run `bash scripts/test-alias-target-resolution.sh` to confirm the helper still meets its contract.
4. Run `/relevant-checks` to confirm `pre-commit` + `agent-lint` are green.
