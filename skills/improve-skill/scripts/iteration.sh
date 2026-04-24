#!/usr/bin/env bash
# iteration.sh — Bash kernel for /improve-skill and /loop-improve-skill.
#
# Represents ONE round (judge → grade-parse → design → im → verify) of the
# iterative skill-improvement loop. Invoked standalone by /improve-skill
# (SKILL.md launches this script directly via Bash+Monitor) and by
# /loop-improve-skill's driver.sh (once per iteration in its up-to-10-round
# while loop). Extracted from the pre-#273 driver.sh iteration body so the
# kernel has a single canonical home.
#
# Halt-class elimination preserved by construction: each child skill runs
# as a fresh `claude -p` subprocess; bash does parsing, posting, and state
# transitions in the parent shell. See SECURITY.md /improve-skill subsection.
#
# Usage:
#   iteration.sh [--no-slack] [--issue <N>] [--breadcrumb-prefix <P>] \
#                [--work-dir <path>] [--iter-num <N>] <skill-name>
#
# Flags:
#   --no-slack               Prepend '--no-slack ' to the /larch:im prompt so the
#                            iteration's /implement run does NOT post to Slack.
#                            Default: absent — posts per /implement's default-on
#                            behavior (gated on Slack env vars).
#   --issue <N>              Use existing tracking issue #N (required for loop
#                            invocation; standalone creates its own via gh).
#   --breadcrumb-prefix <P>  Prepend P to every breadcrumb (e.g., '4.3' for
#                            nested numbering when called from /loop-improve-skill).
#   --work-dir <path>        Use caller-supplied work-dir (loop mode). All
#                            iter-${ITER}-*.txt artifacts are written here.
#                            When absent (standalone mode), iteration.sh calls
#                            session-setup.sh to create a fresh work-dir and
#                            owns its EXIT-trap cleanup.
#   --iter-num <N>           Iteration index (default: 1) used in artifact
#                            filenames iter-${ITER}-*.txt. Driver passes the
#                            loop's ITER counter so all iterations accumulate
#                            in LOOP_TMPDIR without filename collisions.
#   <skill-name>             Target larch skill. Leading `/` stripped. Must
#                            match `^[a-z][a-z0-9-]*$`.
#
# KV footer (stdout, `### iteration-result` delimited, consumed by the loop
# driver's awk parse — 9 keys, all always emitted via the EXIT trap):
#
#   ITER_STATUS=<grade_a|ok|no_plan|design_refusal|im_verification_failed|
#                judge_failed|unknown>
#   EXIT_REASON=<free-text string; same values as pre-#273 driver.sh>
#   PARSE_STATUS=<ok|missing_table|missing_file|bad_row|empty_file|unknown>
#   GRADE_A=<true|false>
#   NON_A_DIMS=<comma-separated dim list, e.g. D2,D7; empty if GRADE_A=true>
#   TOTAL_NUM=<int|N/A>
#   TOTAL_DEN=<int|N/A>
#   ITERATION_TMPDIR=<absolute path>
#   ISSUE_NUM=<int>
#
# Security posture (mirrors pre-refactor driver.sh, see SECURITY.md):
#   - WORK_DIR MUST begin with /tmp/ or /private/tmp/ AND MUST NOT contain
#     `..` as a path component (reject occurrences of /.. or a trailing ..).
#   - All subprocess invocations cd to REPO_ROOT so target skill-dir resolves
#     consistently.
#   - Argv arrays for command construction (no eval, no source of untrusted
#     content).
#   - All gh comment bodies piped through redact-secrets.sh before posting.
#   - In standalone mode, WORK_DIR is cleaned via EXIT trap. In loop mode
#     (--work-dir supplied) the driver owns cleanup; iteration.sh does NOT
#     touch a caller-supplied work-dir at exit.
#   - invoke_claude_p routes each prompt via a file fed on STDIN (FINDING_9;
#     avoids ARG_MAX exhaustion) and redirects stderr to a .stderr sidecar
#     (FINDING_10; stderr is not posted to public issues).
#   - Every exit path (normal, error, set -e abort) emits the KV footer via
#     an EXIT trap so loop-driver parsing is never starved.

set -euo pipefail

# Derive CLAUDE_PLUGIN_ROOT from script location when the harness did not
# export it. Layout:
#   ${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh
# so the plugin root is three directories up from the script.
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
  export CLAUDE_PLUGIN_ROOT
fi

# --------------------------------------------------------------------------
# Breadcrumb helpers (match larch progress convention)
# --------------------------------------------------------------------------

BREADCRUMB_PREFIX=""  # optional caller-supplied prefix (e.g. "4.3")

_prefix() {
  if [[ -n "$BREADCRUMB_PREFIX" ]]; then
    printf '%s.' "$BREADCRUMB_PREFIX"
  fi
}

breadcrumb_inprogress() { printf '> **🔶 %s%s**\n' "$(_prefix)" "$*"; }
breadcrumb_done()       { printf '✅ %s%s\n' "$(_prefix)" "$*"; }
# shellcheck disable=SC2317  # reserved for future skip messages; keep symmetry with other helpers
breadcrumb_skip()       { printf '⏩ %s%s\n' "$(_prefix)" "$*"; }
breadcrumb_warn()       { printf '**⚠ %s%s**\n' "$(_prefix)" "$*"; }

# --------------------------------------------------------------------------
# KV footer state (initialized with defaults so EXIT trap emits a valid
# footer even if the script aborts before any phase completes — FINDING_2).
# --------------------------------------------------------------------------

KV_ITER_STATUS="unknown"
KV_EXIT_REASON=""
KV_PARSE_STATUS="unknown"
KV_GRADE_A="false"
KV_NON_A_DIMS=""
KV_TOTAL_NUM="N/A"
KV_TOTAL_DEN="N/A"
KV_ITERATION_TMPDIR=""
KV_ISSUE_NUM=""

