#!/usr/bin/env bash
# test-research-banner.sh — Offline regression harness for the /research
# Step 1.5 reduced-diversity banner contract.
#
# Fixture-driven: the canonical executable formula lives in
# `compute-research-banner.sh` (sibling helper). This script forks that
# helper for each fixture and compares stdout against hardcoded expected
# strings.
#
# Required harness coverage:
#   (a) clean run (no fallback) → no banner
#   (b) one Codex angle fell back to Claude → banner with N_FALLBACK=1
#   (c) all 4 Codex angles fell back → banner with N_FALLBACK=4
#   (d) REASON containing literal "fallback_" must NOT trigger the banner
#   (e) VALIDATION_*_STATUS=fallback_* must NOT trigger the banner
#
# Plus:
#   - missing-fixture defensive default
#   - prose pin: banner literal in research-phase.md
#   - canonical pin: BANNER_TEMPLATE in helper byte-equals harness's

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/../../.." && pwd -P)"
RESEARCH_PHASE_MD="$REPO_ROOT/skills/research/references/research-phase.md"
HELPER_SCRIPT="$REPO_ROOT/skills/research/scripts/compute-research-banner.sh"

# Banner template — MUST match BANNER_TEMPLATE in compute-research-banner.sh
# AND the literal in research-phase.md §1.5 preamble.
BANNER_TEMPLATE='**⚠ Reduced lane diversity: <N_FALLBACK> of 4 external research lanes ran as Claude-fallback. The model-family heterogeneity claim does not hold for this run.**'

PASS=0
FAIL=0

fail() {
  echo "FAIL: $1" >&2
  FAIL=$((FAIL + 1))
}

TMPDIR_TEST="$(mktemp -d -t test-research-banner.XXXXXX)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

# write_fixture <path> <arch_status> <edge_status> <ext_status> <sec_status>
# Writes a minimal lane-status.txt fixture with the 4 research-angle keys
# plus 3 default-ok validation keys (so VALIDATION_* false-positive checks
# can be added per fixture as needed).
write_fixture() {
  local path="$1" arch="$2" edge="$3" ext="$4" sec="$5"
  cat > "$path" <<EOF
RESEARCH_ARCH_STATUS=$arch
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=$edge
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=$ext
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=$sec
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
}

run_case() {
  local name="$1" arch="$2" edge="$3" ext="$4" sec="$5" expected="$6"
  local fixture="$TMPDIR_TEST/${name}.txt"
  write_fixture "$fixture" "$arch" "$edge" "$ext" "$sec"
  local actual
  actual="$(bash "$HELPER_SCRIPT" "$fixture")"
  if [[ "$actual" != "$expected" ]]; then
    fail "[$name] expected:
  '$expected'
got:
  '$actual'"
    return
  fi
  PASS=$((PASS + 1))
}

BANNER_1="${BANNER_TEMPLATE/<N_FALLBACK>/1}"
BANNER_4="${BANNER_TEMPLATE/<N_FALLBACK>/4}"

# (a) clean run — no fallback → no banner.
run_case "all-ok" "ok" "ok" "ok" "ok" ""

# (b) one Codex angle fell back to Claude → banner with N_FALLBACK=1.
run_case "one-fallback-arch" "fallback_binary_missing" "ok" "ok" "ok" "$BANNER_1"
run_case "one-fallback-sec"  "ok" "ok" "ok" "fallback_runtime_timeout" "$BANNER_1"

# (c) all 4 Codex angles fell back → banner with N_FALLBACK=4.
run_case "all-four-fallback" \
  "fallback_binary_missing" "fallback_binary_missing" \
  "fallback_runtime_timeout" "fallback_probe_failed" \
  "$BANNER_4"

