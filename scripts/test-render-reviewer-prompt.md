# scripts/test-render-reviewer-prompt.sh

## Purpose

Offline regression harness for `scripts/render-reviewer-prompt.sh`. Runs in CI (`make test-harnesses`) and locally (`make lint`). No network, no git state, no external tools.

## Invariants

- **Happy-path coverage**: rendered prompt contains all five focus-area headings, the XML-wrapped untrusted-context with question + findings fixture content, the literal-delimiter sentence, the `NO_ISSUES_FOUND` sentinel (and **not** the archetype default `No in-scope issues found.`), each in-scope instruction line as its own `- <line>` bullet, the OOS section's research-validation default stub, "Do NOT modify files", and no remaining `{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` / `{OUTPUT_INSTRUCTION}` placeholders.
- **Negative coverage**: missing required flag → non-zero with diagnostic; unreadable file → non-zero with diagnostic; mocked template missing BEGIN/END markers → non-zero; mocked template missing the sentinel-override target sentence → non-zero; mocked template with an extra unsubstituted placeholder → non-zero.
- **Static integration check**: `skills/research/references/validation-phase.md` references `render-reviewer-prompt.sh` at least twice (one per Cursor / Codex lane). Pinned by `grep -Fc`, so renaming the helper would also fail this assertion.

## Test harness

This file is itself the test harness. Add new assertions in-place; do NOT split into multiple harnesses unless a clear coverage axis warrants separation. Per-test failure messages MUST name the assertion that failed.

## Edit-in-sync rules

- **`scripts/render-reviewer-prompt.sh`**: any new flag or output behavior should be reflected in a new harness assertion before merge.
- **`skills/research/references/validation-phase.md`**: the static integration check enforces that both Cursor and Codex lanes invoke the renderer. If a third caller is added, raise the threshold or split into per-lane assertions.
- **`Makefile`**: harness is wired into `.PHONY`, `test-harnesses`, and a per-target recipe at lines 4 / 14 / 117 (or current equivalent positions). The Makefile recipe runs `bash scripts/test-render-reviewer-prompt.sh`.

## Exit codes

| Exit | Cause |
|------|-------|
| 0 | All assertions pass; harness prints `PASS: ...` summary line. |
| 1 | Any assertion fails; harness prints `FAIL: ...` line on stderr naming the assertion. |
