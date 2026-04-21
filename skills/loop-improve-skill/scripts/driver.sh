#!/usr/bin/env bash
# driver.sh — Bash driver for /loop-improve-skill (Option B topology, closes #273).
#
# Replaces the prior outer→inner→3-children Skill-tool chain with a single-file
# bash driver that invokes each child skill (/skill-judge, /design, /im) as a
# fresh `claude -p` subprocess. Halt class eliminated by construction: each
# child's report is its subprocess's output, so there is no post-child-return
# model turn that can halt between child-return and post-call Bash.
#
# Usage:
#   driver.sh <skill-name>
#
# Argument:
#   <skill-name>  — target larch skill to iteratively improve. A leading `/`
#                   is stripped. Must match `^[a-z][a-z0-9-]*$`.
#
# Topology:
#   For each iteration (ITER=1..10):
#     Phase 1 — /skill-judge as claude -p subprocess → capture JUDGE_OUT
#                  → parse-skill-judge-grade.sh → append grade-history.txt
#                  → post gh issue comment (redacted)
#                  → if GRADE_A=true: break with EXIT_REASON
#     Phase 2 — /design  as claude -p subprocess → capture DESIGN_OUT
#                  → no-plan detector + rescue re-invocation (one max per iter)
#                  → if no_plan|design_refusal: write infeasibility.md, break
#                  → else post plan comment (redacted)
#     Phase 3 — /im      as claude -p subprocess → capture IM_OUT
#                  → verify-skill-called.sh --stdout-line '^✅ 18: cleanup'
#                  → if VERIFIED=false: write infeasibility.md, break
#   On ITER>10: run one final /skill-judge (post-iter-cap re-evaluation); may
#     reclassify EXIT_REASON if grade A was reached by the last /im.
#   Close-out: compose + post close-out comment (summary + Grade History +
#     conditional Infeasibility Justification + Final Assessment).
#   Cleanup: cleanup-tmpdir.sh (always runs via EXIT trap).
#
# Security posture (mirrors pre-rewrite boundaries, see SECURITY.md):
#   - LOOP_TMPDIR MUST begin with /tmp/ or /private/tmp/ AND MUST NOT contain
#     `..` as a path component (reject occurrences of /.. or a trailing ..).
#   - All subprocess invocations cd to REPO_ROOT so target skill-dir resolves
#     consistently across iterations.
#   - Argv arrays for command construction (no eval, no source of untrusted
#     content).
#   - All gh comment bodies piped through redact-secrets.sh before posting.
#   - $LOOP_TMPDIR always cleaned via EXIT trap.

set -euo pipefail

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
# shellcheck disable=SC2317  # invoked via trap on EXIT — shellcheck cannot see the indirect call
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
# Step 1 — Parse + validate <skill-name>
# --------------------------------------------------------------------------

