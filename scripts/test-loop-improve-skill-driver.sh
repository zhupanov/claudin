#!/usr/bin/env bash
# test-loop-improve-skill-driver.sh — Regression harness for
# skills/loop-improve-skill/scripts/driver.sh (Option B topology, closes #273;
# post-refactor: iteration body factored out into
# skills/improve-skill/scripts/iteration.sh and invoked from the driver's
# loop body via direct bash call).
#
# Two tiers of assertions:
#
#   Tier 1 — Structural (always runs):
#     Greps the driver.sh source for contract tokens the loop-driver layer
#     retains: session-setup.sh, LOOP_TMPDIR /tmp/ + /private/tmp/ prefix
#     literals, `..` rejection, gh issue create/comment, redact-secrets.sh
#     + cleanup-tmpdir.sh, close-out exit-reason literals, delegation to the
#     improve-skill iteration kernel via ${LARCH_ITERATION_SCRIPT_OVERRIDE:-
#     ${CLAUDE_PLUGIN_ROOT}/skills/improve-skill/scripts/iteration.sh}, and
#     the retained slim invoke_claude_p (used only for the post-iter-cap
#     re-judge) including its FINDING_7/9/10 security contracts (--plugin-dir,
#     STDIN prompt, stderr sidecar).
#
#     Iteration-body tokens (verify-skill-called.sh, /larch:design, /larch:im,
#     per-ITER judge/design/im prompt filenames) live in iteration.sh and are
#     pinned by scripts/test-improve-skill-iteration.sh.
#
#   Tier 2 — Behavioral (best-effort smoke tests with stubbed claude/gh and
#     a stub iteration shim redirected via LARCH_ITERATION_SCRIPT_OVERRIDE):
#     Stubs `claude` and `gh` on PATH under a mktemp'd fixture skill dir, and
#     plants a stub iteration.sh shim that emits deterministic KV footers
#     mapping to the test cases. The harness exports
#     LARCH_ITERATION_SCRIPT_OVERRIDE=<stub-path> so the driver invokes the
#     shim instead of the real iteration. Asserts on observable driver output.
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

# ---------- Core driver contract (loop-layer concerns) ----------
check_contains 'parse-skill-judge-grade.sh'                    'parse-skill-judge-grade.sh invocation (final re-judge)'
check_contains 'claude --version'                              'claude --version forensic capture'
check_contains 'set -euo pipefail'                             'set -euo pipefail'
check_contains '/tmp/'                                         'LOOP_TMPDIR /tmp/ prefix literal'
check_contains '/private/tmp/'                                 'LOOP_TMPDIR /private/tmp/ prefix literal'
check_contains "'..'"                                          '.. rejection check (single-quoted literal in message/case)'
check_contains 'redact-secrets.sh'                             'redact-secrets.sh in close-out gh-comment pipeline'
check_contains 'cleanup-tmpdir.sh'                             'cleanup-tmpdir.sh invocation'
check_contains 'gh issue comment'                              'gh issue comment posting'
check_contains 'gh issue create'                               'gh issue create (tracking issue)'
check_contains 'session-setup.sh'                              'session-setup.sh invocation'
check_contains 'max iterations (10) reached'                   'iter-cap exit reason literal'
check_contains 'grade A achieved on all dimensions'            'grade-A exit reason literal'
check_contains 'grade A achieved after final post-iter-cap'   'post-cap A reclassification literal'
check_contains 'Infeasibility Justification'                   'close-out infeasibility section heading'
check_contains 'Grade History'                                 'close-out Grade History section heading'
# FINDING_11: the driver honors LOOP_IMPROVE_SKIP_PREFLIGHT=1 so the fixture
# harness can exercise control-flow under a non-git-repo mktemp'd workdir.
check_contains 'LOOP_IMPROVE_SKIP_PREFLIGHT'                   'opt-in preflight-skip env var (FINDING_11)'
check_contains '--skip-preflight'                              'session-setup.sh --skip-preflight forwarding (FINDING_11)'

