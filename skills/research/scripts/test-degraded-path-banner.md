# test-degraded-path-banner.sh — contract

**Consumer**: `make lint` (via the `test-degraded-path-banner` Makefile target).

**Purpose**: offline regression harness for the /research Step 1.5 reduced-diversity banner contract introduced by issue #506. Validates two surfaces:

1. **Reference-impl correctness**: a bash mirror of the `research-phase.md` §1.5 banner-emission formula, driven by synthetic `lane-status.txt` fixtures across 4 cases × 2 scales (standard, deep). Asserts banner literal + integer substitutions match the expected output, including the all-ok negative case and a missing-fixture defensive default.
2. **Prose pins**: greps `skills/research/references/research-phase.md` for the byte-exact banner literal, both per-scale `N_FALLBACK` formulas, and the `research-report.txt` mention in the §1.5 preamble (BOTH-outputs contract).

**Wired into**: `Makefile` `test-harnesses` target via `test-degraded-path-banner` target. Both `.PHONY` (line 4) and the `test-harnesses` dependency list (line 14) carry the target name.

**Fixtures schema** (synthesized in-process under a `mktemp -d` tmpdir; the harness writes them and tears them down on exit):

```
RESEARCH_CURSOR_STATUS=<ok|fallback_*|empty>
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=<ok|fallback_*|empty>
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
```

The harness only reads the two `RESEARCH_*_STATUS` keys (validation-phase keys are not consumed by the §1.5 banner — they belong to Step 2 / Step 3 attribution). The token vocabulary mirrors `scripts/render-lane-status-lib.sh` ("ok" is the sole non-fallback token; every other value, including empty, is treated as a fallback).

**Per-scale formulas under test** (mirrors of the `research-phase.md` §1.5 banner preamble):

- **Standard**: `LANE_TOTAL=2`, `N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)` ∈ {0, 1, 2}.
- **Deep**: `LANE_TOTAL=4`, `N_FALLBACK = 2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)` ∈ {0, 2, 4}. The `2*` multiplier reflects that `lane-status.txt` aggregates per-tool but each tool covers 2 external slots in deep mode.

**Trigger**: emit the banner when `N_FALLBACK >= 1`. When `N_FALLBACK = 0`, emit nothing — the synthesis output is byte-identical to the pre-banner shape, preserving the byte-stability contract for the all-externals-healthy path.

**Edit-in-sync surfaces** — the banner literal exists in three places. **Any change to the banner literal, the trigger condition, or the per-scale formula MUST be mirrored in all three surfaces in the same PR**. Three-way edit-in-sync rule:

1. **Banner literal in prose**: `skills/research/references/research-phase.md` §1.5 banner preamble. The byte-exact text the synthesizer prepends to `## Research Synthesis`.
2. **Structural pin**: `scripts/test-research-structure.sh` Checks 21a-21e. Section-scoped grep assertions on `research-phase.md` (preamble + 3 branches' references + Quick negative check).
3. **Reference-impl assertions**: `skills/research/scripts/test-degraded-path-banner.sh` (this harness). The `BANNER_TEMPLATE` constant near the top of the script + the formula in `emit_banner()`.

If any of the three drifts, this harness fails (Pin 1-4 catch literal/formula drift) and `test-research-structure.sh` fails (Checks 21a-21e catch section-scope drift).

**Stdout contract**:

- On success: `PASS: test-degraded-path-banner.sh — <N> assertions passed` (single line, exit 0).
- On any failure: per-case diagnostic lines on stderr, summary line `test-degraded-path-banner.sh — <P> passed, <F> failed` on stderr, exit 1.

**Maintenance**:

- When adding a fixture case: add a `run_case` invocation; the assertion count updates automatically.
- When changing the banner literal: update `BANNER_TEMPLATE` near the top of the harness AND the §1.5 preamble in `research-phase.md` AND the structural pin in `scripts/test-research-structure.sh`. Verify all three converge on the same byte sequence.
- When changing the per-scale formula: update `emit_banner()` AND the §1.5 preamble formulas AND the formula-pin grep targets in this harness (`Pin 2` and `Pin 3` use `grep -Fq` on the literal formula text — keep the literal in research-phase.md byte-identical to the grep target).
