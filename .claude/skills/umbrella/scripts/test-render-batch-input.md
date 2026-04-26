# test-render-batch-input.sh — sibling contract

**Purpose**: regression harness pinning the malformed-`pieces.json` gatekeeper contract of `render-batch-input.sh`. Verifies that an unparseable `pieces.json` surfaces as the documented stable `ERROR=invalid pieces.json: <reason>` stderr line + exit 1, instead of leaking jq's raw parse error and propagating jq's exit code.

**Why pinned**: the umbrella skill writes `pieces.json` from untrusted LLM output. `render-batch-input.sh` is the boundary that normalizes failures into a stable grammar consumed by SKILL.md Step 3B.1's structured error handling. A regression here re-opens issue #646 — operators see raw `jq:` error lines and unstable exit codes at the LLM-output boundary.

**CLI**: no flags. Run manually:

```bash
bash .claude/skills/umbrella/scripts/test-render-batch-input.sh
```

**Cases**:

1. `unclosed array` — malformed JSON (unfinished bracket) → expect exit 1 + `ERROR=invalid pieces.json:` line.
2. `trailing comma` — malformed JSON (invalid token) → same expectation.
3. `garbage payload` — wholly unparseable text → same expectation.
4. `top-level object` — valid JSON whose top level is an object with ≥2 keys → expect the type-assert guard fires before the per-entry loop crashes; exit 1 + `ERROR=invalid pieces.json: top-level value must be a JSON array, got object`.
5. `top-level string` — valid JSON whose top level is a string → same type-assert path; got `string`.
6. `single entry` — valid JSON array with only 1 piece → expect existing `ERROR=pieces.json must contain at least 2 entries` path preserved.
7. `valid 2-piece baseline` — happy path → expect exit 0 + `BATCH_INPUT_FILE=` and `PIECES_TOTAL=2` on stdout.

**Exit codes**: runs all cases unconditionally; final exit code is 0 if every case passed, 1 if any case failed (per-case PASS/FAIL counters drive the final `[ "$FAIL" -eq 0 ]` exit assertion).

**Test isolation**: uses `mktemp -d` for per-run temp directory; `trap 'rm -rf "$TMP"' EXIT` cleans up.

**Edit-in-sync rules**: any change to `render-batch-input.sh`'s malformed-JSON guard (the `JQ_PARSE_ERR=...` capture block plus the type-assert that follows it, located in the "Validate JSON shape and count" section) MUST keep both the `ERROR=invalid pieces.json:` literal prefix and the exit-1 contract — both pinned by this harness. Any change to the existing `pieces.json must contain at least 2 entries` error path must keep that literal too. If the contract changes (different stable grammar, different exit code), update both this harness AND `render-batch-input.md`'s Test coverage section in the same PR.

**Wiring**: invoked from `Makefile` via the `test-umbrella-render-batch-input` target, included in the `test-harnesses` aggregate target so `make lint` runs it on every PR (parallel to `test-umbrella-helpers`, `test-umbrella-parse-args`, `test-umbrella-emit-output-contract`).

**Out of scope**: the per-entry validation `for` loop (`title`, `body`, `depends_on` shape) is not exercised here; it's straightforward jq-driven structural validation already covered by integration via SKILL.md end-to-end runs.
