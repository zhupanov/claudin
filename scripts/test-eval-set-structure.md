# test-eval-set-structure.sh — contract

## Purpose

`scripts/test-eval-set-structure.sh` is the offline structural regression harness for the `/research` evaluation set + harness landed by issue #419. It enforces the schema, category coverage, adversarial-entry count, baseline JSON shape, and harness self-test invariants documented in `scripts/eval-research.md`. The test runs cheaply (no API cost), exercises the harness's `--smoke-test` flag end-to-end, and never invokes `claude -p`.

It is a **standalone Makefile target**, not a `test-harnesses` prerequisite — the harness it tests (`scripts/eval-research.sh`) is opt-in operator instrumentation explicitly carved out from the CI lint path per the umbrella's "not a CI gate" constraint, so the structural test mirrors the same standalone shape for symmetry. Operators run it via `make test-eval-set-structure` when iterating on the catalog or harness.

## Assertions (in order)

1. `skills/research/references/eval-set.md` exists.
2. `eval-set.md` opens with the anchored `**Consumer**:` / `**Contract**:` / `**When to load**:` triplet in the first 20 lines (mirrors `scripts/test-research-structure.sh`'s stricter `/research`-local layering on top of the cross-skill check in `scripts/test-references-headers.sh`).
3. `eval-set.md` declares at least 20 entries via `### eval-<N>:` headings.
4. All five required categories appear at least once: `lookup`, `architecture`, `external-comparison`, `risk-assessment`, `feasibility`.
5. Every entry has all six required fields: `question`, `category`, `expected_provenance_count`, `expected_keywords`, `notes` (the `id` is in the heading itself; the field schema validation is line-anchored against `^- \*\*<name>\*\*:`).
5b. Every entry id matches `^[a-z0-9-]+$` (lowercase letters, digits, and hyphens only) and is unique across the eval set. Mirrors `validate_eval_set()` in `scripts/eval-research.sh` so duplicate or path-like ids are rejected at lint time, not just at smoke-test time. Path-like ids would otherwise escape `$WORK_DIR/$id` when a future operator hand-edits `eval-set.md` (closes #442).
6. At least two entries are flagged `ADVERSARIAL` in their `notes` line — the catalog's "test over-claiming" contract requires both a fictitious-mechanism question and a data-absence question.
7. `skills/research/references/eval-baseline.json` exists, parses as JSON (via `jq` when available, with a `grep` fallback), and contains the `version`, `scale`, and `entries` keys with `entries` typed as an array.
8. `scripts/eval-research.sh` contains the literal Anthropic-blog citation tag (`anthropic.com/engineering/built-multi-agent-research-system`) — pinned so a future edit cannot drop the source attribution silently.
9. `bash scripts/eval-research.sh --smoke-test` exits 0 — round-trip verification that the harness's own schema parser agrees with this test's assertions.

## Makefile wiring

<!-- markdownlint-disable MD010 -->
```makefile
test-eval-set-structure:
	bash scripts/test-eval-set-structure.sh
```
<!-- markdownlint-enable MD010 -->

(Recipe lines in a Makefile MUST begin with a literal tab; the example reproduces the actual file's bytes.)

`test-eval-set-structure` is added to the `.PHONY` declaration line but is NOT appended to `test-harnesses`. CI runs `make lint` which exercises `test-harnesses + lint-only`; this target is invoked manually by operators. Mirrors the `halt-rate-probe` / `smoke-dialectic` precedent.

## Edit-in-sync

| File | Relationship |
|------|-------------|
| `skills/research/references/eval-set.md` | Primary subject under test. Schema regressions here fail this harness. |
| `skills/research/references/eval-baseline.json` | Schema-only stub at PR-merge time; `entries: []`. This harness asserts the schema keys exist and parse, not that entries are populated. |
| `scripts/eval-research.sh` | Asserted to exist, exit 0 under `--smoke-test`, and contain the Anthropic-blog citation. Behavior changes that break the schema parser also break this harness via Check 9. |
| `scripts/eval-research.md` | Sibling contract for the runtime harness; documents the operational definitions this test enforces. |
| `Makefile` | Target wiring (standalone, NOT in `test-harnesses`). |
| `agent-lint.toml` | Excludes this script from dead-script checks (Makefile-only reference). |

## Reusable patterns adopted

- The `**Consumer**:` / `**Contract**:` / `**When to load**:` first-20-lines check copies the strictness layer from `scripts/test-research-structure.sh` Check 4. The cross-skill triplet check in `scripts/test-references-headers.sh` already enforces the looser any-line variant; this harness layers the stricter check just for the new file.
- The literal-pin pattern (Check 8 — Anthropic-blog citation) mirrors the byte-pin check in `scripts/test-research-structure.sh` Checks 5 and 6 (`RESEARCH_PROMPT` literal, reviewer XML wrapper tags).
- The `--smoke-test` round-trip (Check 9) mirrors how `scripts/test-loop-improve-skill-driver.sh` round-trips the driver under fixture data.

## When this harness is wrong

If the catalog or harness moves toward a fundamentally different schema (e.g., YAML frontmatter blocks instead of markdown-heading-with-bullets), this test must be rewritten in lockstep. The test's authority is structural, not stylistic — it does not enforce question quality, score thresholds, or content invariants beyond what `eval-set.md` declares about itself.
