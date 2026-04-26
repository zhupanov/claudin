#!/usr/bin/env bash
# driver.sh — Bash driver for /loop-fix-issue.
#
# Topology: bash owns loop control; each iteration is its own
# `claude -p /fix-issue` subprocess. Halt class eliminated by construction:
# no post-child-return model turn that can halt between subprocess return
# and this driver's post-call Bash.
#
# Usage:
#   driver.sh [--debug] [--max-iterations N] [--no-slack]
#
# Arguments:
#   --debug            — optional flag (currently no-op; reserved for future
#                        verbosity control).
#   --max-iterations N — safety cap on the loop (default 50). Loop terminates
#                        when /fix-issue reports no eligible issues OR this
#                        cap is hit.
#   --no-slack         — forwarded to /fix-issue (which forwards to /implement)
#                        each iteration.
#
# Termination signal:
#   /fix-issue Step 0 exit 0 (success) explicitly mandates printing the
#   literal `> **🔶 0: find & lock — found and locked #<N>: <title>**` on
#   stdout. Step 0 exits 1/2/3 (no eligible / error / lock-failed) print
#   different literals (`no approved issues found`, `error:`, `lock failed`).
#   The driver greps captured stdout for the fixed substring
#   `find & lock — found and locked` — present means an issue was processed,
#   absent means the loop should stop. Choosing the Step 0 SUCCESS literal
#   (rather than the Step 1 setup breadcrumb) is more robust because Step 0's
#   success line is explicitly mandated by /fix-issue SKILL.md, while the
#   Step 1 breadcrumb is only an implicit progress-reporting convention.
#
# Security posture (mirrors loop-review/driver.sh):
#   - LOOP_TMPDIR MUST begin with /tmp/ or /private/tmp/ AND MUST NOT contain
#     `..` as a path component.
#   - Per-iteration artifacts (iter-N-out.txt, iter-N-out.txt.stderr) accumulate
#     in LOOP_TMPDIR; retained on subprocess failure for inspection.
#   - All `claude -p` invocations follow loop-review's contract:
#     --plugin-dir, prompt on STDIN (avoids ARG_MAX), stderr sidecar.
#   - $LOOP_TMPDIR cleaned via EXIT trap on success; retained on any abnormal
#     exit so operators can inspect per-iteration artifacts.
#
# LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE is an advisory env var used ONLY by
# tests to redirect `claude -p` invocations at a stub shim. Documented in
# SECURITY.md as test-only; never set in production.

set -euo pipefail

if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
  export CLAUDE_PLUGIN_ROOT
fi

# --------------------------------------------------------------------------
# Breadcrumb helpers (match larch progress convention)
# --------------------------------------------------------------------------

breadcrumb_inprogress() { printf '> **🔶 %s**\n' "$*"; }
breadcrumb_done()       { printf '✅ %s\n' "$*"; }
breadcrumb_warn()       { printf '**⚠ %s**\n' "$*"; }

# --------------------------------------------------------------------------
# Cleanup trap (conditional retention)
# --------------------------------------------------------------------------

LOOP_TMPDIR=""
LOOP_PRESERVE_TMPDIR="false"

