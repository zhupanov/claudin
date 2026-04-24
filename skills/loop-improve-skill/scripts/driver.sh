#!/usr/bin/env bash
# driver.sh — Bash driver for /loop-improve-skill (Option B topology, closes #273).
#
# Factored refactor: the per-iteration body (judge → design → im) lives in
# `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh` — the
# shared kernel also invoked standalone by `/improve-skill`. This driver
# owns only loop-specific concerns: tracking-issue creation, the up-to-10-
# round while loop, grade-history aggregation, post-iter-cap final
# `/skill-judge` re-evaluation, close-out composition, and cleanup.
#
# Halt class eliminated by construction: iteration.sh is invoked via direct
# bash call (not `claude -p`) so there is no post-child-return model turn
# to halt between iteration return and this driver's post-call Bash.
#
# Usage:
#   driver.sh [--no-slack] <skill-name>
#
# Arguments:
#   --no-slack    — optional flag, must precede <skill-name>. Prepended to
#                   every iteration.sh invocation so no iteration's
#                   /larch:im posts to Slack. Default: absent — each
#                   iteration's /implement run posts per its default-on
#                   behavior (gated on Slack env vars).
#   <skill-name>  — target larch skill; leading `/` stripped; must match
#                   `^[a-z][a-z0-9-]*$`.
#
# Topology (post-refactor):
#   Step 1 — argv parse, 3-probe skill lookup, gh/claude pre-flight
#   Step 2 — session-setup.sh → LOOP_TMPDIR
#   Step 3 — gh issue create (the tracking issue is created ONCE by the loop
#             driver; iteration.sh always receives --issue "$ISSUE_NUM")
#   Step 4 — while ITER=1..10: invoke iteration.sh with --work-dir "$LOOP_TMPDIR"
#             --iter-num "$ITER" --issue "$ISSUE_NUM" [--no-slack] "$SKILL_NAME";
#             parse the KV footer from iteration.sh's stdout (via awk on the
#             `### iteration-result` block); break on terminal ITER_STATUS
#             (grade_a / no_plan / design_refusal / im_verification_failed /
#             judge_failed) with byte-compatible EXIT_REASON strings.
#   Step 5a — iter-cap path only: run one final /skill-judge (via a slim
#             local invoke_claude_p helper that preserves FINDING_9 STDIN +
#             FINDING_10 stderr-sidecar contracts) to capture the post-cap
#             grade. May reclassify EXIT_REASON to "grade A achieved after
#             final post-iter-cap re-evaluation" if grade A was reached by
#             the last /im.
#   Step 5b — compose close-out body (summary + Grade History +
#             conditional Infeasibility Justification + Final Assessment).
#   Step 5c — post close-out comment (redacted via redact-secrets.sh),
#             write closeout.sentinel.
#   Step 6  — cleanup-tmpdir.sh via EXIT trap.
#
# LARCH_ITERATION_SCRIPT_OVERRIDE is an advisory env var used ONLY by
# `scripts/test-loop-improve-skill-driver.sh` Tier-2 fixtures to redirect
# iteration.sh invocations at a stub shim. Never set in production.
#
# Security posture (mirrors pre-refactor boundaries, see SECURITY.md):
#   - LOOP_TMPDIR MUST begin with /tmp/ or /private/tmp/ AND MUST NOT contain
#     `..` as a path component.
#   - Iteration artifacts (iter-${ITER}-*.txt, iter-${ITER}-infeasibility.md,
#     grade-history.txt) accumulate in LOOP_TMPDIR via iteration.sh's
#     --work-dir $LOOP_TMPDIR pattern; close-out reads them at byte-identical
#     paths from the pre-refactor driver.
#   - All gh comment bodies piped through redact-secrets.sh before posting.
#   - The retained slim invoke_claude_p (used only for the Step 5a post-iter-
#     cap re-judge) preserves FINDING_9 STDIN + FINDING_10 stderr-sidecar
#     contracts.
#   - $LOOP_TMPDIR always cleaned via EXIT trap.

set -euo pipefail

