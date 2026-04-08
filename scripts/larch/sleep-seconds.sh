#!/usr/bin/env bash
# sleep-seconds.sh — Sleep for a specified number of seconds.
#
# Thin wrapper around `sleep` to avoid direct Bash commands in
# skill SKILL.md files.
#
# Usage:
#   sleep-seconds.sh <seconds>
#
# Arguments:
#   First positional argument — number of seconds to sleep
#
# Exit codes:
#   0 — always

set -euo pipefail

if [[ $# -lt 1 ]]; then
    echo "Usage: sleep-seconds.sh <seconds>" >&2
    exit 1
fi

sleep "$1"
