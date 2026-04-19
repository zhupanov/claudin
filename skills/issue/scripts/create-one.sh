#!/usr/bin/env bash
# create-one.sh — Create a single GitHub issue with defensive-guards that
# preserve the compatibility behavior of the deleted scripts/create-oos-issues.sh.
#
# Guards:
#   - [OOS] double-prefix normalization: strip any leading `[OOS]` (case-
#     insensitive, with optional whitespace) from the input title before
#     applying --title-prefix, so `[OOS] [OOS] …` cannot happen.
#   - Optional-label probe: for each --label value, probe `gh label list
#     --search <L>`; if the label does not exist in the target repo, silently
#     drop that label with a stderr warning. Matches create-oos-issues.sh:71-75.
#   - --dry-run: no network calls, emit DRY_RUN=true plus the final title/body
#     preview.
#
# The OOS-specific body template (Out-of-Scope heading, Surfaced by / Phase /
# Vote tally lines, Description heading, automated-larch footer — as in the
# deleted scripts/create-oos-issues.sh:149-162) is assembled by the caller
# (/issue's SKILL.md in batch mode) and passed via --body-file, not by this
# script. create-one.sh deliberately knows only about title / body-file /
# labels / prefix / dry-run so it stays composable.
#
# Usage:
#   create-one.sh --title TITLE [--title-prefix PREFIX] [--label L]... \
#                 [--body FILE | --body-file FILE] \
#                 [--repo OWNER/REPO] [--dry-run]
#
# Arguments:
#   --title TITLE            — issue title (required).
#   --title-prefix PREFIX    — optional prefix (e.g. "[OOS]"). Applied after
#                              normalizing any existing matching prefix on TITLE.
#   --label L                — repeatable. Each label is probed against the repo
#                              and silently dropped if missing.
#   --body FILE              — alias for --body-file.
#   --body-file FILE         — path to a file containing the issue body verbatim.
#   --repo OWNER/REPO        — target repo (otherwise inferred).
#   --dry-run                — do not call gh; emit DRY_RUN=true and preview.
#
# Output (key=value on stdout; warnings on stderr):
#   ISSUE_NUMBER=<N>   ISSUE_URL=<url>    on success
#   ISSUE_FAILED=true  ISSUE_ERROR=<msg>  on failure
#   DRY_RUN=true       on --dry-run success path
#
# Exit code:
#   0 — success (issue created OR --dry-run emitted preview)
#   1 — arg or usage error
#   2 — gh create failure (ISSUE_FAILED=true already emitted on stdout)
#   3 — redaction helper failure (ISSUE_FAILED=true with ISSUE_ERROR=redaction:…)
#
# Defense-in-depth: TITLE and BODY_CONTENT are piped through
# scripts/redact-secrets.sh before being passed to gh. This scrubs a fixed
# set of token families (sk-*, ghp_, AKIA, xox, JWT, PEM) as a deterministic
# backstop to prompt-level sanitization. See SECURITY.md.

set -euo pipefail

# Resolve the repo-root path to scripts/redact-secrets.sh. This file sits at
# skills/issue/scripts/create-one.sh, so the repo root is three levels up.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
REDACT_HELPER="$REPO_ROOT/scripts/redact-secrets.sh"

# redact_or_fail <text> → prints redacted text on stdout, or emits
# ISSUE_FAILED/ISSUE_ERROR and exits 3 on helper failure. The helper is
# required — there is no fallback to un-redacted content, per the
# defense-in-depth fail-closed design.
redact_or_fail() {
    local text="$1"
    local result
    if result=$(printf '%s' "$text" | "$REDACT_HELPER" 2>/dev/null); then
        printf '%s' "$result"
    else
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=redaction: helper $REDACT_HELPER failed or missing"
        exit 3
    fi
}

TITLE=""
TITLE_PREFIX=""
BODY_FILE=""
REPO=""
DRY_RUN=false
LABELS=()

usage() {
    cat <<USAGE >&2
Usage: create-one.sh --title TITLE [--title-prefix PREFIX] [--label L]... \\
                     [--body FILE | --body-file FILE] \\
                     [--repo OWNER/REPO] [--dry-run]
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
        --title-prefix) TITLE_PREFIX="${2:?--title-prefix requires a value}"; shift 2 ;;
        --label) LABELS+=("${2:?--label requires a value}"); shift 2 ;;
        --body|--body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$TITLE" ]]; then
    usage
    exit 1
fi

# Redact TITLE before [OOS] double-prefix normalization so the normalization
# operates on scrubbed content and downstream FINAL_TITLE / DRY_RUN_TITLE /
# ISSUE_TITLE are uniformly redacted.
TITLE=$(redact_or_fail "$TITLE")

# Resolve repo if not provided.
if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
    if [[ -z "$REPO" ]] && [[ "$DRY_RUN" == false ]]; then
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=could not determine repo"
        exit 2
    fi
fi

# ---------------------------------------------------------------------------
# [OOS] double-prefix normalization.
#
# If TITLE_PREFIX is set and TITLE already starts with the same prefix (case-
# insensitive, with optional whitespace), strip it so applying the prefix a
# second time produces a clean result.
# ---------------------------------------------------------------------------
if [[ -n "$TITLE_PREFIX" ]]; then
    # Build a case-insensitive regex-style check. Compare the normalized lowercase
    # variants of the starts-with check.
    prefix_lower=$(echo "$TITLE_PREFIX" | tr '[:upper:]' '[:lower:]')
    title_lower=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
    if [[ "$title_lower" == "$prefix_lower"* ]]; then
        # Strip the prefix and any whitespace after it.
        TITLE="${TITLE:${#TITLE_PREFIX}}"
        TITLE="${TITLE#"${TITLE%%[![:space:]]*}"}"
    fi
    FINAL_TITLE="$TITLE_PREFIX $TITLE"
