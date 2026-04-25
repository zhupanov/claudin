# `scripts/test-render-lane-status.sh` — sibling contract

## Purpose

Offline regression harness for `scripts/render-lane-status.sh`. Asserts byte-exact stdout for happy-path cases and the contract's behavior under error conditions (exit code + stderr) for missing-input and unknown-token fixtures.

## Invocation

```
make test-render-lane-status
```

or directly:

```
bash scripts/test-render-lane-status.sh
```

Exit 0 on all-pass; exit 1 on any failed assertion (with detailed expected/actual diff on stderr).

## Fixture cases (9)

1. **happy path** — all four lanes report `ok`. Asserts `RESEARCH_HEADER=3 agents (Cursor: ✅, Codex: ✅)` and `VALIDATION_HEADER=3 reviewers (Code: ✅, Cursor: ✅, Codex: ✅)`.
2. **all-binary-missing** — every external lane reports `fallback_binary_missing`.
3. **mixed** — one `ok`, one `fallback_runtime_timeout`, two `fallback_binary_missing`.
4. **probe-failed with reason** — reason text is preserved (no special chars to sanitize away).
5. **probe-failed without reason** — empty `*_REASON` value renders as bare `Claude-fallback (probe failed)` (no parenthetical).
6. **runtime-timeout** — token renders the canonical `Claude-fallback (runtime timeout)` string.
7. **runtime-failed with multi-character-class reason (sanitization)** — embedded `|` and `=` characters are stripped, whitespace runs are collapsed (post-strip).
   - **7b**: a reason longer than 80 characters is truncated to exactly 80.
8. **unknown-status token** — a token like `fallback-binary-missing` (with hyphens instead of underscores) renders as `(unknown)` and emits a stderr warning containing `unknown status token <token>`.
9. **missing-input** — a non-existent `--input` path produces exit code 2 and a stderr line containing `render-lane-status: input file missing`.

The "9 fixture cases" count is documented as the public-surface count even though fixture 7 has a 7b sub-case for the truncation property; both 7 and 7b exercise the same status token (`fallback_runtime_failed`).

## Wired via

- `Makefile` `test-render-lane-status` target.
- `Makefile` `test-harnesses` aggregate target prerequisite list.
- `Makefile` `.PHONY` declaration.
- `agent-lint.toml` `exclude` array (Makefile-only harness; no `SKILL.md` reference, so the dead-script detector would false-flag without the entry).

## Edit-in-sync rules

- **Adding a status token in `render-lane-status.sh`** → add a fixture in this harness, plus update the table in `scripts/render-lane-status.md` and the orchestrator-side mapping in `skills/research/references/{research,validation}-phase.md`.
- **Changing the rendered string for an existing token** → update the byte-exact stdout assertion in the corresponding fixture, plus the table in `scripts/render-lane-status.md`.
- **Changing the reason sanitization rules** → fixture 7 (sanitization) and 7b (truncation) cover this; update both if rules change. Also update `sanitize_reason()` in `render-lane-status.sh` and the "Reason sanitization" section of its sibling `.md`.
- **Changing the exit-code or stderr contract** → fixture 8 (unknown token, exit 0 + stderr warning) and fixture 9 (missing input, exit 2 + stderr) cover both error paths. Update them when the script's stderr message text or exit codes change.