# Captured at Step 3 standalone-create; empty when the loop driver adopts via
# --issue (driver emits the URL itself at loop end). Initialized here so the
# EXIT trap's `set -u` safely references it on any early-exit path.
ISSUE_URL=""

# shellcheck disable=SC2317  # invoked via trap on EXIT — shellcheck cannot see the indirect call
emit_kv_footer() {
  # Emitted on every exit path (normal + set -e abort). Uses `printf` to
  # stdout; loop driver's awk extracts keys line-by-line.
  printf '\n### iteration-result\n'
  printf 'ITER_STATUS=%s\n' "${KV_ITER_STATUS}"
  printf 'EXIT_REASON=%s\n' "${KV_EXIT_REASON}"
  printf 'PARSE_STATUS=%s\n' "${KV_PARSE_STATUS}"
  printf 'GRADE_A=%s\n' "${KV_GRADE_A}"
  printf 'NON_A_DIMS=%s\n' "${KV_NON_A_DIMS}"
  printf 'TOTAL_NUM=%s\n' "${KV_TOTAL_NUM}"
  printf 'TOTAL_DEN=%s\n' "${KV_TOTAL_DEN}"
  printf 'ITERATION_TMPDIR=%s\n' "${KV_ITERATION_TMPDIR}"
  printf 'ISSUE_NUM=%s\n' "${KV_ISSUE_NUM}"
}

# --------------------------------------------------------------------------
# Cleanup trap (optional URL breadcrumb, then KV footer, then work-dir
# cleanup when owned)
# --------------------------------------------------------------------------

WORK_DIR=""
OWNS_WORK_DIR="false"   # true only in standalone mode (no --work-dir passed)
PRESERVE_WORK_DIR="false"  # sticky; once true, cleanup is suppressed (issue #399)

# shellcheck disable=SC2317  # invoked via trap on EXIT
cleanup_on_exit() {
  local rc=$?
  # Surface the tracking-issue URL in standalone mode so the user sees it at
  # the very end via Monitor (loop mode suppresses this: driver.sh emits the
  # URL itself at Step 5, and iteration.sh in loop mode does not hold the
  # URL form — only the adopted number).
  if [[ "$OWNS_WORK_DIR" == "true" && -n "$ISSUE_URL" ]]; then
    breadcrumb_done "tracking issue URL: ${ISSUE_URL}" || true
  fi
  # Emit KV footer so parsers see the result even when work-dir cleanup fails
  # (FINDING_2 guarantee).
  emit_kv_footer || true
  # Retention gate (issue #399): preserve the work-dir on any non-success
  # iteration status so operators can inspect per-iteration artifacts
  # (iter-<N>-*.txt and .stderr sidecars). Cleanup still runs on grade_a/ok.
  case "$KV_ITER_STATUS" in
    grade_a|ok) : ;;
    *) PRESERVE_WORK_DIR="true" ;;
  esac
  if [[ "$OWNS_WORK_DIR" == "true" && -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    if [[ "$PRESERVE_WORK_DIR" == "true" ]]; then
      breadcrumb_warn "retained work-dir at ${WORK_DIR} for diagnostics (status=${KV_ITER_STATUS})." >&2
    elif [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/cleanup-tmpdir.sh" ]]; then
      "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh" --dir "$WORK_DIR" || true
    fi
  fi
  return "$rc"
}
trap cleanup_on_exit EXIT

# --------------------------------------------------------------------------
# Step 1 — Parse flags + positional arg
# --------------------------------------------------------------------------

NO_SLACK_FLAG=""   # empty by default; set to "--no-slack " (trailing space) if --no-slack is present
ISSUE_ARG=""
WORK_DIR_ARG=""
ITER_NUM="1"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-slack) NO_SLACK_FLAG="--no-slack "; shift ;;
    --issue)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        breadcrumb_warn "1: parse args — --issue requires a value. Aborting."
        KV_EXIT_REASON="bad --issue argument"
        exit 1
      fi
      ISSUE_ARG="$2"
      if ! [[ "$ISSUE_ARG" =~ ^[0-9]+$ ]]; then
        breadcrumb_warn "1: parse args — --issue must be a positive integer (got: '$ISSUE_ARG'). Aborting."
        KV_EXIT_REASON="bad --issue argument: '$ISSUE_ARG'"
        exit 1
      fi
      shift 2 ;;
    --breadcrumb-prefix)
      if [[ $# -lt 2 ]]; then
        breadcrumb_warn "1: parse args — --breadcrumb-prefix requires a value. Aborting."
        KV_EXIT_REASON="bad --breadcrumb-prefix argument"
        exit 1
      fi
      BREADCRUMB_PREFIX="$2"
      shift 2 ;;
    --work-dir)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        breadcrumb_warn "1: parse args — --work-dir requires a value. Aborting."
        KV_EXIT_REASON="bad --work-dir argument"
        exit 1
      fi
      WORK_DIR_ARG="$2"
      shift 2 ;;
    --iter-num)
      if [[ $# -lt 2 || -z "${2:-}" ]]; then
        breadcrumb_warn "1: parse args — --iter-num requires a value. Aborting."
        KV_EXIT_REASON="bad --iter-num argument"
        exit 1
      fi
      ITER_NUM="$2"
      if ! [[ "$ITER_NUM" =~ ^[1-9][0-9]*$ ]]; then
        breadcrumb_warn "1: parse args — --iter-num must be a positive integer (got: '$ITER_NUM'). Aborting."
        KV_EXIT_REASON="bad --iter-num argument: '$ITER_NUM'"
        exit 1
      fi
      shift 2 ;;
    --) shift; break ;;
    --*)
      breadcrumb_warn "1: parse args — unknown flag '$1'. Valid flags: --no-slack, --issue, --breadcrumb-prefix, --work-dir, --iter-num."
      KV_EXIT_REASON="unknown flag '$1'"
      exit 1
      ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  breadcrumb_warn "1: parse args — missing <skill-name>. Usage: iteration.sh [--no-slack] [--issue <N>] [--breadcrumb-prefix <P>] [--work-dir <path>] [--iter-num <N>] <skill-name>"
  KV_EXIT_REASON="missing <skill-name>"
  exit 1
