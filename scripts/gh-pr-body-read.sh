#!/usr/bin/env bash
# gh-pr-body-read.sh — Read a PR's body text to a file.
#
# Wraps `gh pr view --json body` and writes the body content to a
# specified output file. Uses file output (not stdout) to avoid
# breaking the repo's KEY=value parsing convention — PR bodies can
# contain arbitrary text including KEY=value-like strings.
#
# Usage:
#   gh-pr-body-read.sh --pr <number> --output <path>
#
# Arguments:
#   --pr     — PR number
#   --output — Path to write the body text to
#
# Outputs (key=value to stdout):
#   BODY_FILE=<path>
#
# Exit codes:
#   0 — success
#   1 — usage/argument error or gh command failure

set -euo pipefail

usage() { echo "Usage: gh-pr-body-read.sh --pr <number> --output <path>" >&2; }

PR=""
OUTPUT_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --pr) PR="${2:?--pr requires a value}"; shift 2 ;;
        --output) OUTPUT_FILE="${2:?--output requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PR" ]] || [[ -z "$OUTPUT_FILE" ]]; then
    echo "ERROR: --pr and --output are required" >&2
    usage; exit 1
fi

gh pr view "$PR" --json body -q '.body' > "$OUTPUT_FILE"
echo "BODY_FILE=$OUTPUT_FILE"
