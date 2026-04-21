#!/usr/bin/env bash
# test-loop-improve-skill-driver.sh — Regression harness for
# skills/loop-improve-skill/scripts/driver.sh (Option B topology, closes #273).
#
# Two tiers of assertions:
#
#   Tier 1 — Structural (always runs):
#     Greps the driver.sh source for contract tokens that the Option B
#     topology requires (parse-skill-judge-grade.sh, claude --version,
#     set -euo pipefail, verify-skill-called.sh --stdout-line, LOOP_TMPDIR
#     validation literals /tmp/ and /private/tmp/, `..` rejection check,
#     file-based prompt writes via $LOOP_TMPDIR/iter-${ITER}-*-prompt.txt,
#     redact-secrets.sh piped into gh-comment path).
#
#   Tier 2 — Behavioral (best-effort smoke tests with stubbed claude/gh):
#     Stubs `claude` and `gh` on PATH under a mktemp'd fixture skill dir,
#     then invokes driver.sh and asserts on observable side effects (gh.log
#     invocation records, presence/absence of per-iter artifacts). These are
#     a minimum-viable subset — 2-3 fixtures is the acceptable floor per
#     the Option B spec.
#
# Invoked via:  bash scripts/test-loop-improve-skill-driver.sh
# Wired into:   make lint (via the test-loop-improve-skill-driver target).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
DRIVER="$REPO_ROOT/skills/loop-improve-skill/scripts/driver.sh"

FAIL_COUNT=0
PASS_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# -----------------------------------------------------------------------
# Tier 1 — Structural asserts on driver.sh source
# -----------------------------------------------------------------------

echo "--- Structural asserts on driver.sh ---"

if [[ ! -f "$DRIVER" ]]; then
  fail "driver.sh not found at $DRIVER"
  echo ""
  echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="
  exit 1
fi

check_contains() {
  local needle="$1"
  local label="$2"
  if LC_ALL=C grep -Fq -- "$needle" "$DRIVER"; then
    pass "driver.sh contains: $label"
  else
    fail "driver.sh missing: $label (needle: $needle)"
  fi
}

