# assemble-anchor.sh contract

## Purpose

Assemble the anchor comment body from local per-section fragment files under a sections directory. Walks the canonical `SECTION_MARKERS` slug list (sourced from `anchor-section-markers.sh`), emits paired `<!-- section:<slug> -->` / `<!-- section-end:<slug> -->` markers wrapping each fragment's content (empty marker pairs when a fragment file is absent), prepends the first-line HTML anchor marker `<!-- larch:implement-anchor v1 issue=<N> -->`, and writes the result to `--output`.

Umbrella #348 Phase 5 extracted this helper to eliminate prose-vs-shell drift across the multiple callsites that previously implemented the walk inline (SKILL.md Step 0.5 Branch 2/3 adoption-seed, Step 0.5 Branch 4 fresh-run first-remote-write, Steps 1/2/5/7a/8/9a.1/11 progressive upserts — Step 2 covers Q/A anchor refresh, and the rebase-rebump sub-procedure Step 6). Every anchor body creation and progressive upsert now routes through this one helper.

## Interface

```
assemble-anchor.sh --sections-dir <dir> --issue <N> --output <path>
```

Flags are all required.

- `--sections-dir <dir>` — directory containing per-slug fragment files named `<slug>.md`. Missing directory is tolerated (all marker pairs emit empty). Unreadable directory is an I/O failure.
- `--issue <N>` — non-negative integer issue number. Embedded verbatim into the first-line HTML marker `<!-- larch:implement-anchor v1 issue=<N> -->`.
- `--output <path>` — destination for the assembled body. Parent directory is created if missing. Atomic rename ensures the file appears complete or not at all.

## Output contract (KEY=value on stdout)

### Success

```
ASSEMBLED=true
OUTPUT=<path>
```

### Failure

```
FAILED=true
ERROR=<single-line message>
```

Prefix matches `tracking-issue-write.sh`'s `FAILED=` / `ERROR=` convention so both helpers can be parsed by the same consumer logic.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invocation / usage error (missing flag, empty value, invalid `--issue`, missing `anchor-section-markers.sh` helper) |
| 2 | I/O failure (unreadable sections dir, unwritable output path, failed tmp-file mv) |

Parsers MUST use the `ERROR=` field (not exit code alone) to disambiguate — exit 1 covers both missing-flag and missing-helper failures.

## Invariants

### Marker order matches SECTION_MARKERS

