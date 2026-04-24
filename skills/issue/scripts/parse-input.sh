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
#   parse-input.sh --input-file FILE --output-dir DIR
#
# Both --input-file and --output-dir are required. DIR is created with
# mkdir -p at startup and normalized to an absolute path.
#
# Output (key=value lines on stdout):
#   ITEMS_TOTAL=<N>
#   ITEM_<i>_TITLE=<single-line title>           (i = 1..N)
#   ITEM_<i>_BODY_FILE=<absolute path>           (plain-text body file at
#                                                 $OUTPUT_DIR/item-<i>-body.txt;
#                                                 bytes identical to the parsed
#                                                 body, preserving newlines.
#                                                 Omitted when the item has no
#                                                 body — title-only MALFORMED.)
#   ITEM_<i>_REVIEWER=<attribution>              (OOS only)
#   ITEM_<i>_PHASE=<design|review>               (OOS only)
#   ITEM_<i>_VOTE_TALLY=<counts>                 (OOS only)
#   ITEM_<i>_MALFORMED=true                      (item cannot be emitted cleanly:
#                                                 either title-without-body, or
#                                                 an incomplete OOS item whose
#                                                 body was terminated by an
#                                                 ambiguous boundary heading
#                                                 with no structured-field
#                                                 close — see issue #138. In
#                                                 the latter case BODY_FILE is
#                                                 also emitted alongside
#                                                 MALFORMED, pointing to the
#                                                 parsed body text that
#                                                 survives as a diagnostic
#                                                 surface until the caller
#                                                 removes $OUTPUT_DIR.)
#
# The body is written to a file (instead of inline on stdout) so multi-line
# content is preserved verbatim and no large opaque payload enters the
# caller's post-tool-use context (issue #402).
#
# Exit code: 0 on success (even if some items are malformed — check
# ITEM_<i>_MALFORMED). 1 on usage error, missing input file, missing
# output-dir, or any file-write failure (via set -euo pipefail). Callers
# MUST treat captured stdout as unreliable on non-zero exit.

set -euo pipefail

INPUT_FILE=""
OUTPUT_DIR=""

usage() {
    echo "Usage: parse-input.sh --input-file FILE --output-dir DIR" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --input-file) INPUT_FILE="${2:?--input-file requires a value}"; shift 2 ;;
        --output-dir) OUTPUT_DIR="${2:?--output-dir requires a value}"; shift 2 ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$INPUT_FILE" ]]; then
    echo "ERROR: --input-file is required" >&2
    usage
    exit 1
fi

if [[ -z "$OUTPUT_DIR" ]]; then
    echo "ERROR: --output-dir is required" >&2
    usage
    exit 1
fi

if [[ ! -f "$INPUT_FILE" ]]; then
    echo "ERROR: input file not found: $INPUT_FILE" >&2
    exit 1
fi

mkdir -p "$OUTPUT_DIR"
# Normalize to absolute path so ITEM_<i>_BODY_FILE lines are CWD-independent
# for consumers.
OUTPUT_DIR=$(cd "$OUTPUT_DIR" && pwd)

