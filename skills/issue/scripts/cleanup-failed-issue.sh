#!/usr/bin/env bash
# cleanup-failed-issue.sh — Best-effort close of an orphan GitHub issue when
# /issue's dependency-wiring path exhausts retries and the just-created issue
# would otherwise persist in the repo without its declared blockers.
#
# Single-attempt close (no retry) since this is itself a best-effort recovery
# step — if the close fails (permissions, lock, transient), /issue surfaces
# the issue URL on stderr so the operator can manually close.
#
# Usage:
#   cleanup-failed-issue.sh --issue-number N [--repo OWNER/REPO]
#
# Output (key=value on stdout):
#   On success:
#     CLOSED=true
#     ISSUE=<N>
#   On failure:
#     CLOSED=false
#     ISSUE=<N>
#     ERROR=<redacted-msg>
#
# Exit code: always 0 (best-effort). Caller distinguishes via CLOSED= field.

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
REDACT_HELPER="$REPO_ROOT/scripts/redact-secrets.sh"

ISSUE=""
REPO=""

usage() {
    cat <<USAGE >&2
Usage: cleanup-failed-issue.sh --issue-number N [--repo OWNER/REPO]
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue-number) ISSUE="${2:?--issue-number requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 0 ;;
    esac
done

if [[ -z "$ISSUE" || ! "$ISSUE" =~ ^[0-9]+$ ]]; then
    echo "CLOSED=false"
    echo "ISSUE=$ISSUE"
    echo "ERROR=invalid or missing --issue-number"
    exit 0
fi

if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
    if [[ -z "$REPO" ]]; then
        echo "CLOSED=false"
        echo "ISSUE=$ISSUE"
        echo "ERROR=could not determine repo"
        exit 0
    fi
fi

ERR_TMP=$(mktemp)
trap 'rm -f "$ERR_TMP"' EXIT

if gh issue close --repo "$REPO" "$ISSUE" --reason "not planned" >/dev/null 2>"$ERR_TMP"; then
    echo "CLOSED=true"
    echo "ISSUE=$ISSUE"
    exit 0
fi

ERR_CONTENT=$(cat "$ERR_TMP")
REDACTED_ERR=$(printf '%s' "$ERR_CONTENT" | "$REDACT_HELPER" 2>/dev/null) || REDACTED_ERR="(redaction-helper failed; original suppressed)"
ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
echo "CLOSED=false"
echo "ISSUE=$ISSUE"
echo "ERROR=$ERR_FLAT"
exit 0
