#!/usr/bin/env bash
# eval-research.sh — Offline harness for measuring /research output quality.
#
# Reads skills/research/references/eval-set.md, runs each entry through
# /research as a fresh `claude -p` subprocess (mirroring the iteration.sh
# pattern), scores the output along deterministic + LLM-as-judge axes, and
# emits a markdown summary table. Opt-in operator instrumentation; NOT a
# CI gate. See scripts/eval-research.md for the full contract.
#
# Source: Anthropic — How we built our multi-agent research system —
# small-sample (~20 case) rubric-based evals catch the low-hanging-fruit
# 30-to-80-percent jumps from prompt tweaks. This harness is the local
# instantiation of that practice.
#
# Usage:
#   bash scripts/eval-research.sh [flags]
#
# Flags:
#   --id <id>             Run only the entry with this id (debugging).
#   --scale <s>           Forwarded to /larch:research as --scale=<s>, manually
#                         overriding the adaptive scale classifier (issue #513).
#                         When --write-baseline is used, the same value is also
#                         recorded in the produced JSON's top-level scale field
#                         so the field accurately reflects the runtime scale.
#                         Default: standard.
#   --baseline <ref>      Pre-fetches the eval-baseline.json file from the
#                         given git ref (sha, tag, or branch) into $WORK_DIR
#                         for manual diffing. Inline delta columns are NOT
#                         yet wired in this PR — a stdout banner makes the
#                         preview-only status visible at run time. The ref
#                         is regex-validated before shell interpolation.
#                         Exits 2 if the ref cannot be resolved.
#   --work-dir <dir>      Per-run scratch base. Default: $(mktemp -d). Each
#                         entry runs in a unique subdirectory under this.
#   --write-baseline <f>  Write the run results in eval-baseline.json shape
#                         to this file path (instead of stdout).
#   --timeout <sec>       Per-question timeout for /research subprocess.
#                         Default: 4200 (above /research's ~3700s composite
#                         budget — Step 1 1860s + Step 2 1860s).
#   --judge-timeout <sec> Per-question timeout for the LLM-as-judge call.
#                         Default: 600.
#   --smoke-test          Parse and schema-validate eval-set.md + baseline
#                         JSON, then exit 0 without invoking claude -p.
#                         No API cost. Used by test-eval-set-structure.sh.
#   --help                Print this header and exit 0.
#
# Output (stdout):
#   When --write-baseline is unset, emits a markdown summary table.
#   When --write-baseline is set, writes JSON to that path; stdout shows
#   only progress breadcrumbs and a one-line summary.
#
# Exit codes:
#   0 — harness ran (individual per-entry timeouts/parse-failures are
#       reported in the status column, not the exit code).
#   1 — schema validation of eval-set.md or eval-baseline.json failed.
#   2 — argument parse error or invalid argument value (e.g., bad timeout
#       integer, regex-invalid baseline ref, baseline ref that cannot be
#       resolved via git show, or a value-taking flag with no following
#       value such as a trailing `--baseline`).
#   3 — required tooling missing (claude, jq, awk).
#
# Security: --baseline accepts only [0-9A-Za-z_./-]+ to avoid shell
# injection into git show. See OOS_1 in the tracking issue for #419.

set -euo pipefail

# ---- CLAUDE_PLUGIN_ROOT bootstrap ----------------------------------------
# Layout: ${CLAUDE_PLUGIN_ROOT}/scripts/eval-research.sh
# So the plugin root is one directory up from this script.
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  CLAUDE_PLUGIN_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
  export CLAUDE_PLUGIN_ROOT
fi

EVAL_SET_FILE="${CLAUDE_PLUGIN_ROOT}/skills/research/references/eval-set.md"
EVAL_BASELINE_FILE="${CLAUDE_PLUGIN_ROOT}/skills/research/references/eval-baseline.json"
# Source attribution: Anthropic — How we built our multi-agent research system.
# URL: anthropic.com/engineering/built-multi-agent-research-system — pinned by
# scripts/test-eval-set-structure.sh Check 8 (literal substring grep) so a
# future edit cannot drop the source-attribution silently.

# ---- Argument parsing ----------------------------------------------------
ID_FILTER=""
SCALE="standard"
BASELINE_REF=""
WORK_DIR=""
WRITE_BASELINE_FILE=""
TIMEOUT_SECONDS="4200"
JUDGE_TIMEOUT_SECONDS="600"
SMOKE_TEST="false"

print_usage() {
  awk '/^# Usage:/,/^# Security:/' "${BASH_SOURCE[0]}" | sed 's/^# \?//'
}

