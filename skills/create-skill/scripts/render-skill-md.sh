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
    echo "ERROR=Missing required argument --${arg,,}" >&2
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

# --- YAML-escape the description (always double-quoted, inner " → \") ---
ESCAPED_DESC="${DESCRIPTION//\"/\\\"}"

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
  Every operational step below MUST invoke a .sh under ${LOCAL_TOKEN}/${TARGET_DIR##*/}/scripts/.
  Do NOT place raw bash commands in this SKILL.md — wrap every command in a script.
  Shared scripts (used by two or more skills) should live under ${PLUGIN_TOKEN}/scripts/ instead.
-->

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

## Step 0 — Setup

<!-- TODO: invoke ${LOCAL_TOKEN}/${TARGET_DIR##*/}/scripts/setup.sh -->

## Step 1 — TODO

<!-- TODO: invoke ${LOCAL_TOKEN}/${TARGET_DIR##*/}/scripts/step1.sh -->

## Step N — Cleanup

<!-- TODO: invoke ${PLUGIN_TOKEN}/scripts/cleanup-tmpdir.sh --dir "\$<SKILL>_TMPDIR" -->
MULTI_STEP_BODY
else
  cat >> "$TMP_FILE" <<MINIMAL_BODY
${DESCRIPTION}

<!--
  TODO (author): replace this scaffold with the real skill.
  Every operational step you add MUST invoke a .sh under ${LOCAL_TOKEN}/${TARGET_DIR##*/}/scripts/.
  Do NOT place raw bash commands in this SKILL.md — wrap every command in a script.
  Shared scripts (used by two or more skills) should live under ${PLUGIN_TOKEN}/scripts/ instead.
-->
MINIMAL_BODY
fi

# Atomic move into place.
mv "$TMP_FILE" "$TARGET_DIR/SKILL.md"

echo "RENDERED=$TARGET_DIR/SKILL.md"
