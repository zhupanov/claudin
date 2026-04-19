#!/usr/bin/env bash
# deny-edit-write.sh — PreToolUse hook that denies Edit/Write/NotebookEdit
# while the /research skill is active. Belt-and-suspenders second mechanical
# layer on top of the `allowed-tools` frontmatter omission.
#
# Output: spec-compliant `hookSpecificOutput` JSON deny envelope on stdout.
# Stdin: ignored (matcher already restricts the trigger surface).
# Exit: always 0. The script emits a well-formed deny envelope on every
# invocation — when `jq` is on PATH it composes the JSON via `jq -cn`; when
# `jq` is absent it falls back to a byte-identical static `printf`. This
# mirrors the precedent in `scripts/block-submodule-edit.sh` (the only other
# PreToolUse deny hook in this plugin) so the deny semantics never depend on
# runtime tooling availability or version-specific hook-failure handling.
#
# INVARIANT: the deny JSON MUST be composed only from fixed ASCII literals —
# no runtime-derived interpolation. The `jq -cn` and `printf` paths MUST
# emit byte-identical output (the regression harness exercises both branches
# only when `jq` is present, but checks idempotency on each invocation).
#
# Regression harness: ${CLAUDE_PLUGIN_ROOT}/scripts/test-deny-edit-write.sh
# (wired into `make lint` via the `test-deny-edit-write` target).

set -uo pipefail

# `jq`-absent static fallback. Matches `block-submodule-edit.sh:39-42` pattern.
# The static literal is byte-identical to the `jq -cn` output below.
if ! command -v jq >/dev/null 2>&1; then
    printf '%s\n' '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"/research is a read-only skill -- file modifications are not permitted."}}'
    exit 0
fi

jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "/research is a read-only skill -- file modifications are not permitted."
  }
}'
