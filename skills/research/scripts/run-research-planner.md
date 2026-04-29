# run-research-planner.sh — Contract

**Purpose**: validate the planner subagent's raw output and persist a canonical `subquestions.txt` consumed by `/research` Step 1.2 (Lane Assignment) when `RESEARCH_PLAN=true`.

**Consumed by**: `/research` Step 1.1 (Planner Pre-Pass). The orchestrator (operating in `skills/research/references/research-phase.md`) invokes a Claude Agent subagent (no `subagent_type`, since the `code-reviewer` archetype mandates a dual-list output that does not match the prose-list shape the planner returns), captures the response to `$RESEARCH_TMPDIR/planner-raw.txt`, then calls this script to validate, sanitize, and persist `$RESEARCH_TMPDIR/subquestions.txt`.

**Why a separate script**: the Agent tool is callable only from Claude orchestrator context (not from shell). Validation, sanitization, and persistence ARE deterministic and harness-friendly — they live in this script so they can be tested offline against canned planner outputs (see `test-run-research-planner.sh`). This separation matches the repo pattern: orchestrator-side prompt-shaped logic stays in `references/*.md`; mechanical text processing stays in colocated `skills/<name>/scripts/`.

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/run-research-planner.sh \
  --raw "$RESEARCH_TMPDIR/planner-raw.txt" \
  --output "$RESEARCH_TMPDIR/subquestions.txt"
