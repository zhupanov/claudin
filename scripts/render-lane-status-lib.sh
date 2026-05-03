# shellcheck shell=bash
# render-lane-status-lib.sh — shared rendering primitives for the per-lane
# attribution helper (`render-lane-status.sh`). This file is sourced, not
# executed (no shebang, no top-level state-mutating commands).
#
# Exported functions:
#   sanitize_reason  — collapse whitespace, strip = and |, trim, truncate to 80
#   render_lane      — map a (status_token, reason) pair to the rendered string
#
# Both functions use `local` vars only and do not change shell options;
# callers may run under `set -euo pipefail` without interference.
#
# Status token vocabulary (canonical, single source of truth):
#   ok                            → ✅
#   fallback_binary_missing       → Claude-fallback (binary missing)
#   fallback_probe_failed         → Claude-fallback (probe failed: <reason>)
#                                   (parenthetical omitted when REASON is empty)
#   fallback_runtime_timeout      → Claude-fallback (runtime timeout)
#   fallback_runtime_failed       → Claude-fallback (runtime failed: <reason>)
#                                   (parenthetical omitted when REASON is empty)
#   '' (missing or empty)         → (unknown)   (no stderr warning)
#   <anything else, non-empty>    → (unknown)   + stderr warning
#
# Reason sanitization rules (in order):
#   1. Strip embedded `=` and `|` characters
#   2. Collapse all whitespace runs (incl. \n, \t, \r) into single spaces
#   3. Trim leading/trailing whitespace
#   4. Truncate to 80 characters
#
# Edit-in-sync: changes to the case statement in `render_lane()` or to
# `sanitize_reason()` MUST be paired with updates to:
#   - scripts/render-lane-status-lib.md (this contract)
#   - scripts/render-lane-status.md (consumer contract)
#   - scripts/test-render-lane-status.sh (byte-exact harness)

# sanitize_reason — collapse whitespace, strip = and |, trim, truncate to 80.
# Defense-in-depth: the writer is supposed to sanitize before heredoc-write,
# but we apply the same rules here so a misformed file never breaks markdown.
sanitize_reason() {
    local s="$1"
    # Strip embedded = and | characters first (stripping can create new
    # whitespace gaps; the subsequent collapse pass merges them).
    s="${s//=/}"
    s="${s//|/}"
    # Collapse all whitespace runs (incl. tabs, newlines, CRs) to single space.
    s="$(printf '%s' "$s" | tr -s '[:space:]' ' ')"
    # Trim leading/trailing whitespace.
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    # Truncate to 80 characters.
    if [ "${#s}" -gt 80 ]; then
        s="${s:0:80}"
    fi
    printf '%s' "$s"
}

# render_lane — given a status token and a (possibly empty) reason, emit the
# human-readable string. Emits a stderr warning for unknown tokens.
render_lane() {
    local status="$1"
    local reason="$2"
    local clean
    clean="$(sanitize_reason "$reason")"
    case "$status" in
        ok)
            printf '✅' ;;
        fallback_binary_missing)
            printf 'Claude-fallback (binary missing)' ;;
        fallback_probe_failed)
            if [ -n "$clean" ]; then
                printf 'Claude-fallback (probe failed: %s)' "$clean"
            else
                printf 'Claude-fallback (probe failed)'
            fi ;;
        fallback_runtime_timeout)
            printf 'Claude-fallback (runtime timeout)' ;;
        fallback_runtime_failed)
            if [ -n "$clean" ]; then
                printf 'Claude-fallback (runtime failed: %s)' "$clean"
            else
                printf 'Claude-fallback (runtime failed)'
            fi ;;
        '')
            printf '(unknown)' ;;
        *)
            echo "**⚠ render-lane-status: unknown status token $status**" >&2
            printf '(unknown)' ;;
    esac
}
