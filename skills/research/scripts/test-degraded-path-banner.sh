#!/usr/bin/env bash
# test-degraded-path-banner.sh — Offline regression harness for the /research
# Step 1.5 reduced-diversity banner contract (issue #506; refactored to a
# fixture-driven harness under issue #507).
#
# This harness is **fixture-driven** rather than carrying a duplicated
# reference implementation: the canonical executable formula lives in
# `compute-degraded-banner.sh` (sibling helper). This script forks that
# helper for each fixture and compares stdout against hardcoded expected
# strings. The independent oracle is the **fixture table** — drift between
# the helper and prose is caught by fixture-vs-stdout mismatch, without
# requiring two parallel implementations of the same formula.
#
# Two halves:
#   (1) Fixture-driven test: synthetic lane-status.txt fixtures × {standard, deep}
#       fork compute-degraded-banner.sh and compare stdout against expected
#       banner strings (substituted from BANNER_TEMPLATE).
#   (2) Prose-pin test: greps skills/research/references/research-phase.md
#       for the byte-stable banner literal (documentation pin) AND greps
#       compute-degraded-banner.sh for the formula literals (canonical
#       executable pin).
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
HELPER_SCRIPT="$REPO_ROOT/skills/research/scripts/compute-degraded-banner.sh"

# Banner template — MUST match the BANNER_TEMPLATE constant in
# compute-degraded-banner.sh AND the literal in research-phase.md §1.5
# preamble. The harness pins all three (canonical executable + prose +
# fixtures) in the same PR per the 5-surface edit-in-sync rule.
BANNER_TEMPLATE='**⚠ Reduced lane diversity: <N_FALLBACK> of <LANE_TOTAL> external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

# ---------- Fixture table ----------

