#!/usr/bin/env bash
# run-research-adjudication.sh — pre-launch coordinator for /research --adjudicate.
#
# Wraps the shell-only logic that precedes the parallel 3-judge launch:
#   1. Empty-check on $RESEARCH_TMPDIR/rejected-findings.md.
#   2. Invoke scripts/build-research-adjudication-ballot.sh to produce the ballot.
#   3. Run scripts/check-reviewers.sh --probe for fresh judge availability.
#
# This consolidates three otherwise-consecutive Bash tool calls into a single
# coordinator per skills/shared/skill-design-principles.md Section III rule C.
# The validation-phase.md Step 2.5 reference issues exactly one Bash call to
# this script and parses the structured stdout below.
#
# Consumers:
#   - skills/research/references/adjudication-phase.md Step 2.5.1.
#
# Output contract (KEY=value on stdout):
#   Always emitted:
#     RAN=true|false
#
#   When RAN=true:
#     BALLOT_PATH=<path>
#     DECISION_COUNT=<N>
#     JUDGE_CODEX_AVAILABLE=true|false
#     JUDGE_CURSOR_AVAILABLE=true|false
#
#   When RAN=false (input empty/absent — short-circuit success path):
#     REASON=<single-line message>  (informational)
#
#   On failure:
#     RAN=false
#     FAILED=true
#     ERROR=<single-line message>
#
# Exit codes:
#   0 — success (RAN=true OR RAN=false short-circuit).
#   1 — invocation / usage error.
#   2 — I/O failure or downstream-script failure.

set -euo pipefail

REJECTED_FINDINGS=""
TMPDIR_VAL=""

usage() {
  cat >&2 <<'USAGE'
Usage: run-research-adjudication.sh --rejected-findings <path> --tmpdir <path>

Both flags are required.
  --rejected-findings <path>   Path to rejected-findings.md from validation-phase.md
                               Sites A/B. Empty/absent → RAN=false short-circuit.
  --tmpdir <path>              Session tmpdir ($RESEARCH_TMPDIR) — used as the
                               working directory for the ballot and as the
                               --output target.

Stdout (KEY=value):
  RAN=true|false (always)
  BALLOT_PATH=<path>, DECISION_COUNT=<N>,
    JUDGE_CODEX_AVAILABLE=true|false, JUDGE_CURSOR_AVAILABLE=true|false (when RAN=true)
  REASON=<message> (when RAN=false short-circuit)
  FAILED=true / ERROR=<message> (on failure)
USAGE
}

