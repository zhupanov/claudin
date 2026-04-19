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
#       The inline value after `- **Description**:` may be empty — in that
#       case the body is supplied entirely by the continuation lines.
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
#
# CURRENT_MODE tracks whether the in-progress item is OOS-shaped or generic-
# shaped. Structured OOS field branches (`- **Description**:`, `- **Reviewer**:`,
# `- **Vote tally**:`, `- **Phase**:`) fire only when CURRENT_MODE=oos; in
# generic items those lines are plain body text. A `### <title>` line inside
# an OOS item's description body (CURRENT_MODE=oos AND IN_BODY=true) is
# absorbed as body continuation rather than starting a new item, so OOS
# descriptions may contain markdown subheadings. `flush_item` resets
# CURRENT_MODE alongside the other per-item state.
# ---------------------------------------------------------------------------
ITEM_INDEX=0
CURRENT_TITLE=""
CURRENT_BODY=""
CURRENT_REVIEWER=""
CURRENT_VOTE=""
CURRENT_PHASE=""
IN_BODY=false
CURRENT_MODE=""

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
    CURRENT_MODE=""
}

# Parse line-by-line. Support both OOS (`### OOS_N: title`) and generic
# (`### <title>` followed by body text) formats, distinguished by CURRENT_MODE.
# Both `### ` branches apply a symmetric mode-guard: a heading that falls
# inside another item's active body is absorbed as body continuation rather
# than flushing the current item.
#
#   * An `### OOS_N: title` line sets CURRENT_MODE=oos; the four structured
#     bullets (Description / Reviewer / Vote tally / Phase) are parsed as
#     metadata only while CURRENT_MODE=oos. In generic items those same
#     bullets are preserved verbatim as body text. UNLESS we are inside a
#     generic body (CURRENT_MODE=generic AND IN_BODY=true), in which case the
#     line is absorbed as body continuation (fix for issue #132 — a generic
#     item's body may contain the literal string `### OOS_N: ...` as prose).
#   * A plain `### <title>` line sets CURRENT_MODE=generic — UNLESS we are
#     inside an OOS description (CURRENT_MODE=oos AND IN_BODY=true), in which
#     case the line is absorbed as body continuation (so OOS descriptions may
#     contain subheadings like `### Notes`; fix for bug a in issue #129).
#   * Well-formed OOS items close their body when a Reviewer / Vote tally /
#     Phase field fires (all set IN_BODY=false), so a following `### <title>`
#     correctly starts a new item. An incomplete OOS item that has only a
#     Description (no trailing structured fields) leaves IN_BODY=true, so a
#     following `### <title>` is absorbed as continuation — by design. Feed
#     well-formed OOS inputs (all 4 fields) to terminate the body explicitly.
#   * flush_item resets CURRENT_MODE so per-item mode does not leak across
#     items.
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\#\#\#[[:space:]]+OOS_[0-9]+:[[:space:]]+(.+)$ ]]; then
        # OOS-format heading — or a literal `### OOS_N: ...` line inside a
        # generic item's body. Inside an active generic body with at least one
        # meaningful (non-whitespace) body line already accumulated, absorb as
        # body continuation rather than flushing (fix for issue #132).
        # Symmetric to the mode-guard on the plain `### <title>` branch below.
        # The meaningful-body check (`${CURRENT_BODY//[[:space:]]/}` — strip
        # all whitespace, test non-empty) aligns semantics with the
        # OOS→generic direction (where IN_BODY=true is set by
        # `**Description**:`, which also populates CURRENT_BODY with non-
        # whitespace content): do not absorb when the generic heading had
        # only blank or whitespace-only lines yet — that malformed case
        # flushes and lets the OOS line start a new OOS item, matching
        # pre-#132 behavior for those degenerate inputs. Avoid `=~` here
        # because it would clobber the outer OOS-heading regex's
        # BASH_REMATCH[1] capture before the `else` branch reads it.
        if [[ "$CURRENT_MODE" == "generic" && "$IN_BODY" == true && -n "${CURRENT_BODY//[[:space:]]/}" ]]; then
            # CURRENT_BODY has at least one non-whitespace character (outer
            # guard), hence is non-empty — the empty-body branch used by
            # other append sites is unreachable here.
            CURRENT_BODY+=$'\n'"$line"
        else
            # OOS body comes from the `**Description**:` field that follows,
            # not from continuation lines under the heading.
            flush_item
            CURRENT_TITLE="${BASH_REMATCH[1]}"
            IN_BODY=false
            CURRENT_MODE="oos"
        fi
    elif [[ "$line" =~ ^\#\#\#[[:space:]]+(.+)$ ]]; then
        # Generic heading — or a markdown subheading inside an OOS description.
        # Inside an active OOS body, absorb as body continuation rather than
        # flushing (fix for bug a in issue #129).
        if [[ "$CURRENT_MODE" == "oos" && "$IN_BODY" == true ]]; then
            if [[ -n "$CURRENT_BODY" ]]; then
                CURRENT_BODY+=$'\n'"$line"
            else
                CURRENT_BODY="$line"
            fi
        else
            flush_item
            CURRENT_TITLE="${BASH_REMATCH[1]}"
            IN_BODY=true
            CURRENT_MODE="generic"
        fi
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Description\*\*:[[:space:]]*(.*)$ ]]; then
        # Accept empty inline value — the body may come entirely from continuation
        # lines (e.g. `- **Description**:` alone on its line with `  content` on
        # the next line). IN_BODY=true ensures those continuations are captured
        # by the fallback branch below.
        CURRENT_BODY="${BASH_REMATCH[1]}"
        IN_BODY=true
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Reviewer\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_REVIEWER="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Vote\ tally\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_VOTE="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Phase\*\*:[[:space:]]+(.+)$ ]]; then
        CURRENT_PHASE="${BASH_REMATCH[1]}"
        IN_BODY=false
    elif [[ "$IN_BODY" == true ]]; then
        # Continuation line. Preserve blank lines in BOTH modes — multi-paragraph
        # descriptions need them. OOS structured field markers (Reviewer, Vote
        # tally, Phase) already set IN_BODY=false above, so blank lines inside
        # a Description cannot bleed past the next field. In generic mode, lines
        # that look like OOS bullets (`- **Reviewer**:`, etc.) fall through to
        # here and are preserved as ordinary body text (fix for bug b in #129).
        # This matches the behavior fix applied to the deleted
        # scripts/create-oos-issues.sh (see CHANGELOG 3.3.10).
        if [[ -n "$CURRENT_BODY" ]]; then
            CURRENT_BODY+=$'\n'"$line"
        else
            CURRENT_BODY="$line"
        fi
    fi
done < "$INPUT_FILE"

flush_item

echo "ITEMS_TOTAL=$ITEM_INDEX"
exit 0
