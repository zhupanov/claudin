#!/usr/bin/env bash
# parse-input.sh — Parse the /issue batch-mode input file into structured
# per-item ITEM_<i>_* lines consumable by the SKILL prompt.
#
# Accepts two input shapes:
#
#   (1) OOS markdown (primary): lifted verbatim from the deleted
#       scripts/create-oos-issues.sh parser (including flush_item semantics)
#       so /implement Step 9a.1 can feed the same oos-items.md it produces
#       today without translation.
#
#         ### OOS_N: <short title>
#         - **Description**: <possibly multi-line>
#           <continuation lines>
#         - **Reviewer**: <attribution>
#         - **Vote tally**: <YES/NO/EXONERATE counts>
#         - **Phase**: design|review
#
#   (2) Generic fallback: for non-OOS callers, accept `### <title>` headings
#       followed by free-form body. Emits only ITEM_<i>_TITLE / ITEM_<i>_BODY.
#
# Usage:
#   parse-input.sh --input-file FILE
#
# Output (key=value lines on stdout):
#   ITEMS_TOTAL=<N>
#   ITEM_<i>_TITLE=<single-line title>           (i = 1..N)
#   ITEM_<i>_BODY=<base64-encoded body>          (base64 so it survives shell)
#   ITEM_<i>_REVIEWER=<attribution>              (OOS only)
#   ITEM_<i>_PHASE=<design|review>               (OOS only)
#   ITEM_<i>_VOTE_TALLY=<counts>                 (OOS only)
#   ITEM_<i>_MALFORMED=true                      (title without body — will fail)
#
# The BODY is base64-encoded (single line, no wrapping) so multi-line content
# does not collide with the one-key-per-line contract.
#
# Exit code: 0 on success (even if some items are malformed — check
# ITEM_<i>_MALFORMED). 1 on usage error or missing input file.

set -euo pipefail

INPUT_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-file) INPUT_FILE="${2:?--input-file requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; echo "Usage: parse-input.sh --input-file FILE" >&2; exit 1 ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "Usage: parse-input.sh --input-file FILE" >&2
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: input file not found: $INPUT_FILE" >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Parser state — mirrors create-oos-issues.sh:185-222's flush_item + while loop.
# Key invariant: an item is emitted only when it has BOTH a title and a body/
# description. A title alone → ITEM_<i>_MALFORMED=true (the caller / SKILL
# treats this as an early-failed item that contributes to ISSUES_FAILED).
# ---------------------------------------------------------------------------
ITEM_INDEX=0
CURRENT_TITLE=""
CURRENT_BODY=""
CURRENT_REVIEWER=""
CURRENT_VOTE=""
CURRENT_PHASE=""
IN_BODY=false
MODE="oos"  # oos or generic — auto-detected per item from the Description field

b64() {
    # Portable single-line base64 (no wrapping). macOS `base64` wraps at 76 chars
    # by default; use `-w 0` on GNU, and strip newlines as a cross-platform fallback.
    if base64 -w 0 </dev/null >/dev/null 2>&1; then
        base64 -w 0
    else
        base64 | tr -d '\n'
    fi
}

emit_item() {
    local title="$1"
    local body="$2"
    local reviewer="$3"
    local vote="$4"
    local phase="$5"

    ITEM_INDEX=$((ITEM_INDEX + 1))

    if [[ -z "$title" ]]; then
        # No title at all — shouldn't happen, but guard.
        return
    fi

    if [[ -z "$body" ]]; then
        # Malformed: title without body. Emit as MALFORMED so the SKILL can
        # count it under ISSUES_FAILED (matching create-oos-issues.sh flush_item
        # behavior: "SKIPPED: '$CURRENT_TITLE' — missing description").
        echo "ITEM_${ITEM_INDEX}_TITLE=$title"
        echo "ITEM_${ITEM_INDEX}_MALFORMED=true"
        return
    fi

    local b64_body
    b64_body=$(printf '%s' "$body" | b64)

    echo "ITEM_${ITEM_INDEX}_TITLE=$title"
    echo "ITEM_${ITEM_INDEX}_BODY=$b64_body"
    if [[ -n "$reviewer" ]]; then
        echo "ITEM_${ITEM_INDEX}_REVIEWER=$reviewer"
    fi
    if [[ -n "$vote" ]]; then
        echo "ITEM_${ITEM_INDEX}_VOTE_TALLY=$vote"
    fi
    if [[ -n "$phase" ]]; then
        echo "ITEM_${ITEM_INDEX}_PHASE=$phase"
    fi
}

flush_item() {
    if [[ -n "$CURRENT_TITLE" ]]; then
        emit_item "$CURRENT_TITLE" "$CURRENT_BODY" "$CURRENT_REVIEWER" "$CURRENT_VOTE" "$CURRENT_PHASE"
    fi
    CURRENT_TITLE=""
    CURRENT_BODY=""
    CURRENT_REVIEWER=""
    CURRENT_VOTE=""
    CURRENT_PHASE=""
    IN_BODY=false
}

# Parse line-by-line. Support both OOS (`### OOS_N: title`) and generic
# (`### <title>` followed by body text) formats. The `**Description**:` line
# is OOS-specific — its absence means generic mode, where everything after
# the `### ` line until the next `### ` is the body.
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\#\#\#[[:space:]]+OOS_[0-9]+:[[:space:]]+(.+)$ ]]; then
        flush_item
        CURRENT_TITLE="${BASH_REMATCH[1]}"
        MODE="oos"
        IN_BODY=false
    elif [[ "$line" =~ ^\#\#\#[[:space:]]+(.+)$ ]]; then
        # Generic title.
        flush_item
        CURRENT_TITLE="${BASH_REMATCH[1]}"
        MODE="generic"
        IN_BODY=true
    elif [[ "$line" =~ ^-[[:space:]]+\*\*Description\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_BODY="${BASH_REMATCH[1]}"
        IN_BODY=true
    elif [[ "$line" =~ ^-[[:space:]]+\*\*Reviewer\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_REVIEWER="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$line" =~ ^-[[:space:]]+\*\*Vote\ tally\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_VOTE="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$line" =~ ^-[[:space:]]+\*\*Phase\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_PHASE="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$IN_BODY" == true ]]; then
        # Continuation line. Preserve blank lines only in generic mode (OOS
        # mode stops at the next structured field or blank line between
        # items).
        if [[ "$MODE" == "oos" ]]; then
            if [[ -n "${line// }" ]]; then
                CURRENT_BODY+=$'\n'"$line"
            fi
        else
            if [[ -n "$CURRENT_BODY" ]]; then
                CURRENT_BODY+=$'\n'"$line"
            else
                CURRENT_BODY="$line"
            fi
        fi
    fi
done < "$INPUT_FILE"

flush_item

echo "ITEMS_TOTAL=$ITEM_INDEX"
exit 0