# Derive CLAUDE_PLUGIN_ROOT from script location when the harness did not
# export it. Layout:
#   ${CLAUDE_PLUGIN_ROOT}/skills/loop-improve-skill/scripts/driver.sh
# so the plugin root is three directories up from the script.
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
  export CLAUDE_PLUGIN_ROOT
fi

# --------------------------------------------------------------------------
# Breadcrumb helpers (match larch progress convention)
# --------------------------------------------------------------------------

breadcrumb_inprogress() { printf '> **🔶 %s**\n' "$*"; }
breadcrumb_done()       { printf '✅ %s\n' "$*"; }
# shellcheck disable=SC2317  # reserved for future skip messages; keep symmetry with other helpers
breadcrumb_skip()       { printf '⏩ %s\n' "$*"; }
breadcrumb_warn()       { printf '**⚠ %s**\n' "$*"; }

# --------------------------------------------------------------------------
# Cleanup trap (always runs)
# --------------------------------------------------------------------------

LOOP_TMPDIR=""
# shellcheck disable=SC2317  # invoked via trap on EXIT
cleanup_on_exit() {
  local rc=$?
  if [[ -n "$LOOP_TMPDIR" && -d "$LOOP_TMPDIR" ]]; then
    if [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/cleanup-tmpdir.sh" ]]; then
      "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh" --dir "$LOOP_TMPDIR" || true
    fi
  fi
  return "$rc"
}
trap cleanup_on_exit EXIT

# --------------------------------------------------------------------------
# Step 1 — Parse + validate flags and <skill-name>
# --------------------------------------------------------------------------

NO_SLACK_FLAG=""  # empty by default; set to "--no-slack " if --no-slack is present
while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-slack) NO_SLACK_FLAG="--no-slack "; shift ;;
    --) shift; break ;;
    --*)
      breadcrumb_warn "1: parse args — unknown flag '$1'. Valid flags: --no-slack."
      exit 1
      ;;
    *) break ;;
  esac
done

