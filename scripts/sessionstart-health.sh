#!/usr/bin/env bash
# sessionstart-health.sh — SessionStart hook that probes required CLI tools
# (jq, git) at session start and emits a spec-compliant advisory to Claude's
# session context when any are missing.
#
# INVARIANT: the additionalContext string MUST be composed only from fixed
# ASCII literals chosen from a small predetermined set — never interpolate
# runtime-derived variables (paths, version strings, locale-dependent text,
# command output, environment values) into this JSON. Hand-crafted JSON is
# only safe because the message body has no `"` / `\` / control characters.
# If dynamic fragments are ever needed, switch to a structured JSON emitter
# (e.g., `jq -n --arg ctx "$MSG" '...'`) and remove this invariant.
#
# SessionStart is non-blocking by spec: the script ALWAYS exits 0. A failing
# probe produces advisory JSON on stdout; a healthy environment produces
# nothing. The hook does not read stdin.

set -euo pipefail
LC_ALL=C

# Collect missing-tool fragments in a single string. Guarded `if ! command -v`
# is -e-safe because the `if` consumes the non-zero exit.
MSG=""
if ! command -v jq >/dev/null 2>&1; then
    MSG="larch hook preflight: jq not on PATH (install: brew install jq / apt install jq). Claude Code JSON parsing and several larch scripts depend on jq."
fi
if ! command -v git >/dev/null 2>&1; then
    if [[ -n "$MSG" ]]; then
        MSG="$MSG "
    fi
    MSG="${MSG}larch hook preflight: git not on PATH. The submodule-edit guard and most larch scripts depend on git."
fi

if [[ -n "$MSG" ]]; then
    # Hand-crafted single-line JSON. The two fixed-literal message strings
    # above contain no `"` / `\` / control characters, so no escaping is
    # required. If the INVARIANT above is ever violated, this line becomes
    # unsafe.
    printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"%s"}}\n' "$MSG"
fi

exit 0
