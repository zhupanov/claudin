# test-assemble-anchor.sh contract

## Purpose

Regression harness for `scripts/assemble-anchor.sh`. Covers the 6 assertion categories pinned by the sibling `scripts/assemble-anchor.md` contract file: empty sections directory, partial fragments, full fragments, missing-helper failure, invalid-`--issue` usage error, first-line marker exactness.

## Assertion catalog

- **(a)** Empty sections directory: output has exactly `1 + 2*N` lines (anchor first-line marker + `N` empty marker pairs, where `N = |SECTION_MARKERS|`). Marker pairs appear in `SECTION_MARKERS` order.
- **(b)** Partial fragments: populated content appears only where fragment files exist; empty marker pairs elsewhere. Order preserves `SECTION_MARKERS` indexing (`diagrams` before `version-bump-reasoning`).
- **(c)** Full fragments: all 8 slugs populated and emitted.
- **(d)** Missing `anchor-section-markers.sh` helper: running a copy of `assemble-anchor.sh` in a fake tree without the helper emits `FAILED=true` + `ERROR=missing helper: ...` on stdout and exits 1.
- **(e)** Invalid `--issue` value (non-integer): emits `FAILED=true` + `ERROR=usage: invalid value for --issue ...` on stdout and exits 1.
- **(f)** First-line marker exactness: output always begins with `<!-- larch:implement-anchor v1 issue=<N> -->` where `<N>` is the `--issue` value.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/assemble-anchor.sh` | Under test — every behavioral change in that script must be mirrored here. |
| `scripts/anchor-section-markers.sh` | Sourced by the harness to resolve canonical slug order for ordering assertions. |
| `scripts/assemble-anchor.md` | Pins the assertion catalog above. |

## Makefile wiring

Wired into `make test-harnesses` (prerequisite of `make lint`). Standalone target: `make test-assemble-anchor`.
