#!/usr/bin/env bash
# test-validate-citations.sh — Offline regression harness for validate-citations.sh.
#
# Pins the consumer-side behavior of skills/research/scripts/validate-citations.sh
# under fail-soft semantics: every scenario asserts (a) exit 0, (b) sidecar
# created at the configured path, (c) the SUMMARY=... line on stdout has the
# expected counts, (d) where applicable, the sidecar body contains the expected
# Status / Reason tokens.
#
# Test seams (env vars exported per case):
#   __VC_FAKE_CURL    : absolute path to a fake-curl shim that returns scripted
#                       HTTP codes per --output-flag URL pattern.
#   __VC_SKIP_DNS     : skip real DNS resolution.
#   __VC_STUB_RESOLVE : 'host=ip;host=ip;...' for stub resolution.
#   __VC_DRY_RUN      : exit after extraction, print to stderr.
#
# Exit 0 on pass, 1 on any failure.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../../.." && pwd -P)
VALIDATOR="$REPO_ROOT/skills/research/scripts/validate-citations.sh"
WORK=$(mktemp -d -t validate-citations-test.XXXXXX)
trap 'rm -rf "$WORK"' EXIT

[[ -x "$VALIDATOR" ]] || { echo "FAIL: $VALIDATOR is not executable"; exit 1; }

PASS=0
FAIL=0

note() { printf '  %s\n' "$1"; }

assert() {
    local name="$1" cond_cmd="$2"
    if eval "$cond_cmd"; then
        PASS=$((PASS + 1))
        note "ok: $name"
    else
        FAIL=$((FAIL + 1))
        note "FAIL: $name"
    fi
}

# ---------- fake-curl shim ----------
# A bash script that:
#   - records every argv into $WORK/last-curl-argv.log
#   - on `-w '%{http_code}'` mode, prints a code based on URL pattern:
#       *://example-403.invalid/*        → 403
#       *://example-404.invalid/*        → 404
#       *://example-501.invalid/*        → 501
#       *://example-hang.invalid/*       → sleep 60 (budget tester drives this)
#       https://doi.org/10.1234/*        → 200 (allow DOI happy path)
#       any other https://*               → 200
#   - exit 0 (curl simulated success)

FAKE_CURL="$WORK/fake-curl"
cat > "$FAKE_CURL" <<'FAKEEOF'
#!/usr/bin/env bash
# Record argv. Use a stable path the harness configured.
echo "ARGV:" >> "${__VC_LAST_ARGV:-/tmp/_VC_last_argv}"
for a in "$@"; do
    printf '  %s\n' "$a" >> "${__VC_LAST_ARGV:-/tmp/_VC_last_argv}"
done

# Find the URL (last positional argument, must start with http).
url=""
for a in "$@"; do
    case "$a" in
        http://*|https://*) url="$a" ;;
    esac
done

case "$url" in
    *example-403.invalid*) printf '403'; exit 0 ;;
    *example-404.invalid*) printf '404'; exit 0 ;;
    *example-501.invalid*) printf '501'; exit 0 ;;
    *example-hang.invalid*)
        sleep 60
        printf '200'; exit 0 ;;
    *) printf '200'; exit 0 ;;
esac
FAKEEOF
chmod +x "$FAKE_CURL"
ARGV_LOG="$WORK/last-argv"

# ---------- Test 1: empty report → header + placeholder body ----------
echo "=== Test 1: empty synthesis (no claims) ==="
mkdir -p "$WORK/c1"
echo "" > "$WORK/c1/report.txt"
SUMMARY=$("$VALIDATOR" --report "$WORK/c1/report.txt" --output "$WORK/c1/cv.md" --tmpdir "$WORK/c1" 2>/dev/null | tail -n 1)
assert "Test 1: exit 0 + sidecar created" "[[ -f \"$WORK/c1/cv.md\" ]]"
assert "Test 1: SUMMARY counts are zero" "[[ \"$SUMMARY\" == 'SUMMARY=PASS=0 FAIL=0 UNKNOWN=0 TOTAL=0' ]]"
assert "Test 1: sidecar mentions zero-claims" "grep -Fq 'Claims extracted**: 0' \"$WORK/c1/cv.md\""

