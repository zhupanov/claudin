#!/usr/bin/env bash
# build-feature-description.sh — Resolve the target skill, enumerate the
# transitively-reachable .md set inside the skill dir, snapshot baseline
# sizes, and compose the /implement feature description for /compress-skill.
#
# Usage:
#   build-feature-description.sh <skill-name-or-absolute-path>
#
# Resolution order for a bare <skill-name> (leading "/" is stripped before
# resolution, so both `implement` and `/implement` are accepted as bare names):
#   1. ${CLAUDE_PLUGIN_ROOT}/skills/<name>/
#   2. $PWD/skills/<name>/
#   3. $PWD/.claude/skills/<name>/
#   4. ${CLAUDE_PLUGIN_ROOT}/.claude/skills/<name>/
# An absolute path (with >1 segment) is used as-is (must exist and contain SKILL.md).
#
# Stdout contract (always one KEY=VALUE per line):
#   On success:
#     STATUS=ok
#     TARGET_DIR=<absolute-path-to-target-skill-dir>
#     SKILL_NAME=<basename>
#     FILE_COUNT=<n>
#     FEATURE_FILE=<absolute-path-to-temp-file-containing-feature-description>
#   On failure:
#     STATUS=not_found|bad_name
#     ERROR=<human-readable message>
#
# Fail-closed contract: exit 0 in all STATUS branches so the caller can parse
# stdout. Exit 1 only on internal errors (unparseable args, mktemp failure,
# discovery-script failure).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

ARG=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; break ;;
    -*) echo "ERROR=Unknown flag: $1" >&2; exit 1 ;;
    *)
      if [[ -n "$ARG" ]]; then
        echo "ERROR=Unexpected extra argument: $1 (skill name/path already set to '$ARG')" >&2
        exit 1
      fi
      ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$ARG" ]]; then
  echo "ERROR=Missing required positional argument: skill name or absolute path" >&2
  exit 1
fi

# Strip a single leading slash when ARG matches the bare-name regex so that
# both `implement` and `/implement` route through the same probe chain rather
# than being misread as the filesystem root.
if [[ "$ARG" =~ ^/[a-z][a-z0-9-]*$ ]]; then
  ARG="${ARG#/}"
fi

# --- Resolve target directory ---

resolve_dir() {
  local candidate="$1"
  if [[ -d "$candidate" && -f "$candidate/SKILL.md" ]]; then
    (cd "$candidate" && pwd -P)
    return 0
  fi
  return 1
}

