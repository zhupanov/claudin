#!/usr/bin/env bash
# prepare-description.sh — Validate and classify a /create-skill description for
# the Step 1.5 / Step 1.6 synthesis flow in skills/create-skill/SKILL.md.
#
# Required flags (exactly one of --description-file or --description):
#   --description-file <path>   Path to a tmpfile holding the candidate description.
#                               Used by Step 1.5's initial probe so multi-line raw
#                               input survives the shell-argument boundary intact.
#   --description <text>        Single-line shell-arg form. Used by Step 1.6 for the
#                               re-validate call against an LLM-synthesized one-liner.
#   --name <name>               Required — forwarded to validate-args.sh.
#   --plugin                    Optional flag — forwarded to validate-args.sh.
#
# Output (stdout, exits 0 on classified results):
#   MODE=verbatim                 Description passed validation as-is.
#   MODE=needs-synthesis          Description failed on the synthesis-eligible
#                                 trigger class (newlines/control characters OR
#                                 length>1024 with no other anti-patterns).
#     REASON=newlines-or-control-chars | length-exceeds-cap
#   MODE=abort                    Description failed for any other reason, OR the
#                                 pre-synthesis security scan caught a banned token
#                                 alongside the synthesis-trigger class.
#     ERROR=<original validator ERROR text, or synthetic mixed-input error>
#
# Stdout NEVER carries the description text — only short fields. The orchestrator
# already holds the raw description (in --description-file or --description) and
# the synthesized line (LLM-side memory). This is required because KEY=VALUE stdout
# cannot carry multi-line content safely.
#
# Internal-error path (missing required flags, ambiguous flags, missing/non-
# executable validator): exit 1 with ERROR=<diagnostic>.
#
# F9 pre-synthesis security scan: BEFORE classifying as MODE=needs-synthesis, scan
# the raw description for banned-token classes (XML tag pattern, backtick, $(,
# standalone EOF/HEREDOC/--- token). If any present alongside the synthesis trigger
# class, emit MODE=abort regardless of which validate-args.sh check fires first.
# This closes the FEATURE_SPEC forward-leak that motivated the narrow-gating
# dialectic outcome (DECISION_1).

set -euo pipefail

NAME=""
DESCRIPTION_FILE=""
DESCRIPTION=""
PLUGIN_FLAG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)              NAME="$2";              shift 2 ;;
    --description-file)  DESCRIPTION_FILE="$2";  shift 2 ;;
    --description)       DESCRIPTION="$2";       shift 2 ;;
    --plugin)            PLUGIN_FLAG="--plugin"; shift ;;
    *)
      echo "ERROR=Unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "ERROR=Missing required --name argument."
  exit 1
fi

if [[ -n "$DESCRIPTION_FILE" && -n "$DESCRIPTION" ]]; then
  echo "ERROR=--description-file and --description are mutually exclusive; pass exactly one."
  exit 1
fi

if [[ -z "$DESCRIPTION_FILE" && -z "$DESCRIPTION" ]]; then
  echo "ERROR=Missing description input; pass either --description-file <path> or --description <text>."
  exit 1
fi

if [[ -n "$DESCRIPTION_FILE" ]]; then
  if [[ ! -f "$DESCRIPTION_FILE" ]]; then
    echo "ERROR=--description-file '$DESCRIPTION_FILE' does not exist."
    exit 1
  fi
  # Read the file's content into DESC_VAR, preserving trailing content. Use
  # printf-then-cat round-trip to preserve embedded newlines verbatim.
  DESC_VAR="$(cat "$DESCRIPTION_FILE")"
else
  DESC_VAR="$DESCRIPTION"
fi

# Locate validate-args.sh next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_ARGS="$SCRIPT_DIR/validate-args.sh"

if [[ ! -x "$VALIDATE_ARGS" ]]; then
  echo "ERROR=validate-args.sh not found or not executable at $VALIDATE_ARGS."
  exit 1
fi

# F9 pre-synthesis security scan.
# Returns 0 if any banned-token class is present, 1 otherwise.
# Banned classes: XML tag pattern, backtick, $(, standalone EOF/HEREDOC/--- tokens.
# Newlines are NOT in this list — they are the synthesis trigger themselves.
contains_banned_token() {
  local s="$1"
  # XML tag pattern <...> with at least one char between brackets.
  if [[ "$s" =~ \<[^\>]+\> ]]; then
    echo "XML tag pattern <...>"
    return 0
  fi
  if [[ "$s" == *'`'* ]]; then
    echo "backtick"
    return 0
  fi
  # shellcheck disable=SC2016  # literal two-char sequence
  if [[ "$s" == *'$('* ]]; then
    echo "command substitution \$("
    return 0
  fi
  for bad in 'EOF' 'HEREDOC' '---'; do
    if [[ "$s" == "$bad" ]] || [[ "$s" == *" $bad "* ]] || [[ "$s" == "$bad "* ]] || [[ "$s" == *" $bad" ]]; then
      echo "heredoc/frontmatter token '$bad'"
      return 0
    fi
  done
  return 1
}

# Invoke validate-args.sh with set -e suppressed (it exits 1 on VALID=false).
# We deliberately ignore the exit code — VALID= and ERROR= lines on stdout are
# the structured signal we parse below.
set +e
VOUT="$("$VALIDATE_ARGS" --name "$NAME" --description "$DESC_VAR" $PLUGIN_FLAG 2>&1)"
set -e

# Extract VALID and ERROR lines from the validator output.
VALID_LINE="$(echo "$VOUT" | grep -E '^VALID=' || true)"
ERROR_LINE="$(echo "$VOUT" | grep -E '^ERROR=' || true)"
ERROR_TEXT="${ERROR_LINE#ERROR=}"

if [[ "$VALID_LINE" == "VALID=true" ]]; then
  echo "MODE=verbatim"
  exit 0
fi

# VALID=false (or VRC != 0). Classify.
# Synthesis-eligible classes (DECISION_1 narrow gating + Round 2 length extension):
#   - "Description contains newlines or control characters"
#   - "Description length ("  — validate-args.sh emits "Description length (N) exceeds 1024 characters."
#
# F9 pre-synthesis security scan: if the raw description contains any banned-token
# class, MODE=abort regardless of which validator class fired first.
if [[ "$ERROR_TEXT" == *"Description contains newlines or control characters"* ]] \
   || [[ "$ERROR_TEXT" == "Description length ("* ]]; then
  if banned_class="$(contains_banned_token "$DESC_VAR")"; then
    echo "MODE=abort"
    echo "ERROR=Description contains synthesis-trigger class plus additional anti-patterns ($banned_class). Synthesis disabled for mixed-input cases. Original validator error: $ERROR_TEXT"
    exit 0
  fi
  echo "MODE=needs-synthesis"
  if [[ "$ERROR_TEXT" == "Description length ("* ]]; then
    echo "REASON=length-exceeds-cap"
  else
    echo "REASON=newlines-or-control-chars"
  fi
  exit 0
fi

# Any other validator failure: abort with the original ERROR text.
echo "MODE=abort"
echo "ERROR=$ERROR_TEXT"
exit 0
