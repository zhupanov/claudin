# `scripts/test-render-deep-lane-status.sh` — sibling contract

## Purpose

Offline regression harness for `scripts/render-deep-lane-status.sh`. Asserts byte-exact stdout for happy-path cases and the contract's behavior under error conditions (exit code + stderr) for missing-input, unknown-token, and usage-error fixtures.

**Phase-segregation guard fixtures (F2 + F3)** are the direct bug-fix witnesses for #451: they verify that a validation-only fallback does NOT taint research-phase attribution (and vice versa), which is the cross-phase bug the deep renderer was introduced to fix.

## Invocation

```
make test-render-deep-lane-status
```

or directly:

```
bash scripts/test-render-deep-lane-status.sh
```

Exit 0 on all-pass; exit 1 on any failed assertion (with detailed expected/actual diff on stderr).

## Fixture cases (9)

1. **F1 — happy path** — all four lanes report `ok`. Asserts `RESEARCH_HEADER=5 agents (Claude inline, Cursor-Arch: ✅, Cursor-Edge: ✅, Codex-Ext: ✅, Codex-Sec: ✅)` and `VALIDATION_HEADER=5 reviewers (Code: ✅, Code-Sec: ✅, Code-Arch: ✅, Cursor: ✅, Codex: ✅)`.
2. **F2 — phase-segregation guard: research OK, validation fallback (BUG WITNESS for #451)** — `RESEARCH_*=ok` while `VALIDATION_CURSOR_STATUS=fallback_runtime_failed`. Asserts research header keeps Cursor-Arch + Cursor-Edge as `✅` (not retroactively tainted by the validation-only fallback) while validation header shows the runtime-failed reason.
3. **F3 — phase-segregation guard: research fallback, validation OK (BUG WITNESS for #451)** — inverse of F2. `RESEARCH_CURSOR_STATUS=fallback_runtime_timeout` while validation is OK. Asserts both Cursor-Arch and Cursor-Edge research slots render the per-tool aggregate fallback while validation `Cursor:` stays `✅`.
4. **F4 — mixed fallback reasons with sanitization** — exercises every fallback variant (`fallback_binary_missing`, `fallback_probe_failed` with reason, `fallback_runtime_failed` with reason containing `=`, `|`, and whitespace runs that must be sanitized, `fallback_runtime_timeout`). Reason after sanitization fits under 80 chars (no truncation).
   - **F4b** — runtime-failed reason longer than 80 chars must truncate to exactly 80.
5. **F5 — unknown status token** — a non-canonical token like `fallback-binary-missing` (hyphens instead of underscores) renders as `(unknown)` and emits a stderr warning. **Critically**, the warning must say `**⚠ render-deep-lane-status: unknown status token <token>**` (deep-attributed, not standard-attributed) — this assertion locks in #451 FINDING_2's caller-name parameterization. If `RENDER_LANE_CALLER` is dropped or mis-set, this fixture fails.
6. **F6 — missing input** — a non-existent `--input` path produces exit code 2 and a stderr line containing `render-deep-lane-status: input file missing`.
7. **F7 — usage error: --input flag omitted** — exit 1 with stderr containing `render-deep-lane-status: --input is required`.
   - **F7b** — unknown flag (e.g., `--bogus`) → exit 1 with stderr containing `render-deep-lane-status: unknown flag: --bogus`.

The "9 fixture cases" count is the public-surface count; F4 and F7 each carry one sub-case (F4b for truncation, F7b for the unknown-flag variant of usage error).

## Wired via

- `Makefile` `test-render-deep-lane-status` target.
- `Makefile` `test-harnesses` aggregate target prerequisite list.
- `Makefile` `.PHONY` declaration.
- `agent-lint.toml` `exclude` array (Makefile-only harness; no `SKILL.md` reference, so the dead-script detector would false-flag without the entry).

## Edit-in-sync rules

- **Adding a status token in `render-lane-status-lib.sh`** → add a fixture in BOTH this harness and `scripts/test-render-lane-status.sh`, plus update both consumer contracts (`render-lane-status.md`, `render-deep-lane-status.md`) and the library contract.
- **Changing the per-tool aggregate semantics** (introducing per-slot keys for the two Cursor / two Codex research slots) → schema-level change. Update `skills/research/SKILL.md` Step 0b, both phase references, the deep renderer's `printf` lines, and ALL fixtures here that exercise the aggregate (F2, F3, F4, F4b, F5).
- **Changing the rendered header strings** (e.g., dropping `Claude inline`, renaming `Code-Sec` → `Code-Architecture`, etc.) → update the deep renderer's two `printf` lines, every fixture's expected stdout in this harness, and the literal-header references in `skills/research/SKILL.md` Step 3 ### Deep prose.
- **Changing the deep-attributed warning convention** (e.g., dropping `RENDER_LANE_CALLER`) → fixture F5's `assert_stderr_contains` will fail loudly. Coordinate with the library, both consumer scripts, and `scripts/render-lane-status-lib.md`.
- **Changing the exit-code or stderr contract** → F5 (unknown token, exit 0 + stderr warning), F6 (missing input, exit 2), F7/F7b (usage errors, exit 1) cover all error paths. Update the corresponding fixtures and the "Stderr" / "Exit codes" sections of `scripts/render-deep-lane-status.md`.
