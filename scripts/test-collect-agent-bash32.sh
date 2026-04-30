#!/usr/bin/env bash
# test-collect-agent-bash32.sh — Regression test for the bash 3.2
# portability hazard in scripts/collect-agent-results.sh:405 (issue #511).
#
# The collector runs `set -uo pipefail` (line 57). Before #511, the validator
# call expanded `"${VAL_ARGS[@]}"` directly; on bash 3.2 (macOS default
# /bin/bash) that expansion raises `VAL_ARGS[@]: unbound variable` when the
# array is empty, which happens whenever a caller passes
# `--substantive-validation` without `--validation-mode` (e.g., `/research`
# Step 1.4). The validator never runs, the wrapper writes
# STATUS=NOT_SUBSTANTIVE for every reviewer file, and callers fall through
# to spurious Claude subagent re-runs. The fix uses the bash-3.2-safe
# expansion idiom `"${VAL_ARGS[@]+"${VAL_ARGS[@]}"}"` (precedented at
# scripts/create-pr.sh:105) plus a WHY-comment at the call site.
#
# This harness layers two checks:
#
#   Case 1 — Static idiom check (always runs): grep
#     scripts/collect-agent-results.sh for the safe-expansion idiom near
#     the validator call. Linux-CI regression backstop on every PR;
#     bash 5.x does not naturally exhibit the bug at runtime.
#
#   Case 2 — Dynamic empty-VAL_ARGS path (only under /bin/bash 3.x):
#     ≥200-word substantive fixture with .done sentinel containing 0;
#     invoke /bin/bash $REPO_ROOT/scripts/collect-agent-results.sh
#     --timeout 30 --substantive-validation <abs-fixture>; assert
#     STATUS=OK AND stderr does NOT contain `unbound variable`.
#     Skip-with-loud-message on bash 4+.
#
#   Case 3 — Dynamic non-empty-VAL_ARGS path / --validation-mode forwarding
#     pin (only under /bin/bash 3.x): literal NO_ISSUES_FOUND fixture;
#     run with --substantive-validation --validation-mode → STATUS=OK
#     (positive); run again WITHOUT --validation-mode → STATUS=NOT_SUBSTANTIVE
#     (negative control — confirms the flag actually changes behavior).
#     Skip-with-loud-message on bash 4+.
#
# Wired into Makefile via the test-collect-agent-bash32 target and the
# test-harnesses aggregator; runs on every `make lint`.

set -uo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
COLLECTOR="$REPO_ROOT/scripts/collect-agent-results.sh"

PASS=0
FAIL=0
SKIP=0
FAILED=()

ok()    { PASS=$((PASS + 1)); echo "  ok: $1"; }
fail()  { FAIL=$((FAIL + 1)); FAILED+=("$1"); echo "  FAIL: $1" >&2; }
skipm() { SKIP=$((SKIP + 1)); echo "  SKIPPED: $1"; }

# --- Case 1: static idiom check (always runs) -------------------------------
#
# Pin the safe-expansion idiom on the validator-invocation line. The pattern
# requires both the `${arr[@]+...}` guard form AND the surrounding `$VALIDATOR`
# call so a future refactor that splits the call site or renames VAL_ARGS will
# fail this check until the regex and this contract are updated together.
# shellcheck disable=SC2016 # Literal regex; outer-shell expansion is intentionally suppressed.
if grep -q '"\${VAL_ARGS\[@\]+"\${VAL_ARGS\[@\]}"}"' "$COLLECTOR" \
   && grep -q '\$VALIDATOR.*VAL_ARGS\[@\]+' "$COLLECTOR"; then
    ok "case 1: safe-expansion idiom present at validator call site"
else
    fail "case 1: safe-expansion idiom missing in $COLLECTOR — issue #511 may have regressed"
fi

# --- Cases 2/3: dynamic checks under vulnerable bash (< 4.4) ----------------
#
# Bash 4.4 fixed the empty-array nounset hazard, so the dynamic checks only
# trigger the original bug under bash 3.x AND bash 4.0-4.3 (both vulnerable).
# Run dynamic cases on any /bin/bash whose version is < 4.4; skip-with-loud-
# message only on bash 4.4+. Case 1 (static grep) is the always-on regression
# backstop regardless of bash version (Linux CI bash 5.x runs Case 1 only).
SYSTEM_BASH="/bin/bash"
BASH_MAJOR=""
BASH_MINOR=""
if [[ -x "$SYSTEM_BASH" ]]; then
    # shellcheck disable=SC2016 # `${BASH_VERSINFO[0]}` / `[1]` are expanded by the inner /bin/bash, not by the outer shell.
    BASH_MAJOR="$("$SYSTEM_BASH" -c 'echo "${BASH_VERSINFO[0]}"' 2>/dev/null || echo "")"
    # shellcheck disable=SC2016
    BASH_MINOR="$("$SYSTEM_BASH" -c 'echo "${BASH_VERSINFO[1]}"' 2>/dev/null || echo "")"
fi

# Dynamic gate: vulnerable iff (major == 3) OR (major == 4 AND minor < 4).
DYNAMIC_VULNERABLE="false"
if [[ "$BASH_MAJOR" == "3" ]]; then
    DYNAMIC_VULNERABLE="true"
elif [[ "$BASH_MAJOR" == "4" ]] && [[ -n "$BASH_MINOR" ]] && (( BASH_MINOR < 4 )); then
    DYNAMIC_VULNERABLE="true"
fi

