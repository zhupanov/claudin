#!/usr/bin/env bash
#
# Regression harness for scripts/lib-loop-improve-halt-ledger.sh.
# Offline fixtures via mktemp -d + touch; asserts classify_halt_location KV output.
#
# Wired into `make lint` via the `test-lib-halt-ledger` target.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
LIB="$SCRIPT_DIR/lib-loop-improve-halt-ledger.sh"

if [[ ! -f "$LIB" ]]; then
    echo "FAIL: library not found at $LIB" >&2
    exit 1
fi

# shellcheck source=scripts/lib-loop-improve-halt-ledger.sh
source "$LIB"

FAIL_COUNT=0
PASS_COUNT=0

# assert_kv <description> <output> <expected-key=expected-value>
assert_kv() {
    local desc="$1" output="$2" expected="$3"
    if printf '%s\n' "$output" | grep -Fxq -- "$expected"; then
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL: $desc — missing line '$expected'" >&2
        echo "  got:" >&2
        printf '%s\n' "$output" | sed 's/^/    /' >&2
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

# Case (a): empty LOOP_TMPDIR (no sentinels at all).
tmpdir_a=$(mktemp -d -t halt-ledger-test.XXXX)
out=$(classify_halt_location "$tmpdir_a")
assert_kv "(a) empty dir - ITER" "$out" "ITER=none"
assert_kv "(a) empty dir - LAST_COMPLETED" "$out" "LAST_COMPLETED=none"
assert_kv "(a) empty dir - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"
rm -rf "$tmpdir_a"

# Case (b): nonexistent LOOP_TMPDIR path.
out=$(classify_halt_location "/tmp/nonexistent-halt-ledger-$$-$RANDOM")
assert_kv "(b) nonexistent dir" "$out" "ITER=none"
assert_kv "(b) nonexistent dir - LAST_COMPLETED" "$out" "LAST_COMPLETED=none"
assert_kv "(b) nonexistent dir - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"

# Case (c): empty string arg.
out=$(classify_halt_location "")
assert_kv "(c) empty arg" "$out" "ITER=none"
assert_kv "(c) empty arg - LAST_COMPLETED" "$out" "LAST_COMPLETED=none"
assert_kv "(c) empty arg - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"

# Case (d): iter-1 done sentinel present (completed).
tmpdir_d=$(mktemp -d -t halt-ledger-test.XXXX)
printf 'VERIFIED=true\n' > "$tmpdir_d/iter-1-done.sentinel"
out=$(classify_halt_location "$tmpdir_d")
assert_kv "(d) iter-1 done - ITER" "$out" "ITER=1"
assert_kv "(d) iter-1 done - LAST_COMPLETED" "$out" "LAST_COMPLETED=done"
assert_kv "(d) iter-1 done - clause" "$out" "HALT_LOCATION_CLAUSE=completed iteration"
rm -rf "$tmpdir_d"

# Case (e): iter-1 halted at 3.j (3j.done present, nothing higher).
tmpdir_e=$(mktemp -d -t halt-ledger-test.XXXX)
printf 'ok\n' > "$tmpdir_e/iter-1-3j.done"
out=$(classify_halt_location "$tmpdir_e")
assert_kv "(e) iter-1 at 3j - ITER" "$out" "ITER=1"
assert_kv "(e) iter-1 at 3j - LAST_COMPLETED" "$out" "LAST_COMPLETED=3j"
assert_kv "(e) iter-1 at 3j - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before grade parse at 3.j.v"
rm -rf "$tmpdir_e"

# Case (f): iter-1 halted at 3jv.
tmpdir_f=$(mktemp -d -t halt-ledger-test.XXXX)
printf 'ok\n' > "$tmpdir_f/iter-1-3j.done"
printf 'ok\n' > "$tmpdir_f/iter-1-3jv.done"
out=$(classify_halt_location "$tmpdir_f")
assert_kv "(f) iter-1 at 3jv - LAST_COMPLETED" "$out" "LAST_COMPLETED=3jv"
assert_kv "(f) iter-1 at 3jv - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /design at 3.d"
rm -rf "$tmpdir_f"

# Case (g): iter-1 halted at 3d-pre-detect.
tmpdir_g=$(mktemp -d -t halt-ledger-test.XXXX)
for s in 3j 3jv 3d-pre-detect; do printf 'ok\n' > "$tmpdir_g/iter-1-${s}.done"; done
out=$(classify_halt_location "$tmpdir_g")
assert_kv "(g) iter-1 at 3d-pre-detect" "$out" "LAST_COMPLETED=3d-pre-detect"
assert_kv "(g) iter-1 at 3d-pre-detect - clause" "$out" "HALT_LOCATION_CLAUSE=halted during no-plan detector or before rescue at 3.d"
rm -rf "$tmpdir_g"

# Case (h): iter-1 halted at 3d-post-detect.
tmpdir_h=$(mktemp -d -t halt-ledger-test.XXXX)
for s in 3j 3jv 3d-pre-detect 3d-post-detect; do printf 'ok\n' > "$tmpdir_h/iter-1-${s}.done"; done
out=$(classify_halt_location "$tmpdir_h")
assert_kv "(h) iter-1 at 3d-post-detect" "$out" "LAST_COMPLETED=3d-post-detect"
assert_kv "(h) iter-1 at 3d-post-detect - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before plan-post at 3.d"
rm -rf "$tmpdir_h"

# Case (i): iter-1 halted at 3d-plan-post.
tmpdir_i=$(mktemp -d -t halt-ledger-test.XXXX)
for s in 3j 3jv 3d-pre-detect 3d-post-detect 3d-plan-post; do printf 'ok\n' > "$tmpdir_i/iter-1-${s}.done"; done
out=$(classify_halt_location "$tmpdir_i")
assert_kv "(i) iter-1 at 3d-plan-post" "$out" "LAST_COMPLETED=3d-plan-post"
assert_kv "(i) iter-1 at 3d-plan-post - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /im at 3.i"
rm -rf "$tmpdir_i"

# Case (j): iter-1 halted at 3i (all partials, no done.sentinel).
tmpdir_j=$(mktemp -d -t halt-ledger-test.XXXX)
for s in 3j 3jv 3d-pre-detect 3d-post-detect 3d-plan-post 3i; do printf 'ok\n' > "$tmpdir_j/iter-1-${s}.done"; done
out=$(classify_halt_location "$tmpdir_j")
assert_kv "(j) iter-1 at 3i" "$out" "LAST_COMPLETED=3i"
assert_kv "(j) iter-1 at 3i - clause" "$out" "HALT_LOCATION_CLAUSE=halted between 3.i verify and Step 4 close-out"
rm -rf "$tmpdir_j"

# Case (k): multi-iter — iter-1 done, iter-2 partial at 3jv. Highest iter wins.
tmpdir_k=$(mktemp -d -t halt-ledger-test.XXXX)
printf 'ok\n' > "$tmpdir_k/iter-1-done.sentinel"
printf 'ok\n' > "$tmpdir_k/iter-1-3j.done"
printf 'ok\n' > "$tmpdir_k/iter-1-3jv.done"
printf 'ok\n' > "$tmpdir_k/iter-2-3j.done"
printf 'ok\n' > "$tmpdir_k/iter-2-3jv.done"
out=$(classify_halt_location "$tmpdir_k")
assert_kv "(k) multi-iter iter-2 at 3jv - ITER" "$out" "ITER=2"
assert_kv "(k) multi-iter iter-2 at 3jv - LAST_COMPLETED" "$out" "LAST_COMPLETED=3jv"
rm -rf "$tmpdir_k"

# Case (l): multi-iter — iter-1 and iter-2 both done. Highest with done wins.
tmpdir_l=$(mktemp -d -t halt-ledger-test.XXXX)
printf 'ok\n' > "$tmpdir_l/iter-1-done.sentinel"
printf 'ok\n' > "$tmpdir_l/iter-2-done.sentinel"
out=$(classify_halt_location "$tmpdir_l")
assert_kv "(l) multi-iter both done - ITER" "$out" "ITER=2"
assert_kv "(l) multi-iter both done - LAST_COMPLETED" "$out" "LAST_COMPLETED=done"
rm -rf "$tmpdir_l"

# Case (m): empty sentinel file (size 0) — per SKILL.md, only non-empty sentinels count.
# The highest-iter scan uses -e (file exists) so ITER=1 is emitted, but the
# per-substep scan uses -s (non-empty) so LAST_COMPLETED stays 'none'. This
# documents the split semantics so future edits do not silently shift either half.
tmpdir_m=$(mktemp -d -t halt-ledger-test.XXXX)
: > "$tmpdir_m/iter-1-3j.done"   # empty
: > "$tmpdir_m/iter-1-done.sentinel"  # empty
out=$(classify_halt_location "$tmpdir_m")
assert_kv "(m) empty sentinels - ITER" "$out" "ITER=1"
assert_kv "(m) empty sentinels - LAST_COMPLETED" "$out" "LAST_COMPLETED=none"
assert_kv "(m) empty sentinels - clause" "$out" "HALT_LOCATION_CLAUSE=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"
rm -rf "$tmpdir_m"

# Case (n): clause_for_last_completed helper emits canonical strings.
# Token `done` is quoted so shellcheck SC1010 doesn't flag it as a for/while terminator.
assert_kv "(n) clause done" "LAST_COMPLETED=$(clause_for_last_completed "done")" "LAST_COMPLETED=completed iteration"
assert_kv "(n) clause 3i" "LAST_COMPLETED=$(clause_for_last_completed 3i)" "LAST_COMPLETED=halted between 3.i verify and Step 4 close-out"
assert_kv "(n) clause none" "LAST_COMPLETED=$(clause_for_last_completed none)" "LAST_COMPLETED=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"
assert_kv "(n) clause unknown-defaults-to-none" "LAST_COMPLETED=$(clause_for_last_completed bogus)" "LAST_COMPLETED=halted at or before /skill-judge at 3.j (or inner aborted during argument validation — see REASON)"

echo "PASS=$PASS_COUNT FAIL=$FAIL_COUNT"
if (( FAIL_COUNT > 0 )); then
    exit 1
fi
exit 0