# ---------------------------------------------------------------------------
# Parser state — mirrors create-oos-issues.sh:185-222's flush_item + while loop.
# Key invariant: a normally-emitted item has BOTH a title and a body. A title
# alone → ITEM_<i>_MALFORMED=true. An incomplete OOS item (see issue #138
# below) is flushed as MALFORMED with its non-empty body via emit_item's
# `force_malformed` parameter. Both cases feed ISSUES_FAILED in the caller.
#
# CURRENT_MODE tracks whether the in-progress item is OOS-shaped or generic-
# shaped. Structured OOS field branches (`- **Description**:`, `- **Reviewer**:`,
# `- **Vote tally**:`, `- **Phase**:`) fire only when CURRENT_MODE=oos; in
# generic items those lines are plain body text. `flush_item` resets
# CURRENT_MODE alongside the other per-item state.
#
# Pending-heading state (issue #138): PENDING_HEADING + PENDING_BODY defer
# the absorb-vs-split decision for a plain `### <title>` line that appears
# inside an OOS Description before any of Reviewer / Vote tally / Phase has
# fired. The line could be either a body subheading (#129 case 1) or the
# intended start of a new item (the #138 bug). Which one is resolved by
# what comes next:
#   * Any of Reviewer / Vote tally / Phase fires → fold PENDING_HEADING +
#     PENDING_BODY back into CURRENT_BODY (rule 1 — subheading case).
#   * A `### OOS_N:` line or EOF arrives → emit current OOS as MALFORMED
#     with its existing body, then emit the pending pair as a new generic
#     item (rule 2 — new-item case).
#   * Another plain `### <title>` line arrives while pending-active → append
#     to PENDING_BODY; do NOT trigger rule 2. Only `### OOS_N:` or EOF splits
#     (required so case 13's multi-subheading OOS still absorbs correctly).
# PENDING_HEADING is non-empty iff the pending state is active; PENDING_BODY
# accumulates continuation lines while pending-active.
# ---------------------------------------------------------------------------
ITEM_INDEX=0
CURRENT_TITLE=""
CURRENT_BODY=""
CURRENT_REVIEWER=""
CURRENT_VOTE=""
CURRENT_PHASE=""
IN_BODY=false
CURRENT_MODE=""
PENDING_HEADING=""
PENDING_BODY=""

