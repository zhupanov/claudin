# test-loop-fix-issue-driver.sh contract

**Purpose**: Tier-1 structural regression harness for `skills/loop-fix-issue/scripts/driver.sh`. Companion to `test-loop-fix-issue-skill-md.sh` (which pins SKILL.md contract tokens).

**Wired into**: `make lint` (via the `test-harnesses` aggregate) and the explicit `test-loop-fix-issue-driver` target.

**Tier-1 vs Tier-2**: this script is Tier-1 (structural assertions only — file existence, contract-token grep, function definition presence). Tier-2 stub-shim integration tests using `LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE` are documented in `skills/loop-fix-issue/scripts/driver.md` as future work; they would require fixture stubs that emit canned `/fix-issue` stdout, which is more involved than the current PR's scope.

## Assertions

| ID | Concern |
|----|---------|
| A | driver.sh exists, is executable, has `set -euo pipefail` |
| B | Derives `CLAUDE_PLUGIN_ROOT` via three-up-from-script pattern (`cd .../../..`). Uses fixed-string match to tolerate the surrounding `if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]` guard |
| C | Has `cleanup_on_exit` trap on EXIT |
| D | Has `/tmp/`+`/private/tmp/` prefix guard on `LOOP_TMPDIR` (matches the `if [[ ]]` form at driver.sh:212, NOT the case-arm pattern from loop-review's driver.sh) |
| E | Has `..` path-component guard on `LOOP_TMPDIR` |
| F | Defines `invoke_claude_p_skill` helper. (Only one helper — `invoke_claude_p_freeform` is loop-review-specific.) |
| G | `invoke_claude_p_skill` preserves FINDING_7 (`--plugin-dir`), FINDING_9 (STDIN delivery), FINDING_10 (stderr sidecar) contracts |
| H | `SETUP_SENTINEL` is assigned the literal `find & lock — found and locked` on a single live line (not just substrings in header comments) |
| I | All four Step-0 sub-sentinel literals appear: `0: find & lock — no approved issues found`, `0: find & lock — error:`, `0: find & lock — lock failed`, plus the defensive fallback `no recognized Step 0 literal` |
| J | Exactly four `LOOP_PRESERVE_TMPDIR="true"` assignments (matching the four documented abnormal-exit paths) AND default `LOOP_PRESERVE_TMPDIR="false"` initialization is preserved |
| K | References `LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE` for Tier-2 test override |
| L | Per-iteration prompt construction uses `printf '/fix-issue%s\n'` (anchored on the live printf line, NOT on bare `/fix-issue` token which appears extensively in comments) and writes to `fix-issue-prompt.txt` |

## Edit-in-sync rules

- When editing `skills/loop-fix-issue/scripts/driver.sh`, run this harness to confirm contract tokens stay intact. Update this file in the same PR if assertion semantics change.
- The FINDING_7/9/10 contract tokens (`--plugin-dir "$CLAUDE_PLUGIN_ROOT"`, `< "$prompt_file"`, `2> "$stderr_file"`) are byte-pinned. Renaming the variables in driver.sh requires updating the assertions here.
- The Step-0 sub-sentinel literals (assertion I) are the contract tokens between driver.sh's termination dispatch and `/fix-issue` SKILL.md's Step 0 stdout. All three locations (`/fix-issue` SKILL.md, this driver.sh, this harness) must stay in sync.
- The `SETUP_SENTINEL` assignment line (assertion H) is anchored on the live executable form `^SETUP_SENTINEL='find & lock — found and locked'`. The same prose appears in header comments at driver.sh:27 and :231 — assertion H must NOT degrade to a substring match that those comments could falsely satisfy.
- The four `LOOP_PRESERVE_TMPDIR="true"` assignments (assertion J) correspond to four documented abnormal-exit paths in `skills/loop-fix-issue/scripts/driver.md`. If a fifth path is added or one is removed, update both driver.md and the expected count in this harness.
- The per-iteration prompt-construction assertion L pairs the live `printf '/fix-issue%s\n'` line with the `fix-issue-prompt.txt` filename to anchor on executable code, not docs prose. The token `/fix-issue` appears extensively in driver.sh comments; do NOT degrade L to a bare `/fix-issue` substring match.
