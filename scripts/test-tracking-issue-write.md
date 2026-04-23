# test-tracking-issue-write.sh contract

## Purpose

Regression harness for `scripts/tracking-issue-write.sh`. Mirrors the stub-`gh` + PATH-override pattern of `scripts/test-redact-secrets.sh`. Phase 1 of umbrella #348.

## Architecture

- `mktemp -d "${TMPDIR:-/tmp}/test-tracking-issue-write-XXXXXX"` tmproot with `trap 'rm -rf "$TMPROOT"' EXIT`.
- Each scenario builds a per-scenario stub-`gh` binary at `$TMPROOT/stub-<tag>/gh` (`chmod +x`) and exports `$BODY_CAPTURE` so the stub can capture `--body-file` content for per-scenario inspection.
- `PATH="$STUB_<tag>:$PATH"` override per-invocation isolates each scenario from others.
- Stub helpers: `build_stub_success` (empty comment list, default happy-path), `build_stub_one_anchor` (one anchor-marker comment in list), `build_stub_multi_anchor` (two anchor-marker comments in list → triggers fail-closed branch), `build_stub_token_stderr` (fail-on-failure path, emits a token on stderr).
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