# Guard for value-taking flags. Without this, a trailing flag with no
# following value (e.g. `eval-research.sh --baseline`) reaches `shift 2`
# with only one positional left, which fails under `set -e` and exits
# with code 1 — colliding with the documented schema-validation exit
# code (issue #477). Routing missing values to exit 2 lines up with the
# script's other argument-parse errors (unknown argument, regex-invalid
# baseline ref).
require_value() {
  if (( $2 < 2 )); then
    printf 'eval-research: %s requires a value\n' "$1" >&2
    exit 2
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --id) require_value "$1" "$#"; ID_FILTER="${2:-}"; shift 2 ;;
    --scale) require_value "$1" "$#"; SCALE="${2:-standard}"; shift 2 ;;
    --baseline) require_value "$1" "$#"; BASELINE_REF="${2:-}"; shift 2 ;;
    --work-dir) require_value "$1" "$#"; WORK_DIR="${2:-}"; shift 2 ;;
    --write-baseline) require_value "$1" "$#"; WRITE_BASELINE_FILE="${2:-}"; shift 2 ;;
    --timeout) require_value "$1" "$#"; TIMEOUT_SECONDS="${2:-4200}"; shift 2 ;;
    --judge-timeout) require_value "$1" "$#"; JUDGE_TIMEOUT_SECONDS="${2:-600}"; shift 2 ;;
    --smoke-test) SMOKE_TEST="true"; shift ;;
    --help|-h) print_usage; exit 0 ;;
    *)
      printf 'eval-research: unknown argument: %s\n' "$1" >&2
      print_usage >&2
      exit 2
      ;;
  esac
done

# Validate timeout values are positive integers (a typo like `--timeout abc`
# would otherwise abort the run mid-poll-loop under set -e with an opaque
# "integer expression expected" error).
if ! [[ "$TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( TIMEOUT_SECONDS < 1 )); then
  printf 'eval-research: --timeout must be a positive integer (got: %s)\n' "$TIMEOUT_SECONDS" >&2
  exit 2
fi
if ! [[ "$JUDGE_TIMEOUT_SECONDS" =~ ^[0-9]+$ ]] || (( JUDGE_TIMEOUT_SECONDS < 1 )); then
  printf 'eval-research: --judge-timeout must be a positive integer (got: %s)\n' "$JUDGE_TIMEOUT_SECONDS" >&2
  exit 2
fi

# ---- Tooling check (skipped under --smoke-test) --------------------------
require_tool() {
  command -v "$1" >/dev/null 2>&1 || {
    printf 'eval-research: required tool missing: %s\n' "$1" >&2
    exit 3
  }
}
require_tool awk
if [[ "$SMOKE_TEST" != "true" ]]; then
  require_tool claude
  require_tool jq
fi

# ---- Validate baseline ref against strict regex --------------------------
# (OOS_1 from the plan-review panel — guards git show interpolation.)
if [[ -n "$BASELINE_REF" ]]; then
  if ! [[ "$BASELINE_REF" =~ ^[0-9A-Za-z._/-]+$ ]]; then
    printf 'eval-research: --baseline ref must match ^[0-9A-Za-z._/-]+$ (got: %s)\n' "$BASELINE_REF" >&2
    exit 2
  fi
fi

# ---- Eval-set parser -----------------------------------------------------
# Extract entries from eval-set.md into a TSV stream:
#   id<TAB>category<TAB>expected_provenance_count<TAB>expected_keywords<TAB>question<TAB>notes
# One line per entry. Uses awk to walk the file, accumulating field values
# under each `### eval-N: <id>` heading until the next heading.
parse_eval_set() {
  local file="$1"
  awk '
    function emit() {
      if (id != "") {
        gsub(/\t/, " ", q); gsub(/\t/, " ", k); gsub(/\t/, " ", n)
        printf "%s\t%s\t%s\t%s\t%s\t%s\n", id, cat, prov, k, q, n
      }
      id=""; cat=""; prov=""; k=""; q=""; n=""
    }
    /^### eval-/ {
      emit()
      sub(/^### eval-[0-9]+:[[:space:]]*/, "")
      id=$0
      next
    }
    /^- \*\*question\*\*:[[:space:]]/ {
      sub(/^- \*\*question\*\*:[[:space:]]+/, "")
      q=$0
      next
    }
    /^- \*\*category\*\*:[[:space:]]/ {
      sub(/^- \*\*category\*\*:[[:space:]]+/, "")
      cat=$0
      next
    }
    /^- \*\*expected_provenance_count\*\*:[[:space:]]/ {
      sub(/^- \*\*expected_provenance_count\*\*:[[:space:]]+/, "")
      prov=$0
      next
    }
    /^- \*\*expected_keywords\*\*:[[:space:]]/ {
      sub(/^- \*\*expected_keywords\*\*:[[:space:]]+/, "")
      k=$0
      next
    }
    /^- \*\*notes\*\*:[[:space:]]/ {
      sub(/^- \*\*notes\*\*:[[:space:]]+/, "")
      n=$0
      next
    }
    END { emit() }
  ' "$file"
}

# ---- Schema validation ---------------------------------------------------
validate_eval_set() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'eval-research: eval-set.md not found at %s\n' "$file" >&2
    return 1
  fi
  local count=0
  local rc=0
  local seen_categories=""
  local seen_ids=""
  while IFS=$'\t' read -r id cat prov kw q notes; do
    if [[ -z "$id" || -z "$cat" || -z "$prov" || -z "$kw" || -z "$q" || -z "$notes" ]]; then
      printf 'eval-research: entry has missing field(s): id=%s cat=%s prov=%s\n' "$id" "$cat" "$prov" >&2
      rc=1
      continue
    fi
    if ! [[ "$id" =~ ^[a-z0-9-]+$ ]]; then
      printf 'eval-research: entry has invalid id (must match ^[a-z0-9-]+$ — lowercase letters, digits, and hyphens only): %s\n' "$id" >&2
      rc=1
    else
      # Duplicate check is gated on format validity so glob metacharacters
      # in $id (e.g. `*`, `?`, `[`) cannot leak into the case-pattern below.
      case "$seen_ids" in
        *"|$id|"*)
          printf 'eval-research: duplicate eval id: %s\n' "$id" >&2
          rc=1
          ;;
        *) seen_ids="${seen_ids}|$id|" ;;
      esac
    fi
    case "$cat" in
      lookup|architecture|external-comparison|risk-assessment|feasibility) ;;
      *)
        printf 'eval-research: entry %s has unknown category: %s\n' "$id" "$cat" >&2
        rc=1
        ;;
    esac
    if ! [[ "$prov" =~ ^[0-9]+$ ]]; then
      printf 'eval-research: entry %s expected_provenance_count not integer: %s\n' "$id" "$prov" >&2
      rc=1
    fi
    case "$seen_categories" in
      *"|$cat|"*) ;;
      *) seen_categories="${seen_categories}|$cat|" ;;
    esac
    count=$((count + 1))
  done < <(parse_eval_set "$file")

  if (( count < 20 )); then
    printf 'eval-research: eval-set.md has %d entries; need at least 20\n' "$count" >&2
    rc=1
  fi
  for required_cat in lookup architecture external-comparison risk-assessment feasibility; do
    case "$seen_categories" in
      *"|$required_cat|"*) ;;
      *)
        printf 'eval-research: eval-set.md missing entries from category: %s\n' "$required_cat" >&2
        rc=1
        ;;
    esac
  done
  return $rc
}

