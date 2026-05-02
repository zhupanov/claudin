#!/usr/bin/env bash
# launch-codex-review.sh — Launch a Codex agent review with automatic model args.
#
# Absorbs the command-substitution chain (agent-model-args.sh + optionally
# render-specialist-prompt.sh) so SKILL.md Bash blocks are simple script
# invocations that don't trigger Claude Code permission prompts.
#
# Two modes:
#   Generic:    --prompt "review text..."
#   Specialist: --agent-file agents/reviewer-X.md --mode diff|description
#               [--description-text TEXT] [--scope-files PATH] [--competition-notice]
#
# Usage:
#   launch-codex-review.sh --output FILE --timeout SECS --prompt "PROMPT"
#   launch-codex-review.sh --output FILE --timeout SECS \
#       --agent-file FILE --mode diff|description [--description-text T] [--scope-files F] [--competition-notice]
#
# Output: same stdout as run-external-agent.sh (no additional output).
#
# Exit codes: passed through from run-external-agent.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUT=""
TIMEOUT=""
PROMPT=""
AGENT_FILE=""
MODE=""
DESCRIPTION_TEXT=""
SCOPE_FILES=""
COMPETITION_NOTICE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="${2:?--output requires a value}"; shift 2 ;;
        --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --prompt) PROMPT="${2:?--prompt requires a value}"; shift 2 ;;
        --agent-file) AGENT_FILE="${2:?--agent-file requires a value}"; shift 2 ;;
        --mode) MODE="${2:?--mode requires a value}"; shift 2 ;;
        --description-text) DESCRIPTION_TEXT="${2:?--description-text requires a value}"; shift 2 ;;
        --scope-files) SCOPE_FILES="${2:?--scope-files requires a value}"; shift 2 ;;
        --competition-notice) COMPETITION_NOTICE=true; shift ;;
        *) echo "launch-codex-review.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$OUTPUT" ]]; then
    echo "launch-codex-review.sh: --output is required" >&2; exit 2
fi
if [[ -z "$TIMEOUT" ]]; then
    echo "launch-codex-review.sh: --timeout is required" >&2; exit 2
fi

if [[ -n "$AGENT_FILE" ]]; then
    RENDER_ARGS=(--agent-file "$AGENT_FILE" --mode "$MODE")
    [[ -n "$DESCRIPTION_TEXT" ]] && RENDER_ARGS+=(--description-text "$DESCRIPTION_TEXT")
    [[ -n "$SCOPE_FILES" ]] && RENDER_ARGS+=(--scope-files "$SCOPE_FILES")
    [[ "$COMPETITION_NOTICE" == "true" ]] && RENDER_ARGS+=(--competition-notice)
    PROMPT=$("$SCRIPT_DIR/render-specialist-prompt.sh" "${RENDER_ARGS[@]}")
elif [[ -z "$PROMPT" ]]; then
    echo "launch-codex-review.sh: either --prompt or --agent-file is required" >&2; exit 2
fi

MODEL_ARGS=$("$SCRIPT_DIR/agent-model-args.sh" --tool codex --with-effort)

# shellcheck disable=SC2086
exec "$SCRIPT_DIR/run-external-agent.sh" \
    --tool codex \
    --output "$OUTPUT" \
    --timeout "$TIMEOUT" \
    -- \
    codex exec --full-auto -C "$PWD" \
    $MODEL_ARGS \
    --output-last-message "$OUTPUT" \
    "$PROMPT"
