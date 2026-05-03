# compute-research-banner.sh — contract

**Consumer**: `/research` Step 1.5 (research-phase.md §1.5 banner preamble) — orchestrator forks this script to compute the reduced-diversity banner before invoking the synthesis subagent. Also consumed by `test-research-banner.sh` (fixture-driven harness, forks this script and compares stdout against fixtures).

**Purpose**: canonical executable home for the /research Step 1.5 reduced-diversity banner formula. Reads line-anchored `^RESEARCH_*_STATUS=` keys from a `lane-status.txt` fixture, counts how many values begin with `fallback_`, and prints the substituted banner literal on stdout (or nothing when `N_FALLBACK = 0`).

**Formula** (canonical — duplicated in research-phase.md §1.5 preamble for documentation only; this script is the executable truth):

`N_FALLBACK` = number of lines matching `^RESEARCH_[A-Z_]+_STATUS=fallback_`. The fixed denominator is **4 external research lanes** (architecture / edge cases / external comparisons / security).

**Trigger condition**: emit the banner when `N_FALLBACK >= 1`. When `N_FALLBACK = 0`, emit nothing.

**False-positive guards** (built into the line/value anchors):

- A `*_REASON=...fallback_...` line is NOT counted (only `_STATUS=` keys are read; `_REASON=` keys do not match the regex).
- A `VALIDATION_*_STATUS=fallback_*` line is NOT counted (regex is anchored on `^RESEARCH_`).

**Stdout contract**:

- On `N_FALLBACK >= 1`: prints the substituted `BANNER_TEMPLATE` on stdout, followed by a single newline.
- On `N_FALLBACK == 0`: prints nothing.
- On missing/unreadable fixture: prints nothing (defensive default).
- On insufficient args (`< 1`): prints nothing on stdout; logs a diagnostic on stderr.
- Always exits 0 (failure-to-emit is signaled by empty stdout, never by a non-zero exit code, so callers using `$(...)` command substitution under `set -e` do not abort).

**Usage**:

```bash
banner=$(bash ${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/compute-research-banner.sh "$RESEARCH_TMPDIR/lane-status.txt")
```

The orchestrator forks this script (NOT `source`-s it) — no shared shell state between caller and helper.

**Edit-in-sync surfaces** — the banner literal exists in **four** places. Any change MUST be mirrored in all four surfaces in the same PR:

1. **Canonical executable**: `BANNER_TEMPLATE` constant + the formula in `emit_banner()` in this script.
2. **Banner literal in prose**: `skills/research/references/research-phase.md` §1.5 banner preamble.
3. **Operator-facing example banner**: `skills/research/SKILL.md` Step 3 — the fully-substituted degraded-path preview example.
4. **Fixture-driven harness**: `skills/research/scripts/test-research-banner.sh`. The harness forks this script and compares stdout against fixtures.

**Wired into**: `Makefile` `test-harnesses` target via `test-research-banner`.

**Maintenance**:

- When changing the banner literal: update `BANNER_TEMPLATE` here, the §1.5 preamble in `research-phase.md`, the substituted example in `SKILL.md` Step 3, and the fixture expectations in `test-research-banner.sh`.
- When changing the formula: update `emit_banner()` here AND the §1.5 preamble formula prose.
