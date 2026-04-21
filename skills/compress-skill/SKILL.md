---
name: compress-skill
description: "Use when compressing an existing skill's prose. Rewrites SKILL.md and all transitively included .md files (excluding sub-skills), applying Strunk & White's Elements of Style adapted for technical writing."
argument-hint: "<skill-name-or-path> [--debug]"
allowed-tools: Bash, Read, Edit, Write
---

# compress-skill

Rewrite an existing skill's Markdown prose to reduce size while preserving meaning, grammar, and every structural element. Operates on SKILL.md and on `.md` files transitively linked from it, restricted to the skill's own directory tree.

## Scope

- **In scope**: `.md` files inside the target skill's directory (`SKILL.md`, `references/*.md`, and any `.md` file reachable from SKILL.md via Markdown link syntax that resolves to a path inside the skill dir).
- **Out of scope**: sub-skills invoked via the Skill tool (separate skills — never compressed from here), shared larch files (`skills/shared/*.md`, top-level `*.md` like `AGENTS.md`, `README.md`, `SECURITY.md`), any `.md` reached by a link whose resolved path is outside the target skill directory.

The directory-tree restriction is the mechanical filter: links to files outside the skill dir are skipped, which naturally excludes shared docs and callee skills.

## Flags

Parse flags from the start of `$ARGUMENTS`. Flags may appear in any order; stop at the first non-flag token. The remaining positional token is the skill name or absolute path.

- `--debug`: verbose progress output. Default: off.

## Style guide (Strunk & White, adapted for technical writing)

Apply to **prose only**. Do not alter any structural element.

