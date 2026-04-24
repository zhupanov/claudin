#!/usr/bin/env bash
# test-tracking-issue-write.sh — regression harness for tracking-issue-write.sh.
#
# Mirrors the stub-gh + PATH-override pattern of scripts/test-redact-secrets.sh.
# Seven assertion categories (a-g) covering redaction, exit codes, truncation,
# anchor-skeleton preservation, anchor-upsert semantics, and gh-failure
# redaction. All assertions run in a hermetic mktemp -d tmproot with a
# stub gh binary on PATH.
#
# Usage:
#   bash scripts/test-tracking-issue-write.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — any assertion failed (summary at EOF)
#
# Conventions: Bash 3.2-safe.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
WRITE="$REPO_ROOT/scripts/tracking-issue-write.sh"

if [[ ! -x "$WRITE" ]]; then
    echo "FAIL: $WRITE not found or not executable" >&2
    exit 1
fi

# Fixture: split prefix in source to defuse GitHub's sk-* secret-scanner heuristic.
SK_TOKEN='sk-''ant-abcdefghijklmnopqrstuvwxyz0123456789ABCD'

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing needle: $needle)")
        echo "  FAIL: $label (missing $needle)" >&2
        echo "       haystack (first 500): ${haystack:0:500}" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (leaked: $needle)")
        echo "  FAIL: $label (leaked $needle)" >&2
        echo "       haystack (first 500): ${haystack:0:500}" >&2
    fi
}

