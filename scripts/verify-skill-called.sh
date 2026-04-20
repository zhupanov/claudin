#!/usr/bin/env bash
# verify-skill-called.sh — Mechanical post-invocation verification of
# Skill calls.
#
# After a parent skill invokes a child skill via the Skill tool, this helper
# provides a deterministic gate that the caller cannot satisfy without the
# child's side effects. Three mutually-exclusive modes target different
# observable signals:
#
#   --sentinel-file <path>
#       VERIFIED=true only if <path> exists, is a regular file, and is
#       non-empty. Use when the child skill writes a known artifact whose
#       presence proves it ran (e.g., /bump-version's reasoning file).
#
#   --stdout-line <regex> --stdout-file <path>
#       VERIFIED=true only if <path> contains at least one line matching
#       the POSIX extended regular expression <regex>. Matching uses
#       `LC_ALL=C grep -E -q -- "$regex" "$path"` to pin locale behavior
#       and prevent option injection via leading-dash patterns. Empty
#       regex is rejected as an argument error (an empty pattern would
#       match any non-empty line, defeating the check).
#       Trust boundary: <regex> and <path> are trusted inputs from the
#       caller; the helper does not sandbox against hostile patterns.
#       Callers must sanitize if regex is user-supplied.
#
#   --commit-delta <expected> --before-count <N>
#       VERIFIED=true only if the current commit count ahead of main (via
#       count_commits in lib-count-commits.sh) increased by exactly
#       <expected> since the caller captured <N> before the child skill
#       ran. If count_commits reports a non-ok status (missing_main_ref
#       or git_error), VERIFIED=false and REASON reflects that status —
#       the count comparison is short-circuited to prevent false-pass on
#       corrupted git state (e.g., delta 0 vs before-count 0 would
#       otherwise spuriously pass).
#
# Output (stdout, KEY=VALUE):
#   VERIFIED=true|false
#   REASON=<token>        (stable enum; see below)
#
# Reason tokens (stable enum):
#   ok                       — verification succeeded (VERIFIED=true)
#   missing_path             — --sentinel-file path is empty or does not exist
#   not_regular_file         — --sentinel-file path exists but is not a regular
#                              file (directory, symlink to non-regular target,
#                              device, etc.)
#   empty_file               — --sentinel-file path exists and is a regular
#                              file but is 0 bytes
#   missing_stdout_file      — --stdout-file path is empty or does not exist
#   no_match                 — --stdout-line regex did not match any line
#   commit_delta_mismatch    — actual commit-delta != expected
#   missing_main_ref         — --commit-delta: neither local `main` nor
#                              `origin/main` exists
#   git_error                — --commit-delta: git rev-list failed against
#                              a valid base ref (corrupted repo, etc.)
#
# Exit codes:
#   0 — verification ran to completion (check VERIFIED on stdout)
#   1 — argument error or internal helper fault (KEY=VALUE NOT emitted)
#
# Fail-closed: any unrecognized flag combination, missing required args,
# empty regex, or internal helper error yields exit 1 without emitting
# VERIFIED=. A successful completion (exit 0) always emits both
# VERIFIED= and REASON= on stdout.
#
# Usage:
#   verify-skill-called.sh --sentinel-file <path>
#   verify-skill-called.sh --stdout-line <regex> --stdout-file <path>
#   verify-skill-called.sh --commit-delta <expected> --before-count <N>

set -euo pipefail

usage() {
    cat >&2 <<'EOF'
Usage: verify-skill-called.sh MODE
Modes (mutually exclusive):
  --sentinel-file <path>
  --stdout-line <regex> --stdout-file <path>
  --commit-delta <expected> --before-count <N>
EOF
}

# --- Parse arguments ---------------------------------------------------------

MODE=""
SENTINEL_PATH=""
STDOUT_LINE_REGEX=""
STDOUT_FILE_PATH=""
COMMIT_DELTA_EXPECTED=""
COMMIT_BEFORE_COUNT=""

# Count how many mode flags were seen to catch mutual-exclusion violations.
mode_count=0

set_mode() {
    local new="$1"
    if [[ -n "$MODE" && "$MODE" != "$new" ]]; then
        mode_count=$((mode_count + 1))
    elif [[ -z "$MODE" ]]; then
        MODE="$new"
        mode_count=1
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --sentinel-file)
            set_mode "sentinel"
            SENTINEL_PATH="${2-}"; shift 2 || { usage; exit 1; }
            ;;
        --stdout-line)
            set_mode "stdout"
            STDOUT_LINE_REGEX="${2-}"; shift 2 || { usage; exit 1; }
            ;;
        --stdout-file)
            STDOUT_FILE_PATH="${2-}"; shift 2 || { usage; exit 1; }
            ;;
        --commit-delta)
            set_mode "commit"
            COMMIT_DELTA_EXPECTED="${2-}"; shift 2 || { usage; exit 1; }
            ;;
        --before-count)
            COMMIT_BEFORE_COUNT="${2-}"; shift 2 || { usage; exit 1; }
            ;;
        --help|-h)
            usage; exit 0
            ;;
        *)
            echo "ERROR: Unknown argument: $1" >&2
            usage; exit 1
            ;;
    esac
