#!/usr/bin/env bash
# assemble-anchor.sh — assemble the anchor comment body from local fragments.
#
# Walks SECTION_MARKERS (sourced from anchor-section-markers.sh), reads each
# fragment file under --sections-dir, emits `<!-- section:<slug> -->\n<content>\n<!-- section-end:<slug> -->`
# marker pairs (empty content when a fragment file is absent), prepends the
# first-line HTML anchor marker, and writes the assembled body to --output.
#
# Seed-only visible-placeholder behavior: when every fragment is absent,
# zero-byte, or whitespace-only (lenient predicate), the assembled body
# carries one extra italic-markdown line between the first-line HTML marker
# and the first <!-- section:... --> open marker so the comment renders
# non-empty in GitHub's UI. Populated runs (any fragment with at least one
# non-whitespace byte) suppress the placeholder and are byte-for-byte
# unchanged. See scripts/assemble-anchor.md "Seed-only visible placeholder".
#
# Consumers:
#   - skills/implement/SKILL.md Step 0.5 (Branch 2/3 adoption seed body, Branch 4
#     first-remote-write seed body), Steps 1/2/5/7a/8/9a.1/11 (progressive upserts —
#     Step 2 covers Q/A anchor refresh after each opportunistic question or
#     mid-coding ambiguity resolution).
#   - skills/implement/references/rebase-rebump-subprocedure.md Step 6 (Phase 5 —
#     post-rebase anchor version-bump-reasoning refresh).
#
# Output contract (KEY=value on stdout):
#   Success:  ASSEMBLED=true
#             OUTPUT=<path>
#   Failure:  FAILED=true
#             ERROR=<single-line message>
#
# Exit codes:
#   0 — success
#   1 — invocation / usage error (missing flag, empty value, missing helper)
#   2 — I/O failure (unreadable sections dir, unwritable output path, etc.)
#
# The helper does NOT invoke the redaction pipeline — that responsibility
# lives with scripts/tracking-issue-write.sh at publish time. Compose-time
# sanitization of fragment bodies is the caller's responsibility (see
# skills/implement/SKILL.md "Compose-time sanitization" and the sibling
# scripts/assemble-anchor.md for the layering spec).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MARKERS_HELPER="$SCRIPT_DIR/anchor-section-markers.sh"

if [ ! -f "$MARKERS_HELPER" ]; then
    echo "FAILED=true"
    echo "ERROR=missing helper: $MARKERS_HELPER"
    exit 1
fi

# shellcheck source=scripts/anchor-section-markers.sh
# shellcheck disable=SC1091
source "$MARKERS_HELPER"

fail_usage() {
    echo "FAILED=true"
    echo "ERROR=usage: $1"
    exit 1
}

fail_io() {
    echo "FAILED=true"
    echo "ERROR=$1"
    exit 2
}

SECTIONS_DIR=""
ISSUE=""
OUTPUT=""

while [ $# -gt 0 ]; do
    case "$1" in
        --sections-dir)
            [ $# -ge 2 ] || fail_usage "--sections-dir requires a value"
            SECTIONS_DIR="$2"; shift 2 ;;
        --issue)
            [ $# -ge 2 ] || fail_usage "--issue requires a value"
            ISSUE="$2"; shift 2 ;;
        --output)
            [ $# -ge 2 ] || fail_usage "--output requires a value"
            OUTPUT="$2"; shift 2 ;;
        *)
            fail_usage "unknown flag: $1" ;;
    esac
done

[ -n "$SECTIONS_DIR" ] || fail_usage "--sections-dir is required"
[ -n "$ISSUE" ]        || fail_usage "--issue is required"
[ -n "$OUTPUT" ]       || fail_usage "--output is required"

# Validate --issue is a non-negative integer (matches tracking-issue-write.sh convention).
case "$ISSUE" in
    ''|*[!0-9]*) fail_usage "invalid value for --issue: '$ISSUE' (expected non-negative integer)" ;;
esac

# Ensure output parent directory exists.
OUTPUT_DIR="$(dirname "$OUTPUT")"
mkdir -p "$OUTPUT_DIR" 2>/dev/null || fail_io "cannot create output directory: $OUTPUT_DIR"

