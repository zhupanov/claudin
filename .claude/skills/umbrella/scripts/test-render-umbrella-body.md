# test-render-umbrella-body.sh — sibling contract

**Purpose**: runtime conformance harness for `render-umbrella-body.sh`. Closes #645 — the script previously emitted success KVs (`UMBRELLA_BODY_FILE=` / `UMBRELLA_TITLE_HINT=`) on stdout in some failure-case paths, masking failure as success in `/umbrella` Step 3B.3. After the fix, the script: (1) rejects non-writable `--tmpdir` upfront with the documented `ERROR=tmpdir not writable: <path>` stderr line; (2) writes the body via mktemp partial → `[ -s ]` verify → `mv` atomic rename, emitting success KVs only past the `mv` gate. This harness pins those invariants.

**Cases**:

1. **Unwritable tempdir** (`chmod 555` on a user-owned `mktemp -d` dir). Asserts: exit non-zero, stderr contains `ERROR=tmpdir not writable:`, stdout contains NEITHER `UMBRELLA_BODY_FILE=` NOR `UMBRELLA_TITLE_HINT=`.
2. **Happy path** on a writable tempdir with valid summary/children inputs. Asserts: exit 0, `$TMPDIR/umbrella-body.md` exists and is non-empty, stdout contains both success KVs, no leftover `umbrella-body.md.*` mktemp partial.
3. **`mv` failure** via PATH-injected fake `mv` that always exits 1. Asserts: exit non-zero, stderr contains `ERROR=failed to write umbrella body:`, stdout contains NEITHER success KV. This case exercises the new checked-write branch's `mv` guard. PATH-injection is used because BSD `mv` (macOS) and GNU `mv` differ on what makes a same-directory rename fail (e.g., dest-as-empty-dir succeeds on BSD by moving source inside, fails with EISDIR on GNU); mocking `mv` removes that platform divergence and isolates the test to the script's own error-handling logic.
3b. **Pre-existing dest as directory** — `mkdir -p $TMPDIR/umbrella-body.md`. Exercises the pre-rename `[ -e "$OUT" ] && [ ! -f "$OUT" ]` guard added in response to the BSD `mv source dir/` silent-nesting bug (same #645 failure-as-success class on a different surface — Codex caught this during code review). Asserts: exit non-zero, stderr `ERROR=failed to write umbrella body:`, no success KVs.
3c. **`mktemp` failure** via PATH-injected fake `mktemp` that always exits 1. Exercises the script's `mktemp ... || { ... }` guard. Asserts: exit non-zero, stderr `ERROR=failed to write umbrella body:`, no success KVs.
4. **Malformed children.tsv** (regression check on the pre-existing validation). Asserts: exit non-zero, stderr contains `ERROR=children.tsv malformed`.

**Pattern**: matches `test-umbrella-parse-args.sh` — `set -euo pipefail`, `mktemp -d` workspace, `trap 'chmod -R 755 "$TMP" 2>/dev/null || true; rm -rf "$TMP"' EXIT` (the `chmod 755` is required so `rm -rf` can recurse into the case-1 `chmod 555` directory), `set +e` / `set -e` around the subject invocation, exit-code + stdout/stderr substring assertions, "All N assertions passed" closer.

**Precondition**: must run as a non-root user. `chmod 555` does not deny `root`, so the unwritable-tmpdir case (Case 1) would falsely pass under `root`. CI runs as a non-root user by default; local dev should not invoke under `sudo`.

**Wiring**: `make lint` runs the harness via the `test-render-umbrella-body` Makefile target (parallel to `test-umbrella-emit-output-contract` / `test-umbrella-parse-args` / `test-umbrella-helpers`). Documented in `docs/linting.md`.

**Edit-in-sync rules**: changes to `render-umbrella-body.sh`'s stdout grammar, `ERROR=` taxonomy, or success/failure paths require updating this harness so its assertions stay aligned. Conversely, adding a new failure path to the script should add a corresponding case here. Sibling contract `render-umbrella-body.md` enumerates the canonical `ERROR=` taxonomy.

**Run manually**:

```bash
bash .claude/skills/umbrella/scripts/test-render-umbrella-body.sh
```

Exits `0` on success, `1` on the first failed assertion.