validate_baseline_json() {
  local file="$1"
  if [[ ! -f "$file" ]]; then
    printf 'eval-research: eval-baseline.json not found at %s\n' "$file" >&2
    return 1
  fi
  if command -v jq >/dev/null 2>&1; then
    if ! jq -e '.version and .scale and (.entries | type == "array")' "$file" >/dev/null 2>&1; then
      printf 'eval-research: eval-baseline.json missing required keys (version, scale, entries)\n' >&2
      return 1
    fi
  else
    if ! grep -q '"version"' "$file"; then
      printf 'eval-research: eval-baseline.json missing required key: version (jq not available; using grep fallback)\n' >&2
      return 1
    fi
    if ! grep -q '"scale"' "$file"; then
      printf 'eval-research: eval-baseline.json missing required key: scale (jq not available; using grep fallback)\n' >&2
      return 1
    fi
    if ! grep -q '"entries"' "$file"; then
      printf 'eval-research: eval-baseline.json missing required key: entries (jq not available; using grep fallback)\n' >&2
      return 1
    fi
  fi
  return 0
}

# ---- Smoke-test path -----------------------------------------------------
if [[ "$SMOKE_TEST" == "true" ]]; then
  validate_eval_set "$EVAL_SET_FILE" || exit 1
  validate_baseline_json "$EVAL_BASELINE_FILE" || exit 1
  printf 'eval-research: smoke test PASS — eval-set.md + eval-baseline.json schema OK\n'
  exit 0
fi

# ---- Set up work dir -----------------------------------------------------
if [[ -z "$WORK_DIR" ]]; then
  WORK_DIR="$(mktemp -d -t eval-research-XXXXXX)"
fi
mkdir -p "$WORK_DIR"
printf 'eval-research: work dir = %s\n' "$WORK_DIR"