done

if [[ -z "$MODE" ]]; then
    echo "ERROR: No mode flag provided (need --sentinel-file, --stdout-line, or --commit-delta)" >&2
    usage; exit 1
fi

if [[ "$mode_count" -gt 1 ]]; then
    echo "ERROR: Modes are mutually exclusive; pass exactly one of --sentinel-file, --stdout-line, or --commit-delta" >&2
    usage; exit 1
fi

emit() {
    printf 'VERIFIED=%s\n' "$1"
    printf 'REASON=%s\n' "$2"
}

# --- Mode dispatch -----------------------------------------------------------

case "$MODE" in
    sentinel)
        if [[ -z "$SENTINEL_PATH" ]]; then
            echo "ERROR: --sentinel-file requires a non-empty path" >&2
            exit 1
        fi
        # Check order matters: existence → regular-file → non-empty. This
        # ensures symlinks to non-regular targets (e.g., /dev/null) report
        # REASON=not_regular_file rather than misleading REASON=empty_file.
        if [[ ! -e "$SENTINEL_PATH" ]]; then
            emit "false" "missing_path"
            exit 0
        fi
        if [[ ! -f "$SENTINEL_PATH" ]]; then
            emit "false" "not_regular_file"
            exit 0
        fi
        if [[ ! -s "$SENTINEL_PATH" ]]; then
            emit "false" "empty_file"
            exit 0
        fi
        emit "true" "ok"
        exit 0
        ;;

    stdout)
        if [[ -z "$STDOUT_LINE_REGEX" ]]; then
            echo "ERROR: --stdout-line requires a non-empty regex (empty would match any non-empty line)" >&2
            exit 1
        fi
        if [[ -z "$STDOUT_FILE_PATH" ]]; then
            echo "ERROR: --stdout-line requires --stdout-file" >&2
            exit 1
        fi
        if [[ ! -f "$STDOUT_FILE_PATH" ]]; then
            emit "false" "missing_stdout_file"
            exit 0
        fi
        # `--` stops option parsing so a regex beginning with `-` is not
        # mistaken for a grep flag. `LC_ALL=C` pins regex semantics to
        # byte-literal matching (no locale-dependent character classes).
        if LC_ALL=C grep -E -q -- "$STDOUT_LINE_REGEX" "$STDOUT_FILE_PATH"; then
            emit "true" "ok"
        else
            emit "false" "no_match"
        fi
        exit 0
        ;;

    commit)
        if [[ -z "$COMMIT_DELTA_EXPECTED" ]]; then
            echo "ERROR: --commit-delta requires an expected value" >&2
            exit 1
        fi
        if [[ -z "$COMMIT_BEFORE_COUNT" ]]; then
            echo "ERROR: --commit-delta requires --before-count" >&2
            exit 1
        fi
        if ! [[ "$COMMIT_DELTA_EXPECTED" =~ ^[0-9]+$ ]]; then
            echo "ERROR: --commit-delta value must be a non-negative integer: $COMMIT_DELTA_EXPECTED" >&2
            exit 1
        fi
        if ! [[ "$COMMIT_BEFORE_COUNT" =~ ^[0-9]+$ ]]; then
            echo "ERROR: --before-count value must be a non-negative integer: $COMMIT_BEFORE_COUNT" >&2
            exit 1
        fi

        # shellcheck source=scripts/lib-count-commits.sh
        source "$(dirname "${BASH_SOURCE[0]}")/lib-count-commits.sh"
        # Use a temp file for the status side channel because bash's $(...)
        # command substitution creates a subshell — any global or exported
        # variable the subshell writes is lost. A file survives the subshell.
        status_file=$(mktemp "${TMPDIR:-/tmp}/verify-skill-called-status.XXXXXX")
        # shellcheck disable=SC2064  # status_file expansion is intentional at trap-registration time
        trap "rm -f '$status_file'" EXIT
        COUNT_COMMITS_STATUS_FILE="$status_file" \
            actual_total=$(COUNT_COMMITS_STATUS_FILE="$status_file" count_commits)
        COUNT_COMMITS_STATUS=$(cat "$status_file" 2>/dev/null || echo "")

        # Short-circuit on degraded git state — a raw count of 0 under
        # missing_main_ref or git_error is untrustworthy and must not be
        # compared against --commit-delta 0.
        case "$COUNT_COMMITS_STATUS" in
            ok)
                ;;
            missing_main_ref)
                emit "false" "missing_main_ref"
                exit 0
                ;;
            git_error)
                emit "false" "git_error"
                exit 0
                ;;
            *)
                # Defensive: unknown status means the lib changed contract
                # without our knowledge. Fail-closed.
                emit "false" "git_error"
                exit 0
                ;;
        esac

        actual_delta=$((actual_total - COMMIT_BEFORE_COUNT))
        if [[ "$actual_delta" -eq "$COMMIT_DELTA_EXPECTED" ]]; then
            emit "true" "ok"
        else
            emit "false" "commit_delta_mismatch"
        fi
        exit 0
        ;;

    *)
        # Unreachable — MODE is constrained by set_mode above.
        echo "ERROR: internal: unknown mode $MODE" >&2
        exit 1
        ;;
esac
