#!/usr/bin/env bash
# driver.sh — Bash driver for /loop-review (inversion-of-control overhaul).
#
# Topology: bash owns loop control; each slice is its own `claude -p /review`
# subprocess. Halt class eliminated by construction: no post-child-return
# model turn that can halt between subprocess return and this driver's
# post-call Bash.
#
# Usage:
#   driver.sh [--debug] [partition criteria...]
#
# Arguments:
#   --debug           — optional flag (currently no-op; reserved for future
#                       verbosity control).
#   partition criteria — remaining argv concatenated as freeform partition
#                       criteria appended to the partition prompt
#                       (e.g., "focus on /research skill and its references").
#
# Topology:
#   Step 1 — argv parse + claude/gh CLI preflight
#   Step 2 — session-setup.sh → LOOP_TMPDIR
#   Step 3 — preflight: loop-review label exists in current repo (warn if not)
#   Step 4 — partition step: invoke_claude_p_freeform with partition prompt
#             → $LOOP_TMPDIR/partitions.txt (one verbal slice per line, 1-20)
#   Step 5 — per-slice loop: for each slice line N (1-based):
#             - Write slice text to $LOOP_TMPDIR/slice-N-desc.txt
#             - Build single-line slash-command prompt:
#                 /review --slice-file <path> --create-issues
#                         --label loop-review
#                         --security-output $LOOP_TMPDIR/security-findings-slice-N.md
#             - Invoke via invoke_claude_p_skill (STDIN: slash-command line)
#             - Parse `### slice-result` KV footer; aggregate counters
#             - Per-slice failure → log warning + retain tmpdir + continue
#   Step 6 — final summary: print aggregate counters, security-findings
#             concatenated from $LOOP_TMPDIR/security-findings-slice-*.md;
#             print SECURITY.md disclaimer
#   Step 7 — cleanup-tmpdir.sh on success via EXIT trap (retained on failure)
#
# Security posture (mirrors loop-improve-skill/driver.sh):
#   - LOOP_TMPDIR MUST begin with /tmp/ or /private/tmp/ AND MUST NOT contain
#     `..` as a path component.
#   - Per-slice artifacts (slice-N-desc.txt, slice-N-cmd.txt, slice-N-review.txt,
#     security-findings-slice-N.md) accumulate in LOOP_TMPDIR.
#   - All subprocess `claude -p` invocations follow FINDING_7 (--plugin-dir),
#     FINDING_9 (prompt on STDIN, avoids ARG_MAX), FINDING_10 (stderr sidecar).
#   - On any subprocess failure, redacted stderr+stdout-tail diagnostics are
#     dumped via dump_subprocess_diagnostics; LOOP_PRESERVE_TMPDIR flips true.
#   - $LOOP_TMPDIR cleaned via EXIT trap on success; retained on any abnormal
#     exit so operators can inspect per-slice artifacts.
#
# LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE is an advisory env var reserved for
# forthcoming Tier-2 stub-shim integration tests in
# scripts/test-loop-review-driver.sh; the shipped Tier-1 structural test only
# references the env-var name (assertion J) and does not exercise the
# override at runtime. Documented in SECURITY.md as test-only;
# never set in production.

set -euo pipefail

# Derive CLAUDE_PLUGIN_ROOT from script location when the harness did not
# export it. Layout:
#   ${CLAUDE_PLUGIN_ROOT}/skills/loop-review/scripts/driver.sh
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
# shellcheck disable=SC2317
breadcrumb_skip()       { printf '⏩ %s\n' "$*"; }
breadcrumb_warn()       { printf '**⚠ %s**\n' "$*"; }

# --------------------------------------------------------------------------
# Cleanup trap (conditional retention)
# --------------------------------------------------------------------------

LOOP_TMPDIR=""
LOOP_PRESERVE_TMPDIR="false"   # sticky; once true, cleanup is suppressed

