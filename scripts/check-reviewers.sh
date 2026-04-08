#!/usr/bin/env bash
# check-reviewers.sh — Check external reviewer binary availability.
#
# Checks if codex and cursor binaries are installed.
# This is NOT a full auth test — just binary existence.
#
# Usage:
#   check-reviewers.sh
#
# Outputs (key=value to stdout):
#   CODEX_AVAILABLE=true|false
#   CURSOR_AVAILABLE=true|false
#
# Exit codes:
#   0 — always

set -uo pipefail

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