fi

SKILL_NAME="${1#/}"  # strip a single leading /

if ! [[ "$SKILL_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  breadcrumb_warn "1: parse args — invalid <skill-name> '$SKILL_NAME' (must match ^[a-z][a-z0-9-]*\$). Aborting."
  KV_EXIT_REASON="invalid <skill-name> '$SKILL_NAME'"
  exit 1
fi

# --------------------------------------------------------------------------
# Resolve REPO_ROOT + TARGET_SKILL_PATH (3-probe order)
# --------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

TARGET_SKILL_PATH=""
for candidate in \
    "${REPO_ROOT}/skills/${SKILL_NAME}/SKILL.md" \
    "${REPO_ROOT}/.claude/skills/${SKILL_NAME}/SKILL.md" \
    "${CLAUDE_PLUGIN_ROOT:-}/skills/${SKILL_NAME}/SKILL.md"; do
  if [[ -n "$candidate" && -f "$candidate" ]]; then
    TARGET_SKILL_PATH="$candidate"
    break
  fi
done

if [[ -z "$TARGET_SKILL_PATH" ]]; then
  breadcrumb_warn "1: parse args — no skill found. Probed: ${REPO_ROOT}/skills/${SKILL_NAME}/, ${REPO_ROOT}/.claude/skills/${SKILL_NAME}/, ${CLAUDE_PLUGIN_ROOT:-<unset>}/skills/${SKILL_NAME}/. Aborting."
  KV_EXIT_REASON="skill '$SKILL_NAME' not found"
  exit 1
fi

breadcrumb_done "1: parse args — target /${SKILL_NAME} at ${TARGET_SKILL_PATH}"

# --------------------------------------------------------------------------
# Pre-flight: gh auth, claude CLI
# --------------------------------------------------------------------------

if ! command -v claude >/dev/null 2>&1; then
  breadcrumb_warn "1: parse args — claude CLI not on PATH. Aborting."
  KV_EXIT_REASON="claude CLI not found"
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  breadcrumb_warn "1: parse args — gh CLI not on PATH. Aborting."
  KV_EXIT_REASON="gh CLI not found"
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  breadcrumb_warn "1: parse args — gh is not authenticated (gh auth status failed). Aborting."
  KV_EXIT_REASON="gh not authenticated"
  exit 1
fi

# --------------------------------------------------------------------------
# Step 2 — Resolve work-dir (standalone creates; loop mode inherits)
# --------------------------------------------------------------------------

breadcrumb_inprogress "2: work-dir"

if [[ -n "$WORK_DIR_ARG" ]]; then
  # Loop mode: caller supplies work-dir. Validate security boundary.
  WORK_DIR="$WORK_DIR_ARG"
  if ! [[ "$WORK_DIR" == /tmp/* || "$WORK_DIR" == /private/tmp/* ]]; then
    breadcrumb_warn "2: work-dir — '$WORK_DIR' does not begin with /tmp/ or /private/tmp/. Aborting."
    KV_EXIT_REASON="invalid --work-dir: not under /tmp"
    exit 1
  fi
  case "$WORK_DIR" in
    */..|*/../*)
      breadcrumb_warn "2: work-dir — '$WORK_DIR' contains '..' path component. Aborting."
      KV_EXIT_REASON="invalid --work-dir: '..' in path"
      exit 1 ;;
  esac
  if [[ ! -d "$WORK_DIR" ]]; then
    breadcrumb_warn "2: work-dir — '$WORK_DIR' does not exist. Aborting."
    KV_EXIT_REASON="--work-dir does not exist"
    exit 1
  fi
  OWNS_WORK_DIR="false"
  breadcrumb_done "2: work-dir — using caller-supplied ${WORK_DIR} (loop mode)"
else
  # Standalone mode: create a fresh work-dir via session-setup.sh.
  # FINDING_11 opt-in: IMPROVE_SKILL_SKIP_PREFLIGHT=1 adds --skip-preflight
  # for the test harness fixtures.
  SETUP_EXTRA_FLAGS=()
  if [[ "${IMPROVE_SKILL_SKIP_PREFLIGHT:-}" == "1" ]]; then
    SETUP_EXTRA_FLAGS+=("--skip-preflight")
  fi
  SETUP_OUT=""
  if ! SETUP_OUT="$("${CLAUDE_PLUGIN_ROOT}"/scripts/session-setup.sh \
      --prefix claude-improve \
      --skip-branch-check \
      --skip-slack-check \
      --skip-repo-check \
      ${SETUP_EXTRA_FLAGS[@]+"${SETUP_EXTRA_FLAGS[@]}"} 2>&1)"; then
    printf '%s\n' "$SETUP_OUT" >&2
    breadcrumb_warn "2: work-dir — session-setup.sh exited non-zero. Aborting."
    KV_EXIT_REASON="session-setup failure"
    exit 1
  fi
  WORK_DIR="$(printf '%s\n' "$SETUP_OUT" | awk -F= '/^SESSION_TMPDIR=/{print substr($0, index($0,"=")+1); exit}')"
  if [[ -z "$WORK_DIR" ]]; then
    breadcrumb_warn "2: work-dir — failed to parse SESSION_TMPDIR. Aborting."
    KV_EXIT_REASON="session-setup parse failure"
    exit 1
  fi
  if ! [[ "$WORK_DIR" == /tmp/* || "$WORK_DIR" == /private/tmp/* ]]; then
    breadcrumb_warn "2: work-dir — WORK_DIR '$WORK_DIR' does not begin with /tmp/ or /private/tmp/. Aborting."
    KV_EXIT_REASON="WORK_DIR not under /tmp"
    exit 1
  fi
  case "$WORK_DIR" in
    */..|*/../*)
      breadcrumb_warn "2: work-dir — WORK_DIR '$WORK_DIR' contains '..' path component. Aborting."
      KV_EXIT_REASON="WORK_DIR contains '..' path component"
      exit 1 ;;
  esac
  OWNS_WORK_DIR="true"
  # One-shot forensic capture (advisory only; failure ignored)
  claude --version > "$WORK_DIR/claude-version.txt" 2>/dev/null || true
  breadcrumb_done "2: work-dir — created ${WORK_DIR} (standalone mode)"
fi

KV_ITERATION_TMPDIR="$WORK_DIR"

# --------------------------------------------------------------------------
# Step 3 — Resolve tracking issue (adopt via --issue, or create)
# --------------------------------------------------------------------------

if [[ -n "$ISSUE_ARG" ]]; then
  ISSUE_NUM="$ISSUE_ARG"
  # Hydrate ISSUE_URL so the EXIT-trap URL breadcrumb fires on standalone-adopt
  # runs too. Loop mode (OWNS_WORK_DIR=false) suppresses the trap line and the
  # driver emits its own URL at loop end, so the hydration is only load-bearing
  # for standalone-adopt. Graceful degradation: if `gh issue view` fails (stale
  # issue number, network blip, gh auth lapse), leave ISSUE_URL empty and log
  # to stderr — the trap's `-n "$ISSUE_URL"` gate falls through silently.
  if [[ "$OWNS_WORK_DIR" == "true" ]]; then
    if ! ISSUE_URL="$(gh issue view "$ISSUE_NUM" --json url --jq .url 2>/dev/null)"; then
      ISSUE_URL=""
      printf 'iteration.sh: warning: gh issue view #%s failed; final URL breadcrumb suppressed.\n' "${ISSUE_NUM}" >&2
    fi
  fi
  breadcrumb_done "3: issue — adopted #${ISSUE_NUM} (via --issue)"
else
  breadcrumb_inprogress "3: issue — creating tracking issue"
  ISSUE_BODY_FILE="$WORK_DIR/issue-body.md"
  {
    # shellcheck disable=SC2016  # backticks inside literal prose (issue body), not command substitution
    printf 'Tracking issue for one-round improvement of /%s via /improve-skill. Runs /skill-judge + /design + /im as fresh `claude -p` subprocesses via a bash iteration kernel. Halt class eliminated by construction (closes #273).\n\n' "${SKILL_NAME}"
    printf 'Target: %s\n' "${TARGET_SKILL_PATH}"
  } > "$ISSUE_BODY_FILE"
  ISSUE_CREATE_STDERR="$WORK_DIR/gh-create-issue.stderr"
  ISSUE_URL="$(gh issue create \
    --title "Improve /${SKILL_NAME} skill via /improve-skill (one iteration)" \
    --body-file "$ISSUE_BODY_FILE" 2> "$ISSUE_CREATE_STDERR")" || {
    breadcrumb_warn "3: issue — gh issue create failed. Aborting."
    dump_helper_stderr "gh-create-issue" "$ISSUE_CREATE_STDERR"
    KV_EXIT_REASON="gh issue create failed"
    exit 1
  }
  ISSUE_NUM="$(printf '%s\n' "$ISSUE_URL" | awk -F/ '/issues\//{print $NF; exit}')"
  if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
    breadcrumb_warn "3: issue — could not parse issue number from '$ISSUE_URL'. Aborting."
    KV_EXIT_REASON="could not parse issue number from gh output"
    exit 1
  fi
  breadcrumb_done "3: issue — created #${ISSUE_NUM}"
fi

KV_ISSUE_NUM="$ISSUE_NUM"

# --------------------------------------------------------------------------
# Helper: dump_subprocess_diagnostics (issue #399 remedy (b))
# --------------------------------------------------------------------------
#
# dump_subprocess_diagnostics <label> <out-file>
#
# Emits to stdout (in order): a breadcrumb_warn signal for Monitor filters,
# a banner, the FULL stderr sidecar (${out_file}.stderr), another banner,
# the LAST 50 lines of <out-file>, and a closing banner. Both diagnostic
# streams are piped through redact-secrets.sh. The stdout tail is also
# spoof-guarded with `sed` so that any accidental `### iteration-result`
# line inside the model output cannot shift the driver's KV-footer parse
# window (parse_kv awk at driver.sh:355-361 flips in_block on the FIRST
# header match).
#
# Appears BEFORE emit_kv_footer (which runs in the EXIT trap), so the KV
# footer is still the last stdout block and KV parse integrity is preserved.
#
# shellcheck disable=SC2317  # called from invoke_claude_p / helper paths
dump_subprocess_diagnostics() {
  local label="$1" out_file="$2" stderr_file="${2}.stderr"
  local redact="${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh"
  breadcrumb_warn "${label}: subprocess non-zero; dumping diagnostics (redacted)."
  printf '── subprocess stderr (label=%s) ──\n' "$label"
  if [[ -s "$stderr_file" ]]; then
    if [[ -x "$redact" ]]; then
      "$redact" < "$stderr_file" || printf '(redaction failed; omitting stderr)\n'
    else
      printf '(redact-secrets.sh unavailable; omitting stderr)\n'
    fi
  else
    printf '(stderr empty)\n'
  fi
  printf '── subprocess stdout tail (label=%s, last 50 lines) ──\n' "$label"
  if [[ -s "$out_file" ]]; then
    if [[ -x "$redact" ]]; then
      tail -n 50 "$out_file" \
        | sed 's/^### iteration-result/### (banner-redacted)/' \
        | "$redact" || printf '(redaction failed; omitting stdout tail)\n'
    else
      printf '(redact-secrets.sh unavailable; omitting stdout tail)\n'
    fi
  else
    printf '(stdout empty)\n'
  fi
  printf '── end subprocess diagnostics (label=%s) ──\n' "$label"
}

# --------------------------------------------------------------------------
# Helper: dump_helper_stderr (issue #399 remedy (c))
# --------------------------------------------------------------------------
#
# dump_helper_stderr <label> <stderr-sidecar-path>
#
# Emits a redacted dump of a helper-script stderr sidecar (non claude -p —
# used for gh issue comment / gh issue create). Also sets the cross-boundary
# preserve sentinel when $WORK_DIR is populated so the driver's cleanup_on_exit
# can pick up the signal (issue #399 FINDING_4).
#
# shellcheck disable=SC2317
dump_helper_stderr() {
  local label="$1" stderr_file="$2"
  local redact="${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh"
  breadcrumb_warn "${label}: helper failure; dumping stderr (redacted)."
  printf '── helper stderr (label=%s) ──\n' "$label"
  if [[ -s "$stderr_file" ]]; then
    if [[ -x "$redact" ]]; then
      "$redact" < "$stderr_file" || printf '(redaction failed; omitting stderr)\n'
    else
      printf '(redact-secrets.sh unavailable; omitting stderr)\n'
    fi
  else
    printf '(stderr empty)\n'
  fi
  printf '── end helper stderr (label=%s) ──\n' "$label"
  PRESERVE_WORK_DIR="true"
  if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
    : > "$WORK_DIR/preserve.sentinel" 2>/dev/null || true
  fi
}

# --------------------------------------------------------------------------
# Helper: invoke_claude_p
# --------------------------------------------------------------------------
#
# invoke_claude_p <prompt-file> <out-file> <phase-label> <timeout-seconds>
#
# Reads prompt from <prompt-file> via STDIN (FINDING_9: avoids argv ARG_MAX
# exhaustion on large plans; macOS ARG_MAX default is 262144).
# Stdout is captured to <out-file>; stderr to <out-file>.stderr sidecar
# (FINDING_10: stderr MUST NOT be posted to public gh issue comments).
# Background-poll pattern (no external `timeout`/`gtimeout` dependency).
# Returns child exit code (0 on success; 124 on timeout). On non-zero rc
# (issue #399 remedy (b)), emits a redacted subprocess-diagnostics block to
# stdout before returning.
invoke_claude_p() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1200}"
  local stderr_file="${out_file}.stderr"
  local rc=0

  : > "$out_file"
  : > "$stderr_file"

  (
    cd "$REPO_ROOT"
    claude -p --plugin-dir "$CLAUDE_PLUGIN_ROOT" \
      < "$prompt_file" > "$out_file" 2> "$stderr_file" &
    # Subshell variables are already isolated from the parent function;
    # no `local` keyword needed (and `local` inside `( ... )` outside a
    # function is an easy-to-misread annotation).
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

  if [[ "$rc" -ne 0 ]]; then
    dump_subprocess_diagnostics "$label" "$out_file"
  fi
  return "$rc"
}

# post_gh_comment <body-file> <label>
# Redacts via redact-secrets.sh, posts with gh issue comment. Warns on
# failure; never fails the iteration (non-fatal: loop still wants the KV
# footer even if gh posts fail).
post_gh_comment() {
  local body_file="$1"
  local label="$2"
  local redacted="${body_file}.redacted"
  local gh_stderr="${body_file}.gh-comment.stderr"
  "${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh" < "$body_file" > "$redacted"
  if ! gh issue comment "$ISSUE_NUM" --body-file "$redacted" 2> "$gh_stderr"; then
    breadcrumb_warn "gh issue comment failed for ${label}. Continuing."
    dump_helper_stderr "gh-comment-${label}" "$gh_stderr"
  fi
}

# --------------------------------------------------------------------------
# detect_plan_status — transplanted byte-close from pre-#273 driver.sh
# --------------------------------------------------------------------------
#
# Returns on stdout: plan_ok | no_plan | design_refusal
detect_plan_status() {
  local design_out="$1"
  if [[ ! -s "$design_out" ]]; then
    printf 'no_plan\n'
    return 0
  fi
  if LC_ALL=C grep -qiE '^(error:|error -|refus(ed|al)|cannot (run|proceed|execute)|/design (failed|could not run|is unavailable))' "$design_out"; then
    printf 'design_refusal\n'
    return 0
  fi
  local first_line
  first_line="$(awk 'NF {print; exit}' "$design_out" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | tr '[:upper:]' '[:lower:]')"
  first_line="$(printf '%s' "$first_line" | sed -E 's/^[*_]+//; s/[*_]+$//')"
  first_line="$(printf '%s' "$first_line" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')"
  while :; do
    case "$first_line" in
      *.|*!|*\?|*\;|*,)
        first_line="${first_line%?}"
        ;;
      *)
        break ;;
    esac
  done
  local has_structural="no"
  if LC_ALL=C grep -qE '^#{1,6}[[:space:]]|^[1-9][0-9]?\.[[:space:]]|^[-*+][[:space:]]' "$design_out"; then
    has_structural="yes"
  fi
  case "$first_line" in
    "no plan"|"no improvements"|"nothing to improve"|"already optimal"|"skill is already high quality")
      if [[ "$has_structural" == "no" ]]; then
        printf 'no_plan\n'
        return 0
      fi
      ;;
  esac
  printf 'plan_ok\n'
}

# --------------------------------------------------------------------------
# write_infeasibility — transplanted from pre-#273 driver.sh
# --------------------------------------------------------------------------
write_infeasibility() {
  local status="$1"
  local parse_status="${2:-unknown}"
  local grade_a="${3:-false}"
  local non_a="${4:-}"
  local inf_file="$WORK_DIR/iter-${ITER_NUM}-infeasibility.md"
  local tmp_file="${inf_file}.tmp"
  local reason why_blocks
  case "$status" in
    no_plan)
      reason="/design emitted no-plan sentinel despite Non-A dimensions ${non_a}"
      why_blocks="/design could not articulate a plan for the listed Non-A dimensions despite the focus block — without a plan there is no implementation candidate."
      ;;
    design_refusal)
      reason="/design returned structured refusal — see iter-${ITER_NUM}-design.txt for the verbatim response"
      why_blocks="/design itself failed to run, so no plan could be produced. A later iteration would need a different target-skill framing or external context."
      ;;
    im_verification_failed)
      reason="/im did not reach its canonical completion line — see iter-${ITER_NUM}-im.txt; the iteration produced design output (iter-${ITER_NUM}-design.txt) but the implementation pipeline could not be verified as complete."
      why_blocks="A plan was produced but could not be landed safely (CI failure, merge conflict, or pipeline halt) — the failed plan would need a different approach to make progress."
      ;;
    *)
      reason="unknown status '${status}'"
      why_blocks="Unknown halt status; see per-iteration tmp files for context."
      ;;
  esac
  {
    printf '## Infeasibility Justification — iteration %s\n\n' "${ITER_NUM}"
    printf '**Status**: %s\n\n' "${status}"
    printf '**Reason**: %s\n\n' "${reason}"
    printf '**Context**:\n'
    printf -- '- Grade parse at start of iteration: PARSE_STATUS=%s, GRADE_A=%s, non-A dimensions: %s\n' "${parse_status}" "${grade_a}" "${non_a}"
    printf -- '- Judge output: iter-%s-judge.txt\n' "${ITER_NUM}"
    printf -- '- Design output (if any): iter-%s-design.txt\n' "${ITER_NUM}"
    printf -- '- /im output (if any): iter-%s-im.txt\n\n' "${ITER_NUM}"
    printf '**Why this blocks reaching grade A**: %s\n' "${why_blocks}"
  } > "$tmp_file"
  mv "$tmp_file" "$inf_file"
}

# --------------------------------------------------------------------------
# Step 4 — Phase 1: /skill-judge
# --------------------------------------------------------------------------

breadcrumb_inprogress "4.j: judge"

JUDGE_PROMPT="$WORK_DIR/iter-${ITER_NUM}-judge-prompt.txt"
JUDGE_OUT="$WORK_DIR/iter-${ITER_NUM}-judge.txt"

printf '/skill-judge:skill-judge %s (absolute SKILL.md path: %s) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.\n' \
  "${SKILL_NAME}" "${TARGET_SKILL_PATH}" > "$JUDGE_PROMPT"

if ! invoke_claude_p "$JUDGE_PROMPT" "$JUDGE_OUT" "judge" 1200; then
  breadcrumb_warn "4.j: judge — claude -p failed. Aborting iteration."
  KV_ITER_STATUS="judge_failed"
  KV_EXIT_REASON="subprocess failure at /skill-judge iteration ${ITER_NUM}"
  exit 0
fi

if [[ ! -s "$JUDGE_OUT" ]]; then
  breadcrumb_warn "4.j: judge — empty output from /skill-judge subprocess. Aborting iteration."
  KV_ITER_STATUS="judge_failed"
  KV_EXIT_REASON="empty /skill-judge output at iteration ${ITER_NUM}"
  exit 0
fi

# ----- Phase 1.v: grade parse -----------------------------------------

breadcrumb_inprogress "4.j.v: grade parse"

GRADE_OUT="$WORK_DIR/iter-${ITER_NUM}-grade.txt"
GRADE_TMP="${GRADE_OUT}.tmp"
"${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh" "$JUDGE_OUT" > "$GRADE_TMP"
mv "$GRADE_TMP" "$GRADE_OUT"

KV_PARSE_STATUS="$(awk -F= '/^PARSE_STATUS=/{print $2; exit}' "$GRADE_OUT")"
KV_GRADE_A="$(awk -F= '/^GRADE_A=/{print $2; exit}' "$GRADE_OUT")"
KV_NON_A_DIMS="$(awk -F= '/^NON_A_DIMS=/{print $2; exit}' "$GRADE_OUT")"
KV_TOTAL_NUM="$(awk -F= '/^TOTAL_NUM=/{print $2; exit}' "$GRADE_OUT")"
KV_TOTAL_DEN="$(awk -F= '/^TOTAL_DEN=/{print $2; exit}' "$GRADE_OUT")"

# Append grade-history.txt so the loop driver's close-out picks up the row.
if [[ "$KV_PARSE_STATUS" == "ok" ]]; then
  printf 'iter=%s total=%s/%s non_a=%s parse_status=ok\n' \
    "${ITER_NUM}" "${KV_TOTAL_NUM}" "${KV_TOTAL_DEN}" "${KV_NON_A_DIMS}" \
    >> "$WORK_DIR/grade-history.txt"
else
  printf 'iter=%s total=N/A non_a=N/A parse_status=%s\n' \
    "${ITER_NUM}" "${KV_PARSE_STATUS:-unknown}" \
    >> "$WORK_DIR/grade-history.txt"
fi

# Post judge comment (redacted)
JUDGE_COMMENT_FILE="$WORK_DIR/iter-${ITER_NUM}-judge-comment.md"
{
  printf '## Iteration %s — /skill-judge\n\n' "${ITER_NUM}"
  cat "$JUDGE_OUT"
} > "$JUDGE_COMMENT_FILE"
post_gh_comment "$JUDGE_COMMENT_FILE" "iter ${ITER_NUM} judge"

# Grade-A short-circuit
if [[ "$KV_GRADE_A" == "true" && "$KV_PARSE_STATUS" == "ok" ]]; then
  KV_ITER_STATUS="grade_a"
  KV_EXIT_REASON="grade A achieved on all dimensions at iteration ${ITER_NUM}"
  breadcrumb_done "4.j.v: grade parse — grade A achieved (iteration done)"
  exit 0
fi

breadcrumb_done "4.j.v: grade parse — non-A (${KV_NON_A_DIMS:-?}); continuing to /design"

# --------------------------------------------------------------------------
# Step 4 — Phase 2: /design (with amended prompt — pushback carve-out)
# --------------------------------------------------------------------------

breadcrumb_inprogress "4.d: design"

DESIGN_PROMPT="$WORK_DIR/iter-${ITER_NUM}-design-prompt.txt"
DESIGN_OUT="$WORK_DIR/iter-${ITER_NUM}-design.txt"

# Per-dimension deficit lines when PARSE_STATUS=ok AND GRADE_A=false
build_deficit_lines() {
  local line=""
  for d in D1 D2 D3 D4 D5 D6 D7 D8; do
    local num den thr
    num="$(awk -F= -v k="${d}_NUM" '$1==k{print $2; exit}' "$GRADE_OUT")"
    den="$(awk -F= -v k="${d}_DEN" '$1==k{print $2; exit}' "$GRADE_OUT")"
    [[ -z "$num" || -z "$den" ]] && continue
    case "$d" in
      D1) thr=18 ;;
      D7) thr=9 ;;
      *)  thr=14 ;;
    esac
    if [[ "$num" -lt "$thr" ]]; then
      local delta=$(( thr - num ))
      line+="  ${d} at ${num}/${den} (needs >=${thr} for A; short by ${delta})"$'\n'
    fi
  done
  printf '%s' "$line"
}

{
  printf '/larch:design Improve /%s at %s' "${SKILL_NAME}" "${TARGET_SKILL_PATH}"
  if [[ "$KV_PARSE_STATUS" == "ok" && "$KV_GRADE_A" == "false" ]]; then
    printf ' focused on %s (the Non-A dimensions from this iteration'"'"'s /skill-judge).' "${KV_NON_A_DIMS}"
    printf '\n\nNon-A dimensions from this iteration'"'"'s /skill-judge: %s.\n' "${KV_NON_A_DIMS}"
    printf 'Per-dimension deficits (current/required):\n'
    build_deficit_lines
    printf 'Focus this iteration'"'"'s plan on raising these dimensions to grade A.\n'
    printf 'Treat this deficit list as the canonical set of must-address findings — do NOT self-curtail on the grounds that these are "minor". The loop'"'"'s termination contract requires per-dimension A on ALL D1..D8; any non-A dimension is load-bearing for forward progress.\n\n'
  else
    printf '.\n\n'
  fi
  # Rule 1: no self-curtailment on minor/cosmetic findings.
  printf '/design MUST produce a concrete, implementable plan for ANY actionable /skill-judge finding — including findings classified "minor", "nit", or cosmetic. Treat "minor" as "small plan", not as "no plan".\n\n'
  # Rule 2: no self-curtailment on budget grounds.
  printf '/design MUST NOT self-curtail citing token/context budget. Under any perceived pressure, narrow scope to the single highest-leverage finding and emit a compressed micro-plan that still conforms to the standard /design plan schema (## Implementation Plan with Files to modify/create, Approach, Edge cases, Testing strategy, and Failure modes when the change is non-trivial per /design'"'"'s own rules) — never emit a no-plan sentinel on budget grounds.\n\n'
  # Rule 3: no no-plan sentinels when findings exist.
  printf '/design MUST NOT emit any of the no-plan sentinel phrases (no plan, no improvements, nothing to improve, already optimal, skill is already high quality) when /skill-judge surfaced any actionable finding. Sentinels are reserved for the genuine case where no improvement is warranted.\n\n'
  # Rule 4 (NEW — narrow per-finding pushback carve-out).
  # shellcheck disable=SC2016  # backticks in literal prose (Pushback subsection name cited as markdown), not command substitution
  printf '/design MAY disagree with specific /skill-judge findings that appear erroneous — skill-judge is not infallible, and a rigorous plan should push back on findings that misread the target skill or misapply the judging rubric. If /design wishes to push back on any finding, the plan MUST include a dedicated `## Pushback on judge findings` subsection at its end. Each pushback entry MUST: (a) identify the specific finding (which dimension it came from + a short excerpt of the finding text), (b) state why the finding is erroneous or misapplied to this skill with specific reasoning, and (c) cite concrete codebase evidence (file:line references, or verbatim quotes from the target skill'"'"'s SKILL.md or scripts) supporting the pushback. This carve-out is strictly per-finding — the plan MUST still address every undisputed non-A dimension with concrete, implementable steps. Pushing back on a finding DOES NOT remove the dimension from the Non-A list; the judge may re-surface it next iteration. This carve-out does NOT override rules 1-3 above: under no circumstances may /design emit a no-plan sentinel, self-curtail on budget grounds, or omit a plan for findings it does not explicitly push back on.\n\n'
  printf 'TARGET_SKILL_PATH is absolute: %s.\n' "${TARGET_SKILL_PATH}"
} > "$DESIGN_PROMPT"

if ! invoke_claude_p "$DESIGN_PROMPT" "$DESIGN_OUT" "design" 1800; then
  breadcrumb_warn "4.d: design — claude -p failed."
  KV_ITER_STATUS="design_refusal"
  KV_EXIT_REASON="subprocess failure at /design iteration ${ITER_NUM}"
  write_infeasibility "design_refusal" "$KV_PARSE_STATUS" "$KV_GRADE_A" "$KV_NON_A_DIMS"
  exit 0
fi

PLAN_STATUS="$(detect_plan_status "$DESIGN_OUT")"

# Rescue re-invocation (at most once) — when output non-empty but has no
# structural-plan markers (no headings, numbered lists, or bullets). Same
# semantics as pre-#273 driver.sh.
if [[ "$PLAN_STATUS" == "plan_ok" ]]; then
  if [[ -s "$DESIGN_OUT" ]] && \
     ! LC_ALL=C grep -qE '^#{1,6}[[:space:]]|^[1-9][0-9]?\.[[:space:]]|^[-*+][[:space:]]' "$DESIGN_OUT"; then
    breadcrumb_inprogress "4.d: design — rescue (no structural markers; re-invoking /design --auto)"
    RESCUE_PROMPT="$WORK_DIR/iter-${ITER_NUM}-design-rescue-prompt.txt"
    {
      printf '/larch:design --auto Re-emit a concrete plan for /%s at %s.\n\n' "${SKILL_NAME}" "${TARGET_SKILL_PATH}"
      # shellcheck disable=SC2016  # backticks inside literal prose, not command substitution
      printf 'Your previous response had no structured-plan markers (no markdown headings, numbered list counters, or bulleted items). Focus this re-attempt exclusively on the single highest-leverage /skill-judge finding from this iteration. The re-attempt MUST use /design'"'"'s standard plan schema: a top-level `## Implementation Plan` section with `Files to modify/create`, `Approach`, `Edge cases`, `Testing strategy`, and `Failure modes` subheadings. No preamble prose. No budget excuses. No no-plan sentinels.\n\n'
      printf 'Non-A dimensions were: %s.\n' "${KV_NON_A_DIMS}"
    } > "$RESCUE_PROMPT"
    # Rescue is best-effort (design continues even on failure), but we still
    # want diagnostics captured when it fails — invoke_claude_p already dumps
    # on rc!=0 before returning, so `|| true` only swallows the exit code.
    invoke_claude_p "$RESCUE_PROMPT" "$DESIGN_OUT" "design-rescue" 1800 || true
    PLAN_STATUS="$(detect_plan_status "$DESIGN_OUT")"
  fi
fi

case "$PLAN_STATUS" in
  no_plan)
    KV_ITER_STATUS="no_plan"
    KV_EXIT_REASON="no plan at iteration ${ITER_NUM}"
    write_infeasibility "no_plan" "$KV_PARSE_STATUS" "$KV_GRADE_A" "$KV_NON_A_DIMS"
    breadcrumb_done "4.d: design — no_plan (iteration done)"
    exit 0
    ;;
  design_refusal)
    KV_ITER_STATUS="design_refusal"
    KV_EXIT_REASON="/design refusal or error at iteration ${ITER_NUM}"
    write_infeasibility "design_refusal" "$KV_PARSE_STATUS" "$KV_GRADE_A" "$KV_NON_A_DIMS"
    breadcrumb_done "4.d: design — design_refusal (iteration done)"
    exit 0
    ;;
  plan_ok)
    PLAN_COMMENT_FILE="$WORK_DIR/iter-${ITER_NUM}-plan-comment.md"
    {
      printf '## Iteration %s — design plan\n\n' "${ITER_NUM}"
      cat "$DESIGN_OUT"
    } > "$PLAN_COMMENT_FILE"
    post_gh_comment "$PLAN_COMMENT_FILE" "iter ${ITER_NUM} plan"
    breadcrumb_done "4.d: design — plan posted"
    ;;
esac

# --------------------------------------------------------------------------
# Step 4 — Phase 3: /im
# --------------------------------------------------------------------------

breadcrumb_inprogress "4.i: im"

IM_PROMPT="$WORK_DIR/iter-${ITER_NUM}-im-prompt.txt"
IM_OUT="$WORK_DIR/iter-${ITER_NUM}-im.txt"

# NO_SLACK_FLAG is either empty or "--no-slack " (trailing space). Prepending
# here makes this iteration's /larch:im suppress Slack posting when --no-slack
# was passed to iteration.sh; default is to post per /implement's default-on
# behavior (gated on Slack env vars).
{
  printf '/larch:im %s' "$NO_SLACK_FLAG"
  cat "$DESIGN_OUT"
} > "$IM_PROMPT"

if ! invoke_claude_p "$IM_PROMPT" "$IM_OUT" "im" 3600; then
  breadcrumb_warn "4.i: im — claude -p failed."
  KV_ITER_STATUS="im_verification_failed"
  KV_EXIT_REASON="/im subprocess failure at iteration ${ITER_NUM}"
  write_infeasibility "im_verification_failed" "$KV_PARSE_STATUS" "$KV_GRADE_A" "$KV_NON_A_DIMS"
  exit 0
fi

# Mechanical gate: verify-skill-called.sh --stdout-line '^✅ 18: cleanup'
VERIFY_OUT="$("${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
  --stdout-line '^✅ 18: cleanup' --stdout-file "$IM_OUT" 2>/dev/null || printf 'VERIFIED=false\nREASON=verify_script_error\n')"
VERIFIED="$(printf '%s\n' "$VERIFY_OUT" | awk -F= '/^VERIFIED=/{print $2; exit}')"

if [[ "$VERIFIED" != "true" ]]; then
  KV_ITER_STATUS="im_verification_failed"
  KV_EXIT_REASON="/im did not reach canonical completion line at iteration ${ITER_NUM}"
  write_infeasibility "im_verification_failed" "$KV_PARSE_STATUS" "$KV_GRADE_A" "$KV_NON_A_DIMS"
  breadcrumb_done "4.i: im — verification failed (iteration done)"
  exit 0
fi

breadcrumb_done "4.i: im — verified"

# --------------------------------------------------------------------------
# Step 5 — Success
# --------------------------------------------------------------------------

KV_ITER_STATUS="ok"
KV_EXIT_REASON="iteration ${ITER_NUM} completed (continue loop)"

breadcrumb_done "5: iteration complete"

exit 0
