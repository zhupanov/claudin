# tracking-issue-write.sh contract

## Purpose

Phase 1 (umbrella #348) foundation layer: outbound helper for the tracking-issue lifecycle. Four narrow subcommands (`create-issue`, `append-comment`, `upsert-anchor`, `rename`) that each perform exactly one GitHub write, sharing a KEY=value stdout envelope and fail-closed redaction posture modelled on `skills/issue/scripts/create-one.sh`. The first three were added in Phase 1; `rename` was added alongside the tracking-issue title-prefix lifecycle (see "Title-prefix lifecycle" below).

## Subcommands

```
tracking-issue-write.sh create-issue   --title T --body-file F [--repo OWNER/REPO]
tracking-issue-write.sh append-comment --issue N --body-file F [--lifecycle-marker ID] [--repo OWNER/REPO]
tracking-issue-write.sh upsert-anchor  --issue N [--anchor-id ID] --body-file F [--repo OWNER/REPO]
tracking-issue-write.sh rename         --issue N --state in-progress|done|stalled [--repo OWNER/REPO]
```

## Output contract (KEY=value on stdout)

### Namespace note

This script emits `FAILED=true` / `ERROR=<msg>` on failure — NOT the `ISSUE_FAILED=true` / `ISSUE_ERROR=<msg>` prefix used by `skills/issue/scripts/create-one.sh`. The divergence is intentional: this script is not an `/issue` layer component. Parsers MUST use the `FAILED=` / `ERROR=` prefix exactly. Parsers MUST also use the `ERROR=` field (not exit code alone) to distinguish error kinds — exit 1 covers both invocation-usage errors and validated-content rejections (see exit-code table below).

### Success keys

| Subcommand | Keys |
|---|---|
| `create-issue` | `ISSUE_NUMBER=<N>`, `ISSUE_URL=<url>` |
| `append-comment` | `COMMENT_ID=<id>`, `COMMENT_URL=<url>` |
| `upsert-anchor` | `ANCHOR_COMMENT_ID=<id>`, `ANCHOR_COMMENT_URL=<url>`, `UPDATED=true\|false` (`true` when an existing anchor was PATCHed; `false` when a new anchor comment was created) |
| `rename` | `RENAMED=true\|false`, `NEW_TITLE=<title>` (`false` when the current title already starts with the target prefix — no `gh issue edit` call was made) |

### Failure keys

`FAILED=true` followed by `ERROR=<single-line message>`. The `ERROR=` value is flattened to one line and length-capped at 500 bytes (matches create-one.sh convention).

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Success |
| 1 | Invocation-usage error OR validated-content rejection (e.g. missing body file, empty body). Disambiguate via `ERROR=`. |
| 2 | `gh` failure (`FAILED=true` / `ERROR=` already emitted on stdout) |
| 3 | Redaction helper failure (`FAILED=true` / `ERROR=redaction:…`) |

## Invariants

### Structural choke point: compose → redact → truncate

Every subcommand composes the full logical body in memory, pipes it through `scripts/redact-secrets.sh`, and only then applies truncation. Order is non-negotiable: reversing it could slice token-shaped byte sequences and let secrets past the scrubber. The placement mirrors the `create-one.sh:202-208` "Single structural choke point" comment. Any refactor that reorders these steps must first update the test harness to prove the invariant still holds.

### gh-failure redaction

Every `gh` invocation captures stdout and stderr separately. On non-success paths, captured stderr is piped through `scripts/redact-secrets.sh` before emission in `ERROR=`. This mirrors `create-one.sh:247-280`'s outbound posture. Covers 4xx API response bodies that may echo token-bearing request material.

### Anchor skeleton preservation

Truncation operates on section interiors only — never on the HTML first-line anchor marker (`<!-- larch:implement-anchor v1 issue=<N> -->`) or on any `<!-- section:<id> -->` / `<!-- section-end:<id> -->` pair. Phase 3 consumers parse by these markers; corrupting them breaks downstream parsers silently.

### Anchor version policy (strict v1)

Upsert-anchor matches and emits only `<!-- larch:implement-anchor v1` prefixed comments. Future versions (v2, …) introduce a new marker handled by a new tool version. Mixed-version state on one issue fails closed via the multiple-anchor-comments branch (exit 2 with `FAILED=true ERROR=multiple anchor comments found (ids: <list>)`).

## Truncation algorithm

Two-pass, applied AFTER redaction:

1. **Per-section cap** (`PER_SECTION_CAP=8000`): for each of the 8 canonical section slugs (`plan-goals-test`, `plan-review-tally`, `code-review-tally`, `diagrams`, `version-bump-reasoning`, `oos-issues`, `execution-issues`, `run-statistics`), if the interior between the section-open marker and section-end marker exceeds 8000 chars, replace the interior with a single inline `[TRUNCATED — <slug> exceeded 8000 chars]` line. The cut offset is **snapped to the next newline boundary** at or before 8000 so the marker always begins on its own line — this prevents open code fences from consuming the marker or subsequent section markers during GitHub rendering.

2. **Body-level cap** (`BODY_CAP=60000`): if total body length still exceeds 60000 chars after pass 1, walk the collapse priority list in order:

   `execution-issues` → `plan-review-tally` → `code-review-tally` → `oos-issues` → `run-statistics` → `version-bump-reasoning` → `diagrams` → `plan-goals-test`

   For each slug, replace the interior with `[section '<slug>' truncated — see execution-issues.md locally]`. Stop once total length fits the cap. The priority order encodes user-value: most-ephemeral sections collapse first (execution-issues are reproducible from local tmpdir); diagrams and plan-goals-test collapse last (highest user value).

### UTF-8 policy

Truncation is byte-length based. Multibyte UTF-8 splitting is tolerated because section interiors are machine-composed by `/implement` — no human-authored multibyte content is expected between section markers. Line-boundary snapping (above) prevents the more visible fence-cut corruption.

## Lifecycle markers

`append-comment` accepts `--lifecycle-marker <id>`, which prepends `<!-- larch:lifecycle-marker:<id> -->\n` to the body before redaction+truncation. Three canonical markers for Phase 2+ callers: `pr-opened`, `pr-closed`, `in-progress`. These machine-owned markers replace the prose-prefix filters (`PR opened:`, `Closed by PR #`) from the original design — prose prefixes were too loose (matched ordinary English comments).

## Title-prefix lifecycle (rename subcommand)

Tracking issues carry a machine-owned title-prefix lifecycle: `[IN PROGRESS]` during active work, `[DONE]` after the tracking run completes, `[STALLED]` when a run fails without closing. Each prefix is followed by a single space before the rest of the title (e.g., `[IN PROGRESS] Fix login bug`). `rename` is the single mutator for these prefixes; every consumer MUST use this subcommand rather than inlining `gh issue edit --title`.

### Algorithm

1. Fetch the current title via `gh issue view --json title`.
2. Strip **exactly one** leading managed prefix (anchored at start; regex matching one of `[IN PROGRESS]`, `[DONE]`, or `[STALLED]` followed by a single space). Stacked prefixes beyond the first are preserved — the helper does not "heal" corrupted titles because the healing policy (prefer first vs. last vs. middle) is ambiguous.
3. Prepend the target-state prefix (`[IN PROGRESS]`, `[DONE]`, or `[STALLED]`) followed by one space.
4. Pipe the prospective new title through `scripts/redact-secrets.sh` (same posture as `create-issue`).
5. Truncate to 256 chars if the result exceeds GitHub's title limit. Truncation uses bash string semantics (`${#var}` + `${var:0:256}`), which matches GitHub's character-based 256 limit under UTF-8 locales. The prefix is preserved (tail is sliced). Managed prefixes are ASCII so truncation is stable regardless of locale.
6. If the resulting title equals the current title (already in target state), emit `RENAMED=false` and skip the `gh` call.
7. Otherwise call `gh issue edit --title` and emit `RENAMED=true`.

### Idempotency

Re-calling `rename --state X` on an issue already at state X is a no-op (`RENAMED=false`). This matters for resumed `/implement` sessions and for the bash drivers' EXIT-trap paths (the trap may fire after a successful explicit rename-to-done; the re-rename to `[STALLED]` is a no-op because the guard flag prevents it, but even without that the helper would emit `RENAMED=false` for an already-stalled title).

### Distinction from `/fix-issue`'s "IN PROGRESS" comment lock

The title prefix `[IN PROGRESS]` (followed by a space) is the **tracking-issue lifecycle state** — whose job is to signal human triage and filter `/fix-issue` auto-pick. It is orthogonal to `/fix-issue`'s existing **comment-based** lock (last comment equal to the bare text `IN PROGRESS`), which is the **concurrency lock** preventing two concurrent `/fix-issue` runners from picking the same subject issue. Both mechanisms coexist:
- Comment lock: applies to any `/fix-issue` subject issue; set at step 2 of `/fix-issue`; cleared when work completes.
- Title prefix: applied to `/implement`-managed tracking issues for the duration of the active run — both fresh-created (Step 0.5 Branch 4) and adopted (Branch 2/3/Branch 1 resume safety net, e.g. via `/fix-issue` forwarding `--issue <N>`). Step 12a/12b flips `[IN PROGRESS]` → `[DONE]` on merge; Step 18 Branch A flips it to `[STALLED]` on failure; Step 18 Branch B flips it to `[DONE]` on clean non-merge or draft completion (PR opened without auto-merge). `/improve-skill` and `/loop-improve-skill` use a narrower policy: the prefix is owned only when the script created the issue itself, OR when an adopted issue's title already begins with a managed prefix (then the script treats it as tool-owned and continues to manage the lifecycle); see `skills/improve-skill/scripts/iteration.sh` for the `ADOPTED` detection. The `rename` subcommand strips exactly one leading managed prefix before prepending the new one, so user-authored title text is preserved across transitions.

## Conventions

Uses Bash 3.2-compatible constructs (indexed arrays only; no associative arrays, no `mapfile`) so macOS-default bash runs match Ubuntu CI. Precedent: `scripts/dialectic-smoke-test.sh`.

## Makefile wiring

The regression harness `scripts/test-tracking-issue-write.sh` is wired into `make test-harnesses` (which is a prerequisite of `make lint`). Standalone target: `make test-tracking-issue-write`.

## Test harness

`scripts/test-tracking-issue-write.sh` covers ten assertion categories (a-j):

- **(a)** `create-issue` redacts title + body (`sk-ant-*` secret → `<REDACTED-TOKEN>`).
- **(b)** `create-issue` exits 3 with `FAILED=true` / `ERROR=redaction:…` when the redactor is missing. Pins exact key literals `FAILED=true` (not `ISSUE_FAILED`).
- **(c)** `upsert-anchor` preserves the HTML anchor marker + all 8 section markers after a >60000-char body-level collapse.
- **(d)** `upsert-anchor` per-section 8000 truncation inserts `[TRUNCATED — <id> exceeded 8000 chars]` on its own line (line-boundary-snapped).
- **(e)** `append-comment` does NOT touch the anchor comment (stub-gh asserts the anchor comment is untouched).
- **(f1) Idempotency**: `upsert-anchor` with exactly one existing anchor comment PATCHes it, emits `UPDATED=true`, creates no new comment on double-call.
- **(f2) Multiple-anchor fail-closed**: `upsert-anchor` with 2+ marker comments exits 2 with `FAILED=true ERROR=multiple anchor comments found (ids: <list>)`.
- **(g) gh-failure redaction**: stub-gh emits a token-bearing stderr on failure → the `FAILED=true ERROR=…` line contains `<REDACTED-TOKEN>` and not the raw token.
- **(h) Missing `anchor-section-markers.sh` helper**: when the script's sourced helper is missing from the script's `$SCRIPT_DIR`, it fails closed with `FAILED=true` / `ERROR=missing helper: …` on stdout and exits 1 — preserving the stdout contract invariant.
- **(i) `SECTION_MARKERS` ⊆ `COLLAPSE_PRIORITY` invariant**: every slug defined in `scripts/anchor-section-markers.sh` appears in `COLLAPSE_PRIORITY`, so the body-level truncation pass has a collapse target for every section.
- **(j) `rename` subcommand**: base rename (no existing prefix → prepend), transition rename (`[IN PROGRESS]` → `[DONE]`), idempotent no-op (already at target state → `RENAMED=false`, no `gh` call), strip-exactly-one (stacked-prefix residue preserved), redact pipeline applied (token in title → `<REDACTED-TOKEN>` in outbound), invalid `--state` → `FAILED=true ERROR=invalid --state: ...`.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/anchor-section-markers.sh` | Single source of truth for `SECTION_MARKERS`; sourced by this script at startup. Missing helper is fail-closed (test harness case (h)). |
| `scripts/redact-secrets.sh` | Sole outbound scrubber — do NOT bypass or add a parallel redactor. |
| `scripts/tracking-issue-read.sh` | Delegates `append-comment` when invoked with `--issue + --prompt`. |
| `scripts/test-tracking-issue-write.sh` | Regression harness for this script — every behavioral change here must be mirrored in the harness. |
| `scripts/assemble-anchor.sh` | Companion helper that assembles anchor bodies from `$IMPLEMENT_TMPDIR/anchor-sections/`. Shares `SECTION_MARKERS` ordering via the same sourced helper. |
| `skills/implement/references/anchor-comment-template.md` | Human-readable template describing the same 8 section slugs + anchor first-line marker; the executable source of truth is `scripts/anchor-section-markers.sh`. |
| `SECURITY.md` | Documents the outbound-redaction invariant, gh-failure redaction, anchor-skeleton preservation. |

## Security

See `SECURITY.md` "tracking-issue-write.sh outbound path" subsection.