TMPDIR_TEST="$(mktemp -d -t test-degraded-path-banner.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# Synthesize a minimal lane-status.txt fixture covering the two RESEARCH_*_STATUS
# keys the helper reads. Other keys are not consulted (the helper only reads the
# two cursor/codex research-phase status values).
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
#
# Forks compute-degraded-banner.sh in a subshell and captures stdout.
run_case() {
  local name="$1"
  local cursor="$2"
  local codex="$3"
  local scale="$4"
  local expected="$5"

  local fixture="$TMPDIR_TEST/${name}.txt"
  write_fixture "$fixture" "$cursor" "$codex"

  local actual
  # Trim trailing newline from helper output for byte-exact comparison.
  actual="$(bash "$HELPER_SCRIPT" "$fixture" "$scale")"

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
MISSING_FIXTURE_RESULT="$(bash "$HELPER_SCRIPT" "$TMPDIR_TEST/does-not-exist.txt" "standard")"
if [[ -n "$MISSING_FIXTURE_RESULT" ]]; then
  fail "[missing-fixture] expected empty output (defensive default), got: '$MISSING_FIXTURE_RESULT'"
else
  PASS=$((PASS + 1))
fi

# Unreadable fixture (chmod 000) → no banner. Skip the test on environments
# where the chmod has no effect (e.g., running as root, or a filesystem that
# ignores POSIX permission bits).
UNREADABLE_FIXTURE="$TMPDIR_TEST/unreadable.txt"
write_fixture "$UNREADABLE_FIXTURE" "fallback_binary_missing" "fallback_binary_missing"
chmod 000 "$UNREADABLE_FIXTURE"
if [[ ! -r "$UNREADABLE_FIXTURE" ]]; then
  UNREADABLE_RESULT="$(bash "$HELPER_SCRIPT" "$UNREADABLE_FIXTURE" "standard")"
  if [[ -n "$UNREADABLE_RESULT" ]]; then
    fail "[unreadable-fixture] expected empty output (defensive default per prose), got: '$UNREADABLE_RESULT'"
  else
    PASS=$((PASS + 1))
  fi
else
  echo "SKIP: [unreadable-fixture] chmod 000 had no effect (running as root or non-POSIX filesystem); test inapplicable in this environment" >&2
fi
chmod 644 "$UNREADABLE_FIXTURE" 2>/dev/null || true  # restore for trap cleanup

# Unknown scale → no banner; helper logs to stderr but exits 0.
UNKNOWN_SCALE_FIXTURE="$TMPDIR_TEST/unknown-scale.txt"
write_fixture "$UNKNOWN_SCALE_FIXTURE" "fallback_binary_missing" "fallback_binary_missing"
UNKNOWN_SCALE_RESULT="$(bash "$HELPER_SCRIPT" "$UNKNOWN_SCALE_FIXTURE" "deeper" 2>/dev/null || true)"
if [[ -n "$UNKNOWN_SCALE_RESULT" ]]; then
  fail "[unknown-scale] expected empty output, got: '$UNKNOWN_SCALE_RESULT'"
else
  PASS=$((PASS + 1))
fi

# ---------- Prose-pin tests against research-phase.md (documentation surface) ----------

[[ -f "$RESEARCH_PHASE_MD" ]] || fail "research-phase.md missing: $RESEARCH_PHASE_MD"

# Pin 1: banner literal MUST appear in research-phase.md (byte-exact, fence-safe via -F).
# This is the documentation pin — research-phase.md prose names the banner literal so
# the operator can read it without forking the helper.
if grep -Fq "$BANNER_TEMPLATE" "$RESEARCH_PHASE_MD"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md does not contain the byte-exact banner literal. Update BANNER_TEMPLATE in compute-degraded-banner.sh AND the §1.5 preamble in research-phase.md AND the structural pin in scripts/test-research-structure.sh AND the fixture expectations in this harness in the same PR (5-surface edit-in-sync rule — see compute-degraded-banner.md)."
fi

# Pin 4: "research-report.txt" mention in the §1.5 preamble (BOTH-outputs contract).
SECTION_PREAMBLE="$(awk '/^## 1\.5 — Synthesis/{f=1} f && /^### Standard \(RESEARCH_SCALE=standard/{exit} f' "$RESEARCH_PHASE_MD")"
if [[ -z "$SECTION_PREAMBLE" ]]; then
  fail "research-phase.md does not contain a '## 1.5 — Synthesis' preamble window"
elif grep -Fq "research-report.txt" <<< "$SECTION_PREAMBLE"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md §1.5 preamble must mention research-report.txt (BOTH-outputs contract)"
fi

# ---------- Canonical-executable pins against compute-degraded-banner.sh ----------

[[ -f "$HELPER_SCRIPT" ]] || fail "compute-degraded-banner.sh missing: $HELPER_SCRIPT"
[[ -x "$HELPER_SCRIPT" ]] || fail "compute-degraded-banner.sh is not executable (chmod +x): $HELPER_SCRIPT"

# Pin 2: standard formula text MUST appear in the helper script (canonical executable).
# Moved here from research-phase.md per #507 — the formula is now executable truth.
if grep -Fq 'N_FALLBACK = (RESEARCH_CURSOR_STATUS != ok) + (RESEARCH_CODEX_STATUS != ok)' "$HELPER_SCRIPT"; then
  PASS=$((PASS + 1))
else
  fail "compute-degraded-banner.sh missing standard-mode N_FALLBACK formula literal in comments. The formula must appear as documentation alongside the implementation so a reader can verify the script matches the prose."
fi

# Pin 3: deep formula text MUST appear in the helper script (canonical executable).
if grep -Fq '2*(RESEARCH_CURSOR_STATUS != ok) + 2*(RESEARCH_CODEX_STATUS != ok)' "$HELPER_SCRIPT"; then
  PASS=$((PASS + 1))
else
  fail "compute-degraded-banner.sh missing deep-mode N_FALLBACK formula literal in comments."
fi

# Pin 5: BANNER_TEMPLATE constant in helper MUST byte-equal the harness's BANNER_TEMPLATE.
# This catches drift between the harness fixture expectations and the canonical executable.
HELPER_TEMPLATE="$(grep -E '^BANNER_TEMPLATE=' "$HELPER_SCRIPT" | head -n 1 | sed -E "s/^BANNER_TEMPLATE='(.*)'$/\1/")"
if [[ "$HELPER_TEMPLATE" == "$BANNER_TEMPLATE" ]]; then
  PASS=$((PASS + 1))
else
  fail "compute-degraded-banner.sh BANNER_TEMPLATE drift detected.
  helper:   '$HELPER_TEMPLATE'
  harness:  '$BANNER_TEMPLATE'"
fi

# ---------- Summary ----------

if (( FAIL > 0 )); then
  echo "test-degraded-path-banner.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-degraded-path-banner.sh — $PASS assertions passed"
exit 0
