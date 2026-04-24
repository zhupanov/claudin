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
# The harness runs three check families:
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
#   3. REQUIRED CROSS-REFERENCES (two-assertion check, target-specific) —
#      guards prose path citations in public docs. Each entry is a (doc, xref)
#      pair where BOTH of the following must hold:
#        (a) the literal xref path appears verbatim in the doc (grep -Fq), AND
#        (b) the xref path resolves to an actual file on disk (relative to
#            REPO_ROOT).
#      Currently wired for docs/review-agents.md -> skills/shared/voting-protocol.md
#      (Note A in the voting-panel collapse thresholds paragraph). A rename of
#      the target file fails (b); a Note A rewording that drops the literal
#      fails (a). Closes #377.
#
# --self-test MODE: writes core fixtures (canonical-correct + stale) for
# check_file PLUS three xref fixtures (xref-good, xref-bad-existence,
# xref-bad-grep) for check_xref, then runs the SAME functions used in
# default mode against each. Asserts the canonical and xref-good fixtures
# pass, the stale / xref-bad-existence / xref-bad-grep fixtures each fail
# exactly once (respectively driven by the stale-phrase, existence, and grep
# assertions). Proves both check mechanics on every invocation — a broken
# harness cannot silently go green in CI.
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

# Required cross-references (file-specific, two-assertion check).
#   Note A in docs/review-agents.md cites skills/shared/voting-protocol.md as
#   the authority for voting-panel collapse thresholds. The check asserts BOTH
#   that the literal path is present in the doc AND that the target file exists
#   on disk — a rename fails the existence assertion; a Note A rewording that
#   drops the literal fails the grep assertion.
readonly XREF_DOC="docs/review-agents.md"
readonly XREF_PATH="skills/shared/voting-protocol.md"

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

