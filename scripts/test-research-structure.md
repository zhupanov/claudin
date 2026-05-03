# scripts/test-research-structure.sh — contract

`scripts/test-research-structure.sh` is the structural regression guard for
the `/research` skill under the simplified fixed-shape topology
(4 Codex-first research lanes + 3-reviewer validation panel,
`--no-issue` as the only flag).

## What it pins

1. `skills/research/SKILL.md` exists.
2. The 4 reference files exist: `references/research-phase.md`,
   `references/validation-phase.md`, `references/citation-validation-phase.md`,
   `references/critique-loop-phase.md`.
3. `references/adjudication-phase.md` does NOT exist (removed under the
   simplified shape).
4. Each reference is named on a `MANDATORY — READ ENTIRE FILE` line in
   `SKILL.md`, and that same line carries reciprocal `Do NOT load <other>`
   guards naming the OTHER three references on the same line (line-scoped,
   presence-not-order).
5. Each `references/*.md` opens with the `**Consumer**:` /
   `**Contract**:` / `**When to load**:` triplet in the first 20 lines.
6. The four named angle-prompt identifiers
   (`RESEARCH_PROMPT_ARCH` / `_EDGE` / `_EXT` / `_SEC`) appear in
   `research-phase.md`.
7. Reviewer XML wrapper tags (`<reviewer_research_question>`,
   `<reviewer_research_findings>`) appear in `validation-phase.md`.
8. `SKILL.md` carries the fail-closed unknown-flag guard heading and the
   `unsupported flag` abort message.
9. `SKILL.md`'s recovery hint enumerates each removed-flag CATEGORY:
   `scale`, `plan`, `interactive`, `adjudicate`, `token-budget`,
   `keep-sidecar`, `verbosity`. (Categories rather than literal `--foo`
   tokens to avoid tripping the unknown-flag guard the prose is documenting.)
10. `SKILL.md` surfaces `--no-issue` (the only supported flag).

## Wiring

- `make test-research-structure` is a `test-harnesses` prerequisite via the
  Makefile target.
- `agent-lint.toml` exempts this harness's literal pins from agent-lint scans.

## Edit-in-sync rules

When editing `skills/research/SKILL.md` (MANDATORY directives, flag surface,
or unknown-flag-guard recovery hint) or any of the four reference files
(header triplet, angle prompts, reviewer wrappers), update this harness if a
pinned literal moves.
