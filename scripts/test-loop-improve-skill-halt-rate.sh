#!/usr/bin/env bash
#
# Halt-rate regression harness for /larch:loop-improve-skill (closes #278).
#
# Invokes `claude -p "/larch:loop-improve-skill <fixture>"` N times against a
# throwaway fixture skill, measures how often the outer loop halts mid-turn
# (the halt-of-interest from #273), and emits HALT_RATE on stdout.
#
# Classification is primarily log-parsed (outer's stdout markers); filesystem
# sentinels are used only as forensic secondary for halt_mid_turn runs where
# the outer's Step 6 cleanup never ran.
#
# Contract tokens (consumed by CI/ad-hoc automation; see README):
#   HALT_RATE=<halted>/<total>
#   PROBE_STATUS=ok|skipped_no_claude|error
#   PER_STATUS_BREAKDOWN: ...
#   PER_LOCATION_BREAKDOWN: ...
#   RUN <i>: status=<...> last_completed=<token> clause="<clause>" elapsed=<s>s
#
# Exit codes:
#   0 — measurement succeeded (any halt rate is signal, not error).
#   1 — preflight or environment failure (missing claude, missing timeout,
#       no harness repo root, bad flag).
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: test-loop-improve-skill-halt-rate.sh [--runs N] [--timeout-per-run SEC] [--keep-tmpdirs]

Flags:
  --runs N              Number of sequential end-to-end runs (default: 5).
  --timeout-per-run SEC Per-run wall-clock bound (default: 1800s = 30min).
  --keep-tmpdirs        Skip per-run scratch cleanup for forensics.
  -h, --help            Print this help.
EOF
}

# Default flags
RUNS=5
TIMEOUT_SEC=1800
KEEP_TMPDIRS=0

while (( $# > 0 )); do
    case "$1" in
        --runs)
            RUNS="${2:?--runs requires a value}"; shift 2 ;;
        --timeout-per-run)
            TIMEOUT_SEC="${2:?--timeout-per-run requires a value}"; shift 2 ;;
        --keep-tmpdirs)
            KEEP_TMPDIRS=1; shift ;;
        -h|--help)
            usage; exit 0 ;;
        *)
            echo "**⚠ unknown flag: $1**" >&2
            usage >&2
            exit 1 ;;
    esac
done

if ! [[ "$RUNS" =~ ^[1-9][0-9]*$ ]]; then
    echo "**⚠ --runs must be a positive integer (got: $RUNS)**" >&2
    exit 1
fi
if ! [[ "$TIMEOUT_SEC" =~ ^[1-9][0-9]*$ ]]; then
    echo "**⚠ --timeout-per-run must be a positive integer (got: $TIMEOUT_SEC)**" >&2
    exit 1
fi

# Preflight — claude binary
if ! command -v claude >/dev/null 2>&1; then
    echo "**⚠ claude binary not found on PATH — this harness requires Claude Code CLI (see https://claude.com/claude-code). Install claude, then retry.**" >&2
    printf 'HALT_RATE=0/0\nPROBE_STATUS=skipped_no_claude\n'
    exit 1
fi

# Preflight — timeout (GNU coreutils). On macOS, gtimeout (from brew coreutils).
TIMEOUT_CMD=""
if command -v timeout >/dev/null 2>&1 && timeout --help 2>&1 | grep -q kill-after; then
    TIMEOUT_CMD="timeout"
elif command -v gtimeout >/dev/null 2>&1 && gtimeout --help 2>&1 | grep -q kill-after; then
    TIMEOUT_CMD="gtimeout"
else
    echo "**⚠ neither 'timeout' nor 'gtimeout' with --kill-after support was found. Install GNU coreutils (macOS: brew install coreutils).**" >&2
    printf 'HALT_RATE=0/0\nPROBE_STATUS=error\n'
    exit 1
fi