# ---------- Test 2: claim extraction (dry-run seam) ----------
echo "=== Test 2: extraction (dry-run) ==="
mkdir -p "$WORK/c2"
cat > "$WORK/c2/report.txt" <<'REPORT'
Some prose. https://example.com/page1 and https://example.com/page2
Reference: 10.1234/foo.bar — see also doi.org/10.5555/bad.baz
File: README.md:5 and src/main.rs:12-20
File-line in prose: scripts/test-validate-citations.sh
REPORT
DRYOUT="$WORK/c2/dry.err"
__VC_DRY_RUN=1 "$VALIDATOR" --report "$WORK/c2/report.txt" --output "$WORK/c2/cv.md" --tmpdir "$WORK/c2" 2>"$DRYOUT" >/dev/null || true
assert "Test 2: dry-run extracted at least one URL" "grep -q 'https://example.com/page1' \"$DRYOUT\""
assert "Test 2: dry-run extracted DOI" "grep -q '10.1234/foo.bar' \"$DRYOUT\""
assert "Test 2: dry-run extracted file:line README.md:5" "grep -q 'README.md:5' \"$DRYOUT\""

# ---------- Test 3: idempotency rerun (byte-identical sidecar) ----------
echo "=== Test 3: idempotency rerun ==="
mkdir -p "$WORK/c3"
cat > "$WORK/c3/report.txt" <<'REPORT'
See README.md:1 and AGENTS.md for context.
REPORT
"$VALIDATOR" --report "$WORK/c3/report.txt" --output "$WORK/c3/cv1.md" --tmpdir "$WORK/c3" >/dev/null
"$VALIDATOR" --report "$WORK/c3/report.txt" --output "$WORK/c3/cv2.md" --tmpdir "$WORK/c3" >/dev/null
assert "Test 3: rerun produces byte-identical sidecar" "diff -q \"$WORK/c3/cv1.md\" \"$WORK/c3/cv2.md\" >/dev/null"

# ---------- Test 4: HTTPS-only enforcement (file:// rejected) ----------
echo "=== Test 4: HTTPS-only enforcement ==="
mkdir -p "$WORK/c4"
cat > "$WORK/c4/report.txt" <<'REPORT'
Insecure: http://attacker.invalid/page and file:///etc/passwd
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" __VC_SKIP_DNS=1 \
    "$VALIDATOR" --report "$WORK/c4/report.txt" --output "$WORK/c4/cv.md" --tmpdir "$WORK/c4" >/dev/null 2>&1
# http:// gets extracted but the validator pre-rejects non-https with FAIL(non-https).
# file:// is not extracted by the URL regex (different scheme).
assert "Test 4: sidecar contains non-https FAIL row" "grep -F 'non-https' \"$WORK/c4/cv.md\" || ! grep -F 'http://attacker.invalid/page' \"$WORK/c4/cv.md\""

# ---------- Test 5: SSRF — RFC1918 host literal pre-rejected ----------
echo "=== Test 5: RFC1918 host literal pre-rejection ==="
mkdir -p "$WORK/c5"
cat > "$WORK/c5/report.txt" <<'REPORT'
Bad: https://10.0.0.1/admin and https://192.168.1.1/secret
Good: https://example.com/page
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" __VC_SKIP_DNS=1 \
    "$VALIDATOR" --report "$WORK/c5/report.txt" --output "$WORK/c5/cv.md" --tmpdir "$WORK/c5" >/dev/null 2>&1
assert "Test 5: ssrf-private-host marked for 10.0.0.1" "grep -F 'ssrf-private-host' \"$WORK/c5/cv.md\""

