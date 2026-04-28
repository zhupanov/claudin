#!/usr/bin/env bash
# test-improve-skill-iteration.sh — Regression harness for the shared
# skills/improve-skill/scripts/iteration.sh kernel (factored out of the pre-
# #273 loop driver). Pins the per-iteration contract that both /improve-skill
# (standalone) and /loop-improve-skill (loop body) rely on.
#
# Two tiers of assertions:
#
#   Tier 1 — Structural (always runs):
#     Greps iteration.sh for contract tokens including: parse-skill-judge-
#     grade.sh, claude --version, set -euo pipefail, verify-skill-called.sh
#     --stdout-line '^✅ 18: cleanup', work-dir /tmp/ + /private/tmp/ prefix
#     literals, `..` rejection, --plugin-dir + CLAUDE_PLUGIN_ROOT, file-based
#     prompt writes, /larch:design + /larch:im fully-qualified invocations,
#     stderr-sidecar redirects (FINDING_10), STDIN prompt pattern (FINDING_9),
#     redact-secrets.sh, cleanup-tmpdir.sh, the kernel's KV footer schema
#     (trap emit_kv_footer EXIT, ### iteration-result header, all 9 keys),
#     the amended /design prompt's four-rule directive set (rules 1-3 plus
#     the new rule 4 pushback carve-out — load-bearing "## Pushback on judge
#     findings" subsection + "MAY disagree with specific" key phrase), and
#     the NO_SLACK_FLAG="--no-slack " byte-parallel literal.
#
#   Tier 2 — Behavioral (best-effort smoke tests with stubbed claude + gh):
#     Stubs `claude` and `gh` on PATH under a mktemp'd fixture skill dir and
#     invokes iteration.sh with --work-dir set, asserting on the KV footer
#     emitted on stdout. Fixtures cover grade_a, no_plan, design_refusal,
#     im_verification_failed, issue_755_refusal_phrase_in_plan_body, and
#     judge_subprocess_failure (issue #399 retention path).
#
# Invoked via:  bash scripts/test-improve-skill-iteration.sh
# Wired into:   make lint (via the test-improve-skill-iteration target).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
KERNEL="$REPO_ROOT/skills/improve-skill/scripts/iteration.sh"

FAIL_COUNT=0
PASS_COUNT=0

pass() { echo "PASS: $*"; PASS_COUNT=$((PASS_COUNT + 1)); }
fail() { echo "FAIL: $*" >&2; FAIL_COUNT=$((FAIL_COUNT + 1)); }

# -----------------------------------------------------------------------
# Tier 1 — Structural asserts on iteration.sh source
# -----------------------------------------------------------------------

echo "--- Structural asserts on iteration.sh ---"

if [[ ! -f "$KERNEL" ]]; then
  fail "iteration.sh not found at $KERNEL"
  echo ""
  echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="
  exit 1
fi

check_contains() {
  local needle="$1"
  local label="$2"
  if LC_ALL=C grep -Fq -- "$needle" "$KERNEL"; then
    pass "iteration.sh contains: $label"
  else
    fail "iteration.sh missing: $label (needle: $needle)"
  fi
}

# Issue #838: file-wide grep -Fq passes as long as ANY occurrence of the
# needle exists, so a guard like `check_contains '/larch:design --auto'`
# silently passes even when ONLY the rescue prompt carries the token and the
# primary prompt has regressed. `check_count` asserts the exact occurrence
# count, anchoring both call sites (primary + rescue) so dropping `--auto`
# from either trips the guard.
check_count() {
  local needle="$1"
  local expected="$2"
  local label="$3"
  local got
  got="$(LC_ALL=C grep -F -c -- "$needle" "$KERNEL" || true)"
  if [[ "$got" == "$expected" ]]; then
    pass "iteration.sh has $expected occurrences of: $label"
  else
    fail "iteration.sh expected $expected occurrences of: $label (needle: $needle), got $got"
  fi
}

