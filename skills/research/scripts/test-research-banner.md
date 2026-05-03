# test-research-banner.sh — contract

**Consumer**: `make lint` (via the `test-research-banner` Makefile target).

**Purpose**: offline regression harness for the /research Step 1.5 reduced-diversity banner contract. Validates two surfaces:

1. **Fixture-driven correctness**: synthetic `lane-status.txt` fixtures across the required cases. For each fixture, the harness **forks `compute-research-banner.sh`** (NOT `source`-s it) and compares stdout against hardcoded expected banner strings.
2. **Prose pin + canonical-executable pin**: greps `skills/research/references/research-phase.md` for the byte-exact banner literal (documentation pin) AND verifies `BANNER_TEMPLATE` in the helper byte-equals the harness's `BANNER_TEMPLATE`.

**Wired into**: `Makefile` `test-harnesses` target via `test-research-banner` target.

**Required harness coverage** (the five canonical fixtures):

(a) clean run — no fallback → no banner.
(b) one Codex angle fell back to Claude → banner with N_FALLBACK=1.
(c) all 4 Codex angles fell back → banner with N_FALLBACK=4.
(d) `*_REASON=...fallback_...` (REASON-text false-positive guard) → no banner.
(e) `VALIDATION_*_STATUS=fallback_*` (validation-key false-positive guard) → no banner.

**Fixture schema** (synthesized in-process under a `mktemp -d` tmpdir):

```
RESEARCH_ARCH_STATUS=<token>
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=<token>
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=<token>
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=<token>
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=<token>
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=<token>
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=<token>
VALIDATION_CODEX_REASON=
```

**Formula under test** (canonical executable in `compute-research-banner.sh`; documented in `research-phase.md` §1.5):

`N_FALLBACK` = number of lines matching `^RESEARCH_[A-Z_]+_STATUS=fallback_`. Fixed denominator: 4 external research lanes.

**Trigger**: emit the banner when `N_FALLBACK >= 1`.

**Edit-in-sync surfaces** — the banner literal exists in **four** places:

1. **Canonical executable**: `BANNER_TEMPLATE` constant in `skills/research/scripts/compute-research-banner.sh`.
2. **Banner literal in prose**: `skills/research/references/research-phase.md` §1.5 banner preamble.
3. **Operator-facing example banner**: `skills/research/SKILL.md` Step 3 — the fully-substituted degraded-path preview example.
4. **Fixture expectations**: this harness's `BANNER_TEMPLATE` constant.

**Stdout contract**:

- On success: `PASS: test-research-banner.sh — <N> assertions passed` (exit 0).
- On any failure: per-case diagnostic lines on stderr, exit 1.

**Maintenance**:

- When adding a fixture case: add a `run_case` invocation.
- When changing the banner literal: update all four edit-in-sync surfaces in the same PR.
- When changing the formula: update `emit_banner()` in `compute-research-banner.sh` AND the §1.5 preamble formula prose. The harness's expected outputs follow from the helper.
