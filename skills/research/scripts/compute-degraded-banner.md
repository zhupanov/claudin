# compute-degraded-banner.sh — contract

**Consumer**: `/research` Step 1.5 (research-phase.md §1.5 banner preamble) — orchestrator forks this script to compute the reduced-diversity banner before invoking the synthesis subagent. Also consumed by `test-degraded-path-banner.sh` (fixture-driven harness, forks this script and compares stdout against fixtures).

**Purpose**: canonical executable home for the /research Step 1.5 reduced-diversity banner formula introduced by issue #506 (degraded-path banner) and refactored under issue #507 (synthesis-subagent split). Reads `RESEARCH_CURSOR_STATUS` / `RESEARCH_CODEX_STATUS` from a `lane-status.txt` fixture, computes `N_FALLBACK` / `LANE_TOTAL` per the per-scale formula, and prints the substituted banner literal on stdout (or nothing when `N_FALLBACK = 0`).

**Per-scale formulas** (canonical — duplicated in research-phase.md §1.5 preamble for documentation only; this script is the executable truth):

- **Standard**: `LANE_TOTAL=2`, `N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)` ∈ {0, 1, 2}.
- **Deep**: `LANE_TOTAL=4`, `N_FALLBACK = 2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)` ∈ {0, 2, 4}. The `2*` multiplier reflects that `lane-status.txt` aggregates per-tool but each tool covers 2 external slots in deep mode.

**Trigger condition**: emit the banner when `N_FALLBACK >= 1`. When `N_FALLBACK = 0`, emit nothing.

**Stdout contract**:

- On `N_FALLBACK >= 1`: prints the substituted `BANNER_TEMPLATE` on stdout, followed by a single newline.
- On `N_FALLBACK == 0`: prints nothing.
- On missing/unreadable fixture: prints nothing (defensive default per research-phase.md prose).
- On unknown `<scale>`: prints nothing; logs a diagnostic on stderr.
- Always exits 0 (failure-to-emit is signaled by empty stdout, never by a non-zero exit code, so callers using `$(...)` command substitution under `set -e` do not abort).

**Usage**:

```bash
banner=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/compute-degraded-banner.sh "$RESEARCH_TMPDIR/lane-status.txt" "$RESEARCH_SCALE")
```

The orchestrator forks this script (NOT `source`-s it) — no shared shell state between caller and helper. The same fork pattern applies to `test-degraded-path-banner.sh`.

**Edit-in-sync surfaces** — the banner literal AND the per-scale formulas exist in **five** places. **Any change to the banner literal, the trigger condition, or the per-scale formulas MUST be mirrored in all five surfaces in the same PR**:

1. **Canonical executable**: `BANNER_TEMPLATE` constant + the formula in `emit_banner()` in this script. THIS is the executable truth — the orchestrator and the harness both fork this script.
2. **Banner literal in prose**: `skills/research/references/research-phase.md` §1.5 banner preamble. The byte-exact text the orchestrator prepends to `## Research Synthesis` after the synthesis subagent returns. Documentation only — does NOT execute.
3. **Structural pin**: `scripts/test-research-structure.sh` Check 21a. Section-scoped grep assertions on `research-phase.md` (banner literal) AND on this script (formula literal — Check 21a greps THIS file for the formula).
4. **Fixture-driven harness**: `skills/research/scripts/test-degraded-path-banner.sh`. Hardcoded fixture expectations for each `(RESEARCH_SCALE, N_FALLBACK)` pair; the harness forks this script and compares stdout against the fixtures. Catches drift without duplicating the formula logic.
5. **Operator-facing example banner**: `skills/research/SKILL.md` Step 3 — the fully-substituted degraded-path preview example, pinned by Check 22 of `scripts/test-research-structure.sh`. Whenever the banner template changes, update the substituted phrases in the SKILL.md Step 3 example so they remain byte-identical to the per-scale render.

If any of the five drifts, the test-degraded-path-banner.sh harness fails (fixture comparison detects template/formula drift) and `test-research-structure.sh` fails (Checks 21a-22 detect section-scope and SKILL.md drift).

**Wired into**: `Makefile` `test-harnesses` target via `test-degraded-path-banner` (the fixture-driven harness is what `make lint` invokes; this script has no standalone test target — it is exercised through the harness).

**Maintenance**:

- When changing the banner literal: update `BANNER_TEMPLATE` in this script AND the §1.5 preamble in `research-phase.md` AND the structural pin in `scripts/test-research-structure.sh` AND the fully-substituted example banner in `skills/research/SKILL.md` Step 3 AND the fixture expectations in `test-degraded-path-banner.sh`. Verify all five converge on the same byte sequence.
- When changing the per-scale formula: update `emit_banner()` in this script AND the §1.5 preamble formulas (documentation) AND the formula-pin grep targets in `scripts/test-research-structure.sh` Check 21a (which now greps THIS file). The harness's expected outputs follow automatically from the formula change.