The assembly walk iterates `"${SECTION_MARKERS[@]}"` from `anchor-section-markers.sh`. Any consumer that depends on a specific section order (notably `scripts/tracking-issue-write.sh`'s truncation pass) MUST share the same source-of-truth array. Do not hardcode slug names in this script.

### First-line marker exactness

Output always begins with `<!-- larch:implement-anchor v1 issue=<N> -->\n`. `tracking-issue-write.sh upsert-anchor` uses this first-line prefix to locate prior anchor comments via GitHub search. Any change to the marker literal requires a coordinated change in `tracking-issue-write.sh` and its anchor version policy.

### Empty marker pairs preserve section shape

Missing fragment files emit only the open/close marker pair with no content between. This preserves the skeleton required by `tracking-issue-write.sh`'s per-section truncation algorithm (which locates interiors by marker-pair boundaries).

### Seed-only visible placeholder

When every fragment is **absent, zero-byte, or whitespace-only** (the lenient "all empty" predicate), the assembled body carries one extra italic-markdown line between the first-line HTML marker and the first `<!-- section:plan-goals-test -->` open marker:

```
_/implement run in progress — sections below populate as the run proceeds._
```

Why: an anchor body composed entirely of HTML comment markers renders invisible in GitHub's UI — the freshly planted seed comment looks blank to humans (issue #431). The placeholder is emitted on its own line, *outside* every section interior, so it never collides with `tracking-issue-write.sh`'s per-section truncation (which locates interiors by whole-line marker-pair boundaries).

Populated runs — any fragment with at least one **non-whitespace byte** — suppress the placeholder. The output for partially or fully populated anchors is byte-for-byte unchanged from the pre-fix shape, so progressive upserts at Steps 1/2/5/7a/8/9a.1/11 only ever see the populated body shape and downstream parsers (truncation, hydration awk) are not affected.

The "all empty" detection runs as a separate pre-pass over `SECTION_MARKERS` after the readability pre-pass and before the assembly brace group. The predicate is `grep -q '[^[:space:]]'` against each candidate fragment file; the first non-whitespace byte hit short-circuits the walk to `ALL_EMPTY=false`. This predicate choice (lenient — whitespace-only fragments still trigger the placeholder) was resolved via dialectic adjudication and confirmed by the user during plan design.

### Atomic output rename

The assembled body is first written to a `mktemp` sibling of `--output` and only atomically `mv`ed into place on success. A partial write never leaves a malformed anchor body on disk. The EXIT trap cleans up the tmp file on error paths.

### No redaction, no network

This helper performs pure text assembly of local files. The redaction pipeline lives in `scripts/tracking-issue-write.sh` (which runs compose → redact → truncate on the assembled body at publish time). Compose-time sanitization of fragment content (secrets → `<REDACTED-TOKEN>`, internal URLs → `<INTERNAL-URL>`, PII → `<REDACTED-PII>`) is the caller's responsibility per `skills/implement/SKILL.md` "Compose-time sanitization" — this helper emits fragments verbatim.

## Conventions

- `set -euo pipefail`. Bash 3.2 compatible (indexed arrays only, no `mapfile`, no associative arrays).
- Missing helper `anchor-section-markers.sh` fails closed with `FAILED=true` / `ERROR=missing helper: …` + exit 1 (preserves the stdout-contract invariant consumers rely on).

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/anchor-section-markers.sh` | Single-source-of-truth for slug order (sourced). |
| `scripts/tracking-issue-write.sh` | Downstream publisher; receives the `--output` path via `upsert-anchor --body-file`. Truncation pass relies on the same SECTION_MARKERS ordering. |
| `scripts/test-assemble-anchor.sh` | Regression harness — every behavioral change here must be mirrored in the harness. |
| `skills/implement/SKILL.md` | Primary consumer for anchor-section accumulation. |
| `skills/implement/references/rebase-rebump-subprocedure.md` | Phase 5 consumer (sub-procedure Step 6). |
| `skills/implement/references/anchor-comment-template.md` | Human-readable template describing the same 8 slugs and first-line marker. |

## Test harness

`scripts/test-assemble-anchor.sh` covers 14 assertion categories:

- **(a)** Empty sections directory: output has exactly 18 lines — `<!-- larch:implement-anchor v1 issue=<N> -->` on line 1, the seed-only visible placeholder line on line 2, and 8 pairs of empty marker tags on lines 3-18.
- **(a2)** Empty sections directory: the seed-only placeholder literal is present on line 2 (regression guard for issue #431).
- **(a3)** Partial fragments (one slug populated): the placeholder is suppressed — only the all-empty seed case fires it.
- **(a4)** All fragments contain only whitespace bytes (lenient predicate validation): the placeholder still fires.
- **(a5)** Nonexistent `--sections-dir`: `ASSEMBLED=true` and the placeholder fires (the all-empty pre-pass treats a missing directory as all-empty).
- **(b)** Partial fragments: output contains the populated content only where fragment files exist, empty marker pairs elsewhere, in `SECTION_MARKERS` order.
- **(b2)** Newline-terminated fragment → exactly one newline before the close marker (regression guard for the `$(tail -c 1 ...)` command-substitution newline-stripping bug that inserted an extra blank line). Full output compared against a byte-exact expected fixture.
- **(b3)** Fragment without a trailing newline → helper inserts one so the close marker stays on its own line.
- **(c)** Full fragments: all 8 slugs have populated content.
- **(d)** Missing `anchor-section-markers.sh` helper: `FAILED=true` + `ERROR=missing helper: …` on stdout + exit 1.
- **(e)** Invalid `--issue` value (non-integer): usage error with exit 1.
- **(f)** First-line marker is always the first line of the output.
- **(g)** Non-directory `--sections-dir` → fail-closed with `FAILED=true` + `ERROR=sections-dir exists but is not a directory: …` + exit 2.
- **(h)** Unreadable fragment file → fail-closed with `FAILED=true` + `ERROR=failed to read fragment: …` + exit 2. Skipped when the test runs as root.

## Makefile wiring

The regression harness `scripts/test-assemble-anchor.sh` is wired into `make test-harnesses` (prerequisite of `make lint`). Standalone target: `make test-assemble-anchor`.
