#!/usr/bin/env bash
# launch-codex-implement.sh — Launch a Codex agent for implementation with
# automatic model args and full-auto approval mode.
#
# Parallel to launch-codex-review.sh but for write-capable implementation,
# not read-only review. No specialist prompt rendering, no competition notice.
#
# Usage:
#   launch-codex-implement.sh --output FILE --timeout SECS --prompt "PROMPT"
#
# Output: same stdout as run-external-agent.sh (no additional output).
#
# Exit codes: passed through from run-external-agent.sh.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

OUTPUT=""
TIMEOUT=""
PROMPT=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --output) OUTPUT="${2:?--output requires a value}"; shift 2 ;;
        --timeout) TIMEOUT="${2:?--timeout requires a value}"; shift 2 ;;
        --prompt) PROMPT="${2:?--prompt requires a value}"; shift 2 ;;
        *) echo "launch-codex-implement.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

if [[ -z "$OUTPUT" ]]; then
    echo "launch-codex-implement.sh: --output is required" >&2; exit 2
fi
if [[ -z "$TIMEOUT" ]]; then
    echo "launch-codex-implement.sh: --timeout is required" >&2; exit 2
fi
if [[ -z "$PROMPT" ]]; then
    echo "launch-codex-implement.sh: --prompt is required" >&2; exit 2
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
