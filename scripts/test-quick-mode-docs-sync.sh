#!/usr/bin/env bash
# test-quick-mode-docs-sync.sh — Cross-validation harness asserting that the
# public quick-mode description in the user-facing docs (README.md,
# docs/review-agents.md, docs/workflow-lifecycle.md) stays aligned with the
# normative `/implement --quick` contract in skills/implement/SKILL.md
# Step 5 (closes #370).
#
# Without this harness, drift between the canonical contract and the public
# mirrors is silent: an editor rewriting Step 5 without propagating to the
# public docs (or vice versa) would ship contradictory documentation.
#
# Invoked via:  bash scripts/test-quick-mode-docs-sync.sh
#               bash scripts/test-quick-mode-docs-sync.sh --self-test
# Wired into:   make lint (via the test-quick-mode-docs-sync Makefile target).
#               Listed in agent-lint.toml exclude because agent-lint does not
#               follow Makefile-only references.
#
# The harness runs two check families against a fixed set of target files:
#
#   1. POSITIVE ANCHORS (required markers) — each target file MUST contain
#      all of the following strings:
#        - "7 rounds"                    (case-sensitive, grep -F)
#        - "Cursor → Codex → Claude"     (case-sensitive, grep -F, UTF-8 U+2192)
#        - "no voting panel"             (case-INSENSITIVE, grep -iF — tolerates
#                                         legitimate sentence-case rewrites)
#
#   2. NEGATIVE CHECKS (forbidden stale phrases) — the three public-doc
#      targets (README.md, docs/review-agents.md, docs/workflow-lifecycle.md)
#      MUST NOT contain any of the following literal stale strings:
#        - "1 Claude Code Reviewer subagent, 1 round"
#        - "no external reviewers"
#        - "no externals, no voting"
#      SKILL.md is EXEMPT from negative checks. Audit performed during #370
#      implementation: grep -F against each stale phrase returned no matches in
#      skills/implement/SKILL.md, so the exemption is currently safe. If a
#      future SKILL.md edit introduces historical/comment references to these
#      phrases, the exemption still holds (SKILL.md positive anchors alone
#      assert the current contract is stated somewhere in the file); if the
#      canonical contract itself changes, edit the marker variables below and
#      the sibling .md FIRST, then propagate to the public docs.
#
# --self-test MODE: writes two fixtures (one canonical-correct, one stale),
# runs the SAME check_file function against each, asserts the canonical
# fixture passes and the stale fixture fails. This proves the check mechanics
# on every invocation — a broken harness cannot silently go green in CI.
#
# Edit-in-sync rule: if skills/implement/SKILL.md Step 5 quick-mode contract
# changes, update (a) POSITIVE_MARKERS / STALE_PHRASES below FIRST, (b) the
# sibling scripts/test-quick-mode-docs-sync.md, (c) then the public docs. The
# positive-anchor check will enforce the new contract across all targets once
# updated. Keep this script and its sibling .md in sync in the same PR.

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"

# --- Canonical markers and stale phrases (single source of truth) -----------

# Positive anchors: each target file must contain all three markers.
# Format: "marker|casing" where casing is "sensitive" or "insensitive".
readonly POS_MARKER_1="7 rounds|sensitive"
readonly POS_MARKER_2="Cursor → Codex → Claude|sensitive"
readonly POS_MARKER_3="no voting panel|insensitive"

# Stale phrases (forbidden in public docs; SKILL.md exempt).
readonly STALE_1="1 Claude Code Reviewer subagent, 1 round"
readonly STALE_2="no external reviewers"
readonly STALE_3="no externals, no voting"

# Target files: relative paths from REPO_ROOT.
#   public docs  — subject to both positive and negative checks
#   SKILL.md     — subject to positive checks only (negative exempted)
readonly PUBLIC_DOCS=(
  "README.md"
  "docs/review-agents.md"
  "docs/workflow-lifecycle.md"
)
readonly SKILL_MD="skills/implement/SKILL.md"

# --- Check function (shared between default mode and --self-test) -----------

# check_file PATH LABEL APPLY_NEGATIVE
#   PATH             absolute path to file being checked
#   LABEL            human-readable label for error messages
#   APPLY_NEGATIVE   "yes" | "no" — whether stale-phrase bans apply
# Emits PASS/FAIL lines on stdout/stderr; sets global PASS_COUNT / FAIL_COUNT.
check_file() {
  local path="$1"
  local label="$2"
  local apply_negative="$3"

  if [[ ! -f "$path" ]]; then
    echo "FAIL: $label — file not found: $path" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  local local_fail=0

  # Positive anchors: iterate the three markers.
  local marker spec casing
  for spec in "$POS_MARKER_1" "$POS_MARKER_2" "$POS_MARKER_3"; do
    marker="${spec%|*}"
    casing="${spec##*|}"
    if [[ "$casing" == "insensitive" ]]; then
      if ! grep -iFq -- "$marker" "$path"; then
        echo "FAIL: $label — missing required marker (case-insensitive): '$marker'" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        local_fail=1
      fi
    else
      if ! grep -Fq -- "$marker" "$path"; then
        echo "FAIL: $label — missing required marker: '$marker'" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        local_fail=1
      fi
    fi
  done

  # Negative checks: forbidden stale phrases (public docs only).
  if [[ "$apply_negative" == "yes" ]]; then
    local stale
    for stale in "$STALE_1" "$STALE_2" "$STALE_3"; do
      if grep -Fq -- "$stale" "$path"; then
        echo "FAIL: $label — forbidden stale phrase present: '$stale'" >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
        local_fail=1
      fi
    done
  fi

  if [[ $local_fail -eq 0 ]]; then
    echo "PASS: $label"
    PASS_COUNT=$((PASS_COUNT + 1))
    return 0
  fi
  return 1
}