# check_xref DOC_PATH LABEL XREF_REL REPO_ROOT_FOR_XREF
#   DOC_PATH            absolute path to the doc that should cite XREF_REL
#   LABEL               human-readable label for error messages
#   XREF_REL            repo-relative path expected to appear verbatim in DOC_PATH
#                       AND to resolve to an extant file relative to REPO_ROOT_FOR_XREF
#   REPO_ROOT_FOR_XREF  root directory to which XREF_REL is resolved on disk
# Two independent assertions per call; failures increment FAIL_COUNT once each.
# Kept separate from check_file so self-test's single-file fixture invariants
# remain isolated.
check_xref() {
  local doc_path="$1"
  local label="$2"
  local xref_rel="$3"
  local xref_root="$4"

  if [[ ! -f "$doc_path" ]]; then
    echo "FAIL: $label — doc file not found: $doc_path" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi

  local local_fail=0

  if ! grep -Fq -- "$xref_rel" "$doc_path"; then
    echo "FAIL: $label — missing required cross-reference literal: '$xref_rel'" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    local_fail=1
  fi

  # Use -f (regular file) rather than -e (any existing path) so a directory
  # at the cited path does NOT silently satisfy the check — the contract is a
  # file, not any path. Any non-file (dir, symlink-to-missing, broken link,
  # missing) all fail through this single branch.
  if [[ ! -f "$xref_root/$xref_rel" ]]; then
    echo "FAIL: $label — cross-reference target does not resolve to a regular file on disk: '$xref_rel'" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    local_fail=1
  fi

  if [[ $local_fail -eq 0 ]]; then
    echo "PASS: $label — cross-reference '$xref_rel' present and resolves"
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

  # Required cross-reference: Note A in docs/review-agents.md -> voting-protocol.md
  check_xref "$REPO_ROOT/$XREF_DOC" "$XREF_DOC (Note A xref)" "$XREF_PATH" "$REPO_ROOT" || true

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

  # --- xref check mechanics ---
  # Good xref fixture: doc contains the literal path AND target file exists.
  # Expect 0 failures from check_xref.
  local xref_good_root="$FIXTURE_DIR/xref-good"
  local xref_good_doc="$xref_good_root/doc.md"
  local xref_good_target_rel="target/voting-protocol.md"
  mkdir -p "$xref_good_root/target"
  printf 'Cites %s in prose.\n' "$xref_good_target_rel" > "$xref_good_doc"
  echo "placeholder" > "$xref_good_root/$xref_good_target_rel"

  # Bad-existence xref fixture: doc contains the literal path BUT target file
  # is missing on disk. Expect exactly 1 failure from check_xref, driven by
  # the existence assertion only. Regression-tests the -f branch — if the
  # existence block were removed, this fixture would produce 0 failures.
  local xref_bad_exist_root="$FIXTURE_DIR/xref-bad-existence"
  local xref_bad_exist_doc="$xref_bad_exist_root/doc.md"
  local xref_bad_exist_target_rel="target/voting-protocol.md"
  mkdir -p "$xref_bad_exist_root"
  printf 'Cites %s in prose.\n' "$xref_bad_exist_target_rel" > "$xref_bad_exist_doc"
  # Deliberately do NOT create xref_bad_exist_root/$xref_bad_exist_target_rel.

  # Bad-grep xref fixture: target file exists on disk BUT doc omits the
  # literal path. Expect exactly 1 failure from check_xref, driven by the
  # grep assertion only. Regression-tests the grep -Fq branch — if the grep
  # block were removed, this fixture would produce 0 failures (symmetric
  # guard to the bad-existence fixture above).
  local xref_bad_grep_root="$FIXTURE_DIR/xref-bad-grep"
  local xref_bad_grep_doc="$xref_bad_grep_root/doc.md"
  local xref_bad_grep_target_rel="target/voting-protocol.md"
  mkdir -p "$xref_bad_grep_root/target"
  # Deliberately write a doc body that does NOT contain the literal path.
  printf 'Doc body without the expected xref literal.\n' > "$xref_bad_grep_doc"
  echo "placeholder" > "$xref_bad_grep_root/$xref_bad_grep_target_rel"

  PASS_COUNT=0
  FAIL_COUNT=0
  echo "--- self-test: check xref-good fixture (expect 0 failures) ---"
  check_xref "$xref_good_doc" "self-test/xref-good" "$xref_good_target_rel" "$xref_good_root" || true
  local xref_good_fail=$FAIL_COUNT

  PASS_COUNT=0
  FAIL_COUNT=0
  echo "--- self-test: check xref-bad-existence fixture (expect exactly 1 failure from existence assertion) ---"
  check_xref "$xref_bad_exist_doc" "self-test/xref-bad-existence" "$xref_bad_exist_target_rel" "$xref_bad_exist_root" || true
  local xref_bad_exist_fail=$FAIL_COUNT

  PASS_COUNT=0
  FAIL_COUNT=0
  echo "--- self-test: check xref-bad-grep fixture (expect exactly 1 failure from grep assertion) ---"
  check_xref "$xref_bad_grep_doc" "self-test/xref-bad-grep" "$xref_bad_grep_target_rel" "$xref_bad_grep_root" || true
  local xref_bad_grep_fail=$FAIL_COUNT

  if [[ $xref_good_fail -ne 0 ]]; then
    echo "SELF-TEST FAIL: xref-good fixture produced $xref_good_fail failures (expected 0)" >&2
    exit 1
  fi
  if [[ $xref_bad_exist_fail -ne 1 ]]; then
    echo "SELF-TEST FAIL: xref-bad-existence fixture produced $xref_bad_exist_fail failures (expected exactly 1 from existence assertion)" >&2
    echo "  If 0: existence-assertion path is not firing (missing-target detection broken)." >&2
    echo "  If >1: grep assertion is also failing — bad-existence fixture's doc content may no longer contain the literal." >&2
    exit 1
  fi
  if [[ $xref_bad_grep_fail -ne 1 ]]; then
    echo "SELF-TEST FAIL: xref-bad-grep fixture produced $xref_bad_grep_fail failures (expected exactly 1 from grep assertion)" >&2
    echo "  If 0: grep-assertion path is not firing (missing-literal detection broken)." >&2
    echo "  If >1: existence assertion is also failing — bad-grep fixture's target file may be missing." >&2
    exit 1
  fi

  echo "SELF-TEST PASS: good fixture passed ($good_fail failures); bad fixture failed exactly once ($bad_fail failure) from negative check; xref-good passed ($xref_good_fail); xref-bad-existence failed exactly once ($xref_bad_exist_fail) from existence assertion; xref-bad-grep failed exactly once ($xref_bad_grep_fail) from grep assertion as expected"
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
skills/implement/SKILL.md Step 5 (positive anchors + stale-phrase negatives)
plus required cross-references (doc literal present AND target file exists).

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
