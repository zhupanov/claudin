# test-tracking-issue-write.sh contract

## Purpose

Regression harness for `scripts/tracking-issue-write.sh`. Mirrors the stub-`gh` + PATH-override pattern of `scripts/test-redact-secrets.sh`. Phase 1 of umbrella #348.

## Architecture

- `mktemp -d "${TMPDIR:-/tmp}/test-tracking-issue-write-XXXXXX"` tmproot with `trap 'rm -rf "$TMPROOT"' EXIT`.
- Each scenario builds a per-scenario stub-`gh` binary at `$TMPROOT/stub-<tag>/gh` (`chmod +x`) and exports `$BODY_CAPTURE` so the stub can capture `--body-file` content for per-scenario inspection.
- `PATH="$STUB_<tag>:$PATH"` override per-invocation isolates each scenario from others.
- Stub helpers: `build_stub_success` (empty comment list, default happy-path), `build_stub_one_anchor` (one anchor-marker comment in list), `build_stub_multi_anchor` (two anchor-marker comments in list → triggers fail-closed branch), `build_stub_token_stderr` (fail-on-failure path, emits a token on stderr), `build_stub_pagination` (sensitive to `--paginate` in `gh api` argv: without `--paginate` returns only 100 rows with no anchor; with `--paginate` returns 150 rows with the anchor on row 125 — exercises case (o)'s regression guard).
- `assert_contains` / `assert_not_contains` / `assert_equal` helpers for test assertions. PASS/FAIL counters + summary, exit 1 on failure.

## Assertion categories

| ID | What it covers |
|---|---|
| (a) | `create-issue` redacts title + body: inject `sk-ant-*` fixture token, assert `<REDACTED-TOKEN>` appears in captured body, raw token does not leak into stdout or captured body. |
| (b) | `create-issue` exits 3 with `FAILED=true ERROR=redaction:…` when `scripts/redact-secrets.sh` is missing. Uses a fake-tree copy of the script without the redactor sibling. Pins exact key literal `FAILED=true` (confirms the NAMESPACE divergence from `ISSUE_FAILED`). |
| (c) | `upsert-anchor` against >60000-char body preserves HTML anchor marker + all 8 section-open/section-end marker pairs after body-level collapse. |
| (d) | `upsert-anchor` per-section 8000-cap inserts the inline `[TRUNCATED — plan-goals-test exceeded 8000 chars]` marker, and the marker begins on its own line (line-boundary snap). |
| (e) | `append-comment` does NOT write the anchor marker into the posted comment — captured body asserts anchor marker absent; stdout asserts `COMMENT_ID=` (not `ANCHOR_COMMENT_ID=`). |
| (f1) | Idempotency: `upsert-anchor` against a stubbed comment-list with exactly one anchor-marker comment PATCHes that comment (id echoed on stdout), emits `UPDATED=true`, does not create a new comment. |
| (f2) | Multiple-anchor fail-closed: `upsert-anchor` against a stubbed comment-list with two anchor-marker comments exits 2 with `FAILED=true ERROR=multiple anchor comments found (ids: 5001,5002)`. |
| (g) | gh-failure redaction: stub gh emits a token-bearing stderr on failure path → the `ERROR=…` line on stdout contains `<REDACTED-TOKEN>` and does not leak the raw token. |
| (h) | `tracking-issue-write.sh` startup-guard: running a copy of the script in a fake tree without the sibling `anchor-section-markers.sh` helper exits 1 with `FAILED=true ERROR=missing helper: …`. |
| (i) | `SECTION_MARKERS ⊆ COLLAPSE_PRIORITY` invariant (set-membership): every slug in `SECTION_MARKERS` (sourced from `anchor-section-markers.sh`) appears in `tracking-issue-write.sh`'s inline `COLLAPSE_PRIORITY` array. Drift would silently de-prioritize a section from body-level collapse. |
| (j) | `rename` subcommand: idempotency (no-op when title already at target state emits `RENAMED=false`), strip-exactly-one (only one prefix is stripped on transition; stacked residue is preserved verbatim), redaction (sk-ant fixture in title is replaced with `<REDACTED-TOKEN>` in the outbound `gh issue edit` arg and stdout), and invalid `--state` rejection (exits 1 with full canonical `ERROR=invalid --state: <value>`). |
| (k) | `upsert-anchor` preserves the seed-only visible placeholder line: a non-section content line inserted between the first-line anchor marker and the first `<!-- section:... -->` open marker (the placeholder emitted by `scripts/assemble-anchor.sh` when every fragment is empty per the lenient predicate, issue #431) survives the redact + truncate publish path verbatim, on its own line, in the captured outbound body. Pins position invariants: line 1 = anchor marker, line 2 = placeholder, line 3 = first section open marker. |
| (l) | `find-anchor` zero anchors: stub returns an empty comment list (via `build_stub_success`) → `find-anchor --issue 42` emits exactly `ANCHOR_COMMENT_ID=` (empty value) on its own line, no `FAILED=true`, exit 0. |
| (m) | `find-anchor` one anchor: stub returns one v1-marker comment (via `build_stub_one_anchor`) → `find-anchor --issue 42` emits `ANCHOR_COMMENT_ID=5001` on stdout, no `FAILED=true`, exit 0. |
| (n) | `find-anchor` multi-anchor fail-closed: stub returns two v1-marker comments (via `build_stub_multi_anchor`) → `find-anchor --issue 42` exits 2 with `FAILED=true ERROR=multiple anchor comments found (ids: 5001,5002)`. Asserts no `ANCHOR_COMMENT_ID=` line is emitted on the failure path (consumers must check `FAILED=true` first). |
| (o) | `find-anchor` pagination across >100 comments — regression guard for #654: `build_stub_pagination` is sensitive to whether `--paginate` is present in `gh api`'s argv. WITHOUT `--paginate`, returns only the first 100 rows (no anchor among them); WITH `--paginate`, returns all 150 rows with the anchor on row 125. Asserts `find-anchor` returns `ANCHOR_COMMENT_ID=5125` (the late-page anchor) — a future edit that drops `--paginate` from `list_anchor_comments` would fail this assertion because the stub would return the no-anchor first-page-only payload. |

## Fixture tokens

- `SK_TOKEN='sk-''ant-abcdefghijklmnopqrstuvwxyz0123456789ABCD'` — split prefix in source to defuse GitHub's sk-* secret-scanner heuristic. Shape matches `redact-secrets.sh` regex so redaction exercises the real path.

## Makefile wiring

Listed in `Makefile`'s `test-harnesses:` prerequisite and `.PHONY:` declaration. Standalone: `make test-tracking-issue-write`.

## Conventions

Bash 3.2-safe (indexed arrays only; no associative arrays, no `mapfile`).

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/tracking-issue-write.sh` | The script under test. Any behavioral change there must be mirrored in a harness assertion here. |
| `scripts/redact-secrets.sh` | Sibling outbound scrubber exercised by assertions (a) and (g). |
| `scripts/test-redact-secrets.sh` | Pattern precedent for stub-gh + PATH-override + assert_contains helpers. |
| `Makefile` | Target `test-tracking-issue-write` and `test-harnesses` prereq entry — both must remain in sync when renaming the harness. |