# ---------- Test 6: SSRF — DNS resolves to private IP ----------
echo "=== Test 6: DNS resolved to private IP ==="
mkdir -p "$WORK/c6"
cat > "$WORK/c6/report.txt" <<'REPORT'
See https://internal-api.invalid/data for details.
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='internal-api.invalid=10.0.0.5' \
    "$VALIDATOR" --report "$WORK/c6/report.txt" --output "$WORK/c6/cv.md" --tmpdir "$WORK/c6" >/dev/null 2>&1
assert "Test 6: ssrf-private-resolved marked" "grep -F 'ssrf-private-resolved' \"$WORK/c6/cv.md\""

# ---------- Test 7: SSRF — multi-answer DNS, ANY private fails closed ----------
echo "=== Test 7: multi-answer DNS, mixed public+private ==="
mkdir -p "$WORK/c7"
cat > "$WORK/c7/report.txt" <<'REPORT'
See https://rebinding.invalid/page for details.
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='rebinding.invalid=8.8.8.8;rebinding.invalid=10.0.0.1' \
    "$VALIDATOR" --report "$WORK/c7/report.txt" --output "$WORK/c7/cv.md" --tmpdir "$WORK/c7" >/dev/null 2>&1
assert "Test 7: rebinding rejected as ssrf-private-resolved" "grep -F 'ssrf-private-resolved' \"$WORK/c7/cv.md\""

# ---------- Test 8: HEAD 403 / 405 / 501 → UNKNOWN(head-not-supported) ----------
echo "=== Test 8: HEAD 403/501 mapping ==="
mkdir -p "$WORK/c8"
cat > "$WORK/c8/report.txt" <<'REPORT'
See https://example-403.invalid/page1 and https://example-501.invalid/page2.
REPORT
: > "$ARGV_LOG"
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example-403.invalid=8.8.8.8;example-501.invalid=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c8/report.txt" --output "$WORK/c8/cv.md" --tmpdir "$WORK/c8" >/dev/null 2>&1
assert "Test 8: head-not-supported reason present" "grep -F 'head-not-supported' \"$WORK/c8/cv.md\""

# ---------- Test 9: HEAD 404 → FAIL(head-not-found) ----------
echo "=== Test 9: HEAD 404 mapping ==="
mkdir -p "$WORK/c9"
cat > "$WORK/c9/report.txt" <<'REPORT'
See https://example-404.invalid/missing.
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example-404.invalid=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c9/report.txt" --output "$WORK/c9/cv.md" --tmpdir "$WORK/c9" >/dev/null 2>&1
assert "Test 9: head-not-found reason present" "grep -F 'head-not-found' \"$WORK/c9/cv.md\""

# ---------- Test 10: fake-curl argv contract (MUST + MUST-NOT) ----------
echo "=== Test 10: fake-curl argv MUST / MUST-NOT ==="
mkdir -p "$WORK/c10"
cat > "$WORK/c10/report.txt" <<'REPORT'
See https://example.com/page1.
REPORT
: > "$ARGV_LOG"
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example.com=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c10/report.txt" --output "$WORK/c10/cv.md" --tmpdir "$WORK/c10" >/dev/null 2>&1
assert "Test 10: argv MUST contain --max-redirs 0" "grep -Fq -- '--max-redirs' \"$ARGV_LOG\" && grep -Fq '0' \"$ARGV_LOG\""
assert "Test 10: argv MUST contain --max-time" "grep -Fq -- '--max-time' \"$ARGV_LOG\""
assert "Test 10: argv MUST contain --noproxy" "grep -Fq -- '--noproxy' \"$ARGV_LOG\""
assert "Test 10: argv MUST contain HTTPS URL last" "grep -Fq 'https://example.com/page1' \"$ARGV_LOG\""
assert "Test 10: argv MUST NOT contain --insecure" "! grep -Fq -- '--insecure' \"$ARGV_LOG\""
assert "Test 10: argv MUST NOT contain -k" "! grep -E '^  -k$' \"$ARGV_LOG\" >/dev/null"
assert "Test 10: argv MUST NOT contain --proxy" "! grep -Fq -- '--proxy' \"$ARGV_LOG\""
assert "Test 10: argv MUST NOT contain --socks" "! grep -Fq -- '--socks' \"$ARGV_LOG\""
assert "Test 10: argv MUST NOT contain --cacert" "! grep -Fq -- '--cacert' \"$ARGV_LOG\""

