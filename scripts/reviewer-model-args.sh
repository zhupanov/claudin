#!/usr/bin/env bash
# reviewer-model-args.sh — Output model (and optionally effort) arguments for an
# external reviewer tool.
#
# Returns the appropriate --model / -m flag for the given tool based on
# environment variables. Cursor defaults to composer-2-fast when no model is
# configured. Codex outputs nothing when unconfigured (uses its own default).
#
# When --with-effort is passed, also emits tool-specific reasoning-effort flags.
# The --with-effort flag is an opt-in gate: real reviewer launch call sites
# pass it; lightweight probe callers (e.g., check-reviewers.sh health probes,
# run-negotiation-round.sh) do NOT pass it, preserving the original probe
# semantics regardless of env var settings.
#
# Environment variables:
#   LARCH_CURSOR_MODEL  — Model name for Cursor (e.g., gpt-5.4-medium)
#   LARCH_CODEX_MODEL   — Model name for Codex (e.g., o3)
#   LARCH_CODEX_EFFORT  — Codex reasoning effort: minimal|low|medium|high
#                         (only consulted when --with-effort is passed)
#
# Plugin userConfig fallbacks (lower priority):
#   CLAUDE_PLUGIN_OPTION_CURSOR_MODEL  → LARCH_CURSOR_MODEL
#   CLAUDE_PLUGIN_OPTION_CODEX_MODEL   → LARCH_CODEX_MODEL
#   CLAUDE_PLUGIN_OPTION_CODEX_EFFORT  → LARCH_CODEX_EFFORT  (default "high")
#
# Cursor effort: Cursor CLI has no dedicated reasoning-effort flag. No effort
# tokens are emitted for Cursor; the "Work at maximum reasoning effort"
# instruction is appended to Cursor prompts at the call site instead.
#
# Usage:
#   reviewer-model-args.sh --tool cursor|codex [--with-effort]
#
# Output (stdout):
#   Model flag tokens, optionally followed by effort flag tokens when
#   --with-effort is passed (Codex only).
#   Examples:
#     --model gpt-5.4-medium
#         (cursor with LARCH_CURSOR_MODEL=gpt-5.4-medium)
#     --model composer-2-fast
#         (cursor default, --with-effort is a no-op for Cursor)
#     -m o3 -c model_reasoning_effort="high"
#         (codex with LARCH_CODEX_MODEL=o3 and --with-effort and default effort)
#     -c model_reasoning_effort="high"
#         (codex without a model pin but --with-effort)
#     (empty)
#         (codex with no model and no --with-effort)
#
# Exit codes:
#   0 — success
#   1 — invalid arguments or invalid effort value

set -euo pipefail

TOOL=""
WITH_EFFORT="false"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tool) TOOL="${2:?--tool requires a value}"; shift 2 ;;
        --with-effort) WITH_EFFORT="true"; shift ;;
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
        # Cursor has no effort flag; --with-effort is intentionally a no-op here.
        ;;
    codex)
        MODEL="${LARCH_CODEX_MODEL:-${CLAUDE_PLUGIN_OPTION_CODEX_MODEL:-}}"
        OUT=""
        if [[ -n "$MODEL" ]]; then
            OUT="-m $MODEL"
        fi
        if [[ "$WITH_EFFORT" == "true" ]]; then
            EFFORT="${LARCH_CODEX_EFFORT:-${CLAUDE_PLUGIN_OPTION_CODEX_EFFORT:-high}}"
            case "$EFFORT" in
                minimal|low|medium|high) ;;
                *)
                    echo "reviewer-model-args.sh: WARN invalid codex effort '$EFFORT' (must be minimal|low|medium|high); falling back to 'high'" >&2
                    EFFORT="high"
                    ;;
            esac
            if [[ -n "$OUT" ]]; then
                OUT="$OUT -c model_reasoning_effort=\"$EFFORT\""
            else
                OUT="-c model_reasoning_effort=\"$EFFORT\""
            fi
        fi
        if [[ -n "$OUT" ]]; then
            echo "$OUT"
        fi
        ;;
    *)
        echo "reviewer-model-args.sh: --tool must be 'cursor' or 'codex' (got: $TOOL)" >&2
        exit 1
        ;;
esac
