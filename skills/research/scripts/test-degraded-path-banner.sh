#!/usr/bin/env bash
# test-degraded-path-banner.sh — Offline regression harness for the /research
# Step 1.5 reduced-diversity banner contract (issue #506).
#
# Two halves:
#   (1) Reference-impl test: synthetic lane-status.txt fixtures × {standard, deep}
#       drive a small bash reference implementation of the banner-emission
#       formula. Asserts banner literal + integer substitutions match the
#       expected output for each fixture, including the all-ok negative case.
#   (2) Prose-pin test: greps skills/research/references/research-phase.md
#       for the byte-stable banner literal, the trigger formulas (standard
#       and deep), and the "research-report.txt" mention proximity.
#
# Wired into `make lint` via the `test-degraded-path-banner` target. See
# `test-degraded-path-banner.md` for the contract, edit-in-sync rules, and
# expected stdout schema.
#
# Exit 0 on all assertions passing; exit 1 on any failure (with diagnostic
# on stderr).

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_PHASE_MD="$REPO_ROOT/skills/research/references/research-phase.md"

# Banner literal — MUST match the literal in research-phase.md §1.5 preamble.
# When changing the banner text, update all three edit-in-sync surfaces in the
# same PR (see test-degraded-path-banner.md "Edit-in-sync surfaces").
BANNER_TEMPLATE='**⚠ Reduced lane diversity: <N_FALLBACK> of <LANE_TOTAL> external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# ---------- Reference implementation (mirror of research-phase.md §1.5 prose) ----------

# Reads RESEARCH_CURSOR_STATUS / RESEARCH_CODEX_STATUS from the fixture file
# (KV format, prefix-strip parsing). Emits the substituted banner literal on
# stdout when N_FALLBACK >= 1, otherwise emits nothing. Mirrors the prose in
# research-phase.md §1.5 banner preamble exactly.
#
# Args:
#   $1 = path to fixture lane-status.txt
#   $2 = scale (standard | deep)
emit_banner() {
  local fixture="$1"
  local scale="$2"
  local cursor_status codex_status
  local cursor_fallback codex_fallback
  local n_fallback lane_total

  # Fallback default per prose ("missing or unreadable" → no banner). The -r
  # check covers the chmod-000 case; a present-but-unreadable file would
  # otherwise let grep collapse to empty values and treat them as fallbacks.
  if [[ ! -f "$fixture" ]] || [[ ! -r "$fixture" ]]; then
    return 0
  fi

  cursor_status="$(grep -E '^RESEARCH_CURSOR_STATUS=' "$fixture" | head -n 1 | sed 's/^RESEARCH_CURSOR_STATUS=//')" || cursor_status=""
  codex_status="$(grep -E '^RESEARCH_CODEX_STATUS=' "$fixture" | head -n 1 | sed 's/^RESEARCH_CODEX_STATUS=//')" || codex_status=""

  if [[ "$cursor_status" == "ok" ]]; then cursor_fallback=0; else cursor_fallback=1; fi
  if [[ "$codex_status" == "ok" ]]; then codex_fallback=0; else codex_fallback=1; fi

  case "$scale" in
    standard)
      n_fallback=$(( cursor_fallback + codex_fallback ))
      lane_total=2
      ;;
    deep)
      n_fallback=$(( 2 * cursor_fallback + 2 * codex_fallback ))
      lane_total=4
      ;;
    *)
      # Internal-only failure path — log and emit empty (no banner). Returning
      # non-zero would abort the harness under `set -e` when called inside
      # command substitution. Callers are expected to pass standard|deep.
      echo "INTERNAL: emit_banner unknown scale '$scale'" >&2
      return 0
      ;;
  esac

  if (( n_fallback >= 1 )); then
    local banner="${BANNER_TEMPLATE/<N_FALLBACK>/$n_fallback}"
    banner="${banner/<LANE_TOTAL>/$lane_total}"
    printf '%s\n' "$banner"
  fi
}

# ---------- Fixture-driven cases ----------

TMPDIR_TEST="$(mktemp -d -t test-degraded-path-banner.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Synthesize a minimal lane-status.txt fixture covering the two RESEARCH_*_STATUS
# keys this harness reads. Other keys are not consulted by emit_banner (the prose
# only reads the two cursor/codex research-phase status values).
write_fixture() {
  local path="$1"
  local cursor_status="$2"
  local codex_status="$3"
  cat > "$path" <<EOF
RESEARCH_CURSOR_STATUS=$cursor_status
RESEARCH_CURSOR_REASON=
RESEARCH_CODEX_STATUS=$codex_status
RESEARCH_CODEX_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
}

# run_case <case-name> <cursor-status> <codex-status> <scale> <expected-banner-or-empty>
run_case() {
  local name="$1"
  local cursor="$2"
  local codex="$3"
  local scale="$4"
  local expected="$5"

  local fixture="$TMPDIR_TEST/${name}.txt"
  write_fixture "$fixture" "$cursor" "$codex"

  local actual
  actual="$(emit_banner "$fixture" "$scale")"

  if [[ "$actual" != "$expected" ]]; then
    fail "[$name | scale=$scale] expected:
  '$expected'
got:
  '$actual'"
    return
  fi
  PASS=$((PASS + 1))
}