# ---- Per-question subprocess invocation ----------------------------------
# Mirrors the stdin-file + stderr-sidecar + poll-loop pattern from
# skills/improve-skill/scripts/iteration.sh's invoke_claude_p, with
# numeric timeouts decoupled (this harness's defaults are higher to
# accommodate /research's composite budget).
build_research_prompt() {
  local question="$1"
  # Forward --scale=$SCALE so /research's adaptive classifier (issue #513) is
  # bypassed and the harness deterministically tests the labeled scale. Without
  # this forwarding, baseline runs labeled $SCALE could silently execute at a
  # different scale via auto-classification, breaking baseline comparability.
  printf '/larch:research --scale=%s %s\n' "$SCALE" "$question"
}

run_one_research() {
  local id="$1"
  local question="$2"
  local out_dir="$WORK_DIR/$id"
  local prompt_file="$out_dir/prompt.txt"
  local out_file="$out_dir/research.md"
  local stderr_file="$out_dir/research.stderr"
  local timing_file="$out_dir/timing.txt"
  mkdir -p "$out_dir"

  build_research_prompt "$question" > "$prompt_file"
  : > "$out_file"
  : > "$stderr_file"

  local start_epoch end_epoch rc=0
  start_epoch="$(date +%s)"

  # `|| rc=$?` keeps `set -e` from aborting the function when the subshell
  # exits non-zero, so the timing.txt write below always runs — failed and
  # timed-out entries get accurate wall-clock data, not a silent 0s.
  (
    cd "$CLAUDE_PLUGIN_ROOT"
    claude -p --plugin-dir "$CLAUDE_PLUGIN_ROOT" \
      < "$prompt_file" > "$out_file" 2> "$stderr_file" &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if [[ "$elapsed" -ge "$TIMEOUT_SECONDS" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 5
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        printf 'TIMED_OUT_AFTER=%s\n' "$TIMEOUT_SECONDS" >> "$stderr_file"
        exit 124
      fi
      sleep 10
      elapsed=$((elapsed + 10))
    done
    wait "$pid"
    exit $?
  ) || rc=$?

  end_epoch="$(date +%s)"
  printf 'WALL_CLOCK_SECONDS=%s\n' "$((end_epoch - start_epoch))" > "$timing_file"
  printf 'EXIT_CODE=%s\n' "$rc" >> "$timing_file"

  return $rc
}

# ---- Deterministic scorer ------------------------------------------------
# Three orthogonal counters (#FINDING_6 from the plan-review panel):
#   prov_file_line: matches like "scripts/foo.sh:42" or "skills/x/SKILL.md:100"
#   prov_repo_path: matches like "scripts/foo.sh" without :line (also catches
#                   path mentions inside "Key Files and Areas" section)
#   prov_url:       matches https?:// URLs
#
# Keyword-coverage: case-insensitive substring on lowercased text. A keyword
# is "covered" if it appears anywhere in the report; coverage = covered/total.
score_deterministic() {
  local out_file="$1"
  local expected_keywords="$2"
  local lowered
  lowered="$(tr '[:upper:]' '[:lower:]' < "$out_file")"

  local prov_file_line prov_repo_path prov_url
  # Match file:line citations with mixed-case extensions (e.g. `.MD`, `.SH`)
  # AND extensionless basenames like `Makefile:42`, `Dockerfile:10` (which
  # fall on the `[A-Za-z0-9_/.-]+:[0-9]+` branch since the prior `\.[a-z]+`
  # required a lowercase extension).
  prov_file_line="$(grep -oE '[A-Za-z0-9_/.-]+:[0-9]+' "$out_file" | grep -vE '^https?:|^[0-9]+:[0-9]+$' | sort -u | wc -l | tr -d ' ')"
  prov_repo_path="$(grep -oE '(scripts|skills|hooks|docs|tests|agents)/[A-Za-z0-9_/.-]+' "$out_file" | sort -u | wc -l | tr -d ' ')"
  prov_url="$(grep -oE 'https?://[A-Za-z0-9._/?#&=%-]+' "$out_file" | sort -u | wc -l | tr -d ' ')"

  local total_kw matched_kw
  total_kw=0
  matched_kw=0
  while IFS=, read -r -d ',' kw || [[ -n "$kw" ]]; do
    kw="$(printf '%s' "$kw" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr '[:upper:]' '[:lower:]')"
    [[ -z "$kw" ]] && continue
    total_kw=$((total_kw + 1))
    if printf '%s' "$lowered" | grep -qF -- "$kw"; then
      matched_kw=$((matched_kw + 1))
    fi
  done <<< "${expected_keywords},"

  local kw_pct
  if (( total_kw > 0 )); then
    kw_pct=$((matched_kw * 100 / total_kw))
  else
    kw_pct=0
  fi

  local length
  length="$(wc -l < "$out_file" | tr -d ' ')"

  printf 'PROV_FILE_LINE=%s\nPROV_REPO_PATH=%s\nPROV_URL=%s\nKW_TOTAL=%s\nKW_MATCHED=%s\nKW_PCT=%s\nLENGTH=%s\n' \
    "$prov_file_line" "$prov_repo_path" "$prov_url" \
    "$total_kw" "$matched_kw" "$kw_pct" "$length"
}

# ---- LLM-as-judge --------------------------------------------------------
# The judge prompt is a literal heredoc embedded here (not in references/)
# because it is shell-machinery, not a sub-skill body. The contract enforces
# a fail-closed structured output — malformed responses route to status
# JUDGE_PARSE_FAILED with null scores rather than a default mid-range.
JUDGE_RUBRIC=$(cat <<'JUDGE_PROMPT_EOF'
You are a strict evaluator of /research outputs. Read the question, the research synthesis, and the expected_keywords list, then score the synthesis along five dimensions (each 0-20, total 0-100). Output MUST be exactly the format below — no preamble, no commentary, no markdown.

If the research synthesis claims something the evidence does not support, score factual_accuracy 0-5. If it admits "we don't have data" when the question targets data that does not exist, score factual_accuracy 16-20. Do not invent intermediate scores; if uncertain, score lower.

For citation_accuracy: count whether file/path citations are real (the file actually exists in the repo as cited) and whether URL citations are reputable (anthropic.com, openai.com, *.gov, *.edu, official docs > random Medium/blog posts).

For tool_efficiency: did the synthesis use minimal tool calls relative to the depth of the answer?

Output exactly these six lines:
JUDGE_SCORE_FACTUAL=<0-20>
JUDGE_SCORE_CITATION=<0-20>
JUDGE_SCORE_COMPLETENESS=<0-20>
JUDGE_SCORE_SOURCE_QUALITY=<0-20>
JUDGE_SCORE_TOOL_EFFICIENCY=<0-20>
JUDGE_SCORE_TOTAL=<0-100>

Then one line: JUDGE_RATIONALE=<single-line summary, no newlines>
JUDGE_PROMPT_EOF
)

run_judge() {
  local id="$1"
  local question="$2"
  local research_file="$3"
  local expected_keywords="$4"
  local out_dir="$WORK_DIR/$id"
  local judge_prompt_file="$out_dir/judge-prompt.txt"
  local judge_out_file="$out_dir/judge.txt"
  local judge_err_file="$out_dir/judge.stderr"

  {
    printf '%s\n\n' "$JUDGE_RUBRIC"
    printf 'QUESTION: %s\n\n' "$question"
    printf 'EXPECTED_KEYWORDS: %s\n\n' "$expected_keywords"
    printf 'RESEARCH SYNTHESIS:\n---\n'
    cat "$research_file"
    printf '\n---\n'
  } > "$judge_prompt_file"

  : > "$judge_out_file"
  : > "$judge_err_file"

  local rc=0
  (
    cd "$CLAUDE_PLUGIN_ROOT"
    claude -p --plugin-dir "$CLAUDE_PLUGIN_ROOT" \
      < "$judge_prompt_file" > "$judge_out_file" 2> "$judge_err_file" &
    pid=$!
    elapsed=0
    while kill -0 "$pid" 2>/dev/null; do
      if [[ "$elapsed" -ge "$JUDGE_TIMEOUT_SECONDS" ]]; then
        kill "$pid" 2>/dev/null || true
        sleep 5
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        exit 124
      fi
      sleep 5
      elapsed=$((elapsed + 5))
    done
    wait "$pid"
    exit $?
  ) || rc=$?
  return $rc
}

# Fail-closed parser. Mirrors the discipline of
# scripts/parse-skill-judge-grade.sh: any malformed input yields a single
# JUDGE_STATUS=parse_failed line with all numeric fields null. Required
# fields: TOTAL plus all five per-dimension scores. Range checks use a
# decimal regex so leading-zero values (e.g. `0100`) cannot smuggle past
# the `(( ))` arithmetic comparison via octal interpretation.
parse_judge_output() {
  local judge_file="$1"
  if [[ ! -s "$judge_file" ]]; then
    printf 'JUDGE_STATUS=parse_failed\nJUDGE_TOTAL=null\n'
    return 0
  fi

  local total f c m q t
  total="$(grep -oE '^JUDGE_SCORE_TOTAL=[0-9]+' "$judge_file" | head -1 | sed 's/JUDGE_SCORE_TOTAL=//')"
  f="$(grep -oE '^JUDGE_SCORE_FACTUAL=[0-9]+' "$judge_file" | head -1 | sed 's/.*=//')"
  c="$(grep -oE '^JUDGE_SCORE_CITATION=[0-9]+' "$judge_file" | head -1 | sed 's/.*=//')"
  m="$(grep -oE '^JUDGE_SCORE_COMPLETENESS=[0-9]+' "$judge_file" | head -1 | sed 's/.*=//')"
  q="$(grep -oE '^JUDGE_SCORE_SOURCE_QUALITY=[0-9]+' "$judge_file" | head -1 | sed 's/.*=//')"
  t="$(grep -oE '^JUDGE_SCORE_TOOL_EFFICIENCY=[0-9]+' "$judge_file" | head -1 | sed 's/.*=//')"

  # All six fields required (Codex review #1: parser was previously too
  # permissive on missing per-dimension scores).
  if [[ -z "$total" || -z "$f" || -z "$c" || -z "$m" || -z "$q" || -z "$t" ]]; then
    printf 'JUDGE_STATUS=parse_failed\nJUDGE_TOTAL=null\n'
    return 0
  fi

  # Decimal-only range checks (Cursor review #2: octal interpretation in
  # `(( ))` would silently miscompare values like `0100`).
  if ! [[ "$total" =~ ^(100|[1-9]?[0-9])$ ]]; then
    printf 'JUDGE_STATUS=parse_failed\nJUDGE_TOTAL=null\n'
    return 0
  fi
  local v
  for v in "$f" "$c" "$m" "$q" "$t"; do
    if ! [[ "$v" =~ ^(20|1?[0-9])$ ]]; then
      printf 'JUDGE_STATUS=parse_failed\nJUDGE_TOTAL=null\n'
      return 0
    fi
  done

  printf 'JUDGE_STATUS=ok\nJUDGE_FACTUAL=%s\nJUDGE_CITATION=%s\nJUDGE_COMPLETENESS=%s\nJUDGE_SOURCE_QUALITY=%s\nJUDGE_TOOL_EFFICIENCY=%s\nJUDGE_TOTAL=%s\n' \
    "$f" "$c" "$m" "$q" "$t" "$total"
}

# ---- Domain-reputability classifier (external-comparison only) -----------
# Scans URLs in the research output and counts high vs low reputability.
classify_url_reputability() {
  local out_file="$1"
  local high=0 low=0 unknown=0
  while read -r url; do
    [[ -z "$url" ]] && continue
    case "$url" in
      *anthropic.com*|*openai.com*|*.gov*|*.edu*|*deepmind.com*|*microsoft.com/research*|*arxiv.org*|*nature.com*) high=$((high + 1)) ;;
      *medium.com*|*dev.to*|*.blog*|*substack.com*|*hashnode.dev*) low=$((low + 1)) ;;
      *) unknown=$((unknown + 1)) ;;
    esac
  done < <(grep -oE 'https?://[A-Za-z0-9._/?#&=%-]+' "$out_file" | sort -u)
  printf 'URL_HIGH=%s\nURL_LOW=%s\nURL_UNKNOWN=%s\n' "$high" "$low" "$unknown"
}

