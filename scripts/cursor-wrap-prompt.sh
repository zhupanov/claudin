#!/usr/bin/env bash
# cursor-wrap-prompt.sh — Wrap a Cursor prompt with the max-mode slash-command prefix.
#
# Emits " /max-mode on. Prompt: <prompt>" (leading space intentional, no trailing
# newline) on stdout. Single source of truth for the max-mode prefix literal.
#
# Cursor supports ~/.cursor/cli-config.json for max-mode and model pinning, but
# that path is user-managed and cannot be enforced programmatically across
# environments. Prepending the /max-mode slash command to the prompt is the
# mechanism larch controls from its own invocations.
#
# Usage:
#   cursor-wrap-prompt.sh "<prompt>"
#
# Output (stdout):
#   " /max-mode on. Prompt: <prompt>"   (no trailing newline)
#
# Exit codes:
#   0 — success
#   1 — no prompt argument provided

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "cursor-wrap-prompt.sh: a single prompt argument is required" >&2
    exit 1
fi

printf ' /max-mode on. Prompt: %s' "$1"