if [[ $# -lt 1 ]]; then
  breadcrumb_warn "1: parse args — missing <skill-name>. Usage: driver.sh <skill-name>"
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

SETUP_OUT="$("${CLAUDE_PLUGIN_ROOT}"/scripts/session-setup.sh \
  --prefix claude-loop-improve \
  --skip-branch-check \
  --skip-slack-check \
  --skip-repo-check)"

LOOP_TMPDIR="$(printf '%s\n' "$SETUP_OUT" | awk -F= '/^SESSION_TMPDIR=/{print substr($0, index($0,"=")+1); exit}')"

if [[ -z "$LOOP_TMPDIR" ]]; then
  breadcrumb_warn "2: session setup — failed to parse SESSION_TMPDIR. Aborting."
  exit 1
fi

# Validate LOOP_TMPDIR security boundary (prefix + no `..` traversal).
# Accept /tmp/ or /private/tmp/ prefix. Reject any occurrence of /..
# path component (including a trailing `..`).
if ! [[ "$LOOP_TMPDIR" == /tmp/* || "$LOOP_TMPDIR" == /private/tmp/* ]]; then
  breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' does not begin with /tmp/ or /private/tmp/. Aborting."
  exit 1
fi
case "$LOOP_TMPDIR" in
  */..|*/../*)
    breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' contains '..' path component. Aborting."
    exit 1 ;;
esac
if [[ "$LOOP_TMPDIR" == *"/.."* ]]; then
  breadcrumb_warn "2: session setup — LOOP_TMPDIR '$LOOP_TMPDIR' contains '..' path component. Aborting."
  exit 1
fi

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
  printf 'Iteratively improve /%s via /loop-improve-skill. Runs up to 10 rounds of /skill-judge + /design + /im, each invoked as a fresh `claude -p` subprocess by the bash driver (topology #273). Exits when every /skill-judge dimension reaches grade A, or when an infeasibility halt (no_plan / design_refusal / im_verification_failed, with written justification appended below) or the 10-iteration cap is reached.\n\n' "${SKILL_NAME}"
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
# Helper: invoke claude -p with a prompt file, capture stdout to <out-file>
# --------------------------------------------------------------------------

# invoke_claude_p <prompt-file> <out-file> <phase-label> <timeout-seconds>
# Reads the prompt from <prompt-file> (so the full prompt is a file on disk,
# not an argv element — keeps argv small and avoids shell-quoting surprises),
# passes it to `claude -p <prompt>` via a here-doc, captures stdout to
# <out-file>. cd's to REPO_ROOT first.
invoke_claude_p() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1200}"

  local prompt
  prompt="$(cat "$prompt_file")"

  # Use run-external-reviewer.sh for uniform monitoring + timeout + stdout capture.
  # (Sidesteps reimplementing the poll/kill logic inline.)
  (
    cd "$REPO_ROOT"
    "${CLAUDE_PLUGIN_ROOT}/scripts/run-external-reviewer.sh" \
      --tool "claude-${label}" \
      --output "$out_file" \
      --timeout "$timeout_s" \
      --capture-stdout \
      -- claude -p "$prompt"
  )
}

# post_gh_comment <body-file> <iter-label>
# Redacts via redact-secrets.sh, posts with gh issue comment. Warns on failure,
# never fails the loop.
post_gh_comment() {
  local body_file="$1"
  local iter_label="$2"
  local redacted="${body_file}.redacted"

  "${CLAUDE_PLUGIN_ROOT}/scripts/redact-secrets.sh" < "$body_file" > "$redacted"
  if ! gh issue comment "$ISSUE_NUM" --body-file "$redacted"; then
    breadcrumb_warn "gh issue comment failed for ${iter_label}. Continuing."
  fi
}

# --------------------------------------------------------------------------
# No-plan detector — transplanted from inner Step 3.d
# --------------------------------------------------------------------------
#
# Returns via stdout one of:
#   plan_ok | no_plan | design_refusal
#
# Detects:
#   - empty output             → no_plan
#   - first non-blank line matches no-plan sentinel AND no structural
#     markers on any subsequent line → no_plan
#   - explicit refusal / error pattern anywhere → design_refusal
#   - otherwise → plan_ok (may still trigger rescue; see caller)
detect_plan_status() {
  local design_out="$1"

  # Empty
  if [[ ! -s "$design_out" ]]; then
    printf 'no_plan\n'
    return 0
  fi

  # Explicit refusal/error patterns (conservative — require one of these exact markers)
  if LC_ALL=C grep -qiE '^(error:|error -|refus(ed|al)|cannot (run|proceed|execute)|/design (failed|could not run|is unavailable))' "$design_out"; then
    printf 'design_refusal\n'
    return 0
  fi

  # First non-blank line: trim + case-fold
  local first_line
  first_line="$(awk 'NF {print; exit}' "$design_out" \
    | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
    | tr '[:upper:]' '[:lower:]')"

  # Structural markers — anchored regex on any line
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
# Infeasibility justification writer — transplanted from inner Step 3.d
# --------------------------------------------------------------------------
#
# write_infeasibility <iter> <iter-status> <parse-status> <grade-a> <non-a-dims>
write_infeasibility() {
  local iter="$1"
  local status="$2"
  local parse_status="${3:-unknown}"
  local grade_a="${4:-false}"
  local non_a="${5:-}"

  local inf_file="$LOOP_TMPDIR/iter-${iter}-infeasibility.md"
  local tmp_file="${inf_file}.tmp"

  local reason why_blocks

  case "$status" in
    no_plan)
      reason="/design emitted no-plan sentinel despite Non-A dimensions ${non_a}"
      why_blocks="/design could not articulate a plan for the listed Non-A dimensions despite the Step 3.d focus block — without a plan there is no implementation candidate."
      ;;
    design_refusal)
      reason="/design returned structured refusal — see iter-${iter}-design.txt for the verbatim response"
      why_blocks="/design itself failed to run, so no plan could be produced. A later iteration would need a different target-skill framing or external context."
      ;;
    im_verification_failed)
      reason="/im did not reach its canonical completion line — see iter-${iter}-im.txt; the iteration produced design output (iter-${iter}-design.txt) but the implementation pipeline could not be verified as complete."
      why_blocks="A plan was produced but could not be landed safely (CI failure, merge conflict, or pipeline halt) — the failed plan would need a different approach to make progress."
      ;;
    *)
      reason="unknown status '${status}'"
      why_blocks="Unknown halt status; see per-iteration tmp files for context."
      ;;
  esac

  {
    printf '## Infeasibility Justification — iteration %s\n\n' "${iter}"
    printf '**Status**: %s\n\n' "${status}"
    printf '**Reason**: %s\n\n' "${reason}"
    printf '**Context**:\n'
    printf -- '- Grade parse at start of iteration: PARSE_STATUS=%s, GRADE_A=%s, non-A dimensions: %s\n' "${parse_status}" "${grade_a}" "${non_a}"
    printf -- '- Judge output: iter-%s-judge.txt\n' "${iter}"
    printf -- '- Design output (if any): iter-%s-design.txt\n' "${iter}"
    printf -- '- /im output (if any): iter-%s-im.txt\n\n' "${iter}"
    printf '**Why this blocks reaching grade A**: %s\n' "${why_blocks}"
  } > "$tmp_file"
  mv "$tmp_file" "$inf_file"
}

# --------------------------------------------------------------------------
# Step 4 — Loop
# --------------------------------------------------------------------------

ITER=1
EXIT_REASON=""
# PARSE_STATUS/GRADE_A/NON_A_DIMS track the most recent judge parse (used by
# infeasibility write for context).
PARSE_STATUS="unknown"
GRADE_A="false"
NON_A_DIMS=""

while [[ $ITER -le 10 ]]; do
  breadcrumb_inprogress "4: loop — iteration ${ITER}"

  # ----- Phase 1: /skill-judge ------------------------------------------

  breadcrumb_inprogress "4.${ITER}.j: judge"

  JUDGE_PROMPT="$LOOP_TMPDIR/iter-${ITER}-judge-prompt.txt"
  JUDGE_OUT="$LOOP_TMPDIR/iter-${ITER}-judge.txt"

  # Build prompt via printf (single call — the whole body is fixed-format).
  # NOTE: the /skill-judge invocation prompt is transplanted verbatim from
  # the pre-rewrite inner Step 3.j prompt text.
  printf '/skill-judge %s (absolute SKILL.md path: %s) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.\n' \
    "${SKILL_NAME}" "${TARGET_SKILL_PATH}" > "$JUDGE_PROMPT"

  invoke_claude_p "$JUDGE_PROMPT" "$JUDGE_OUT" "judge" 1200 || {
    breadcrumb_warn "4.${ITER}.j: judge — claude -p failed. Continuing to next iteration (loop treats subprocess failure as no-op for this phase)."
    EXIT_REASON="subprocess failure at /skill-judge iteration ${ITER}"
    break
  }

  # Wait for output via collect-reviewer-results.sh (validates non-empty / retries once).
  "${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh" --timeout 1260 "$JUDGE_OUT" >/dev/null 2>&1 || true

  if [[ ! -s "$JUDGE_OUT" ]]; then
    breadcrumb_warn "4.${ITER}.j: judge — empty output from /skill-judge subprocess. Aborting loop."
    EXIT_REASON="empty /skill-judge output at iteration ${ITER}"
    break
  fi

  # ----- Phase 1.v: grade parse -----------------------------------------

  breadcrumb_inprogress "4.${ITER}.j.v: grade parse"

  GRADE_OUT="$LOOP_TMPDIR/iter-${ITER}-grade.txt"
  GRADE_TMP="${GRADE_OUT}.tmp"
  "${CLAUDE_PLUGIN_ROOT}/scripts/parse-skill-judge-grade.sh" "$JUDGE_OUT" > "$GRADE_TMP"
  mv "$GRADE_TMP" "$GRADE_OUT"

  # Parse KV fields we need
  PARSE_STATUS="$(awk -F= '/^PARSE_STATUS=/{print $2; exit}' "$GRADE_OUT")"
  GRADE_A="$(awk -F= '/^GRADE_A=/{print $2; exit}' "$GRADE_OUT")"
  NON_A_DIMS="$(awk -F= '/^NON_A_DIMS=/{print $2; exit}' "$GRADE_OUT")"
  TOTAL_NUM="$(awk -F= '/^TOTAL_NUM=/{print $2; exit}' "$GRADE_OUT")"
  TOTAL_DEN="$(awk -F= '/^TOTAL_DEN=/{print $2; exit}' "$GRADE_OUT")"

  # Append grade-history.txt
  if [[ "$PARSE_STATUS" == "ok" ]]; then
    printf 'iter=%s total=%s/%s non_a=%s parse_status=ok\n' \
      "${ITER}" "${TOTAL_NUM}" "${TOTAL_DEN}" "${NON_A_DIMS}" \
      >> "$LOOP_TMPDIR/grade-history.txt"
  else
    printf 'iter=%s total=N/A non_a=N/A parse_status=%s\n' \
      "${ITER}" "${PARSE_STATUS:-unknown}" \
      >> "$LOOP_TMPDIR/grade-history.txt"
  fi

  # Post judge comment (redacted)
  JUDGE_COMMENT_FILE="$LOOP_TMPDIR/iter-${ITER}-judge-comment.md"
  {
    printf '## Iteration %s — /skill-judge\n\n' "${ITER}"
    cat "$JUDGE_OUT"
  } > "$JUDGE_COMMENT_FILE"
  post_gh_comment "$JUDGE_COMMENT_FILE" "iter ${ITER} judge"

  # Grade-A short-circuit
  if [[ "$GRADE_A" == "true" && "$PARSE_STATUS" == "ok" ]]; then
    EXIT_REASON="grade A achieved on all dimensions at iteration ${ITER}"
    breadcrumb_done "4.${ITER}.j.v: grade parse — grade A achieved (break loop)"
    break
  fi

  breadcrumb_done "4.${ITER}.j.v: grade parse — non-A (${NON_A_DIMS:-?}); continuing to /design"

  # ----- Phase 2: /design -----------------------------------------------

  breadcrumb_inprogress "4.${ITER}.d: design"

  DESIGN_PROMPT="$LOOP_TMPDIR/iter-${ITER}-design-prompt.txt"
  DESIGN_OUT="$LOOP_TMPDIR/iter-${ITER}-design.txt"

  # Build per-dimension deficit lines when PARSE_STATUS=ok AND GRADE_A=false
  build_deficit_lines() {
    local line=""
    for d in D1 D2 D3 D4 D5 D6 D7 D8; do
      local num den thr
      num="$(awk -F= -v k="${d}_NUM" '$1==k{print $2; exit}' "$GRADE_OUT")"
      den="$(awk -F= -v k="${d}_DEN" '$1==k{print $2; exit}' "$GRADE_OUT")"
      [[ -z "$num" || -z "$den" ]] && continue
      # Threshold per dim: D1>=18/20, D2-D6+D8>=14/15, D7>=9/10
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
    printf '/design Improve /%s at %s' "${SKILL_NAME}" "${TARGET_SKILL_PATH}"
    if [[ "$PARSE_STATUS" == "ok" && "$GRADE_A" == "false" ]]; then
      printf ' focused on %s (the Non-A dimensions from this iteration'"'"'s /skill-judge).' "${NON_A_DIMS}"
      printf '\n\nNon-A dimensions from this iteration'"'"'s /skill-judge: %s.\n' "${NON_A_DIMS}"
      printf 'Per-dimension deficits (current/required):\n'
      build_deficit_lines
      printf 'Focus this iteration'"'"'s plan on raising these dimensions to grade A.\n'
      printf 'Treat this deficit list as the canonical set of must-address findings — do NOT self-curtail on the grounds that these are "minor". The loop'"'"'s termination contract requires per-dimension A on ALL D1..D8; any non-A dimension is load-bearing for forward progress.\n\n'
    else
      printf '.\n\n'
    fi
    # Three contract clauses — transplanted VERBATIM from pre-rewrite inner Step 3.d
    printf '/design MUST produce a concrete, implementable plan for ANY actionable /skill-judge finding — including findings classified "minor", "nit", or cosmetic. Treat "minor" as "small plan", not as "no plan".\n\n'
    printf '/design MUST NOT self-curtail citing token/context budget. Under any perceived pressure, narrow scope to the single highest-leverage finding and emit a compressed micro-plan that still conforms to the standard /design plan schema (## Implementation Plan with Files to modify/create, Approach, Edge cases, Testing strategy, and Failure modes when the change is non-trivial per /design'"'"'s own rules) — never emit a no-plan sentinel on budget grounds.\n\n'
    printf '/design MUST NOT emit any of the no-plan sentinel phrases (no plan, no improvements, nothing to improve, already optimal, skill is already high quality) when /skill-judge surfaced any actionable finding. Sentinels are reserved for the genuine case where no improvement is warranted.\n\n'
    printf 'TARGET_SKILL_PATH is absolute: %s.\n' "${TARGET_SKILL_PATH}"
  } > "$DESIGN_PROMPT"

  invoke_claude_p "$DESIGN_PROMPT" "$DESIGN_OUT" "design" 1800 || {
    breadcrumb_warn "4.${ITER}.d: design — claude -p failed."
    EXIT_REASON="subprocess failure at /design iteration ${ITER}"
    write_infeasibility "$ITER" "design_refusal" "$PARSE_STATUS" "$GRADE_A" "$NON_A_DIMS"
    break
  }
  "${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh" --timeout 1860 "$DESIGN_OUT" >/dev/null 2>&1 || true

  PLAN_STATUS="$(detect_plan_status "$DESIGN_OUT")"

  # Rescue re-invocation (at most once per iter). Triggered when:
  #   - output non-empty, no sentinel match, no explicit refusal,
  #   - AND no structured plan markers anywhere.
  if [[ "$PLAN_STATUS" == "plan_ok" ]]; then
    if [[ -s "$DESIGN_OUT" ]] && \
       ! LC_ALL=C grep -qE '^#{1,6}[[:space:]]|^[1-9][0-9]?\.[[:space:]]|^[-*+][[:space:]]' "$DESIGN_OUT"; then
      breadcrumb_inprogress "4.${ITER}.d: design — rescue (no structural markers; re-invoking /design --auto)"
      RESCUE_PROMPT="$LOOP_TMPDIR/iter-${ITER}-design-rescue-prompt.txt"
      {
        printf '/design --auto Re-emit a concrete plan for /%s at %s.\n\n' "${SKILL_NAME}" "${TARGET_SKILL_PATH}"
        # shellcheck disable=SC2016  # backticks inside literal prose, not command substitution
        printf 'Your previous response had no structured-plan markers (no markdown headings, numbered list counters, or bulleted items). Focus this re-attempt exclusively on the single highest-leverage /skill-judge finding from this iteration. The re-attempt MUST use /design'"'"'s standard plan schema: a top-level `## Implementation Plan` section with `Files to modify/create`, `Approach`, `Edge cases`, `Testing strategy`, and `Failure modes` subheadings. No preamble prose. No budget excuses. No no-plan sentinels.\n\n'
        printf 'Non-A dimensions were: %s.\n' "${NON_A_DIMS}"
      } > "$RESCUE_PROMPT"
      invoke_claude_p "$RESCUE_PROMPT" "$DESIGN_OUT" "design-rescue" 1800 || true
      "${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh" --timeout 1860 "$DESIGN_OUT" >/dev/null 2>&1 || true
      PLAN_STATUS="$(detect_plan_status "$DESIGN_OUT")"
    fi
  fi

  case "$PLAN_STATUS" in
    no_plan)
      EXIT_REASON="no plan at iteration ${ITER}"
      write_infeasibility "$ITER" "no_plan" "$PARSE_STATUS" "$GRADE_A" "$NON_A_DIMS"
      breadcrumb_done "4.${ITER}.d: design — no_plan (break)"
      break
      ;;
    design_refusal)
      EXIT_REASON="/design refusal or error at iteration ${ITER}"
      write_infeasibility "$ITER" "design_refusal" "$PARSE_STATUS" "$GRADE_A" "$NON_A_DIMS"
      breadcrumb_done "4.${ITER}.d: design — design_refusal (break)"
      break
      ;;
    plan_ok)
      # Post plan comment (redacted)
      PLAN_COMMENT_FILE="$LOOP_TMPDIR/iter-${ITER}-plan-comment.md"
      {
        printf '## Iteration %s — design plan\n\n' "${ITER}"
        cat "$DESIGN_OUT"
      } > "$PLAN_COMMENT_FILE"
      post_gh_comment "$PLAN_COMMENT_FILE" "iter ${ITER} plan"
      breadcrumb_done "4.${ITER}.d: design — plan posted"
      ;;
  esac

  # ----- Phase 3: /im ---------------------------------------------------

  breadcrumb_inprogress "4.${ITER}.i: im"

  IM_PROMPT="$LOOP_TMPDIR/iter-${ITER}-im-prompt.txt"
  IM_OUT="$LOOP_TMPDIR/iter-${ITER}-im.txt"

  # /im takes the plan text as its argument
  {
    printf '/im '
    cat "$DESIGN_OUT"
  } > "$IM_PROMPT"

  invoke_claude_p "$IM_PROMPT" "$IM_OUT" "im" 3600 || {
    breadcrumb_warn "4.${ITER}.i: im — claude -p failed."
    EXIT_REASON="/im subprocess failure at iteration ${ITER}"
    write_infeasibility "$ITER" "im_verification_failed" "$PARSE_STATUS" "$GRADE_A" "$NON_A_DIMS"
    break
  }
  "${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh" --timeout 3660 "$IM_OUT" >/dev/null 2>&1 || true

  # Mechanical gate: verify-skill-called.sh --stdout-line '^✅ 18: cleanup'
  VERIFY_OUT="$("${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
    --stdout-line '^✅ 18: cleanup' --stdout-file "$IM_OUT" 2>/dev/null || printf 'VERIFIED=false\nREASON=verify_script_error\n')"
  VERIFIED="$(printf '%s\n' "$VERIFY_OUT" | awk -F= '/^VERIFIED=/{print $2; exit}')"

  if [[ "$VERIFIED" != "true" ]]; then
    EXIT_REASON="/im did not reach canonical completion line at iteration ${ITER}"
    write_infeasibility "$ITER" "im_verification_failed" "$PARSE_STATUS" "$GRADE_A" "$NON_A_DIMS"
    breadcrumb_done "4.${ITER}.i: im — verification failed (break)"
    break
  fi

  breadcrumb_done "4.${ITER}.i: im — verified"

  # ----- Advance ITER ---------------------------------------------------
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

  printf '/skill-judge %s (absolute SKILL.md path: %s) — read the SKILL.md at this exact path before evaluating; do NOT resolve by name against the plugin installation directory. Also evaluate any sibling scripts/ and references/ files under the same skill directory.\n' \
    "${SKILL_NAME}" "${TARGET_SKILL_PATH}" > "$FINAL_PROMPT"

  if invoke_claude_p "$FINAL_PROMPT" "$FINAL_JUDGE_OUT" "final-judge" 1200; then
    "${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh" --timeout 1260 "$FINAL_JUDGE_OUT" >/dev/null 2>&1 || true
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
        # shellcheck disable=SC2016  # backticks inside literal prose (close-out body), not command substitution
        printf 'See `final-judge.txt` (captured at Step 5a) and `grade-history.txt` for the per-iteration trajectory — whether the loop plateaued, regressed, or improved monotonically without reaching A informs whether the remaining gap is likely to yield to additional iterations or requires structural redesign.\n\n'
      else
        # shellcheck disable=SC2016  # backticks inside literal prose (close-out body), not command substitution
        printf 'Final /skill-judge assessment unavailable: see Grade History above for the last successful judge parse. Last in-loop judge: `iter-%s-judge.txt`.\n\n' "${IT}"
      fi
      printf '## Final Assessment\n\n'
      # shellcheck disable=SC2016  # backticks inside literal prose (close-out body), not command substitution
      printf 'Captured by the post-iter-cap re-judge at Step 5a. The full /skill-judge report is in `final-judge.txt` under the loop tmpdir; the parsed KV summary is in `final-grade.txt`.\n\n'
      ;;
    *)
      printf '## Infeasibility Justification\n\n'
      if [[ -s "$LOOP_TMPDIR/iter-${IT}-infeasibility.md" ]]; then
        cat "$LOOP_TMPDIR/iter-${IT}-infeasibility.md"
        printf '\n'
      else
        # shellcheck disable=SC2016  # backticks inside literal prose (close-out body), not command substitution
        printf 'Iteration %s did not produce a written justification (the driver may have halted before writing `iter-%s-infeasibility.md`). See `iter-%s-design.txt` and `iter-%s-im.txt` for context.\n\n' "${IT}" "${IT}" "${IT}" "${IT}"
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

# Cleanup will run from EXIT trap. Print the completion breadcrumb here so it
# appears before the trap-driven cleanup's side effects.
breadcrumb_done "6: cleanup — loop-improve-skill complete!"

exit 0
