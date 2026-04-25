# skills/research/scripts/test-standard-angle-prompts.sh — contract

`skills/research/scripts/test-standard-angle-prompts.sh` is the structural regression guard for the `/research --scale=standard` per-lane angle-prompt mapping introduced by #508 (which extended deep-mode angle prompts to standard mode). Seven assertions:

1. `RESEARCH_PROMPT_BASELINE` identifier exists in `skills/research/references/research-phase.md` — the post-#508 rename of the previous shared `RESEARCH_PROMPT` literal.
2. All four named angle prompt identifiers (`RESEARCH_PROMPT_ARCH`, `RESEARCH_PROMPT_EDGE`, `RESEARCH_PROMPT_EXT`, `RESEARCH_PROMPT_SEC`) appear in `research-phase.md`. Already pinned by Check 10 of `scripts/test-research-structure.sh`; pinned here too for failure-locality so a regression in standard-mode wiring fails THIS harness with a directly relevant error message.
3. The Step 1.3 `### Standard (RESEARCH_SCALE=standard, default)` subsection references `<RESEARCH_PROMPT_ARCH>` (Cursor lane angle prompt).
4. The same subsection references `<RESEARCH_PROMPT_EDGE>` (Codex lane default angle prompt).
5. The same subsection references `<RESEARCH_PROMPT_EXT>` (Codex lane variant under `external_evidence_mode=true`).
6. The same subsection mentions `external_evidence_mode` (the keyword that drives Codex EDGE → EXT switching).
7. The same subsection references `RESEARCH_PROMPT_SEC` (Claude inline lane angle prompt).

**Section extraction is H2-then-H3 nested**, mirroring Check 16 of `scripts/test-research-structure.sh`:

- Stage 1 — narrow to the `## 1.3` window (between a level-2 heading whose text starts with `1.3` and the next level-2 heading) so the `### Standard` headers in Step 1.4 (Wait and Validate) and Step 1.5 (Synthesis) cannot satisfy the per-lane pins. The awk extractor matches the regex `^## 1\.3` (anchored on a level-2 heading; literal trailing space in the pattern enforces "level-2, not level-3") and stops at the next `^##` heading.
- Stage 2 — within that window, scope to the `### Standard (RESEARCH_SCALE=standard, default)` subsection (between that header and the next level-3 heading) so the `### Quick` and `### Deep` subsections cannot substitute either.

The nested approach is necessary because `research-phase.md` carries separate `### Standard` subsections in Step 1.3 (Launch), Step 1.4 (Collection), and Step 1.5 (Synthesis); a single-stage `^### Standard ... next ^###` extractor would match the wrong one depending on file order.

**Wiring**:
- Wired into `make lint` via the `test-standard-angle-prompts` target in `Makefile` (declared in `.PHONY` and added to `test-harnesses` prerequisites).
- The test script is added to `agent-lint.toml`'s `[[skill_metadata.suppressed_agent_files]]` exclude list (alongside the other test-* harnesses) because agent-lint's dead-script rule does not follow Makefile-only references.
- This sibling `.md` is added to the skill-local sibling-`.md` block (`[[skill_metadata.suppressed_skill_files]]` near lines 476-487 of `agent-lint.toml`) because it is not cited from any SKILL.md and would otherwise trigger S030 (orphaned-skill-files).

**Edit-in-sync rules**: edits to the Step 1.3 `### Standard` subsection's per-lane angle assignment in `skills/research/references/research-phase.md`, to the four angle prompt identifiers, or to `RESEARCH_PROMPT_BASELINE`, must keep this harness's assertions current. Specifically:
- Renaming any of `RESEARCH_PROMPT_BASELINE` / `RESEARCH_PROMPT_ARCH` / `RESEARCH_PROMPT_EDGE` / `RESEARCH_PROMPT_EXT` / `RESEARCH_PROMPT_SEC` requires updating Checks 1, 2, 3, 4, 5, 7 here.
- Renaming or restructuring the `### Standard (RESEARCH_SCALE=standard, default)` header requires updating the awk extractor pattern (regex on the subsection header).
- Removing `external_evidence_mode` switching language from the Standard subsection requires updating Check 6.
