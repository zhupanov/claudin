#!/usr/bin/env bash
# gh-pr-checks.sh — List PR check statuses.
#
# Wraps `gh pr checks` for fallback CI diagnosis when FAILED_RUN_ID
# is not available from ci-status.sh. Output is raw checks text to
# stdout since callers parse it for failed check identification.
#
# Usage:
#   gh-pr-checks.sh --pr <number> --repo <owner/repo>
#
# Arguments:
#   --pr   — PR number
#   --repo — Owner/repo identifier (e.g., "myorg/myrepo")
#
# Exit codes:
#   0 — success (checks printed to stdout)
#   1 — usage/argument error or gh command failure

set -euo pipefail

usage() { echo "Usage: gh-pr-checks.sh --pr <number> --repo <owner/repo>" >&2; }

PR=""
REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --pr and --repo are required" >&2
    usage; exit 1
fi

gh pr checks "$PR" --repo "$REPO"
