# shellcheck shell=bash
# lib-loop-improve-halt-ledger.sh — sourced-only helper
#
# Provides classify_halt_location which scans a /loop-improve-skill LOOP_TMPDIR
# for per-substep sentinel files and emits KV classification on stdout.
#
# Canonical-source sync: the LAST_COMPLETED token taxonomy and the byte-preserved
# HALT_LOCATION_CLAUSE strings are owned by the clause_for_last_completed()
# function below — this library is the canonical taxonomy source (the prior
# mapping table in skills/loop-improve-skill/SKILL.md §#247 no longer exists;
# the outer skill was rewritten as scripts/driver.sh under #273). Any change
# to the taxonomy MUST be paired with updates to:
#   - scripts/test-lib-loop-improve-halt-ledger.sh (this lib's regression harness)
#
# This library is sourced only; it has no shebang and must not be executed
# directly. Consumers:
#   - scripts/test-loop-improve-skill-halt-rate.sh (halt-rate probe)

# clause_for_last_completed <token>
#
# Emits the exact canonical HALT_LOCATION_CLAUSE string for a given
# LAST_COMPLETED token (stdout, no newline suffix). Shared between
# classify_halt_location (sentinel-ledger scan path) and the halt-rate
# probe's log-parsing path (halt_detected_by_outer classification) so
# the two paths cannot drift.
clause_for_last_completed() {
    case "$1" in
        done)           printf '%s' 'completed iteration' ;;
        3j)             printf '%s' 'halted at or before grade parse at 3.j.v' ;;
        3jv)            printf '%s' 'halted at or before /design at 3.d' ;;
        3d-pre-detect)  printf '%s' 'halted during no-plan detector or before rescue at 3.d' ;;
        3d-post-detect) printf '%s' 'halted at or before plan-post at 3.d' ;;
        3d-plan-post)   printf '%s' 'halted at or before /im at 3.i' ;;
        3i)             printf '%s' 'halted between 3.i verify and Step 4 close-out' ;;
        none|*)         printf '%s' 'halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)' ;;
    esac
}

# classify_halt_location <LOOP_TMPDIR>
#
# Iteration-agnostic: finds the highest ITER among any iter-<N>-*.done files
# (or iter-<N>-done.sentinel), then returns the halt-location classification
# for that iteration.
#
# Emits on stdout (always exit 0):
#   ITER=<N|none>
#   LAST_COMPLETED=<none|3j|3jv|3d-pre-detect|3d-post-detect|3d-plan-post|3i|done>
#   HALT_LOCATION_CLAUSE=<exact canonical string>
classify_halt_location() {
    local loop_tmpdir="${1:-}"

    if [[ -z "$loop_tmpdir" || ! -d "$loop_tmpdir" ]]; then
        printf 'ITER=none\nLAST_COMPLETED=none\nHALT_LOCATION_CLAUSE=%s\n' \
            'halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)'
        return 0
    fi

    # Find highest ITER among sentinel files. Probe iter-N-done.sentinel,
    # iter-N-3j.done, ..., iter-N-3i.done — the union of all per-substep names.
    local highest_iter=""
    local f name iter
    for f in "$loop_tmpdir"/iter-*-done.sentinel "$loop_tmpdir"/iter-*-3j.done \
             "$loop_tmpdir"/iter-*-3jv.done "$loop_tmpdir"/iter-*-3d-pre-detect.done \
             "$loop_tmpdir"/iter-*-3d-post-detect.done "$loop_tmpdir"/iter-*-3d-plan-post.done \
             "$loop_tmpdir"/iter-*-3i.done; do
        [[ -e "$f" ]] || continue
        name="${f##*/}"
        # Extract N from iter-N-... — strip "iter-" prefix, then everything from first "-" after the digit block
        iter="${name#iter-}"
        iter="${iter%%-*}"
        # Validate iter is a positive integer
        [[ "$iter" =~ ^[0-9]+$ ]] || continue
        if [[ -z "$highest_iter" ]] || (( iter > highest_iter )); then
            highest_iter="$iter"
        fi
    done

    if [[ -z "$highest_iter" ]]; then
        printf 'ITER=none\nLAST_COMPLETED=none\nHALT_LOCATION_CLAUSE=%s\n' \
            'halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)'
        return 0
    fi

    # For the highest observed iter, check completion sentinel first.
    if [[ -s "$loop_tmpdir/iter-${highest_iter}-done.sentinel" ]]; then
        printf 'ITER=%s\nLAST_COMPLETED=done\nHALT_LOCATION_CLAUSE=%s\n' \
            "$highest_iter" 'completed iteration'
        return 0
    fi

    # Scan per-substep sentinels in canonical order (low to high). Highest-rank
    # non-empty sentinel identifies the last-completed substep.
    local last_completed="none"
    local s
    for s in 3j 3jv 3d-pre-detect 3d-post-detect 3d-plan-post 3i; do
        if [[ -s "$loop_tmpdir/iter-${highest_iter}-${s}.done" ]]; then
            last_completed="$s"
        fi
    done

    local clause
    clause=$(clause_for_last_completed "$last_completed")

    printf 'ITER=%s\nLAST_COMPLETED=%s\nHALT_LOCATION_CLAUSE=%s\n' \
        "$highest_iter" "$last_completed" "$clause"
    return 0
}