# --- Main: default mode -----------------------------------------------------

PASS_COUNT=0
FAIL_COUNT=0

run_default() {
  local rel abs
  for rel in "${PUBLIC_DOCS[@]}"; do
    abs="$REPO_ROOT/$rel"
    check_file "$abs" "$rel (public doc)" "yes" || true
  done

  abs="$REPO_ROOT/$SKILL_MD"
  check_file "$abs" "$SKILL_MD (canonical source)" "no" || true

  echo "----"
  echo "PASS_COUNT=$PASS_COUNT  FAIL_COUNT=$FAIL_COUNT"
  if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
  fi
}

# --- --self-test mode -------------------------------------------------------

FIXTURE_DIR=""
cleanup_fixture() {
  if [[ -n "$FIXTURE_DIR" && -d "$FIXTURE_DIR" ]]; then
    rm -rf "$FIXTURE_DIR"
  fi
}

run_self_test() {
  FIXTURE_DIR=$(mktemp -d)
  trap cleanup_fixture EXIT

  local good="$FIXTURE_DIR/good.md"
  local bad="$FIXTURE_DIR/bad.md"

  # Canonical-correct fixture: contains all 3 positive markers, no stale phrases.
  cat > "$good" <<'EOF'
This is a fixture describing quick-mode behavior.
The review loop runs up to 7 rounds.
Reviewer selection per round follows Cursor → Codex → Claude fallback.
The loop has no voting panel — main agent accepts or rejects each finding.
EOF

  # Stale-phrase fixture: contains ALL positive markers PLUS exactly one stale
  # phrase, so the ONLY reason check_file can fail on this fixture is the
  # negative-check path. If the negative-check block in check_file were ever
  # removed or bypassed, this fixture would produce zero failures and the
  # self-test below would fail — exactly the regression the self-test is
  # designed to catch.
  cat > "$bad" <<'EOF'
Stale-phrase fixture: contains every positive marker so only the stale phrase can drive failure.
The review loop runs up to 7 rounds.
Reviewer selection per round follows Cursor → Codex → Claude fallback.
The loop has no voting panel — main agent accepts or rejects each finding.
Stale phrase intentionally embedded: simplified code review (1 Claude Code Reviewer subagent, 1 round).
EOF

  # Reset counts; check the good fixture. Expect all checks pass.
  PASS_COUNT=0
  FAIL_COUNT=0
  echo "--- self-test: check canonical-correct fixture (expect 0 failures) ---"
  check_file "$good" "self-test/good.md" "yes" || true
  local good_fail=$FAIL_COUNT

  # Reset counts; check the bad fixture. Expect EXACTLY 1 FAIL — the stale
  # phrase. Any other count would indicate check_file drift (positive anchors
  # mis-matching the bad fixture, or negative-check not firing).
  PASS_COUNT=0
  FAIL_COUNT=0
  echo "--- self-test: check stale-phrase fixture (expect exactly 1 failure from negative check) ---"
  check_file "$bad" "self-test/bad.md" "yes" || true
  local bad_fail=$FAIL_COUNT

  echo "----"
  if [[ $good_fail -ne 0 ]]; then
    echo "SELF-TEST FAIL: canonical-correct fixture produced $good_fail failures (expected 0)" >&2
    exit 1
  fi
  if [[ $bad_fail -ne 1 ]]; then
    echo "SELF-TEST FAIL: stale-phrase fixture produced $bad_fail failures (expected exactly 1 from negative check)" >&2
    echo "  If 0: negative-check path is not firing (stale-phrase detection broken)." >&2
    echo "  If >1: positive anchors are mis-matching the bad fixture, or additional checks added without updating this assertion." >&2
    exit 1
  fi

  echo "SELF-TEST PASS: good fixture passed ($good_fail failures); bad fixture failed exactly once ($bad_fail failure) from negative check as expected"
}

main() {
  case "${1:-}" in
    --self-test)
      run_self_test
      ;;
    ""|--help|-h)
      if [[ "${1:-}" == "--help" || "${1:-}" == "-h" ]]; then
        cat <<EOF
Usage: $0 [--self-test]

Default mode: validate that public quick-mode docs stay in sync with
skills/implement/SKILL.md Step 5 (positive anchors + stale-phrase negatives).

--self-test: run the check against embedded good/bad fixtures to prove the
check mechanics. Used in CI alongside the default check.
EOF
        exit 0
      fi
      run_default
      ;;
    *)
      echo "Unknown argument: $1" >&2
      echo "Usage: $0 [--self-test]" >&2
      exit 2
      ;;
  esac
}

main "$@"