# ---------- Core security + subprocess contracts ----------
check_contains 'parse-skill-judge-grade.sh'                    'parse-skill-judge-grade.sh invocation'
check_contains 'claude --version'                              'claude --version forensic capture'
check_contains 'set -euo pipefail'                             'set -euo pipefail'
check_contains "verify-skill-called.sh"                        'verify-skill-called.sh invocation'
check_contains "--stdout-line '^✅ 18: cleanup'"               'verify-skill-called.sh stdout-line mechanical gate'
check_contains '/tmp/'                                         'work-dir /tmp/ prefix literal'
check_contains '/private/tmp/'                                 'work-dir /private/tmp/ prefix literal'
check_contains "'..'"                                          '.. rejection check (single-quoted literal in message/case)'
check_contains 'redact-secrets.sh'                             'redact-secrets.sh in gh-comment pipeline'
check_contains 'cleanup-tmpdir.sh'                             'cleanup-tmpdir.sh invocation (standalone cleanup)'
check_contains 'gh issue comment'                              'gh issue comment posting'
check_contains 'gh issue create'                               'gh issue create (standalone-mode tracking issue)'
check_contains 'session-setup.sh'                              'session-setup.sh invocation (standalone mode)'
check_contains 'claude -p'                                     'claude -p subprocess invocation'
# FINDING_7: every child claude invocation must pass --plugin-dir.
check_contains '--plugin-dir'                                  'claude -p --plugin-dir argument (FINDING_7)'
# shellcheck disable=SC2016
check_contains '"$CLAUDE_PLUGIN_ROOT"'                         'CLAUDE_PLUGIN_ROOT passed as --plugin-dir value'
# Issue #585: non-interactive permission contract on every claude -p child so
# that an in-child tool-permission prompt cannot stall invoke_claude_p until
# the 3600s timeout fires. Both tokens must appear adjacent on the executable
# argv line; Tier-2 fixtures below additionally assert the constructed argv.
check_contains '--permission-mode bypassPermissions'           'non-interactive permission contract for claude -p children (issue #585)'
# FINDING_7: fully-qualified slash-command names for larch-shipped children.
check_contains '/larch:design'                                 'fully-qualified /larch:design invocation'
check_contains '/larch:im'                                     'fully-qualified /larch:im invocation'
# Issue #758: primary /design and /im prompts MUST carry --auto so the
# subprocess-driven /design and /im runs are non-interactive (matching the
# rescue retry which already passes --auto). Without these pins, the fix in
# iteration.sh could silently regress.
#
# Issue #838: `/larch:design --auto` appears at TWO sites in iteration.sh —
# the primary prompt and the rescue prompt. A file-wide `check_contains`
# would silently pass even if the primary regressed, because the rescue
# would still satisfy the grep. Pin the exact count instead so dropping
# `--auto` from EITHER site trips the guard. `/larch:im --auto` only has
# one site (the primary), so check_contains there is still effective.
check_count    '/larch:design --auto' 2                        'primary + rescue /larch:design --auto prompts (issues #758, #838)'
check_contains '/larch:im --auto'                              'primary /larch:im --auto prompt (issue #758)'
# FINDING_10: stderr MUST NOT merge into stdout (which is posted publicly).
# shellcheck disable=SC2016
check_contains '2> "$stderr_file"'                             'stderr redirected to separate file (FINDING_10)'
# shellcheck disable=SC2016
check_contains 'local stderr_file="${out_file}.stderr"'        '.stderr sidecar naming (FINDING_10)'
# FINDING_9: prompt body fed via STDIN (not argv) so large plans do not
# exceed macOS ARG_MAX = 262144.
# shellcheck disable=SC2016
check_contains '< "$prompt_file"'                              'prompt-file fed via STDIN (FINDING_9)'
# Per-iteration artifact filename template (driver close-out reads these
# at the same paths via $LOOP_TMPDIR; drift here breaks the loop close-out).
# shellcheck disable=SC2016
check_contains 'iter-${ITER_NUM}-judge-prompt.txt'             'file-based judge prompt template'
# shellcheck disable=SC2016
check_contains 'iter-${ITER_NUM}-design-prompt.txt'            'file-based design prompt template'
# shellcheck disable=SC2016
check_contains 'iter-${ITER_NUM}-im-prompt.txt'                'file-based im prompt template'
# shellcheck disable=SC2016
check_contains 'iter-${ITER_NUM}-infeasibility.md'             'infeasibility filename template (driver close-out reads this)'
# FINDING_11 parallel: IMPROVE_SKILL_SKIP_PREFLIGHT opt-in for test harnesses.
check_contains 'IMPROVE_SKILL_SKIP_PREFLIGHT'                  'opt-in preflight-skip env var'

