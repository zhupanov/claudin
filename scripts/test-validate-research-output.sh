#!/usr/bin/env bash
# test-validate-research-output.sh — Regression test for scripts/validate-research-output.sh.
#
# Cases (per the acceptance criteria in issue #416, extended for #447):
#   1. Happy path: substantive prose with one file:line citation → exit 0
#   2. Empty file → exit 2 (body thin)
#   3. Short-but-cited (50 words + citation) → exit 2 (body thin)
#   4. Long-but-uncited (250 words, no markers) → exit 3 (no marker)
#   5. Adversarial zero-citations (300 words, no markers) → exit 3
#   6. One file:line citation passes (250 words + path/file.go:7) → exit 0
#   7. One fenced code block with >= 1 line passes → exit 0
#   8. One URL passes → exit 0
#   9. --no-require-citations long-but-uncited → exit 0
#   10. --min-words 50 short-but-cited → exit 0
#   11. .pre-commit-config.yaml leading-dot file citation passes → exit 0
#   12. Makefile (extensionless) citation passes → exit 0
#   13. Empty fenced block (no content) does NOT count as a marker → exit 3
#   14. Fence interior excluded from word count (300 words inside ``` only) → exit 2
#   15. Missing file → exit 4
#   16. No file argument → exit 1 (usage error)
#   17. Unknown flag → exit 1 (usage error)
#   18. --validation-mode literal NO_ISSUES_FOUND passes → exit 0
#   19. --validation-mode NO_ISSUES_FOUND padded with blank lines passes → exit 0
#   20. --validation-mode short cited finding (40 words + file:line) passes (30-word floor) → exit 0
#   21. --validation-mode 10-word too-short → exit 2
#   22. --validation-mode 40-word uncited → exit 3
#   23. --validation-mode prose mentioning NO_ISSUES_FOUND inline + citation passes (full path, not short-circuit) → exit 0
#   24. --validation-mode --min-words 50 (override beats preset's 30) → exit 2
# Cases added by #447 (broadened extension list + trailing-boundary rule):
#   25. Broadened extension .tsx:42 passes → exit 0
#   26. Broadened extension .vue:1 passes → exit 0
#   27. Broadened extension .rb:7 passes → exit 0 (covers r/rb/rs prefix family)
#   28. Broadened extension .java:5 passes → exit 0
#   29. Broadened extension .css:10 passes → exit 0 (covers c/cs/css/csv prefix family)
#   30. Existing .json:1 still passes → exit 0 (covers js/json/jsx prefix family regression)
#   31. Fake-citation bypass file.mdjunk:42 → exit 3 (#447 defect (2) primary fix)
#   32. Bypass regression file.tsxfoo:1 → exit 3 (covers new-extension boundary)
#   33. Happy-path .md:42 still passes → exit 0 (no regression of existing case 1)
#   34. Prose-glued comma file.md, → exit 0 (boundary char is a real comma)
#   35. Compound-extension file.md.bak → exit 0 (substring match on .md; #447 boundary class allows `.` as boundary)
#   36. Sentence-ending period See file.go. → exit 0 (#447 boundary class allows `.` as boundary)
#   37. Bare-`:`-then-non-digits bypass file.md:garbage → exit 3 (#447 boundary class excludes `:`)
#   38. Slash-suffix bypass file.md/child → exit 3 (#447 boundary class excludes `/`)
# Cases added by #473 (short-extension strict-mode rule):
#   39. Verified repro: 250-word prose containing `the spin.lock primitive` → exit 3 (short-ext, no path-likeness signal)
#   40. 250-word prose containing `the my.env switch` → exit 3
#   41. 250-word prose containing `the big.m optimization` → exit 3
#   42. 250-word prose containing `the foo.r constant` → exit 3
#   43. 250-word prose containing `the raw.txt format` → exit 3
#   44. Bare `Cargo.lock` in prose (no line-ref, no path) → exit 3 (forward-compat behavioral change)
#   45. Compound `Cargo.lock.bak` in prose (no signal on inner .lock) → exit 3 (regression of pre-#473 case 35-style behavior — now rejects)
#   46. `Cargo.lock:7` (line-ref qualifier) → exit 0 (short-tier strict rule, :line-ref signal)
#   47. `app.env:5` (line-ref qualifier) → exit 0 (short-tier strict rule, :line-ref signal)
#   48. `foo.m:42` (line-ref qualifier) → exit 0 (short-tier strict rule, :line-ref signal)
#   49. `kernel/spin.lock` (slash qualifier, no line-ref) → exit 0 (short-tier strict rule, / signal)
#   50. `parser_state.h` (underscore qualifier, no line-ref) → exit 0 (short-tier strict rule, _ signal — snake_case)
#   51. `kernel-mod.h` (dash qualifier, no line-ref) → exit 0 (short-tier strict rule, - signal — kebab-case)
#
# Usage:
#   bash scripts/test-validate-research-output.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — first failure (message to stderr)

