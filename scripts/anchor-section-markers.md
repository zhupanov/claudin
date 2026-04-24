# anchor-section-markers.sh — contract

## Purpose

Single source of truth for the 8 canonical anchor section slugs, in assembly / truncation order. Sourced by both `scripts/tracking-issue-write.sh` (for per-section + body-level truncation) and `scripts/assemble-anchor.sh` (for anchor-body assembly).

Before umbrella #348 Phase 5, `SECTION_MARKERS` was declared inline at the top of `scripts/tracking-issue-write.sh`. Phase 5 extracted it into this sourceable fragment so the assembly helper (`assemble-anchor.sh`) and the publish helper (`tracking-issue-write.sh`) share one executable definition — preventing silent drift across the two scripts' understanding of section order.

## Interface

One array, one read-only contract:

```bash
SECTION_MARKERS=(plan-goals-test plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics)
```

The array contains 8 elements in assembly order. Consumer contract:

- `scripts/assemble-anchor.sh` walks the array to emit `<!-- section:<slug> -->` / `<!-- section-end:<slug> -->` marker pairs in the same order.
- `scripts/tracking-issue-write.sh` walks the array in its per-section truncation pass (see `tracking-issue-write.md` "Truncation algorithm").

## Conventions

- **Not a standalone script**: no `set -euo pipefail`, no shebang line requirement, no flag parsing. Do NOT add a `main` entry — consumers `source` this file to acquire the array, not execute it.
- **Bash 3.2 compatible**: indexed arrays only; no associative arrays.
- **Read-only**: consumers MUST NOT mutate the array after sourcing. Downstream code may iterate `"${SECTION_MARKERS[@]}"` but never `SECTION_MARKERS=(...)`.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/tracking-issue-write.sh` | Sources this file to drive truncation-pass ordering. |
| `scripts/assemble-anchor.sh` | Sources this file to drive assembly-order walk. |
| `scripts/tracking-issue-write.md` | Documents the truncation algorithm that depends on this ordering. |
| `scripts/assemble-anchor.md` | Documents the assembly algorithm that depends on this ordering. |
| `skills/implement/references/anchor-comment-template.md` | Human-readable anchor body template referencing the same 8 slugs; the array here is the executable source of truth. |

The `COLLAPSE_PRIORITY` array lives inline in `scripts/tracking-issue-write.sh` — it encodes a different ordering (body-cap collapse priority, most-ephemeral first) over the same slug set. An invariant assertion in `scripts/test-tracking-issue-write.sh` pins that every `SECTION_MARKERS` slug appears in `COLLAPSE_PRIORITY`.

## Test harness

Covered indirectly by:
- `scripts/test-assemble-anchor.sh` — fixture-based validation that assemble-anchor.sh emits the full 8-slug marker set in SECTION_MARKERS order.
- `scripts/test-tracking-issue-write.sh` — existing harness validates truncation + the SECTION_MARKERS ⊆ COLLAPSE_PRIORITY invariant (Phase 5 addition).

No direct harness — the file exposes only a constant array.

## Makefile wiring

No direct target. Both consumers are already wired into `make test-harnesses` (prerequisite of `make lint`).