# Banner literals expected for each case (with integer substitutions applied).
BANNER_S_1="${BANNER_TEMPLATE/<N_FALLBACK>/1}"; BANNER_S_1="${BANNER_S_1/<LANE_TOTAL>/2}"
BANNER_S_2="${BANNER_TEMPLATE/<N_FALLBACK>/2}"; BANNER_S_2="${BANNER_S_2/<LANE_TOTAL>/2}"
BANNER_D_2="${BANNER_TEMPLATE/<N_FALLBACK>/2}"; BANNER_D_2="${BANNER_D_2/<LANE_TOTAL>/4}"
BANNER_D_4="${BANNER_TEMPLATE/<N_FALLBACK>/4}"; BANNER_D_4="${BANNER_D_4/<LANE_TOTAL>/4}"

# Standard scale × 4 fixtures.
run_case "all-ok"               "ok"                       "ok"                       "standard" ""
run_case "cursor-only-fallback" "fallback_binary_missing"  "ok"                       "standard" "$BANNER_S_1"
run_case "codex-only-fallback"  "ok"                       "fallback_runtime_timeout" "standard" "$BANNER_S_1"
run_case "both-fallback"        "fallback_probe_failed"    "fallback_binary_missing"  "standard" "$BANNER_S_2"

# Deep scale × 4 fixtures (per-slot multiplier yields 0/2/4).
run_case "all-ok-deep"               "ok"                       "ok"                       "deep" ""
run_case "cursor-only-fallback-deep" "fallback_binary_missing"  "ok"                       "deep" "$BANNER_D_2"
run_case "codex-only-fallback-deep"  "ok"                       "fallback_runtime_timeout" "deep" "$BANNER_D_2"
run_case "both-fallback-deep"        "fallback_probe_failed"    "fallback_binary_missing"  "deep" "$BANNER_D_4"

# Empty values count as non-`ok` per prose ("ok is the sole non-fallback token").
run_case "empty-status-standard" "" "" "standard" "$BANNER_S_2"
run_case "empty-status-deep"     "" "" "deep"     "$BANNER_D_4"

# Missing fixture path → no banner (defensive default).
MISSING_FIXTURE_RESULT="$(emit_banner "$TMPDIR_TEST/does-not-exist.txt" "standard")"
if [[ -n "$MISSING_FIXTURE_RESULT" ]]; then
  fail "[missing-fixture] expected empty output (defensive default), got: '$MISSING_FIXTURE_RESULT'"
else
  PASS=$((PASS + 1))
fi

# Unreadable fixture (chmod 000) → no banner. Skip the test on environments
# where the chmod has no effect (e.g., running as root, or a filesystem that
# ignores POSIX permission bits) — `unreadable_test` would still be readable
# and produce a banner.
UNREADABLE_FIXTURE="$TMPDIR_TEST/unreadable.txt"
write_fixture "$UNREADABLE_FIXTURE" "fallback_binary_missing" "fallback_binary_missing"
chmod 000 "$UNREADABLE_FIXTURE"
if [[ ! -r "$UNREADABLE_FIXTURE" ]]; then
  UNREADABLE_RESULT="$(emit_banner "$UNREADABLE_FIXTURE" "standard")"
  if [[ -n "$UNREADABLE_RESULT" ]]; then
    fail "[unreadable-fixture] expected empty output (defensive default per prose), got: '$UNREADABLE_RESULT'"
  else
    PASS=$((PASS + 1))
  fi
else
  echo "SKIP: [unreadable-fixture] chmod 000 had no effect (running as root or non-POSIX filesystem); test inapplicable in this environment" >&2
fi
chmod 644 "$UNREADABLE_FIXTURE" 2>/dev/null || true  # restore for trap cleanup

# ---------- Prose-pin tests against research-phase.md ----------

[[ -f "$RESEARCH_PHASE_MD" ]] || fail "research-phase.md missing: $RESEARCH_PHASE_MD"

# Pin 1: banner literal MUST appear in the file (byte-exact, fence-safe via -F).
if grep -Fq "$BANNER_TEMPLATE" "$RESEARCH_PHASE_MD"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md does not contain the byte-exact banner literal. Update the BANNER_TEMPLATE in this harness AND the §1.5 preamble in research-phase.md AND the structural pin in scripts/test-research-structure.sh in the same PR."
fi

# Pin 2: standard formula text MUST appear.
if grep -Fq 'N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)' "$RESEARCH_PHASE_MD"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md missing standard-mode N_FALLBACK formula literal"
fi

# Pin 3: deep formula text MUST appear.
if grep -Fq '2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)' "$RESEARCH_PHASE_MD"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md missing deep-mode N_FALLBACK formula literal"
fi

# Pin 4: "research-report.txt" mention in the §1.5 preamble (BOTH-outputs contract).
# Extract the §1.5 preamble window: from "## 1.5 — Synthesis" to the first
# "### Standard" heading. The preamble must mention research-report.txt.
SECTION_PREAMBLE="$(awk '/^## 1\.5 — Synthesis/{f=1} f && /^### Standard \(RESEARCH_SCALE=standard/{exit} f' "$RESEARCH_PHASE_MD")"
if [[ -z "$SECTION_PREAMBLE" ]]; then
  fail "research-phase.md does not contain a '## 1.5 — Synthesis' preamble window"
elif grep -Fq "research-report.txt" <<< "$SECTION_PREAMBLE"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md §1.5 preamble must mention research-report.txt (BOTH-outputs contract)"
fi

# ---------- Summary ----------

if (( FAIL > 0 )); then
  echo "test-degraded-path-banner.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-degraded-path-banner.sh — $PASS assertions passed"
exit 0