# ---------- Issue #399 — tmpdir retention + stderr dump contracts ----------
check_contains 'PRESERVE_WORK_DIR'                             'retention flag (issue #399 remedy (a))'
check_contains 'dump_subprocess_diagnostics'                   'subprocess-diagnostics helper (issue #399 remedy (b))'
check_contains 'dump_helper_stderr'                            'helper-stderr dump helper (issue #399 remedy (c))'
check_contains '── subprocess stderr (label='                  'subprocess-stderr banner literal (issue #399)'
check_contains '── subprocess stdout tail (label='             'subprocess-stdout-tail banner literal (issue #399)'
check_contains 'tail -n 50'                                    'stdout-tail 50-line cap (issue #399)'
check_contains 'banner-redacted'                               'sed spoof-guard for ### iteration-result (issue #399)'
check_contains 'preserve.sentinel'                             'cross-boundary preserve sentinel (issue #399)'
check_contains 'grade_a|ok'                                    'status-gate case pattern in cleanup_on_exit (issue #399)'
check_contains 'gh-create-issue.stderr'                        'standalone gh issue create stderr sidecar (issue #399)'
check_contains 'gh-comment.stderr'                             'post_gh_comment stderr sidecar (issue #399)'

# ---------- Argv flags ----------
check_contains '--no-slack'                                    '--no-slack flag handling'
check_contains '--issue'                                       '--issue flag handling'
check_contains '--work-dir'                                    '--work-dir flag handling'
check_contains '--iter-num'                                    '--iter-num flag handling'
check_contains '--breadcrumb-prefix'                           '--breadcrumb-prefix flag handling'
# NO_SLACK_FLAG byte-parallel literal (trailing space matters for /larch:im prompt composition).
check_contains 'NO_SLACK_FLAG="--no-slack "'                   'NO_SLACK_FLAG byte-parallel literal'

# ---------- KV footer (EXIT trap + schema) ----------
check_contains 'trap cleanup_on_exit EXIT'                     'EXIT trap (guarantees KV footer emission)'
check_contains 'emit_kv_footer'                                'emit_kv_footer function (KV footer emitter)'
check_contains '### iteration-result'                          'KV footer delimiter header'
check_contains 'ITER_STATUS'                                   'KV footer key: ITER_STATUS'
check_contains 'EXIT_REASON'                                   'KV footer key: EXIT_REASON'
check_contains 'PARSE_STATUS'                                  'KV footer key: PARSE_STATUS'
check_contains 'GRADE_A'                                       'KV footer key: GRADE_A'
check_contains 'NON_A_DIMS'                                    'KV footer key: NON_A_DIMS'
check_contains 'TOTAL_NUM'                                     'KV footer key: TOTAL_NUM'
check_contains 'TOTAL_DEN'                                     'KV footer key: TOTAL_DEN'
check_contains 'ITERATION_TMPDIR'                              'KV footer key: ITERATION_TMPDIR'
check_contains 'ISSUE_NUM'                                     'KV footer key: ISSUE_NUM'

# ---------- Amended /design prompt four-rule directive set ----------
# Rules 1-3 (pre-existing) must remain byte-present alongside rule 4.
check_contains 'MUST produce a concrete, implementable plan for ANY actionable'  'Rule 1: no-minor-self-curtailment'
check_contains 'MUST NOT self-curtail citing token/context budget'               'Rule 2: no-budget-self-curtailment'
check_contains 'MUST NOT emit any of the no-plan sentinel phrases'               'Rule 3: no-no-plan-sentinels'
# Rule 4 (NEW — narrow per-finding pushback carve-out).
check_contains 'MAY disagree with specific /skill-judge findings'                'Rule 4: pushback carve-out header phrase'
check_contains '## Pushback on judge findings'                                   'Rule 4: pushback subsection name'
check_contains 'does NOT override rules 1-3'                                     'Rule 4: non-override clause'

