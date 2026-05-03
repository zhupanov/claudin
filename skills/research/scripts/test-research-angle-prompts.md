# test-research-angle-prompts.sh — Contract

Structural regression guard for the fixed-shape angle-prompt mapping in
`skills/research/references/research-phase.md`.

## Purpose

Pin that the four named angle prompts (`RESEARCH_PROMPT_ARCH` /
`RESEARCH_PROMPT_EDGE` / `RESEARCH_PROMPT_EXT` / `RESEARCH_PROMPT_SEC`) exist
and that each is bound to its declared Codex-first lane in the 4-lane fixed
topology (Architecture / Edge cases / External comparisons / Security), with
per-lane Claude `Agent` fallback.

## Invariants

- Every angle prompt identifier is present in `research-phase.md`.
- Each lane label co-occurs on the same line with its angle prompt
  identifier and the `Codex-first` declaration.
- Per-lane Claude Agent fallback wording is documented somewhere in the
  research-phase.md lane block.

## Wiring

- Wired into `make lint` via the `test-research-angle-prompts` target.
- Listed in agent-lint.toml allowlist so the harness's own metaprompt
  literals don't trip lint scans of the test source.

## Edit-in-sync rules

When changing the lane-declaration block at the top of
`skills/research/references/research-phase.md`, update this harness if the
lane labels, angle prompt identifiers, or Codex-first / Claude Agent fallback
wording change.
