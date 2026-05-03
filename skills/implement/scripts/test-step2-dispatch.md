# test-step2-dispatch.sh

**Purpose**: Offline regression harness for `skills/implement/scripts/step2-implement.sh` covering the dispatcher branches that do not require spawning Codex. Runs in <1s with no external dependencies (no `codex` binary, no network).

**Coverage** (10 assertions):
1. `--codex-available false` emits `STATUS=claude_fallback` with no other KV keys, and writes no baseline files (the claude_fallback branch must short-circuit before any plugin / git resolution).
2. Missing `--codex-available` exits with code 2.
3. Bad `--codex-available` enum value exits with code 2.
4. Bad `--tmpdir` (not a directory) exits with code 2.
5. Resume cap: pre-seeding `codex-resume-count.txt` to 5 and invoking with `--answers` produces `STATUS=bailed REASON=qa-loop-exceeded` before any Codex spawn.
6. `--answers` pointing at a non-existent file exits with code 2.
7. (paired with #1) the claude_fallback branch does not leak a baseline file into `$TMPDIR_ARG`.
8. Corrupt resume counter (non-numeric) → `STATUS=bailed REASON=manifest-schema-invalid`. Defense-in-depth against tmpdir tampering / partial-write corruption.
9. `--codex-available true` invoked with cwd outside any git working tree exits with code 2 and stderr containing `must be invoked from within a git working tree`. Pins the cache-deploy regression fix (REPO_ROOT now derived from `git rev-parse --show-toplevel`, not `SCRIPT_DIR/../../..`).
10. (paired with #9) the non-git-tree exit-2 path does not leak a baseline file into `$TMPDIR_ARG` (validation must happen before any state mutation).

All `--codex-available true` invocations are run with cwd pinned to `$REPO_ROOT` so the dispatcher's git resolution targets the harness's own git tree (matches the production caller's contract — the orchestrator always invokes the dispatcher from the consumer-repo cwd).

**Out of scope** (no automated coverage today — manual / end-to-end testing only; an offline stub-Codex harness is a known gap):
- Manifest schema validation (per-status required-key checks via `jq -e`).
- `git diff --name-only $BASELINE..HEAD` set-equality cross-check.
- Path normalization (`..` / leading `/` / `.claude-plugin/plugin.json` / submodule paths).
- Sanitization via `scripts/redact-secrets.sh`.
- Single-retry on transient launcher failure with clean-state guard.
- `branch-changed` / `protected-path-modified` / `submodule-dirty` / `dirty-tree-after-codex` post-Codex checks.

**Invariants**:
- Tests run against the live `step2-implement.sh` in the repo (not a copy) so any edit to the dispatcher's argument parsing, fallback branching, or resume-cap logic is caught here.
- Tests pre-seed baseline files only for assertion 5 (the dispatcher must NOT touch the working tree, branch state, or git state in any other test path).
- Scratch directory is created via `mktemp -d` and removed via `trap` on exit; tests run in parallel-safe isolation.

**Call sites**:
- `make test-step2-dispatch` — Makefile target.
- `make test-harnesses` — included in the full pre-CI harness battery.
- `make lint` — runs both `lint-only` and `test-harnesses`.

**Edit-in-sync**:
- `skills/implement/scripts/step2-implement.sh` — any change to argument parsing, the claude_fallback branch, baseline-file handling, or the resume counter must be exercised here.
- `skills/implement/scripts/step2-implement.md` — sibling contract for the dispatcher; assertions in this harness should match invariants stated there.
- `scripts/test-implement-structure.sh` — assertion 19 verifies this harness path exists alongside the dispatcher (via the dispatcher-pin assertion); both should be added/removed together.

**Running locally**: `make test-step2-dispatch` or `bash skills/implement/scripts/test-step2-dispatch.sh`.
