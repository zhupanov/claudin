# scripts/render-reviewer-prompt.sh

## Purpose

Render the unified Code Reviewer archetype from `skills/shared/reviewer-templates.md` into a plain-text prompt suitable for `cursor agent -p` and `codex exec` in the `/research` validation lanes (`skills/research/references/validation-phase.md`). Closes the asymmetry where the always-on Claude lane uses the unified five-focus-area archetype with XML-wrapped untrusted-context while Codex/Cursor lanes used a legacy four-perspectives string without security tagging.

The script extracts the canonical archetype body, performs context-keyed substitutions for `{REVIEW_TARGET}`, `{CONTEXT_BLOCK}`, `{OUTPUT_INSTRUCTION}`, applies a research-validation sentinel-override so externals emit `NO_ISSUES_FOUND` (matching the existing single-list contract `/research`'s negotiation pipeline depends on), and instructs models to leave the OOS section empty.

## Invariants

- **Template marker dependency**: extracts the archetype body between `<!-- BEGIN GENERATED_BODY -->` and `<!-- END GENERATED_BODY -->` in `skills/shared/reviewer-templates.md`, dropping the outer ``` fences by position. Same shape as `scripts/generate-code-reviewer-agent.sh:58-83`. If the markers are renamed, both scripts must be updated in lockstep — the agent-sync CI job catches drift on the generator side, and this script's negative test (`scripts/test-render-reviewer-prompt.sh`) catches drift on the renderer side.
- **Sentinel-override pinned target**: the literal substring `If no in-scope issues found, say "No in-scope issues found."` (the archetype's default closing-rule sentence) MUST be present in the rendered output before the override step. If the archetype changes that sentence, this script fails closed with a diagnostic so the caller does not silently ship a prompt with a divergent no-issues sentinel.
- **stderr/stdout discipline**: all diagnostics and progress messages on stderr; ONLY the rendered prompt body on stdout. The script terminates with `cat` of the final stage file, so the byte content of the rendered template is preserved as-is (no synthesized trailing newline beyond what `awk`'s line-oriented output naturally produces). The rendered output is consumed verbatim by `cursor-wrap-prompt.sh` and `codex exec`; mixing diagnostics into stdout would corrupt the prompt.
- **Validation gate scope**: the unresolved-placeholder check runs on the template-only intermediate output, BEFORE the `{CONTEXT_BLOCK}` substitution embeds user-supplied research findings. The check verifies that no `{REVIEW_TARGET}` or `{OUTPUT_INSTRUCTION}` tokens remain (substitutions must have succeeded) AND that exactly one `{CONTEXT_BLOCK}` marker line is still present (it is substituted last). User content embedded inside `<reviewer_research_findings>` may legitimately contain any of these literal token names — the gate's pre-substitution scope ensures meta-research about the reviewer system itself does not trigger false-positive failures.
- **`--target` value safety**: the `{REVIEW_TARGET}` substitution uses `index`/`substr` rather than awk's `gsub`, so target values containing `&` or `\` are treated as literal characters (e.g., `--target 'R&D findings'` is preserved verbatim). awk's `gsub` would expand `&` to the matched text and corrupt the output.
- **Determinism**: `LC_ALL=C`, no timestamps, no git state, no network. Same render produces the same bytes.

## Flags

| Flag | Required | Semantics |
|------|----------|-----------|
| `--target <text>` | Yes | Substituted for `{REVIEW_TARGET}` (e.g., `'research findings'`). |
| `--research-question-file <path>` | Yes | Contents embedded inside `<reviewer_research_question>` tag (verbatim). |
| `--context-file <path>` | Yes | Contents embedded inside `<reviewer_research_findings>` tag (verbatim). Typically `$RESEARCH_TMPDIR/research-report.txt`. |
| `--in-scope-instruction-file <path>` | Yes | Multi-line bullets emitted under `### In-Scope Findings`. Each non-empty line in the file becomes one `- <line>` bullet in the rendered prompt. |
| `--oos-instruction-file <path>` | No | Multi-line bullets emitted under `### Out-of-Scope Observations`. Defaults to a built-in stub: `Out-of-Scope Observations are not applicable for /research validation. Do not emit any items in this section; emit only In-Scope Findings.` Override only when extending to a new context that wants OOS observations from externals. |

## Inputs / Outputs

- **Inputs**: the canonical archetype template, the four required content files, optionally the OOS instruction file.
- **Output**: the fully-substituted prompt body on stdout. Suitable to pass directly as the positional `cursor agent -p` argument (via `cursor-wrap-prompt.sh`) or as the positional `codex exec` argument.

## Exit codes

| Exit | Cause |
|------|-------|
| 0 | Render succeeded; prompt emitted on stdout. |
| 1 | Template marker missing, sentinel-override target missing, unresolved placeholder in rendered output, or `{OUTPUT_INSTRUCTION}` encountered outside a known section. |
| 2 | Required flag missing, unrecognized flag, template file not found, required input file missing or unreadable. |

## Test harness

`scripts/test-render-reviewer-prompt.sh` (wired into the Makefile `test-harnesses` target). Covers the happy path plus 5 negative cases (missing flag, unreadable file, missing BEGIN/END markers, missing sentinel-override target, unresolved placeholder) plus 1 static integration check that `skills/research/references/validation-phase.md` invokes this helper for both Cursor and Codex lanes.

## Edit-in-sync rules

- **`skills/shared/reviewer-templates.md`**: if the BEGIN/END markers are renamed or the `{REVIEW_TARGET}` / `{CONTEXT_BLOCK}` / `{OUTPUT_INSTRUCTION}` placeholder names change, update this script and `scripts/generate-code-reviewer-agent.sh` in the same PR. The two scripts share the marker dependency by convention, not by code.
- **Sentinel-override target sentence**: pinned literal in this script. If `reviewer-templates.md`'s closing-rule sentence wording changes, update the `SENTINEL_TARGET` variable in this script in the same PR. The negative test will catch a missed update.
- **`skills/research/references/validation-phase.md`**: callers of this helper. The static integration check in `test-render-reviewer-prompt.sh` enforces that both Cursor and Codex lanes invoke this script.

## Caller pattern (for `validation-phase.md`)

```bash
# Foreground render — fails fast on any error.
${CLAUDE_PLUGIN_ROOT}/scripts/render-reviewer-prompt.sh \
  --target 'research findings' \
  --research-question-file "$RESEARCH_TMPDIR/research-question.txt" \
  --context-file "$RESEARCH_TMPDIR/research-report.txt" \
  --in-scope-instruction-file "$RESEARCH_TMPDIR/research-in-scope-instruction.txt" \
  > "$RESEARCH_TMPDIR/cursor-prompt.txt"

# On non-zero exit: follow Runtime Timeout Fallback in skills/shared/external-reviewers.md —
# (1) surgically rewrite VALIDATION_<TOOL>_STATUS=fallback_runtime_failed in lane-status.txt
# (with a sanitized REASON) so Step 3's final report cannot show the failed lane as
# native success; (2) set cursor_available=false, omit the path from COLLECT_ARGS,
# launch a Claude Code Reviewer subagent fallback to preserve the 3-lane invariant.
```
