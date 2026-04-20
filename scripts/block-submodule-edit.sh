#!/usr/bin/env bash
# PreToolUse hook: Block edits to files inside any checked-out git submodule
# of the current superproject.
#
# Stdin: JSON with tool_input.file_path (absolute path)
# Always exits 0. To block, emits Anthropic's documented PreToolUse deny shape
# on stdout: {"hookSpecificOutput":{"hookEventName":"PreToolUse",
# "permissionDecision":"deny","permissionDecisionReason":"<why>"}}.
# To allow, emits no output. See Anthropic's Hooks reference for the spec.
#
# Behavior:
# - Fails CLOSED on stdin / JSON parse failure
# - Fails OPEN for clearly non-git situations
# - Blocks only true submodules of the current repo, not arbitrary nested repos
#
# Regression harness: ${CLAUDE_PLUGIN_ROOT}/scripts/test-block-submodule-edit.sh
# (wired into `make lint` via the `test-block-submodule` target).

set -uo pipefail

# See: https://docs.anthropic.com/en/docs/claude-code/hooks
# If jq fails at runtime (broken install, I/O error, etc.), emit a static deny
# JSON fallback so a failed jq never degrades to exit 0 + empty stdout, which
# the runtime would interpret as allow — weakening the submodule-edit policy.
block() {
  jq -cn --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }' || printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"submodule edit guard: deny (jq runtime failure)"}}'
  exit 0
}

# jq is required to produce the deny JSON via block(). Check it first so every
# block() call below can assume jq is available. For the missing-jq case, emit
# a static JSON literal directly (no jq needed for a fixed string).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"submodule edit guard: jq is required but not installed; install jq and retry"}}'
  exit 0
fi

# --- Read stdin ---
INPUT=$(cat) || block "submodule edit guard: failed to read stdin, blocking as precaution"

# --- Extract file_path from JSON ---
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
# Anchor to CLAUDE_PROJECT_DIR so that a session `cd`'d into a submodule still
# resolves REPO_ROOT to the superproject; $PWD fallback preserves behavior for
# non-Claude-Code callers (manual testing). Closes the cd-into-submodule bypass
# tracked as issue #150.
ANCHOR_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
REPO_ROOT=$(git -C "$ANCHOR_DIR" rev-parse --show-toplevel 2>/dev/null || true)
if [[ -z "$REPO_ROOT" ]]; then
  exit 0
fi
# Canonicalize once to avoid symlink/path ambiguity in later comparisons.
REPO_ROOT=$(cd "$REPO_ROOT" 2>/dev/null && pwd -P) || {
  echo "submodule edit guard: warning: could not canonicalize repo root" >&2
  exit 0
}

# --- Resolve file_path through any symlink chain ---
# macOS has no readlink -f / realpath by default; use a pure-bash loop.
# Bounded depth (40) doubles as a cycle detector (fail-closed on exhaustion).
# Relative readlink targets are rebased against the link's own directory
# (follows each hop; does not perform full lexical `..` normalization — the
# kernel resolves `..` at lstat time, and PROBE_DIR is canonicalized below).
# Placed after REPO_ROOT so non-git callers still fail-open (issue #166).
# Only activates when the path is itself a symlink; non-symlink inputs pass
# through unchanged.
resolved="$FILE_PATH"
max_depth=40
depth=0
while [[ -L "$resolved" ]]; do
  if (( depth >= max_depth )); then
    block "submodule edit guard: symlink resolution exceeded $max_depth hops (possible cycle), blocking as precaution"
  fi
  target=$(readlink "$resolved" 2>/dev/null) \
    || block "submodule edit guard: readlink failed on '$resolved', blocking as precaution"
  [[ -n "$target" ]] \
    || block "submodule edit guard: readlink returned empty target for '$resolved', blocking as precaution"
  if [[ "$target" == /* ]]; then
    resolved="$target"
  else
    resolved="$(dirname "$resolved")/$target"
  fi
  depth=$((depth + 1))
done
FILE_PATH="$resolved"

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
