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
7. `fractional depends_on` — valid JSON whose entry 2 has `depends_on:[1.5]` → expect the per-entry `bad_deps` predicate (the `(. != (. | floor))` clause added for #647) fires; exit 1 + `ERROR=pieces.json entry 2 has out-of-range depends_on values:` line. Pins the integer-only contract documented in `render-batch-input.md`.
8. `valid 2-piece baseline` — happy path → expect exit 0 + `BATCH_INPUT_FILE=` and `PIECES_TOTAL=2` on stdout.

**Exit codes**: runs all cases unconditionally; final exit code is 0 if every case passed, 1 if any case failed (per-case PASS/FAIL counters drive the final `[ "$FAIL" -eq 0 ]` exit assertion).

**Test isolation**: uses `mktemp -d` for per-run temp directory; `trap 'rm -rf "$TMP"' EXIT` cleans up.

**Edit-in-sync rules**: any change to `render-batch-input.sh`'s malformed-JSON guard (the `JQ_PARSE_ERR=...` capture block plus the type-assert that follows it, located in the "Validate JSON shape and count" section) MUST keep both the `ERROR=invalid pieces.json:` literal prefix and the exit-1 contract — both pinned by this harness. Any change to the existing `pieces.json must contain at least 2 entries` error path must keep that literal too. Any change to the per-entry `bad_deps` jq predicate that validates `depends_on` (the `map(select(...))` clause inside the per-entry `for` loop, currently rejecting non-numbers, non-integers via `(. != (. | floor))`, and out-of-range values) MUST keep the `ERROR=pieces.json entry <i> has out-of-range depends_on values:` literal prefix and the exit-1 contract — both pinned by case 7. If any of these contracts change (different stable grammar, different exit code), update both this harness AND `render-batch-input.md`'s Test coverage section in the same PR.

**Wiring**: invoked from `Makefile` via the `test-umbrella-render-batch-input` target, included in the `test-harnesses` aggregate target so `make lint` runs it on every PR (parallel to `test-umbrella-helpers`, `test-umbrella-parse-args`, `test-umbrella-emit-output-contract`).

**Out of scope**: the per-entry validation `for` loop's `title` and `body` non-empty checks remain covered by integration via SKILL.md end-to-end runs; they are not exercised at the script boundary here. The `depends_on` predicate's integer / non-fractional / out-of-range branch IS exercised at the script boundary by case 7.