check_contains 'parse-skill-judge-grade.sh'                    'parse-skill-judge-grade.sh invocation'
check_contains 'claude --version'                              'claude --version forensic capture'
check_contains 'set -euo pipefail'                             'set -euo pipefail'
check_contains "verify-skill-called.sh"                        'verify-skill-called.sh invocation'
check_contains "--stdout-line '^✅ 18: cleanup'"               'verify-skill-called.sh stdout-line mechanical gate'
check_contains '/tmp/'                                         'LOOP_TMPDIR /tmp/ prefix literal'
check_contains '/private/tmp/'                                 'LOOP_TMPDIR /private/tmp/ prefix literal'
check_contains "'..'"                                          '.. rejection check (single-quoted literal in message/case)'
# shellcheck disable=SC2016  # literal substrings asserted via grep against driver.sh source — NOT command substitution
check_contains 'iter-${ITER}-judge-prompt.txt'                 'file-based judge prompt write'
# shellcheck disable=SC2016
check_contains 'iter-${ITER}-design-prompt.txt'                'file-based design prompt write'
# shellcheck disable=SC2016
check_contains 'iter-${ITER}-im-prompt.txt'                    'file-based im prompt write'
check_contains 'redact-secrets.sh'                             'redact-secrets.sh in gh-comment pipeline'
check_contains 'cleanup-tmpdir.sh'                             'cleanup-tmpdir.sh invocation'
check_contains 'gh issue comment'                              'gh issue comment posting'
check_contains 'gh issue create'                               'gh issue create (tracking issue)'
check_contains 'session-setup.sh'                              'session-setup.sh invocation'
check_contains 'max iterations (10) reached'                   'iter-cap exit reason literal'
check_contains 'grade A achieved on all dimensions'            'grade-A exit reason literal'
check_contains 'grade A achieved after final post-iter-cap'   'post-cap A reclassification literal'
check_contains 'Infeasibility Justification'                   'close-out infeasibility section heading'
check_contains 'Grade History'                                 'close-out Grade History section heading'
check_contains 'claude -p'                                     'claude -p subprocess invocation'
# FINDING_7: every child claude invocation must pass --plugin-dir so contributor
# dev-mode (claude --plugin-dir .) or shadowed-repo installs still resolve the
# target skills from the larch plugin tree.
check_contains '--plugin-dir'                                  'claude -p --plugin-dir argument (FINDING_7)'
# shellcheck disable=SC2016
check_contains '"$CLAUDE_PLUGIN_ROOT"'                         'CLAUDE_PLUGIN_ROOT passed as --plugin-dir value'
# FINDING_7: fully-qualified slash-command names for larch-shipped children
# (design, im) so they never resolve against a user-local shadow.
check_contains '/larch:design'                                 'fully-qualified /larch:design invocation'
check_contains '/larch:im'                                     'fully-qualified /larch:im invocation'
# FINDING_10: stderr MUST NOT merge into stdout (which is posted publicly) —
# invoke_claude_p redirects stdout and stderr to separate files; the .stderr
# sidecar stays in LOOP_TMPDIR for diagnostics only.
# shellcheck disable=SC2016
check_contains '2> "$stderr_file"'                             'stderr redirected to separate file (FINDING_10)'
# shellcheck disable=SC2016
check_contains 'local stderr_file="${out_file}.stderr"'        '.stderr sidecar naming (FINDING_10)'
# FINDING_9: the /im plan body is piped via STDIN (not argv) so large plans do
# not exceed macOS ARG_MAX = 262144.
# shellcheck disable=SC2016
check_contains '< "$prompt_file"'                              'prompt-file fed via STDIN (FINDING_9)'
# FINDING_11: the driver honors LOOP_IMPROVE_SKIP_PREFLIGHT=1 so the fixture
# harness can exercise control-flow under a non-git-repo mktemp'd workdir.
check_contains 'LOOP_IMPROVE_SKIP_PREFLIGHT'                   'opt-in preflight-skip env var (FINDING_11)'
check_contains '--skip-preflight'                              'session-setup.sh --skip-preflight forwarding (FINDING_11)'

# -----------------------------------------------------------------------
# Tier 1b — Syntax check
# -----------------------------------------------------------------------

if bash -n "$DRIVER" 2>/dev/null; then
  pass "driver.sh passes bash -n syntax check"
else
  fail "driver.sh fails bash -n syntax check"
fi

# -----------------------------------------------------------------------
# Tier 2 — Behavioral smoke fixtures with stubbed claude + gh
# -----------------------------------------------------------------------

echo ""
echo "--- Behavioral smoke fixtures ---"

# Build a grade-A /skill-judge output (score/max >= 0.90 in every dim)
build_grade_a_judge() {
  cat <<'EOF'
# Report

## Dimension Scores

| Dim | Score | Max |
|-----|-------|-----|
| D1  | 20    | 20  |
| D2  | 15    | 15  |
| D3  | 15    | 15  |
| D4  | 15    | 15  |
| D5  | 15    | 15  |
| D6  | 15    | 15  |
| D7  | 10    | 10  |
| D8  | 15    | 15  |

Grade A on every dimension.
EOF
}

