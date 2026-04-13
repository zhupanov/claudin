#!/usr/bin/env bash
# reviewer-model-args.sh — Output model arguments for an external reviewer tool.
#
# Returns the appropriate --model / -m flag for the given tool based on
# environment variables. Cursor defaults to composer-2-fast when no model is
# configured. Codex outputs nothing when unconfigured (uses its own default).
#
# Environment variables:
#   LARCH_CURSOR_MODEL — Model name for Cursor (e.g., gpt-5.4-medium)
#   LARCH_CODEX_MODEL  — Model name for Codex (e.g., o3)
#
# Plugin userConfig fallbacks (lower priority):
#   CLAUDE_PLUGIN_OPTION_CURSOR_MODEL → LARCH_CURSOR_MODEL
#   CLAUDE_PLUGIN_OPTION_CODEX_MODEL  → LARCH_CODEX_MODEL
#
# Usage:
#   reviewer-model-args.sh --tool cursor|codex
#
# Output (stdout):
#   The model flag(s) to splice into the command, or empty string (Codex only;
#   Cursor always emits a model flag).
#   Examples:
#     --model gpt-5.4-medium    (cursor with LARCH_CURSOR_MODEL=gpt-5.4-medium)
#     --model composer-2-fast   (cursor with no env var — default)
#     -m o3                     (codex with LARCH_CODEX_MODEL=o3)
#     (empty)                   (codex with no env var set)
#
# Exit codes:
#   0 — always

set -euo pipefail

TOOL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool) TOOL="${2:?--tool requires a value}"; shift 2 ;;
        *) echo "reviewer-model-args.sh: unknown argument: $1" >&2; exit 1 ;;
    esac
done

if [[ -z "$TOOL" ]]; then
    echo "reviewer-model-args.sh: --tool is required" >&2
    exit 1
fi

case "$TOOL" in
    cursor)
        MODEL="${LARCH_CURSOR_MODEL:-${CLAUDE_PLUGIN_OPTION_CURSOR_MODEL:-composer-2-fast}}"
        echo "--model $MODEL"
        ;;
    codex)
        MODEL="${LARCH_CODEX_MODEL:-${CLAUDE_PLUGIN_OPTION_CODEX_MODEL:-}}"
        if [[ -n "$MODEL" ]]; then
            echo "-m $MODEL"
        fi
        ;;
    *)
        echo "reviewer-model-args.sh: --tool must be 'cursor' or 'codex' (got: $TOOL)" >&2
        exit 1
        ;;
esac