# Missing sections directory is tolerated — walk emits all empty marker pairs.
# Unreadable sections directory is an I/O failure (distinguish missing vs permission denied).
# A non-directory entry (regular file, symlink to file, fifo, etc.) is fail-closed:
# silently walking it would treat each `<slug>.md` path lookup as "file not present" and
# emit an all-empty skeleton, which could overwrite populated remote anchor content on
# a subsequent upsert — a documentation-correctness regression.
if [ -e "$SECTIONS_DIR" ]; then
    if [ ! -d "$SECTIONS_DIR" ]; then
        fail_io "sections-dir exists but is not a directory: $SECTIONS_DIR"
    fi
    if [ ! -r "$SECTIONS_DIR" ]; then
        fail_io "sections directory not readable: $SECTIONS_DIR"
    fi
fi

# Pre-pass: verify every existing fragment file is readable BEFORE entering
# the assembly brace-group (whose redirection `> "$TMP_OUTPUT"` would swallow
# any FAILED=true / ERROR= output emitted from inside the loop into the tmp
# file instead of the parent's stdout). Any unreadable fragment fails closed
# now, with the envelope reaching the parent shell's stdout intact.
for slug in "${SECTION_MARKERS[@]}"; do
    fragment="$SECTIONS_DIR/$slug.md"
    if [ -f "$fragment" ] && [ ! -r "$fragment" ]; then
        fail_io "failed to read fragment: $fragment"
    fi
done

# Seed-only visible-placeholder pre-pass: detect whether every fragment is
# absent, zero-byte, or whitespace-only (lenient predicate per dialectic
# DECISION_1 and Round 2 user confirmation in /design — see the
# "Seed-only visible placeholder" subsection of scripts/assemble-anchor.md).
# An anchor body composed entirely of HTML comment markers renders invisible
# in GitHub's UI; emit one visible markdown line in that case so the seed
# anchor is not blank between Step 0.5 plant and the first progressive
# upsert. Populated runs (any fragment with at least one non-whitespace
# byte) are byte-for-byte unchanged.
ALL_EMPTY=true
for slug in "${SECTION_MARKERS[@]}"; do
    fragment="$SECTIONS_DIR/$slug.md"
    if [ -f "$fragment" ] && grep -q '[^[:space:]]' "$fragment" 2>/dev/null; then
        ALL_EMPTY=false
        break
    fi
done

# Assemble body in a tmp file first, then atomic-rename into place.
TMP_OUTPUT="$(mktemp "${OUTPUT}.XXXXXX")" || fail_io "cannot create temp file next to $OUTPUT"
# Clean up tmp on any exit path (success atomic-renames; failure removes stale tmp).
trap 'rm -f "$TMP_OUTPUT"' EXIT

{
    printf '<!-- larch:implement-anchor v1 issue=%s -->\n' "$ISSUE"
    if "$ALL_EMPTY"; then
        printf '%s\n' '_/implement run in progress — sections below populate as the run proceeds._'
    fi
    for slug in "${SECTION_MARKERS[@]}"; do
        fragment="$SECTIONS_DIR/$slug.md"
        printf '<!-- section:%s -->\n' "$slug"
        if [ -f "$fragment" ]; then
            # Fragment content emitted verbatim; caller owns compose-time sanitization.
            # cat preserves trailing-newline semantics as authored by the caller.
            # Fail closed on read error so a permission-denied fragment cannot
            # silently produce an empty section interior (which would clobber
            # populated remote content on upsert).
            cat "$fragment" || fail_io "failed to read fragment: $fragment"
            # Ensure exactly one newline between fragment content and the close
            # marker. If the fragment already ends with a newline, do not add
            # another — command substitution in bash strips trailing newlines,
            # so we cannot use `$(tail -c 1 ...)` to detect it. Instead, use
            # `od -An -to1 | tr -d ' '` which preserves byte identity of the
            # last byte even when it is a newline. Newline = octal 012.
            if [ -s "$fragment" ]; then
                last_oct="$(tail -c 1 "$fragment" 2>/dev/null | od -An -to1 | tr -d ' ')"
                if [ "$last_oct" != "012" ]; then
                    printf '\n'
                fi
            fi
        fi
        printf '<!-- section-end:%s -->\n' "$slug"
    done
} > "$TMP_OUTPUT" || fail_io "failed to write assembled body to $TMP_OUTPUT"

mv -f "$TMP_OUTPUT" "$OUTPUT" || fail_io "failed to move assembled body into $OUTPUT"
# mv succeeded; clear the trap's rm target so the file stays.
trap - EXIT

echo "ASSEMBLED=true"
echo "OUTPUT=$OUTPUT"
exit 0