# shellcheck disable=SC2317
cleanup_on_exit() {
  local rc=$?
  printf 'LOOP_TMPDIR=%s\n' "${LOOP_TMPDIR}"
  if [[ -n "$LOOP_TMPDIR" && -d "$LOOP_TMPDIR" ]]; then
    if [[ "$LOOP_PRESERVE_TMPDIR" == "true" ]]; then
      breadcrumb_warn "7: cleanup — Retained working directory: ${LOOP_TMPDIR}"
    elif [[ -x "${CLAUDE_PLUGIN_ROOT:-}/scripts/cleanup-tmpdir.sh" ]]; then
      "${CLAUDE_PLUGIN_ROOT}/scripts/cleanup-tmpdir.sh" --dir "$LOOP_TMPDIR" || true
    fi
  fi
  return "$rc"
}
trap cleanup_on_exit EXIT

# --------------------------------------------------------------------------
# Helper: dump_subprocess_diagnostics (issue #399 remedy (b), driver copy)
# --------------------------------------------------------------------------
# shellcheck disable=SC2317
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
      tail -n 50 "$out_file" | "$redact" || printf '(redaction failed; omitting stdout tail)\n'
    else
      printf '(redact-secrets.sh unavailable; omitting stdout tail)\n'
    fi
  else
    printf '(stdout empty)\n'
  fi
  printf '── end subprocess diagnostics (label=%s) ──\n' "$label"
  LOOP_PRESERVE_TMPDIR="true"
}

# --------------------------------------------------------------------------
# Helper: dump_helper_stderr
# --------------------------------------------------------------------------
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
  LOOP_PRESERVE_TMPDIR="true"
}

# --------------------------------------------------------------------------
# Helpers: invoke_claude_p_freeform / invoke_claude_p_skill
# --------------------------------------------------------------------------
# Both helpers preserve FINDING_7 (--plugin-dir), FINDING_9 (STDIN delivery,
# avoids macOS ARG_MAX = 262144), FINDING_10 (stderr sidecar).
#
# _freeform: prompt-file content is a freeform instruction (e.g., partition
#   prompt). Used by Step 4.
# _skill: prompt-file content is a single-line slash-command (e.g.,
#   "/review --slice-file ... --create-issues ..."). Used by Step 5
#   per-slice loop.
#
# Tier-2 test override: LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE replaces the
# `claude` binary with a stub shim. Production: variable unset → uses the
# real `claude` binary on PATH.

# shellcheck disable=SC2317
invoke_claude_p_freeform() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1200}"
  _invoke_claude_p_inner "$prompt_file" "$out_file" "$label" "$timeout_s"
}

# shellcheck disable=SC2317
invoke_claude_p_skill() {
  local prompt_file="$1"   # contains a single-line slash-command
  local out_file="$2"
  local label="$3"
  local timeout_s="${4:-1800}"
  _invoke_claude_p_inner "$prompt_file" "$out_file" "$label" "$timeout_s"
}

# Internal: shared implementation. Both helpers delegate here because the
# `claude -p` invocation contract is identical — STDIN delivery + plugin-dir +
# stderr sidecar. The two named entry points exist solely to make per-call-site
# semantics legible and to allow future divergence (e.g., different timeouts).
_invoke_claude_p_inner() {
  local prompt_file="$1"
  local out_file="$2"
  local label="$3"
  local timeout_s="$4"
  local stderr_file="${out_file}.stderr"
  local rc=0

  local claude_bin="${LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE:-claude}"

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

  if [[ "$rc" -ne 0 ]]; then
    dump_subprocess_diagnostics "$label" "$out_file"
  fi
  return "$rc"
}

# --------------------------------------------------------------------------
# Step 1 — Parse argv + CLI preflight
# --------------------------------------------------------------------------

DEBUG_FLAG="false"
PARTITION_CRITERIA=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --debug) DEBUG_FLAG="true"; shift ;;
    --) shift; break ;;
    --*)
      breadcrumb_warn "1: parse args — unknown flag '$1'. Valid flags: --debug."
      exit 1
      ;;
    *) break ;;
  esac
done

