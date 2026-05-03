#!/usr/bin/env bash
# token-tally.sh — Per-run token-cost telemetry helper for /research.
#
# Two subcommands:
#   write — record a per-lane token sidecar.
#   report — render the ## Token Spend section to stdout.
#
# Sidecar schema (KEY=value):
#   PHASE=research|validation
#   LANE=<stable slot name>
#   TOOL=claude
#   TOTAL_TOKENS=<integer or "unknown">
#
# Sidecar file naming:
#   $RESEARCH_TMPDIR/lane-tokens-<phase>-<lane>.txt
#
# All --dir values must be under /tmp/ or /private/tmp/ (defense in depth;
# mirrors cleanup-tmpdir.sh's path guard).

set -euo pipefail

usage() {
    cat <<'EOF' >&2
Usage:
  token-tally.sh write --phase <p> --lane <l> --tool <t> --total-tokens <N|unknown> --dir <d>
  token-tally.sh report --dir <d>

  write — write one per-lane sidecar to <d>/lane-tokens-<phase>-<lane>.txt.
  report — emit the ## Token Spend section (header + body) to stdout.

Path validation: --dir MUST be under /tmp/ or /private/tmp/.
EOF
}

validate_dir() {
    local d="$1"
    if [[ -z "$d" ]]; then
        echo "ERROR: --dir is required and must be non-empty" >&2
        return 1
    fi
    # Reject `..` segments outright — they can let a /tmp-prefixed path
    # escape the /tmp tree (e.g. /tmp/../etc passes a naive prefix check
    # but resolves outside /tmp). Defense in depth: the canonicalization
    # below also catches this, but rejecting `..` early gives a clearer
    # error message and prevents the resolved-path branch from doing
    # filesystem work on a hostile input.
    case "/$d/" in
        */../*|*/..*|*../*) echo "ERROR: --dir must not contain '..' segments (got: $d)" >&2; return 1 ;;
    esac
    # String-prefix guard (cheap, catches the obvious cases).
    if [[ "$d" != /tmp/* && "$d" != /private/tmp/* ]]; then
        echo "ERROR: --dir must be under /tmp/ or /private/tmp/ (got: $d)" >&2
        return 1
    fi
    # Canonical-path guard (defense in depth — resolves symlinks, ., ..).
    # The string-prefix check above rejects literal escapes like /home/foo,
    # but a path like /tmp/foo/link/leaf where /tmp/foo/link is a symlink
    # to outside /tmp still passes the string check. Walk to the nearest
    # existing-or-symlink ancestor and require it to canonicalize under
    # /tmp or /private/tmp. Use `cd ... && pwd -P` rather than `realpath`
    # for portability (realpath is not POSIX and missing on some macOS
    # installs without coreutils). This mirrors scripts/deny-edit-write.sh.

    # Canonicalize the allowed roots once. On macOS /tmp -> /private/tmp,
    # so both spellings collapse to one canonical path; on Linux they
    # are typically distinct (and /private/tmp may not exist). Accept
    # paths that resolve under either canonical root.
    local allowed_root_a allowed_root_b=""
    allowed_root_a=$(cd /tmp 2>/dev/null && pwd -P) || {
        echo "ERROR: cannot canonicalize /tmp" >&2
        return 1
    }
    if [[ -d /private/tmp ]]; then
        allowed_root_b=$(cd /private/tmp 2>/dev/null && pwd -P) || true
    fi

    # Walk up from $d to the nearest existing-or-symlink anchor. The
    # `! -L` clause stops at dangling symlinks so the validator surfaces
    # a clear error rather than letting `cd` (or a subsequent mkdir -p)
    # fail later with a confusing message. Note `-e` is true for a
    # symlink only when its target exists, so dangling symlinks would
    # otherwise be silently walked past.
    local probe="$d"
    while [[ ! -e "$probe" && ! -L "$probe" ]] && [[ "$probe" != "/" ]]; do
        probe=$(dirname "$probe")
    done
    if [[ "$probe" == "/" ]]; then
        echo "ERROR: --dir has no existing ancestor: $d" >&2
        return 1
    fi
    # A regular file (or symlink-to-file) is not a directory; reject
    # with a clear error rather than silently taking dirname.
    if [[ -f "$probe" ]]; then
        echo "ERROR: --dir nearest existing ancestor is not a directory: $probe" >&2
        return 1
    fi

    # Canonicalize the probe directory. Symlinks anywhere on the chain
    # are resolved here — this is the load-bearing security check. A
    # dangling-symlink probe makes `cd` fail; treat that as a hard error.
    local resolved
    resolved=$(cd "$probe" 2>/dev/null && pwd -P) || {
        echo "ERROR: cannot resolve --dir: $d" >&2
        return 1
    }

    # Accept iff resolved anchor matches either canonical root.
    if [[ "$resolved" == "$allowed_root_a" ]] || [[ "$resolved" == "$allowed_root_a"/* ]]; then
        return 0
    fi
    if [[ -n "$allowed_root_b" ]] && { [[ "$resolved" == "$allowed_root_b" ]] || [[ "$resolved" == "$allowed_root_b"/* ]]; }; then
        return 0
    fi
    echo "ERROR: --dir resolves outside /tmp/ (resolved: $resolved)" >&2
    return 1
}

# Sanitize a lane label: lowercase, non-alphanumerics → '-'.
safe_lane() {
    printf '%s' "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9]/-/g'
}

cmd_write() {
    local phase="" lane="" tool="" total="" dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --phase)        phase="${2:?--phase requires a value}"; shift 2 ;;
            --lane)         lane="${2:?--lane requires a value}"; shift 2 ;;
            --tool)         tool="${2:?--tool requires a value}"; shift 2 ;;
            --total-tokens) total="${2:?--total-tokens requires a value}"; shift 2 ;;
            --dir)          dir="${2:?--dir requires a value}"; shift 2 ;;
            *) echo "ERROR: unknown flag for write: $1" >&2; return 1 ;;
        esac
    done

    [[ -n "$phase" && -n "$lane" && -n "$tool" && -n "$total" && -n "$dir" ]] || {
        echo "ERROR: write requires --phase --lane --tool --total-tokens --dir" >&2
        return 1
    }

    case "$phase" in
        research|validation) ;;
        *) echo "ERROR: --phase must be one of research|validation (got: $phase)" >&2; return 1 ;;
    esac

    # TOTAL_TOKENS must be a non-negative integer OR the literal "unknown".
    if [[ "$total" != "unknown" && ! "$total" =~ ^[0-9]+$ ]]; then
        echo "ERROR: --total-tokens must be a non-negative integer or 'unknown' (got: $total)" >&2
        return 1
    fi

    validate_dir "$dir" || return 1
    mkdir -p "$dir"

    local safe sidecar
    safe="$(safe_lane "$lane")"
    sidecar="$dir/lane-tokens-$phase-$safe.txt"

    cat > "$sidecar" <<EOF
PHASE=$phase
LANE=$lane
TOOL=$tool
TOTAL_TOKENS=$total
EOF
}

cmd_report() {
    local dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir) dir="${2:?--dir requires a value}"; shift 2 ;;
            *) echo "ERROR: unknown flag for report: $1" >&2; return 1 ;;
        esac
    done

    [[ -n "$dir" ]] || {
        echo "ERROR: report requires --dir" >&2
        return 1
    }

    validate_dir "$dir" || return 1

    if [[ ! -d "$dir" ]]; then
        echo "## Token Spend (Claude tokens only; external lanes excluded)"
        echo
        echo "_(token telemetry unavailable: \$RESEARCH_TMPDIR was already removed)_"
        return 0
    fi

    # Read sidecars: parse PHASE / LANE / TOTAL_TOKENS.
    # Aggregate by phase. Track measured-count vs total-lane-count per phase.
    local research_total=0 research_measured=0 research_unknown=0 research_lanes=()
    local validation_total=0 validation_measured=0 validation_unknown=0 validation_lanes=()

    shopt -s nullglob
    local f
    for f in "$dir"/lane-tokens-*.txt; do
        local p="" l="" t=""
        local line
        while IFS= read -r line; do
            # Split on first '=' only — values may contain '=' defensively.
            local k="${line%%=*}"
            local v="${line#*=}"
            case "$k" in
                PHASE) p="$v" ;;
                LANE) l="$v" ;;
                TOTAL_TOKENS) t="$v" ;;
            esac
        done < "$f"

        [[ -n "$p" && -n "$l" ]] || continue

        case "$p" in
            research)
                research_lanes+=("$l")
                if [[ "$t" =~ ^[0-9]+$ ]]; then
                    research_total=$(( research_total + t ))
                    research_measured=$(( research_measured + 1 ))
                else
                    research_unknown=$(( research_unknown + 1 ))
                fi
                ;;
            validation)
                validation_lanes+=("$l")
                if [[ "$t" =~ ^[0-9]+$ ]]; then
                    validation_total=$(( validation_total + t ))
                    validation_measured=$(( validation_measured + 1 ))
                else
                    validation_unknown=$(( validation_unknown + 1 ))
                fi
                ;;
        esac
    done
    shopt -u nullglob

    local grand_total=$(( research_total + validation_total ))
    local total_lane_count=$(( ${#research_lanes[@]} + ${#validation_lanes[@]} ))

    # Optional cost column when LARCH_TOKEN_RATE_PER_M is a positive number.
    # Zero is treated as unset (per scripts/token-tally.md and
    # docs/configuration-and-permissions.md — "When unset, malformed, or
    # zero, the $ column is omitted entirely").
    local rate="" cost_supported=false
    if [[ -n "${LARCH_TOKEN_RATE_PER_M:-}" ]] \
       && [[ "${LARCH_TOKEN_RATE_PER_M}" =~ ^[0-9]+([.][0-9]+)?$ ]] \
       && awk -v r="${LARCH_TOKEN_RATE_PER_M}" 'BEGIN { exit (r > 0) ? 0 : 1 }'; then
        rate="${LARCH_TOKEN_RATE_PER_M}"
        cost_supported=true
    fi

    # Render report
    echo "## Token Spend (Claude tokens only; external lanes excluded)"
    echo

    if [[ "$total_lane_count" -eq 0 ]]; then
        echo "_(no measurements available — Claude inline only, no measurable subagent invocations)_"
        return 0
    fi

    fmt_phase_row() {
        local label="$1"
        local total="$2"
        local measured="$3"
        local unknown="$4"
        local lane_count=$(( measured + unknown ))
        local cost_str=""
        if [[ "$cost_supported" == "true" ]] && [[ "$total" -gt 0 ]]; then
            # Cost in dollars using awk for floating-point: (total * rate) / 1_000_000.
            # Rate is USD per million tokens (LARCH_TOKEN_RATE_PER_M).
            cost_str=$(awk -v tot="$total" -v rt="$rate" 'BEGIN { printf "  $%.4f", (tot * rt) / 1000000 }')
        fi
        local coverage=""
        if [[ "$unknown" -gt 0 ]]; then
            coverage=" ($lane_count lanes, $measured measured, $unknown unmeasurable)"
        else
            coverage=" ($lane_count lanes, $measured measured)"
        fi
        printf '  %-22s%s: total=%s%s\n' "$label" "$coverage" "$total" "$cost_str"
    }

    # Research phase row — fixed shape: 4 Codev-first lanes (architecture/
    # edge cases/external comparisons/security) with per-lane Claude
    # fallback. Always render the row when sidecars exist; otherwise emit
    # an explicit "not measured" line so the operator sees the phase ran.
    if [[ ${#research_lanes[@]} -gt 0 ]]; then
        fmt_phase_row "Research phase" "$research_total" "$research_measured" "$research_unknown"
    else
        echo "  Research phase         (4 lanes — Codex-first with per-lane Claude fallback): not measured"
    fi
    # Validation phase row — fixed shape: 3 reviewers (Code|Cursor|Codex).
    if [[ ${#validation_lanes[@]} -gt 0 ]]; then
        fmt_phase_row "Validation phase" "$validation_total" "$validation_measured" "$validation_unknown"
    else
        echo "  Validation phase       (3 reviewers — Code|Cursor|Codex): not measured"
    fi

    # Total row
    local total_measured=$(( research_measured + validation_measured ))
    local total_unknown=$(( research_unknown + validation_unknown ))
    local total_lanes=$(( total_measured + total_unknown ))
    local cost_str=""
    if [[ "$cost_supported" == "true" ]] && [[ "$grand_total" -gt 0 ]]; then
        cost_str=$(awk -v tot="$grand_total" -v rt="$rate" 'BEGIN { printf "  $%.4f", (tot * rt) / 1000000 }')
    fi
    if [[ "$total_unknown" -gt 0 ]]; then
        printf '  %-22s (%s lanes, %s measured, %s unmeasurable): total=%s%s\n' "Total" "$total_lanes" "$total_measured" "$total_unknown" "$grand_total" "$cost_str"
    else
        printf '  %-22s (%s lanes, %s measured): total=%s%s\n' "Total" "$total_lanes" "$total_measured" "$grand_total" "$cost_str"
    fi

    echo
    echo "_Note: only Claude subagent (Agent-tool) invocations report token counts. Claude inline (orchestrator) and external lanes (Cursor/Codex) are excluded from the totals above._"
}

# Main dispatch
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    write)        shift; cmd_write "$@" ;;
    report)       shift; cmd_report "$@" ;;
    --help|-h)    usage; exit 0 ;;
    *)            echo "ERROR: unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
