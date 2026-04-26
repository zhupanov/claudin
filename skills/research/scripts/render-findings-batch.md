# render-findings-batch.sh — Contract

**Purpose**: extract findings from `/research`'s rendered Step 3 final report and emit one `### <title>` block per finding to a sidecar markdown file consumable by `skills/issue/scripts/parse-input.sh` (generic `### <title>` + body fallback path). Closes #510.

**Consumed by**: `/research` Step 3 (after the rendered final report is written to `$RESEARCH_TMPDIR/research-report-final.md`). The orchestrator invokes this script with the report path; the script slices `### Findings Summary`, extracts global metadata (Risk / Difficulty / Feasibility / Key Files / Open Questions), runs the heuristic ladder (numbered → top-level bulleted → paragraph-per-item), and emits items.

**Why a separate script**: prose-shaped extraction is deterministic and harness-friendly — it lives in this script so it can be tested offline against canned report fixtures (see `test-render-findings-batch.sh`). The orchestrator stays prompt-shaped in SKILL.md.

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/render-findings-batch.sh \
  --report "$RESEARCH_TMPDIR/research-report-final.md" \
  --output "$RESEARCH_TMPDIR/research-findings-batch.md" \
  --research-question-file "$RESEARCH_TMPDIR/research-question.txt" \
  --branch "$CURRENT_BRANCH" \
  --commit "$HEAD_SHA" \
  [--quick-disclaimer "$QUICK_DISCLAIMER"]
```

All flags are required except `--quick-disclaimer`. The orchestrator passes `--quick-disclaimer` only when `RESEARCH_QUICK=true` (the `--quick` boolean — issue #520 re-keyed the trigger from `RESEARCH_SCALE=quick`), sourcing the canonical literal from `skills/research/data/quick-disclaimer.txt`. The script itself is unchanged: it forwards the `--quick-disclaimer <text>` argument verbatim into each rendered finding's body when present.

## Contract

### Stdout (machine output only)

- **On success** (exit 0): `COUNT=<N>` on a single line where `N >= 1`.
- **On empty findings** (exit 3): `COUNT=0` on a single line; the sidecar file is still written as a zero-byte file.
- **On usage error** (exit 1): no machine output.
- **On exit 2**: no machine output. Exit 2 fires when `--report` is missing OR when the path exists but is not a regular file (e.g., a directory) — `[[ ! -f "$REPORT_PATH" ]]` rejects both. Stderr carries an `ERROR:` diagnostic line (#510 review FINDING_7 — single canonical wording).

### Stderr (human diagnostics)

- **On exit 3**, one of two warning texts on stderr:
  - `WARNING: Findings Summary section is empty (zero findings). The sidecar is empty; '/issue --input-file <path>' on it would create no issues.`
  - `WARNING: Findings Summary section not found in input (input may be malformed). The sidecar is empty; '/issue --input-file <path>' on it would create no issues.`
- **On exit 1 / 2**: short usage or diagnostic line.

### Exit codes

- `0` — at least one finding emitted.
- `1` — usage error (missing required flag, unknown flag).
- `2` — `--report` path does not exist or is not a regular file.
- `3` — Findings Summary section is empty OR absent. Empty output file still written; SKILL.md treats exit 3 as non-fatal warning.

## Section extraction

The Findings Summary section is sliced from the line `### Findings Summary` (matched verbatim) through the line BEFORE the first of the canonical "next top-level header" markers:

- `### Risk Assessment`
- `### Difficulty Estimate`
- `### Feasibility Verdict`
- `### Key Files and Areas`
- `### Open Questions`
- <code>## </code> (any top-level header — the start of a NEW `## Section`)

Generic <code>### </code> is NOT a terminator (planner mode produces `### Subquestion N: ...` headings inside Findings Summary, and a generic terminator would silently truncate findings). See FINDING_5a in the design review.