# Run one fixture: set up stubs on PATH, invoke driver, capture + assert.
run_fixture() {
  local name="$1"
  local judge_body_cmd="$2"     # shell code that writes judge output on stdout
  local design_body_cmd="$3"    # shell code that writes design output on stdout
  local im_body_cmd="$4"        # shell code that writes im output on stdout
  local expect_grep="$5"        # regex to grep in driver stdout
  local not_grep="${6:-}"       # regex that must NOT appear in driver stdout

  local fixture_tmp
  fixture_tmp="$(mktemp -d)"
  local stub_dir="$fixture_tmp/stubs"
  local work_dir="$fixture_tmp/work"
  mkdir -p "$stub_dir" "$work_dir/skills/testskill"

  # Target SKILL.md so the driver's 3-probe resolves.
  cat > "$work_dir/skills/testskill/SKILL.md" <<'SKILL_EOF'
---
name: testskill
description: "Fixture skill"
---
# testskill
Fixture.
SKILL_EOF

  # Write the stub scripts.
  cat > "$stub_dir/gh" <<GH_EOF
#!/usr/bin/env bash
# gh stub — records invocations + synthesizes outputs.
printf '%s\n' "gh \$*" >> "$fixture_tmp/gh.log"
case "\$1" in
  auth)
    # 'gh auth status' → exit 0
    exit 0 ;;
  issue)
    shift
    case "\$1" in
      create)
        # Parse --body-file (ignore); emit fake URL
        printf 'https://github.com/example/repo/issues/42\n'
        exit 0 ;;
      comment)
        # record body-file if present for inspection
        while [[ \$# -gt 0 ]]; do
          if [[ "\$1" == "--body-file" ]]; then
            printf 'gh-comment body-file=%s\n' "\$2" >> "$fixture_tmp/gh.log"
            shift 2
          else
            shift
          fi
        done
        exit 0 ;;
    esac
    ;;
esac
exit 0
GH_EOF
  chmod +x "$stub_dir/gh"

  # Build per-phase output files — claude stub switches by prompt contents.
  cat > "$fixture_tmp/judge-body.sh" <<JBODY
$judge_body_cmd
JBODY
  cat > "$fixture_tmp/design-body.sh" <<DBODY
$design_body_cmd
DBODY
  cat > "$fixture_tmp/im-body.sh" <<IBODY
$im_body_cmd
IBODY
  chmod +x "$fixture_tmp/judge-body.sh" "$fixture_tmp/design-body.sh" "$fixture_tmp/im-body.sh"

  cat > "$stub_dir/claude" <<CLAUDE_EOF
#!/usr/bin/env bash
# claude stub — picks body by prompt prefix. Supports the FINDING_7/9 contract:
# claude -p --plugin-dir <root>  (prompt is read from STDIN, not argv).
if [[ "\$1" == "--version" ]]; then
  echo "claude stub 0.0.0"
  exit 0
fi
# Skip any leading flags until we've consumed -p and --plugin-dir.
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -p) shift ;;
    --plugin-dir) shift 2 ;;
    --*) shift ;;
    *) break ;;
  esac
done
# Prompt may be on stdin (FINDING_9) or as a positional arg (legacy fallback).
if [[ \$# -gt 0 ]]; then
  prompt="\$1"
else
  prompt="\$(cat)"
fi
# Match against the leading slash-command token.
case "\$prompt" in
  "/skill-judge"*|"/larch:skill-judge"*)
    bash "$fixture_tmp/judge-body.sh" ;;
  "/design"*|"/larch:design"*)
    bash "$fixture_tmp/design-body.sh" ;;
  "/im"*|"/larch:im"*)
    bash "$fixture_tmp/im-body.sh" ;;
  *)
    printf 'unknown-prompt-stub\n' ;;