# (d) REASON containing literal "fallback_" must NOT trigger the banner.
REASON_FIXTURE="$TMPDIR_TEST/reason-text.txt"
cat > "$REASON_FIXTURE" <<'EOF'
RESEARCH_ARCH_STATUS=ok
RESEARCH_ARCH_REASON=earlier run produced fallback_binary_missing but recovered
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=note: lane was suspected of fallback_runtime_timeout
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=ok
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=ok
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=ok
VALIDATION_CODEX_REASON=
EOF
REASON_RESULT="$(bash "$HELPER_SCRIPT" "$REASON_FIXTURE")"
if [[ -n "$REASON_RESULT" ]]; then
  fail "[reason-text-false-positive] expected empty (REASON-text 'fallback_' must not trigger), got: '$REASON_RESULT'"
else
  PASS=$((PASS + 1))
fi

# (e) VALIDATION_*_STATUS=fallback_* must NOT trigger the banner.
VAL_FIXTURE="$TMPDIR_TEST/validation-fallback.txt"
cat > "$VAL_FIXTURE" <<'EOF'
RESEARCH_ARCH_STATUS=ok
RESEARCH_ARCH_REASON=
RESEARCH_EDGE_STATUS=ok
RESEARCH_EDGE_REASON=
RESEARCH_EXT_STATUS=ok
RESEARCH_EXT_REASON=
RESEARCH_SEC_STATUS=ok
RESEARCH_SEC_REASON=
VALIDATION_CODE_STATUS=fallback_runtime_timeout
VALIDATION_CODE_REASON=
VALIDATION_CURSOR_STATUS=fallback_binary_missing
VALIDATION_CURSOR_REASON=
VALIDATION_CODEX_STATUS=fallback_runtime_failed
VALIDATION_CODEX_REASON=
EOF
VAL_RESULT="$(bash "$HELPER_SCRIPT" "$VAL_FIXTURE")"
if [[ -n "$VAL_RESULT" ]]; then
  fail "[validation-fallback-false-positive] expected empty (VALIDATION_* must not affect research banner), got: '$VAL_RESULT'"
else
  PASS=$((PASS + 1))
fi

# Missing fixture path → no banner (defensive default).
MISSING_RESULT="$(bash "$HELPER_SCRIPT" "$TMPDIR_TEST/does-not-exist.txt")"
if [[ -n "$MISSING_RESULT" ]]; then
  fail "[missing-fixture] expected empty output, got: '$MISSING_RESULT'"
else
  PASS=$((PASS + 1))
fi

# ---------- Prose-pin tests against research-phase.md ----------

[[ -f "$RESEARCH_PHASE_MD" ]] || fail "research-phase.md missing: $RESEARCH_PHASE_MD"

# Banner literal MUST appear byte-exact in research-phase.md.
if grep -Fq "$BANNER_TEMPLATE" "$RESEARCH_PHASE_MD"; then
  PASS=$((PASS + 1))
else
  fail "research-phase.md does not contain the byte-exact banner literal. Update BANNER_TEMPLATE in compute-research-banner.sh AND the §1.5 preamble in research-phase.md AND the substituted example in SKILL.md Step 3 AND the fixture expectations in this harness in the same PR."
fi

# ---------- Canonical-executable pins ----------

[[ -f "$HELPER_SCRIPT" ]] || fail "compute-research-banner.sh missing: $HELPER_SCRIPT"
[[ -x "$HELPER_SCRIPT" ]] || fail "compute-research-banner.sh is not executable: $HELPER_SCRIPT"

HELPER_TEMPLATE="$(grep -E '^BANNER_TEMPLATE=' "$HELPER_SCRIPT" | head -n 1 | sed -E "s/^BANNER_TEMPLATE='(.*)'$/\1/")"
if [[ "$HELPER_TEMPLATE" == "$BANNER_TEMPLATE" ]]; then
  PASS=$((PASS + 1))
else
  fail "compute-research-banner.sh BANNER_TEMPLATE drift detected.
  helper:   '$HELPER_TEMPLATE'
  harness:  '$BANNER_TEMPLATE'"
fi

if (( FAIL > 0 )); then
  echo "test-research-banner.sh — $PASS passed, $FAIL failed" >&2
  exit 1
fi

echo "PASS: test-research-banner.sh — $PASS assertions passed"
exit 0
