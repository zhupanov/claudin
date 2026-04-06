#!/usr/bin/env bash
# PreToolUse hook: Block edits to files inside any checked-out git submodule
# of the current superproject.
#
# Stdin: JSON with tool_input.file_path (absolute path)
# Exit 0: allow the operation
# Exit 2: block the operation (stdout is the reason shown to Claude)
#
# Behavior:
# - Fails CLOSED on stdin / JSON parse failure
# - Fails OPEN for clearly non-git situations
# - Blocks only true submodules of the current repo, not arbitrary nested repos

set -uo pipefail

block() {
  printf '%s\n' "$1"
  exit 2
}

# --- Read stdin ---
INPUT=$(cat) || block "submodule edit guard: failed to read stdin, blocking as precaution"

# --- Extract file_path from JSON ---
if ! command -v jq >/dev/null 2>&1; then
  block "submodule edit guard: jq is required but not installed; install jq and retry"
fi
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null) \
  || block "submodule edit guard: failed to parse tool input, blocking as precaution"

# No file_path means not a file operation we care about.
if [[ -z "$FILE_PATH" ]]; then
  exit 0
fi

# Require absolute path per contract.
if [[ "$FILE_PATH" != /* ]]; then
  block "submodule edit guard: tool_input.file_path is not absolute, blocking as precaution"
fi

# --- Determine the superproject root ---
# If we're not running inside a git repo, do not interfere.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi
# Canonicalize once to avoid symlink/path ambiguity in later comparisons.
REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || {
  echo "submodule edit guard: warning: could not canonicalize repo root" >&2
  exit 0
}

# --- Find the nearest existing ancestor of the target path ---
# Handles Write to a new file in a new subdirectory inside a submodule.
PROBE_PATH="$FILE_PATH"
while [[ ! -e "$PROBE_PATH" ]] && [[ "$PROBE_PATH" != "/" ]]; do
  PROBE_PATH=$(dirname "$PROBE_PATH")
done

# If we walked all the way to / without finding anything, allow.
if [[ "$PROBE_PATH" == "/" ]]; then
  exit 0
fi

# If we landed on a file, inspect its directory.
if [[ -f "$PROBE_PATH" ]]; then
  PROBE_DIR=$(dirname "$PROBE_PATH")
else
  PROBE_DIR="$PROBE_PATH"
fi

# Canonicalize the probe directory.
PROBE_DIR=$(cd "$PROBE_DIR" 2>/dev/null && pwd -P) || {
  echo "submodule edit guard: warning: could not canonicalize probe dir" >&2
  exit 0
}

# --- Resolve the git repo containing the target path ---
FILE_REPO_ROOT=$(git -C "$PROBE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$FILE_REPO_ROOT" ]]; then
  # Target is not in any git repo, allow.
  exit 0
fi
FILE_REPO_ROOT=$(cd "$FILE_REPO_ROOT" 2>/dev/null && pwd -P) || {
  echo "submodule edit guard: warning: could not canonicalize file repo root" >&2
  exit 0
}

# Same repo root => not in a submodule.
if [[ "$FILE_REPO_ROOT" == "$REPO_ROOT" ]]; then
  exit 0
fi

# --- Verify it's actually a submodule of this repo, not an unrelated nested repo ---
FILE_SUPERPROJECT=$(git -C "$FILE_REPO_ROOT" rev-parse --show-superproject-working-tree 2>/dev/null || true)
if [[ -z "$FILE_SUPERPROJECT" ]]; then
  # No superproject — it's a standalone nested repo, not a submodule. Allow.
  exit 0
fi
FILE_SUPERPROJECT=$(cd "$FILE_SUPERPROJECT" 2>/dev/null && pwd -P) || {
  echo "submodule edit guard: warning: could not canonicalize superproject path" >&2
  exit 0
}

if [[ "$FILE_SUPERPROJECT" != "$REPO_ROOT" ]]; then
  # Superproject is some other repo, not ours. Allow.
  exit 0
fi

# --- Block: file is in a submodule of this repo ---
SUBMODULE_PATH="${FILE_REPO_ROOT#"$REPO_ROOT"/}"
block "This file is inside the '$SUBMODULE_PATH' submodule. Never edit submodules directly here; file PRs in the submodule's own repo instead."