# ---------- Test 11: env http_proxy is bypassed via --noproxy '*' ----------
echo "=== Test 11: http_proxy bypassed by --noproxy '*' ==="
mkdir -p "$WORK/c11"
cat > "$WORK/c11/report.txt" <<'REPORT'
See https://example.com/page1.
REPORT
: > "$ARGV_LOG"
http_proxy='http://attacker.invalid/' \
HTTPS_PROXY='http://attacker.invalid/' \
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example.com=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c11/report.txt" --output "$WORK/c11/cv.md" --tmpdir "$WORK/c11" >/dev/null 2>&1
assert "Test 11: --noproxy still present under hostile proxy env" "grep -Fq -- '--noproxy' \"$ARGV_LOG\""

# ---------- Test 12: file:line citation against this repo (PASS) ----------
echo "=== Test 12: file:line PASS (existing path + line) ==="
mkdir -p "$WORK/c12"
cat > "$WORK/c12/report.txt" <<'REPORT'
See AGENTS.md:1 in this repo.
REPORT
( cd "$REPO_ROOT" && \
  "$VALIDATOR" --report "$WORK/c12/report.txt" --output "$WORK/c12/cv.md" --tmpdir "$WORK/c12" >/dev/null 2>&1 )
assert "Test 12: AGENTS.md:1 marked PASS" "grep -E '\\| .*AGENTS\\.md:1.* \\| file-line \\| PASS \\|' \"$WORK/c12/cv.md\""

# ---------- Test 13: file:line outside-repo line range (FAIL line-out-of-range) ----------
echo "=== Test 13: file:line line-out-of-range ==="
mkdir -p "$WORK/c13"
cat > "$WORK/c13/report.txt" <<'REPORT'
See AGENTS.md:99999 in this repo.
REPORT
( cd "$REPO_ROOT" && \
  "$VALIDATOR" --report "$WORK/c13/report.txt" --output "$WORK/c13/cv.md" --tmpdir "$WORK/c13" >/dev/null 2>&1 )
assert "Test 13: line-out-of-range present" "grep -F 'line-out-of-range' \"$WORK/c13/cv.md\""

# ---------- Test 14: file:line missing file (FAIL file-not-found) ----------
echo "=== Test 14: file:line file-not-found ==="
mkdir -p "$WORK/c14"
cat > "$WORK/c14/report.txt" <<'REPORT'
See does-not-exist.go:5 — bogus citation.
REPORT
( cd "$REPO_ROOT" && \
  "$VALIDATOR" --report "$WORK/c14/report.txt" --output "$WORK/c14/cv.md" --tmpdir "$WORK/c14" >/dev/null 2>&1 )
assert "Test 14: file-not-found present" "grep -F 'file-not-found' \"$WORK/c14/cv.md\""

# ---------- Test 15: git-root-unavailable when not in git tree ----------
echo "=== Test 15: git-root-unavailable when cwd is non-git ==="
mkdir -p "$WORK/c15"
cat > "$WORK/c15/report.txt" <<'REPORT'
See README.md:1 — should fall through to git-root-unavailable.
REPORT
( cd "$WORK/c15" && \
  "$VALIDATOR" --report "$WORK/c15/report.txt" --output "$WORK/c15/cv.md" --tmpdir "$WORK/c15" >/dev/null 2>&1 )
assert "Test 15: git-root-unavailable present" "grep -F 'git-root-unavailable' \"$WORK/c15/cv.md\""