# ---------- Breadcrumb helpers (filter-regex parity with SKILL.md) ----------
check_contains "printf '> **🔶 %s%s**"                         'breadcrumb_inprogress printf (> **🔶 prefix)'
check_contains "printf '✅ %s%s"                                'breadcrumb_done printf (✅ prefix)'
check_contains "printf '**⚠ %s%s**"                             'breadcrumb_warn printf (**⚠ prefix)'

# -----------------------------------------------------------------------
# Tier 1b — Syntax check
# -----------------------------------------------------------------------

if bash -n "$KERNEL" 2>/dev/null; then
  pass "iteration.sh passes bash -n syntax check"
else
  fail "iteration.sh fails bash -n syntax check"
fi

# -----------------------------------------------------------------------
# Tier 2 — Behavioral smoke fixtures with stubbed claude + gh
# -----------------------------------------------------------------------

echo ""
echo "--- Behavioral smoke fixtures ---"

# Run one fixture: set up stubs on PATH, invoke iteration.sh, assert on
# the KV footer in stdout.
run_fixture() {
  local name="$1"
  local judge_body_cmd="$2"
  local design_body_cmd="$3"
  local im_body_cmd="$4"
  local expect_iter_status="$5"

  # Explicitly create fixture tmpdir under /tmp so iteration.sh's work-dir
  # security check (which accepts only /tmp/ or /private/tmp/ prefixes)
  # passes. Default mktemp on macOS uses /var/folders/.../T/ which fails.
  local fixture_tmp
  fixture_tmp="$(mktemp -d -p /tmp tmp.XXXXXXXXXX 2>/dev/null || mktemp -d /tmp/tmp.XXXXXXXXXX)"
  local stub_dir="$fixture_tmp/stubs"
  local work_dir="$fixture_tmp/work"
  local iter_workdir="$fixture_tmp/iter-workdir"
  mkdir -p "$stub_dir" "$work_dir/skills/testskill" "$iter_workdir"

  cat > "$work_dir/skills/testskill/SKILL.md" <<'SKILL_EOF'
---
name: testskill
description: "Fixture skill"
---
# testskill
Fixture.
SKILL_EOF

  # Stub gh
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
      comment) exit 0 ;;
    esac
    ;;
esac
exit 0
GH_EOF
  chmod +x "$stub_dir/gh"

  # Build per-phase body files
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

  # Stub claude (FINDING_9 contract: prompt on stdin).
  # Issue #585: log argv (excluding --version) so the post-invocation assertion
  # below can verify the kernel constructs --permission-mode bypassPermissions.
  # --permission-mode must be parsed as a 2-arg flag like --plugin-dir, else
  # `bypassPermissions` would be mistaken for the positional prompt and break
  # FINDING_9's stdin path.
  cat > "$stub_dir/claude" <<CLAUDE_EOF
#!/usr/bin/env bash
if [[ "\$1" == "--version" ]]; then
  echo "claude stub 0.0.0"
  exit 0
fi
printf '%s\n' "\$*" >> "$fixture_tmp/claude-argv.log"
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    -p) shift ;;
    --plugin-dir) shift 2 ;;
    --permission-mode) shift 2 ;;
    --*) shift ;;
    *) break ;;
  esac
