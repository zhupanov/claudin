#!/usr/bin/env bash
# resolve-target.sh — Resolve the target directory for a new /alias-generated skill.
#
# Usage:
#   resolve-target.sh --alias-name <name> [--private]
#
# Stdout (machine-readable, exactly three KEY=VALUE lines, in this order):
#   REPO_ROOT=<absolute path>
#   PLUGIN_REPO=true|false
#   TARGET_DIR=<absolute path>
#
# Stderr: human-readable diagnostics on error.
# Exit: 0 on success; 1 on usage error or fail-closed git failure.
#
# Plugin-repo detection uses the two-file predicate matching
# skills/create-skill/scripts/validate-args.sh:133 — both
# .claude-plugin/plugin.json AND skills/implement/SKILL.md must exist
# at the git repo root for PLUGIN_REPO=true. This guards against
# routing arbitrary Claude plugin repos (containing only plugin.json)
# to the larch skills/ tree.

set -euo pipefail

NAME=""
PRIVATE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --alias-name)
      # Arity guard: under `set -u`, dereferencing $2 without a value would
      # trip the unbound-variable error before our friendly --alias-name-required
      # message at the bottom can fire. Emit the documented ERROR contract instead.
      [[ $# -ge 2 ]] || { echo "ERROR: --alias-name requires a value" >&2; exit 1; }
      NAME="$2"
      shift 2
      ;;
    --private)    PRIVATE=true; shift ;;
    *) echo "ERROR: Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "ERROR: --alias-name is required" >&2
  exit 1
fi

if [[ ! "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  echo "ERROR: alias-name '$NAME' is invalid (must match ^[a-z][a-z0-9-]*\$)" >&2
  exit 1
fi

# Fail-closed: do NOT fall back to $PWD if git rev-parse fails.
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [[ -z "$REPO_ROOT" ]]; then
  echo "ERROR: not in a git repository" >&2
  exit 1
fi

if [[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]] \
  && [[ -f "$REPO_ROOT/skills/implement/SKILL.md" ]]; then
  PLUGIN_REPO=true
else
  PLUGIN_REPO=false
fi

if [[ "$PLUGIN_REPO" == "true" ]] && [[ "$PRIVATE" == "false" ]]; then
  TARGET_DIR="$REPO_ROOT/skills/$NAME"
else
  TARGET_DIR="$REPO_ROOT/.claude/skills/$NAME"
fi

echo "REPO_ROOT=$REPO_ROOT"
echo "PLUGIN_REPO=$PLUGIN_REPO"
echo "TARGET_DIR=$TARGET_DIR"
