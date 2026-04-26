# test-degraded-path-banner.sh — contract

**Consumer**: `make lint` (via the `test-degraded-path-banner` Makefile target).

**Purpose**: offline regression harness for the /research Step 1.5 reduced-diversity banner contract introduced by issue #506 and refactored under issue #507. Validates two surfaces:

1. **Fixture-driven correctness**: synthetic `lane-status.txt` fixtures across 4 cases × 2 scales (standard, deep). For each fixture, the harness **forks `compute-degraded-banner.sh`** (NOT `source`-s it) and compares stdout against hardcoded expected banner strings. The independent oracle is the **fixture table** — drift between the helper's output and the prose is caught by fixture-vs-stdout mismatch, without requiring two parallel implementations of the same formula.
2. **Prose pins + canonical-executable pins**: greps `skills/research/references/research-phase.md` for the byte-exact banner literal (documentation pin) AND greps `skills/research/scripts/compute-degraded-banner.sh` for the formula literals (canonical-executable pin) AND verifies `BANNER_TEMPLATE` in the helper byte-equals the harness's `BANNER_TEMPLATE`.

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

**Per-scale formulas under test** (canonical executable in `compute-degraded-banner.sh`; documented in `research-phase.md` §1.5):

- **Standard**: `LANE_TOTAL=2`, `N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)` ∈ {0, 1, 2}.
- **Deep**: `LANE_TOTAL=4`, `N_FALLBACK = 2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)` ∈ {0, 2, 4}. The `2*` multiplier reflects that `lane-status.txt` aggregates per-tool but each tool covers 2 external slots in deep mode.

**Trigger**: emit the banner when `N_FALLBACK >= 1`. When `N_FALLBACK = 0`, emit nothing — the synthesis output is byte-identical to the pre-banner shape, preserving the byte-stability contract for the all-externals-healthy path.

**Edit-in-sync surfaces** — the banner literal AND the per-scale formulas exist in **five** places. **Any change to the banner literal, the trigger condition, or the per-scale formula MUST be mirrored in all five surfaces in the same PR**:

1. **Canonical executable**: `BANNER_TEMPLATE` constant + the formula in `emit_banner()` in `skills/research/scripts/compute-degraded-banner.sh`. THIS is the executable truth — the orchestrator (research-phase.md §1.5 prose) and this harness both fork the helper.
2. **Banner literal in prose**: `skills/research/references/research-phase.md` §1.5 banner preamble. The byte-exact text the orchestrator prepends to `## Research Synthesis` after the synthesis subagent returns. Documentation only — does NOT execute.
3. **Structural pin**: `scripts/test-research-structure.sh` Check 21a. Section-scoped grep assertions on `research-phase.md` (banner literal) AND on `compute-degraded-banner.sh` (formula literals — Check 21a greps the helper for the formula text).
4. **Fixture expectations**: `skills/research/scripts/test-degraded-path-banner.sh` (this harness). The `BANNER_TEMPLATE` constant near the top of the script is byte-pinned against the helper's `BANNER_TEMPLATE` (Pin 5); fixture rows enumerate `(RESEARCH_SCALE, N_FALLBACK)` pairs.
5. **Operator-facing example banner**: `skills/research/SKILL.md` Step 3 — the fully-substituted degraded-path preview example, pinned by Check 22 of `scripts/test-research-structure.sh`. Whenever the banner template changes, update the substituted phrases in the SKILL.md Step 3 example so they remain byte-identical to the per-scale render.

If any of the five drifts, this harness fails (fixture comparison detects template/formula drift, Pin 5 detects `BANNER_TEMPLATE` drift between helper and harness) AND `test-research-structure.sh` fails (Checks 21a-22 detect section-scope and SKILL.md drift).

**Stdout contract**:

- On success: `PASS: test-degraded-path-banner.sh — <N> assertions passed` (single line, exit 0).
- On any failure: per-case diagnostic lines on stderr, summary line `test-degraded-path-banner.sh — <P> passed, <F> failed` on stderr, exit 1.

**Maintenance**:

- When adding a fixture case: add a `run_case` invocation; the assertion count updates automatically.
- When changing the banner literal: update `BANNER_TEMPLATE` in `compute-degraded-banner.sh` AND in this harness AND the §1.5 preamble in `research-phase.md` AND the structural pin in `scripts/test-research-structure.sh` AND the fully-substituted example banner in `skills/research/SKILL.md` Step 3 (the operator-facing degraded-path preview, pinned by Check 22). Verify all five converge on the same byte sequence.
- When changing the per-scale formula: update the implementation in `compute-degraded-banner.sh` AND the §1.5 preamble formulas (documentation) AND the formula-pin grep targets in `scripts/test-research-structure.sh` Check 21a (which now greps the helper). The harness's expected outputs follow automatically from the formula change in the helper — no per-case edit is needed.
