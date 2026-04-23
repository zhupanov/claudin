#!/usr/bin/env bash
# check-reviewers.sh — Check external reviewer binary availability and optional health probe.
#
# Checks if codex and cursor binaries are installed. With --probe, also sends a
# trivial prompt to each available tool with a 60-second timeout to verify it is
# actually responding (catches auth failures, network issues, outages).
# Failed probes are retried once to tolerate transient timeouts.
#
# Usage:
#   check-reviewers.sh [--probe] [--skip-codex-probe] [--skip-cursor-probe]
#
# Outputs (key=value to stdout):
#   CODEX_AVAILABLE=true|false    — binary exists on PATH
#   CURSOR_AVAILABLE=true|false   — binary exists on PATH
#   CODEX_HEALTHY=true|false      — (only with --probe) responded to trivial prompt within timeout
#   CURSOR_HEALTHY=true|false     — (only with --probe) responded to trivial prompt within timeout
#
# Exit codes:
#   0 — always (availability/health are informational, not errors)

# No -e: exit codes from probe subprocesses are informational, not errors.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

PROBE=false
SKIP_CODEX_PROBE=false
SKIP_CURSOR_PROBE=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        --probe)              PROBE=true; shift ;;
        --skip-codex-probe)   SKIP_CODEX_PROBE=true; shift ;;
        --skip-cursor-probe)  SKIP_CURSOR_PROBE=true; shift ;;
        *) echo "check-reviewers.sh: unknown argument: $1" >&2; exit 1 ;;
    esac
done

CODEX_AVAILABLE="false"
CURSOR_AVAILABLE="false"

if command -v codex >/dev/null 2>&1; then
    CODEX_AVAILABLE="true"
fi

if command -v cursor >/dev/null 2>&1; then
    CURSOR_AVAILABLE="true"
fi

echo "CODEX_AVAILABLE=$CODEX_AVAILABLE"
echo "CURSOR_AVAILABLE=$CURSOR_AVAILABLE"

