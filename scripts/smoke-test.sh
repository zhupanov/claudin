#!/usr/bin/env bash
# smoke-test.sh — Validation-only smoke test for the larch plugin.
#
# Runs the plugin structure validator and optionally `claude plugin validate .`
# if the Claude CLI is available. Does not modify files.
#
# Called by:
#   1. .github/workflows/ci.yaml (plugin-structure job)
#   2. Developers, directly: bash scripts/smoke-test.sh
#
# Exit codes:
#   0 — all checks passed
#   1 — one or more checks failed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: not inside a git repository" >&2
    exit 1
}
cd "$REPO_ROOT"

ERRORS=0

# --- 1. Run the plugin structure validator ---
echo "=== Running plugin structure validator ==="
if bash "$SCRIPT_DIR/validate-plugin-structure.sh"; then
    echo "✓ Plugin structure validator passed"
else
    echo "✗ Plugin structure validator failed" >&2
    ERRORS=$((ERRORS + 1))
fi

# --- 2. Run claude plugin validate (if available) ---
# NOTE: treated as advisory (warning, not error) because the CLI schema may
# evolve independently of the plugin structure validator. The plugin structure
# validator (validate-plugin-structure.sh) is the authoritative gate.
if command -v claude >/dev/null 2>&1; then
    echo "=== Running claude plugin validate (advisory) ==="
    if claude plugin validate . 2>&1; then
        echo "✓ claude plugin validate passed"
    else
        echo "⚠ claude plugin validate reported warnings/errors (advisory — not blocking)" >&2
    fi
else
    echo "=== Skipping claude plugin validate (claude CLI not found) ==="
fi

# --- Result ---
if [ "$ERRORS" -eq 0 ]; then
    echo "Smoke test OK"
    exit 0
else
    printf 'Smoke test: %d check(s) failed\n' "$ERRORS" >&2
    exit 1
fi