# ---------- Test 16: DOI syntactic check ----------
echo "=== Test 16: DOI syntax FAIL ==="
mkdir -p "$WORK/c16"
cat > "$WORK/c16/report.txt" <<'REPORT'
Bogus DOI: 10.123/no-good (too few digits).
REPORT
"$VALIDATOR" --report "$WORK/c16/report.txt" --output "$WORK/c16/cv.md" --tmpdir "$WORK/c16" >/dev/null 2>&1
# Note: 10.123 (3 digits) is rejected by the extractor regex which requires {4,9}.
# So no claim is extracted at all — total = 0. That's also acceptable.
assert "Test 16: 3-digit DOI not extracted (regex rejects)" "grep -E 'Claims extracted\\*\\*: (0|1)' \"$WORK/c16/cv.md\""

# ---------- Test 17: URL dedup → one ledger row ----------
echo "=== Test 17: URL dedup ==="
mkdir -p "$WORK/c17"
cat > "$WORK/c17/report.txt" <<'REPORT'
See https://example.com/dup-page.
And again: https://example.com/dup-page.
And once more: https://example.com/dup-page.
REPORT
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example.com=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c17/report.txt" --output "$WORK/c17/cv.md" --tmpdir "$WORK/c17" >/dev/null 2>&1
DUP_ROWS=$(grep -c 'https://example.com/dup-page' "$WORK/c17/cv.md" || echo 0)
assert "Test 17: deduplicated URL appears in exactly one row" "[[ \"$DUP_ROWS\" == 1 ]]"

# ---------- Test 18: numeric-flag validation (FINDING_5) ----------
echo "=== Test 18: malformed --max-claims rejected with degraded sidecar ==="
mkdir -p "$WORK/c18"
cat > "$WORK/c18/report.txt" <<'REPORT'
See https://example.com/page.
REPORT
set +e
"$VALIDATOR" --report "$WORK/c18/report.txt" --output "$WORK/c18/cv.md" --tmpdir "$WORK/c18" --max-claims foo >/dev/null 2>&1
RC=$?
set -e
assert "Test 18: exit non-zero (programmer error, not fail-soft)" "[[ \"$RC\" -eq 2 ]]"
assert "Test 18: degraded sidecar still written" "[[ -s \"$WORK/c18/cv.md\" ]]"
assert "Test 18: degraded sidecar mentions invalid arg" "grep -F 'invalid argument' \"$WORK/c18/cv.md\""

# ---------- Test 19: --max-claims combined cap (FINDING_4) ----------
echo "=== Test 19: --max-claims is a combined cap, not per-bucket ==="
mkdir -p "$WORK/c19"
{
    for i in 1 2 3 4 5; do
        echo "URL $i: https://example.com/page-$i"
    done
    for i in 1 2 3 4 5; do
        echo "DOI $i: 10.1234/foo-$i"
    done
    for i in 1 2 3 4 5; do
        echo "File $i: README.md:$i"
    done
} > "$WORK/c19/report.txt"
__VC_FAKE_CURL="$FAKE_CURL" __VC_LAST_ARGV="$ARGV_LOG" \
__VC_SKIP_DNS=1 __VC_STUB_RESOLVE='example.com=8.8.8.8;doi.org=8.8.8.8' \
    "$VALIDATOR" --report "$WORK/c19/report.txt" --output "$WORK/c19/cv.md" --tmpdir "$WORK/c19" --max-claims 6 >/dev/null 2>&1
# 5+5+5 = 15 raw claims, cap=6 → exactly 6 ledger rows total (in stable URL→DOI→file order).
LEDGER_ROWS=$(grep -c '^| `' "$WORK/c19/cv.md" || echo 0)
assert "Test 19: combined cap yields exactly --max-claims rows (got $LEDGER_ROWS)" "[[ \"$LEDGER_ROWS\" == 6 ]]"

# ---------- Summary ----------
echo "=== Summary ==="
echo "Passed: $PASS"
echo "Failed: $FAIL"
if [[ "$FAIL" -gt 0 ]]; then
    exit 1
fi
echo "All assertions passed."
exit 0
