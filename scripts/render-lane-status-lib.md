# `scripts/render-lane-status-lib.sh` — sibling contract

## Purpose

Shared rendering primitives sourced by `scripts/render-lane-status.sh`. Provides `sanitize_reason()` and `render_lane()` so the consumer script has one canonical token vocabulary, one sanitization pass, and one mapping from status token to rendered string.

## Invariants

1. **Sourced, not executed** — no shebang. Top-level contains only function definitions and comments; no commands that would mutate state on `source`. Callers may run under `set -euo pipefail` without interference (both functions use `local` vars and do not toggle shell options).

2. **Status tokens are the single rendering vocabulary** — the case statement in `render_lane()` is the authoritative token list. Tokens that do not match render as `(unknown)` with a stderr warning.

3. **Reasons are sanitized on render** — defense-in-depth. The writer is supposed to sanitize before heredoc-write, but `sanitize_reason()` re-applies the same rules so a misformed file never breaks the report markdown.

## Exported functions

### `sanitize_reason <s>`

Returns the sanitized reason on stdout. Sanitization rules (in order):

1. Strip embedded `=` and `|` characters.
2. Collapse all whitespace runs (incl. `\n`, `\t`, `\r`) into single spaces.
3. Trim leading/trailing whitespace.
4. Truncate to 80 characters.

### `render_lane <status_token> <reason>`

Returns the rendered string on stdout. Maps status tokens per the canonical table below. Emits a stderr warning for unknown non-empty tokens.

## Status tokens (canonical)

| Token | Rendered |
|-------|----------|
| `ok` | `✅` |
| `fallback_binary_missing` | `Claude-fallback (binary missing)` |
| `fallback_probe_failed` | `Claude-fallback (probe failed: <reason>)` (parenthetical omitted when reason empty) |
| `fallback_runtime_timeout` | `Claude-fallback (runtime timeout)` |
| `fallback_runtime_failed` | `Claude-fallback (runtime failed: <reason>)` (parenthetical omitted when reason empty) |
| `` (missing or empty) | `(unknown)` (no stderr warning) |
| anything else, non-empty | `(unknown)` (with stderr warning) |

## Consumers

- `scripts/render-lane-status.sh` — parses the 14-key KV file, calls `render_lane()` for each of the 4 research angles + 3 validation reviewers, emits seven `<NAME>_HEADER=` lines.

## Test harness

The library has no dedicated harness — it is exercised end-to-end by `scripts/test-render-lane-status.sh`, which pins byte-exact stdout of the consumer.

## Edit-in-sync rules

- **Adding/removing/renaming a status token** → update the case statement in `render_lane()` (this file), the canonical table above, the consumer contract (`scripts/render-lane-status.md`), the orchestrator-side mapping in `skills/research/references/research-phase.md` and `validation-phase.md`, and add fixtures in `scripts/test-render-lane-status.sh`.
- **Changing the rendered string for an existing token** → update `render_lane()` and the byte-exact stdout assertions in the consumer harness fixtures.
- **Changing the reason sanitization rules** → update `sanitize_reason()` (this file), the rules section above, and the orchestrator-side prompt sanitization in `research-phase.md` Step 1 and `validation-phase.md` Step 2.