# ---- Main loop -----------------------------------------------------------
validate_eval_set "$EVAL_SET_FILE" || exit 1
validate_baseline_json "$EVAL_BASELINE_FILE" || exit 1

# Optional baseline pull. The summary-table delta column is not yet wired
# in this PR — operators get the baseline JSON cached under $WORK_DIR for
# manual diffing or future amendment, but no inline columns. A stdout
# banner (alongside the existing stderr WARNING) keeps the preview-only
# status visible on the same stream operators read for results, so the
# flag cannot be mistaken for a successful comparison run. An unresolvable
# ref is treated as an invalid argument value (exit 2) rather than a
# silent no-op, since the bad-ref path otherwise produces a normal-looking
# summary table with no baseline behind it.
BASELINE_ROWS_FILE=""
if [[ -n "$BASELINE_REF" ]]; then
  BASELINE_ROWS_FILE="$WORK_DIR/baseline-rows.json"
  baseline_git_err="$WORK_DIR/baseline-git-stderr.log"
  if git -C "$CLAUDE_PLUGIN_ROOT" show "${BASELINE_REF}:skills/research/references/eval-baseline.json" > "$BASELINE_ROWS_FILE" 2>"$baseline_git_err"; then
    # Validate the schema of the cached blob. A ref where the baseline JSON has
    # drifted (missing required keys, malformed entries) would otherwise still
    # print the success banner and exit 0, which is the same misleading-success
    # failure mode #441 fixed for unresolvable refs. Reuse the same validator
    # that the local EVAL_BASELINE_FILE is checked against on line 532.
    if ! validate_baseline_json "$BASELINE_ROWS_FILE"; then
      printf 'eval-research: ERROR — baseline ref %s resolved but the cached JSON failed schema validation (see preceding diagnostic); aborting.\n' "$BASELINE_REF" >&2
      rm -f "$BASELINE_ROWS_FILE" "$baseline_git_err"
      exit 2
    fi
    printf 'eval-research: baseline ref %s cached at %s\n' "$BASELINE_REF" "$BASELINE_ROWS_FILE"
    printf '\neval-research: --baseline: PREVIEW MODE — baseline JSON pre-fetched to %s; inline delta columns are not yet wired in this PR (a future amendment will add them).\n\n' "$BASELINE_ROWS_FILE"
    printf 'eval-research: WARNING — --baseline delta columns are not yet wired in this PR; the baseline JSON is cached at the path printed above for manual diffing or future amendment, but no inline comparison column appears in the summary table.\n' >&2
    rm -f "$baseline_git_err"
  else
    printf 'eval-research: ERROR — --baseline ref %s could not be resolved via git show; aborting (would otherwise produce a misleading run with no baseline behind it).\n' "$BASELINE_REF" >&2
    if [[ -s "$baseline_git_err" ]]; then
      printf 'eval-research: git show stderr (last 5 lines):\n' >&2
      tail -n 5 "$baseline_git_err" | sed 's/^/  /' >&2
    fi
    rm -f "$BASELINE_ROWS_FILE" "$baseline_git_err"
    exit 2
  fi
