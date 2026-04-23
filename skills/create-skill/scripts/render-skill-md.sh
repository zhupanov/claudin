#!/usr/bin/env bash
# render-skill-md.sh — Scaffold a new skill directory and SKILL.md.
#
# Writes:
#   <target-dir>/
#   ├── SKILL.md          (frontmatter + minimal or multi-step body scaffold)
#   └── scripts/
#       └── .gitkeep
#
# Required flags:
#   --name <name>                Validated skill name.
#   --description <desc>         Validated description (already sanitized by validate-args.sh).
#   --target-dir <absolute-path> Absolute path where the new skill dir will live
#                                (e.g. /path/.claude/skills/foo or /path/skills/foo).
#   --local-token <token>        Literal path token to embed in generated SKILL.md
#                                for the new skill's OWN scripts directory — either
#                                $PWD or ${CLAUDE_PLUGIN_ROOT}.
#   --plugin-token <token>       Literal path token to embed for SHARED larch
#                                references — always ${CLAUDE_PLUGIN_ROOT}.
#   --multi-step true|false      Select scaffold variant.
#
# Behavior:
#   - mkdir -p for the parent directory (safe on fresh consumer repos).
#   - mkdir (no -p) for the final leaf (fails loudly on collision / concurrent run).
#   - Atomic write: SKILL.md.tmp then mv into place.
#   - scripts/.gitkeep created; no placeholder step scripts are generated
#     (bodies are TODO-only so there are no dangling script references).
#   - Description is YAML-escaped (always double-quoted, inner " backslash-escaped).
#     Newlines and control chars are already rejected by validate-args.sh.

set -euo pipefail

NAME=""
DESCRIPTION=""
TARGET_DIR=""
LOCAL_TOKEN=""
PLUGIN_TOKEN=""
MULTI_STEP=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)         NAME="$2";         shift 2 ;;
    --description)  DESCRIPTION="$2";  shift 2 ;;
    --target-dir)   TARGET_DIR="$2";   shift 2 ;;
    --local-token)  LOCAL_TOKEN="$2";  shift 2 ;;
    --plugin-token) PLUGIN_TOKEN="$2"; shift 2 ;;
    --multi-step)   MULTI_STEP="$2";   shift 2 ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

for arg in NAME DESCRIPTION TARGET_DIR LOCAL_TOKEN PLUGIN_TOKEN; do
  if [[ -z "${!arg}" ]]; then
    # Lowercase via tr — portable to bash 3.2 (macOS default).
    arg_flag="$(printf '%s' "$arg" | tr '[:upper:]' '[:lower:]' | tr '_' '-')"
    echo "ERROR=Missing required argument --${arg_flag}" >&2
    exit 1
  fi
done

# --- Prepare target directory ---

PARENT_DIR="$(dirname "$TARGET_DIR")"
mkdir -p "$PARENT_DIR"

# Final leaf: mkdir (no -p) so collision and concurrent-invocation races fail loudly.
if ! mkdir "$TARGET_DIR" 2>/dev/null; then
  echo "ERROR=Target directory already exists: $TARGET_DIR" >&2
  exit 1
fi

mkdir "$TARGET_DIR/scripts"
: > "$TARGET_DIR/scripts/.gitkeep"

# --- YAML-escape the description. YAML double-quoted scalars interpret
# backslash as an escape character, so both \ and " must be escaped.
# Order matters: escape backslashes FIRST, then escape double quotes.
ESCAPED_DESC="${DESCRIPTION//\\/\\\\}"
ESCAPED_DESC="${ESCAPED_DESC//\"/\\\"}"

