# test-render-findings-batch.sh — Contract

**Purpose**: offline regression harness for `render-findings-batch.sh`. Feeds canned final-report fixtures to the helper, asserts exit code + `COUNT=` output, and round-trips the emitted sidecar through `skills/issue/scripts/parse-input.sh` to verify `ITEMS_TOTAL` matches and no `MALFORMED` items appear.

**Wired into**: `make lint` via the `test-render-findings-batch` target. The Makefile follows the `test-run-research-planner` template — three locations updated: `.PHONY` declaration, `test-harnesses` prerequisite chain, and the recipe itself.

## Cross-skill dependency (intentional)

This harness depends on `skills/issue/scripts/parse-input.sh` being present and executable. The dependency is the integration contract for the sidecar-as-input flow: research emits the sidecar; `/issue` validates the grammar. Future changes to `parse-input.sh`'s generic-mode handling (line 393's `^\#\#\#[[:space:]]+(.+)$` regex, the OOS field branches, blank-line preservation) require re-running this harness even when only `skills/issue/` is edited. The reverse coupling is documented in `skills/issue/scripts/parse-input.md`.

## Fixtures

12 cases:

1. **Numbered list** — three findings; round-trip ITEMS_TOTAL=3.
2. **Bulleted list** — two findings; round-trip ITEMS_TOTAL=2.
3. **Paragraph-per-item** — two paragraph-shape findings; round-trip ITEMS_TOTAL=2.
4. **Empty Findings Summary** — exit 3, COUNT=0, empty sidecar.
5. **Missing Findings Summary** — exit 3, COUNT=0, empty sidecar (different stderr warning).
6. **Planner-mode nested `#### Subquestion 1`** — sub-headings flush in-progress items but are NOT emitted as items themselves; numbered findings under each subquestion are extracted normally.
7. **Fenced code with `### Foo` inside** — fence-aware section extraction does NOT terminate the section on the in-fence pseudo-header.
8. **Body-line `### Bad Header` at column 0** — escaped to `\### Bad Header` so `parse-input.sh:393`'s regex does not split items downstream.
9. **Empty-title fallback** — first sentence is all `!` characters; title strips to empty; helper emits `Finding 1` fallback so `parse-input.sh:161-163` does not silently drop the item.
10. **Quick-disclaimer** — same fixture as #1 but with `--quick-disclaimer` set; assertion: each item body contains the disclaimer literal.
11. **Special characters** — backticks, dollars, asterisks, single/double quotes preserved verbatim in body.
12. **Multi-line bulleted continuation** — bullet item with a continuation line stays one item.

## Assertions per case

- Exit code matches expectation.
- `COUNT=<N>` on stdout matches expected count.
- When `expected_count > 0`: `parse-input.sh` round-trip asserts `ITEMS_TOTAL=<expected_count>` and no `ITEM_<i>_MALFORMED=true` lines.
- When `--quick-disclaimer` is set: each item body contains the disclaimer literal at least once (`grep -cF` count >= expected_count).

## Edit-in-sync rules

- **Helper contract changes** (extraction terminator list, heuristic ladder, body-line escape, exit-code vocabulary, stdout schema) → update fixtures and assertions here AND `render-findings-batch.md`.
- **`parse-input.sh` generic-mode changes** → re-run this harness; if behavior shifts, update fixtures (and add/update fixtures pinning the new behavior).
- **`make lint` wiring** — keep the three Makefile locations in sync (`.PHONY` + `test-harnesses` prereq + recipe). The structural pin in `scripts/test-research-structure.sh` (`test-render-findings-batch` referenced in Makefile) catches partial edits.

## Exit code

- `0` when all cases pass; final stdout line is `PASS: test-render-findings-batch.sh — all <N> cases passed`.
- `1` on any case failure; per-case `FAIL [...]` diagnostic on stderr; final stderr summary `FAIL: <K> of <N> cases failed`.
