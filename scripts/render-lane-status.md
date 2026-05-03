# `scripts/render-lane-status.sh` — sibling contract

## Purpose

Format the per-lane attribution record used by `/research`'s Step 3 final-report header. Reads a small KV file (4 research angles + 3 validation reviewers), emits seven `<NAME>_HEADER=<value>` lines on stdout that SKILL.md Step 3 substitutes into the report.

## Library

Sources `scripts/render-lane-status-lib.sh` for `render_lane()` and `sanitize_reason()`. The shared library is the single source of truth for the status-token vocabulary and reason-sanitization rules.

## Invariants

1. **Pure formatter** — I/O is limited to the single input file path (`--input`) plus stdout/stderr. No git, no network, no temp files.
2. **Lane count is fixed** — 4 research angles (architecture / edge cases / external comparisons / security) + 3 validation reviewers (Code / Cursor / Codex). One renderer; no scale or mode branching.
3. **All lanes are honest** — including the Code reviewer, which is now rendered from `VALIDATION_CODE_STATUS` like every other lane (no hard-coded `✅`).
4. **Status tokens are the single rendering vocabulary** — the case statement lives in the shared library `scripts/render-lane-status-lib.sh`; this script does not duplicate it. Tokens that do not match render as `(unknown)` with a stderr warning.
5. **Reasons are sanitized on render** — defense-in-depth via the shared library's `sanitize_reason()`.

## Input KV schema

```
RESEARCH_ARCH_STATUS=<token>
RESEARCH_ARCH_REASON=<short reason text>
RESEARCH_EDGE_STATUS=<token>
RESEARCH_EDGE_REASON=<short reason text>
RESEARCH_EXT_STATUS=<token>
RESEARCH_EXT_REASON=<short reason text>
RESEARCH_SEC_STATUS=<token>
RESEARCH_SEC_REASON=<short reason text>
VALIDATION_CODE_STATUS=<token>
VALIDATION_CODE_REASON=<short reason text>
VALIDATION_CURSOR_STATUS=<token>
VALIDATION_CURSOR_REASON=<short reason text>
VALIDATION_CODEX_STATUS=<token>
VALIDATION_CODEX_REASON=<short reason text>
```

All keys are optional. A missing or empty `*_STATUS` renders as `(unknown)`.

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

## Reason sanitization

Applied inside the shared library `scripts/render-lane-status-lib.sh` (function `sanitize_reason`):

1. Strip embedded `=` and `|` characters.
2. Collapse all whitespace runs (incl. `\n`, `\t`, `\r`) into single spaces.
3. Trim leading/trailing whitespace.
4. Truncate to 80 characters.

The orchestrator prompt should apply the same rules before writing to `lane-status.txt` (defense-in-depth).

## Output (stdout)

```
RESEARCH_ARCH_HEADER=Architecture: <rendered>
RESEARCH_EDGE_HEADER=Edge cases: <rendered>
RESEARCH_EXT_HEADER=External comparisons: <rendered>
RESEARCH_SEC_HEADER=Security: <rendered>
VALIDATION_CODE_HEADER=Code: <rendered>
VALIDATION_CURSOR_HEADER=Cursor: <rendered>
VALIDATION_CODEX_HEADER=Codex: <rendered>
```

The orchestrator parses these lines via prefix-strip (e.g., `RESEARCH_ARCH_HEADER="${line#RESEARCH_ARCH_HEADER=}"`), not `cut -d=`, so values containing `=` are not truncated.

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error (missing flag, unknown flag) |
| 2 | I/O failure (input file missing or unreadable) |

## Stderr

| Trigger | Message | Exit |
|---------|---------|------|
| `--input` flag omitted | `**⚠ render-lane-status: --input is required**` | 1 |
| Unknown flag | `**⚠ render-lane-status: unknown flag: <flag>**` | 1 |
| `--input` flag with no value | `**⚠ render-lane-status: --input requires a value**` | 1 |
| Input path does not exist | `**⚠ render-lane-status: input file missing**` | 2 |
| Input path is not readable | `**⚠ render-lane-status: input file unreadable**` | 2 |
| Unknown non-empty status token | `**⚠ render-lane-status: unknown status token <token>**` | 0 (per occurrence) |

## Consumers

- `skills/research/SKILL.md` Step 3 — invokes the script and parses all seven header lines into the final report.
- `skills/research/references/research-phase.md` Step 1 — surgically updates the `RESEARCH_*` per-angle slice of `lane-status.txt` after each lane settles.
- `skills/research/references/validation-phase.md` Step 2 — surgically updates the `VALIDATION_*` slice for Code/Cursor/Codex.

## Test harness

`scripts/test-render-lane-status.sh` — offline regression harness. Wired via the Makefile `test-render-lane-status` target into `test-harnesses`. The harness MUST stay in sync with the `render_lane()` case statement and the `sanitize_reason()` rules.

## Edit-in-sync rules

- **Adding/removing/renaming a status token** → update the case statement in the shared library (`scripts/render-lane-status-lib.sh`), the canonical token table in `scripts/render-lane-status-lib.md`, this contract, the orchestrator-side mapping in `research-phase.md` and `validation-phase.md`, and add fixtures in `scripts/test-render-lane-status.sh`.
- **Changing the rendered string for an existing token** → update the library's `render_lane()` case statement and the byte-exact stdout assertion in the harness.
- **Changing the lane count or per-angle key names** → update the case statement in `scripts/render-lane-status.sh`, the printf block at the bottom, the "Invariants" section, the orchestrator-side writers in `research-phase.md` Step 1 and `validation-phase.md` Step 2, and the harness fixtures.
