#!/usr/bin/env bash
# deny-edit-write.sh — PreToolUse hook that denies Edit/Write/NotebookEdit
# while the /research skill is active. Belt-and-suspenders second mechanical
# layer on top of the `allowed-tools` frontmatter omission.
#
# Output: spec-compliant `hookSpecificOutput` JSON deny envelope on stdout.
# Stdin: ignored (matcher already restricts the trigger surface).
# Exit: 0 on success (jq's exit status). If jq is missing or fails, the
# script exits non-zero so Claude Code surfaces the hook failure rather than
# silently allowing the tool call.
#
# INVARIANT: the permissionDecisionReason string MUST be composed only from
# fixed ASCII literals — no runtime-derived interpolation. This keeps the
# emitted JSON structurally trivial and the regression test deterministic.
#
# Regression harness: ${CLAUDE_PLUGIN_ROOT}/scripts/test-deny-edit-write.sh
# (wired into `make lint` via the `test-deny-edit-write` target).

set -uo pipefail

jq -cn '{
  hookSpecificOutput: {
    hookEventName: "PreToolUse",
    permissionDecision: "deny",
    permissionDecisionReason: "/research is a read-only skill -- file modifications are not permitted."
  }
}'
