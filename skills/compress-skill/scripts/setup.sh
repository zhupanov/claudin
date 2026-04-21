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
# On error (stdout, exit 1):
#   ERROR=<message>
# Placing ERROR= on stdout matches the SKILL.md Step 0 "parse output for
# ERROR= line" directive — the orchestrator reads only stdout.

set -euo pipefail

ARG=""
DEBUG=false
while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG=true; shift ;;
    --) shift; break ;;
    -*) echo "ERROR=Unknown flag: $1"; exit 1 ;;
    *)
      if [[ -n "$ARG" ]]; then
        echo "ERROR=Unexpected extra argument: $1 (skill name/path already set to '$ARG')"
        exit 1
      fi
      ARG="$1"
      shift
      ;;
  esac
done

if [[ -z "$ARG" ]]; then
  echo "ERROR=Missing required positional argument: skill name or absolute path"
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
    echo "ERROR=No SKILL.md at absolute path: $ARG"
    exit 1
  fi
else
  # Enforce the same name regex /create-skill applies at scaffold time:
  # ^[a-z][a-z0-9-]*$. Names outside this shape (uppercase, leading digit,
  # leading hyphen, embedded slash, '..', etc.) risk escaping the intended
  # skills/<name> tree when joined under ${CLAUDE_PLUGIN_ROOT}/skills/ or
  # $PWD/.claude/skills/, or simply diverge from plugin conventions.
  if ! [[ "$ARG" =~ ^[a-z][a-z0-9-]*$ ]]; then
    echo "ERROR=Invalid skill name '$ARG' — must match ^[a-z][a-z0-9-]*\$ or be an absolute path"
    exit 1
  fi
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
    echo "ERROR=Could not resolve skill '$ARG'. Tried: ${TRIED[*]}"
    exit 1
  fi
fi

SKILL_NAME="$(basename "$SKILL_DIR")"
# Literal /tmp prefix (matching scripts/session-setup.sh and scripts/cleanup-tmpdir.sh's
# allowlist). macOS's default TMPDIR points to /var/folders/... which cleanup-tmpdir.sh
# refuses, leaving the session dir behind. The Step 5 cleanup invocation depends on the
# path matching /tmp/ or /private/tmp/.
COMPRESS_TMPDIR="$(mktemp -d "/tmp/claude-compress-skill-XXXXXX")"

printf 'SKILL_DIR=%s\n' "$SKILL_DIR"
printf 'SKILL_NAME=%s\n' "$SKILL_NAME"
printf 'COMPRESS_TMPDIR=%s\n' "$COMPRESS_TMPDIR"

if [[ "$DEBUG" == "true" ]]; then
  printf 'DEBUG=true\n'
fi