if [[ "$DYNAMIC_VULNERABLE" != "true" ]]; then
    BASH_VER_DISPLAY="${BASH_MAJOR:-unknown}.${BASH_MINOR:-?}"
    skipm "case 2: bash $BASH_VER_DISPLAY at $SYSTEM_BASH (need < 4.4 for dynamic empty-VAL_ARGS check; bash 4.4+ fixed the hazard)"
    skipm "case 3: bash $BASH_VER_DISPLAY at $SYSTEM_BASH (need < 4.4 for --validation-mode forwarding pin)"
else
    TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-collect-agent-bash32-XXXXXX")"
    trap 'rm -rf "$TMPROOT"' EXIT

    # --- Fixture for Case 2: ≥200 words substantive prose with file:line citation
    #
    # Matches `validate-research-output.sh` defaults (--min-words 200) so the
    # validator returns exit 0 (STATUS=OK). Basename contains `cursor` so
    # `derive_tool` in the collector attributes correctly. Pre-create the
    # .done sentinel containing 0 BEFORE invoking the collector so
    # wait-for-reviewers.sh finds it immediately under the small --timeout.
    F2="$TMPROOT/cursor-substantive-output.txt"
    awk 'BEGIN { for (i = 0; i < 250; i++) printf "lorem%d ", i; printf "\n" }' > "$F2"
    echo 'See path/to/file.md:42 for the relevant context.' >> "$F2"
    : > "$F2.done"
    printf '0' > "$F2.done"

    # Case 2: --substantive-validation without --validation-mode → empty VAL_ARGS
    cd "$REPO_ROOT" || { fail "case 2: cd to REPO_ROOT failed"; exit 1; }
    OUT2="$("$SYSTEM_BASH" "$COLLECTOR" --timeout 30 --substantive-validation "$F2" 2>"$TMPROOT/case2.stderr")"
    if echo "$OUT2" | grep -q '^STATUS=OK$'; then
        if grep -q 'unbound variable' "$TMPROOT/case2.stderr"; then
            fail "case 2: STATUS=OK but stderr contains 'unbound variable' — bash 3.2 hazard regressed"
        else
            ok "case 2: empty VAL_ARGS under /bin/bash 3.x, STATUS=OK, clean stderr"
        fi
    else
        ACTUAL_STATUS="$(echo "$OUT2" | grep '^STATUS=' | head -1)"
        if grep -q 'unbound variable' "$TMPROOT/case2.stderr"; then
            fail "case 2: bash 3.2 unbound-variable hazard fired — issue #511 regressed (got: $ACTUAL_STATUS)"
        else
            fail "case 2: validator did not return OK (got: $ACTUAL_STATUS) — fixture or collector contract drifted"
        fi
    fi

    # --- Fixture for Case 3: literal NO_ISSUES_FOUND
    #
    # Fails default `validate-research-output.sh` (200-word floor) but passes
    # under --validation-mode (which short-circuits on the literal token).
    # Pinning STATUS=OK with --validation-mode AND STATUS=NOT_SUBSTANTIVE
    # without proves the flag is actually being forwarded through the safe
    # expansion idiom (regression guard for the non-empty branch).
    F3="$TMPROOT/cursor-no-issues-output.txt"
    printf 'NO_ISSUES_FOUND\n' > "$F3"
    : > "$F3.done"
    printf '0' > "$F3.done"

    # Case 3 positive: --validation-mode forwards, validator short-circuits → OK
    OUT3a="$("$SYSTEM_BASH" "$COLLECTOR" --timeout 30 --substantive-validation --validation-mode "$F3" 2>"$TMPROOT/case3a.stderr")"
    if echo "$OUT3a" | grep -q '^STATUS=OK$'; then
        ok "case 3 positive: NO_ISSUES_FOUND fixture under --validation-mode → STATUS=OK"
    else
        ACTUAL_STATUS_A="$(echo "$OUT3a" | grep '^STATUS=' | head -1)"
        fail "case 3 positive: NO_ISSUES_FOUND under --validation-mode did not return OK (got: $ACTUAL_STATUS_A) — flag forwarding broken"
    fi

    # Case 3 negative control: same fixture without --validation-mode → NOT_SUBSTANTIVE
    # (200-word floor rejects the 1-word fixture). Confirms --validation-mode
    # actually changes behavior; the same fixture must NOT pass without it.
    F3b="$TMPROOT/cursor-no-issues-control.txt"
    printf 'NO_ISSUES_FOUND\n' > "$F3b"
    : > "$F3b.done"
    printf '0' > "$F3b.done"
    OUT3b="$("$SYSTEM_BASH" "$COLLECTOR" --timeout 30 --substantive-validation "$F3b" 2>"$TMPROOT/case3b.stderr")"
    if echo "$OUT3b" | grep -q '^STATUS=NOT_SUBSTANTIVE$'; then
        if grep -q 'unbound variable' "$TMPROOT/case3b.stderr"; then
            fail "case 3 negative: STATUS=NOT_SUBSTANTIVE but stderr contains 'unbound variable' — bash 3.2 hazard"
        else
            ok "case 3 negative: NO_ISSUES_FOUND without --validation-mode → STATUS=NOT_SUBSTANTIVE (200-word floor)"
        fi
    else
        ACTUAL_STATUS_B="$(echo "$OUT3b" | grep '^STATUS=' | head -1)"
        fail "case 3 negative: same fixture without --validation-mode did not reject (got: $ACTUAL_STATUS_B) — flag is not actually changing behavior"
    fi
fi

echo ""
echo "Summary: $PASS passed, $FAIL failed, $SKIP skipped"
if (( FAIL > 0 )); then
    echo "Failed cases:" >&2
    for t in "${FAILED[@]+"${FAILED[@]}"}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
exit 0