TARGET_DIR=""
if [[ "$ARG" = /* ]]; then
  if ! TARGET_DIR="$(resolve_dir "$ARG")"; then
    printf 'STATUS=not_found\n'
    printf 'ERROR=No SKILL.md at absolute path: %s\n' "$ARG"
    exit 0
  fi
else
  # Same name regex as /create-skill scaffolding.
  if ! [[ "$ARG" =~ ^[a-z][a-z0-9-]*$ ]]; then
    printf 'STATUS=bad_name\n'
    printf 'ERROR=Invalid skill name %s — must match ^[a-z][a-z0-9-]*$ or be an absolute path.\n' "$ARG"
    exit 0
  fi
  TRIED=()
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    CANDIDATE="${CLAUDE_PLUGIN_ROOT}/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if TARGET_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$TARGET_DIR" ]]; then
    CANDIDATE="${PWD}/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if TARGET_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$TARGET_DIR" ]]; then
    CANDIDATE="${PWD}/.claude/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if TARGET_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$TARGET_DIR" ]] && [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    CANDIDATE="${CLAUDE_PLUGIN_ROOT}/.claude/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if TARGET_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$TARGET_DIR" ]]; then
    printf 'STATUS=not_found\n'
    printf 'ERROR=Could not resolve skill %s. Tried: %s\n' "$ARG" "${TRIED[*]}"
    exit 0
  fi
fi

SKILL_NAME="$(basename "$TARGET_DIR")"

# --- Discover transitive .md set ---

TMP_LIST="$(mktemp -t compress-skill-mdset.XXXXXX)"
# Capture stdout only; let stderr stream through so warnings stay visible
# and cannot contaminate the FILE_COUNT= line parse.
DISCOVER_OUT="$("$SCRIPT_DIR/discover-md-set.sh" --skill-dir "$TARGET_DIR" --output "$TMP_LIST")" || {
  rm -f "$TMP_LIST"
  echo "ERROR=discover-md-set.sh failed" >&2
  exit 1
}

FILE_COUNT="$(printf '%s\n' "$DISCOVER_OUT" | awk -F= '/^FILE_COUNT=/{print $2}')"
if [[ -z "$FILE_COUNT" ]]; then
  rm -f "$TMP_LIST"
  echo "ERROR=discover-md-set.sh did not emit FILE_COUNT. Output: $DISCOVER_OUT" >&2
  exit 1
fi

# --- Measure baseline sizes ---
# Read NUL-delimited path list; build Markdown-table rows and totals.

FEATURE_FILE="$(mktemp -t compress-skill-feature.XXXXXX)" || {
  rm -f "$TMP_LIST"
  echo "ERROR=Failed to create feature-description temp file" >&2
  exit 1
}

BEFORE_TABLE_ROWS=""
FILE_LIST_BULLETS=""
TOTAL_BYTES=0
TOTAL_LINES=0

while IFS= read -r -d '' path; do
  [[ -z "$path" ]] && continue
  bytes=$(wc -c < "$path" | tr -d '[:space:]')
  lines=$(wc -l < "$path" | tr -d '[:space:]')
  TOTAL_BYTES=$((TOTAL_BYTES + bytes))
  TOTAL_LINES=$((TOTAL_LINES + lines))
  # Relativize path under TARGET_DIR for readability in the feature description.
  rel="${path#"${TARGET_DIR}"/}"
  BEFORE_TABLE_ROWS="${BEFORE_TABLE_ROWS}| ${rel} | ${bytes} / ${lines} |"$'\n'
  FILE_LIST_BULLETS="${FILE_LIST_BULLETS}  - ${path}"$'\n'
done < "$TMP_LIST"

rm -f "$TMP_LIST"

# --- Compose the feature description ---

cat >"$FEATURE_FILE" <<FEATURE_EOF
Compress the Markdown prose of the /${SKILL_NAME} skill by applying Strunk & White's *Elements of Style* (adapted for technical writing) to every in-scope .md file. BEHAVIOR-PRESERVING — no semantic changes, no feature changes, no citation drift. Meaning preservation beats compression.

Target skill directory: ${TARGET_DIR}
In-scope file count: ${FILE_COUNT}

In-scope .md files (SKILL.md first, then every .md file reachable from SKILL.md via Markdown links or path-shaped backticked references, restricted to the skill's own directory tree):
${FILE_LIST_BULLETS}
OUT OF SCOPE (do NOT edit under any circumstance):
  - Any skill invoked by /${SKILL_NAME} via the Skill tool (each sub-skill is an independent target).
  - Files under \${CLAUDE_PLUGIN_ROOT}/skills/shared/ or top-level docs (AGENTS.md, README.md, SECURITY.md, CHANGELOG.md, etc.).
  - Any .md file whose resolved path is outside ${TARGET_DIR}/ even if cited from within.

## Baseline sizes (before compression)

| File (relative to target skill dir) | Before (bytes / lines) |
|-------------------------------------|------------------------|
${BEFORE_TABLE_ROWS}| **Total** | ${TOTAL_BYTES} / ${TOTAL_LINES} |

## Style guide (Strunk & White, adapted for technical writing)

Apply to **prose only**. Never alter any structural element.

**Preserve verbatim** (byte-identical):
- YAML frontmatter
- Fenced code blocks (\`\`\` and ~~~) — every line inside a fence is untouchable
- Inline code spans
- HTML comments
- Heading text (so \`references/*.md § <heading>\` anchors still resolve)
- Link targets
- Table cell structure
- List markers
- File paths
- Numeric values, identifiers, flag names, shell variable names

**Rewrite prose** following these principles:
- **Omit needless words.** "In order to" → "to". "Due to the fact that" → "because". "At the present time" → "now". "For the purpose of" → "for". "Is able to" → "can".
- **Prefer active voice.** "The result is returned by the script" → "The script returns the result."
- **Use positive form.** "Do not fail to" → "remember to". "Not honest" → "dishonest".
- **Use definite, specific, concrete language.** Replace abstractions with names, counts, examples.
- **Keep related words together.** Do not split modifiers from what they modify.
- **One idea per sentence.** Split long sentences; do not coalesce short ones that carry distinct facts.

**Retain technical precision.** Never drop a qualifier that changes meaning (\`usually\`, \`only when\`, \`at least\`, \`must\`, \`should\`, \`never\`). If a word looks redundant but encodes an invariant or rationale, keep it.

## Anti-patterns (MUST NOT be violated)

- **NEVER alter any line inside a fenced code block.** Why: fences contain shell commands, regex patterns, YAML, JSON, mermaid diagrams, and example output that tests or harnesses match byte-exactly. A reworded example breaks the contract.
- **NEVER change heading text.** Why: citations like \`foo/SKILL.md § Step 3\` resolve to \`## Step 3\` by exact string match; harnesses fail closed on a miss.
- **NEVER remove the "why" explanation from an anti-pattern or invariant.** Why: skill-design-principles Section VI declares the "why" load-bearing — stripping it turns a strong anti-pattern into a weak one.
- **NEVER drop file-path or \`file:line\` citations.** Why: AGENTS.md, review harnesses, and cross-references depend on these tokens.
- **NEVER shorten a paragraph by under ~10%.** Why: marginal gains do not justify drift risk; leave short paragraphs alone.
- **NEVER compress a file outside the target skill's directory tree.** Why: shared docs and callee skills have other consumers; a mutation here propagates silently.
- **NEVER introduce feature or behavior changes.** Why: this is a prose-compression pass; any semantic change violates the contract and destabilizes downstream callers.

## Per-file judgment rules

- Compress sentence by sentence. A paragraph that is already lean stays as-is.
- A rewrite that shortens the paragraph by under ~10% is not worth the drift risk — keep the original.
- If any doubt remains about meaning equivalence, keep the original wording.
- Confirm every anti-pattern retains its **Why:** clause; every instruction retains its modal (\`must\`, \`should\`, \`may\`).
- When uncertain, keep the original wording. Meaning preservation beats compression.

## Verification plan

- After rewriting, run /relevant-checks to ensure Markdown validity and no broken references.
- Re-measure each in-scope file (\`wc -c\` and \`wc -l\`) and include the delta in the PR body (see below).
- Spot-check that all fenced code blocks, YAML frontmatter, and headings are byte-identical.

## PR body MUST include a "## Token budget" section

Use this exact table shape, re-measuring each file after compression:

\`\`\`markdown
## Token budget

| File (relative to ${TARGET_DIR}) | Before (bytes / lines) | After (bytes / lines) | Delta (bytes / lines) |
|----------------------------------|------------------------|------------------------|------------------------|
| <each in-scope file> | <before> | <after> | <signed-delta> |
| **Total** | ${TOTAL_BYTES} / ${TOTAL_LINES} | <new-total> | <signed-total-delta> |
\`\`\`

A net-zero or positive total-delta means the pass produced no useful compression — flag this in the PR body and justify (acceptable when every paragraph was already at or below the ~10% threshold).
FEATURE_EOF

# --- Emit machine output ---

printf 'STATUS=ok\n'
printf 'TARGET_DIR=%s\n' "$TARGET_DIR"
printf 'SKILL_NAME=%s\n' "$SKILL_NAME"
printf 'FILE_COUNT=%s\n' "$FILE_COUNT"
printf 'FEATURE_FILE=%s\n' "$FEATURE_FILE"
