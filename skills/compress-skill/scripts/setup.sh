#!/usr/bin/env bash
# setup.sh — Resolve /compress-skill's argument to an absolute skill directory,
# create a session tmpdir, and emit key=value lines for the caller.
#
# Usage:
#   setup.sh [--debug] <skill-name-or-path>
#
# Resolution order for a bare <skill-name>:
#   1. ${CLAUDE_PLUGIN_ROOT}/skills/<name>/
#   2. $PWD/skills/<name>/
#   3. $PWD/.claude/skills/<name>/
#
# An absolute path is used as-is (must exist and contain SKILL.md).
#
# Output (stdout):
#   SKILL_DIR=<abs path>
#   SKILL_NAME=<basename>
#   COMPRESS_TMPDIR=<abs path>
# On error:
#   ERROR=<message>   (exit 1)

set -euo pipefail

ARG=""
DEBUG=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG=true; shift ;;
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

resolve_dir() {
  local candidate="$1"
  if [[ -d "$candidate" && -f "$candidate/SKILL.md" ]]; then
    (cd "$candidate" && pwd -P)
    return 0
  fi
  return 1
}

SKILL_DIR=""
if [[ "$ARG" = /* ]]; then
  if ! SKILL_DIR="$(resolve_dir "$ARG")"; then
    echo "ERROR=No SKILL.md at absolute path: $ARG" >&2
    exit 1
  fi
else
  TRIED=()
  if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
    CANDIDATE="${CLAUDE_PLUGIN_ROOT}/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if SKILL_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$SKILL_DIR" ]]; then
    CANDIDATE="${PWD}/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if SKILL_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$SKILL_DIR" ]]; then
    CANDIDATE="${PWD}/.claude/skills/${ARG}"
    TRIED+=("$CANDIDATE")
    if SKILL_DIR="$(resolve_dir "$CANDIDATE")"; then :; fi
  fi
  if [[ -z "$SKILL_DIR" ]]; then
    echo "ERROR=Could not resolve skill '$ARG'. Tried: ${TRIED[*]}" >&2
    exit 1
  fi
fi

SKILL_NAME="$(basename "$SKILL_DIR")"
COMPRESS_TMPDIR="$(mktemp -d "${TMPDIR:-/tmp}/claude-compress-skill-XXXXXX")"

printf 'SKILL_DIR=%s\n' "$SKILL_DIR"
printf 'SKILL_NAME=%s\n' "$SKILL_NAME"
printf 'COMPRESS_TMPDIR=%s\n' "$COMPRESS_TMPDIR"

if [[ "$DEBUG" == "true" ]]; then
  printf 'DEBUG=true\n'
fi