# Resolve LARCH_ROOT (this plugin's source tree) BEFORE any cd.
# The harness script lives at <LARCH_ROOT>/scripts/test-loop-improve-skill-halt-rate.sh.
HARNESS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LARCH_ROOT="$(cd "$HARNESS_DIR/.." && pwd -P)"
if [[ ! -d "$LARCH_ROOT/skills/loop-improve-skill" ]]; then
    echo "**⚠ LARCH_ROOT=$LARCH_ROOT does not contain skills/loop-improve-skill — harness must be run from its source tree.**" >&2
    printf 'HALT_RATE=0/0\nPROBE_STATUS=error\n'
    exit 1
fi

# Source the halt-ledger helper.
# shellcheck source=scripts/lib-loop-improve-halt-ledger.sh
source "$LARCH_ROOT/scripts/lib-loop-improve-halt-ledger.sh"

FIXTURE_SRC="$LARCH_ROOT/tests/fixtures/loop-halt-rate/SKILL.md"
if [[ ! -f "$FIXTURE_SRC" ]]; then
    echo "**⚠ fixture not found at $FIXTURE_SRC**" >&2
    printf 'HALT_RATE=0/0\nPROBE_STATUS=error\n'
    exit 1
fi

# Emit a small gh stub into a given bin dir. Minimal: accepts any subcommand,
# logs subcommand + arg count to GH_STUB_LOG, emits a generic line on stdout.
# Deliberately does NOT reproduce full gh pr/issue contract — /im's gh-dependent
# path will fail, producing ITER_STATUS=im_verification_failed which the outer
# surfaces via EXIT_REASON; harness classifies that as completed_by_outer (NOT
# the halt-of-interest, which fires much earlier at /skill-judge return).
emit_gh_stub() {
    local bindir="$1"
    mkdir -p "$bindir"
    cat > "$bindir/gh" <<'STUBEOF'
#!/usr/bin/env bash
# Halt-rate harness gh stub. Logs call count and subcommand only; does not capture argv.
: "${GH_STUB_LOG:=/dev/null}"
sub="${1:-none}"; argc=$#
echo "[$(date -u +%FT%TZ)] gh $sub argc=$argc" >> "$GH_STUB_LOG"
case "$sub" in
    issue)
        case "${2:-}" in
            create) echo "https://github.com/stub/repo/issues/999" ;;
            comment|close|edit|reopen|view) echo "stub-ok" ;;
            list) echo "[]" ;;
            *) echo "stub-ok" ;;
        esac ;;
    pr)
        # /im may call gh pr * — emit enough to keep things moving; specifics
        # may not match create-pr.sh / ci-status.sh / merge-pr.sh parsers, and
        # that is intentional (we accept /im failing; see README).
        echo "stub-ok" ;;
    auth)
        echo "Logged in to github.com as stub-user (stub)" ;;
    repo)
        echo '{"name":"stub"}' ;;
    api)
        echo '{}' ;;
    *)
        echo "stub-ok" ;;
esac
exit 0
STUBEOF
    chmod +x "$bindir/gh"
}

# Per-status and per-location counters
status_completed=0
status_halt_mid_turn=0
status_halt_detected=0
status_timeout=0
status_tool_failure=0
status_error=0
loc_done=0
loc_3i=0
loc_3d_plan_post=0
loc_3d_post_detect=0
loc_3d_pre_detect=0
loc_3jv=0
loc_3j=0
loc_none=0

# Maintain a cleanup list of scratch dirs
declare -a scratch_dirs
# shellcheck disable=SC2317  # invoked via EXIT trap
cleanup_all() {
    if (( KEEP_TMPDIRS == 1 )); then
        return 0
    fi
    local d
    for d in "${scratch_dirs[@]-}"; do
        [[ -z "${d:-}" ]] && continue
        [[ -d "$d" ]] && rm -rf "$d"
    done
}
trap cleanup_all EXIT