done
if [[ \$# -gt 0 ]]; then
  prompt="\$1"
else
  prompt="\$(cat)"
fi
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

  # Invoke iteration.sh (loop-mode: supply --work-dir so iteration does NOT
  # call session-setup.sh, which would fail in this non-git fixture workdir).
  local iter_log="$fixture_tmp/iter.log"
  local rc=0
  (
    cd "$work_dir"
    PATH="$stub_dir:$PATH" \
    CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
      bash "$KERNEL" \
        --issue 42 \
        --work-dir "$iter_workdir" \
        --iter-num 1 \
        testskill
  ) > "$iter_log" 2>&1 || rc=$?

  # Extract ITER_STATUS from KV footer
  local got_status
  got_status="$(awk -F= '/^ITER_STATUS=/{print $2; exit}' "$iter_log" 2>/dev/null || true)"

  if [[ "$got_status" == "$expect_iter_status" ]]; then
    pass "fixture [$name]: ITER_STATUS=$expect_iter_status (as expected)"
  else
    fail "fixture [$name]: expected ITER_STATUS=$expect_iter_status, got '$got_status' (rc=$rc)"
    echo "    === iter.log (tail) ===" >&2
    tail -40 "$iter_log" >&2 || true
  fi

  # Every fixture should emit the `### iteration-result` delimiter.
  if grep -Fq -- '### iteration-result' "$iter_log" 2>/dev/null; then
    pass "fixture [$name]: KV footer delimiter emitted"
  else
    fail "fixture [$name]: missing '### iteration-result' KV footer delimiter"
  fi

  # Issue #585: every claude -p child invocation constructed by
  # invoke_claude_p must carry the non-interactive permission contract.
  # The stub appends each non-`--version` invocation's argv to claude-argv.log
  # before its shift loop; assert at least one logged argv contains the pair.
  if [[ -f "$fixture_tmp/claude-argv.log" ]] && \
     grep -Fq -- '--permission-mode bypassPermissions' "$fixture_tmp/claude-argv.log"; then
    pass "fixture [$name]: claude -p argv carried --permission-mode bypassPermissions (issue #585)"
  else
    fail "fixture [$name]: claude -p argv missing --permission-mode bypassPermissions (issue #585)"
    if [[ -f "$fixture_tmp/claude-argv.log" ]]; then
      echo "    === claude-argv.log ===" >&2
      cat "$fixture_tmp/claude-argv.log" >&2 || true
    fi
  fi

  rm -rf "$fixture_tmp" 2>/dev/null || true
}

if [[ -x "$REPO_ROOT/scripts/parse-skill-judge-grade.sh" && \
      -x "$REPO_ROOT/scripts/verify-skill-called.sh" && \
      -x "$REPO_ROOT/scripts/redact-secrets.sh" ]]; then

  # Grade-A judge table
  GRADE_A_JUDGE="$(cat <<'EOF'
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
  )"

  # Non-A judge table
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

  # Fixture 1: grade_a at iter 1 (short-circuits before /design + /im)
  run_fixture \
    "grade_a" \
    "cat <<'HEREDOC_EOF'
$GRADE_A_JUDGE
HEREDOC_EOF" \
    "echo 'should not be called'" \
    "echo 'should not be called'" \
    "grade_a"

  # Fixture 2: no_plan (non-A judge, design returns "No plan.")
  run_fixture \
    "no_plan" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf 'No plan.\n'" \
    "echo 'should not be called'" \
    "no_plan"

  # Fixture 3: design_refusal (non-A judge, design starts with 'Error:')
  run_fixture \
    "design_refusal" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf 'Error: /design could not run\n'" \
    "echo 'should not be called'" \
    "design_refusal"

  # Fixture 4: im_verification_failed (valid plan, /im output lacks ✅ 18: cleanup)
  run_fixture \
    "im_verification_failed" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf '## Implementation Plan\n\n- Step one\n- Step two\n'" \
    "printf 'Some output but no canonical completion line.\n'" \
    "im_verification_failed"

  # Fixture 4b — issue #755: a valid plan whose body contains a line that
  # matches the refusal regex (e.g. "Cannot run in parallel ...") must NOT be
  # classified as design_refusal. The fix narrows refusal detection to the
  # first non-empty line; the canonical `## Implementation Plan` header
  # explicit-search establishes plan presence robustly. Expected flow:
  # plan_ok → /im → im_verification_failed (the gate is "anything except
  # design_refusal" — im_verification_failed is the closest reachable terminal
  # status given the /im stub's non-canonical output).
  run_fixture \
    "issue_755_refusal_phrase_in_plan_body" \
    "cat <<'HEREDOC_EOF'
