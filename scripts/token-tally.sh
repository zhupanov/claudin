#!/usr/bin/env bash
# token-tally.sh — Per-run token-cost telemetry helper for /research.
#
# Three subcommands:
#   write — record a per-lane token sidecar.
#   report — render the ## Token Spend section to stdout.
#   check-budget — sum measured tokens; exit 2 if over budget.
#
# Sidecar schema (KEY=value):
#   PHASE=research|validation|adjudication
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
  token-tally.sh report --dir <d> --scale <quick|standard|deep> --adjudicate <true|false>
                        [--planner true|false] [--budget-aborted true|false]
  token-tally.sh check-budget --budget <N> --dir <d>

  write — write one per-lane sidecar to <d>/lane-tokens-<phase>-<lane>.txt.
  report — emit the ## Token Spend section (header + body) to stdout.
  check-budget — sum measured TOTAL_TOKENS; exit 0 if <=, exit 2 if over.

Path validation: --dir MUST be under /tmp/ or /private/tmp/.
EOF
}

validate_dir() {
    local d="$1"
    if [[ -z "$d" ]]; then
        echo "ERROR: --dir is required and must be non-empty" >&2
        return 1
    fi
    if [[ "$d" != /tmp/* && "$d" != /private/tmp/* ]]; then
        echo "ERROR: --dir must be under /tmp/ (got: $d)" >&2
        return 1
    fi
    return 0
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
        research|validation|adjudication) ;;
        *) echo "ERROR: --phase must be one of research|validation|adjudication (got: $phase)" >&2; return 1 ;;
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
    local dir="" scale="" adjudicate="" planner="false" aborted="false"
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dir)             dir="${2:?--dir requires a value}"; shift 2 ;;
            --scale)           scale="${2:?--scale requires a value}"; shift 2 ;;
            --adjudicate)      adjudicate="${2:?--adjudicate requires a value}"; shift 2 ;;
            --planner)         planner="${2:?--planner requires a value}"; shift 2 ;;
            --budget-aborted)  aborted="${2:?--budget-aborted requires a value}"; shift 2 ;;
            *) echo "ERROR: unknown flag for report: $1" >&2; return 1 ;;
        esac
    done

    [[ -n "$dir" && -n "$scale" && -n "$adjudicate" ]] || {
        echo "ERROR: report requires --dir --scale --adjudicate" >&2
        return 1
    }

    validate_dir "$dir" || return 1

    if [[ ! -d "$dir" ]]; then
        echo "## Token Spend"
        echo
        echo "_(token telemetry unavailable: \$RESEARCH_TMPDIR was already removed)_"
        if [[ "$aborted" == "true" ]]; then
            echo
            echo "**Run aborted: --token-budget exceeded.**"
        fi
        return 0
    fi

    # Read sidecars: parse PHASE / LANE / TOTAL_TOKENS.
    # Aggregate by phase. Track measured-count vs total-lane-count per phase.
    local research_total=0 research_measured=0 research_unknown=0 research_lanes=()
    local validation_total=0 validation_measured=0 validation_unknown=0 validation_lanes=()
    local adjudication_total=0 adjudication_measured=0 adjudication_unknown=0 adjudication_lanes=()

    shopt -s nullglob
    local f
    for f in "$dir"/lane-tokens-*.txt; do
        local p="" l="" t=""
        while IFS='=' read -r k v; do
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
            adjudication)
                adjudication_lanes+=("$l")
                if [[ "$t" =~ ^[0-9]+$ ]]; then
                    adjudication_total=$(( adjudication_total + t ))
                    adjudication_measured=$(( adjudication_measured + 1 ))
                else
                    adjudication_unknown=$(( adjudication_unknown + 1 ))
                fi
                ;;
        esac
    done
    shopt -u nullglob

    local grand_total=$(( research_total + validation_total + adjudication_total ))
    local total_lane_count=$(( ${#research_lanes[@]} + ${#validation_lanes[@]} + ${#adjudication_lanes[@]} ))

    # Optional cost column when LARCH_TOKEN_RATE_PER_M is a positive number.
    local rate="" cost_supported=false
    if [[ -n "${LARCH_TOKEN_RATE_PER_M:-}" ]] && [[ "${LARCH_TOKEN_RATE_PER_M}" =~ ^[0-9]+([.][0-9]+)?$ ]]; then
        rate="${LARCH_TOKEN_RATE_PER_M}"
        cost_supported=true
    fi

    # Render report
    echo "## Token Spend (Claude tokens only; external lanes excluded)"
    echo

    if [[ "$total_lane_count" -eq 0 ]]; then
        echo "_(no measurements available — Claude inline only, no measurable subagent invocations)_"
        if [[ "$aborted" == "true" ]]; then
            echo
            echo "**Run aborted: --token-budget exceeded.**"
        fi
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
            # Cost in cents using awk for floating-point: (total * rate) / 1_000_000
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

    if [[ ${#research_lanes[@]} -gt 0 ]]; then
        fmt_phase_row "Research phase" "$research_total" "$research_measured" "$research_unknown"
        # When --planner=true was set but no planner sidecar exists, surface this so
        # the operator notices that planner spend was not captured (helps detect
        # missing token-tally write hooks in references/research-phase.md §1.1.b).
        if [[ "$planner" == "true" ]]; then
            local saw_planner=false
            local lane
            for lane in "${research_lanes[@]}"; do
                if [[ "$lane" == "planner" ]]; then
                    saw_planner=true
                    break
                fi
            done
            if [[ "$saw_planner" == "false" ]]; then
                echo "    _(--plan was set but no planner sidecar found; planner spend was not measured)_"
            fi
        fi
    elif [[ "$scale" == "quick" ]]; then
        echo "  Research phase         (1 lane — Claude inline only): not measured"
    fi
    if [[ ${#validation_lanes[@]} -gt 0 ]]; then
        fmt_phase_row "Validation phase" "$validation_total" "$validation_measured" "$validation_unknown"
    elif [[ "$scale" == "quick" ]]; then
        echo "  Validation phase       (skipped in --scale=quick): -"
    fi
    if [[ "$adjudicate" == "true" ]]; then
        if [[ ${#adjudication_lanes[@]} -gt 0 ]]; then
            fmt_phase_row "Adjudication" "$adjudication_total" "$adjudication_measured" "$adjudication_unknown"
        else
            echo "  Adjudication           (no rejections to adjudicate): -"
        fi
    else
        echo "  Adjudication           (--adjudicate not set): skipped"
    fi

    # Total row
    local total_measured=$(( research_measured + validation_measured + adjudication_measured ))
    local total_unknown=$(( research_unknown + validation_unknown + adjudication_unknown ))
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

    if [[ "$aborted" == "true" ]]; then
        echo
        echo "**Run aborted: --token-budget exceeded.**"
    fi
}

cmd_check_budget() {
    local budget="" dir=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --budget) budget="${2:?--budget requires a value}"; shift 2 ;;
            --dir)    dir="${2:?--dir requires a value}"; shift 2 ;;
            *) echo "ERROR: unknown flag for check-budget: $1" >&2; return 1 ;;
        esac
    done

    [[ -n "$budget" && -n "$dir" ]] || {
        echo "ERROR: check-budget requires --budget --dir" >&2
        return 1
    }

    if [[ ! "$budget" =~ ^[0-9]+$ ]] || [[ "$budget" -le 0 ]]; then
        echo "ERROR: --budget must be a positive integer (got: $budget)" >&2
        return 1
    fi

    validate_dir "$dir" || return 1

    if [[ ! -d "$dir" ]]; then
        # No tmpdir → no measurements → cannot have exceeded budget.
        echo "BUDGET_EXCEEDED=false MEASURED=0 UNKNOWN_LANES=0"
        return 0
    fi

    local measured=0 unknown_count=0
    shopt -s nullglob
    local f
    for f in "$dir"/lane-tokens-*.txt; do
        local t=""
        while IFS='=' read -r k v; do
            case "$k" in
                TOTAL_TOKENS) t="$v" ;;
            esac
        done < "$f"
        if [[ "$t" =~ ^[0-9]+$ ]]; then
            measured=$(( measured + t ))
        else
            unknown_count=$(( unknown_count + 1 ))
        fi
    done
    shopt -u nullglob

    if [[ "$measured" -gt "$budget" ]]; then
        echo "BUDGET_EXCEEDED=true MEASURED=$measured UNKNOWN_LANES=$unknown_count BUDGET=$budget"
        return 2
    fi
    echo "BUDGET_EXCEEDED=false MEASURED=$measured UNKNOWN_LANES=$unknown_count BUDGET=$budget"
    return 0
}

# Main dispatch
if [[ $# -lt 1 ]]; then
    usage
    exit 1
fi

case "$1" in
    write)        shift; cmd_write "$@" ;;
    report)       shift; cmd_report "$@" ;;
    check-budget) shift; cmd_check_budget "$@" ;;
    --help|-h)    usage; exit 0 ;;
    *)            echo "ERROR: unknown subcommand: $1" >&2; usage; exit 1 ;;
esac
