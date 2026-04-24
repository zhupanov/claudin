# test-quick-mode-docs-sync.sh

Cross-validation harness that asserts alignment between the normative `/implement --quick` contract in `skills/implement/SKILL.md` Step 5 and the public user-facing documentation in `README.md`, `docs/review-agents.md`, and `docs/workflow-lifecycle.md`. Closes #370.

## Purpose

Without this harness, drift between the canonical quick-mode contract and its three public mirrors is silent. The bug that triggered #370 — "simplified code review (1 Claude Code Reviewer subagent, 1 round)" persisting in the public docs long after SKILL.md evolved to "up to 7 rounds, Cursor → Codex → Claude fallback, no voting panel" — is exactly the class this harness prevents: a SKILL.md edit that does not propagate to the public mirrors, or a public-doc edit that re-introduces a contradiction with SKILL.md.

## Invariants enforced

### Target files

| Target | Positive anchors | Negative (stale-phrase) checks |
|--------|------------------|--------------------------------|
| `skills/implement/SKILL.md` | required | **exempted** (see audit below) |
| `README.md` | required | required |
| `docs/review-agents.md` | required | required |
| `docs/workflow-lifecycle.md` | required | required |

### Positive anchors (required in every target)

Each target file MUST contain all three markers:

| Marker | Casing | Rationale |
|--------|--------|-----------|
| `7 rounds` | case-sensitive `grep -F` | Pins the 7-round cap. SKILL.md uses lowercase "7 rounds" consistently. |
| `Cursor → Codex → Claude` | case-sensitive `grep -F`, UTF-8 U+2192 arrow | Pins the fallback chain order. |
| `no voting panel` | **case-insensitive** `grep -iF` | Semantic marker; tolerates legitimate sentence-case rewrites (e.g. "No voting panel"). |

### Negative checks (forbidden in public docs only)

Public docs (`README.md`, `docs/review-agents.md`, `docs/workflow-lifecycle.md`) MUST NOT contain any of these legacy stale phrases:

- `1 Claude Code Reviewer subagent, 1 round` — full stale README phrase.
- `no external reviewers` — legacy claim contradicting the actual fallback chain.
- `no externals, no voting` — legacy short-form variant.

All three are matched as fixed strings (`grep -F`) to avoid false positives on unrelated prose.

### SKILL.md negative-check exemption

`skills/implement/SKILL.md` is **exempted from negative checks**. Rationale: SKILL.md is the canonical contract and may legitimately quote historical/comment references to these phrases in unrelated contexts (e.g. NEVER-list examples, changelog-style prose).

**Audit performed during #370 implementation**: `grep -F` against each of the three stale phrases returned no matches in `skills/implement/SKILL.md`. The exemption is currently factual (no stale phrases present) rather than merely defensive. If a future SKILL.md edit introduces one of these phrases in a historical context, the exemption still holds by design — SKILL.md's positive anchors alone assert that the current contract is stated somewhere in the file; the canonical source-of-truth assertion does not require the file to be free of historical references.

If the canonical contract itself changes (e.g. the round cap goes to 10 or the fallback chain re-orders), edit the marker variables in `test-quick-mode-docs-sync.sh` and this sibling `.md` FIRST, then propagate to the public docs. The positive-anchor check enforces the new contract across all targets once the markers are updated.

## `--self-test` mode

The harness ships with a `--self-test` flag that runs the check against two embedded fixtures:

1. **Good fixture**: contains all three positive markers and no stale phrases.
2. **Bad fixture**: contains a stale phrase intentionally.

The same `check_file` function used in default mode is called against each. `--self-test` asserts that the good fixture produces 0 failures and the bad fixture produces at least 1 failure. This proves the check mechanics end-to-end on every CI run — a broken harness that always exits 0 would be caught because `--self-test` expects the bad fixture to fail. The fixture temp dir is cleaned up via `trap` on EXIT.

## Makefile wiring

Invoked via:

```bash
bash scripts/test-quick-mode-docs-sync.sh             # default mode
bash scripts/test-quick-mode-docs-sync.sh --self-test # self-test mode
make test-quick-mode-docs-sync                        # Makefile target (default mode only)
```

Listed in `Makefile` as a prerequisite of the `test-harnesses` target, alongside `test-orchestrator-scope-sync`, `test-implement-structure`, and other regression harnesses. `make lint` runs both `test-harnesses` and `lint-only`.

## agent-lint.toml wiring

Listed in `agent-lint.toml`'s `exclude` list because `agent-lint` does not follow Makefile-only references and would otherwise flag the script as orphaned. Matches the pattern used by sibling harnesses (e.g., `scripts/test-orchestrator-scope-sync.sh` at line 296). The sibling `scripts/test-quick-mode-docs-sync.md` does NOT need an explicit exclude — `scripts/test-orchestrator-scope-sync.md` is also not listed, and the same pre-existing convention is preserved here.

## Edit-in-sync rules

Whenever any of the following change, update them in the same PR:

- **The canonical contract in `skills/implement/SKILL.md` Step 5 quick-mode changes** — update the `POS_MARKER_*` and `STALE_*` constants at the top of `test-quick-mode-docs-sync.sh` FIRST; then update this `.md`; then propagate the new phrasing to each public doc target.
- **A new public doc surfaces that also describes `/implement --quick`** — add it to the `PUBLIC_DOCS` array in the script and list it in the Target Files table above.
- **The self-test fixture shape needs to change** — keep `check_file` usage byte-identical between default mode and self-test so self-test exercises the same code path.

## CI & portability

- `set -euo pipefail` and `export LC_ALL=C` at the top of the script. `LC_ALL=C` mirrors `scripts/test-orchestrator-scope-sync.sh` and normalizes grep behavior across GNU (Linux CI) and BSD (macOS dev).
- All file paths are resolved relative to `REPO_ROOT`, computed via `dirname "${BASH_SOURCE[0]}"`, so the script can be invoked from any working directory.
- `grep -Fq` is used for all fixed-string checks (portable between GNU and BSD).
- `mktemp -d` + `trap ... EXIT` ensures self-test fixtures are cleaned up even on failure paths.