$NON_A_JUDGE
HEREDOC_EOF" \
    "printf '## Implementation Plan\n\n- Add retry handler.\nCannot run in parallel — must serialize.\n- Add tests.\n'" \
    "printf 'Some output but no canonical completion line.\n'" \
    "im_verification_failed"

  # Fixture 5 — issue #399: subprocess failure triggers diagnostics dump +
  # work-dir retention. The judge stub exits non-zero with stderr content;
  # iteration.sh's invoke_claude_p must (a) dump a redacted ── subprocess
  # stderr banner + stdout tail to stdout, (b) NOT clean up the work-dir
  # (PRESERVE_WORK_DIR=true via the KV_ITER_STATUS != grade_a|ok gate).
  judge_failure_fixture() {
    local name="judge_subprocess_failure"
    local fixture_tmp stub_dir work_dir iter_workdir
    fixture_tmp="$(mktemp -d -p /tmp tmp.XXXXXXXXXX 2>/dev/null || mktemp -d /tmp/tmp.XXXXXXXXXX)"
    stub_dir="$fixture_tmp/stubs"
    work_dir="$fixture_tmp/work"
    iter_workdir="$fixture_tmp/iter-workdir"
    mkdir -p "$stub_dir" "$work_dir/skills/testskill" "$iter_workdir"
    cat > "$work_dir/skills/testskill/SKILL.md" <<'SKILL_EOF'
---
name: testskill
description: "Fixture skill"
---
# testskill
SKILL_EOF
    cat > "$stub_dir/gh" <<'GH_EOF'
#!/usr/bin/env bash
exit 0
GH_EOF
    chmod +x "$stub_dir/gh"
    # claude stub: always fails, writes a distinctive stderr marker so the
    # fixture can assert the dump captured it verbatim.
    cat > "$stub_dir/claude" <<'CLAUDE_EOF'
#!/usr/bin/env bash
if [[ "$1" == "--version" ]]; then echo "claude stub 0.0.0"; exit 0; fi
printf 'FIXTURE_STDERR_MARKER: subprocess failure\n' >&2
exit 3
CLAUDE_EOF
    chmod +x "$stub_dir/claude"

    local iter_log="$fixture_tmp/iter.log"
    local rc=0
    (
      cd "$work_dir"
      PATH="$stub_dir:$PATH" \
      CLAUDE_PLUGIN_ROOT="$REPO_ROOT" \
        bash "$KERNEL" \
          --issue 42 \
          --work-dir "$iter_workdir" \
          --iter-num 1 \
          testskill
    ) > "$iter_log" 2>&1 || rc=$?

    # Assert the dump banner appeared.
    if grep -Fq '── subprocess stderr (label=judge) ──' "$iter_log" 2>/dev/null; then
      pass "fixture [$name]: subprocess-stderr banner emitted"
    else
      fail "fixture [$name]: missing '── subprocess stderr (label=judge) ──' banner"
      echo "    === iter.log (tail) ===" >&2
      tail -60 "$iter_log" >&2 || true
    fi

    # Assert the stderr marker itself reached stdout (verbatim — redact-secrets
    # does not alter non-secret content).
    if grep -Fq 'FIXTURE_STDERR_MARKER: subprocess failure' "$iter_log" 2>/dev/null; then
      pass "fixture [$name]: verbatim stderr content reached stdout after redaction"
    else
      fail "fixture [$name]: stderr marker 'FIXTURE_STDERR_MARKER' not in iter.log"
    fi

    # Assert ITER_STATUS was flipped to judge_failed (invoke_claude_p non-zero
    # on judge phase maps to judge_failed in iteration.sh).
    local got_status
    got_status="$(awk -F= '/^ITER_STATUS=/{print $2; exit}' "$iter_log" 2>/dev/null || true)"
    if [[ "$got_status" == "judge_failed" ]]; then
      pass "fixture [$name]: ITER_STATUS=judge_failed (as expected)"
    else
      fail "fixture [$name]: expected ITER_STATUS=judge_failed, got '$got_status' (rc=$rc)"
    fi

    # Assert the iteration work-dir persists (retention path). In loop mode
    # iteration.sh does not clean the caller-supplied work-dir anyway; for
    # standalone retention we would need OWNS_WORK_DIR=true. This fixture
    # supplies --work-dir so retention is a driver-level concern; we check
    # instead that the sentinel would have been touchable (the dir exists).
    if [[ -d "$iter_workdir" ]]; then
      pass "fixture [$name]: work-dir persists (caller-owned in loop mode)"
    else
      fail "fixture [$name]: work-dir unexpectedly cleaned"
    fi

    rm -rf "$fixture_tmp" 2>/dev/null || true
  }
  judge_failure_fixture

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