set -uo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/scripts/validate-research-output.sh"

if [[ ! -x "$HELPER" ]]; then
    echo "FAIL: $HELPER is not executable" >&2
    exit 1
fi

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-validate-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0
FAILED_TESTS=()

# Run helper, capture exit code and stdout. Args: <label> <expected_exit> [helper-args...] <file>
run_case() {
    local label="$1"; shift
    local expected_exit="$1"; shift
    local actual_exit actual_stdout
    actual_stdout=$("$HELPER" "$@" 2>&1)
    actual_exit=$?
    if [[ "$actual_exit" == "$expected_exit" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (exit $actual_exit)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected exit $expected_exit, got $actual_exit; stdout: ${actual_stdout:0:200})")
        echo "  FAIL: $label (expected exit $expected_exit, got $actual_exit)" >&2
        echo "        stdout: ${actual_stdout:0:200}" >&2
    fi
}

# Compose a fixture file with N space-separated word tokens.
make_words() {
    local n="$1" file="$2"
    awk -v n="$n" 'BEGIN { for (i = 0; i < n; i++) printf "lorem%d ", i; printf "\n" }' > "$file"
}

# --- Case 1: happy path (250 words + file:line citation) ---
F1="$TMPROOT/case1-happy.txt"
make_words 250 "$F1"
echo 'See path/to/file.md:42 for context.' >> "$F1"
run_case "case 1: happy path (250 words + file:line)" 0 "$F1"

# --- Case 2: empty file ---
F2="$TMPROOT/case2-empty.txt"
: > "$F2"
run_case "case 2: empty file" 2 "$F2"

# --- Case 3: short-but-cited (50 words + citation) ---
F3="$TMPROOT/case3-short-cited.txt"
make_words 50 "$F3"
echo 'See path/to/file.md:42 for context.' >> "$F3"
run_case "case 3: short-but-cited" 2 "$F3"

# --- Case 4: long-but-uncited (250 words, no markers, --require-citations on) ---
F4="$TMPROOT/case4-long-uncited.txt"
make_words 250 "$F4"
run_case "case 4: long-but-uncited" 3 "$F4"

# --- Case 5: adversarial zero-citations (300 words, no markers) ---
F5="$TMPROOT/case5-adversarial.txt"
make_words 300 "$F5"
run_case "case 5: adversarial zero-citations" 3 "$F5"

# --- Case 6: one file:line citation passes (250 words + .go:7) ---
F6="$TMPROOT/case6-fileline.txt"
make_words 250 "$F6"
echo 'Citation: pkg/server/main.go:7' >> "$F6"
run_case "case 6: one file:line citation" 0 "$F6"

# --- Case 7: one fenced code block with >= 1 line passes ---
F7="$TMPROOT/case7-fence.txt"
make_words 250 "$F7"
{
    echo '```bash'
    echo 'echo hello'
    echo '```'
} >> "$F7"
run_case "case 7: one fenced code block (with content)" 0 "$F7"

# --- Case 8: one URL passes ---
F8="$TMPROOT/case8-url.txt"
make_words 250 "$F8"
echo 'See https://example.com/foo for details.' >> "$F8"
run_case "case 8: one URL" 0 "$F8"

# --- Case 9: --no-require-citations long-but-uncited passes ---
F9="$TMPROOT/case9-no-citations.txt"
make_words 250 "$F9"
run_case "case 9: --no-require-citations long-but-uncited" 0 --no-require-citations "$F9"

# --- Case 10: --min-words 50 short-but-cited passes ---
F10="$TMPROOT/case10-min-words.txt"
make_words 60 "$F10"
echo 'See path/to/file.md:42 for context.' >> "$F10"
run_case "case 10: --min-words 50 short-but-cited" 0 --min-words 50 "$F10"

# --- Case 11: .pre-commit-config.yaml leading-dot file citation passes ---
F11="$TMPROOT/case11-hidden-file.txt"
make_words 250 "$F11"
echo 'See .pre-commit-config.yaml:7 for the hook config.' >> "$F11"
run_case "case 11: leading-dot hidden file citation" 0 "$F11"

# --- Case 12: Makefile extensionless citation passes ---
F12="$TMPROOT/case12-makefile.txt"
make_words 250 "$F12"
echo 'See Makefile:14 for the test-harnesses target.' >> "$F12"
run_case "case 12: Makefile extensionless citation" 0 "$F12"

# --- Case 13: empty fenced block (no content lines) does NOT count ---
F13="$TMPROOT/case13-empty-fence.txt"
make_words 250 "$F13"
{
    echo '```'
    echo '```'
} >> "$F13"
run_case "case 13: empty fenced block does not count" 3 "$F13"

# --- Case 14: fence interior excluded from word count ---
# Wrap 300 words inside a fence; outside the fence is a 5-word header.
# Result: word count outside fence = 5 < 200, so exit 2.
F14="$TMPROOT/case14-fence-strips-body.txt"
{
    echo 'Header line with five words.'
    echo '```'
} > "$F14"
make_words 300 "$TMPROOT/case14-words.txt"
cat "$TMPROOT/case14-words.txt" >> "$F14"
echo '```' >> "$F14"
run_case "case 14: fence interior excluded from word count" 2 "$F14"

# --- Case 15: missing file ---
run_case "case 15: missing file" 4 "$TMPROOT/does-not-exist.txt"

# --- Case 16: usage error (no file argument) ---
run_case "case 16: no file argument" 1

# --- Case 17: unknown flag ---
run_case "case 17: unknown flag" 1 --bogus-flag "$F1"

# --- Case 18: --validation-mode + literal NO_ISSUES_FOUND passes (no body / no citation needed) ---
F18="$TMPROOT/case18-noissues.txt"
echo 'NO_ISSUES_FOUND' > "$F18"
run_case "case 18: --validation-mode NO_ISSUES_FOUND" 0 --validation-mode "$F18"

# --- Case 19: --validation-mode NO_ISSUES_FOUND with surrounding blank lines passes ---
F19="$TMPROOT/case19-noissues-padded.txt"
{
    echo ''
    echo '   NO_ISSUES_FOUND   '
    echo ''
    echo ''
} > "$F19"
run_case "case 19: --validation-mode NO_ISSUES_FOUND padded with blank lines" 0 --validation-mode "$F19"

# --- Case 20: --validation-mode short cited finding (50 words + file:line) passes (30-word floor) ---
F20="$TMPROOT/case20-validation-finding.txt"
make_words 40 "$F20"
echo 'See pkg/server/main.go:7 for the off-by-one.' >> "$F20"
run_case "case 20: --validation-mode short cited finding" 0 --validation-mode "$F20"

# --- Case 21: --validation-mode 10-word uncited finding fails (below 30-word floor) ---
F21="$TMPROOT/case21-validation-too-short.txt"
make_words 10 "$F21"
run_case "case 21: --validation-mode 10-word too-short" 2 --validation-mode "$F21"

# --- Case 22: --validation-mode 40-word uncited finding fails (no marker) ---
F22="$TMPROOT/case22-validation-uncited.txt"
make_words 40 "$F22"
run_case "case 22: --validation-mode 40-word uncited" 3 --validation-mode "$F22"

# --- Case 23: --validation-mode does NOT short-circuit on prose mentioning NO_ISSUES_FOUND inline ---
F23="$TMPROOT/case23-validation-mentions-token.txt"
make_words 40 "$F23"
echo 'The reviewer was instructed to emit NO_ISSUES_FOUND but instead reported these issues:' >> "$F23"
echo 'See pkg/server/main.go:7 for the off-by-one.' >> "$F23"
run_case "case 23: --validation-mode prose mentioning token + citation passes (full validator path, not short-circuit)" 0 --validation-mode "$F23"

# --- Case 24: --validation-mode + explicit --min-words override wins ---
F24="$TMPROOT/case24-validation-override.txt"
make_words 25 "$F24"
echo 'See pkg/server/main.go:7 for the off-by-one.' >> "$F24"
run_case "case 24: --validation-mode --min-words 50 (override beats preset's 30)" 2 --validation-mode --min-words 50 "$F24"

# === #447 cases — broadened extension list + trailing-boundary rule ===

# --- Case 25: broadened extension .tsx:42 passes ---
F25="$TMPROOT/case25-tsx.txt"
make_words 250 "$F25"
echo 'See app/components/Button.tsx:42 for the click handler.' >> "$F25"
run_case "case 25: .tsx:42 (broadened extension) passes" 0 "$F25"

# --- Case 26: broadened extension .vue:1 passes ---
F26="$TMPROOT/case26-vue.txt"
make_words 250 "$F26"
echo 'See src/App.vue:1 for the root component.' >> "$F26"
run_case "case 26: .vue:1 (broadened extension) passes" 0 "$F26"

# --- Case 27: broadened extension .rb:7 passes (covers r/rb/rs prefix family) ---
F27="$TMPROOT/case27-rb.txt"
make_words 250 "$F27"
echo 'See lib/parser.rb:7 for the tokenizer.' >> "$F27"
run_case "case 27: .rb:7 (covers r/rb/rs prefix family longest-first ordering)" 0 "$F27"

# --- Case 28: broadened extension .java:5 passes ---
F28="$TMPROOT/case28-java.txt"
make_words 250 "$F28"
echo 'See src/main/java/Foo.java:5 for the constructor.' >> "$F28"
run_case "case 28: .java:5 (broadened extension) passes" 0 "$F28"

# --- Case 29: broadened extension .css:10 passes (covers c/cs/css/csv prefix family) ---
F29="$TMPROOT/case29-css.txt"
make_words 250 "$F29"
echo 'See styles/main.css:10 for the layout rule.' >> "$F29"
run_case "case 29: .css:10 (covers c/cs/css/csv prefix family longest-first ordering)" 0 "$F29"

# --- Case 30: existing .json:1 still passes (covers js/json/jsx prefix family regression) ---
F30="$TMPROOT/case30-json.txt"
make_words 250 "$F30"
echo 'See package.json:1 for the manifest.' >> "$F30"
run_case "case 30: .json:1 still passes (js/json/jsx prefix family regression)" 0 "$F30"

# --- Case 31: fake-citation bypass file.mdjunk:42 → exit 3 (#447 defect (2) primary fix) ---
F31="$TMPROOT/case31-bypass-mdjunk.txt"
make_words 250 "$F31"
echo 'Reference: file.mdjunk:42 — fake-citation bypass attempt.' >> "$F31"
run_case "case 31: file.mdjunk:42 (fake-citation bypass) rejected" 3 "$F31"

# --- Case 32: bypass regression file.tsxfoo:1 → exit 3 (covers new-extension boundary) ---
F32="$TMPROOT/case32-bypass-tsxfoo.txt"
make_words 250 "$F32"
echo 'Reference: file.tsxfoo:1 — bypass regression on broadened extension.' >> "$F32"
run_case "case 32: file.tsxfoo:1 (broadened-extension bypass) rejected" 3 "$F32"

# --- Case 33: happy-path .md:42 still passes (no regression of existing case 1) ---
F33="$TMPROOT/case33-md-passes.txt"
make_words 250 "$F33"
echo 'See docs/notes.md:42 for the explanation.' >> "$F33"
run_case "case 33: .md:42 still passes (existing case 1 regression guard)" 0 "$F33"

# --- Case 34: prose-glued comma file.md, → exit 0 (boundary char is a real comma) ---
F34="$TMPROOT/case34-comma-glue.txt"
make_words 250 "$F34"
echo 'See docs/notes.md, then continue with the discussion below.' >> "$F34"
run_case "case 34: prose-glued comma file.md, passes (real-char boundary)" 0 "$F34"

# --- Case 35: compound-extension file.md.bak → exit 0 (substring match on .md; #447 boundary class allows `.`) ---
F35="$TMPROOT/case35-compound.txt"
make_words 250 "$F35"
echo 'Reference: see file.md.bak in the backup directory.' >> "$F35"
run_case "case 35: file.md.bak compound-extension accepted via .md substring (#447 boundary allows period)" 0 "$F35"

# --- Case 36: sentence-ending period See file.go. → exit 0 (#447 boundary class allows `.`) ---
F36="$TMPROOT/case36-sentence-period.txt"
make_words 250 "$F36"
echo 'Refer to scripts/foo.go.' >> "$F36"
run_case "case 36: sentence-ending period scripts/foo.go. accepted (#447 boundary allows period)" 0 "$F36"

# --- Case 37: bare-`:`-then-non-digits bypass file.md:garbage → exit 3 (#447 boundary excludes `:`) ---
F37="$TMPROOT/case37-bypass-colon-garbage.txt"
make_words 250 "$F37"
echo 'Reference: file.md:garbage — bare colon followed by non-digits, fake-citation bypass attempt.' >> "$F37"
run_case "case 37: file.md:garbage rejected (#447 boundary excludes colon so optional :line group must match digits)" 3 "$F37"

# --- Case 38: slash-suffix bypass file.md/child → exit 3 (#447 boundary excludes `/`) ---
F38="$TMPROOT/case38-bypass-slash.txt"
make_words 250 "$F38"
echo 'Reference: file.md/child — slash-suffix bypass attempt.' >> "$F38"
run_case "case 38: file.md/child rejected (#447 boundary excludes slash)" 3 "$F38"

# === #473 cases — short-extension strict-mode rule ===

# --- Case 39: verified repro: prose with `the spin.lock primitive` → exit 3 ---
F39="$TMPROOT/case39-spin-lock.txt"
make_words 250 "$F39"
echo 'In concurrency theory the spin.lock primitive is the simplest of all locking abstractions.' >> "$F39"
run_case "case 39: 'the spin.lock primitive' rejected (#473 verified repro)" 3 "$F39"

# --- Case 40: prose with `the my.env switch` → exit 3 ---
F40="$TMPROOT/case40-my-env.txt"
make_words 250 "$F40"
echo 'When deployed to production the my.env switch toggles between modes.' >> "$F40"
run_case "case 40: 'the my.env switch' rejected (#473 short-ext FP)" 3 "$F40"

# --- Case 41: prose with `the big.m optimization` → exit 3 ---
F41="$TMPROOT/case41-big-m.txt"
make_words 250 "$F41"
echo 'In linear programming the big.m optimization scales linearly with constraint count.' >> "$F41"
run_case "case 41: 'the big.m optimization' rejected (#473 short-ext FP)" 3 "$F41"

# --- Case 42: prose with `the foo.r constant` → exit 3 ---
F42="$TMPROOT/case42-foo-r.txt"
make_words 250 "$F42"
echo 'Throughout the derivation the foo.r constant remains positive.' >> "$F42"
run_case "case 42: 'the foo.r constant' rejected (#473 short-ext FP)" 3 "$F42"

# --- Case 43: prose with `the raw.txt format` → exit 3 ---
F43="$TMPROOT/case43-raw-txt.txt"
make_words 250 "$F43"
echo 'Conversion pipelines often store the raw.txt format unchanged through transit.' >> "$F43"
run_case "case 43: 'the raw.txt format' rejected (#473 short-ext FP)" 3 "$F43"

# --- Case 44: bare `Cargo.lock` in prose (no line-ref, no path) → exit 3 ---
F44="$TMPROOT/case44-bare-cargo-lock.txt"
make_words 250 "$F44"
echo 'Rust projects ship a Cargo.lock that pins dependency versions.' >> "$F44"
run_case "case 44: bare Cargo.lock in prose rejected (#473 forward-compat change)" 3 "$F44"

# --- Case 45: compound `Cargo.lock.bak` in prose → exit 3 (regression of pre-#473 behavior) ---
F45="$TMPROOT/case45-cargo-lock-bak.txt"
make_words 250 "$F45"
echo 'Some setups keep a backup file Cargo.lock.bak in the workspace root.' >> "$F45"
run_case "case 45: Cargo.lock.bak rejected (#473 short-ext compound, no path-likeness signal)" 3 "$F45"

# --- Case 46: `Cargo.lock:7` (line-ref qualifier) → exit 0 ---
F46="$TMPROOT/case46-cargo-lock-line.txt"
make_words 250 "$F46"
echo 'See Cargo.lock:7 for the locked openssl version.' >> "$F46"
run_case "case 46: Cargo.lock:7 accepted (#473 short-tier :line-ref signal)" 0 "$F46"

# --- Case 47: `app.env:5` (line-ref qualifier) → exit 0 ---
F47="$TMPROOT/case47-app-env-line.txt"
make_words 250 "$F47"
echo 'Reference: app.env:5 for the DATABASE_URL setting.' >> "$F47"
run_case "case 47: app.env:5 accepted (#473 short-tier :line-ref signal)" 0 "$F47"

# --- Case 48: `foo.m:42` (line-ref qualifier) → exit 0 ---
F48="$TMPROOT/case48-foo-m-line.txt"
make_words 250 "$F48"
echo 'In Objective-C see Classes/Foo.m:42 for the dealloc handler.' >> "$F48"
run_case "case 48: Foo.m:42 accepted (#473 short-tier :line-ref signal)" 0 "$F48"

# --- Case 49: `kernel/spin.lock` (slash qualifier, no line-ref) → exit 0 ---
F49="$TMPROOT/case49-kernel-spin-lock.txt"
make_words 250 "$F49"
echo 'The path kernel/spin.lock holds the in-tree lockfile.' >> "$F49"
run_case "case 49: kernel/spin.lock accepted (#473 short-tier / signal in stem)" 0 "$F49"

# --- Case 50: `parser_state.h` (underscore qualifier, no line-ref) → exit 0 ---
F50="$TMPROOT/case50-parser-state-h.txt"
make_words 250 "$F50"
echo 'Header parser_state.h declares the lexer state machine.' >> "$F50"
run_case "case 50: parser_state.h accepted (#473 short-tier _ signal in stem — snake_case)" 0 "$F50"

# --- Case 51: `kernel-mod.h` (dash qualifier, no line-ref) → exit 0 ---
F51="$TMPROOT/case51-kernel-mod-h.txt"
make_words 250 "$F51"
echo 'Header kernel-mod.h declares the loadable-module ABI.' >> "$F51"
run_case "case 51: kernel-mod.h accepted (#473 short-tier - signal in stem — kebab-case)" 0 "$F51"

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
exit 0