fi

# Resolve git harness commit (informational; recorded in --write-baseline output).
HARNESS_COMMIT=""
if HARNESS_COMMIT="$(git -C "$CLAUDE_PLUGIN_ROOT" rev-parse HEAD 2>/dev/null)"; then :; else HARNESS_COMMIT=""; fi

# Header for stdout summary table.
SUMMARY_HEADER='| id | category | prov_fl | prov_path | prov_url | kw% | len | judge | wall(s) | status |'
SUMMARY_DIVIDER='|----|----------|---------|-----------|----------|-----|-----|-------|---------|--------|'

ROW_FILES=()
ENTRIES_RUN=0

while IFS=$'\t' read -r id cat prov kw question notes; do
  if [[ -n "$ID_FILTER" && "$id" != "$ID_FILTER" ]]; then
    continue
  fi
  ENTRIES_RUN=$((ENTRIES_RUN + 1))
  printf '\n--- eval-research: running entry %s (category=%s) ---\n' "$id" "$cat"

  # Run /research.
  if run_one_research "$id" "$question"; then
    research_status="ok"
  elif [[ -f "$WORK_DIR/$id/research.stderr" ]] && grep -q '^TIMED_OUT_AFTER=' "$WORK_DIR/$id/research.stderr"; then
    research_status="timeout"
  else
    research_status="research_failed"
  fi

  # Score deterministic.
  if [[ "$research_status" == "ok" || -s "$WORK_DIR/$id/research.md" ]]; then
    det_kv="$(score_deterministic "$WORK_DIR/$id/research.md" "$kw")"
  else
    det_kv='PROV_FILE_LINE=0