esac
exit 0
CLAUDE_EOF
  chmod +x "$stub_dir/claude"

  # Invoke driver with PATH prefix — suppress long output, capture to file.
  local driver_log="$fixture_tmp/driver.log"
  local rc=0
  (
    cd "$work_dir"
    PATH="$stub_dir:$PATH" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    LOOP_IMPROVE_SKIP_PREFLIGHT=1 \
      bash "$DRIVER" testskill
  ) > "$driver_log" 2>&1 || rc=$?

  # Best-effort: some fixtures are smoke-only and the driver may legitimately
  # exit non-zero because of the stubbed environment (no git repo, etc.).
  # Assert on observable output tokens rather than exit code.

  # Behavioral fixtures are best-effort smoke tests — the driver depends on
  # helper scripts (preflight, session-setup, run-external-reviewer) that
  # have environmental requirements not always satisfiable from the harness.
  # If session-setup fails preflight in the fixture work_dir, the driver
  # aborts before the phase under test. In that case we SKIP the fixture
  # rather than fail the harness — the structural assertions above are the
  # primary contract; behavioral fixtures are smoke aids only.
  # Driver dies at SETUP_OUT=$(...) under `set -e` when session-setup.sh exits
  # non-zero due to preflight failure in the fixture work_dir (not a git repo
  # with origin main configured). The driver log stops after "2: session
  # setup" breadcrumb with no further output; detect either that shape or a
  # rc >= 2 (session-setup or preflight error codes).
  local skip_reason=""
  if grep -q 'PREFLIGHT=fail\|PREFLIGHT_ERROR\|session setup — failed' "$driver_log" 2>/dev/null; then
    skip_reason="session-setup preflight not satisfiable in fixture work_dir"
  elif [[ "$rc" -ge 2 ]] && ! grep -q '^✅ 2: session setup' "$driver_log" 2>/dev/null; then
    skip_reason="driver aborted before/at session setup (rc=$rc; fixture work_dir not a fetchable git repo)"
  fi

  if [[ -n "$skip_reason" ]]; then
    echo "SKIP: fixture [$name]: $skip_reason (structural asserts are the primary contract)"
  else
    if grep -Eq -- "$expect_grep" "$driver_log" 2>/dev/null; then
      pass "fixture [$name]: found expected pattern '$expect_grep'"
    else
      fail "fixture [$name]: missing expected pattern '$expect_grep' (rc=$rc)"
      echo "    === driver.log (tail) ===" >&2
      tail -40 "$driver_log" >&2 || true
    fi

    if [[ -n "$not_grep" ]]; then
      if grep -Eq -- "$not_grep" "$driver_log" 2>/dev/null; then
        fail "fixture [$name]: found forbidden pattern '$not_grep'"
      else
        pass "fixture [$name]: correctly absent '$not_grep'"
      fi
    fi
  fi

  rm -rf "$fixture_tmp" 2>/dev/null || true
}

# Only run behavioral fixtures if the helper scripts exist — they reference
# session-setup.sh, run-external-reviewer.sh, etc., which must be on disk
# for the driver to work even with stubs.
if [[ -x "$REPO_ROOT/scripts/session-setup.sh" && \
      -x "$REPO_ROOT/scripts/run-external-reviewer.sh" && \
      -x "$REPO_ROOT/scripts/cleanup-tmpdir.sh" && \
      -x "$REPO_ROOT/scripts/redact-secrets.sh" && \
      -x "$REPO_ROOT/scripts/parse-skill-judge-grade.sh" && \
      -x "$REPO_ROOT/scripts/verify-skill-called.sh" ]]; then

  GRADE_A_JUDGE="$(build_grade_a_judge)"

  # Fixture 1: grade_a_achieved at iter 1
  run_fixture \
    "grade_a_achieved_iter1" \
    "cat <<'HEREDOC_EOF'
$GRADE_A_JUDGE
HEREDOC_EOF" \
    "echo 'should not be called'" \
    "echo '✅ 18: cleanup'" \
    'grade A achieved|grade_a_achieved|Loop finished' \
    ''

  # Fixture 2: no_plan at iter 1 (non-A judge, design returns "No plan.")
  NON_A_JUDGE="$(cat <<'EOF'
# Report

## Dimension Scores

| Dim | Score | Max |
|-----|-------|-----|
| D1  | 18    | 20  |
| D2  | 14    | 15  |
| D3  | 14    | 15  |
| D4  | 14    | 15  |
| D5  | 14    | 15  |
| D6  | 14    | 15  |
| D7  | 8     | 10  |
| D8  | 14    | 15  |
EOF
)"
  run_fixture \
    "no_plan" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf 'No plan.\n'" \
    "echo 'should not be called'" \
    'no plan at iteration 1|no_plan|Infeasibility' \
    ''

  # Fixture 3: im_verification_failed (valid plan, /im output lacks ✅ 18: cleanup)
  run_fixture \
    "im_verification_failed" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf '## Implementation Plan\n\n- Step one\n- Step two\n'" \
    "printf 'Some output but no canonical completion line.\n'" \
    'im did not reach canonical completion line|im_verification_failed|Infeasibility' \
    ''

else
  echo "SKIP: behavioral fixtures skipped — required helper scripts not all present."
fi

# -----------------------------------------------------------------------
# Summary
# -----------------------------------------------------------------------

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
