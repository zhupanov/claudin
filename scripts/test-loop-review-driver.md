# test-loop-review-driver.sh contract

**Purpose**: Tier-1 structural regression harness for `skills/loop-review/scripts/driver.sh`. Companion to `test-loop-review-skill-md.sh` (which pins SKILL.md contract tokens).

**Wired into**: `make lint` via the `test-loop-review` target.

**Tier-1 vs Tier-2**: this script is Tier-1 (structural assertions only — file existence, contract-token grep, function definition presence). Tier-2 stub-shim integration tests using `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` are documented in `skills/loop-review/scripts/driver.md` and tracked as a focused follow-up; they require fixture stubs that emit canned partition output + canned per-slice `/review` output, which is more involved than the current PR's scope.

## Assertions

| ID | Concern |
|----|---------|
| A | driver.sh exists, is executable, has `set -euo pipefail` |
| B | Derives `CLAUDE_PLUGIN_ROOT` via three-up-from-script pattern (`cd .../../..`) |
| C | Has `cleanup_on_exit` trap on EXIT |
| D | Has `/tmp/`+`/private/tmp/` prefix guard on `LOOP_TMPDIR` |
| E | Has `..` path-component guard on `LOOP_TMPDIR` |
| F | Defines both `invoke_claude_p_freeform` AND `invoke_claude_p_skill` helpers |
| G | Both invoke helpers preserve FINDING_7 (`--plugin-dir`), FINDING_9 (STDIN delivery), FINDING_10 (stderr sidecar) contracts |
| H | Has `parse_slice_kv` awk-scoped to lines AFTER `### slice-result` header |
| I | Per-slice invocation uses `--slice-file` (file-based handoff, bypasses argv shell-quoting) |
| J | References `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` for Tier-2 test override |

## Edit-in-sync rules

- When editing `skills/loop-review/scripts/driver.sh`, run this harness to confirm contract tokens stay intact. Update this file in the same PR if assertion semantics change.
- The FINDING_7/9/10 contract tokens (`--plugin-dir "$CLAUDE_PLUGIN_ROOT"`, `< "$prompt_file"`, `2> "$stderr_file"`) are byte-pinned. Renaming the variables in driver.sh requires updating the assertions here.
- The `### slice-result` header is the contract token between driver.sh's `parse_slice_kv` and `/review`'s slice-mode KV footer (skills/review/SKILL.md Step 4d). All three locations must stay in sync.
