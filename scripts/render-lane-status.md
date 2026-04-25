# `scripts/render-lane-status.sh` — sibling contract

## Purpose

Format the per-lane attribution record used by `/research`'s Step 3 final-report header. Reads a small KV file, emits two `<NAME>_HEADER=<value>` lines on stdout that SKILL.md Step 3 substitutes into the report. Closes #421.

## Invariants

1. **Pure formatter** — I/O is limited to the single input file path (`--input`) plus stdout/stderr (stdin is unused). No git, no network, no temp files.
2. **3-lane count is hard-coded — standard-mode only** — both header lines emit `3 agents` / `3 reviewers`. The script is used only by the `### Standard` branch of `skills/research/SKILL.md` Step 3 (quick / deep emit literal headers without this script — see #418). The standard-mode 3-lane shape is pinned in the `### Standard` subsections of `skills/research/references/research-phase.md` and `skills/research/references/validation-phase.md`, and is byte-drift-guarded by `scripts/test-research-structure.sh` Checks 14 / 15 (filename literals on the Standard subsection). If the standard-mode lane count ever changes, this script, both references' Standard subsections, and the harness pins must be updated together.
3. **Code lane is hard-coded `✅`** — the Claude code-reviewer subagent has no fallback path (it is the always-on lane in the validation phase). This script does NOT consult the input file for the Code lane.
4. **Status tokens are the single rendering vocabulary** — the case statement in `render_lane()` is the authoritative token list. Tokens that do not match render as `(unknown)` with a stderr warning.
5. **Reasons are sanitized on render** — defense-in-depth. The orchestrator prompt in SKILL.md / phase references is supposed to sanitize before heredoc-write, but `sanitize_reason()` re-applies the same rules so a misformed file never breaks the report markdown.

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

## Collector `STATUS=`→token mapping

`scripts/collect-reviewer-results.sh` emits a per-reviewer `STATUS=` value drawn from the enum `OK | TIMED_OUT | FAILED | EMPTY_OUTPUT | SENTINEL_TIMEOUT | NOT_SUBSTANTIVE`. The orchestrator-side update logic in `skills/research/references/research-phase.md` (Step 1.3) and `skills/research/references/validation-phase.md` (Step 2.4) translates non-`OK` statuses to the lane-status tokens above before writing `lane-status.txt`. The mapping:

| Collector `STATUS` | lane-status token | Reason field |
|-------|----------|----------|
| `OK` | `ok` | empty |
| `TIMED_OUT` / `SENTINEL_TIMEOUT` | `fallback_runtime_timeout` | empty |
| `FAILED` / `EMPTY_OUTPUT` | `fallback_runtime_failed` | sanitized `FAILURE_REASON` |
| `NOT_SUBSTANTIVE` | `fallback_runtime_failed` | sanitized `FAILURE_REASON` |

`NOT_SUBSTANTIVE` shares the `fallback_runtime_failed` token because the operator-facing distinction lives in `FAILURE_REASON` (e.g., "body too thin: 5/200 words after stripping fenced code") rather than in a dedicated render token. Introducing a separate token (e.g., `fallback_content_invalid`) was considered and rejected at design time — it would require updating `render_lane()`, the test harness, and the contract for low signal: the diagnostic already disambiguates cause for the operator. If the renderer ever needs to disambiguate at the header level (e.g., to color-code content vs runtime failures distinctly), introduce a new token in lockstep with the orchestrator-side mapping update.

## Reason sanitization

Applied inside the script after parse, before render:

1. Collapse all whitespace runs (incl. `\n`, `\t`, `\r`) into single spaces.
2. Strip embedded `=` and `|` characters.
3. Trim leading/trailing whitespace.
4. Truncate to 80 characters.

The orchestrator prompt should apply the same rules before writing to `lane-status.txt` (defense-in-depth).

## Output (stdout)

```
RESEARCH_HEADER=3 agents (Cursor: <rendered>, Codex: <rendered>)
VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: <rendered>, Codex: <rendered>)
```

The orchestrator parses these lines via prefix-strip (e.g., `RESEARCH_HEADER="${line#RESEARCH_HEADER=}"`), not `cut -d=`, so values containing `=` are not truncated (the script's sanitization strips `=` from reasons, but the orchestrator should be `=`-safe regardless).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Usage error (missing flag, unknown flag) |
| 2 | I/O failure (input file missing or unreadable) |

## Stderr

Two distinct error paths share this surface:

**Usage errors (exit 1):** the `--input` flag was omitted, or an unknown flag was supplied.

| Trigger | Message | Exit |
|---------|---------|------|
| `--input` flag omitted | `**⚠ render-lane-status: --input is required**` | 1 |
| Unknown flag | `**⚠ render-lane-status: unknown flag: <flag>**` | 1 |
| `--input` flag with no value | `**⚠ render-lane-status: --input requires a value**` | 1 |

**Input-file errors (exit 2):** the `--input` flag was supplied but its path is missing or unreadable.

| Trigger | Message | Exit |
|---------|---------|------|
| Path does not exist (or is not a regular file) | `**⚠ render-lane-status: input file missing**` | 2 |
| Path exists but is not readable | `**⚠ render-lane-status: input file unreadable**` | 2 |

**Per-occurrence warnings (exit 0):** emitted while rendering and do not block exit status.

| Trigger | Message | Exit |
|---------|---------|------|
| Unknown non-empty status token | `**⚠ render-lane-status: unknown status token <token>**` | 0 (per occurrence) |

## Consumers

- `skills/research/SKILL.md` Step 3 — invokes the script and parses both header lines into the final report.
- `skills/research/references/research-phase.md` Step 1.3 — surgically updates the `RESEARCH_*` slice of `lane-status.txt` after `collect-reviewer-results.sh` returns.
- `skills/research/references/validation-phase.md` Step 2 entry + Step 2.4 — surgically updates the `VALIDATION_*` slice (Step 2 entry propagates downgrades from research phase per #421 plan-review FINDING_6; Step 2.4 captures runtime failures).

## Test harness

`scripts/test-render-lane-status.sh` — offline regression harness, 9 fixtures. Wired via the Makefile `test-render-lane-status` target into `test-harnesses`. The harness MUST stay in sync with the case statement in `render_lane()` and the sanitization rules in `sanitize_reason()`. When adding a new status token, add a fixture; when changing the rendered string for an existing token, update the byte-exact assertions.

## Edit-in-sync rules

- **Adding/removing/renaming a status token** → update the case statement in `render_lane()`, the table in this contract, the orchestrator-side mapping in `skills/research/references/research-phase.md` (Step 1.3) and `validation-phase.md` (Step 2.4), and add/update a fixture in `scripts/test-render-lane-status.sh`.
- **Changing the rendered string for an existing token** → update `render_lane()`, the table above, and the byte-exact stdout assertion in the harness fixture.
- **Changing the reason sanitization rules** → update `sanitize_reason()`, the "Reason sanitization" section above, and the orchestrator-side prompt sanitization in SKILL.md Step 0a / phase references' Step 1.3 / 2.4.
- **Changing the lane count or the Code-lane special case** → update both `printf` lines at the bottom of the script, the "Invariants" section above, and the assertion-count literal in the `scripts/test-research-structure.sh` success message (currently `all 15 structural invariants hold`).