# Log-classification helper: writes three lines to stdout — status, last_completed, clause.
classify_run() {
    local run_log="$1" wrapper_exit="$2" loop_tmpdir="$3"

    # timeout exit codes: 124 = TERM timeout; 137 = SIGKILL after --kill-after grace (128+9).
    if [[ "$wrapper_exit" == "124" || "$wrapper_exit" == "137" ]]; then
        if [[ -n "$loop_tmpdir" && -d "$loop_tmpdir" ]]; then
            local ledger_out last_c clause
            ledger_out=$(classify_halt_location "$loop_tmpdir")
            last_c=$(printf '%s\n' "$ledger_out" | sed -n 's/^LAST_COMPLETED=//p' | head -1)
            clause=$(printf '%s\n' "$ledger_out" | sed -n 's/^HALT_LOCATION_CLAUSE=//p' | head -1)
            printf 'STATUS=timeout\nLAST_COMPLETED=%s\nCLAUSE=%s\n' "${last_c:-none}" "${clause:-timeout_before_start}"
        else
            printf 'STATUS=timeout\nLAST_COMPLETED=none\nCLAUSE=timeout_before_start\n'
        fi
        return 0
    fi

    if [[ -z "$loop_tmpdir" ]]; then
        # Distinguish infrastructure error (no loop tmpdir emitted) from model halt.
        # If wrapper exited non-zero AND no LOOP_TMPDIR, treat as tool_failure
        # (neither a halt nor a measurement).
        if [[ "$wrapper_exit" != "0" ]]; then
            printf 'STATUS=tool_failure\nLAST_COMPLETED=none\nCLAUSE=claude_exit_%s_no_loop_tmpdir\n' "$wrapper_exit"
        else
            printf 'STATUS=error\nLAST_COMPLETED=none\nCLAUSE=no_loop_tmpdir\n'
        fi
        return 0
    fi

    # Parse outer's Step 5 close-out breadcrumb (authoritative progress line):
    #   ✅ 5: close out — issue #<N>, exit: <EXIT_REASON value>
    # Also fall back to the closeout-body.md preamble "Loop finished. Iterations
    # run: <N>. Exit reason: <...>." which claude -p's Bash-tool stdout captures.
    local exit_reason_value=""
    exit_reason_value=$(grep -oE '✅ 5: close out — issue #[0-9]+, exit: .*' "$run_log" 2>/dev/null | tail -1 | sed -E 's/^.*exit: //' || true)
    if [[ -z "$exit_reason_value" ]]; then
        exit_reason_value=$(grep -oE 'Loop finished\. Iterations run: [0-9]+\. Exit reason: .*' "$run_log" 2>/dev/null | tail -1 | sed -E 's/^.*Exit reason: //' | sed -E 's/\.$//' || true)
    fi

    if [[ -n "$exit_reason_value" ]]; then
        if printf '%s' "$exit_reason_value" | grep -q 'iteration sentinel missing'; then
            # Outer caught the halt. Extract last-completed from the diagnostic.
            local lc clause
            lc=$(printf '%s' "$exit_reason_value" | grep -oE 'last-completed=[A-Za-z0-9-]+' | tail -1 | cut -d= -f2)
            if [[ -z "$lc" ]]; then lc="none"; fi
            clause=$(clause_for_last_completed "$lc")
            printf 'STATUS=halt_detected_by_outer\nLAST_COMPLETED=%s\nCLAUSE=%s\n' "$lc" "$clause"
        else
            # Normal loop exit (grade A, max iters, infeasibility, etc.)
            printf 'STATUS=completed_by_outer\nLAST_COMPLETED=done\nCLAUSE=completed iteration\n'
        fi
        return 0
    fi

    # No close-out line found and non-timeout exit → outer itself halted before
    # reaching Step 5. Scan LOOP_TMPDIR (which survives since Step 6 cleanup
    # never ran) for sentinel forensics.
    if [[ -d "$loop_tmpdir" ]]; then
        local ledger_out last_c clause
        ledger_out=$(classify_halt_location "$loop_tmpdir")
        last_c=$(printf '%s\n' "$ledger_out" | sed -n 's/^LAST_COMPLETED=//p' | head -1)
        clause=$(printf '%s\n' "$ledger_out" | sed -n 's/^HALT_LOCATION_CLAUSE=//p' | head -1)
        printf 'STATUS=halt_mid_turn\nLAST_COMPLETED=%s\nCLAUSE=%s\n' "${last_c:-none}" "${clause:-unknown}"
    else
        printf 'STATUS=halt_mid_turn\nLAST_COMPLETED=none\nCLAUSE=loop_tmpdir_already_cleaned\n'
    fi
}