emit_failure() {
  printf 'RAN=false\nFAILED=true\nERROR=%s\n' "$1"
  exit "${2:-2}"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --rejected-findings)
      [[ $# -ge 2 ]] || { usage; emit_failure "Missing value for --rejected-findings" 1; }
      REJECTED_FINDINGS="$2"
      shift 2
      ;;
    --tmpdir)
      [[ $# -ge 2 ]] || { usage; emit_failure "Missing value for --tmpdir" 1; }
      TMPDIR_VAL="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      usage
      emit_failure "Unknown argument: $1" 1
      ;;
  esac
done

[[ -n "$REJECTED_FINDINGS" ]] || { usage; emit_failure "Missing required flag --rejected-findings" 1; }
[[ -n "$TMPDIR_VAL" ]]        || { usage; emit_failure "Missing required flag --tmpdir"            1; }

[[ -d "$TMPDIR_VAL" ]] || emit_failure "Tmpdir does not exist: $TMPDIR_VAL" 2

# Phase 1 — empty-check.
# Treat any of: missing file, zero-byte file, or a file with no parseable
# `### REJECTED_FINDING_N` blocks, as the short-circuit path. The cheapest
# robust check is a missing-or-empty test combined with a grep for the block
# header; if neither shows up, no decisions exist for adjudication.
if [[ ! -f "$REJECTED_FINDINGS" ]]; then
  printf 'RAN=false\nREASON=%s\n' "rejected-findings file does not exist"
  exit 0
fi

if [[ ! -s "$REJECTED_FINDINGS" ]]; then
  printf 'RAN=false\nREASON=%s\n' "rejected-findings file is empty"
  exit 0
fi

if ! grep -qE '^### REJECTED_FINDING_[0-9]+[[:space:]]*$' "$REJECTED_FINDINGS"; then
  printf 'RAN=false\nREASON=%s\n' "rejected-findings file has no parseable blocks"
  exit 0
fi

# Phase 2 — locate sibling helpers (script lives in scripts/ alongside its peers).
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
BALLOT_BUILDER="$SCRIPT_DIR/build-research-adjudication-ballot.sh"
PROBE_HELPER="$SCRIPT_DIR/check-reviewers.sh"

[[ -x "$BALLOT_BUILDER" ]] || emit_failure "Ballot builder not found or not executable: $BALLOT_BUILDER" 2
[[ -x "$PROBE_HELPER"   ]] || emit_failure "Probe helper not found or not executable: $PROBE_HELPER"     2

BALLOT_PATH="$TMPDIR_VAL/research-adjudication-ballot.txt"

# Phase 3 — invoke ballot builder. Capture stdout to parse KEY=value contract.
if ! BUILDER_OUT="$("$BALLOT_BUILDER" --input "$REJECTED_FINDINGS" --output "$BALLOT_PATH" 2>&1)"; then
  # Helper exited non-zero; surface its error and bail.
  err_line="$(printf '%s\n' "$BUILDER_OUT" | grep -E '^ERROR=' | head -1 | sed 's/^ERROR=//')"
  err_line="${err_line:-Ballot builder failed}"
  emit_failure "$err_line" 2
fi

# Verify BUILT=true and parse DECISION_COUNT.
if ! printf '%s\n' "$BUILDER_OUT" | grep -qE '^BUILT=true[[:space:]]*$'; then
  err_line="$(printf '%s\n' "$BUILDER_OUT" | grep -E '^ERROR=' | head -1 | sed 's/^ERROR=//')"
  err_line="${err_line:-Ballot builder did not emit BUILT=true}"
  emit_failure "$err_line" 2
fi

DECISION_COUNT="$(printf '%s\n' "$BUILDER_OUT" | grep -E '^DECISION_COUNT=' | head -1 | sed 's/^DECISION_COUNT=//')"
DECISION_COUNT="${DECISION_COUNT:-0}"

# If DECISION_COUNT is 0 (input had no parseable blocks even though grep matched
# the header — could happen if all blocks were structurally incomplete), short-circuit.
if [[ "$DECISION_COUNT" == "0" ]]; then
  printf 'RAN=false\nREASON=%s\n' "ballot builder produced 0 decisions (input blocks were incomplete)"
  exit 0
fi

# Phase 4 — fresh judge re-probe.
if ! PROBE_OUT="$("$PROBE_HELPER" --probe 2>&1)"; then
  emit_failure "Reviewer probe failed: $(printf '%s' "$PROBE_OUT" | head -1)" 2
fi

# Two-key rule (per skills/shared/external-reviewers.md): judge_*_available =
# *_AVAILABLE=true AND *_HEALTHY=true.
get_kv() {
  printf '%s\n' "$PROBE_OUT" | awk -F= -v key="$1" '$1 == key { print $2; exit }'
}

CODEX_AVAILABLE="$(get_kv CODEX_AVAILABLE)"
CODEX_HEALTHY="$(get_kv CODEX_HEALTHY)"
CURSOR_AVAILABLE="$(get_kv CURSOR_AVAILABLE)"
CURSOR_HEALTHY="$(get_kv CURSOR_HEALTHY)"

if [[ "$CODEX_AVAILABLE" == "true" && "$CODEX_HEALTHY" == "true" ]]; then
  JUDGE_CODEX_AVAILABLE=true
else
  JUDGE_CODEX_AVAILABLE=false
fi

if [[ "$CURSOR_AVAILABLE" == "true" && "$CURSOR_HEALTHY" == "true" ]]; then
  JUDGE_CURSOR_AVAILABLE=true
else
  JUDGE_CURSOR_AVAILABLE=false
fi

cat <<EOF
RAN=true
BALLOT_PATH=$BALLOT_PATH
DECISION_COUNT=$DECISION_COUNT
JUDGE_CODEX_AVAILABLE=$JUDGE_CODEX_AVAILABLE
JUDGE_CURSOR_AVAILABLE=$JUDGE_CURSOR_AVAILABLE
EOF
