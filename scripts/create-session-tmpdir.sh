#!/usr/bin/env bash
# create-session-tmpdir.sh — Create a session-scoped temporary directory.
#
# Lightweight alternative to session-setup.sh for skills that only need
# a temp directory without preflight checks, Slack token checks, or repo
# name derivation. If your skill also needs those, use session-setup.sh.
#
# Usage:
#   create-session-tmpdir.sh --prefix <name>
#
# Arguments:
#   --prefix — Prefix for the temp directory (e.g., "claude-review")
#
# Outputs (key=value to stdout):
#   SESSION_TMPDIR=<path>
#
# Exit codes:
#   0 — success
#   1 — usage/argument error

set -euo pipefail

usage() { echo "Usage: create-session-tmpdir.sh --prefix <name>" >&2; }

PREFIX=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --prefix) PREFIX="${2:?--prefix requires a value}"; shift 2 ;;
        --help) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$PREFIX" ]]; then
    echo "ERROR: --prefix is required" >&2
    usage; exit 1
fi

TMPDIR=$(mktemp -d "/tmp/${PREFIX}-XXXXXX")
echo "SESSION_TMPDIR=$TMPDIR"