# Helper: bump a per-location counter variable given a last_completed token.
bump_location() {
    local lc="$1"
    case "$lc" in
        done)           loc_done=$((loc_done + 1)) ;;
        3i)             loc_3i=$((loc_3i + 1)) ;;
        3d-plan-post)   loc_3d_plan_post=$((loc_3d_plan_post + 1)) ;;
        3d-post-detect) loc_3d_post_detect=$((loc_3d_post_detect + 1)) ;;
        3d-pre-detect)  loc_3d_pre_detect=$((loc_3d_pre_detect + 1)) ;;
        3jv)            loc_3jv=$((loc_3jv + 1)) ;;
        3j)             loc_3j=$((loc_3j + 1)) ;;
        *)              loc_none=$((loc_none + 1)) ;;
    esac
}

# ---- Per-run loop ----------------------------------------------------------
for (( i=1; i<=RUNS; i++ )); do
    echo ">>> RUN $i/$RUNS starting" >&2
    run_start=$(date +%s)

    scratch=$(mktemp -d -t loop-halt-rate-run.XXXXXX)
    scratch_dirs+=("$scratch")

    # Provision bare origin + scratch working repo + fixture install.
    origin_git="$scratch/origin.git"
    work_repo="$scratch/repo"
    binshim="$scratch/bin"
    gh_stub_log="$scratch/gh-stub.log"
    run_log="$scratch/run.log"

    (
        git init --bare -q "$origin_git" || git init --bare "$origin_git" >/dev/null 2>&1

        mkdir -p "$work_repo"
        cd "$work_repo"
        if git init -q -b main . 2>/dev/null; then
            :
        else
            git init -q .
            git checkout -b main 2>/dev/null || git branch -m master main 2>/dev/null || true
        fi
        git config user.email "halt-rate-harness@local.test"
        git config user.name "halt-rate-harness"

        mkdir -p skills/loop-halt-rate
        cp "$FIXTURE_SRC" skills/loop-halt-rate/SKILL.md
        # Also copy fixture README if present, harmless.
        if [[ -f "$LARCH_ROOT/tests/fixtures/loop-halt-rate/README.md" ]]; then
            cp "$LARCH_ROOT/tests/fixtures/loop-halt-rate/README.md" skills/loop-halt-rate/README.md
        fi

        git add -A
        git commit -q -m "initial fixture for halt-rate harness"
        git remote add origin "$origin_git"
        git push -q origin main
    ) >"$scratch/provision.log" 2>&1 || {
        echo "RUN $i: status=error last_completed=none clause=\"provisioning_failed\" elapsed=0s"
        status_error=$((status_error + 1))
        loc_none=$((loc_none + 1))
        continue
    }

    emit_gh_stub "$binshim"

    # Invoke claude headlessly. Use timeout --kill-after to escalate to SIGKILL
    # after 10s of SIGTERM grace for zombie resilience.
    wrapper_exit=0
    (
        cd "$work_repo"
        PATH="$binshim:$PATH" GH_STUB_LOG="$gh_stub_log" \
            "$TIMEOUT_CMD" --kill-after=10 "$TIMEOUT_SEC" \
            claude --plugin-dir "$LARCH_ROOT" -p "/larch:loop-improve-skill loop-halt-rate" \
            >"$run_log" 2>&1
    ) || wrapper_exit=$?

    run_end=$(date +%s)
    elapsed=$((run_end - run_start))

    # Recover LOOP_TMPDIR from the log: parse either SESSION_TMPDIR= or LOOP_TMPDIR=
    # restricted to the claude-loop-improve- prefix under canonical /tmp or /private/tmp.
    LOOP_TMPDIR=""
    if [[ -s "$run_log" ]]; then
        # Restrict to /tmp or /private/tmp + claude-loop-improve- prefix; allow any non-whitespace tail.
        LOOP_TMPDIR=$(grep -oE '(SESSION_TMPDIR|LOOP_TMPDIR)=(/private)?/tmp/claude-loop-improve-[^[:space:]]*' "$run_log" \
                      | head -1 | cut -d= -f2- || true)
    fi

    # Classify
    class_out=$(classify_run "$run_log" "$wrapper_exit" "$LOOP_TMPDIR")
    run_status=$(printf '%s\n' "$class_out" | sed -n 's/^STATUS=//p' | head -1)
    last_c=$(printf '%s\n' "$class_out" | sed -n 's/^LAST_COMPLETED=//p' | head -1)
    clause=$(printf '%s\n' "$class_out" | sed -n 's/^CLAUSE=//p' | head -1)

    # Bump counters
    case "$run_status" in
        completed_by_outer)     status_completed=$((status_completed + 1)) ;;
        halt_mid_turn)          status_halt_mid_turn=$((status_halt_mid_turn + 1)) ;;
        halt_detected_by_outer) status_halt_detected=$((status_halt_detected + 1)) ;;
        timeout)                status_timeout=$((status_timeout + 1)) ;;
        tool_failure)           status_tool_failure=$((status_tool_failure + 1)) ;;
        error|*)                status_error=$((status_error + 1)) ;;
    esac
    bump_location "${last_c:-none}"

    echo "RUN $i: status=$run_status last_completed=${last_c:-none} clause=\"${clause:-unknown}\" elapsed=${elapsed}s"
