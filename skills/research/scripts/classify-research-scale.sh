#!/usr/bin/env bash
# classify-research-scale.sh — Deterministic shell classifier that resolves
# RESEARCH_SCALE for /research from the question text alone.
#
# Consumed by /research Step 0.5 (Adaptive Scale Classification). The orchestrator
# writes RESEARCH_QUESTION to a file under $RESEARCH_TMPDIR and invokes this script.
# The script applies a three-stage rule set with asymmetric conservatism (never
# auto-quick on doubt; require strong positive signals to fire quick or deep;
# ambiguity defaults to standard) and emits exactly one bucket on stdout.
#
# Stdout (machine output only):
#   On success: SCALE=<bucket> followed by REASON=<token>, exit 0.
#     SCALE tokens: quick | standard | deep
#     REASON tokens: length_deep | keyword_deep | multi_part_deep |
#                    lookup_quick | default_standard
#   On failure: REASON=<token>, exit non-zero.
#     REASON tokens: empty_input (exit 1) | missing_arg (exit 2) | bad_path (exit 2)
#   No other lines appear on stdout.
#
# Stderr: human diagnostics (one short line per anomaly observed).
#
# Validation rules (applied in order):
#   1. --question file must exist, be a regular file, and be readable
#      (else REASON=bad_path, exit 2).
#   2. --question file must be non-empty (else REASON=empty_input, exit 1).
#   3. Stage 1 — strong-deep signals (any one fires -> SCALE=deep):
#        a. byte length > 600 (wc -c)
#        b. >=2 matches across the case-insensitive deep keyword set:
#           compare, tradeoff, audit, architecture, migration, vulnerab,
#           security review, threat model, refactor, design decision,
#           end-to-end, comprehensive
#        c. structural cue: >=2 '?' characters in the question text
#   4. Stage 2 — strong-quick signals (ALL fire AND no Stage 1 hit -> SCALE=quick):
#        a. byte length < 80
#        b. exactly one '?' character in the question text
#        c. matches at least one lookup keyword (case-insensitive):
#           "what is", "where is", "who owns", "which file", "value of",
#           "how many"
#           (Note: "does" was deliberately excluded — it would false-positive on
#           "how does X work" questions. Yes/no questions land in standard.)
#        d. zero deep keywords present (Stage 1 already excluded by structure,
#           but re-checked to keep Stage 2 self-contained)
#   5. Stage 3 — default -> SCALE=standard.
#
# Asymmetric conservatism: deep fires on any single trigger; quick requires the
# conjunction of all positive signals AND no deep trigger; ambiguity defaults to
# standard. This is a deliberate posture (per dialectic resolution on issue #513
# DECISION_1) so that auto-classification never silently downgrades a broad
# question to a single-lane run.
#
# See classify-research-scale.md for the full contract, callers, and edit-in-sync
# rules.

set -euo pipefail

usage() {
  cat >&2 <<'USAGE'
Usage: classify-research-scale.sh --question <path>

  --question <path>  Required. Path to a file containing the research question
                     (RESEARCH_QUESTION). Must be a regular, readable, non-empty
                     file. Orchestrator confines the path to $RESEARCH_TMPDIR by
                     convention; this script does not enforce that constraint.

Exit 0 on success (with SCALE=<bucket> and REASON=<token> on stdout).
Exit 1 on empty input.
Exit 2 on argument error or bad path.
USAGE
}

QUESTION_PATH=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --question)
      QUESTION_PATH="${2:-}"
      shift 2 || { echo "REASON=missing_arg"; exit 2; }
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "REASON=missing_arg"
      echo "Unknown argument: $1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$QUESTION_PATH" ]]; then
  echo "REASON=missing_arg"
  echo "--question is required." >&2
  exit 2
fi

# Path validation: must exist, be a regular file (or symlink resolving to one),
# and be readable. Mirrors run-research-planner.sh's posture.
if [[ ! -e "$QUESTION_PATH" ]]; then
  echo "REASON=bad_path"
  echo "Question file does not exist: $QUESTION_PATH" >&2
  exit 2
fi

if [[ ! -f "$QUESTION_PATH" ]]; then
  echo "REASON=bad_path"
  echo "Question path is not a regular file: $QUESTION_PATH" >&2
  exit 2
fi

if [[ ! -r "$QUESTION_PATH" ]]; then
  echo "REASON=bad_path"
  echo "Question file is not readable: $QUESTION_PATH" >&2
  exit 2
