#!/usr/bin/env bash
# deny-edit-write.sh — skill-scoped PreToolUse hook that permits
# Edit/Write/NotebookEdit only when the tool's target path resolves to
# an absolute path under canonical /tmp. Every other outcome — missing
# path, relative path, traversal, symlink cycle, resolution failure,
# jq runtime failure — denies, so the repo working tree is never
# written to while /research is active. Belt-and-suspenders second
# mechanical layer on top of the `allowed-tools` frontmatter.
#
# Stdin: JSON with .tool_input.file_path or .tool_input.notebook_path
#        (absolute path). NotebookEdit uses notebook_path; fall back
#        to it so an empty file_path does not fail-open.
# Stdout: on deny, spec-compliant `hookSpecificOutput` deny envelope
#         (single fixed-reason ASCII literal, byte-identical across
#         the jq -cn and printf fallback paths). On allow, empty.
# Exit: always 0. Deny semantics never depend on runtime tooling
#       availability or version-specific hook-failure handling.
#
# INVARIANTS:
#   1. deny JSON is composed only from fixed ASCII literals — no
#      runtime-derived interpolation. The `jq -cn` and `printf` paths
#      emit byte-identical output.
#   2. every error branch routes through block() which emits the deny
#      envelope then exits 0 — no silent fall-through to empty stdout.
#   3. allow requires a positively proven canonical path under /tmp;
#      any ambiguity denies.
#
# Style mirrors scripts/block-submodule-edit.sh (stdin-JSON contract,
# bounded symlink walk, nearest-existing-ancestor probe, `pwd -P`
# canonicalization) with a different predicate (/tmp-allow instead of
# submodule-deny).
#
# Regression harness: ${CLAUDE_PLUGIN_ROOT}/scripts/test-deny-edit-write.sh
# (wired into `make lint` via the `test-deny-edit-write` target).

set -uo pipefail

# Fixed deny JSON — single reason string, no runtime interpolation.
# The jq -cn expression below and the static printf fallback must emit
# byte-identical output for this literal. When editing the reason,
# keep both branches in sync.
block() {
  jq -cn '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "/research is a read-only skill -- Edit/Write/NotebookEdit outside /tmp is not permitted."
    }
  }' || printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"/research is a read-only skill -- Edit/Write/NotebookEdit outside /tmp is not permitted."}}'
  exit 0
}

# jq-absent static fallback. Byte-identical to the `jq -cn` output
# above (same single reason literal).
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"/research is a read-only skill -- Edit/Write/NotebookEdit outside /tmp is not permitted."}}'
  exit 0
fi

# --- Read stdin ---
INPUT=$(cat) || block

# --- Extract path ---
# NotebookEdit's JSON uses `notebook_path`; fall back to it so that
# shape does not fail-open. Empty result when neither field is set.
FILE_PATH=$(printf '%s' "$INPUT" | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' 2>/dev/null) \
  || block

# Fail-closed when matcher triggered but no path is present.
# The hooks.json matcher restricts invocation to Edit|Write|NotebookEdit,
# all of which are file operations — a missing path is ambiguous.
if [[ -z "$FILE_PATH" ]]; then
  block
fi

# Require absolute path.
if [[ "$FILE_PATH" != /* ]]; then
  block
fi

# --- Canonicalize the allowed root once ---
# /tmp is a symlink to /private/tmp on macOS; canonicalize so the
# comparison below handles both layouts uniformly.
ALLOWED_ROOT=$(cd /tmp 2>/dev/null && pwd -P) || block
if [[ -z "$ALLOWED_ROOT" ]]; then
  block
fi

# --- Resolve file_path through any symlink chain ---
# Bounded depth (40) doubles as a cycle detector. Relative readlink
# targets rebased against the link's own directory.
resolved="$FILE_PATH"
max_depth=40
depth=0
while [[ -L "$resolved" ]]; do
  if (( depth >= max_depth )); then
    block
  fi
  target=$(readlink "$resolved" 2>/dev/null) || block
  [[ -n "$target" ]] || block
  if [[ "$target" == /* ]]; then
    resolved="$target"
  else
    resolved="$(dirname "$resolved")/$target"
  fi
  depth=$((depth + 1))
done
FILE_PATH="$resolved"

# --- Find the nearest existing ancestor ---
# Handles Write to a not-yet-existing file inside an existing directory.
PROBE_PATH="$FILE_PATH"
while [[ ! -e "$PROBE_PATH" ]] && [[ "$PROBE_PATH" != "/" ]]; do
  PROBE_PATH=$(dirname "$PROBE_PATH")
done

# Walked to / without finding anything — ambiguous.
if [[ "$PROBE_PATH" == "/" ]]; then
  block
fi

# Resolve to the probe directory.
if [[ -f "$PROBE_PATH" ]]; then
  PROBE_DIR=$(dirname "$PROBE_PATH")
else
  PROBE_DIR="$PROBE_PATH"
fi

# Canonicalize the probe directory.
PROBE_DIR=$(cd "$PROBE_DIR" 2>/dev/null && pwd -P) || block

# --- Policy: allow only when the canonical probe dir is under the
# canonical /tmp root. Exact equality OR $ALLOWED_ROOT/ prefix.
if [[ "$PROBE_DIR" == "$ALLOWED_ROOT" ]] || [[ "$PROBE_DIR" == "$ALLOWED_ROOT"/* ]]; then
  exit 0
fi

block