assert_equal() {
    local actual="$1" expected="$2" label="$3"
    if [[ "$actual" == "$expected" ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (expected '$expected', got '$actual')")
        echo "  FAIL: $label (expected '$expected', got '$actual')" >&2
    fi
}

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-tracking-issue-write-XXXXXX")
# shellcheck disable=SC2317
trap 'rm -rf "$TMPROOT"' EXIT

# ---------------------------------------------------------------------------
# Helper: build a stub gh directory for a given scenario. Each scenario is
# a subdirectory under $TMPROOT/stub-<tag>, with its own gh script and
# capture files. Usage: stub_dir=$(build_stub <tag> <success|multi-anchor|token-stderr|zero-anchors>)
# ---------------------------------------------------------------------------

build_stub_success() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Stub gh: capture --body-file content; emit fake URLs on stdout.
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--body-file" ]]; then
        next=$((i + 1))
        cp "${!next}" "$BODY_CAPTURE"
    fi
    if [[ "${!i}" == "--input" ]]; then
        next=$((i + 1))
        # Extract the body field from the JSON input and write that to
        # $BODY_CAPTURE so the assertion framework sees the post-redact
        # post-truncate body content, not the JSON wrapper.
        jq -r '.body' < "${!next}" > "$BODY_CAPTURE" 2>/dev/null || cp "${!next}" "$BODY_CAPTURE"
    fi
done
# repo view
if [[ "$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# issue create
if [[ "$1" == "issue" ]] && [[ "$2" == "create" ]]; then
    echo 'https://github.com/owner/repo/issues/42'
    exit 0
fi
# issue comment
if [[ "$1" == "issue" ]] && [[ "$2" == "comment" ]]; then
    echo 'https://github.com/owner/repo/issues/42#issuecomment-7001'
    exit 0
fi
# api — default: empty list (no existing anchors); PATCH: return JSON with html_url.
if [[ "$1" == "api" ]]; then
    # Detect PATCH by looking for -X PATCH.
    is_patch=0
    for arg in "$@"; do
        if [[ "$arg" == "PATCH" ]]; then
            is_patch=1
            break
        fi
    done
    if (( is_patch )); then
        echo '{"id":7001,"html_url":"https://github.com/owner/repo/issues/42#issuecomment-7001"}'
        exit 0
    fi
    # GET /comments — return empty list by default.
    exit 0
fi
exit 0
GHSTUB
    chmod +x "$stub_dir/gh"
}

build_stub_one_anchor() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'GHSTUB'
#!/usr/bin/env bash
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--body-file" ]]; then
        next=$((i + 1))
        cp "${!next}" "$BODY_CAPTURE"
    fi
    if [[ "${!i}" == "--input" ]]; then
        next=$((i + 1))
        # Extract the body field from the JSON input and write that to
        # $BODY_CAPTURE so the assertion framework sees the post-redact
        # post-truncate body content, not the JSON wrapper.
        jq -r '.body' < "${!next}" > "$BODY_CAPTURE" 2>/dev/null || cp "${!next}" "$BODY_CAPTURE"
    fi
done
if [[ "$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
if [[ "$1" == "api" ]]; then
    is_patch=0
    for arg in "$@"; do
        [[ "$arg" == "PATCH" ]] && is_patch=1
    done
    if (( is_patch )); then
        echo '{"id":5001,"html_url":"https://github.com/owner/repo/issues/42#issuecomment-5001"}'
        exit 0
    fi
    # GET comments — return one anchor-prefixed line.
    printf '%s\t%s\n' "5001" '<!-- larch:implement-anchor v1 issue=42 -->'
    exit 0
fi
if [[ "$1" == "issue" ]] && [[ "$2" == "comment" ]]; then
    echo 'https://github.com/owner/repo/issues/42#issuecomment-9001'
    exit 0
fi
exit 0
GHSTUB
    chmod +x "$stub_dir/gh"
}

build_stub_multi_anchor() {
    local stub_dir="$1"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<'GHSTUB'
#!/usr/bin/env bash
if [[ "$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
if [[ "$1" == "api" ]]; then
    # GET comments — return TWO anchor-prefixed lines.
    printf '%s\t%s\n' "5001" '<!-- larch:implement-anchor v1 issue=42 -->'
    printf '%s\t%s\n' "5002" '<!-- larch:implement-anchor v1 issue=42 -->'
    exit 0
fi
exit 0
GHSTUB
    chmod +x "$stub_dir/gh"
}

build_stub_token_stderr() {
    local stub_dir="$1"
    local token="$2"
    mkdir -p "$stub_dir"
    cat > "$stub_dir/gh" <<GHSTUB
#!/usr/bin/env bash
if [[ "\$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# Any other path — emit token on stderr, fail.
echo "API error: token $token rejected" >&2
exit 1
GHSTUB
    chmod +x "$stub_dir/gh"
}

echo "=== (a) create-issue redacts title+body ==="
STUB_A="$TMPROOT/stub-a"
BODY_CAPTURE="$TMPROOT/capture-a.txt"
build_stub_success "$STUB_A"
export BODY_CAPTURE
BODY_A="$TMPROOT/body-a.txt"
printf 'Body containing %s secret\n' "$SK_TOKEN" > "$BODY_A"
out_a=$(PATH="$STUB_A:$PATH" bash "$WRITE" create-issue --title "leaking $SK_TOKEN title" --body-file "$BODY_A" --repo owner/repo 2>&1)
assert_contains "$out_a" 'ISSUE_NUMBER=42' '(a) ISSUE_NUMBER emitted'
# Body capture should have redacted token.
if [[ -f "$BODY_CAPTURE" ]]; then
    captured=$(cat "$BODY_CAPTURE")
    assert_contains "$captured" '<REDACTED-TOKEN>' '(a) body captured contains <REDACTED-TOKEN>'
    assert_not_contains "$captured" "$SK_TOKEN" '(a) body captured does NOT leak sk-ant'
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(a) body capture file missing")
    echo "  FAIL: (a) body capture file missing" >&2
fi
# Title redaction is applied internally; it doesn't leak into stdout on success.
# But the title is passed to gh which is stubbed — we'd need to capture argv.
# Minimum assertion: the stdout ISSUE contract doesn't leak the token.
assert_not_contains "$out_a" "$SK_TOKEN" '(a) stdout does not leak sk-ant'

echo ""
echo "=== (b) create-issue exit 3 with FAILED/ERROR=redaction when redactor missing ==="
# Create a fake tree without scripts/redact-secrets.sh to trigger redaction failure.
# Phase 5 (umbrella #348): tracking-issue-write.sh now sources
# scripts/anchor-section-markers.sh; copy it so startup succeeds and the
# test reaches the redaction-failure path under exercise.
FAKE_TREE="$TMPROOT/fake-tree"
mkdir -p "$FAKE_TREE/scripts"
cp "$WRITE" "$FAKE_TREE/scripts/tracking-issue-write.sh"
cp "$REPO_ROOT/scripts/anchor-section-markers.sh" "$FAKE_TREE/scripts/anchor-section-markers.sh"
chmod +x "$FAKE_TREE/scripts/tracking-issue-write.sh"
# Intentionally do NOT create $FAKE_TREE/scripts/redact-secrets.sh.
BODY_B="$TMPROOT/body-b.txt"
printf 'body content\n' > "$BODY_B"
out_b=$(PATH="$STUB_A:$PATH" bash "$FAKE_TREE/scripts/tracking-issue-write.sh" create-issue --title 'plain-title' --body-file "$BODY_B" --repo owner/repo 2>&1 || true)
assert_contains "$out_b" 'FAILED=true' '(b) missing redactor → FAILED=true on stdout'
assert_contains "$out_b" 'ERROR=redaction:' '(b) missing redactor → ERROR=redaction: prefix'
assert_not_contains "$out_b" 'ISSUE_FAILED=true' '(b) does NOT use ISSUE_FAILED namespace'
# Pin exact key literal FAILED= (not ISSUE_FAILED=).
if [[ "$out_b" =~ ^FAILED=true$ ]] || [[ "$out_b" == *$'\n'FAILED=true$'\n'* ]] || [[ "$out_b" == *$'\n'FAILED=true ]] || [[ "$out_b" == FAILED=true* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: (b) exact 'FAILED=true' key literal present"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(b) exact 'FAILED=true' literal missing")
    echo "  FAIL: (b) exact FAILED=true literal not found" >&2
fi

echo ""
echo "=== (c) upsert-anchor preserves anchor + all 8 section markers after >60k body collapse ==="
STUB_C="$TMPROOT/stub-c"
BODY_CAPTURE="$TMPROOT/capture-c.txt"
build_stub_one_anchor "$STUB_C"
export BODY_CAPTURE
BODY_C="$TMPROOT/body-c.txt"
# Compose body: anchor marker line + 8 sections, each with 10000+ chars of content
# so the per-section cap fires first; then ensure body still exceeds 60000.
{
    echo '<!-- larch:implement-anchor v1 issue=42 -->'
    for slug in plan-goals-test plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics; do
        printf '<!-- section:%s -->\n' "$slug"
        # 10000 chars of content per section (well over 8000 cap).
        # Use a chunk-repeat pattern that is stable for Bash 3.2.
        for _ in $(seq 1 100); do
            printf 'This is 100 characters of section content to exceed the per-section cap and trigger body-level collapse of some sections.\n'
        done
        printf '<!-- section-end:%s -->\n' "$slug"
    done
} > "$BODY_C"
out_c=$(PATH="$STUB_C:$PATH" bash "$WRITE" upsert-anchor --issue 42 --body-file "$BODY_C" --repo owner/repo 2>&1)
assert_contains "$out_c" 'ANCHOR_COMMENT_ID=5001' '(c) PATCH hit existing anchor (id=5001)'
assert_contains "$out_c" 'UPDATED=true' '(c) UPDATED=true'
if [[ -f "$BODY_CAPTURE" ]]; then
    captured_c=$(cat "$BODY_CAPTURE")
    assert_contains "$captured_c" '<!-- larch:implement-anchor v1 issue=42 -->' '(c) HTML anchor marker preserved'
    for slug in plan-goals-test plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics; do
        assert_contains "$captured_c" "<!-- section:${slug} -->" "(c) section:${slug} marker preserved"
        assert_contains "$captured_c" "<!-- section-end:${slug} -->" "(c) section-end:${slug} marker preserved"
    done
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(c) body capture missing")
    echo "  FAIL: (c) body capture file missing" >&2
fi

echo ""
echo "=== (d) upsert-anchor per-section 8000 cap inserts inline TRUNCATED marker on own line ==="
STUB_D="$TMPROOT/stub-d"
BODY_CAPTURE="$TMPROOT/capture-d.txt"
build_stub_one_anchor "$STUB_D"
export BODY_CAPTURE
BODY_D="$TMPROOT/body-d.txt"
# Single section with >8000 interior chars; total body well under 60000.
{
    echo '<!-- larch:implement-anchor v1 issue=42 -->'
    echo '<!-- section:plan-goals-test -->'
    for _ in $(seq 1 85); do
        printf 'Line of 100 characters exactly to ensure the section overflows the per-section cap with line-boundaries.\n'
    done
    echo '<!-- section-end:plan-goals-test -->'
} > "$BODY_D"
out_d=$(PATH="$STUB_D:$PATH" bash "$WRITE" upsert-anchor --issue 42 --body-file "$BODY_D" --repo owner/repo 2>&1)
assert_contains "$out_d" 'UPDATED=true' '(d) PATCH succeeded'
if [[ -f "$BODY_CAPTURE" ]]; then
    captured_d=$(cat "$BODY_CAPTURE")
    assert_contains "$captured_d" "[TRUNCATED — plan-goals-test exceeded 8000 chars]" '(d) per-section TRUNCATED marker present'
    # Assert marker begins on its own line (line-boundary snap).
    if grep -qE '^\[TRUNCATED — plan-goals-test exceeded 8000 chars\]$' "$BODY_CAPTURE"; then
        PASS=$((PASS + 1))
        echo "  ok: (d) TRUNCATED marker on its own line"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("(d) TRUNCATED marker not on own line")
        echo "  FAIL: (d) TRUNCATED marker not on own line" >&2
    fi
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(d) body capture missing")
fi

echo ""
echo "=== (e) append-comment does NOT touch anchor ==="
STUB_E="$TMPROOT/stub-e"
BODY_CAPTURE="$TMPROOT/capture-e.txt"
build_stub_success "$STUB_E"
export BODY_CAPTURE
BODY_E="$TMPROOT/body-e.txt"
printf 'plain append comment body\n' > "$BODY_E"
out_e=$(PATH="$STUB_E:$PATH" bash "$WRITE" append-comment --issue 42 --body-file "$BODY_E" --repo owner/repo 2>&1)
assert_contains "$out_e" 'COMMENT_ID=7001' '(e) append-comment emits COMMENT_ID'
assert_not_contains "$out_e" 'ANCHOR_COMMENT_ID' '(e) stdout does not mention ANCHOR_COMMENT_ID'
if [[ -f "$BODY_CAPTURE" ]]; then
    captured_e=$(cat "$BODY_CAPTURE")
    assert_not_contains "$captured_e" '<!-- larch:implement-anchor' '(e) posted body does not contain anchor marker'
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(e) body capture missing")
fi

echo ""
echo "=== (f1) upsert-anchor with exactly one existing anchor → PATCH, UPDATED=true ==="
# Already covered by (c) which tests PATCH against one existing anchor.
# Additional assertion: UPDATED=true is surfaced in output AND no new comment
# is created. Since build_stub_one_anchor returns one line from list_anchor_comments,
# the upsert path goes through PATCH (not create). We already validated UPDATED=true
# in (c). Re-assert explicitly here with minimal body.
STUB_F1="$TMPROOT/stub-f1"
BODY_CAPTURE="$TMPROOT/capture-f1.txt"
build_stub_one_anchor "$STUB_F1"
export BODY_CAPTURE
BODY_F1="$TMPROOT/body-f1.txt"
printf '<!-- larch:implement-anchor v1 issue=42 -->\nbody content\n' > "$BODY_F1"
out_f1=$(PATH="$STUB_F1:$PATH" bash "$WRITE" upsert-anchor --issue 42 --body-file "$BODY_F1" --repo owner/repo 2>&1)
assert_contains "$out_f1" 'ANCHOR_COMMENT_ID=5001' '(f1) PATCHed anchor id=5001 (not a new comment)'
assert_contains "$out_f1" 'UPDATED=true' '(f1) UPDATED=true'

echo ""
echo "=== (f2) upsert-anchor with 2+ existing anchors → exit 2, FAILED=true multiple anchor comments ==="
STUB_F2="$TMPROOT/stub-f2"
build_stub_multi_anchor "$STUB_F2"
BODY_F2="$TMPROOT/body-f2.txt"
printf '<!-- larch:implement-anchor v1 issue=42 -->\nbody\n' > "$BODY_F2"
exit_f2=0
out_f2=$(PATH="$STUB_F2:$PATH" bash "$WRITE" upsert-anchor --issue 42 --body-file "$BODY_F2" --repo owner/repo 2>&1) || exit_f2=$?
assert_equal "$exit_f2" "2" '(f2) exit code is 2'
assert_contains "$out_f2" 'FAILED=true' '(f2) FAILED=true on stdout'
assert_contains "$out_f2" 'multiple anchor comments found' '(f2) ERROR mentions multiple anchor comments'
assert_contains "$out_f2" 'ids: 5001,5002' '(f2) ERROR includes comma-separated ids'

echo ""
echo "=== (g) gh-failure redaction: token-bearing stderr → REDACTED in ERROR ==="
STUB_G="$TMPROOT/stub-g"
build_stub_token_stderr "$STUB_G" "$SK_TOKEN"
BODY_G="$TMPROOT/body-g.txt"
printf 'body content\n' > "$BODY_G"
exit_g=0
out_g=$(PATH="$STUB_G:$PATH" bash "$WRITE" create-issue --title 'plain-title' --body-file "$BODY_G" --repo owner/repo 2>&1) || exit_g=$?
assert_equal "$exit_g" "2" '(g) exit code is 2 (gh failure)'
assert_contains "$out_g" 'FAILED=true' '(g) FAILED=true on gh failure'
# Extract the ERROR= line.
err_line=$(printf '%s\n' "$out_g" | grep '^ERROR=' || true)
assert_contains "$err_line" '<REDACTED-TOKEN>' '(g) ERROR contains <REDACTED-TOKEN>'
assert_not_contains "$err_line" "$SK_TOKEN" '(g) ERROR does NOT leak raw sk-ant'

echo ""
echo "=== (h) tracking-issue-write.sh missing anchor-section-markers.sh helper → exit 1, FAILED=true ==="
# Phase 5 (umbrella #348): the script sources scripts/anchor-section-markers.sh
# at startup and fails closed if the helper is missing, so the stdout
# FAILED=true / ERROR= contract is preserved for the hermetic-fake-tree case.
FAKE_TREE_H="$TMPROOT/fake-tree-no-markers"
mkdir -p "$FAKE_TREE_H/scripts"
cp "$WRITE" "$FAKE_TREE_H/scripts/tracking-issue-write.sh"
cp "$REPO_ROOT/scripts/redact-secrets.sh" "$FAKE_TREE_H/scripts/redact-secrets.sh"
chmod +x "$FAKE_TREE_H/scripts/tracking-issue-write.sh" "$FAKE_TREE_H/scripts/redact-secrets.sh"
# Intentionally do NOT copy anchor-section-markers.sh.
BODY_H="$TMPROOT/body-h.txt"
printf 'body content\n' > "$BODY_H"
exit_h=0
out_h=$(bash "$FAKE_TREE_H/scripts/tracking-issue-write.sh" create-issue --title 'plain-title' --body-file "$BODY_H" --repo owner/repo 2>&1) || exit_h=$?
assert_equal "$exit_h" "1" '(h) exit code is 1 when anchor-section-markers.sh is missing'
assert_contains "$out_h" 'FAILED=true' '(h) FAILED=true on stdout'
assert_contains "$out_h" 'missing helper' '(h) ERROR mentions missing helper'
assert_contains "$out_h" 'anchor-section-markers.sh' '(h) ERROR names the missing helper file'

echo ""
echo "=== (i) SECTION_MARKERS ⊆ COLLAPSE_PRIORITY invariant (set-membership) ==="
# Every SECTION_MARKERS slug must appear in COLLAPSE_PRIORITY so the
# body-level truncation pass can find each section as a collapse target.
# A future edit that adds a slug to SECTION_MARKERS without updating
# COLLAPSE_PRIORITY would break the truncation algorithm silently.
# Source both arrays in a subshell to probe the invariant.
invariant_out=$(bash -c "
    set -euo pipefail
    source '$REPO_ROOT/scripts/anchor-section-markers.sh'
    # COLLAPSE_PRIORITY lives inline in tracking-issue-write.sh; grep it out.
    cp_line=\$(grep -E '^COLLAPSE_PRIORITY=\\(' '$WRITE' | head -n 1)
    if [ -z \"\$cp_line\" ]; then
        echo 'ERROR=COLLAPSE_PRIORITY= declaration not found in tracking-issue-write.sh'
        exit 1
    fi
    # shellcheck disable=SC2294
    eval \"\$cp_line\"
    missing=()
    for slug in \"\${SECTION_MARKERS[@]}\"; do
        found=0
        for cp in \"\${COLLAPSE_PRIORITY[@]}\"; do
            if [ \"\$cp\" = \"\$slug\" ]; then
                found=1
                break
            fi
        done
        if [ \"\$found\" = 0 ]; then
            missing+=(\"\$slug\")
        fi
    done
    if [ \${#missing[@]} -gt 0 ]; then
        echo \"ERROR=SECTION_MARKERS slugs missing from COLLAPSE_PRIORITY: \${missing[*]}\"
        exit 1
    fi
    echo 'OK=invariant holds'
" 2>&1) || true
if [[ "$invariant_out" == OK=* ]]; then
    PASS=$((PASS + 1))
    echo "  ok: (i) SECTION_MARKERS ⊆ COLLAPSE_PRIORITY"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("(i) SECTION_MARKERS ⊆ COLLAPSE_PRIORITY invariant")
    echo "  FAIL: (i) $invariant_out" >&2
fi

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if (( FAIL > 0 )); then
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
exit 0
