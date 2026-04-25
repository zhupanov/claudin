# `scripts/render-deep-lane-status.sh` — sibling contract

## Purpose

Format the per-lane attribution record for `/research`'s Step 3 final-report header in **deep mode** (5 research agents + 5 validation reviewers). Reads the same 8-key KV file as the standard renderer (`scripts/render-lane-status.sh`) and emits two `<NAME>_HEADER=<value>` lines on stdout that SKILL.md Step 3 substitutes into the report. Closes #451.

## Invariants

1. **Pure formatter** — I/O is limited to the single input file path (`--input`) plus stdout/stderr (stdin is unused). No git, no network, no temp files.
2. **5-lane count is hard-coded — deep-mode only** — both header lines emit `5 agents` / `5 reviewers`. The script is used only by the `### Deep` branch of `skills/research/SKILL.md` Step 3 (quick emits literal headers without a script; standard uses `render-lane-status.sh`).
3. **Per-tool aggregate semantics** — both Cursor research slots (Cursor-Arch and Cursor-Edge) share the same `RESEARCH_CURSOR_*` token from `lane-status.txt`; same for Codex research slots (Codex-Ext and Codex-Sec) and `RESEARCH_CODEX_*`. This matches the schema's documented aggregate semantics in `skills/research/SKILL.md` Step 0b: `RESEARCH_CURSOR_*` reflects the per-tool aggregate over both Cursor research slots in deep mode.
4. **Code/Code-Sec/Code-Arch lanes are hard-coded `✅`** — the three Claude validation lanes in deep mode have no fallback path (each is an always-on Claude code-reviewer subagent). This script does NOT consult the input file for those three lanes.
5. **Status tokens are the single rendering vocabulary** — the case statement lives in the shared library `scripts/render-lane-status-lib.sh`; this script does not duplicate it. Tokens that do not match render as `(unknown)` with a stderr warning attributed to `render-deep-lane-status` (via `RENDER_LANE_CALLER`).
6. **Reasons are sanitized on render** — defense-in-depth via the shared library's `sanitize_reason()`.

## Library

Sources `scripts/render-lane-status-lib.sh` for `render_lane()` and `sanitize_reason()`. Sets `RENDER_LANE_CALLER="render-deep-lane-status"` before sourcing so the unknown-token stderr warning attributes to this script's basename.

## Input KV schema

```
RESEARCH_CURSOR_STATUS=<token>
RESEARCH_CURSOR_REASON=<short reason text>
RESEARCH_CODEX_STATUS=<token>
RESEARCH_CODEX_REASON=<short reason text>
VALIDATION_CURSOR_STATUS=<token>
VALIDATION_CURSOR_REASON=<short reason text>
VALIDATION_CODEX_STATUS=<token>
VALIDATION_CODEX_REASON=<short reason text>
```

Identical to `render-lane-status.sh`'s schema. All keys are optional. A missing or empty `*_STATUS` renders as `(unknown)`.

## Status tokens

See `scripts/render-lane-status-lib.md` for the canonical token table — this script delegates rendering to the shared library.

## Output (stdout)

```
RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: <rendered>, Cursor-Edge: <rendered>, Codex-Ext: <rendered>, Codex-Sec: <rendered>)
VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: <rendered>, Codex: <rendered>)
```

The orchestrator parses these lines via prefix-strip (e.g., `RESEARCH_HEADER="${line#RESEARCH_HEADER=}"`), not `cut -d=`, so values containing `=` are not truncated (the library's `sanitize_reason` strips `=` from reasons regardless).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error (missing flag, unknown flag) |
| 2 | I/O failure (input file missing or unreadable) |

## Stderr

Symmetric with `render-lane-status.sh`. The script-name prefix in every message is `render-deep-lane-status` (not `render-lane-status`), so log greps attribute correctly.

**Usage errors (exit 1):**

| Trigger | Message |
|---------|---------|
| `--input` flag omitted | `**⚠ render-deep-lane-status: --input is required**` |
| Unknown flag | `**⚠ render-deep-lane-status: unknown flag: <flag>**` |
| `--input` flag with no value | `**⚠ render-deep-lane-status: --input requires a value**` |

**Input-file errors (exit 2):**

| Trigger | Message |
|---------|---------|
| Path does not exist (or is not a regular file) | `**⚠ render-deep-lane-status: input file missing**` |
| Path exists but is not readable | `**⚠ render-deep-lane-status: input file unreadable**` |

**Per-occurrence warnings (exit 0):**

| Trigger | Message |
|---------|---------|
| Unknown non-empty status token | `**⚠ render-deep-lane-status: unknown status token <token>**` |

## Consumers

- `skills/research/SKILL.md` Step 3 `### Deep (RESEARCH_SCALE=deep)` branch — invokes the script and parses both header lines into the final report.

## Test harness

`scripts/test-render-deep-lane-status.sh` — offline regression harness, ≥6 fixtures including phase-segregation guards (research OK + validation fallback, and inverse) as direct bug-fix witnesses for #451. Wired via the Makefile `test-render-deep-lane-status` target into `test-harnesses`.

## Edit-in-sync rules

- **Adding/removing/renaming a status token** → update the case statement in the shared library (`scripts/render-lane-status-lib.sh`), the canonical token table in `scripts/render-lane-status-lib.md`, both consumer contracts (this file + `scripts/render-lane-status.md`), the orchestrator-side mapping in `skills/research/references/research-phase.md` (Step 1.3) and `validation-phase.md` (Step 2.4), and add fixtures in BOTH consumer harnesses.
- **Changing the rendered header strings (e.g., from `5 agents (Claude inline, …)` to a different format)** → update both `printf` lines at the bottom of `scripts/render-deep-lane-status.sh`, the "Output" section above, the literal-header expectations in `skills/research/SKILL.md` Step 3 ### Deep prose, and every fixture's expected stdout in `scripts/test-render-deep-lane-status.sh`.
- **Changing the per-tool aggregate semantics** (e.g., adding per-slot keys to distinguish Cursor-Arch from Cursor-Edge) → this is a schema change, NOT a renderer-only change. Coordinate with `skills/research/SKILL.md` Step 0b, `research-phase.md` Step 1.3, `validation-phase.md` Step 2 entry / 2.4, and update both consumer scripts + harnesses + library tokens together.
- **Changing the Code/Code-Sec/Code-Arch hard-coded `✅`** → this means one of those lanes acquired a fallback path. Update the `printf` line, the "Invariants" section above, and add a new schema key + writer site in the relevant phase reference.