# --- Derive the full skill-relative path (e.g. `.claude/skills/foo` or
# `skills/foo`) so the generated SKILL.md reminders point to the ACTUAL
# scripts/ directory, not just the leaf name. In consumer mode the layout
# under $PWD is `.claude/skills/<name>`; in plugin mode under
# ${CLAUDE_PLUGIN_ROOT} it is `skills/<name>`.
NAME_LEAF="$(basename "$TARGET_DIR")"
# Derive from TARGET_DIR rather than LOCAL_TOKEN — robust regardless of
# whether the caller passes $PWD or an expanded absolute path. Consumer
# scaffolds live under `.../.claude/skills/<name>`; plugin scaffolds under
# `.../skills/<name>`.
case "$TARGET_DIR" in
  */.claude/skills/*) SKILL_REL=".claude/skills/${NAME_LEAF}" ;;
  */skills/*)         SKILL_REL="skills/${NAME_LEAF}" ;;
  *)
    echo "ERROR=Unable to derive skill-relative path from --target-dir=$TARGET_DIR (expected it to contain /.claude/skills/ or /skills/)." >&2
    exit 1
    ;;
esac

# --- Render SKILL.md ---

TMP_FILE="$TARGET_DIR/SKILL.md.tmp"

# Frontmatter is identical for both variants.
{
  printf -- '---\n'
  printf 'name: %s\n' "$NAME"
  printf 'description: "%s"\n' "$ESCAPED_DESC"
  printf 'argument-hint: ""\n'
  printf 'allowed-tools: Bash, Read\n'
  printf -- '---\n\n'
  printf '# %s\n\n' "$NAME"
} > "$TMP_FILE"

if [[ "$MULTI_STEP" == "true" ]]; then
  cat >> "$TMP_FILE" <<MULTI_STEP_BODY
${DESCRIPTION}

<!--
  TODO (author): replace this scaffold with the real skill.
  Every operational step below MUST invoke a .sh under ${LOCAL_TOKEN}/${SKILL_REL}/scripts/.
  Do NOT place raw bash commands in this SKILL.md — wrap every command in a script.
  Shared scripts (used by two or more skills) should live under ${PLUGIN_TOKEN}/scripts/ instead.
-->

> **Before editing, read \`${PLUGIN_TOKEN}/skills/shared/skill-design-principles.md\`** — canonical larch skill-design principles (knowledge delta, structure, mechanical rules A/B/C, anti-patterns). Section III overrides general writing-style guidance.

## Flags

Parse flags from the start of \$ARGUMENTS. Flags may appear in any order; stop at the first non-flag token.

- \`--debug\`: Set \`debug_mode=true\`. Default: \`debug_mode=false\`.

## Progress Reporting

Follow the formatting rules in \`${PLUGIN_TOKEN}/skills/shared/progress-reporting.md\`.

Step Name Registry:
| Step | Short Name |
|------|------------|
| 0 | setup |
| 1 | TODO |
| ... | ... |

## Sub-skill Invocation

If this skill invokes another skill via the \`Skill\` tool, read \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` for the full conventions. Quick checklist:

1. Pick one of two invocation shapes (Pattern A bulleted or Pattern B inline). Do not bury the Skill-tool call in a prose conditional.
2. Use the bare name first (e.g., \`"implement"\`), then the fully-qualified \`larch:<name>\` fallback. Never start with the fully-qualified name.
3. If this skill delegates to another skill, widen the \`allowed-tools\` frontmatter to include \`Skill\` — the scaffold default is \`Bash, Read\`, which silently blocks \`Skill\` invocations.
4. For orchestrators that continue based on child side effects, pair the Skill call with a mechanical verification (commit-count delta, parsed stdout key, or sentinel file).
5. For state that must cross skill boundaries (reviewer health, repo name, slack-ok, session tmpdir), write a \`session-env.sh\` and pass \`--session-env <path>\` to the child. Never \`source\` the file — parse it line-by-line.
6. **Anti-halt continuation reminder** (orchestrators only — closes #177): if this skill runs additional steps after a child Skill call returns, include the canonical top-of-file banner and per-call-site micro-reminders from \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` section Anti-halt continuation reminder. Pure delegators (enumerated in \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` section "Scope list") are exempt. The banner and micro-reminder substrings are asserted by \`${PLUGIN_TOKEN}/scripts/test-anti-halt-banners.sh\` (wired into \`make lint\` via the \`test-anti-halt\` target).

If this skill does not delegate to any other skill, delete this entire section.

## Step 0 — Setup

<!-- TODO: invoke ${LOCAL_TOKEN}/${SKILL_REL}/scripts/setup.sh -->

## Step 1 — TODO

<!-- TODO: invoke ${LOCAL_TOKEN}/${SKILL_REL}/scripts/step1.sh -->

## Step N — Cleanup

<!-- TODO: invoke ${PLUGIN_TOKEN}/scripts/cleanup-tmpdir.sh --dir "\$<SKILL>_TMPDIR" -->
MULTI_STEP_BODY
else
  cat >> "$TMP_FILE" <<MINIMAL_BODY
${DESCRIPTION}

<!--
  TODO (author): replace this scaffold with the real skill.
  Every operational step you add MUST invoke a .sh under ${LOCAL_TOKEN}/${SKILL_REL}/scripts/.
  Do NOT place raw bash commands in this SKILL.md — wrap every command in a script.
  Shared scripts (used by two or more skills) should live under ${PLUGIN_TOKEN}/scripts/ instead.
-->

> **Before editing, read \`${PLUGIN_TOKEN}/skills/shared/skill-design-principles.md\`** — canonical larch skill-design principles (knowledge delta, structure, mechanical rules A/B/C, anti-patterns). Section III overrides general writing-style guidance.

## Sub-skill Invocation

If this skill invokes another skill via the \`Skill\` tool, read \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` for the full conventions. Quick checklist:

1. Pick one of two invocation shapes (Pattern A bulleted or Pattern B inline). Do not bury the Skill-tool call in a prose conditional.
2. Use the bare name first (e.g., \`"implement"\`), then the fully-qualified \`larch:<name>\` fallback. Never start with the fully-qualified name.
3. If this skill delegates to another skill, widen the \`allowed-tools\` frontmatter to include \`Skill\` — the scaffold default is \`Bash, Read\`, which silently blocks \`Skill\` invocations.
4. For orchestrators that continue based on child side effects, pair the Skill call with a mechanical verification (commit-count delta, parsed stdout key, or sentinel file).
5. For state that must cross skill boundaries (reviewer health, repo name, slack-ok, session tmpdir), write a \`session-env.sh\` and pass \`--session-env <path>\` to the child. Never \`source\` the file — parse it line-by-line.
6. **Anti-halt continuation reminder** (orchestrators only — closes #177): if this skill runs additional steps after a child Skill call returns, include the canonical top-of-file banner and per-call-site micro-reminders from \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` section Anti-halt continuation reminder. Pure delegators (enumerated in \`${PLUGIN_TOKEN}/skills/shared/subskill-invocation.md\` section "Scope list") are exempt. The banner and micro-reminder substrings are asserted by \`${PLUGIN_TOKEN}/scripts/test-anti-halt-banners.sh\` (wired into \`make lint\` via the \`test-anti-halt\` target).

If this skill does not delegate to any other skill, delete this entire section.
MINIMAL_BODY
fi

# Atomic move into place.
mv "$TMP_FILE" "$TARGET_DIR/SKILL.md"

echo "RENDERED=$TARGET_DIR/SKILL.md"