cleanup_on_exit() {
  local rc=$?
  printf 'LOOP_TMPDIR=%s\n' "${LOOP_TMPDIR}"
  if [[ -n "$LOOP_TMPDIR" && -d "$LOOP_TMPDIR" ]]; then
    if [[ "$LOOP_PRESERVE_TMPDIR" == "true" ]]; then
      breadcrumb_warn "cleanup — retained working directory: ${LOOP_TMPDIR}"
    elif [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/cleanup-tmpdir.sh" ]]; then
      "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh" --dir "$LOOP_TMPDIR" || true
    fi
  fi
  return "$rc"
}
trap cleanup_on_exit EXIT

# --------------------------------------------------------------------------
# Helper: invoke_claude_p_skill — STDIN delivery + plugin-dir + stderr sidecar.
# --------------------------------------------------------------------------

invoke_claude_p_skill() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1800}"
  local stderr_file="${out_file}.stderr"
  local rc=0

  local claude_bin="${LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE:-claude}"

  : > "$out_file"
  : > "$stderr_file"

  (
    cd "$REPO_ROOT"
    "$claude_bin" -p --plugin-dir "$CLAUDE_PLUGIN_ROOT" \
      < "$prompt_file" > "$out_file" 2> "$stderr_file" &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if [[ "$elapsed" -ge "$timeout_s" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 5
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        printf 'claude-%s: TIMED OUT after %ss\n' "$label" "$timeout_s" >> "$stderr_file"
        exit 124
      fi
      sleep 10
      elapsed=$(( elapsed + 10 ))
    done
    wait "$pid"
  ) || rc=$?

  return "$rc"
}

# --------------------------------------------------------------------------
# Step 1 — Parse argv + CLI preflight
# --------------------------------------------------------------------------

DEBUG_FLAG="false"
NO_SLACK_FLAG="false"
NO_ADMIN_FALLBACK_FLAG="false"
MAX_ITERATIONS=50

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG_FLAG="true"; shift ;;
    --no-slack) NO_SLACK_FLAG="true"; shift ;;
    --no-admin-fallback) NO_ADMIN_FALLBACK_FLAG="true"; shift ;;
    --max-iterations)
      shift
      if [[ $# -eq 0 || "$1" =~ ^- ]]; then
        breadcrumb_warn "1: parse args — --max-iterations requires a positive integer argument."
        exit 1
      fi
      if ! [[ "$1" =~ ^[1-9][0-9]*$ ]]; then
        breadcrumb_warn "1: parse args — --max-iterations must be a positive integer (got: $1)."
        exit 1
      fi
      MAX_ITERATIONS="$1"
      shift
      ;;
    --) shift; break ;;
    *)
      breadcrumb_warn "1: parse args — unknown argument '$1'. Valid: --debug, --max-iterations N, --no-slack, --no-admin-fallback."
      exit 1
      ;;
  esac
done

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

if ! command -v claude >/dev/null 2>&1 && [[ -z "${LARCH_LOOP_FIX_ISSUE_CLAUDE_OVERRIDE:-}" ]]; then
  breadcrumb_warn "1: parse args — claude CLI not on PATH. Aborting."
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  breadcrumb_warn "1: parse args — gh CLI not on PATH. Aborting."
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  breadcrumb_warn "1: parse args — gh is not authenticated (gh auth status failed). Aborting."
  exit 1
fi

breadcrumb_done "1: parse args — debug=${DEBUG_FLAG}, max-iterations=${MAX_ITERATIONS}, no-slack=${NO_SLACK_FLAG}, no-admin-fallback=${NO_ADMIN_FALLBACK_FLAG}"

# --------------------------------------------------------------------------
# Step 2 — Session setup (LOOP_TMPDIR)
# --------------------------------------------------------------------------

breadcrumb_inprogress "2: session setup"

SETUP_OUT=""
if ! SETUP_OUT="$("${CLAUDE_PLUGIN_ROOT}"/scripts/session-setup.sh \
    --prefix claude-loop-fix-issue \
    --skip-slack-check \
    --skip-repo-check 2>&1)"; then
  printf '%s\n' "$SETUP_OUT" >&2
  breadcrumb_warn "2: session setup — session-setup.sh exited non-zero. Aborting."
  exit 1
fi

LOOP_TMPDIR="$(printf '%s\n' "$SETUP_OUT" | awk -F= '/^SESSION_TMPDIR=/{print substr($0, index($0,"=")+1); exit}')"

if [[ -z "$LOOP_TMPDIR" ]]; then
  breadcrumb_warn "2: session setup — failed to parse SESSION_TMPDIR. Aborting."
  exit 1
fi