PROV_REPO_PATH=0
PROV_URL=0
KW_TOTAL=0
KW_MATCHED=0
KW_PCT=0
LENGTH=0'
  fi

  # Eval external-comparison entries get URL-reputability data written to a
  # side-output file under the entry's work-dir so future reporting amendments
  # can wire it into the summary table without re-running the eval.
  if [[ "$cat" == "external-comparison" ]]; then
    classify_url_reputability "$WORK_DIR/$id/research.md" \
      > "$WORK_DIR/$id/url-reputability.txt" 2>/dev/null \
      || printf 'URL_HIGH=0\nURL_LOW=0\nURL_UNKNOWN=0\n' > "$WORK_DIR/$id/url-reputability.txt"
  fi

  # Run judge if research succeeded.
  judge_kv=""
  if [[ "$research_status" == "ok" && -s "$WORK_DIR/$id/research.md" ]]; then
    if run_judge "$id" "$question" "$WORK_DIR/$id/research.md" "$kw"; then
      judge_kv="$(parse_judge_output "$WORK_DIR/$id/judge.txt")"
    else
      judge_kv='JUDGE_STATUS=judge_call_failed
JUDGE_TOTAL=null'
    fi
  else
    judge_kv='JUDGE_STATUS=skipped_no_research
JUDGE_TOTAL=null'
  fi

  wall="$(grep -oE '^WALL_CLOCK_SECONDS=[0-9]+' "$WORK_DIR/$id/timing.txt" 2>/dev/null | head -1 | sed 's/.*=//' || printf '0')"
  prov_fl="$(printf '%s' "$det_kv" | grep -oE '^PROV_FILE_LINE=[0-9]+' | head -1 | sed 's/.*=//')"
  prov_path="$(printf '%s' "$det_kv" | grep -oE '^PROV_REPO_PATH=[0-9]+' | head -1 | sed 's/.*=//')"
  prov_url="$(printf '%s' "$det_kv" | grep -oE '^PROV_URL=[0-9]+' | head -1 | sed 's/.*=//')"
  kw_pct="$(printf '%s' "$det_kv" | grep -oE '^KW_PCT=[0-9]+' | head -1 | sed 's/.*=//')"
  length="$(printf '%s' "$det_kv" | grep -oE '^LENGTH=[0-9]+' | head -1 | sed 's/.*=//')"
  judge_total="$(printf '%s' "$judge_kv" | grep -oE '^JUDGE_TOTAL=[0-9a-z]+' | head -1 | sed 's/.*=//')"
  judge_status="$(printf '%s' "$judge_kv" | grep -oE '^JUDGE_STATUS=[a-z_]+' | head -1 | sed 's/.*=//')"

  # Compose row file (NDJSON-style; one entry per line) for --write-baseline.
  row_file="$WORK_DIR/$id/row.json"
  jq -nc \
    --arg id "$id" --arg cat "$cat" \
    --argjson prov_fl "${prov_fl:-0}" --argjson prov_path "${prov_path:-0}" \
    --argjson prov_url "${prov_url:-0}" --argjson kw_pct "${kw_pct:-0}" \
    --argjson length "${length:-0}" \
    --arg judge_total "${judge_total:-null}" \
    --arg judge_status "${judge_status:-unknown}" \
    --argjson wall "${wall:-0}" \
    --arg research_status "$research_status" \
    '{id:$id, category:$cat, provenance:{file_line:$prov_fl, repo_path:$prov_path, url:$prov_url}, keyword_coverage_pct:$kw_pct, length_lines:$length, judge_total:(if $judge_total=="null" then null else ($judge_total|tonumber) end), judge_status:$judge_status, wall_clock_seconds:$wall, research_status:$research_status}' \
    > "$row_file" 2>/dev/null || printf '{"id":"%s","error":"row write failed"}\n' "$id" > "$row_file"
  ROW_FILES+=("$row_file")

  # Print row to stdout.
  if (( ENTRIES_RUN == 1 )); then
    printf '\n%s\n%s\n' "$SUMMARY_HEADER" "$SUMMARY_DIVIDER"
  fi
  printf '| %s | %s | %s | %s | %s | %s%% | %s | %s | %s | %s |\n' \
    "$id" "$cat" "${prov_fl:-?}" "${prov_path:-?}" "${prov_url:-?}" "${kw_pct:-?}" \
    "${length:-?}" "${judge_total:-?}" "${wall:-?}" "$research_status/$judge_status"

