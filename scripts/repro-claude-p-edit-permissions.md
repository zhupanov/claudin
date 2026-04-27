# scripts/repro-claude-p-edit-permissions.sh — contract

Sibling per-script-contract doc per `AGENTS.md`. Edit this file in lockstep with `repro-claude-p-edit-permissions.sh` whenever the script's behavior changes.

## Purpose

Isolated reproducer for the `claude -p` Edit-permission stall first observed in #566. Validates the kernel fix (#585) and the related settings audit independently of the full `/loop-improve-skill` pipeline.

The script invokes a single `claude -p --plugin-dir "$REPO_ROOT"` subprocess against the project's permission stack (`.claude/settings.json` + `.claude/settings.local.json` + `hooks/hooks.json` PreToolUse hooks), asks the model to perform a trivial edit on a tracked file under `skills/**`, and classifies the outcome by combining a pinned stall-regex grep on combined stdout+stderr with a `git diff` ground-truth check on the edit target.

Opt-in operator instrumentation. NOT a CI gate. Depends on a real authenticated `claude` binary, costs API tokens, and is timing-sensitive. Same shape as `scripts/eval-research.sh` and `scripts/test-loop-improve-skill-halt-rate.sh`.

## Invariants

The script preserves these invariants under every normal exit path (success, failure, SIGINT, SIGTERM):

- `.claude/settings.json` is byte-identical to its pre-run state.
- `.claude/settings.local.json` (if present) is byte-identical to its pre-run state.
- `skills/umbrella/SKILL.md` is byte-identical to its pre-run state.
- No staging files (`*.repro.bak`, `*.repro.new`) remain on disk.
- The mktemp scratch directory is removed.

`kill -9` of the script SKIPS the EXIT/INT/TERM trap and is unrecoverable in the same way every other trap-based bash script in this repo is unrecoverable. Manual recovery: see "Manual recovery" section below.

Variants A and B are read-only against the on-disk settings: they do NOT mutate `.claude/settings.json`. Variants C and D mutate `.claude/settings.json` and the trap restores it.

## Variant matrix

| Variant | KERNEL_FLAGS                              | settings.json operation | settings.local.json | EXPECTED              |
| ------- | ----------------------------------------- | ----------------------- | ------------------- | --------------------- |
| A       | (empty)                                   | none                    | staged aside        | `stall`               |
| B       | `--permission-mode bypassPermissions`     | none                    | unchanged           | `edit_completed`      |
| C       | (empty)                                   | replace via `jq`        | staged aside        | `observational_only`  |
| D       | `--permission-mode bypassPermissions`     | rename aside            | staged aside        | `edit_completed`      |

Variant C's replacement settings JSON is built via `jq -n --arg p "$REPO_ROOT" '{permissions:{allow:["Read(\($p)/skills/**)","Edit(\($p)/skills/**)","Write(\($p)/skills/**)"]}}'` and atomically `mv`'d from `.claude/settings.json.repro.new` (same directory as the target, guaranteeing same-filesystem rename atomicity).

Variant A reproduces the original #566 incident shape (current settings, no kernel flag) — meaningful even when the live `.claude/settings.json` has `defaultMode: bypassPermissions` because #566 reproduced on that exact shape. The script emits a preflight `**⚠ WARNING**` when this combination is detected so the operator interprets the result with context.

`settings.local.json` staging covers an active second permission surface in this repo. Without it, A/C/D would not be isolated.

## Stall-signature parsing rule

Result classification is a 4-way switch evaluated on the captured stdout file AND stderr file (concatenated):

```
if combined output contains the literal substring "Edit tool is repeatedly returning":
  RESULT=stall
elif `git diff -- skills/umbrella/SKILL.md` is non-empty:
  RESULT=edit_completed
elif timeout exit code is 124 or 137:
  RESULT=timeout
else:
  RESULT=inconclusive
```

The stall substring `Edit tool is repeatedly returning` is **pinned**. It is the canonical phrasing observed in #566. If the upstream Claude CLI reworks the stall message, the substring drifts and the script reports `RESULT=inconclusive` for genuine stalls. Update the substring in lockstep with this `.md` whenever the upstream phrasing changes — the breakage signal is a Variant A run that exits non-zero with `RESULT=inconclusive` and no `Edit tool` substring on stdout/stderr.

The `git diff` ground-truth check guards against the model simply ignoring the prompt: a clean diff means no edit happened, regardless of any stall phrase, so RESULT collapses to `inconclusive` rather than misreporting.

Combined with the timeout exit code (124 = SIGTERM, 137 = SIGKILL after `--kill-after`), the classifier covers the four observable outcomes.

## Trap-based cleanup contract

A single `cleanup()` function is registered on `EXIT INT TERM`. Restoration order is bottom-up by setup order:

1. `mv` `$SETTINGS_BACKUP` → `.claude/settings.json` (Variant C only).
2. `mv` `$SETTINGS_RENAMED_AWAY` → `.claude/settings.json` (Variant D only).
3. `mv` `$LOCAL_SETTINGS_RENAMED_AWAY` → `.claude/settings.local.json` (variants A/C/D).
4. `git checkout -- skills/umbrella/SKILL.md 2>/dev/null || true` (no-op if clean or absent).
5. `rm -rf "$REPRO_WORKDIR"`.

All four cleanup variables are initialized to empty strings BEFORE the trap is registered so that `set -u` does not error inside the trap. Each step is idempotent and tolerant of partial-stage interrupts: if a setup phase failed before assigning a variable, the corresponding cleanup step is skipped.

`git checkout --` is piped to `2>/dev/null || true` so a missing-file edge case does not abort cleanup before the `rm -rf` step.

## `--smoke-test` mode

`bash scripts/repro-claude-p-edit-permissions.sh --variant A --smoke-test` (or `B`/`C`/`D`) runs `parse_args`, `preflight`, `register_cleanup_trap`, `stage_variant`, then explicitly `exit 0` so the cleanup trap fires and restores all on-disk state.

Smoke-test exercises:
- Argument parsing.
- All preflight checks (binaries: claude/git/jq/timeout, clean tree, defaultMode warning).
- Settings staging + restoration round-trip for the chosen variant.
- Trap registration.

It does NOT invoke `claude -p`. Total runtime: <1 second. Used as a CI-friendly structural regression check (no API cost, no `claude` dependency at runtime — but `claude` is still required on PATH because preflight checks for it; if `claude` is absent, smoke-test exits 3 with `PROBE_STATUS=skipped_no_claude`).

## Hooks remain active

This repo's plugin-installed PreToolUse hooks (via `hooks/hooks.json` → `scripts/block-submodule-edit.sh`) fire on every `Edit`/`Write` tool use, alongside the permission engine. Observed behavior is therefore "permission manager + hook policy" combined. `block-submodule-edit.sh` does not block `skills/umbrella/SKILL.md` (not in a submodule), so the hook layer is permissive for this target.

## Path resolution

The script `cd`s to `git rev-parse --show-toplevel` and uses `pwd -P` to resolve symlinks before recording `$REPO_ROOT`. The path-qualified Variant C allow rule is built from this resolved path. In symlinked-checkout edge cases where the developer's clone uses a symlinked path that `claude` does not resolve identically, the variant may misbehave — run from a non-symlinked clone for reliable results.

## Exit codes

| Exit | Meaning |
|------|---------|
| 0    | Variant's expected outcome was observed (or Variant C — observational_only — exits 0 unconditionally). |
| 1    | Observed RESULT diverged from EXPECTED for Variant A/B/D. |
| 2    | Preflight failure: missing binary, dirty working tree, bad argument, edit target absent or untracked, or `.claude/settings.json` absent when running Variants C or D (which mutate it). |
| 3    | `PROBE_STATUS=skipped_no_claude` — `claude` binary not on PATH. Treat like a no-op. |

## Manual recovery (`kill -9` aftermath)

If the trap was skipped, manually restore:

```bash
# Settings (whichever applies):
mv .claude/settings.json.repro.bak .claude/settings.json   # variant C or D
mv .claude/settings.local.json.repro.bak .claude/settings.local.json  # if present
# Edit target:
git checkout -- skills/umbrella/SKILL.md
# Staging tmp file (variant C, mid-staging interrupt):
rm -f .claude/settings.json.repro.new
```

## Test harness

This script's structural correctness is exercised by its own `--smoke-test` mode. There is no separate `test-repro-claude-p-edit-permissions.sh` harness — the smoke-test IS the offline regression harness. `make lint` is unaffected (the script is excluded from `agent-lint --pedantic` via `agent-lint.toml` — same Makefile-only / opt-in pattern as `eval-research.sh` and `test-loop-improve-skill-halt-rate.sh`).

## Edit-in-sync rules

When changing this script:

- Update the variant matrix table here if `EXPECTED` values, `KERNEL_FLAGS`, or `SETTINGS_OP` change.
- Update the stall-signature substring in BOTH this file's "Stall-signature parsing rule" section AND the script's `STALL_SIGNATURE` constant.
- Update the manual-recovery commands if staging-file paths change.
- Update the `agent-lint.toml` exclusion entry if the script is renamed.

## References

- #566 — original stall incident.
- #585 — kernel fix that this reproducer validates.
- #587 — this reproducer.
- `scripts/eval-research.sh` and `scripts/test-loop-improve-skill-halt-rate.sh` — pattern templates for opt-in `claude -p` operator harnesses.
- `AGENTS.md` "Per-script contracts live beside the script" — the rule that mandates this `.md` exist beside the script.
