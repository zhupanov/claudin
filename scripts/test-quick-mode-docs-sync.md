# test-quick-mode-docs-sync.sh

Cross-validation harness with two check families: (1) alignment between the normative `/implement --quick` contract in `skills/implement/SKILL.md` Step 5 and the public user-facing documentation in `README.md`, `docs/review-agents.md`, and `docs/workflow-lifecycle.md` (closes #370); and (2) required cross-references — currently `docs/review-agents.md` → `skills/shared/voting-protocol.md` (closes #377). See the Target files and Required cross-references sections below for full coverage.

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

### Required cross-references

A third check family guards prose path citations in public docs against silent drift. Each entry is a (doc, xref) pair with two independent assertions:

| Doc | Cross-reference path | What each assertion catches |
|-----|----------------------|------------------------------|
| `docs/review-agents.md` | `skills/shared/voting-protocol.md` | (a) `grep -Fq` against the whole doc — fails if the literal path is absent from the file (substring-level; not anchored to Note A — see "Scope limitation" below); (b) regular-file check `[[ -f "$REPO_ROOT/<path>" ]]` — fails if the target file is renamed / moved / deleted without updating the citation (a directory at the cited path is deliberately NOT accepted, matching the contract that the citation resolves to a file). |

Both assertions are required. Dropping (a) would let a **rewording** that removes the literal path from the doc pass silently (the target file still exists on disk, so (b) alone would still pass). Dropping (b) would let a **rename / move / delete** of the target file pass silently (the old literal is still in the doc, so (a) alone would still pass). Together they pin the two-way invariant: **the cited path is present in the doc AND resolves to a real file**.

The check is implemented by `check_xref` (a dedicated function kept separate from `check_file`). Target-specific — NOT applied to every public doc — so it does not affect the existing self-test's "exactly 1 failure" invariant on the pre-existing bad fixture, which exercises `check_file` only. New xref targets extend the `XREF_DOC` / `XREF_PATH` constants at the top of the script and add a `check_xref` call in `run_default` (with matching self-test coverage).

**Scope limitation**: assertion (a) is a substring-level `grep -Fq` against the whole doc — it does NOT pin the citation to the specific Note A paragraph or any structural anchor. If Note A is reorganized elsewhere in the file, or the literal path is quoted in an unrelated paragraph (e.g., a historical note), the grep still passes. The guard is strong enough for the recurring failure modes #377 targeted (Note A rewording that drops the path, target-file rename breaking the reference), and stronger semantic binding would require a line-anchored check or an explicit marker string in the source doc.

### SKILL.md negative-check exemption

`skills/implement/SKILL.md` is **exempted from negative checks**. Rationale: SKILL.md is the canonical contract and may legitimately quote historical/comment references to these phrases in unrelated contexts (e.g. NEVER-list examples, changelog-style prose).

**Audit performed during #370 implementation**: `grep -F` against each of the three stale phrases returned no matches in `skills/implement/SKILL.md`. The exemption is currently factual (no stale phrases present) rather than merely defensive. If a future SKILL.md edit introduces one of these phrases in a historical context, the exemption still holds by design — SKILL.md's positive anchors alone assert that the current contract is stated somewhere in the file; the canonical source-of-truth assertion does not require the file to be free of historical references.

If the canonical contract itself changes (e.g. the round cap goes to 10 or the fallback chain re-orders), edit the marker variables in `test-quick-mode-docs-sync.sh` and this sibling `.md` FIRST, then propagate to the public docs. The positive-anchor check enforces the new contract across all targets once the markers are updated.

## `--self-test` mode

The harness ships with a `--self-test` flag that runs two `check_file` fixtures + three `check_xref` fixtures (see next block), all against embedded temp-dir content.

`check_file` fixtures:

1. **Good fixture**: contains all three positive markers and no stale phrases. `--self-test` asserts the good fixture produces exactly **0** failures.
2. **Bad fixture**: contains all three positive markers AND one stale phrase — structured so the ONLY reason `check_file` can fail on this fixture is the negative-check path firing on the stale phrase. `--self-test` asserts the bad fixture produces exactly **1** failure.

The same `check_file` function used in default mode is called against each. The "exactly 1 failure" assertion on the bad fixture is the load-bearing guarantee: if the negative-check block in `check_file` were deleted or bypassed, the bad fixture would produce 0 failures and the self-test would exit non-zero. If the positive-anchor block were deleted, the good fixture would still produce 0 failures (unchanged), but the bad fixture's positive markers would never be checked — the default-mode run against real repo files remains the primary guard against positive-check regressions. The fixture temp dir is cleaned up via `trap` on EXIT.

Additionally, the self-test exercises `check_xref` against three xref-specific fixtures carved from sub-directories inside the same `FIXTURE_DIR`:

1. **xref-good**: doc contains the literal xref path AND target file exists on disk. `--self-test` asserts 0 failures.
2. **xref-bad-existence**: doc contains the literal xref path BUT target file is missing on disk. `--self-test` asserts exactly 1 failure, driven entirely by the existence assertion. Regression-guards the `-f` branch: if the existence block were removed from `check_xref`, this fixture would produce 0 failures.
3. **xref-bad-grep**: target file exists on disk BUT doc omits the literal xref path. `--self-test` asserts exactly 1 failure, driven entirely by the grep assertion. Regression-guards the `grep -Fq` branch: if the grep block were removed, this fixture would produce 0 failures.

The bad-existence and bad-grep fixtures are symmetric — together they pin both assertions in place, matching the two-way invariant that the `check_xref` contract exists to enforce. Each fixture's "exactly 1 failure" assertion is the load-bearing guarantee for its respective branch. Symmetric in spirit to the `check_file` bad-fixture invariant.

## Makefile wiring

Invoked via:

```bash
bash scripts/test-quick-mode-docs-sync.sh             # default mode
bash scripts/test-quick-mode-docs-sync.sh --self-test # self-test mode
make test-quick-mode-docs-sync                        # Makefile target (runs both default and --self-test)
```

Listed in `Makefile` as a prerequisite of the `test-harnesses` target, alongside `test-orchestrator-scope-sync`, `test-implement-structure`, and other regression harnesses. `make lint` runs both `test-harnesses` and `lint-only`.

## agent-lint.toml wiring

Listed in `agent-lint.toml`'s `exclude` list because `agent-lint` does not follow Makefile-only references and would otherwise flag the script as orphaned. Matches the pattern used by sibling harnesses such as `scripts/test-orchestrator-scope-sync.sh` (grep the exclude list for exact position — line numbers drift as entries are added). The sibling `scripts/test-quick-mode-docs-sync.md` does NOT need an explicit exclude — `scripts/test-orchestrator-scope-sync.md` is also not listed, and the same pre-existing convention is preserved here.

## Edit-in-sync rules

Whenever any of the following change, update them in the same PR:

- **The canonical contract in `skills/implement/SKILL.md` Step 5 quick-mode changes** — update the `POS_MARKER_*` and `STALE_*` constants at the top of `test-quick-mode-docs-sync.sh` FIRST; then update this `.md`; then propagate the new phrasing to each public doc target.
- **A new public doc surfaces that also describes `/implement --quick`** — add it to the `PUBLIC_DOCS` array in the script and list it in the Target Files table above.
- **The self-test fixture shape needs to change** — keep `check_file` usage byte-identical between default mode and self-test so self-test exercises the same code path. Same rule for `check_xref`: default-mode and self-test must call the same function.
- **Note A's cited path in `docs/review-agents.md` is renamed / moved / replaced** — update the `XREF_PATH` constant in the script to the new path AND update the "Required cross-references" table above in the same PR. If the rename's intent is to drop the xref entirely, remove the `check_xref` call from `run_default` plus its self-test fixtures, and delete the corresponding row from the table.

## CI & portability

- `set -euo pipefail` and `export LC_ALL=C` at the top of the script. `LC_ALL=C` mirrors `scripts/test-orchestrator-scope-sync.sh` and normalizes grep behavior across GNU (Linux CI) and BSD (macOS dev).
- All file paths are resolved relative to `REPO_ROOT`, computed via `dirname "${BASH_SOURCE[0]}"`, so the script can be invoked from any working directory.
- `grep -Fq` is used for all fixed-string checks (portable between GNU and BSD).
- `mktemp -d` + `trap ... EXIT` ensures self-test fixtures are cleaned up even on failure paths.
