#!/usr/bin/env bash
# gh-run-logs.sh — View failed CI run logs.
#
# Wraps `gh run view --log-failed` for diagnostic purposes.
# Output is raw log text to stdout (not KEY=value) since callers
# need the full unstructured log for AI-driven diagnosis.
#
# Usage:
#   gh-run-logs.sh --run-id <id> --repo <owner/repo>
#
# Arguments:
#   --run-id — GitHub Actions workflow run ID
#   --repo   — Owner/repo identifier (e.g., "myorg/myrepo")
#
# Exit codes:
#   0 — success (logs printed to stdout)
#   1 — usage/argument error or gh command failure

set -euo pipefail

usage() { echo "Usage: gh-run-logs.sh --run-id <id> --repo <owner/repo>" >&2; }

RUN_ID=""
REPO=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --run-id) RUN_ID="${2:?--run-id requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$RUN_ID" ]] || [[ -z "$REPO" ]]; then
    echo "ERROR: --run-id and --repo are required" >&2
    usage; exit 1
fi

gh run view "$RUN_ID" --repo "$REPO" --log-failed
