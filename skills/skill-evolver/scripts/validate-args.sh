#!/usr/bin/env bash
# validate-args.sh — Parse and validate /skill-evolver arguments.
#
# Positional:
#   <skill-name>  First positional. Leading '/' is stripped. Must match
#                 ^[a-z][a-z0-9-]*$ and resolve to an existing skill directory
#                 (skills/<name>/SKILL.md preferred; .claude/skills/<name>/SKILL.md
#                 as project-local fallback).
#
# Output (stdout, key=value lines):
#   VALID=true|false
#   SKILL_NAME=<canonical name>     # only when VALID=true
#   SKILL_DIR=<absolute path>       # only when VALID=true
#   ERROR=<msg>                     # only when VALID=false
#
# Exit code is always 0 — the VALID=false line is the orchestrator's branch
# signal, not the exit code.

set -euo pipefail

SKILL_NAME=""

emit_invalid() {
  printf 'VALID=false\n'
  printf 'ERROR=%s\n' "$1"
  exit 0
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --) shift; break ;;
    --*) emit_invalid "Unknown flag '$1'. /skill-evolver accepts no flags." ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  emit_invalid "Missing <skill-name>. Usage: /skill-evolver <skill-name>"
fi

SKILL_NAME="$1"
shift

# Strip a single leading '/' if the user passed /foo instead of foo.
SKILL_NAME="${SKILL_NAME#/}"

if [[ $# -gt 0 ]]; then
  emit_invalid "Unexpected extra arguments after <skill-name>: $*"
fi

if [[ -z "$SKILL_NAME" ]]; then
  emit_invalid "Mandatory <skill-name> argument is empty after stripping leading '/'."
fi

if [[ ! "$SKILL_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  emit_invalid "Skill name must match ^[a-z][a-z0-9-]*\$ (got: $SKILL_NAME)."
fi

if (( ${#SKILL_NAME} > 64 )); then
  emit_invalid "Skill name too long (${#SKILL_NAME} chars > 64)."
fi

# Validate CWD is a larch plugin repo. Same gate as skills/create-skill/scripts/validate-args.sh.
if [[ ! -f .claude-plugin/plugin.json ]] || [[ ! -f skills/implement/SKILL.md ]]; then
  emit_invalid "CWD is not a larch plugin repo (.claude-plugin/plugin.json + skills/implement/SKILL.md required)."
fi

# Locate target skill (plugin tree first, then project-local).
SKILL_DIR=""
if [[ -f "skills/${SKILL_NAME}/SKILL.md" ]]; then
  SKILL_DIR="$(cd "skills/${SKILL_NAME}" && pwd)"
elif [[ -f ".claude/skills/${SKILL_NAME}/SKILL.md" ]]; then
  SKILL_DIR="$(cd ".claude/skills/${SKILL_NAME}" && pwd)"
else
  emit_invalid "Target skill not found at skills/${SKILL_NAME}/SKILL.md or .claude/skills/${SKILL_NAME}/SKILL.md."
fi

printf 'VALID=true\n'
printf 'SKILL_NAME=%s\n' "$SKILL_NAME"
printf 'SKILL_DIR=%s\n' "$SKILL_DIR"
exit 0