# Remaining argv → freeform partition criteria
if [[ $# -gt 0 ]]; then
  PARTITION_CRITERIA="$*"
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)"

if ! command -v claude >/dev/null 2>&1 && [[ -z "${LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE:-}" ]]; then
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

breadcrumb_done "1: parse args — debug=${DEBUG_FLAG}, partition_criteria='${PARTITION_CRITERIA}'"

# --------------------------------------------------------------------------
# Step 2 — Session setup (LOOP_TMPDIR)
# --------------------------------------------------------------------------

breadcrumb_inprogress "2: session setup"

SETUP_OUT=""
if ! SETUP_OUT="$("${CLAUDE_PLUGIN_ROOT}"/scripts/session-setup.sh \
    --prefix claude-loop-review \
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

# Counter file initialization (replaces the deleted init-session-files.sh).
: > "$LOOP_TMPDIR/issues-created-count.txt"
: > "$LOOP_TMPDIR/issues-deduplicated-count.txt"
: > "$LOOP_TMPDIR/issues-failed-count.txt"
: > "$LOOP_TMPDIR/security-held-count.txt"
echo 0 > "$LOOP_TMPDIR/issues-created-count.txt"
echo 0 > "$LOOP_TMPDIR/issues-deduplicated-count.txt"
echo 0 > "$LOOP_TMPDIR/issues-failed-count.txt"
echo 0 > "$LOOP_TMPDIR/security-held-count.txt"

breadcrumb_done "2: session setup — LOOP_TMPDIR=${LOOP_TMPDIR}"

# --------------------------------------------------------------------------
# Step 3 — Preflight: loop-review label
# --------------------------------------------------------------------------

breadcrumb_inprogress "3: preflight"

if ! gh label list --limit 200 --json name --jq '.[].name' 2>/dev/null | grep -Fxq loop-review; then
  breadcrumb_warn "3: preflight — 'loop-review' label not found in current repo. /issue will create issues unlabeled. Create it once with: gh label create loop-review --description 'Surfaced by /loop-review' --color 5319E7"
fi

breadcrumb_done "3: preflight"

# --------------------------------------------------------------------------
# Step 4 — Partition step (single claude -p call)
# --------------------------------------------------------------------------

breadcrumb_inprogress "4: partition"

PARTITION_PROMPT_FILE="$LOOP_TMPDIR/partition-prompt.txt"
PARTITION_OUT_FILE="$LOOP_TMPDIR/partition-output.txt"
PARTITIONS_FILE="$LOOP_TMPDIR/partitions.txt"

# Partition prompt: instruct claude -p to enumerate verbal slice descriptions.
# Output contract: one verbal slice description per non-empty line, 1-20 lines,
# no duplicates. Validation runs in bash after the subprocess returns.
{
  printf 'You are partitioning a code repository for a comprehensive code review sweep. Explore the repo (Read/Grep/Glob/LS) to understand its structure, then output a list of 1 to 20 verbal slice descriptions, one per non-empty line, that together cover the repository in non-overlapping, semantically-meaningful chunks.\n\n'
  printf 'Each slice description must be a short verbal phrase (5-15 words) that a downstream reviewer can resolve into a concrete file set via Glob/Grep/Read. Examples of good slice descriptions:\n'
  printf '- "implementation of /research skill (SKILL.md and references)"\n'
  printf '- "all hook scripts under hooks/"\n'
  printf '- "shared scripts under scripts/ that handle reviewer health probes"\n'
  printf '- "complete contents of the design skill including its reference files"\n'
  printf '- "top-level docs under docs/ and the README"\n\n'
  printf 'Constraints:\n'
  printf '- One verbal slice description per non-empty line. Do NOT use markdown bullets, numbering, headers, or any prefix characters.\n'
  printf '- 1 to 20 lines total. Aim for whatever count gives semantically clean partitions.\n'
  printf '- Slices should be non-overlapping and together exhaustive of the parts of the repo worth reviewing.\n'
  printf '- Do NOT include shell metacharacters (quotes, backticks, dollar signs, ampersands, parentheses, semicolons, pipes) in slice descriptions — descriptions are written to a file but downstream readability matters.\n'
  printf '- Do NOT print any preamble, explanation, or trailing commentary. Output ONLY the slice descriptions, one per line.\n\n'
  if [[ -n "$PARTITION_CRITERIA" ]]; then
    printf 'Additional partitioning guidance from the user:\n'
    printf '%s\n\n' "$PARTITION_CRITERIA"
  fi
  printf 'Begin output now.\n'
} > "$PARTITION_PROMPT_FILE"

if ! invoke_claude_p_freeform "$PARTITION_PROMPT_FILE" "$PARTITION_OUT_FILE" "partition" 1200; then
  breadcrumb_warn "4: partition — partition subprocess failed. Aborting."
  exit 1
fi

# Validate partition output: 1-20 non-empty lines after trim, no duplicates.
# Strip blank lines and leading/trailing whitespace; dedupe; cap at 20.
awk 'NF > 0 { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, ""); print }' \
  "$PARTITION_OUT_FILE" \
  | awk '!seen[$0]++' \
  > "$PARTITIONS_FILE"

PARTITION_COUNT=$(wc -l < "$PARTITIONS_FILE" | awk '{print $1}')

if [[ "$PARTITION_COUNT" -lt 1 ]]; then
  breadcrumb_warn "4: partition — partition output produced 0 non-empty unique lines. Raw output retained at $PARTITION_OUT_FILE. Aborting."
  LOOP_PRESERVE_TMPDIR="true"
  exit 1
fi

if [[ "$PARTITION_COUNT" -gt 20 ]]; then
  breadcrumb_warn "4: partition — partition output produced $PARTITION_COUNT lines (>20 cap). Truncating to 20."
  head -n 20 "$PARTITIONS_FILE" > "$PARTITIONS_FILE.truncated"
  mv "$PARTITIONS_FILE.truncated" "$PARTITIONS_FILE"
  PARTITION_COUNT=20
fi

breadcrumb_done "4: partition — ${PARTITION_COUNT} slice(s) identified"

# --------------------------------------------------------------------------
# Step 5 — Per-slice loop
# --------------------------------------------------------------------------

SLICE_NUM=0
SLICES_OK=0
SLICES_FAILED=0

while IFS= read -r SLICE_TEXT; do
  SLICE_NUM=$(( SLICE_NUM + 1 ))
  if [[ -z "$SLICE_TEXT" ]]; then
    continue
  fi

  breadcrumb_inprogress "5.${SLICE_NUM}: slice — ${SLICE_TEXT}"

  SLICE_DESC_FILE="$LOOP_TMPDIR/slice-${SLICE_NUM}-desc.txt"
  SLICE_CMD_FILE="$LOOP_TMPDIR/slice-${SLICE_NUM}-cmd.txt"
  SLICE_OUT_FILE="$LOOP_TMPDIR/slice-${SLICE_NUM}-review.txt"
  SLICE_SECURITY_FILE="$LOOP_TMPDIR/security-findings-slice-${SLICE_NUM}.md"

  # File-based slice handoff (per FINDING_2 — avoids argv shell-quoting hazard)
  printf '%s\n' "$SLICE_TEXT" > "$SLICE_DESC_FILE"

  # Single-line slash-command prompt (claude -p reads it via STDIN)
  printf '/review --slice-file %s --create-issues --label loop-review --security-output %s\n' \
    "$SLICE_DESC_FILE" "$SLICE_SECURITY_FILE" \
    > "$SLICE_CMD_FILE"

  if invoke_claude_p_skill "$SLICE_CMD_FILE" "$SLICE_OUT_FILE" "slice-${SLICE_NUM}" 1800; then
    # Parse `### slice-result` KV footer (mirror of `### iteration-result`).
    # awk-scope to lines AFTER the header so a stray pre-block KV-shaped line
    # cannot spoof the parse.
    parse_slice_kv() {
      local key="$1"
      awk -F= -v k="${key}" '
        /^### slice-result/ { in_block=1; next }
        in_block && $0 ~ "^" k "=" {print substr($0, length(k)+2); exit}
      ' "$SLICE_OUT_FILE"
    }

    PARSE_STATUS=$(parse_slice_kv PARSE_STATUS)
    if [[ "$PARSE_STATUS" != "ok" ]]; then
      breadcrumb_warn "5.${SLICE_NUM}: slice — KV footer missing or PARSE_STATUS != ok. Slice review may have failed silently. Continuing."
      SLICES_FAILED=$(( SLICES_FAILED + 1 ))
      LOOP_PRESERVE_TMPDIR="true"
    else
      ISSUES_CREATED=$(parse_slice_kv ISSUES_CREATED)
      ISSUES_DEDUPLICATED=$(parse_slice_kv ISSUES_DEDUPLICATED)
      ISSUES_FAILED=$(parse_slice_kv ISSUES_FAILED)
      SECURITY_FINDINGS_HELD=$(parse_slice_kv SECURITY_FINDINGS_HELD)

      # Update aggregate counters
      CUR=$(cat "$LOOP_TMPDIR/issues-created-count.txt"); echo $(( CUR + ${ISSUES_CREATED:-0} )) > "$LOOP_TMPDIR/issues-created-count.txt"
      CUR=$(cat "$LOOP_TMPDIR/issues-deduplicated-count.txt"); echo $(( CUR + ${ISSUES_DEDUPLICATED:-0} )) > "$LOOP_TMPDIR/issues-deduplicated-count.txt"
      CUR=$(cat "$LOOP_TMPDIR/issues-failed-count.txt"); echo $(( CUR + ${ISSUES_FAILED:-0} )) > "$LOOP_TMPDIR/issues-failed-count.txt"
      CUR=$(cat "$LOOP_TMPDIR/security-held-count.txt"); echo $(( CUR + ${SECURITY_FINDINGS_HELD:-0} )) > "$LOOP_TMPDIR/security-held-count.txt"

      breadcrumb_done "5.${SLICE_NUM}: slice — created=${ISSUES_CREATED:-0} deduped=${ISSUES_DEDUPLICATED:-0} failed=${ISSUES_FAILED:-0} security_held=${SECURITY_FINDINGS_HELD:-0}"
      SLICES_OK=$(( SLICES_OK + 1 ))
    fi
  else
    breadcrumb_warn "5.${SLICE_NUM}: slice — subprocess failed. Continuing to next slice."
    SLICES_FAILED=$(( SLICES_FAILED + 1 ))
    LOOP_PRESERVE_TMPDIR="true"
  fi
done < "$PARTITIONS_FILE"

# --------------------------------------------------------------------------
# Step 6 — Final summary
# --------------------------------------------------------------------------

breadcrumb_inprogress "6: summary"

TOTAL_CREATED=$(cat "$LOOP_TMPDIR/issues-created-count.txt")
TOTAL_DEDUPED=$(cat "$LOOP_TMPDIR/issues-deduplicated-count.txt")
TOTAL_FAILED=$(cat "$LOOP_TMPDIR/issues-failed-count.txt")
TOTAL_SECURITY=$(cat "$LOOP_TMPDIR/security-held-count.txt")

cat <<SUMMARY_EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
📊 Loop Review Complete
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Slices reviewed: ${SLICES_OK}/${PARTITION_COUNT} (failed: ${SLICES_FAILED})
Issues filed: ${TOTAL_CREATED}   (deduplicated: ${TOTAL_DEDUPED}, failed: ${TOTAL_FAILED})
Security-tagged findings held locally: ${TOTAL_SECURITY}

Filter in GitHub: \`is:issue is:open label:loop-review\`
SUMMARY_EOF

# Concatenate per-slice security-findings files if any non-empty.
SECURITY_AGG_FOUND=0
for f in "$LOOP_TMPDIR"/security-findings-slice-*.md; do
  if [[ -s "$f" ]]; then
    if [[ "$SECURITY_AGG_FOUND" -eq 0 ]]; then
      cat <<SECURITY_HEADER

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
🔒 Security-tagged findings (held locally per SECURITY.md)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECURITY_HEADER
      SECURITY_AGG_FOUND=1
    fi
    printf '\n## %s\n\n' "$(basename "$f")"
    cat "$f"
  fi
done

if [[ "$SECURITY_AGG_FOUND" -eq 1 ]]; then
  cat <<SECURITY_FOOTER

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
SECURITY_FOOTER
  breadcrumb_warn "Handle these findings per SECURITY.md's vulnerability-disclosure procedure. They are NOT filed as public GitHub issues. Session tmpdir is removed by Step 7 — preserve the block above if further triage is needed."
  LOOP_PRESERVE_TMPDIR="true"
fi

breadcrumb_done "6: summary — ${SLICES_OK}/${PARTITION_COUNT} slices, ${TOTAL_CREATED} issues filed"

# --------------------------------------------------------------------------
# Step 7 — Cleanup (EXIT trap also handles this)
# --------------------------------------------------------------------------

breadcrumb_done "7: cleanup — loop-review complete!"

exit 0