# ---------- Issue #399 — tmpdir retention + stderr dump contracts ----------
check_contains 'LOOP_PRESERVE_TMPDIR'                          'retention flag (issue #399 remedy (a))'
check_contains 'Retained working directory'                    'close-out + stdout breadcrumb literal (issue #399)'
check_contains '── subprocess stderr (label='                  'subprocess-stderr banner literal (issue #399 remedy (b))'
check_contains '── subprocess stdout tail (label='             'subprocess-stdout-tail banner literal (issue #399 remedy (b))'
check_contains 'tail -n 50'                                    'stdout-tail 50-line cap (issue #399 remedy (b))'
check_contains 'dump_subprocess_diagnostics'                   'subprocess-diagnostics helper function (issue #399)'
check_contains 'dump_helper_stderr'                            'helper-stderr dump function (issue #399 remedy (c))'
check_contains 'preserve.sentinel'                             'cross-boundary preserve sentinel (issue #399)'
check_contains 'banner-redacted'                               'sed spoof-guard for ### iteration-result (issue #399)'
check_contains 'gh-create-issue.stderr'                        'gh issue create stderr sidecar (issue #399 remedy (c))'
check_contains 'gh-comment.stderr'                             'gh issue comment stderr sidecar (issue #399 remedy (c))'
check_contains 'redact.stderr'                                 'redact-secrets stderr sidecar (issue #399 remedy (c))'
# shellcheck disable=SC2016
check_contains 'LOOP_TMPDIR=%s'                                'always-emit LOOP_TMPDIR= stdout token (issue #399)'

# ---------- Iteration delegation (post-refactor) ----------
# Driver must invoke iteration.sh via an ITERATION_SCRIPT variable resolved
# from LARCH_ITERATION_SCRIPT_OVERRIDE (test-only) or the default kernel path.
check_contains 'LARCH_ITERATION_SCRIPT_OVERRIDE'               'iteration-script test-only override env var'
check_contains 'skills/improve-skill/scripts/iteration.sh'     'default iteration kernel path'
check_contains 'ITERATION_SCRIPT'                              'ITERATION_SCRIPT variable (delegation binding)'
# Driver must pass --issue / --work-dir / --iter-num / --breadcrumb-prefix
# to the kernel (contract surface between driver and iteration.sh).
check_contains '--work-dir'                                    'iteration.sh --work-dir flag passthrough'
check_contains '--iter-num'                                    'iteration.sh --iter-num flag passthrough'
check_contains '--breadcrumb-prefix'                           'iteration.sh --breadcrumb-prefix flag passthrough'
check_contains '--issue'                                       'iteration.sh --issue flag passthrough'
# Driver parses the kernel's KV footer from iteration.sh stdout.
check_contains '### iteration-result'                          'KV-footer delimiter literal (expected in iteration.sh stdout)'
check_contains 'ITER_STATUS'                                   'KV footer key: ITER_STATUS'
check_contains 'EXIT_REASON'                                   'KV footer key: EXIT_REASON'
check_contains 'PARSE_STATUS'                                  'KV footer key: PARSE_STATUS'
check_contains 'GRADE_A'                                       'KV footer key: GRADE_A'
check_contains 'NON_A_DIMS'                                    'KV footer key: NON_A_DIMS'

# ---------- Retained slim invoke_claude_p (post-iter-cap re-judge only) ----------
# The final re-judge is NOT delegated to iteration.sh; it uses a slim local
# helper in driver.sh. That helper MUST preserve the same security contracts.
check_contains 'claude -p'                                     'claude -p subprocess invocation (slim final re-judge)'
check_contains '--plugin-dir'                                  'claude -p --plugin-dir argument (FINDING_7)'
# shellcheck disable=SC2016
check_contains '"$CLAUDE_PLUGIN_ROOT"'                         'CLAUDE_PLUGIN_ROOT passed as --plugin-dir value'
# FINDING_10: stderr MUST NOT merge into stdout (which is posted publicly).
# shellcheck disable=SC2016
check_contains '2> "$stderr_file"'                             'stderr redirected to separate file (FINDING_10)'
# shellcheck disable=SC2016
check_contains 'local stderr_file="${out_file}.stderr"'        '.stderr sidecar naming (FINDING_10)'
# FINDING_9: prompt body fed via STDIN so large final-judge prompts do not
# exceed macOS ARG_MAX = 262144.
# shellcheck disable=SC2016
check_contains '< "$prompt_file"'                              'prompt-file fed via STDIN (FINDING_9)'

