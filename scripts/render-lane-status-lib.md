# `scripts/render-lane-status-lib.sh` — sibling contract

## Purpose

Shared rendering primitives sourced by both `scripts/render-lane-status.sh` (standard mode, 3-lane) and `scripts/render-deep-lane-status.sh` (deep mode, 5-lane). Provides `sanitize_reason()` and `render_lane()` so the two consumer scripts share one canonical token vocabulary, one sanitization pass, and one mapping from status token to rendered string. Closes #451.

## Invariants

1. **Sourced, not executed** — no shebang. Top-level contains only function definitions and comments; no commands that would mutate state on `source`. Callers may run under `set -euo pipefail` without interference (both functions use `local` vars and do not toggle shell options).

2. **Status tokens are the single rendering vocabulary** — the case statement in `render_lane()` is the authoritative token list. Tokens that do not match render as `(unknown)` with a stderr warning attributed to the caller.

3. **Caller-attributed stderr warnings** — the unknown-token warning uses `${RENDER_LANE_CALLER:-render-lane-status}` so each consumer script (`render-lane-status.sh` / `render-deep-lane-status.sh`) attributes the warning to its own basename. The default (`render-lane-status`) preserves byte-stable historical behavior if a caller forgets to set the variable.

4. **Reasons are sanitized on render** — defense-in-depth. The writer is supposed to sanitize before heredoc-write, but `sanitize_reason()` re-applies the same rules so a misformed file never breaks the report markdown.

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
| anything else, non-empty | `(unknown)` (with stderr warning attributed to `$RENDER_LANE_CALLER`) |

## Caller protocol

Each consumer script sets `RENDER_LANE_CALLER` to its own basename BEFORE sourcing this file:

```bash
RENDER_LANE_CALLER="render-lane-status"
source "$(dirname "$0")/render-lane-status-lib.sh"
```

The deep consumer:

```bash
RENDER_LANE_CALLER="render-deep-lane-status"
source "$(dirname "$0")/render-lane-status-lib.sh"
```

Without this convention, an unknown-token warning emitted from the deep helper would mis-attribute the failure to `render-lane-status`, confusing operators grepping logs.

## Consumers

- `scripts/render-lane-status.sh` (standard mode) — parses 8-key KV file, calls `render_lane()` for each of the 4 external lanes, emits 3-agent / 3-reviewer headers.
- `scripts/render-deep-lane-status.sh` (deep mode) — parses the same 8-key KV file, calls `render_lane()` for the 4 external lanes (Cursor and Codex slots in research aggregate over both Arch+Edge / Ext+Sec respectively per `skills/research/SKILL.md` Step 0b), emits 5-agent / 5-reviewer headers with the three Claude validation lanes (Code, Code-Sec, Code-Arch) hard-coded as `✅`.

## Test harnesses

The library has no dedicated harness — it is exercised end-to-end by:

- `scripts/test-render-lane-status.sh` (10 fixtures) — pins byte-exact stdout of the standard-mode consumer.
- `scripts/test-render-deep-lane-status.sh` (≥ 6 fixtures) — pins byte-exact stdout of the deep-mode consumer, including phase-segregation guards (research OK + validation fallback, and inverse) as direct bug-fix witnesses for #451.

Both consumer harnesses indirectly verify the library by checking the rendered output strings.

## Edit-in-sync rules

- **Adding/removing/renaming a status token** → update the case statement in `render_lane()` (this file), the canonical table above, both consumer contracts (`scripts/render-lane-status.md`, `scripts/render-deep-lane-status.md`), the orchestrator-side mapping in `skills/research/references/research-phase.md` (Step 1.3) and `validation-phase.md` (Step 2.4), and add fixtures in BOTH consumer harnesses.
- **Changing the rendered string for an existing token** → update `render_lane()` and the byte-exact stdout assertions in both consumer harnesses' fixtures.
- **Changing the reason sanitization rules** → update `sanitize_reason()` (this file), the rules section above, and the orchestrator-side prompt sanitization in SKILL.md Step 0a / `research-phase.md` Step 1.3 / `validation-phase.md` Step 2 entry, render-failure handlers, and Step 2.4.
- **Changing the caller-attributed warning convention** → update both consumer scripts' `RENDER_LANE_CALLER=` settings, both consumer contracts, and both harness unknown-token fixtures.