done < <(parse_eval_set "$EVAL_SET_FILE")

# ---- Write baseline JSON if requested ------------------------------------
if [[ -n "$WRITE_BASELINE_FILE" ]]; then
  GENERATED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  ENTRIES_JSON="["
  first="true"
  for row in "${ROW_FILES[@]}"; do
    [[ -s "$row" ]] || continue
    if [[ "$first" == "true" ]]; then
      ENTRIES_JSON="$ENTRIES_JSON$(cat "$row")"
      first="false"
    else
      ENTRIES_JSON="$ENTRIES_JSON,$(cat "$row")"
    fi
  done
  ENTRIES_JSON="$ENTRIES_JSON]"
  jq -n \
    --argjson v 1 \
    --arg sc "$SCALE" \
    --arg hc "${HARNESS_COMMIT:-null}" \
    --arg ga "$GENERATED_AT" \
    --argjson ent "$ENTRIES_JSON" \
    '{version:$v, harness_commit:(if $hc=="null" then null else $hc end), model_id:null, scale:$sc, generated_at:$ga, entries:$ent}' \
    > "$WRITE_BASELINE_FILE"
  printf 'eval-research: baseline written to %s\n' "$WRITE_BASELINE_FILE"
fi

if (( ENTRIES_RUN == 0 )); then
  printf '\neval-research: no entries matched (--id %s); nothing to do.\n' "$ID_FILTER" >&2
  exit 0
fi

printf '\neval-research: complete — %d entries run\n' "$ENTRIES_RUN"
exit 0