# -----------------------------------------------------------------------
# Tier 1b — Syntax check
# -----------------------------------------------------------------------

if bash -n "$DRIVER" 2>/dev/null; then
  pass "driver.sh passes bash -n syntax check"
else
  fail "driver.sh fails bash -n syntax check"
fi

# -----------------------------------------------------------------------
# Tier 2 — Behavioral smoke fixtures
# -----------------------------------------------------------------------

echo ""
echo "--- Behavioral smoke fixtures ---"

# Run one fixture: set up stubs + LARCH_ITERATION_SCRIPT_OVERRIDE, invoke
# driver, assert on observable output.
#
# Args:
#   $1 name             Fixture name for pass/fail labels.
#   $2 iter_body        Shell body written into the stub iteration shim.
#   $3 expect_grep      Regex that MUST appear in driver stdout.
#   $4 not_grep         Optional regex that must NOT appear in driver stdout.
#   $5 expect_retained  Optional — "true" asserts LOOP_TMPDIR persists after
#                       driver exit; "false" asserts LOOP_TMPDIR was cleaned.
#                       Driver always emits `LOOP_TMPDIR=<path>` to stdout at
#                       EXIT (issue #399) so the harness can extract it.
run_fixture() {
  local name="$1"
  local iter_body="$2"        # shell body written into the stub iteration shim
  local expect_grep="$3"      # regex to grep in driver stdout
  local not_grep="${4:-}"     # regex that must NOT appear in driver stdout
  local expect_retained="${5:-}"  # "true" / "false" / "" (skip) — issue #399

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

  # Stub gh (records invocations).
  cat > "$stub_dir/gh" <<GH_EOF
#!/usr/bin/env bash
printf '%s\n' "gh \$*" >> "$fixture_tmp/gh.log"
case "\$1" in
  auth) exit 0 ;;
  issue)
    shift
    case "\$1" in
      create)
        printf 'https://github.com/example/repo/issues/42\n'
        exit 0 ;;
      comment)
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

  # Stub claude (only used by Step 5a final re-judge in this fixture shape;
  # the iteration body is intercepted by the iteration shim below).
  cat > "$stub_dir/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then
  echo "claude stub 0.0.0"
  exit 0
fi
# Skip leading flags
while [[ $# -gt 0 ]]; do
  case "$1" in
    -p) shift ;;
    --plugin-dir) shift 2 ;;
    --*) shift ;;
    *) break ;;
  esac
done
if [[ $# -gt 0 ]]; then prompt="$1"; else prompt="$(cat)"; fi
# For the post-iter-cap re-judge in fixture 3 (iter-cap), synthesize a
# grade-A judge report so reclassification can be exercised.
case "$prompt" in
  "/skill-judge"*|"/larch:skill-judge"*)
    cat <<'GRADE_EOF'
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
GRADE_EOF
    ;;
  *)
    printf 'unknown-prompt-stub\n' ;;
esac
exit 0
CLAUDE_EOF
  chmod +x "$stub_dir/claude"

  # Stub iteration.sh shim (LARCH_ITERATION_SCRIPT_OVERRIDE target).
  cat > "$fixture_tmp/stub-iteration.sh" <<'SHIM_EOF'
