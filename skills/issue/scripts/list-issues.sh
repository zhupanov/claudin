#!/usr/bin/env bash
# list-issues.sh — Snapshot open + recently-closed issue titles for LLM Phase 1
# semantic dedup.
#
# Emits a TSV snapshot suitable for the /issue skill's Phase 1 prompt (title-only
# candidate triage). Uses gh api --paginate so the snapshot is not capped at any
# fixed number of issues; the --limit path in gh issue list has no "unlimited"
# sentinel and would silently starve older/closed issues on large repos.
#
# Open issues: all of them.
# Closed issues: only those with closed_at >= today - closed-window-days.
#
# Usage:
#   list-issues.sh [--closed-window-days N] [--repo OWNER/REPO]
#
# Arguments:
#   --closed-window-days N — include closed issues whose closed_at is within the
#                            last N days (default: 90). Set to 0 to skip closed
#                            issues entirely.
#   --repo OWNER/REPO      — explicit repo (otherwise inferred from current dir
#                            via `gh repo view`).
#
# Output on stdout (key=value first, then TSV):
#   LIST_STATUS=ok               — snapshot succeeded; TSV follows
#   LIST_STATUS=failed           — snapshot failed; no TSV; fail-open to CREATE-all
#
#   Followed by zero or more TSV rows (tab-separated):
#     <number>\t<title>\t<state>\t<url>
#
# Stderr is used for warnings (portable-date fallbacks, rate-limit notes). All
# machine lines go to stdout.
#
# Exit code: always 0 (fail-open). A LIST_STATUS=failed line is the structured
# failure signal for the caller.

set -euo pipefail

CLOSED_WINDOW_DAYS=90
REPO=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --closed-window-days)
            CLOSED_WINDOW_DAYS="${2:?--closed-window-days requires a value}"
            shift 2
            ;;
        --repo)
            REPO="${2:?--repo requires a value}"
            shift 2
            ;;
        *)
            echo "LIST_STATUS=failed"
            echo "WARN: unknown option: $1" >&2
            exit 0
            ;;
    esac
done

# Validate closed-window-days is a non-negative integer.
if ! [[ "$CLOSED_WINDOW_DAYS" =~ ^[0-9]+$ ]]; then
    echo "LIST_STATUS=failed"
    echo "WARN: --closed-window-days must be a non-negative integer, got: $CLOSED_WINDOW_DAYS" >&2
    exit 0
fi

# Resolve repo identity.
if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
        echo "LIST_STATUS=failed"
        echo "WARN: failed to resolve repository name via 'gh repo view'" >&2
        exit 0
    }
fi

if [[ -z "$REPO" ]]; then
    echo "LIST_STATUS=failed"
    echo "WARN: empty repo name after gh repo view" >&2
    exit 0
fi

# ---------------------------------------------------------------------------
# Portable cutoff-date computation.
#
# BSD/macOS `date` uses `-v-Nd`; GNU/Linux `date` uses `-d "-N days"`. Rather
# than branch on the host, prefer python3 which is available on both platforms
# and already in this repo's allowlist (.claude/settings.json:120).
# ---------------------------------------------------------------------------
CUTOFF_DATE=""
if [[ "$CLOSED_WINDOW_DAYS" -gt 0 ]]; then
    if command -v python3 >/dev/null 2>&1; then
        CUTOFF_DATE=$(python3 -c "import datetime; print((datetime.date.today() - datetime.timedelta(days=$CLOSED_WINDOW_DAYS)).isoformat())" 2>/dev/null) || CUTOFF_DATE=""
    fi
    if [[ -z "$CUTOFF_DATE" ]]; then
        # Fallback: try BSD, then GNU.
        CUTOFF_DATE=$(date -v-"${CLOSED_WINDOW_DAYS}"d +%Y-%m-%d 2>/dev/null) || CUTOFF_DATE=""
    fi
    if [[ -z "$CUTOFF_DATE" ]]; then
        CUTOFF_DATE=$(date -d "-${CLOSED_WINDOW_DAYS} days" +%Y-%m-%d 2>/dev/null) || CUTOFF_DATE=""
    fi
    if [[ -z "$CUTOFF_DATE" ]]; then
        echo "LIST_STATUS=failed"
        echo "WARN: failed to compute cutoff date (no python3, BSD, or GNU date available)" >&2
        exit 0
    fi
fi

# ---------------------------------------------------------------------------
# Fetch issues via gh api --paginate.
#
# GitHub's REST issues endpoint returns both issues and PRs; filter PRs via
# `select(.pull_request == null)` to match the `gh issue list` behavior.
#
# state=all returns open + closed. We filter closed issues by closed_at in jq
# rather than using a `search` query so pagination is natural REST pagination
# (no search-result limits).
# ---------------------------------------------------------------------------
RAW=$(gh api --paginate "repos/${REPO}/issues?state=all&per_page=100" 2>/dev/null) || {
    echo "LIST_STATUS=failed"
    echo "WARN: gh api --paginate failed for repo $REPO (network, auth, or rate limit)" >&2
    exit 0
}

# Compose the jq filter. Each input is a page (JSON array); emit one TSV line
# per non-PR issue. For closed issues, keep only those with closed_at >= cutoff.
# --paginate concatenates pages as separate JSON documents; jq's default input
# mode reads them one-by-one, so `.[] | …` processes each issue across all
# pages.
#
# Titles may contain tabs or newlines; strip them so TSV stays one issue per
# line with 4 fields.
# shellcheck disable=SC2016  # $cutoff is a jq variable passed via --arg, not a shell variable
JQ_FILTER='.[] | select(.pull_request == null) | select(.state == "open" or (.state == "closed" and .closed_at != null and (.closed_at[:10] >= $cutoff))) | [(.number|tostring), (.title | gsub("\t"; " ") | gsub("\n"; " ") | gsub("\r"; " ")), .state, .html_url] | @tsv'

TSV=$(echo "$RAW" | jq -r --arg cutoff "${CUTOFF_DATE:-0000-00-00}" "$JQ_FILTER" 2>/dev/null) || {
    echo "LIST_STATUS=failed"
    echo "WARN: jq failed to parse gh api output" >&2
    exit 0
}

echo "LIST_STATUS=ok"
if [[ -n "$TSV" ]]; then
    printf '%s\n' "$TSV"
fi
exit 0
