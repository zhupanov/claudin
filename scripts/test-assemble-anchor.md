# test-assemble-anchor.sh contract

## Purpose

Regression harness for `scripts/assemble-anchor.sh`. Covers 14 assertion categories pinned by the sibling `scripts/assemble-anchor.md` contract file: empty sections directory (line-count, line-walk, placeholder presence), partial fragments and whitespace-only fragments (placeholder gating), nonexistent `--sections-dir` (placeholder fires for missing dir), exact line-shape around a newline-terminated fragment, line-shape around a no-trailing-newline fragment, full fragments, missing-helper failure, invalid-`--issue` usage error, first-line marker exactness, non-directory `--sections-dir` fail-closed, and unreadable-fragment fail-closed.

## Assertion catalog

- **(a)** Empty sections directory: output has exactly `2 + 2*N` lines (anchor first-line marker + seed-only visible placeholder line + `N` empty marker pairs, where `N = |SECTION_MARKERS|`). Marker pairs appear in `SECTION_MARKERS` order, starting at line 3. Pinned line-2 literal: `_/implement run in progress — sections below populate as the run proceeds._`.
- **(a2)** Empty sections directory: explicit regression guard that the seed-only visible placeholder literal is present in the output (issue #431).
- **(a3)** Partial fragments (one slug populated with non-whitespace content): the placeholder is suppressed — the gate fires only on the all-empty seed.
- **(a4)** All fragments populated with whitespace-only content (newlines, spaces, tabs): the placeholder still fires (lenient predicate per dialectic DECISION_1).
- **(a5)** Nonexistent `--sections-dir`: `ASSEMBLED=true` and the placeholder fires; the all-empty pre-pass treats a missing directory the same as an empty one.
- **(b)** Partial fragments: populated content appears only where fragment files exist; empty marker pairs elsewhere. Order preserves `SECTION_MARKERS` indexing (`diagrams` before `version-bump-reasoning`).
- **(b2)** Newline-terminated fragment → exactly one newline before the close marker (regression guard for the pre-fix `$(tail -c 1 ...)` command-substitution newline-stripping bug, which inserted an extra blank line for every populated fragment). Full output compared against a byte-exact expected fixture.
- **(b3)** Fragment without a trailing newline → helper inserts the missing newline so the close marker still appears on its own line; fragment content and close marker do not run together on the same line.
- **(c)** Full fragments: all 8 slugs populated and emitted.
- **(d)** Missing `anchor-section-markers.sh` helper: running a copy of `assemble-anchor.sh` in a fake tree without the helper emits `FAILED=true` + `ERROR=missing helper: ...` on stdout and exits 1.
- **(e)** Invalid `--issue` value (non-integer): emits `FAILED=true` + `ERROR=usage: invalid value for --issue ...` on stdout and exits 1.
- **(f)** First-line marker exactness: output always begins with `<!-- larch:implement-anchor v1 issue=<N> -->` where `<N>` is the `--issue` value.
- **(g)** Non-directory `--sections-dir` (regular file passed where a directory is expected): fails closed with `FAILED=true` + `ERROR=sections-dir exists but is not a directory: …` on stdout and exits 2. Regression guard: pre-fix the helper silently produced an all-empty skeleton in this case, which could clobber populated remote anchor content on upsert.
- **(h)** Unreadable fragment file (chmod 000 on a listed slug): fails closed with `FAILED=true` + `ERROR=failed to read fragment: …` on stdout and exits 2. Skipped when the test runs as root (root bypasses POSIX file-read permission checks). Regression guard: pre-fix the helper silently emitted an empty section interior on fragment read failure, which could also clobber remote content.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/assemble-anchor.sh` | Under test — every behavioral change in that script must be mirrored here. |
| `scripts/anchor-section-markers.sh` | Sourced by the harness to resolve canonical slug order for ordering assertions. |
| `scripts/assemble-anchor.md` | Pins the assertion catalog above. |

## Makefile wiring

Wired into `make test-harnesses` (prerequisite of `make lint`). Standalone target: `make test-assemble-anchor`.