emit_item() {
    local title="$1"
    local body="$2"
    local reviewer="$3"
    local vote="$4"
    local phase="$5"
    # force_malformed (6th arg): when "true", emit BODY_FILE + MALFORMED=true
    # together (the issue #138 incomplete-OOS path). Empty / falsy keeps the
    # legacy behavior: MALFORMED only when body is empty.
    local force_malformed="${6:-}"

    ITEM_INDEX=$((ITEM_INDEX + 1))

    if [[ -z "$title" ]]; then
        # No title at all — shouldn't happen, but guard.
        return
    fi

    if [[ -z "$body" ]]; then
        # Malformed: title without body. Emit as MALFORMED so the SKILL can
        # count it under ISSUES_FAILED (matching create-oos-issues.sh flush_item
        # behavior: "SKIPPED: '$CURRENT_TITLE' — missing description"). No body
        # file is written and no BODY_FILE line is emitted — consistent with
        # the pre-existing "no body key" invariant for the empty-body case.
        echo "ITEM_${ITEM_INDEX}_TITLE=$title"
        echo "ITEM_${ITEM_INDEX}_MALFORMED=true"
        return
    fi

    local body_file="$OUTPUT_DIR/item-${ITEM_INDEX}-body.txt"
    # Write body BEFORE emitting the BODY_FILE line so consumers never see a
    # path to a missing file. `printf '%s'` preserves byte-equivalence with
    # the prior base64 pipeline (no trailing newline injected). `set -euo
    # pipefail` above aborts on any write failure.
    printf '%s' "$body" > "$body_file"

    echo "ITEM_${ITEM_INDEX}_TITLE=$title"
    echo "ITEM_${ITEM_INDEX}_BODY_FILE=$body_file"
    if [[ "$force_malformed" == "true" ]]; then
        # Issue #138: incomplete OOS flushed mid-stream. Body is non-empty
        # (has the Description text), but the item is structurally malformed
        # because Reviewer / Vote tally / Phase never fired before the
        # ambiguous boundary heading arrived. The caller downstream counts it
        # under ISSUES_FAILED and does not create a GitHub issue for it — the
        # description is written to the body file at
        # $OUTPUT_DIR/item-<i>-body.txt and survives as a diagnostic surface
        # until the caller removes $OUTPUT_DIR.
        echo "ITEM_${ITEM_INDEX}_MALFORMED=true"
    fi
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

# resolve_pending_foldback — rule 1 resolution (issue #138).
#
# Called as the FIRST action of each structured-field branch (Description,
# Reviewer, Vote tally, Phase) before any BASH_REMATCH usage or state
# mutation. No-ops when PENDING_HEADING is empty. When pending-active, merges
# PENDING_HEADING + PENDING_BODY back into CURRENT_BODY (preserving the #129
# subheading-in-OOS-description behavior), then clears the pending state.
#
# Uses the conditional-append pattern so an empty CURRENT_BODY (the #131
# case 9 shape: empty inline Description) does not acquire a spurious
# leading newline.
resolve_pending_foldback() {
    if [[ -z "$PENDING_HEADING" ]]; then
        return
    fi
    if [[ -n "$CURRENT_BODY" ]]; then
        CURRENT_BODY+=$'\n'"$PENDING_HEADING"
    else
        CURRENT_BODY="$PENDING_HEADING"
    fi
    if [[ -n "$PENDING_BODY" ]]; then
        CURRENT_BODY+=$'\n'"$PENDING_BODY"
    fi
    PENDING_HEADING=""
    PENDING_BODY=""
}

# resolve_pending_split — rule 2 resolution (issue #138).
#
# Called as the FIRST action of the `### OOS_N:` heading branch (as a
# preamble to the existing #132 mode-guard) and from the terminal flush_item
# at EOF. No-ops when PENDING_HEADING is empty. When pending-active: emits
# the current OOS as MALFORMED (preserving its non-empty body), then emits
# the pending pair as a new generic item with no OOS metadata. After this
# call, the caller's remaining per-item state (CURRENT_TITLE, CURRENT_BODY,
# etc.) is reset — safe to start a new item inline.
resolve_pending_split() {
    if [[ -z "$PENDING_HEADING" ]]; then
        return
    fi
    # Capture pending state before flush_item clears it.
    local pending_title_line="$PENDING_HEADING"
    local pending_body="$PENDING_BODY"

    # Save current item's state, clear pending so flush_item does not re-enter
    # any pending-aware path, then emit current as MALFORMED.
    PENDING_HEADING=""
    PENDING_BODY=""
    if [[ -n "$CURRENT_TITLE" ]]; then
        emit_item "$CURRENT_TITLE" "$CURRENT_BODY" "$CURRENT_REVIEWER" \
            "$CURRENT_VOTE" "$CURRENT_PHASE" "true"
    fi
    # Reset per-item state (same fields flush_item clears).
    CURRENT_TITLE=""
    CURRENT_BODY=""
    CURRENT_REVIEWER=""
    CURRENT_VOTE=""
    CURRENT_PHASE=""
    IN_BODY=false
    CURRENT_MODE=""

    # Extract the pending heading's title from the raw stashed line. Re-match
    # the raw line against the plain-heading regex to get the title.
    local pending_title=""
    if [[ "$pending_title_line" =~ ^\#\#\#[[:space:]]+(.+)$ ]]; then
        pending_title="${BASH_REMATCH[1]}"
    fi
    # Emit pending pair as a generic item (no OOS fields).
    if [[ -n "$pending_title" ]]; then
        emit_item "$pending_title" "$pending_body" "" "" "" ""
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
    # Issue #138: clear pending state alongside per-item resets so pending
    # content cannot leak across items. resolve_pending_split (called by the
    # OOS heading preamble and the terminal EOF path) must run BEFORE
    # flush_item in those call sites, since flush_item silently drops any
    # pending state.
    PENDING_HEADING=""
    PENDING_BODY=""
}

# Parse line-by-line. Support both OOS (`### OOS_N: title`) and generic
# (`### <title>` followed by body text) formats, distinguished by CURRENT_MODE.
# Three guards coexist, each scoped to a different branch / trigger:
#
#   * Issue #129: a plain `### <subheading>` line inside an OOS Description
#     (CURRENT_MODE=oos AND IN_BODY=true) must not flush the OOS — it is a
#     body subheading (e.g., `### Notes`). Handled by the pending-heading
#     state below: the line enters PENDING_HEADING on first sight and is
#     folded back into CURRENT_BODY when the next structured field fires.
#
#   * Issue #132: a `### OOS_N: ...` line inside an active generic body
#     (CURRENT_MODE=generic AND IN_BODY=true with meaningful CURRENT_BODY) is
#     absorbed as body continuation rather than flushing. Symmetric mode-
#     guard on the OOS-heading branch, unchanged from PR #140.
#
#   * Issue #138: a plain `### <title>` line inside an OOS Description is
#     ambiguous — it could be a body subheading (#129) or the author's
#     intended start of a new generic item after an incomplete OOS. The
#     pending-heading state defers the decision: PENDING_HEADING stashes the
#     line, PENDING_BODY accumulates subsequent continuation lines (and
#     additional plain `### <subheading>` lines, so case 13 multi-subheading
#     still works). Resolution:
#       - Reviewer / Vote tally / Phase fires (any of these) →
#         resolve_pending_foldback absorbs pending content into CURRENT_BODY
#         (rule 1, preserves #129).
#       - `### OOS_N:` line arrives OR EOF is reached → resolve_pending_split
#         emits the current OOS as MALFORMED with its body, then emits
#         PENDING_HEADING + PENDING_BODY as a new generic item (rule 2).
#       - Another plain `### <title>` arrives while pending-active → append
#         to PENDING_BODY (does NOT trigger rule 2 — only `### OOS_N:` or
#         EOF splits).
#
# Well-formed OOS items (all 4 fields) close via Phase → IN_BODY=false →
# a subsequent `### <title>` correctly starts a new item without entering
# pending state. flush_item resets CURRENT_MODE and pending state alongside
# the other per-item state. resolve_pending_split runs BEFORE flush_item in
# split-path call sites since flush_item silently clears pending.
#
#   ┌─────────────────────────────┬──────────────────┬───────────────────┐
#   │ Trigger line                │ Pending-active?  │ Action            │
#   ├─────────────────────────────┼──────────────────┼───────────────────┤
#   │ `### OOS_N:` (plain)        │ no               │ flush + new OOS   │
#   │ `### OOS_N:` (gen body)     │ no               │ absorb (#132)     │
#   │ `### OOS_N:` (plain)        │ yes              │ split + new OOS   │
#   │ plain `### <title>` (new)   │ no, mode=oos,    │ start pending     │
#   │                             │   IN_BODY=true   │                   │
#   │ plain `### <title>` (new)   │ no, mode!=oos or │ flush + new gen   │
#   │                             │   IN_BODY=false  │                   │
#   │ plain `### <title>` (new)   │ yes              │ append to pending │
#   │ Description / Reviewer /    │ yes              │ fold-back then    │
#   │   Vote tally / Phase        │                  │   process field   │
#   │ Description / Reviewer /    │ no               │ process field     │
#   │   Vote tally / Phase        │                  │                   │
#   │ continuation (IN_BODY=true) │ yes              │ append to pending │
#   │ continuation (IN_BODY=true) │ no               │ append to body    │
#   │ EOF                         │ yes              │ split             │
#   │ EOF                         │ no               │ flush             │
#   └─────────────────────────────┴──────────────────┴───────────────────┘
while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$line" =~ ^\#\#\#[[:space:]]+OOS_[0-9]+:[[:space:]]+(.+)$ ]]; then
        # OOS-format heading — or a literal `### OOS_N: ...` line inside a
        # generic item's body (issue #132 case), or the resolution point for
        # an active pending-heading state (issue #138 rule 2).
        #
        # Priority order:
        #   1. #132 guard: inside an active generic body with meaningful
        #      content, absorb as continuation (unchanged from PR #140).
        #   2. #138 pending-split: if pending is active, emit current OOS as
        #      MALFORMED + pending pair as generic, then process the OOS_N:
        #      line as a fresh OOS heading.
        #   3. Default: flush current item + start a new OOS item.
        #
        # The #132 guard clause must run first because a generic body with a
        # nested `### OOS_42:` is the exact case case 10 locks in, and the
        # pending-heading state is gated on CURRENT_MODE=oos (so the two
        # paths are disjoint by mode — but explicit ordering is safer).
        #
        # Save BASH_REMATCH[1] into a local before calling
        # resolve_pending_split (which re-runs `=~` internally and would
        # otherwise clobber the capture).
        if [[ "$CURRENT_MODE" == "generic" && "$IN_BODY" == true && -n "${CURRENT_BODY//[[:space:]]/}" ]]; then
            CURRENT_BODY+=$'\n'"$line"
        else
            new_oos_title="${BASH_REMATCH[1]}"
            # Rule 2 preamble (issue #138): if pending-active, split before
            # starting the new OOS item. No-ops when pending is empty.
            resolve_pending_split
            flush_item
            CURRENT_TITLE="$new_oos_title"
            IN_BODY=false
            CURRENT_MODE="oos"
        fi
    elif [[ "$line" =~ ^\#\#\#[[:space:]]+(.+)$ ]]; then
        # Plain `### <title>` heading. Three paths depending on mode and
        # pending state:
        #
        #   1. CURRENT_MODE=oos AND IN_BODY=true AND pending empty → this is
        #      the #138 ambiguous case: stash the raw line in PENDING_HEADING
        #      and keep accumulating via the continuation branch.
        #   2. CURRENT_MODE=oos AND IN_BODY=true AND pending already active →
        #      another plain `### <subheading>` arriving while pending-active.
        #      Per case 13, append to PENDING_BODY (do NOT trigger rule 2).
        #   3. Otherwise → flush current item and start a new generic item.
        if [[ "$CURRENT_MODE" == "oos" && "$IN_BODY" == true ]]; then
            if [[ -z "$PENDING_HEADING" ]]; then
                # Path 1: first ambiguous heading — start pending state.
                PENDING_HEADING="$line"
            else
                # Path 2: additional heading while pending-active — accumulate.
                if [[ -n "$PENDING_BODY" ]]; then
                    PENDING_BODY+=$'\n'"$line"
                else
                    PENDING_BODY="$line"
                fi
            fi
        else
            # Path 3: normal flush + new generic item.
            new_title="${BASH_REMATCH[1]}"
            flush_item
            CURRENT_TITLE="$new_title"
            IN_BODY=true
            CURRENT_MODE="generic"
        fi
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Description\*\*:[[:space:]]*(.*)$ ]]; then
        # Accept empty inline value — the body may come entirely from continuation
        # lines (e.g. `- **Description**:` alone on its line with `  content` on
        # the next line). IN_BODY=true ensures those continuations are captured
        # by the fallback branch below.
        #
        # Description should not fire while pending-active (no `- **Description**:`
        # can follow an in-progress OOS item before Reviewer/Vote/Phase closes
        # it), but resolve_pending_foldback is idempotent — safe to call.
        # Capture BASH_REMATCH[1] first since resolve_pending_foldback does
        # not run `=~` itself but the pattern of saving captures before any
        # helper keeps future edits safe.
        description_inline="${BASH_REMATCH[1]}"
        resolve_pending_foldback
        CURRENT_BODY="$description_inline"
        IN_BODY=true
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Reviewer\*\*:[[:space:]]+(.+)$ ]]; then
        reviewer_value="${BASH_REMATCH[1]}"
        resolve_pending_foldback
        CURRENT_REVIEWER="$reviewer_value"
        IN_BODY=false
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Vote\ tally\*\*:[[:space:]]+(.+)$ ]]; then
        vote_value="${BASH_REMATCH[1]}"
        resolve_pending_foldback
        CURRENT_VOTE="$vote_value"
        IN_BODY=false
    elif [[ "$CURRENT_MODE" == "oos" && "$line" =~ ^-[[:space:]]+\*\*Phase\*\*:[[:space:]]+(.+)$ ]]; then
        phase_value="${BASH_REMATCH[1]}"
        resolve_pending_foldback
        CURRENT_PHASE="$phase_value"
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
        #
        # Issue #138: while pending-active, route continuation lines to
        # PENDING_BODY so they resolve together with the stashed heading.
        if [[ -n "$PENDING_HEADING" ]]; then
            if [[ -n "$PENDING_BODY" ]]; then
                PENDING_BODY+=$'\n'"$line"
            else
                PENDING_BODY="$line"
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

# EOF rule-2 resolution (issue #138): if a pending-heading state is still
# active, split the current OOS (MALFORMED) and emit the pending pair as a
# generic item before the terminal flush_item runs.
resolve_pending_split
flush_item

echo "ITEMS_TOTAL=$ITEM_INDEX"
exit 0