The slicer is **fence-aware**: lines matching `^[[:space:]]*` followed by three backticks toggle an `IN_FENCE` boolean. Indented fences (e.g., a 3-space-prefixed fenced block inside a bulleted item's body) toggle the state correctly per #510 review FINDING_5 — earlier drafts matched only column-0 fences and would misparse indented fenced contents. Header detection is suppressed inside fenced blocks (defense against `### Foo` inside an inline code block). See FINDING_5b.

## Heuristic ladder (item splitting)

Applied to the Findings Summary slice:

1. **Numbered list** — lines matching `^[[:space:]]*[0-9]+\.[[:space:]]` start new items.
2. **Top-level bulleted** — lines matching `^[[:space:]]{0,2}[-*][[:space:]]` start new items.
3. **Paragraph-per-item** — paragraphs separated by blank lines.

Modes are **adaptive**: a top-level numbered or bulleted line ALWAYS starts a new item, regardless of which mode the parser entered first. This handles planner-mode where a `#### Subquestion 1: ...` heading-paragraph precedes a numbered list. Sub-headings (lines beginning with <code>#### </code>) are skipped entirely — they flush the current item but are NOT emitted as items themselves.

## Title extraction

For each item:

1. The first line is stripped of leading bullet/numbering markers and whitespace.
2. The first sentence is taken (split on <code>. </code>, <code>! </code>, <code>? </code>, or end-of-line).
3. Truncated to 80 chars.
4. Trailing whitespace and punctuation stripped.
5. **Empty-title fallback** (FINDING_2): if the result is empty (e.g., the first sentence was all punctuation), the title becomes `Finding <N>` where N is the 1-based item index. Without this fallback, `parse-input.sh:161-163` silently drops empty-title items, breaking the round-trip `ITEMS_TOTAL` assertion.

## Body composition

For each item, the body contains:

1. (Optional) `--quick-disclaimer` value as the first content line, separated by a blank line from the metadata.
2. **Metadata block** — five lines, applied globally per finding (NOT per-finding precision; see "Known limitations" below):
   ```
   **Source**: /research output, branch `<branch>` at `<commit>`, run <ISO8601-UTC-timestamp>
   **Risk**: <Risk Assessment value | N/A>
   **Difficulty**: <Difficulty Estimate value | N/A>
   **Feasibility**: <Feasibility Verdict value | N/A>
   **Files touched**: <comma-joined Key Files entries | N/A>
   ```
3. The finding's prose body — verbatim from the synthesis, with one transformation:
   - **Body-line <code>### </code> escape** (FINDING_5c, refined per #510 review FINDING_2): any line matching `^###[[:space:]]` (any whitespace after the three hashes — space OR tab) is prefixed with a backslash so `parse-input.sh:393`'s `^\#\#\#[[:space:]]+(.+)$` regex does not match it as a new-item boundary downstream. Markdown rendering displays the line unchanged (the leading `\` escapes the first `#`). Lines inside fenced code blocks are NOT escaped (the `IN_FENCE` toggle is honored). Without the FINDING_2 fix, lines like `###<TAB>Foo` would slip past a literal-space-only escape and split items downstream.
4. (Optional) `**Open questions** (if any): <semicolon-joined Open Questions entries>` line — emitted only when the Open Questions section is non-empty.
5. **Audit-context separator and italic line**:
   ```
   ---
   *This issue was filed from /research output. Audit context: <RESEARCH_QUESTION>.*
   ```

The metadata `**Source**:` / `**Risk**:` / etc. lines (no leading <code>- </code>) cleanly pass through `parse-input.sh`'s generic-mode body — verified at `parse-input.sh:393-481`. In `CURRENT_MODE=generic`, the OOS field branches require leading `- **Description**:` / `- **Reviewer**:` / etc.; our format cannot trigger them.

## Known limitations

- **Odd fence count leaves IN_FENCE stuck through EOF** (#510 review FINDING_8): if the input has an odd number of `^[[:space:]]*\`\`\`` lines (an opening fence with no closing fence in the slice), the toggle leaves `in_fence=1` for every subsequent line, suppressing header detection until end-of-input. The `### Findings Summary` section bound by named next-headers may be over-extended in this case. The synthesis prompt produces well-formed fenced blocks in practice; this is a defensive note for unusual inputs.

## Other limitations

- **Heuristic extraction is fuzzy**: LLM-shaped synthesis prose may produce slight under- or over-splitting. The harness includes stress fixtures (planner-nested headings, fenced blocks, body-`###` lines, multi-paragraph bullets) but cannot enumerate every real-world synthesis shape.
- **Global metadata, not per-finding**: Risk / Difficulty / Feasibility / Files-touched are report-level sections and are repeated verbatim in every item. The repetition can imply per-finding precision that the source report does not actually carry. The audit-context italic line ("filed from /research output") signals the prose-derivation origin to mitigate this.
- **Open Questions applied globally**: per-finding mapping based on the Open Question text referencing a finding number is a future-work item, not implemented in v1.
- **Title duplication**: two findings whose first sentences are similar can produce near-identical titles. `/issue`'s 2-phase semantic dedup catches them, but treats them as inter-batch duplicates rather than as distinct findings.
- **Concurrent overwrites**: SKILL.md Step 4 copies the sidecar to `$PWD/research-findings-batch.md` (default) unconditionally. Two concurrent `/research` runs racing with `--keep-sidecar` (defaults) will clobber each other.

## Future work (NOT implemented in v1)

- HTML-comment sentinels around findings (replacing heuristic extraction with parser delimiters).
- JSON sidecar emitted by Step 1.5 / Step 3 normalized by this helper into batch markdown — more robust than awk-on-prose.
- Per-finding metadata extraction (Risk / Difficulty / Feasibility per finding, when synthesis ever produces them).
- Smart per-finding Open Questions mapping (resolve "(see finding 3)" references).
- Synthesis-prompt soft directive ("structure findings as a numbered list when possible") — design-time mitigation orthogonal to extraction robustness.

## Path-validation security property

SKILL.md Step 4 (the consumer of the helper's output) validates the `--keep-sidecar` destination path before `cp`. The destination MUST NOT resolve under `$RESEARCH_TMPDIR`. Two implementation tiers:

- **`realpath`-resolved** (Darwin 23, modern Linux): the destination is canonicalized via `realpath` before the prefix check, defending against symlink/hardlink escapes (e.g., a symlink in `$PWD` pointing into `/tmp/claude-research-...` would be caught).
- **String-prefix fallback** (rare; some BSD without `realpath`): a string-prefix check after `cd ... && pwd` resolution. This is best-effort only — symlinks within the tmpdir parent could in principle bypass the check, but this requires operator-controlled symlinks. Maintainers MUST NOT "simplify" the validation by removing the `realpath` branch.

See FINDING_11 in the design review.

## Cross-skill coupling (research ↔ issue)

This script's output MUST round-trip through `skills/issue/scripts/parse-input.sh` cleanly:

- `parse-input.sh` exits 0.
- `ITEMS_TOTAL` matches the helper's `COUNT`.
- No item carries `MALFORMED=true`.

The harness `test-render-findings-batch.sh` asserts this end-to-end. The coupling is intentional and is also documented in `skills/issue/scripts/parse-input.md` (reverse coupling note): changes to `parse-input.sh`'s generic-mode `### <title>` handling (e.g., new line-prefix rules) require re-running `/research`'s `make lint` even when `skills/research/` is not edited.

See FINDING_9 in the design review.

## Operator security note

`--keep-sidecar` is an opt-in workspace write. Operators should review the sidecar (and apply redaction if needed) before filing — the sidecar may include security-relevant findings from `/research --scale=deep`'s `Codex-Sec` lane. The post-cleanup advertisement in SKILL.md Step 4 prints `/issue --input-file <path> --label research --dry-run` (NOT `--go`) so the operator manually escalates after review. See SECURITY.md "External reviewer write surface in /research and /loop-review" and FINDING_7 in the design review.

## Test harness

`skills/research/scripts/test-render-findings-batch.sh` — offline regression harness with canned report fixtures (numbered, bulleted, paragraph, mixed, empty, missing, special chars, multi-paragraph bullets, planner-nested headings, fenced code blocks, body-line <code>### </code> escape, empty-title fallback). Round-trip integration through `parse-input.sh`. Wired into `make lint` via the `test-render-findings-batch` target — three Makefile locations updated per the `test-run-research-planner` template (`.PHONY` + `test-harnesses` prereq + recipe).

## Edit-in-sync rules

- **Section-extraction terminator list changes**: update this contract AND `test-render-findings-batch.sh` AND `scripts/test-research-structure.sh` Step-3 pin (which asserts the helper invocation in SKILL.md).
- **Heuristic-ladder changes**: update this contract AND `test-render-findings-batch.sh` (fixtures and asserted behavior).
- **Body-line escape changes**: update this contract AND `test-render-findings-batch.sh` (escape fixture and round-trip assertion) AND the comment-link in `skills/issue/scripts/parse-input.md`.
- **Stdout schema changes** (`COUNT=`): update this contract, the harness, AND the orchestrator's stdout-parsing instruction in SKILL.md Step 3.
- **Exit code vocabulary changes**: update this contract, the harness, AND SKILL.md Step 3's exit-3 handling.
- **Quick-disclaimer source changes** (data file path, format): update this contract AND `skills/research/references/research-phase.md` Quick branch AND `scripts/test-research-structure.sh`'s "data/quick-disclaimer.txt referenced from both paths" pin.
