#!/usr/bin/env bash
# parse-args.sh — Parse /create-skill arguments.
#
# Flags (stop at first non-flag token):
#   --plugin      Write to skills/<name>/ with ${CLAUDE_PLUGIN_ROOT} path token.
#                 Default: .claude/skills/<name>/ with $PWD path token.
#   --multi-step  Emit the multi-step scaffold.
#                 Default: minimal single-step scaffold.
#   --merge       Accepted for backward compatibility. /create-skill delegates via /im
#                 (which prepends --merge), so this flag is redundant and is NOT forwarded
#                 to the child skill. Kept in the parser to avoid breaking existing
#                 invocations that pass it explicitly.
#   --debug       Forward to /im (which forwards to /implement).
#   --no-slack    Forward to /im (which forwards to /implement). When set, the delegated
#                 /implement run does NOT post a Slack announcement. Default (no --no-slack):
#                 delegated run posts per /implement's default-on behavior (gated on
#                 Slack env vars).
#
# Positional (after flags):
#   <skill-name>  First positional. Leading '/' is stripped.
#   <description> Remainder of the argument string, verbatim.
#
# Output (stdout, key=value lines):
#   NAME=<name>
#   DESCRIPTION=<description>
#   PLUGIN=true|false
#   MULTI_STEP=true|false
#   MERGE=true|false
#   DEBUG=true|false
#   NO_SLACK=true|false
#
# On failure, emits `ERROR=<msg>` to stdout and exits non-zero.

set -euo pipefail

PLUGIN=false
MULTI_STEP=false
MERGE=false
DEBUG=false
NO_SLACK=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --plugin)     PLUGIN=true;     shift ;;
    --multi-step) MULTI_STEP=true; shift ;;
    --merge)      MERGE=true;      shift ;;
    --debug)      DEBUG=true;      shift ;;
    --no-slack)   NO_SLACK=true;   shift ;;
    --*)
      echo "ERROR=Unknown flag '$1'. Valid flags: --plugin, --multi-step, --merge, --debug, --no-slack."
      exit 1
      ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  echo "ERROR=Missing <skill-name>. Usage: /create-skill [--plugin] [--multi-step] [--merge] [--debug] [--no-slack] <skill-name> <description>"
  exit 1
fi

NAME="$1"
shift

# Strip a single leading '/' if the user passed /foo instead of foo.
NAME="${NAME#/}"

if [[ $# -lt 1 ]]; then
  echo "ERROR=Missing <description>. Usage: /create-skill [--plugin] [--multi-step] [--merge] [--debug] [--no-slack] <skill-name> <description>"
  exit 1
fi

# Description is the verbatim remainder, space-joined.
DESCRIPTION="$*"

echo "NAME=${NAME}"
echo "DESCRIPTION=${DESCRIPTION}"
echo "PLUGIN=${PLUGIN}"
echo "MULTI_STEP=${MULTI_STEP}"
echo "MERGE=${MERGE}"
echo "DEBUG=${DEBUG}"
echo "NO_SLACK=${NO_SLACK}"
