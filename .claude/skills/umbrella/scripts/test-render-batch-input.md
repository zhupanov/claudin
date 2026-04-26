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
4. `single entry` — valid JSON, only 1 piece → expect existing `ERROR=pieces.json must contain at least 2 entries` path preserved.
5. `valid 2-piece baseline` — happy path → expect exit 0 + `BATCH_INPUT_FILE=` and `PIECES_TOTAL=2` on stdout.

**Exit codes**: 0 if all cases pass; 1 on first failed assertion (cases continue but the harness exits non-zero at the end).

**Test isolation**: uses `mktemp -d` for per-run temp directory; `trap 'rm -rf "$TMP"' EXIT` cleans up.

**Edit-in-sync rules**: any change to `render-batch-input.sh`'s malformed-JSON guard (the `JQ_PARSE_ERR` block at line 32) MUST keep the `ERROR=invalid pieces.json:` literal and the exit-1 contract — both pinned by this harness. Any change to the existing `pieces.json must contain at least 2 entries` error path must keep that literal too. If the contract changes (different stable grammar, different exit code), update both this harness AND `render-batch-input.md`'s Test coverage section in the same PR.

**Wiring**: invoked from `Makefile` via the `test-umbrella-render-batch-input` target, included in the `test-harnesses` aggregate target so `make lint` runs it on every PR (parallel to `test-umbrella-helpers`, `test-umbrella-parse-args`, `test-umbrella-emit-output-contract`).

**Out of scope**: the per-entry validation block (lines 38–60 — `title`, `body`, `depends_on` shape) is not exercised here; it's straightforward jq-driven structural validation already covered by integration via SKILL.md end-to-end runs.