#!/usr/bin/env bash
# Parse minimal args to find --iter-num, the skill name, and --work-dir
# (exported as WORK_DIR so fixture bodies can touch $WORK_DIR/preserve.sentinel
# for issue #399 cross-boundary signal testing).
ITER_NUM=1
WORK_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --iter-num) ITER_NUM="$2"; shift 2 ;;
    --work-dir) WORK_DIR="$2"; shift 2 ;;
    --issue|--breadcrumb-prefix) shift 2 ;;
    --no-slack) shift ;;
    --) shift; break ;;
    --*) shift ;;
    *) break ;;
  esac
done
SHIM_EOF
  # Append the fixture-specific iteration body (sets KV footer fields + emits).
  printf '%s\n' "$iter_body" >> "$fixture_tmp/stub-iteration.sh"
  chmod +x "$fixture_tmp/stub-iteration.sh"

  # Invoke driver with PATH prefix + iteration override.
  local driver_log="$fixture_tmp/driver.log"
  local rc=0
  (
    cd "$work_dir"
    PATH="$stub_dir:$PATH" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
    LOOP_IMPROVE_SKIP_PREFLIGHT=1 \
    LARCH_ITERATION_SCRIPT_OVERRIDE="$fixture_tmp/stub-iteration.sh" \
      bash "$DRIVER" testskill
  ) > "$driver_log" 2>&1 || rc=$?

  # Skip fixture if preflight failed in the fixture env (same policy as before).
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
      tail -60 "$driver_log" >&2 || true
    fi

    if [[ -n "$not_grep" ]]; then
      if grep -Eq -- "$not_grep" "$driver_log" 2>/dev/null; then
        fail "fixture [$name]: found forbidden pattern '$not_grep'"
      else
        pass "fixture [$name]: correctly absent '$not_grep'"
      fi
    fi

    # Issue #399 retention assertion. Driver emits `LOOP_TMPDIR=<path>` on
    # every exit path — extract it from the log and check persistence vs
    # cleanup. The extracted path lives under /tmp or /private/tmp (outside
    # $fixture_tmp), so the fixture's own `rm -rf $fixture_tmp` does not
    # affect it; we must clean it up manually on retention paths to avoid
    # /tmp leakage between test runs.
    if [[ -n "$expect_retained" ]]; then
      local loop_tmpdir
      loop_tmpdir="$(grep -E '^LOOP_TMPDIR=' "$driver_log" 2>/dev/null | tail -1 | cut -d= -f2-)"
      if [[ -z "$loop_tmpdir" ]]; then
        fail "fixture [$name]: could not extract LOOP_TMPDIR= from driver output"
      else
        case "$expect_retained" in
          true)
            if [[ -d "$loop_tmpdir" ]]; then
              pass "fixture [$name]: LOOP_TMPDIR retained on failure path ($loop_tmpdir)"
              rm -rf "$loop_tmpdir" 2>/dev/null || true
            else
              fail "fixture [$name]: expected LOOP_TMPDIR retained, but $loop_tmpdir was cleaned"
            fi
            ;;
          false)
            if [[ -d "$loop_tmpdir" ]]; then
              fail "fixture [$name]: expected LOOP_TMPDIR cleaned on success path, but $loop_tmpdir persisted"
              rm -rf "$loop_tmpdir" 2>/dev/null || true
            else
              pass "fixture [$name]: LOOP_TMPDIR cleaned on success path"
            fi
            ;;
        esac
      fi
    fi
  fi

  rm -rf "$fixture_tmp" 2>/dev/null || true
}

# Only run behavioral fixtures if the helper scripts exist.
if [[ -x "$REPO_ROOT/scripts/session-setup.sh" && \
      -x "$REPO_ROOT/scripts/cleanup-tmpdir.sh" && \
      -x "$REPO_ROOT/scripts/redact-secrets.sh" && \
      -x "$REPO_ROOT/scripts/parse-skill-judge-grade.sh" ]]; then

  # Fixture 1: iteration returns ITER_STATUS=grade_a on iteration 1.
  # Success path — LOOP_TMPDIR must be cleaned (issue #399).
  # shellcheck disable=SC2016
  run_fixture \
    "grade_a_at_iter1" \
    'printf "> **🔶 4.1.j: judge**\n"