**Preserve verbatim**: YAML frontmatter, fenced code blocks (``` and ~~~), inline code, HTML comments, heading text (so `references/*.md § <heading>` anchors still resolve), link targets, table cell structure, list markers, file paths, numeric values, identifiers.

**Rewrite**:

- **Omit needless words.** "In order to" → "to". "Due to the fact that" → "because". "At the present time" → "now". "For the purpose of" → "for". "Is able to" → "can".
- **Prefer active voice.** "The result is returned by the script" → "The script returns the result."
- **Use positive form.** "Do not fail to" → "remember to". "Not honest" → "dishonest".
- **Use definite, specific, concrete language.** Replace abstractions with names, counts, examples.
- **Keep related words together.** Do not split modifiers from what they modify.
- **One idea per sentence.** Split long sentences; do not coalesce short ones that carry distinct facts.

**Retain technical precision.** Never drop a qualifier that changes meaning (`usually`, `only when`, `at least`, `must`, `should`, `never`). If a word looks redundant but encodes an invariant or rationale, keep it.

## Anti-patterns

- **NEVER alter any line inside a fenced code block.** Why: code fences contain shell commands, regex patterns, YAML, JSON, mermaid, and example output that tests or harnesses match byte-exactly. A reworded example breaks the contract.
- **NEVER change heading text.** Why: citations like ``` `foo/SKILL.md § Step 3` ``` resolve to `## Step 3` by exact string; `scripts/test-subskill-anchors.sh` and similar harnesses fail-closed on a miss.
- **NEVER remove the "why" explanation from an anti-pattern or invariant.** Why: Section VI of `skill-design-principles.md` declares the "why" load-bearing — stripping it turns a strong anti-pattern into a weak one.
- **NEVER drop file-path or `file:line` citations.** Why: AGENTS.md, review harnesses, and cross-references depend on these tokens.
- **NEVER shorten a paragraph by under ~10%.** Why: marginal gains do not justify the drift risk; leave short paragraphs alone.
- **NEVER compress a file outside the target skill's directory tree.** Why: shared docs and callee skills have other consumers; a mutation here propagates.

When uncertain, keep the original wording. Meaning preservation beats compression.

## Progress Reporting

Follow the formatting rules in `${CLAUDE_PLUGIN_ROOT}/skills/shared/progress-reporting.md`.

Step Name Registry:

| Step | Short Name       |
|------|------------------|
| 0    | setup            |
| 1    | discover         |
| 2    | snapshot         |
| 3    | compress         |
| 4    | report           |
| 5    | cleanup          |

## Step 0 — Setup

Resolve the skill argument to an absolute skill directory (containing `SKILL.md`), create a session tmpdir, and emit the resolved values.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/setup.sh $ARGUMENTS
```

Parse output for `SKILL_DIR`, `SKILL_NAME`, `COMPRESS_TMPDIR`. On an `ERROR=` line, print the error and abort.

Set `debug_mode` from the `--debug` flag when present in `$ARGUMENTS`.

Print: `> **🔶 0: setup — <SKILL_NAME> at <SKILL_DIR>**`

## Step 1 — Discover Transitive `.md` Set

Starting from `SKILL.md`, walk Markdown link targets of the form `](path.md)` (with optional `#anchor`), resolve each relative to the referring file's directory, canonicalize, and keep only those whose resolved path lies inside `SKILL_DIR`. Links inside fenced code blocks are ignored.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/discover-md-set.sh --skill-dir "$SKILL_DIR" --output "$COMPRESS_TMPDIR/md-set.list"
```

The shell wrapper dispatches to `${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/discover-md-set.py` (Python — Markdown parsing with fenced-block exclusion and path canonicalization is cleaner than pure bash).

Parse output for `FILE_COUNT`. The list file contains NUL-delimited absolute paths in discovery order (breadth-first from `SKILL.md`). Read the list file to obtain the paths.

Print: `✅ 1: discover — <FILE_COUNT> file(s)`

## Step 2 — Snapshot Before Sizes

Record each file's byte and line count before compression.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/measure-set.sh --input "$COMPRESS_TMPDIR/md-set.list" --output "$COMPRESS_TMPDIR/before.tsv"
```

Parse output for `TOTAL_BYTES`, `TOTAL_LINES`. Save as `BYTES_BEFORE` and `LINES_BEFORE`.

Print: `✅ 2: snapshot — before: <BYTES_BEFORE> bytes, <LINES_BEFORE> lines`

## Step 3 — Compress Each File

For each absolute path in `$COMPRESS_TMPDIR/md-set.list`:

1. Read the file in full.
2. Apply the **Style guide** above to prose only. Preserve every structural element verbatim (frontmatter, fenced blocks, inline code, headings, link targets, list markers, table structure, file paths, numeric values, identifiers).
3. Write the compressed content back to the same path (use the Edit tool with `replace_all: false` on the whole file via a unique pre-existing anchor, or the Write tool for full-file replacement).

Per-file judgment rules:

- Compress sentence by sentence. A paragraph that is already lean stays as-is.
- A rewrite that shortens the paragraph by under ~10% is not worth the drift risk — keep the original.
- If any doubt remains about meaning equivalence, keep the original wording.
- Confirm every anti-pattern retains its **Why:** clause; every instruction retains its modal (`must`, `should`, `may`).

Print per-file progress only when `debug_mode=true`: `⏳ 3: compress — <path>`.

Print on step completion: `✅ 3: compress — <FILE_COUNT> file(s) rewritten`

## Step 4 — Report Deltas

Re-measure each file and emit a Markdown report comparing before and after.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/report-deltas.sh --input "$COMPRESS_TMPDIR/md-set.list" --before "$COMPRESS_TMPDIR/before.tsv" --output "$COMPRESS_TMPDIR/report.md"
```

Read `$COMPRESS_TMPDIR/report.md` and print it. The report shows per-file before/after byte and line counts, absolute deltas, and overall totals.

Print: `✅ 4: report — overall Δ printed above`

## Step 5 — Cleanup

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh --dir "$COMPRESS_TMPDIR"
```

Print: `✅ 5: cleanup — compress-skill complete`