else
    FINAL_TITLE="$TITLE"
fi

# ---------------------------------------------------------------------------
# Probe labels. Drop any label that does not exist in the target repo, with a
# stderr warning. Matches compatibility behavior of create-oos-issues.sh:71-75.
# In --dry-run mode without a resolvable repo, skip the probe entirely and
# accept all labels as-is.
# ---------------------------------------------------------------------------
VALID_LABELS=()
for L in "${LABELS[@]+"${LABELS[@]}"}"; do
    if [[ -z "$REPO" ]] && [[ "$DRY_RUN" == true ]]; then
        VALID_LABELS+=("$L")
        continue
    fi
    # Probe. gh label list --search returns partial matches; require exact name.
    if gh label list --repo "$REPO" --search "$L" --json name --jq '.[].name' 2>/dev/null | grep -qx -- "$L"; then
        VALID_LABELS+=("$L")
    else
        echo "WARN: label '$L' does not exist in $REPO, skipping" >&2
    fi
done

# ---------------------------------------------------------------------------
# Assemble the body.
# ---------------------------------------------------------------------------
BODY_CONTENT=""
BODY_TMP=""
# shellcheck disable=SC2317  # reachable via EXIT trap; shellcheck can't see indirect invocation
cleanup() {
    if [[ -n "${BODY_TMP:-}" ]] && [[ -f "$BODY_TMP" ]]; then
        rm -f "$BODY_TMP"
    fi
}
trap cleanup EXIT

if [[ -n "$BODY_FILE" ]]; then
    if [[ ! -f "$BODY_FILE" ]]; then
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=body file not found: $BODY_FILE"
        exit 1
    fi
    BODY_CONTENT=$(cat "$BODY_FILE")
fi

# Single structural choke point: redact BODY_CONTENT after all body-assembly
# paths converge, before dry-run branching or gh invocation. Any future body
# source added above the fi must still go through this point — that is the
# invariant this placement encodes.
if [[ -n "$BODY_CONTENT" ]]; then
    BODY_CONTENT=$(redact_or_fail "$BODY_CONTENT")
fi

# ---------------------------------------------------------------------------
# Dry-run path.
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
    echo "DRY_RUN=true"
    echo "DRY_RUN_TITLE=$FINAL_TITLE"
    echo "ISSUE_TITLE=$FINAL_TITLE"
    if [[ ${#VALID_LABELS[@]} -gt 0 ]]; then
        DRY_LABELS_JOINED=$(IFS=,; echo "${VALID_LABELS[*]}")
        echo "DRY_RUN_LABELS=$DRY_LABELS_JOINED"
    fi
    # Body preview: first 300 chars.
    if [[ -n "$BODY_CONTENT" ]]; then
        PREVIEW="${BODY_CONTENT:0:300}"
        # Flatten to single line for key=value.
        PREVIEW_FLAT=$(printf '%s' "$PREVIEW" | tr '\n' ' ' | tr -s ' ')
        echo "DRY_RUN_BODY_PREVIEW=$PREVIEW_FLAT"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Real create. Write body to a temp file so quoting is safe.
# ---------------------------------------------------------------------------
BODY_TMP=$(mktemp)
printf '%s' "$BODY_CONTENT" > "$BODY_TMP"

GH_ARGS=(issue create --repo "$REPO" --title "$FINAL_TITLE" --body-file "$BODY_TMP")
for L in "${VALID_LABELS[@]+"${VALID_LABELS[@]}"}"; do
    GH_ARGS+=(--label "$L")
done

if ISSUE_URL=$(gh "${GH_ARGS[@]}" 2>&1); then
    # gh issue create emits the URL on stdout. Extract the trailing number.
    URL_LINE=$(echo "$ISSUE_URL" | grep -oE 'https?://[^[:space:]]+/issues/[0-9]+' | tail -1)
    if [[ -z "$URL_LINE" ]]; then
        # gh's output on this branch may include body fragments echoed by the
        # API on a rejected request — redact through the same helper before
        # surfacing to stdout.
        REDACTED_OUTPUT=$(redact_or_fail "$ISSUE_URL")
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=gh issue create did not emit a URL (output: $REDACTED_OUTPUT)"
        exit 2
    fi
    ISSUE_NUM=$(echo "$URL_LINE" | grep -oE '[0-9]+$')
    echo "ISSUE_NUMBER=$ISSUE_NUM"
    echo "ISSUE_URL=$URL_LINE"
    echo "ISSUE_TITLE=$FINAL_TITLE"
    exit 0
else
    # ISSUE_URL here actually holds stderr content because of 2>&1.
    # Redact secondary leak surface (tokens in auth-failure messages, request
    # bodies echoed by the API in 4xx responses) before flattening/echoing.
    REDACTED_ERR=$(redact_or_fail "$ISSUE_URL")
    ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
    echo "ISSUE_FAILED=true"
    echo "ISSUE_ERROR=$ERR_FLAT"
    exit 2
fi
