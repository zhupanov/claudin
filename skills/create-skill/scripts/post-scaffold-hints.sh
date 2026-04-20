#!/usr/bin/env bash
# post-scaffold-hints.sh — Print human-readable reminders after a scaffold.
#
# Required flags:
#   --target-dir <path>  Absolute path of the new skill directory.
#   --plugin true|false  Whether this was a plugin-dev-mode scaffold.

set -euo pipefail

TARGET_DIR=""
PLUGIN=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target-dir) TARGET_DIR="$2"; shift 2 ;;
    --plugin)     PLUGIN="$2";     shift 2 ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$TARGET_DIR" ]]; then
  echo "ERROR=Missing --target-dir" >&2
  exit 1
fi

NAME="$(basename "$TARGET_DIR")"

echo "Scaffolded: $TARGET_DIR/SKILL.md"
echo ""
echo "Next steps:"
echo "  - Open $TARGET_DIR/SKILL.md and fill in the TODO body."
echo "  - Every operational step must live in a .sh under $TARGET_DIR/scripts/."
echo "    Do NOT place raw bash commands in SKILL.md."
echo "  - If a script is needed by two or more skills, promote it to the shared scripts/ directory instead."

if [[ "$PLUGIN" == "true" ]]; then
  echo ""
  echo "Plugin-dev reminders:"
  echo "  - Add a row for /$NAME to README.md (Skills catalog + feature matrix)."
  echo "  - Add the following entries to .claude/settings.json permissions.allow,"
  echo "    then re-sort the whole permissions.allow block by strict ASCII"
  echo "    code-point order (e.g. via sort -u):"
  echo "      \"Bash(\$PWD/skills/$NAME/scripts/*)\""
  echo "      \"Skill($NAME)\""
  echo "      \"Skill(larch:$NAME)\""
  echo "  - Both Skill forms are required for strict-permissions consumers; see"
  echo "    README subsection \"Strict-permissions consumers — Skill permission entries\" for rationale."
fi

if [[ -d "$PWD/.claude/skills/relevant-checks" ]]; then
  echo ""
  echo "  - Run /relevant-checks after editing the scaffold."
fi