fi

# Empty-input check (zero-byte file, even if it exists).
if [[ ! -s "$QUESTION_PATH" ]]; then
  echo "REASON=empty_input"
  echo "Question file is empty: $QUESTION_PATH" >&2
  exit 1
fi

# Read the question text into a variable. Trim trailing whitespace for robust
# whitespace-only detection — a file containing only spaces / tabs / newlines
# is treated as empty input (Stage 0 of the rules, defending against orchestrators
# that accidentally write a whitespace-only RESEARCH_QUESTION).
QUESTION_TEXT="$(cat -- "$QUESTION_PATH")"
QUESTION_TRIMMED="${QUESTION_TEXT//[$'\t\r\n ']/}"
if [[ -z "$QUESTION_TRIMMED" ]]; then
  echo "REASON=empty_input"
  echo "Question file contains only whitespace: $QUESTION_PATH" >&2
  exit 1
fi

# Byte length (wc -c counts bytes; for ASCII this equals char count, for UTF-8
# multi-byte chars it inflates length toward "deep" — the conservative direction).
QUESTION_LEN=$(wc -c < "$QUESTION_PATH" | tr -d '[:space:]')

# Count '?' characters across the whole question text.
QUESTION_MARK_COUNT=$(printf '%s' "$QUESTION_TEXT" | tr -cd '?' | wc -c | tr -d '[:space:]')

# Lower-case the question for case-insensitive keyword matching.
QUESTION_LOWER=$(printf '%s' "$QUESTION_TEXT" | tr '[:upper:]' '[:lower:]')

# Deep keyword set. Each keyword is matched as a substring (no word-boundary
# anchoring) — `vulnerab` matches both "vulnerable" and "vulnerability" without
# requiring two list entries; the cost is occasional false positives that are
# acceptable under the asymmetric-conservatism rule (deep is the safe direction).
DEEP_KEYWORDS=(
  "compare"
  "tradeoff"
  "trade-off"
  "audit"
  "architecture"
  "migration"
  "vulnerab"
  "security review"
  "threat model"
  "refactor"
  "design decision"
  "end-to-end"
  "end to end"
  "comprehensive"
)

DEEP_HIT_COUNT=0
for kw in "${DEEP_KEYWORDS[@]}"; do
  if [[ "$QUESTION_LOWER" == *"$kw"* ]]; then
    DEEP_HIT_COUNT=$((DEEP_HIT_COUNT + 1))
  fi
done

# Stage 1 — strong-deep signals (any one fires).
# 1a: length > 600 bytes.
if (( QUESTION_LEN > 600 )); then
  echo "SCALE=deep"
  echo "REASON=length_deep"
  exit 0
fi

# 1b: >=2 deep keyword hits.
if (( DEEP_HIT_COUNT >= 2 )); then
  echo "SCALE=deep"
  echo "REASON=keyword_deep"
  exit 0
fi

# 1c: >=2 '?' characters in the question text.
if (( QUESTION_MARK_COUNT >= 2 )); then
  echo "SCALE=deep"
  echo "REASON=multi_part_deep"
  exit 0
fi

# Stage 2 — strong-quick signals (ALL fire AND no Stage 1 hit).
# 2a: length < 80 bytes.
# 2b: exactly one '?' in the question.
# 2c: at least one lookup keyword present.
# 2d: zero deep keywords (defensive — Stage 1 already excluded >=2 hits, but
# Stage 2 requires ZERO).
if (( QUESTION_LEN < 80 )) && (( QUESTION_MARK_COUNT == 1 )) && (( DEEP_HIT_COUNT == 0 )); then
  LOOKUP_KEYWORDS=(
    "what is"
    "where is"
    "who owns"
    "which file"
    "value of"
    "how many"
  )

  LOOKUP_HIT=0
  for kw in "${LOOKUP_KEYWORDS[@]}"; do
    if [[ "$QUESTION_LOWER" == *"$kw"* ]]; then
      LOOKUP_HIT=1
      break
    fi
  done

  if (( LOOKUP_HIT == 1 )); then
    echo "SCALE=quick"
    echo "REASON=lookup_quick"
    exit 0
  fi
fi

# Stage 3 — default to standard for everything ambiguous.
echo "SCALE=standard"
echo "REASON=default_standard"
exit 0
