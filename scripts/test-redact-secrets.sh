#!/usr/bin/env bash
# test-redact-secrets.sh — Regression test for the secret scrubber and its
# integration with skills/issue/scripts/create-one.sh.
#
# Three sections:
#   1. Unit: feed each covered pattern directly through redact-secrets.sh
#      and assert the placeholder appears and the raw token does not.
#   2. Idempotency: run a multi-pattern body through the helper twice;
#      assert the two outputs are byte-equal.
#   3. Integration (fake gh): drop a stub gh into PATH, invoke create-one.sh
#      against a body containing all six families, and assert:
#        - --dry-run path: DRY_RUN_TITLE and DRY_RUN_BODY_PREVIEW are
#          redacted.
#        - non-dry-run success path: body file passed to gh is redacted.
#        - non-dry-run failure path: ISSUE_ERROR is redacted when gh's
#          stderr contains token-like content.
#
# Usage:
#   bash scripts/test-redact-secrets.sh
#
# Exit codes:
#   0 — all assertions passed
#   1 — first failure (message to stderr)

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
HELPER="$REPO_ROOT/scripts/redact-secrets.sh"
CREATE_ONE="$REPO_ROOT/skills/issue/scripts/create-one.sh"

# Test fixture tokens. Chosen so the shape matches the helper regexes but
# the values are obviously synthetic (safe to appear in logs).
# Split prefix in source to defuse GitHub's sk-* secret-scanner heuristic.
SK_TOKEN='sk-''ant-abcdefghijklmnopqrstuvwxyz0123456789ABCD'
GHP_TOKEN='ghp_abcdefghijklmnopqrstuvwxyz0123456789ABCDEFGH'
AKIA_TOKEN='AKIAIOSFODNN7EXAMPLE'
XOXB_TOKEN='xoxb-FAKE-TEST-ONLY-NOT-A-REAL-SECRET'
JWT_TOKEN='eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIiwibmFtZSI6IkpvaG4gRG9lIn0.SflKxwRJSMeKKF2QT4fwpMeJf36POk6yJV_adQssw5c'
PEM_BLOCK='-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Qu
KUpRKfFLfRYC9AIKjbJTWit+CqvjWYzvQwECAwEAAQJAIJLixBy2qpFoS4DSmoEm
-----END RSA PRIVATE KEY-----'

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (contains $needle)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (missing $needle)")
        echo "  FAIL: $label (missing $needle)" >&2
        echo "       haystack (first 500 chars): ${haystack:0:500}" >&2
    fi
}

assert_not_contains() {
    local haystack="$1" needle="$2" label="$3"
    if [[ "$haystack" != *"$needle"* ]]; then
        PASS=$((PASS + 1))
        echo "  ok: $label (does not contain $needle)"
    else
        FAIL=$((FAIL + 1))
        FAILED_TESTS+=("$label (leaked $needle)")
        echo "  FAIL: $label (leaked $needle)" >&2
        echo "       haystack (first 500 chars): ${haystack:0:500}" >&2
    fi
}

echo "=== Section 1: Unit tests (direct helper) ==="

out=$(printf '%s' "$SK_TOKEN" | "$HELPER")
assert_contains "$out" '<REDACTED-TOKEN>' 'sk-ant key → placeholder'
assert_not_contains "$out" "$SK_TOKEN" 'sk-ant key → raw absent'

out=$(printf '%s' "$GHP_TOKEN" | "$HELPER")
assert_contains "$out" '<REDACTED-TOKEN>' 'ghp_ PAT → placeholder'
assert_not_contains "$out" "$GHP_TOKEN" 'ghp_ PAT → raw absent'

out=$(printf '%s' "$AKIA_TOKEN" | "$HELPER")
assert_contains "$out" '<REDACTED-TOKEN>' 'AKIA key → placeholder'
assert_not_contains "$out" "$AKIA_TOKEN" 'AKIA key → raw absent'

