# quick-vote-state.sh — Quick K-vote state helper

**Consumer**: `/research` Step 1.4 Quick (writer) and Step 1.5 Quick + Step 3 (readers). Issue #520.

**Contract**: write/read a single integer state file `$RESEARCH_TMPDIR/quick-vote-state.txt` with one line `LANES_SUCCEEDED=<N>` where `N ∈ {0,1,2,3}`. Used by Step 1.5 Quick to branch into vote / single-lane fallback / no-lane-fail paths, and by Step 3 to pick the right disclaimer file and header literal.

## Subcommands

### `write --dir <RESEARCH_TMPDIR> --succeeded <N>`

Writes `LANES_SUCCEEDED=N` atomically (mktemp + mv). `N` must be one of `{0,1,2,3}`. Exits 2 on bad arg or missing dir. Exits 0 with stdout `WROTE=<path>` and `LANES_SUCCEEDED=<N>` on success.

### `read --dir <RESEARCH_TMPDIR>`

Prints `LANES_SUCCEEDED=<N>` to stdout. **Defensive defaults**: missing file, unparseable content, or out-of-range value prints `LANES_SUCCEEDED=0` (treated as the no-lane / hard-fail path). Always exits 0.

## Edit-in-sync surfaces

Behavior changes here MUST be mirrored in:
1. `skills/research/scripts/quick-vote-state.md` (this file).
2. `skills/research/scripts/test-quick-vote-state.sh` (regression harness).
3. `skills/research/references/research-phase.md` Quick subsections of §1.4 / §1.5 (call sites).
4. `skills/research/SKILL.md` Step 3 Quick header literal (consumer of `read` output).
5. `scripts/test-research-structure.sh` (CI pin asserting the helper exists).

## Why a helper, not inline awk

`/research` is bash-driven; its prose-level instructions could specify inline awk parsing for the state file. A dedicated helper:
- Is testable via a regression harness wired into `make lint` (drift-prevention).
- Provides a single canonical implementation of the `{0,1,2,3}` validity check + defensive default.
- Decouples the call sites in research-phase.md and SKILL.md from the file format — future changes (e.g., adding more state fields) only update the helper.
- Mirrors the project's existing pattern: shell helper + sibling `.md` + Makefile target (`token-tally.sh`, `compute-degraded-banner.sh`, `assemble-anchor.sh`, etc.).
