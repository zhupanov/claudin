#!/usr/bin/env bash
# PostToolUse hook: Auto-run goimports on .go files after Edit/Write tool calls.
# Note: Bash-driven writes (make format, shell scripts) are not intercepted by this hook.
#
# Stdin: JSON with tool_input.file_path (absolute path)
# Always exits 0 (non-blocking). Failures are silently ignored.

set -uo pipefail

INPUT=$(cat)

# Extract file_path. If parsing fails, silently exit.
FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) || exit 0

# No path or not a .go file → nothing to do.
[ -z "$FILE_PATH" ] && exit 0
[[ "$FILE_PATH" != *.go ]] && exit 0

# Run goimports if available. Silently ignore errors.
if command -v goimports >/dev/null 2>&1; then
  goimports -w "$FILE_PATH" 2>/dev/null || true
fi

exit 0
