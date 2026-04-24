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
echo "  - If this skill invokes another skill via the Skill tool, read"
echo "    \${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md for the canonical"
echo "    sub-skill invocation conventions (patterns, allowed-tools narrowing, session-env handoff)."

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
  echo "    docs/configuration-and-permissions.md subsection \"Strict-permissions consumers — Skill permission entries\" for rationale."
  echo "  - Update docs/workflow-lifecycle.md — if /$NAME is a stateful orchestrator,"
  echo "    add it to the Skill Orchestration Hierarchy mermaid; if /$NAME is a pure"
  echo "    forwarder/delegator, add it to the Delegation Topology subsection. Also"
  echo "    add a Standalone Usage bullet."
  echo "  - Update docs/agents.md when applicable (your skill spawns subagents via the Agent tool)."
  echo "  - Update docs/review-agents.md when applicable (your skill alters reviewer composition or archetypes)."
  echo "  - Update AGENTS.md Canonical sources list when applicable (your skill introduces a shared script used by multiple skills, or is itself a canonical source)."
fi

if [[ -d "$PWD/.claude/skills/relevant-checks" ]]; then
  echo ""
  echo "  - Run /relevant-checks after editing the scaffold."
fi