if [[ "$PROBE" == "true" ]]; then
    CODEX_HEALTHY="false"
    CURSOR_HEALTHY="false"

    PROBE_DIR=$(mktemp -d /tmp/larch-probe-XXXXXX)
    # Clean up probe tmpdir on exit
    trap 'rm -rf "$PROBE_DIR"' EXIT

    # Launch probes in parallel for available tools (skip already-known-unhealthy)
    if [[ "$CODEX_AVAILABLE" == "true" && "$SKIP_CODEX_PROBE" == "true" ]]; then
        CODEX_HEALTHY="false"
    elif [[ "$CODEX_AVAILABLE" == "true" ]]; then
        # Build codex command with optional model from LARCH_CODEX_MODEL
        CODEX_MODEL_ARGS=$("$SCRIPT_DIR/reviewer-model-args.sh" --tool codex)
        # shellcheck disable=SC2086
        "$SCRIPT_DIR/run-external-reviewer.sh" \
            --tool codex \
            --output "$PROBE_DIR/codex-probe.txt" \
            --timeout 60 \
            -- codex exec --full-auto -C "$PWD" $CODEX_MODEL_ARGS \
            --output-last-message "$PROBE_DIR/codex-probe.txt" \
            "Respond with OK" \
            >"$PROBE_DIR/codex-wrapper.log" 2>&1 &
    fi

    if [[ "$CURSOR_AVAILABLE" == "true" && "$SKIP_CURSOR_PROBE" == "true" ]]; then
        CURSOR_HEALTHY="false"
    elif [[ "$CURSOR_AVAILABLE" == "true" ]]; then
        # Build cursor command with optional model from LARCH_CURSOR_MODEL
        CURSOR_MODEL_ARGS=$("$SCRIPT_DIR/reviewer-model-args.sh" --tool cursor)
        # Health probe: "Respond with OK" is passed verbatim — NOT wrapped via
        # scripts/cursor-wrap-prompt.sh. Probes exist to verify reachability and
        # auth within a 60s budget; engaging max-mode here would add latency and
        # cost without diagnostic value.
        # shellcheck disable=SC2086
        "$SCRIPT_DIR/run-external-reviewer.sh" \
            --tool cursor \
            --output "$PROBE_DIR/cursor-probe.txt" \
            --timeout 60 \
            --capture-stdout \
            -- cursor agent -p --force --trust $CURSOR_MODEL_ARGS --workspace "$PWD" \
            "Respond with OK" \
            >"$PROBE_DIR/cursor-wrapper.log" 2>&1 &
    fi

    # Build sentinel list for wait-for-reviewers.sh (only for probes actually launched)
    SENTINELS=()
    if [[ "$CODEX_AVAILABLE" == "true" && "$SKIP_CODEX_PROBE" == "false" ]]; then
        SENTINELS+=("$PROBE_DIR/codex-probe.txt.done")
    fi
    if [[ "$CURSOR_AVAILABLE" == "true" && "$SKIP_CURSOR_PROBE" == "false" ]]; then
        SENTINELS+=("$PROBE_DIR/cursor-probe.txt.done")
    fi

    if [[ ${#SENTINELS[@]} -gt 0 ]]; then
        # Wait for probes (120s = 60s timeout + 60s grace)
        "$SCRIPT_DIR/wait-for-reviewers.sh" --timeout 120 "${SENTINELS[@]}" \
            >"$PROBE_DIR/wait.log" 2>&1 || true
    fi

    CODEX_PROBE_ERROR=""
    CURSOR_PROBE_ERROR=""

    # Check codex probe result (skip if probe was not launched)
    if [[ "$CODEX_AVAILABLE" == "true" && "$SKIP_CODEX_PROBE" == "false" ]]; then
        if [[ -f "$PROBE_DIR/codex-probe.txt.done" ]]; then
            CODEX_EXIT=$(cat "$PROBE_DIR/codex-probe.txt.done")
            if [[ "$CODEX_EXIT" == "0" ]]; then
                # Verify output is non-empty
                if [[ -s "$PROBE_DIR/codex-probe.txt" ]]; then
                    CODEX_HEALTHY="true"
                elif [[ -f "$PROBE_DIR/codex-probe.txt.diag" ]]; then
                    CODEX_PROBE_ERROR=$(cat "$PROBE_DIR/codex-probe.txt.diag")
                else
                    CODEX_PROBE_ERROR="Probe exited successfully but produced no output"
                fi
            else
                # Read .diag file if available, fall back to exit code
                if [[ -f "$PROBE_DIR/codex-probe.txt.diag" ]]; then
                    CODEX_PROBE_ERROR=$(cat "$PROBE_DIR/codex-probe.txt.diag")
                else
                    CODEX_PROBE_ERROR="Probe failed with exit code $CODEX_EXIT"
                fi
            fi
        else
            CODEX_PROBE_ERROR="Probe process did not complete (sentinel file missing — possible crash or system kill)"
        fi
    fi

    # Check cursor probe result (skip if probe was not launched)
    if [[ "$CURSOR_AVAILABLE" == "true" && "$SKIP_CURSOR_PROBE" == "false" ]]; then
        if [[ -f "$PROBE_DIR/cursor-probe.txt.done" ]]; then
            CURSOR_EXIT=$(cat "$PROBE_DIR/cursor-probe.txt.done")
            if [[ "$CURSOR_EXIT" == "0" ]]; then
                if [[ -s "$PROBE_DIR/cursor-probe.txt" ]]; then
                    CURSOR_HEALTHY="true"
                elif [[ -f "$PROBE_DIR/cursor-probe.txt.diag" ]]; then
                    CURSOR_PROBE_ERROR=$(cat "$PROBE_DIR/cursor-probe.txt.diag")
                else
                    CURSOR_PROBE_ERROR="Probe exited successfully but produced no output"
                fi
            else
                if [[ -f "$PROBE_DIR/cursor-probe.txt.diag" ]]; then
                    CURSOR_PROBE_ERROR=$(cat "$PROBE_DIR/cursor-probe.txt.diag")
                else
                    CURSOR_PROBE_ERROR="Probe failed with exit code $CURSOR_EXIT"
                fi
            fi
        else
            CURSOR_PROBE_ERROR="Probe process did not complete (sentinel file missing — possible crash or system kill)"
        fi
    fi

    # --- Retry once for failed probes (transient timeout recovery) ---
    RETRY_CODEX=false
    RETRY_CURSOR=false

    if [[ "$CODEX_AVAILABLE" == "true" && "$SKIP_CODEX_PROBE" == "false" && "$CODEX_HEALTHY" == "false" ]]; then
        RETRY_CODEX=true
    fi
    if [[ "$CURSOR_AVAILABLE" == "true" && "$SKIP_CURSOR_PROBE" == "false" && "$CURSOR_HEALTHY" == "false" ]]; then
        RETRY_CURSOR=true
    fi

    if [[ "$RETRY_CODEX" == "true" || "$RETRY_CURSOR" == "true" ]]; then
        echo "Retrying failed health probes..." >&2

        RETRY_SENTINELS=()

        if [[ "$RETRY_CODEX" == "true" ]]; then
            rm -f "$PROBE_DIR/codex-probe.txt" "$PROBE_DIR/codex-probe.txt.done" "$PROBE_DIR/codex-probe.txt.meta" "$PROBE_DIR/codex-probe.txt.diag"
            CODEX_MODEL_ARGS=$("$SCRIPT_DIR/reviewer-model-args.sh" --tool codex)
            # shellcheck disable=SC2086
            "$SCRIPT_DIR/run-external-reviewer.sh" \
                --tool codex \
                --output "$PROBE_DIR/codex-probe.txt" \
                --timeout 60 \
                -- codex exec --full-auto -C "$PWD" $CODEX_MODEL_ARGS \
                --output-last-message "$PROBE_DIR/codex-probe.txt" \
                "Respond with OK" \
                >"$PROBE_DIR/codex-wrapper-retry.log" 2>&1 &
            RETRY_SENTINELS+=("$PROBE_DIR/codex-probe.txt.done")
        fi

        if [[ "$RETRY_CURSOR" == "true" ]]; then
            rm -f "$PROBE_DIR/cursor-probe.txt" "$PROBE_DIR/cursor-probe.txt.done" "$PROBE_DIR/cursor-probe.txt.meta" "$PROBE_DIR/cursor-probe.txt.diag"
            CURSOR_MODEL_ARGS=$("$SCRIPT_DIR/reviewer-model-args.sh" --tool cursor)
            # Retry probe: same rationale as the initial probe above — no max-mode wrap.
            # shellcheck disable=SC2086
            "$SCRIPT_DIR/run-external-reviewer.sh" \
                --tool cursor \
                --output "$PROBE_DIR/cursor-probe.txt" \
                --timeout 60 \
                --capture-stdout \
                -- cursor agent -p --force --trust $CURSOR_MODEL_ARGS --workspace "$PWD" \
                "Respond with OK" \
                >"$PROBE_DIR/cursor-wrapper-retry.log" 2>&1 &
            RETRY_SENTINELS+=("$PROBE_DIR/cursor-probe.txt.done")
        fi

        if [[ ${#RETRY_SENTINELS[@]} -gt 0 ]]; then
            "$SCRIPT_DIR/wait-for-reviewers.sh" --timeout 120 "${RETRY_SENTINELS[@]}" \
                >"$PROBE_DIR/wait-retry.log" 2>&1 || true
        fi

        # Re-check codex retry result
        if [[ "$RETRY_CODEX" == "true" ]]; then
            if [[ -f "$PROBE_DIR/codex-probe.txt.done" ]]; then
                CODEX_EXIT=$(cat "$PROBE_DIR/codex-probe.txt.done")
                if [[ "$CODEX_EXIT" == "0" && -s "$PROBE_DIR/codex-probe.txt" ]]; then
                    CODEX_HEALTHY="true"
                    CODEX_PROBE_ERROR=""  # retry succeeded, clear error
                else
                    # Update error with retry failure info
                    if [[ -f "$PROBE_DIR/codex-probe.txt.diag" ]]; then
                        CODEX_PROBE_ERROR="Retry also failed: $(cat "$PROBE_DIR/codex-probe.txt.diag")"
                    elif [[ "$CODEX_EXIT" == "0" ]]; then
                        CODEX_PROBE_ERROR="Retry also produced no output"
                    else
                        CODEX_PROBE_ERROR="Retry also failed with exit code $CODEX_EXIT"
                    fi
                fi
            else
                CODEX_PROBE_ERROR="Retry process did not complete (sentinel file missing)"
            fi
        fi

        # Re-check cursor retry result
        if [[ "$RETRY_CURSOR" == "true" ]]; then
            if [[ -f "$PROBE_DIR/cursor-probe.txt.done" ]]; then
                CURSOR_EXIT=$(cat "$PROBE_DIR/cursor-probe.txt.done")
                if [[ "$CURSOR_EXIT" == "0" && -s "$PROBE_DIR/cursor-probe.txt" ]]; then
                    CURSOR_HEALTHY="true"
                    CURSOR_PROBE_ERROR=""  # retry succeeded, clear error
                else
                    if [[ -f "$PROBE_DIR/cursor-probe.txt.diag" ]]; then
                        CURSOR_PROBE_ERROR="Retry also failed: $(cat "$PROBE_DIR/cursor-probe.txt.diag")"
                    elif [[ "$CURSOR_EXIT" == "0" ]]; then
                        CURSOR_PROBE_ERROR="Retry also produced no output"
                    else
                        CURSOR_PROBE_ERROR="Retry also failed with exit code $CURSOR_EXIT"
                    fi
                fi
            else
                CURSOR_PROBE_ERROR="Retry process did not complete (sentinel file missing)"
            fi
        fi
    fi

    # Only emit health keys for tools that are installed — absent binaries
    # are already handled by *_AVAILABLE=false and should not propagate a
    # misleading *_HEALTHY=false into session-env.
    if [[ "$CODEX_AVAILABLE" == "true" ]]; then
        echo "CODEX_HEALTHY=$CODEX_HEALTHY"
        if [[ -n "$CODEX_PROBE_ERROR" ]]; then
            echo "CODEX_PROBE_ERROR=$CODEX_PROBE_ERROR"
        fi
    fi
    if [[ "$CURSOR_AVAILABLE" == "true" ]]; then
        echo "CURSOR_HEALTHY=$CURSOR_HEALTHY"
        if [[ -n "$CURSOR_PROBE_ERROR" ]]; then
            echo "CURSOR_PROBE_ERROR=$CURSOR_PROBE_ERROR"
        fi
    fi

fi