printf "✅ 4.1.j: judge — grade A\n"
printf "\n### iteration-result\n"
printf "ITER_STATUS=grade_a\n"
printf "EXIT_REASON=grade A achieved on all dimensions at iteration 1\n"
printf "PARSE_STATUS=ok\n"
printf "GRADE_A=true\n"
printf "NON_A_DIMS=\n"
printf "TOTAL_NUM=120\n"
printf "TOTAL_DEN=120\n"
printf "ITERATION_TMPDIR=\n"
printf "ISSUE_NUM=42\n"
exit 0' \
    'grade A achieved|Loop finished' \
    '' \
    'false'

  # Fixture 2: iteration returns ITER_STATUS=no_plan on iteration 1.
  # Retention path — LOOP_TMPDIR must persist + close-out body has Diagnostics
  # block + driver stdout has the "Retained working directory" breadcrumb.
  # shellcheck disable=SC2016
  run_fixture \
    "preserve_tmpdir_on_no_plan" \
    'printf "> **🔶 4.1.d: design**\n"
printf "\n### iteration-result\n"
printf "ITER_STATUS=no_plan\n"
printf "EXIT_REASON=no plan at iteration 1\n"
printf "PARSE_STATUS=ok\n"
printf "GRADE_A=false\n"
printf "NON_A_DIMS=D2,D7\n"
printf "TOTAL_NUM=100\n"
printf "TOTAL_DEN=120\n"
printf "ITERATION_TMPDIR=\n"
printf "ISSUE_NUM=42\n"
exit 0' \
    'Retained working directory' \
    '' \
    'true'

  # Fixture 3: iteration returns ITER_STATUS=im_verification_failed.
  # Retention path (same shape as no_plan but different terminal status).
  # shellcheck disable=SC2016
  run_fixture \
    "im_verification_failed_at_iter1" \
    'printf "\n### iteration-result\n"
printf "ITER_STATUS=im_verification_failed\n"
printf "EXIT_REASON=/im did not reach canonical completion line at iteration 1\n"
printf "PARSE_STATUS=ok\n"
printf "GRADE_A=false\n"
printf "NON_A_DIMS=D2,D7\n"
printf "TOTAL_NUM=100\n"
printf "TOTAL_DEN=120\n"
printf "ITERATION_TMPDIR=\n"
printf "ISSUE_NUM=42\n"
exit 0' \
    'im did not reach canonical completion line|Infeasibility' \
    '' \
    'true'

  # Fixture 4: iteration returns ITER_STATUS=grade_a (a nominally clean-success
  # status), BUT also touches the cross-boundary preserve sentinel at
  # $WORK_DIR/preserve.sentinel — simulating a helper-script-failure path in
  # the kernel signaling retention to the driver via sentinel (issue #399
  # FINDING_4). The driver's cleanup_on_exit must honor the sentinel and
  # retain LOOP_TMPDIR despite the clean-success status.
  # shellcheck disable=SC2016
  run_fixture \
    "preserve_tmpdir_on_sentinel" \
    '# Simulate a kernel-side helper-script failure: touch the preserve sentinel
# before emitting the (clean) KV footer. The driver must pick up the signal.
if [[ -n "$WORK_DIR" && -d "$WORK_DIR" ]]; then
  : > "$WORK_DIR/preserve.sentinel"
fi
printf "\n### iteration-result\n"
printf "ITER_STATUS=grade_a\n"
printf "EXIT_REASON=grade A achieved on all dimensions at iteration 1\n"
printf "PARSE_STATUS=ok\n"
printf "GRADE_A=true\n"
printf "NON_A_DIMS=\n"
printf "TOTAL_NUM=120\n"
printf "TOTAL_DEN=120\n"
printf "ITERATION_TMPDIR=\n"
printf "ISSUE_NUM=42\n"
exit 0' \
    'Retained working directory' \
    '' \
    'true'

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