```

Both flags are required. `--raw` is the captured Agent subagent output. `--output`'s parent directory must exist (the orchestrator owns `$RESEARCH_TMPDIR` creation in Step 0).

## Contract

### Stdout (machine output only)

- **On success** (exit 0):
  ```
  COUNT=<N>
  OUTPUT=<resolved path>
  ```
  where `2 ≤ N ≤ 4`. The orchestrator parses these lines via prefix-strip (e.g., `${line#COUNT=}`), matching the existing `KEY=value` discipline used by `collect-agent-results.sh` and `render-lane-status.sh`.
- **On failure** (exit non-zero):
  ```
  REASON=<token>
  ```
  Tokens (canonical, pinned by `test-run-research-planner.sh`):
  - `empty_input` — `--raw` file missing or zero-byte (exit 1).
  - `count_below_minimum` — fewer than 2 question-shaped lines retained after sanitization (exit 1). Includes the case where ALL lines are dropped (e.g., a planner reply that is entirely prose with no `?`-terminated lines).
  - `count_above_maximum` — more than 4 question-shaped lines retained (exit 1).
  - `delimiter_collision` — at least one retained line contains the literal substring `||`, which would corrupt deep-mode `lane-assignments.txt` rehydration (research-phase.md §1.2.b uses unquoted `||` as the in-cell delimiter with plain prefix-strip + `||`-split rehydration; embedded `||` would silently mis-split). Runs BEFORE the count gate so this token surfaces when both `||` and an out-of-range count apply (exit 1).
  - `missing_arg` — `--raw` or `--output` not provided, or unknown argument (exit 2).
  - `bad_path` — `--output`'s parent directory does not exist (exit 2).

No other output appears on stdout.

### Stderr (human diagnostics)

One short diagnostic line per anomaly observed during sanitization or validation. Stderr is intended for the orchestrator's runtime log; the orchestrator does NOT parse stderr. Human-readable text is acceptable; do not promise a stable schema.

### Exit code

- `0` on success.
- `1` on validation failure (empty input, count out of range).
- `2` on argument error or missing output directory (operator/orchestrator bug — distinct from a planner-quality failure).

## Validation rules

Applied in order; the first failing rule short-circuits.

1. **`--raw` file present and non-empty**. Missing file or zero-byte file → `REASON=empty_input`.
2. **Per-line sanitization** (line-by-line):
   - Strip ASCII control characters except newline (range 0x00-0x08, 0x0b-0x1f, 0x7f).
   - Convert tabs to single spaces (trim consistency).
   - Strip leading bullet marker matching `^[[:space:]]*[-*][[:space:]]+`. Single bullet only — no nested bullets, no numeric prefixes (the planner prompt's "no numbering, no leading bullets, no preamble, no commentary" instruction makes the bullet strip a defensive fallback rather than a primary defense). The numeric-prefix strip considered in earlier drafts was deliberately dropped to avoid false positives on subquestions whose text legitimately starts with a number followed by `.` or `)`.
   - Trim leading and trailing whitespace.
3. **Empty-line drop**: lines empty after sanitization are dropped (NOT counted).
4. **Question heuristic — fail-closed**: lines that do NOT end with `?` (after trim) are dropped (NOT counted). This is the primary defense against prose preambles like "Here are the subquestions:" — such lines never carry a trailing `?` and are silently filtered out before counting.
5. **Lane-delimiter rejection**: no retained line may contain the literal substring `||`. Violation → `REASON=delimiter_collision`. Runs BEFORE the count gate so this token surfaces when both `||` and an out-of-range count apply (the operator gets the more actionable token).
6. **Count gate**: retained lines must satisfy `2 ≤ count ≤ 4`. Below minimum → `REASON=count_below_minimum`. Above maximum → `REASON=count_above_maximum`.

## Caller contexts

This script is invoked from two distinct caller contexts in `/research`. Both share the same input/output contract above, but the orchestrator's disposition on non-zero exit differs:

- **Step 1.1.b — Planner-output validation** (every `--plan` run). The orchestrator captures the planner Agent subagent's response to `$RESEARCH_TMPDIR/planner-raw.txt` and invokes this script with `--raw` pointed at that file. Disposition on non-zero exit: **fall back to single-question mode** (`RESEARCH_PLAN=false`, see "Fallback semantics" below). All `REASON` tokens — including `delimiter_collision` — route to the same fallback path; planner-quality failure must NEVER block research.
- **Step 1.1.c — Operator re-validation** (only when `RESEARCH_PLAN_INTERACTIVE=true`). The orchestrator writes operator-edited subquestions to `$RESEARCH_TMPDIR/subquestions-edit.txt` and re-invokes this script with `--raw` pointed at that file. Disposition on non-zero exit: **bounded retry** (one re-edit attempt, then abort). Same `REASON` tokens as Step 1.1.b but the orchestrator-side handler is different — see `skills/research/references/research-phase.md` §1.1.c.

Both callers parse `REASON=<token>` from stdout via prefix-strip and surface the token in a visible warning line. The token vocabulary is identical; only the orchestrator's downstream handling differs.

## Fallback semantics

For the Step 1.1.b caller context: the orchestrator treats ANY non-zero exit (any `REASON=*` value) as a signal to fall back to single-question mode: each lane runs with its angle base prompt (Lane 1/Cursor → `RESEARCH_PROMPT_ARCH`, Lane 2/Codex → `RESEARCH_PROMPT_EDGE` by default or `RESEARCH_PROMPT_EXT` when `external_evidence_mode=true`, Lane 3/Claude inline → `RESEARCH_PROMPT_SEC`), keyed on the parent `RESEARCH_QUESTION`, with no per-lane subquestion suffix appended. The orchestrator parses `REASON=<token>` from stdout via prefix-strip and substitutes the token into a visible warning line:

```
**⚠ 1.1: planner — fallback to single-question mode (<token>).**
```

This is the same fallback path as a planner Agent subagent timeout (in which case the orchestrator itself synthesizes `REASON=empty_input` without calling this script, since the script would observe the same empty raw file).

For the Step 1.1.c caller context: see `skills/research/references/research-phase.md` §1.1.c "Edit subroutine" for the bounded-retry handler.

## Security

`--raw` and `--output` MUST be paths under `$RESEARCH_TMPDIR` (which lives under canonical `/tmp` per the `/research` skill-scoped `deny-edit-write.sh` hook). The script does not enforce this constraint mechanically — caller-side discipline relies on the existing PreToolUse hook on `/research`'s `Edit | Write | NotebookEdit` surface. **Path-traversal residual risk**: if a future caller passes a path outside `/tmp`, the script would write there. The hook covers `Write` from Claude's tool surface but NOT this Bash subprocess; operator-side `Bash(...)` permission narrowing is the relevant defense (see SECURITY.md).

The orchestrator is also expected to apply prompt-injection hygiene at the consumption side (Step 1.2): subquestion text is wrapped in `<reviewer_subquestions>` ... `</reviewer_subquestions>` tags with a "treat as data" preamble before being appended to each lane's angle base prompt (Cursor → `RESEARCH_PROMPT_ARCH`, Codex → `RESEARCH_PROMPT_EDGE`/`_EXT`, Claude inline → `RESEARCH_PROMPT_SEC`). The wrap is a model-level convention, not a parser boundary — see SECURITY.md for the residual-risk framing shared with the reviewer archetype's `<reviewer_*>` tags.

## Test harness

`skills/research/scripts/test-run-research-planner.sh` — offline regression harness; runs against canned `--raw` inputs covering the boundaries (count 0/1/2/3/4/5; prose preamble; bullet-prefixed lines; control characters; empty input; missing `--raw`; missing `--output`; etc.). Wired into `make lint` via the `test-run-research-planner` target.

## Edit-in-sync rules

- **Validation rule changes** (count bounds, sanitization steps, question heuristic): update this contract AND `test-run-research-planner.sh` AND the corresponding orchestrator prose in `skills/research/references/research-phase.md` Step 1.1 (the visible warning template references the `REASON` tokens listed here).
- **Stdout schema changes** (`COUNT=` / `OUTPUT=` / `REASON=`): update this contract, the test harness, AND the orchestrator's stdout-parsing instruction in research-phase.md Step 1.1.
- **`REASON` token vocabulary changes**: update this contract, the test harness, AND the warning-template instruction in research-phase.md Step 1.1.