done

# ---- Terminal output --------------------------------------------------------
halted=$((status_halt_mid_turn + status_halt_detected))
measured=$((status_completed + status_halt_mid_turn + status_halt_detected + status_timeout))
# error and tool_failure runs are excluded from HALT_RATE's numerator AND
# denominator — they are infrastructure failures, not halt-measurement signal.

# Derive PROBE_STATUS: `ok` iff at least one measured run AND no infrastructure
# errors; `error` otherwise (degraded signal — automation should check this
# token before consuming HALT_RATE).
probe_status="ok"
if (( measured == 0 || status_error > 0 || status_tool_failure > 0 )); then
    probe_status="error"
fi

echo ""
printf 'HALT_RATE=%s/%s\n' "$halted" "$measured"
printf 'MEASURED_RUNS=%s\n' "$measured"
printf 'PROBE_STATUS=%s\n' "$probe_status"
printf 'PER_STATUS_BREAKDOWN: completed=%s halt_mid_turn=%s halt_detected_by_outer=%s timeout=%s tool_failure=%s error=%s\n' \
    "$status_completed" "$status_halt_mid_turn" "$status_halt_detected" "$status_timeout" "$status_tool_failure" "$status_error"
printf 'PER_LOCATION_BREAKDOWN: none=%s 3j=%s 3jv=%s 3d-pre-detect=%s 3d-post-detect=%s 3d-plan-post=%s 3i=%s done=%s\n' \
    "$loc_none" "$loc_3j" "$loc_3jv" "$loc_3d_pre_detect" "$loc_3d_post_detect" "$loc_3d_plan_post" "$loc_3i" "$loc_done"

exit 0