if [[ $# -lt 1 ]]; then
  breadcrumb_warn "1: parse args — missing <skill-name>. Usage: driver.sh [--no-slack] <skill-name>"
  exit 1
fi

SKILL_NAME="${1#/}"  # strip a single leading /

if ! [[ "$SKILL_NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  breadcrumb_warn "1: parse args — invalid <skill-name> '$SKILL_NAME' (must match ^[a-z][a-z0-9-]*\$). Aborting."
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
  exit 1
fi

breadcrumb_done "1: parse args — target /${SKILL_NAME} at ${TARGET_SKILL_PATH}"

# --------------------------------------------------------------------------
# Pre-flight: gh auth, claude CLI
# --------------------------------------------------------------------------

if ! command -v claude >/dev/null 2>&1; then
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

# --------------------------------------------------------------------------
# Step 2 — Session setup (LOOP_TMPDIR)
# --------------------------------------------------------------------------

breadcrumb_inprogress "2: session setup"

# FINDING_11 opt-in: LOOP_IMPROVE_SKIP_PREFLIGHT=1 adds --skip-preflight so the
# regression harness can exercise the driver's control-flow under a mktemp'd
# fixture workdir (which is not a real git repo with an origin/main). Never
# enable in production.
SETUP_EXTRA_FLAGS=()
if [[ "${LOOP_IMPROVE_SKIP_PREFLIGHT:-}" == "1" ]]; then
  SETUP_EXTRA_FLAGS+=("--skip-preflight")
fi

# FINDING_8: guard command substitution so a non-zero exit surfaces through a
# breadcrumb rather than silently aborting under `set -e`.
SETUP_OUT=""
if ! SETUP_OUT="$("${CLAUDE_PLUGIN_ROOT}"/scripts/session-setup.sh \
    --prefix claude-loop-improve \
    --skip-branch-check \
    --skip-slack-check \
    --skip-repo-check \
    ${SETUP_EXTRA_FLAGS[@]+"${SETUP_EXTRA_FLAGS[@]}"} 2>&1)"; then
  printf '%s\n' "$SETUP_OUT" >&2
  breadcrumb_warn "2: session setup — session-setup.sh exited non-zero. Aborting."
  exit 1
fi

LOOP_TMPDIR="$(printf '%s\n' "$SETUP_OUT" | awk -F= '/^SESSION_TMPDIR=/{print substr($0, index($0,"=")+1); exit}')"

if [[ -z "$LOOP_TMPDIR" ]]; then
  breadcrumb_warn "2: session setup — failed to parse SESSION_TMPDIR. Aborting."
  exit 1
fi

# Validate LOOP_TMPDIR security boundary (prefix + no `..` traversal).
if ! [[ "$LOOP_TMPDIR" == /tmp/* || "$LOOP_TMPDIR" == /private/tmp/* ]]; then
  breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' does not begin with /tmp/ or /private/tmp/. Aborting."
  exit 1
fi
case "$LOOP_TMPDIR" in
  */..|*/../*)
    breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' contains '..' path component. Aborting."
    exit 1 ;;
esac

# One-shot forensic capture (advisory only; failure ignored)
claude --version > "$LOOP_TMPDIR/claude-version.txt" 2>/dev/null || true

breadcrumb_done "2: session setup — LOOP_TMPDIR=${LOOP_TMPDIR}"

# --------------------------------------------------------------------------
# Step 3 — Create tracking GitHub issue
# --------------------------------------------------------------------------

breadcrumb_inprogress "3: create issue"

ISSUE_BODY_FILE="$LOOP_TMPDIR/issue-body.md"
{
  # shellcheck disable=SC2016  # backticks inside literal prose (issue body), not command substitution
  printf 'Iteratively improve /%s via /loop-improve-skill. Runs up to 10 rounds of /skill-judge + /design + /im via the shared iteration kernel at `${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh`, invoked once per iteration from this driver (topology #273; factored out as /improve-skill). Exits when every /skill-judge dimension reaches grade A, or when an infeasibility halt (no_plan / design_refusal / im_verification_failed, with written justification appended below) or the 10-iteration cap is reached.\n\n' "${SKILL_NAME}"
  printf 'Target: %s\n' "${TARGET_SKILL_PATH}"
} > "$ISSUE_BODY_FILE"

ISSUE_URL="$(gh issue create \
  --title "Improve /${SKILL_NAME} skill via loop-improve-skill" \
  --body-file "$ISSUE_BODY_FILE")" || {
  breadcrumb_warn "3: create issue — gh issue create failed. Aborting."
  exit 1
}

# Parse trailing issue number (e.g. https://github.com/org/repo/issues/123)
ISSUE_NUM="$(printf '%s\n' "$ISSUE_URL" | awk -F/ '/issues\//{print $NF; exit}')"
if ! [[ "$ISSUE_NUM" =~ ^[0-9]+$ ]]; then
  breadcrumb_warn "3: create issue — could not parse issue number from '$ISSUE_URL'. Aborting."
  exit 1
fi

breadcrumb_done "3: create issue — #${ISSUE_NUM}"

# --------------------------------------------------------------------------
# Helper: invoke_claude_p (slim — used only for Step 5a post-iter-cap re-judge)
# --------------------------------------------------------------------------
#
# Preserved here (instead of reusing iteration.sh) so the final re-judge has
# a minimal surface area and the driver test can pin FINDING_9/10 contracts
# against this file directly.
#
# invoke_claude_p <prompt-file> <out-file> <phase-label> <timeout-seconds>
#   - Prompt on STDIN (FINDING_9: avoids argv ARG_MAX on macOS default 262144)
#   - Stderr redirected to <out-file>.stderr sidecar (FINDING_10: never posted)
#   - --plugin-dir "$CLAUDE_PLUGIN_ROOT" (FINDING_7: plugin resolution)
#   - Background-poll pattern (no external `timeout`/`gtimeout` dependency)
invoke_claude_p() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1200}"
  local stderr_file="${out_file}.stderr"

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
  )
}

# --------------------------------------------------------------------------
# Step 4 — Loop (one iteration.sh invocation per round)
# --------------------------------------------------------------------------

# LARCH_ITERATION_SCRIPT_OVERRIDE: advisory env var for Tier-2 test fixtures
# only. Redirects iteration.sh invocations at a stub shim. In production
# environments this MUST be unset; the default resolves to the shipped kernel.
ITERATION_SCRIPT="${LARCH_ITERATION_SCRIPT_OVERRIDE:-${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh}"

if [[ ! -x "$ITERATION_SCRIPT" ]]; then
  breadcrumb_warn "4: loop — iteration script not executable at '$ITERATION_SCRIPT'. Aborting."
  exit 1
fi

ITER=1
EXIT_REASON=""
# Last-seen grade-parse context (used by close-out and Step 5a reclassification).
PARSE_STATUS="unknown"
GRADE_A="false"
NON_A_DIMS=""

while [[ $ITER -le 10 ]]; do
  breadcrumb_inprogress "4: loop — iteration ${ITER}"

  # Invoke iteration.sh. Build argv as an array so flag presence is explicit;
  # conditionally prepend --no-slack when the caller passed it to the driver.
  ITER_OUT="$LOOP_TMPDIR/iter-${ITER}-iteration-stdout.txt"
  ITER_ARGV=()
  if [[ -n "$NO_SLACK_FLAG" ]]; then
    ITER_ARGV+=(--no-slack)
  fi
  ITER_ARGV+=(--issue "$ISSUE_NUM")
  ITER_ARGV+=(--work-dir "$LOOP_TMPDIR")
  ITER_ARGV+=(--iter-num "$ITER")
  ITER_ARGV+=(--breadcrumb-prefix "4.${ITER}")
  ITER_ARGV+=("$SKILL_NAME")

  ITER_RC=0
  "$ITERATION_SCRIPT" "${ITER_ARGV[@]}" > "$ITER_OUT" 2>&1 || ITER_RC=$?

  # Tee iteration stdout to the driver log so Monitor sees the iteration's
  # breadcrumbs + KV footer. The iteration.sh kernel writes to stdout;
  # capture it and re-emit here so the driver's stdout (which the SKILL.md
  # Monitor-tail filter reads) surfaces the kernel's progress.
  cat "$ITER_OUT"

  # Parse KV footer from the iteration.sh stdout capture. The footer is
  # delimited by a `### iteration-result` header line and contains 9 KV
  # lines. Scope the awk match to post-header lines so a pre-block line
  # shaped `KEY=VAL` (e.g., a stray subprocess diagnostic) cannot spoof
  # the parse.
  parse_kv() {
    local key="$1"
    awk -F= -v k="${key}" '
      /^### iteration-result/ { in_block=1; next }
      in_block && $0 ~ "^" k "=" {print substr($0, length(k)+2); exit}
    ' "$ITER_OUT"
  }

  ITER_STATUS="$(parse_kv ITER_STATUS)"
  EXIT_REASON_ITER="$(parse_kv EXIT_REASON)"
  # PARSE_STATUS / GRADE_A / NON_A_DIMS are extracted for diagnostic transparency
  # (they surface in close-out prose and in the Grade History; iteration.sh already
  # appends the grade-history.txt line itself, but extracting here keeps the driver
  # aware of the last-iteration context for Step 5a's reclassification path and for
  # any future close-out enrichment that inspects per-iteration parse health).
  # shellcheck disable=SC2034  # consumed by future close-out enrichment; kept for diagnostic parity with KV footer schema
  PARSE_STATUS="$(parse_kv PARSE_STATUS)"
  # shellcheck disable=SC2034  # same rationale
  GRADE_A="$(parse_kv GRADE_A)"
  # shellcheck disable=SC2034  # same rationale
  NON_A_DIMS="$(parse_kv NON_A_DIMS)"

  if [[ -z "$ITER_STATUS" ]]; then
    breadcrumb_warn "4: loop — iteration ${ITER} did not emit a KV footer (stdout missing '### iteration-result' block). Treating as subprocess failure."
    EXIT_REASON="subprocess failure at iteration ${ITER}: no KV footer (rc=${ITER_RC})"
    break
  fi

  case "$ITER_STATUS" in
    grade_a)
      EXIT_REASON="${EXIT_REASON_ITER:-grade A achieved on all dimensions at iteration ${ITER}}"
      breadcrumb_done "4: loop — grade A achieved at iteration ${ITER} (break)"
      break
      ;;
    no_plan)
      EXIT_REASON="${EXIT_REASON_ITER:-no plan at iteration ${ITER}}"
      breadcrumb_done "4: loop — iteration ${ITER}: no_plan (break)"
      break
      ;;
    design_refusal)
      EXIT_REASON="${EXIT_REASON_ITER:-/design refusal or error at iteration ${ITER}}"
      breadcrumb_done "4: loop — iteration ${ITER}: design_refusal (break)"
      break
      ;;
    im_verification_failed)
      EXIT_REASON="${EXIT_REASON_ITER:-/im did not reach canonical completion line at iteration ${ITER}}"
      breadcrumb_done "4: loop — iteration ${ITER}: im_verification_failed (break)"
      break
      ;;
    judge_failed)
      EXIT_REASON="${EXIT_REASON_ITER:-subprocess failure at /skill-judge iteration ${ITER}}"
      breadcrumb_done "4: loop — iteration ${ITER}: judge_failed (break)"
      break
      ;;
    ok)
      breadcrumb_done "4: loop — iteration ${ITER} completed; continuing"
      ;;
    *)
      breadcrumb_warn "4: loop — iteration ${ITER} returned unknown ITER_STATUS '${ITER_STATUS}'. Breaking."
      EXIT_REASON="unknown ITER_STATUS '${ITER_STATUS}' at iteration ${ITER}"
      break
      ;;
  esac

  # Advance ITER
  ITER=$(( ITER + 1 ))
done

# Iter-cap path
if [[ -z "$EXIT_REASON" ]]; then
  EXIT_REASON="max iterations (10) reached"
fi

# --------------------------------------------------------------------------
# Step 5a — Final /skill-judge re-evaluation (iter-cap path only)
# --------------------------------------------------------------------------

IT=$(( ITER > 10 ? 10 : ITER ))

if [[ "$EXIT_REASON" == "max iterations (10) reached" ]]; then
  breadcrumb_inprogress "5a: final /skill-judge post-iter-cap"

  FINAL_PROMPT="$LOOP_TMPDIR/final-judge-prompt.txt"
  FINAL_JUDGE_OUT="$LOOP_TMPDIR/final-judge.txt"
  FINAL_GRADE_OUT="$LOOP_TMPDIR/final-grade.txt"

  printf '/skill-judge:skill-judge %s (absolute SKILL.md path: %s) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.\n' \
    "${SKILL_NAME}" "${TARGET_SKILL_PATH}" > "$FINAL_PROMPT"

  if invoke_claude_p "$FINAL_PROMPT" "$FINAL_JUDGE_OUT" "final-judge" 1200; then
    if [[ -s "$FINAL_JUDGE_OUT" ]]; then
      "${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh" "$FINAL_JUDGE_OUT" > "$FINAL_GRADE_OUT"
      F_PARSE="$(awk -F= '/^PARSE_STATUS=/{print $2; exit}' "$FINAL_GRADE_OUT")"
      F_GRADE_A="$(awk -F= '/^GRADE_A=/{print $2; exit}' "$FINAL_GRADE_OUT")"
      F_NON_A="$(awk -F= '/^NON_A_DIMS=/{print $2; exit}' "$FINAL_GRADE_OUT")"
      F_NUM="$(awk -F= '/^TOTAL_NUM=/{print $2; exit}' "$FINAL_GRADE_OUT")"
      F_DEN="$(awk -F= '/^TOTAL_DEN=/{print $2; exit}' "$FINAL_GRADE_OUT")"
      if [[ "$F_PARSE" == "ok" ]]; then
        printf 'iter=final total=%s/%s non_a=%s parse_status=ok\n' \
          "${F_NUM}" "${F_DEN}" "${F_NON_A}" >> "$LOOP_TMPDIR/grade-history.txt"
        if [[ "$F_GRADE_A" == "true" ]]; then
          EXIT_REASON="grade A achieved after final post-iter-cap re-evaluation"
        fi
      else
        printf 'iter=final total=N/A non_a=N/A parse_status=%s\n' \
          "${F_PARSE:-unknown}" >> "$LOOP_TMPDIR/grade-history.txt"
      fi
    fi
  fi

  breadcrumb_done "5a: final /skill-judge post-iter-cap"
fi

# --------------------------------------------------------------------------
# Step 5b — Compose close-out body
# --------------------------------------------------------------------------

breadcrumb_inprogress "5b: compose close-out"

CLOSEOUT_BODY="$LOOP_TMPDIR/closeout-body.md"
{
  printf 'Loop finished. Iterations run: %s. Exit reason: %s.\n\n' "${IT}" "${EXIT_REASON}"

  printf '## Grade History\n\n'
  if [[ -s "$LOOP_TMPDIR/grade-history.txt" ]]; then
    printf '```\n'
    cat "$LOOP_TMPDIR/grade-history.txt"
    printf '```\n\n'
  else
    printf '(no grade parses captured)\n\n'
  fi

  case "$EXIT_REASON" in
    "grade A achieved on all dimensions at iteration "*|"grade A achieved after final post-iter-cap re-evaluation")
      : # no Infeasibility Justification section
      ;;
    "max iterations (10) reached")
      printf '## Infeasibility Justification\n\n'
      printf 'After 10 iterations the skill still does not achieve grade A on every dimension.\n\n'
      if [[ -s "$LOOP_TMPDIR/final-grade.txt" ]] && LC_ALL=C grep -q '^PARSE_STATUS=ok$' "$LOOP_TMPDIR/final-grade.txt"; then
        FINAL_NON_A="$(LC_ALL=C grep '^NON_A_DIMS=' "$LOOP_TMPDIR/final-grade.txt" | head -1 | cut -d= -f2-)"
        printf 'Non-A dimensions in the final post-iter-cap /skill-judge: %s.\n\n' "${FINAL_NON_A}"
        # shellcheck disable=SC2016
        printf 'See `final-judge.txt` (captured at Step 5a) and `grade-history.txt` for the per-iteration trajectory — whether the loop plateaued, regressed, or improved monotonically without reaching A informs whether the remaining gap is likely to yield to additional iterations or requires structural redesign.\n\n'
      else
        # shellcheck disable=SC2016
        printf 'Final /skill-judge assessment unavailable: see Grade History above for the last successful judge parse. Last in-loop judge: `iter-%s-judge.txt`.\n\n' "${IT}"
      fi
      printf '## Final Assessment\n\n'
      # shellcheck disable=SC2016
      printf 'Captured by the post-iter-cap re-judge at Step 5a. The full /skill-judge report is in `final-judge.txt` under the loop tmpdir; the parsed KV summary is in `final-grade.txt`.\n\n'
      ;;
    *)
      printf '## Infeasibility Justification\n\n'
      if [[ -s "$LOOP_TMPDIR/iter-${IT}-infeasibility.md" ]]; then
        cat "$LOOP_TMPDIR/iter-${IT}-infeasibility.md"
        printf '\n'
      else
        # shellcheck disable=SC2016
        printf 'Iteration %s did not produce a written justification (the iteration may have halted before writing `iter-%s-infeasibility.md`). See `iter-%s-design.txt` and `iter-%s-im.txt` for context.\n\n' "${IT}" "${IT}" "${IT}" "${IT}"
      fi
      ;;
  esac
} > "$CLOSEOUT_BODY"

# --------------------------------------------------------------------------
# Step 5c — Post close-out comment (redacted)
# --------------------------------------------------------------------------

CLOSEOUT_REDACTED="${CLOSEOUT_BODY}.redacted"
"${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh" < "$CLOSEOUT_BODY" > "$CLOSEOUT_REDACTED"
gh issue comment "$ISSUE_NUM" --body-file "$CLOSEOUT_REDACTED" || {
  GH_RC=$?
  breadcrumb_warn "5: close out — gh comment failed (exit ${GH_RC}). Continuing to cleanup."
}
printf 'done\n' > "$LOOP_TMPDIR/closeout.sentinel"

breadcrumb_done "5: close out — issue #${ISSUE_NUM}, exit: ${EXIT_REASON}"

# --------------------------------------------------------------------------
# Step 6 — Cleanup (EXIT trap also handles this; explicit call for symmetry)
# --------------------------------------------------------------------------

breadcrumb_done "6: cleanup — loop-improve-skill complete!"

exit 0
