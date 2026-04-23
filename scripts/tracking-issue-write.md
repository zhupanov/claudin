# tracking-issue-write.sh contract

## Purpose

Phase 1 (umbrella #348) foundation layer: outbound helper for the tracking-issue lifecycle. Three narrow subcommands that each perform exactly one GitHub write, sharing a KEY=value stdout envelope and fail-closed redaction posture modelled on `skills/issue/scripts/create-one.sh`. No consumers wired in Phase 1; Phase 3 is the first consumer.

## Subcommands

```
tracking-issue-write.sh create-issue   --title T --body-file F [--repo OWNER/REPO]
tracking-issue-write.sh append-comment --issue N --body-file F [--lifecycle-marker ID] [--repo OWNER/REPO]
tracking-issue-write.sh upsert-anchor  --issue N [--anchor-id ID] --body-file F [--repo OWNER/REPO]
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

## Conventions

Uses Bash 3.2-compatible constructs (indexed arrays only; no associative arrays, no `mapfile`) so macOS-default bash runs match Ubuntu CI. Precedent: `scripts/dialectic-smoke-test.sh`.

## Makefile wiring

The regression harness `scripts/test-tracking-issue-write.sh` is wired into `make test-harnesses` (which is a prerequisite of `make lint`). Standalone target: `make test-tracking-issue-write`.

## Test harness

`scripts/test-tracking-issue-write.sh` covers seven assertion categories:

- **(a)** `create-issue` redacts title + body (`sk-ant-*` secret → `<REDACTED-TOKEN>`).
- **(b)** `create-issue` exits 3 with `FAILED=true` / `ERROR=redaction:…` when the redactor is missing. Pins exact key literals `FAILED=true` (not `ISSUE_FAILED`).
- **(c)** `upsert-anchor` preserves the HTML anchor marker + all 8 section markers after a >60000-char body-level collapse.
- **(d)** `upsert-anchor` per-section 8000 truncation inserts `[TRUNCATED — <id> exceeded 8000 chars]` on its own line (line-boundary-snapped).
- **(e)** `append-comment` does NOT touch the anchor comment (stub-gh asserts the anchor comment is untouched).
- **(f1) Idempotency**: `upsert-anchor` with exactly one existing anchor comment PATCHes it, emits `UPDATED=true`, creates no new comment on double-call.
- **(f2) Multiple-anchor fail-closed**: `upsert-anchor` with 2+ marker comments exits 2 with `FAILED=true ERROR=multiple anchor comments found (ids: <list>)`.
- **(g) gh-failure redaction**: stub-gh emits a token-bearing stderr on failure → the `FAILED=true ERROR=…` line contains `<REDACTED-TOKEN>` and not the raw token.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/redact-secrets.sh` | Sole outbound scrubber — do NOT bypass or add a parallel redactor. |
| `scripts/tracking-issue-read.sh` | Delegates `append-comment` when invoked with `--issue + --prompt`. |
| `scripts/test-tracking-issue-write.sh` | Regression harness for this script — every behavioral change here must be mirrored in the harness. |
| `skills/implement/references/anchor-comment-template.md` | Defines the 8 canonical section slugs + anchor first-line marker; the arrays here must match. |
| `SECURITY.md` | Documents the outbound-redaction invariant, gh-failure redaction, anchor-skeleton preservation. |

## Security

See `SECURITY.md` "tracking-issue-write.sh outbound path" subsection.