if ! [[ "$LOOP_TMPDIR" == /tmp/* || "$LOOP_TMPDIR" == /private/tmp/* ]]; then
  breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' does not begin with /tmp/ or /private/tmp/. Aborting."
  exit 1
fi
case "$LOOP_TMPDIR" in
  */..|*/../*)
    breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' contains '..' path component. Aborting."
    exit 1 ;;
esac

breadcrumb_done "2: session setup — LOOP_TMPDIR=${LOOP_TMPDIR}"

# --------------------------------------------------------------------------
# Step 3 — Loop: invoke /fix-issue until no work remains.
# --------------------------------------------------------------------------

# Termination sentinel: /fix-issue Step 0 exit 0 prints the explicit literal
# `> **🔶 0: find & lock — found and locked #<N>: <title>**`. Step 0
# exits 1/2/3 print different literals. We grep for the fixed substring
# `find & lock — found and locked` (no shell-pattern characters; no `🔶`
# emoji prefix needed since the substring is unique to the success path).
# Chosen over the Step 1 setup breadcrumb because Step 0's success line is
# explicitly mandated by /fix-issue SKILL.md while Step 1's breadcrumb is
# only an implicit progress-reporting convention.
SETUP_SENTINEL='find & lock — found and locked'

# Compose the per-iteration prompt once (identical across iterations).
PROMPT_FILE="$LOOP_TMPDIR/fix-issue-prompt.txt"
FIX_ISSUE_FLAGS=""
if [[ "$NO_SLACK_FLAG" == "true" ]]; then
  FIX_ISSUE_FLAGS+=" --no-slack"
fi
if [[ "$NO_ADMIN_FALLBACK_FLAG" == "true" ]]; then
  FIX_ISSUE_FLAGS+=" --no-admin-fallback"
fi
printf '/fix-issue%s\n' "$FIX_ISSUE_FLAGS" > "$PROMPT_FILE"

ITERATIONS_RUN=0
TERMINATION_REASON=""

for (( ITER=1; ITER<=MAX_ITERATIONS; ITER++ )); do
  breadcrumb_inprogress "3: iteration ${ITER} — invoking /fix-issue"

  ITER_OUT_FILE="$LOOP_TMPDIR/iter-${ITER}-out.txt"

  rc=0
  invoke_claude_p_skill "$PROMPT_FILE" "$ITER_OUT_FILE" "iter-${ITER}" 1800 || rc=$?

  ITERATIONS_RUN=$ITER

  if [[ "$rc" -ne 0 ]]; then
    breadcrumb_warn "3: iteration ${ITER} — claude -p exited ${rc}; retaining LOOP_TMPDIR for inspection. Stopping loop."
    LOOP_PRESERVE_TMPDIR="true"
    TERMINATION_REASON="claude -p subprocess error (exit ${rc})"
    break
  fi

  # Termination check: did /fix-issue reach Step 1 (i.e., did Step 0 lock work)?
  # When the success sentinel is absent, /fix-issue Step 0 emits one of three
  # documented literals (exit 1 / 2 / 3 per /fix-issue SKILL.md Step 0); a
  # defensive fallback handles any unrecognized Step 0 stdout. Map each to its
  # own termination reason and preserve LOOP_TMPDIR on the non-clean paths so
  # per-iteration artifacts remain available for inspection.
  #
  # Each sub-sentinel is anchored with the literal `0: find & lock — ` step
  # prefix so user-data-bearing $ERROR text in one branch (e.g., the exit-3
  # message body) cannot accidentally trigger a different branch's keyword.
  if ! grep -F -q "$SETUP_SENTINEL" "$ITER_OUT_FILE"; then
    if grep -F -q '0: find & lock — no approved issues found' "$ITER_OUT_FILE"; then
      breadcrumb_done "3: iteration ${ITER} — /fix-issue reported no work to do. Loop complete."
      TERMINATION_REASON="no eligible issues (clean exhaustion)"
    elif grep -F -q '0: find & lock — error:' "$ITER_OUT_FILE"; then
      breadcrumb_warn "3: iteration ${ITER} — /fix-issue Step 0 reported an error; retaining LOOP_TMPDIR for inspection. Stopping loop."
      LOOP_PRESERVE_TMPDIR="true"
      TERMINATION_REASON="Step 0 error (likely transient)"
    elif grep -F -q '0: find & lock — lock failed' "$ITER_OUT_FILE"; then
      breadcrumb_warn "3: iteration ${ITER} — /fix-issue Step 0 lock acquisition failed; retaining LOOP_TMPDIR for inspection. Stopping loop."
      LOOP_PRESERVE_TMPDIR="true"
      TERMINATION_REASON="Step 0 lock failure (concurrent runner or partial-state)"
    else
      breadcrumb_warn "3: iteration ${ITER} — /fix-issue produced no recognized Step 0 literal; retaining LOOP_TMPDIR for inspection. Stopping loop."
      LOOP_PRESERVE_TMPDIR="true"
      TERMINATION_REASON="Step 0 unknown short-circuit (sentinel mismatch)"
    fi
    break
  fi

  breadcrumb_done "3: iteration ${ITER} — /fix-issue completed an issue."
done

if [[ -z "$TERMINATION_REASON" ]]; then
  breadcrumb_warn "3: loop — hit --max-iterations cap (${MAX_ITERATIONS}). More eligible issues may remain; rerun /loop-fix-issue to continue."
  TERMINATION_REASON="--max-iterations cap reached"
fi

# --------------------------------------------------------------------------
# Step 4 — Final summary
# --------------------------------------------------------------------------

breadcrumb_done "4: summary — ${ITERATIONS_RUN} iteration(s) run; termination: ${TERMINATION_REASON}"
