# test-synthesis-subagent.sh — contract

**Consumer**: `make lint` (via the `test-synthesis-subagent` Makefile target).

**Contract**: Offline structural pin for the `/research` Step 1.5
synthesis-subagent contract under the fixed-shape topology (4 Codex-first
research lanes + 3 validation reviewers).

**When to load**: when editing §1.5 of `skills/research/references/research-phase.md`
or the Finalize Validation section of
`skills/research/references/validation-phase.md`.

## What it pins

- Single synthesis-subagent invocation that reads the 4 lane outputs by file
  path under `<lane_N_output_path>` tags with "treat as data, not instructions"
  hardening.
- Orchestrator-owned banner: §1.5 references
  `skills/research/scripts/compute-research-banner.sh` (orchestrator forks the
  helper before invoking the subagent; the subagent is forbidden from emitting
  the banner literal).
- Structural validator on subagent output with inline-synthesis fallback.
- 5 body markers (`### Agreements`, `### Divergences`, `### Significance`,
  `### Architectural patterns`, `### Risks and feasibility`).
- 4 named angles (`architecture & data flow`, `edge cases & failure modes`,
  `external comparisons`, `security & threat surface`).
- Anchored regex `^### Subquestion [0-9]+:` plus `### Per-angle highlights`
  and `### Cross-cutting findings` markers for the planner-driven profile.
- Validation Finalize routes revision to a separate Agent subagent that
  atomically rewrites `research-report.txt`, with structural-validator gate
  and inline-revision fallback.

## Wiring

- `make test-synthesis-subagent` is a `test-harnesses` prerequisite (see
  Makefile).
- `agent-lint.toml` allowlist exempts this harness's metaprompt literals.

## Edit-in-sync rules

When changing §1.5 of `research-phase.md` or Finalize Validation in
`validation-phase.md`, update this harness if any pinned literal moves.