out=$(printf '%s' "$XOXB_TOKEN" | "$HELPER")
assert_contains "$out" '<REDACTED-TOKEN>' 'xoxb- token → placeholder'
assert_not_contains "$out" "$XOXB_TOKEN" 'xoxb- token → raw absent'

out=$(printf '%s' "$JWT_TOKEN" | "$HELPER")
assert_contains "$out" '<REDACTED-TOKEN>' 'JWT → placeholder'
assert_not_contains "$out" "$JWT_TOKEN" 'JWT → raw absent'

out=$(printf '%s\n' "$PEM_BLOCK" | "$HELPER")
assert_contains "$out" '<REDACTED-PRIVATE-KEY>' 'PEM block → placeholder'
assert_not_contains "$out" 'MIIBOgIBAAJB' 'PEM block → key material absent'
assert_not_contains "$out" 'BEGIN RSA PRIVATE KEY' 'PEM block → BEGIN marker absent'

echo ""
echo "=== Section 2: Idempotency ==="

multi_body="prefix $SK_TOKEN middle $GHP_TOKEN suffix"
pass1=$(printf '%s' "$multi_body" | "$HELPER")
pass2=$(printf '%s' "$pass1" | "$HELPER")
if [[ "$pass1" == "$pass2" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: idempotent (single vs double pass byte-equal)"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=('idempotency (single vs double pass differ)')
    echo "  FAIL: idempotency — pass1 != pass2" >&2
    echo "       pass1: $pass1" >&2
    echo "       pass2: $pass2" >&2
fi

echo ""
echo "=== Section 3: Integration (fake gh) ==="

TMPROOT=$(mktemp -d "${TMPDIR:-/tmp}/test-redact-XXXXXX")
trap 'rm -rf "$TMPROOT"' EXIT

# Build a body containing all six families.
BODY_FILE="$TMPROOT/body.txt"
cat > "$BODY_FILE" <<BODY_EOF
Line with $SK_TOKEN in prose.
Another line with $GHP_TOKEN PAT.
AWS key line: $AKIA_TOKEN here.
Slack: $XOXB_TOKEN here.
JWT: $JWT_TOKEN here.
$PEM_BLOCK
Trailing normal text.
BODY_EOF

# --- 3a: --dry-run path redaction ---
dry_title_raw="leaking ${SK_TOKEN} here"
dry_out=$(bash "$CREATE_ONE" --title "$dry_title_raw" --body-file "$BODY_FILE" --repo owner/repo --dry-run 2>&1)
assert_contains "$dry_out" '<REDACTED-TOKEN>' '[dry-run] preview/title contain placeholder'
assert_not_contains "$dry_out" "$SK_TOKEN" '[dry-run] sk-ant not echoed'
assert_not_contains "$dry_out" "$GHP_TOKEN" '[dry-run] ghp not echoed'
assert_not_contains "$dry_out" "$AKIA_TOKEN" '[dry-run] AKIA not echoed'
# DRY_RUN_TITLE line specifically must be redacted (not just DRY_RUN_BODY_PREVIEW).
dry_title_line=$(printf '%s\n' "$dry_out" | grep '^DRY_RUN_TITLE=' || true)
assert_contains "$dry_title_line" '<REDACTED-TOKEN>' '[dry-run] DRY_RUN_TITLE contains placeholder'

# --- 3b: non-dry-run success path — stub gh that records the body file ---
STUB_DIR="$TMPROOT/stub-success"
mkdir -p "$STUB_DIR"
BODY_CAPTURE="$TMPROOT/captured-body.txt"
cat > "$STUB_DIR/gh" <<'GHSTUB'
#!/usr/bin/env bash
# Capture --body-file content if present, emit a fake issue URL on stdout.
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--body-file" ]]; then
        next=$((i + 1))
        cp "${!next}" "$BODY_CAPTURE"
    fi
done
# label-list command path — emit nothing (no labels exist).
if [[ "$1" == "label" ]]; then
    exit 0
fi
# repo view path — emit a fake nameWithOwner JSON.
if [[ "$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# api path — handle the issue-id lookup used by the old-gh fallback in
# create-one.sh after issue #546. Returns the numeric id 4242 for issue #42.
if [[ "$1" == "api" ]]; then
    echo '4242'
    exit 0
fi
# issue create path — modern gh path uses --json id,number,url, so detect
# that flag and return JSON. Fall through to the legacy URL-on-stdout path
# when --json is absent (covers older test invocations and the fallback).
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--json" ]]; then
        echo '{"id":4242,"number":42,"url":"https://github.com/owner/repo/issues/42"}'
        exit 0
    fi
done
echo 'https://github.com/owner/repo/issues/42'
exit 0
GHSTUB
chmod +x "$STUB_DIR/gh"
# Export BODY_CAPTURE so the stub can see it.
export BODY_CAPTURE

success_out=$(PATH="$STUB_DIR:$PATH" bash "$CREATE_ONE" --title "$dry_title_raw" --body-file "$BODY_FILE" --repo owner/repo 2>&1)
assert_contains "$success_out" 'ISSUE_NUMBER=42' '[success] issue number emitted'
# ISSUE_TITLE line must have placeholder, not raw token.
success_title_line=$(printf '%s\n' "$success_out" | grep '^ISSUE_TITLE=' || true)
assert_contains "$success_title_line" '<REDACTED-TOKEN>' '[success] ISSUE_TITLE redacted'
assert_not_contains "$success_title_line" "$SK_TOKEN" '[success] ISSUE_TITLE does not leak sk-ant'

# Captured body file must have placeholders and no raw tokens.
if [[ -f "$BODY_CAPTURE" ]]; then
    captured=$(cat "$BODY_CAPTURE")
    assert_contains "$captured" '<REDACTED-TOKEN>' '[success] captured body has placeholder'
    assert_contains "$captured" '<REDACTED-PRIVATE-KEY>' '[success] captured body has PEM placeholder'
    assert_not_contains "$captured" "$SK_TOKEN" '[success] captured body does not leak sk-ant'
    assert_not_contains "$captured" "$GHP_TOKEN" '[success] captured body does not leak ghp'
    assert_not_contains "$captured" "$JWT_TOKEN" '[success] captured body does not leak JWT'
    assert_not_contains "$captured" 'MIIBOgIBAAJB' '[success] captured body does not leak PEM material'
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=('[success] captured body file missing')
    echo "  FAIL: captured body file missing at $BODY_CAPTURE" >&2
fi

# --- 3c: non-dry-run failure path — stub gh that emits token-bearing stderr ---
STUB_FAIL_DIR="$TMPROOT/stub-fail"
mkdir -p "$STUB_FAIL_DIR"
cat > "$STUB_FAIL_DIR/gh" <<GHFAIL
#!/usr/bin/env bash
if [[ "\$1" == "label" ]]; then
    exit 0
fi
if [[ "\$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# issue create path — write a token-bearing error to stderr and exit non-zero.
echo "API error: token $SK_TOKEN rejected" >&2
exit 1
GHFAIL
chmod +x "$STUB_FAIL_DIR/gh"

fail_out=$(PATH="$STUB_FAIL_DIR:$PATH" bash "$CREATE_ONE" --title 'plain-title' --body-file "$BODY_FILE" --repo owner/repo 2>&1 || true)
fail_err_line=$(printf '%s\n' "$fail_out" | grep '^ISSUE_ERROR=' || true)
assert_contains "$fail_err_line" '<REDACTED-TOKEN>' '[failure] ISSUE_ERROR has placeholder for stderr token'
assert_not_contains "$fail_err_line" "$SK_TOKEN" '[failure] ISSUE_ERROR does not leak stderr token'

# --- 3d: regression for #137 — gh exits 0 with URL on stdout AND noise on stderr ---
# Before the fix, ISSUE_URL=$(gh ... 2>&1) merged stderr into the variable used
# for URL extraction. A warning line on stderr could corrupt the regex match.
# Post-fix: stderr is captured to a temp file and ignored on the success path,
# so URL parsing still succeeds.
STUB_NOISE_DIR="$TMPROOT/stub-success-with-stderr"
mkdir -p "$STUB_NOISE_DIR"
cat > "$STUB_NOISE_DIR/gh" <<'GHNOISE'
#!/usr/bin/env bash
if [[ "$1" == "label" ]]; then
    exit 0
fi
if [[ "$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# api path — handle issue-id lookup from create-one.sh's old-gh fallback.
if [[ "$1" == "api" ]]; then
    echo '13737'
    exit 0
fi
# issue create path — modern path returns JSON when --json is requested.
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--json" ]]; then
        echo 'warning: experimental feature enabled' >&2
        echo '{"id":13737,"number":137,"url":"https://github.com/owner/repo/issues/137"}'
        exit 0
    fi
done
# Legacy / fallback path — emit warning on stderr and URL on stdout.
echo 'warning: experimental feature enabled' >&2
echo 'https://github.com/owner/repo/issues/137'
exit 0
GHNOISE
chmod +x "$STUB_NOISE_DIR/gh"
noise_out=$(PATH="$STUB_NOISE_DIR:$PATH" bash "$CREATE_ONE" --title 'plain-title' --body-file "$BODY_FILE" --repo owner/repo 2>&1 || true)
assert_contains "$noise_out" 'ISSUE_NUMBER=137' '[#137] URL parsed from stdout despite stderr noise'
assert_contains "$noise_out" 'ISSUE_URL=https://github.com/owner/repo/issues/137' '[#137] ISSUE_URL exact match, no stderr contamination'
assert_not_contains "$noise_out" 'warning: experimental feature enabled' '[#137] stderr noise not echoed via ISSUE_URL/ISSUE_NUMBER'

echo ""
echo "=== Section 4: Edge cases ==="

# --- 4a: indented / blockquoted PEM blocks (F4) ---
# Blockquote-prefixed PEM block (common in markdown issue bodies).
INDENTED_BODY="prefix line
> -----BEGIN RSA PRIVATE KEY-----
> MIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Q
> -----END RSA PRIVATE KEY-----
    -----BEGIN OPENSSH PRIVATE KEY-----
    b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAABlwAAAA
    -----END OPENSSH PRIVATE KEY-----
suffix line"
indented_out=$(printf '%s' "$INDENTED_BODY" | "$HELPER")
assert_contains "$indented_out" '<REDACTED-PRIVATE-KEY>' '[edge] blockquote PEM → placeholder'
assert_not_contains "$indented_out" 'MIIBOgIBAAJB' '[edge] blockquote PEM → RSA key material absent'
assert_not_contains "$indented_out" 'b3BlbnNzaC1rZXktdjEA' '[edge] indented PEM → OPENSSH key material absent'
assert_contains "$indented_out" 'prefix line' '[edge] non-PEM prefix passes through'
assert_contains "$indented_out" 'suffix line' '[edge] non-PEM suffix passes through'

# --- 4b: unterminated PEM block (F3) ---
UNTERMINATED_BODY="opening text
-----BEGIN RSA PRIVATE KEY-----
MIIBOgIBAAJBAKj34GkxFhD90vcNLYLInFEX6Ppy1tPf9Cnzj4p4WGeKLs1Pt8Q
KUpRKfFLfRYC9AIKjbJTWit+CqvjWYzvQwECAwEAAQJAIJLixBy2qpFoS4DSmoEm
tail-that-should-not-silently-survive"
unterm_out=$(printf '%s\n' "$UNTERMINATED_BODY" | "$HELPER" 2>/dev/null)
assert_contains "$unterm_out" '<REDACTED-PRIVATE-KEY>' '[edge] unterminated PEM → placeholder'
assert_contains "$unterm_out" 'opening text' '[edge] unterminated PEM → pre-BEGIN text preserved'
assert_not_contains "$unterm_out" 'MIIBOgIBAAJB' '[edge] unterminated PEM → key material absent'
assert_contains "$unterm_out" 'content truncated' '[edge] unterminated PEM → truncation marker emitted'
# The malicious or malformed tail must NOT survive.
assert_not_contains "$unterm_out" 'tail-that-should-not-silently-survive' '[edge] unterminated PEM → tail dropped'

# --- 4c: redact helper missing (F1) — fail-closed with ISSUE_FAILED/ERROR on stdout ---
MISSING_DIR="$TMPROOT/stub-missing-helper"
mkdir -p "$MISSING_DIR"
# Create a broken helper wrapper by using a PATH with a sh-breaking placeholder.
# Simpler: move the real helper out of reach by running create-one.sh with a
# bogus SCRIPT_DIR layout. Since create-one.sh resolves REPO_ROOT via
# BASH_SOURCE, we copy create-one.sh to a sibling tree without redact-secrets.sh.
FAKE_TREE="$TMPROOT/fake-tree"
mkdir -p "$FAKE_TREE/skills/issue/scripts" "$FAKE_TREE/scripts"
cp "$CREATE_ONE" "$FAKE_TREE/skills/issue/scripts/create-one.sh"
# Intentionally do NOT create $FAKE_TREE/scripts/redact-secrets.sh.
chmod +x "$FAKE_TREE/skills/issue/scripts/create-one.sh"
missing_out=$(bash "$FAKE_TREE/skills/issue/scripts/create-one.sh" --title 'a-title' --body-file "$BODY_FILE" --repo owner/repo --dry-run 2>&1 || true)
assert_contains "$missing_out" 'ISSUE_FAILED=true' '[edge] missing helper → ISSUE_FAILED=true on stdout'
assert_contains "$missing_out" 'ISSUE_ERROR=redaction:' '[edge] missing helper → ISSUE_ERROR=redaction: prefix on stdout'

# --- 4d: gh emits zero-URL multi-line output (F5) — no-URL branch flattens ---
ZERO_URL_DIR="$TMPROOT/stub-zero-url"
mkdir -p "$ZERO_URL_DIR"
cat > "$ZERO_URL_DIR/gh" <<GHZERO
#!/usr/bin/env bash
if [[ "\$1" == "label" ]]; then
    exit 0
fi
if [[ "\$1" == "repo" ]]; then
    echo 'owner/repo'
    exit 0
fi
# issue create path — emit multi-line output with no URL, exit 0.
printf 'line one\nline two with ${SK_TOKEN:0:35}\nline three\n'
exit 0
GHZERO
chmod +x "$ZERO_URL_DIR/gh"
zero_out=$(PATH="$ZERO_URL_DIR:$PATH" bash "$CREATE_ONE" --title 'plain-title' --body-file "$BODY_FILE" --repo owner/repo 2>&1 || true)
# Must emit a single-line ISSUE_ERROR (no raw newlines).
zero_err_lines=$(printf '%s\n' "$zero_out" | grep -c '^ISSUE_ERROR=' || true)
if [[ "$zero_err_lines" == "1" ]]; then
    PASS=$((PASS + 1))
    echo "  ok: [edge] no-URL branch emits single-line ISSUE_ERROR (count=$zero_err_lines)"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("[edge] no-URL branch emitted $zero_err_lines ISSUE_ERROR lines (expected 1)")
    echo "  FAIL: [edge] no-URL branch emits single-line ISSUE_ERROR (count=$zero_err_lines)" >&2
    echo "       zero_out: $zero_out" >&2
fi
zero_err_line=$(printf '%s\n' "$zero_out" | grep '^ISSUE_ERROR=' || true)
assert_contains "$zero_err_line" '<REDACTED-TOKEN>' '[edge] no-URL branch redacts stderr token'
assert_not_contains "$zero_err_line" "${SK_TOKEN:0:35}" '[edge] no-URL branch does not leak sk-ant'

# --- 4e: label-existence probe with regex metacharacters (closes #775) ---
# Pre-fix: `grep -qx -- "$L"` interprets $L as BRE. A label `bug.feature`
# would match a sibling label like `bug-feature` because BRE `.` matches any
# single character → silent false-positive accept. Post-fix: `grep -Fqx --`
# is byte-exact whole-line match. The fake gh emits a label list containing
# `bug-feature` (no dot), and create-one.sh is invoked with `--label
# bug.feature` (with dot). The probe must REJECT `bug.feature` (it does NOT
# exist as an exact label name) and emit the standard WARN line.
LABEL_DIR="$TMPROOT/stub-label-metachar"
mkdir -p "$LABEL_DIR"
cat > "$LABEL_DIR/gh" <<'GHLABEL'
#!/usr/bin/env bash
# label list --search <X> --json name --jq '.[].name' path: emit one-name-per-line.
# When --search is "bug.feature" or "release[2026]", emit a sibling whose only
# difference is in regex-meaningful characters (so BRE would match but
# fixed-string must not).
if [[ "$1" == "label" ]] && [[ "$2" == "list" ]]; then
    # Find the --search value.
    search=""
    for ((i=1; i<=$#; i++)); do
        if [[ "${!i}" == "--search" ]]; then
            j=$((i + 1))
            search="${!j}"
            break
        fi
    done
    case "$search" in
        bug.feature)
            # Emit a label whose name has `-` where the search has `.`.
            # BRE `bug.feature` would match `bug-feature` (`.` = any char);
            # fixed-string must reject.
            printf 'bug-feature\nfoo\n'
            ;;
        release\[2026\])
            # Emit `release2` and `release6`. BRE `release[2026]` is a
            # character class matching ANY single char in {2,0,2,6}; would
            # match `release2`. Fixed-string must reject.
            printf 'release2\nrelease6\n'
            ;;
        *)
            # Default: empty (label does not exist).
            ;;
    esac
    exit 0
fi
if [[ "$1" == "repo" ]]; then echo 'owner/repo'; exit 0; fi
if [[ "$1" == "api" ]]; then echo '4242'; exit 0; fi
# issue create path: emit modern JSON.
for ((i=1; i<=$#; i++)); do
    if [[ "${!i}" == "--json" ]]; then
        echo '{"id":4242,"number":42,"url":"https://github.com/owner/repo/issues/42"}'
        exit 0
    fi
done
echo 'https://github.com/owner/repo/issues/42'
exit 0
GHLABEL
chmod +x "$LABEL_DIR/gh"

# Sub-case 1: `bug.feature` against `bug-feature` sibling.
label_out_1=$(PATH="$LABEL_DIR:$PATH" bash "$CREATE_ONE" --title 'plain-title' --body-file "$BODY_FILE" --repo owner/repo --label 'bug.feature' --dry-run 2>&1 || true)
if printf '%s\n' "$label_out_1" | grep -q "WARN: label 'bug.feature' does not exist"; then
    PASS=$((PASS + 1))
    echo "  ok: [label-metachar] bug.feature correctly rejected (no BRE false-match against bug-feature)"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("[label-metachar] bug.feature should produce WARN: does not exist")
    echo "  FAIL: [label-metachar] bug.feature against bug-feature sibling" >&2
    echo "       label_out: $label_out_1" >&2
fi

# Sub-case 2: `release[2026]` against `release2`/`release6` siblings.
label_out_2=$(PATH="$LABEL_DIR:$PATH" bash "$CREATE_ONE" --title 'plain-title' --body-file "$BODY_FILE" --repo owner/repo --label 'release[2026]' --dry-run 2>&1 || true)
if printf '%s\n' "$label_out_2" | grep -qF "WARN: label 'release[2026]' does not exist"; then
    PASS=$((PASS + 1))
    echo "  ok: [label-metachar] release[2026] correctly rejected (no BRE class false-match against release2/release6)"
else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("[label-metachar] release[2026] should produce WARN: does not exist")
    echo "  FAIL: [label-metachar] release[2026] against release2/release6 siblings" >&2
    echo "       label_out: $label_out_2" >&2
fi

echo ""
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ $FAIL -gt 0 ]]; then
    echo "Failed tests:" >&2
    for t in "${FAILED_TESTS[@]}"; do
        echo "  - $t" >&2
    done
    exit 1
fi
echo "All assertions passed."
exit 0
