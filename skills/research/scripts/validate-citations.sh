#!/usr/bin/env bash
# validate-citations.sh — Citation-credibility validator for /research Step 2.7.
#
# Reads a `/research` synthesis report, extracts cited provenance (file:line,
# URL, DOI), HEAD-fetches each unique URL with bounded timeout in parallel
# under SSRF guards, validates DOIs syntactically + via doi.org HEAD,
# spot-checks file:line existence and line range against the git tree, and
# writes a 3-state ledger (PASS / FAIL / UNKNOWN) sidecar markdown file.
# Domain credibility is advisory only — never flips PASS to FAIL.
#
# **Fail-soft contract**: this script exits 0 on validation paths; exit 2 only
# for argument/flag errors (operator or harness bug). Per-claim failures are
# recorded in the sidecar's Status column. The Step 2.7 orchestrator parses
# the script's last stdout line `SUMMARY=PASS=<n> FAIL=<n> UNKNOWN=<n>
# TOTAL=<n>` to drive the completion breadcrumb and conditional advisory
# warnings. On internal errors (curl missing, git rev-parse failure), the
# script still writes a minimally-formed sidecar so Step 3's splice always
# has a consumer.
#
# Usage:
#   validate-citations.sh --report <path> --output <path> --tmpdir <path>
#                         [--budget-seconds N] [--per-fetch-timeout N]
#                         [--max-claims N]
#
# Required:
#   --report <path>           validated synthesis (input)
#   --output <path>           sidecar markdown (output, overwritten)
#   --tmpdir <path>           scratch dir for parallel fetch results
#
# Optional:
#   --budget-seconds N        overall wall-clock budget (default 300)
#   --per-fetch-timeout N     per-curl HEAD timeout (default 10)
#   --max-claims N            cap on extracted claims (default 200, soft DoS guard)
#
# Exit code:
#   Exit 0 on validation paths (fail-soft). Exit 2 only for argument/flag
#   errors (operator or harness bug) — operators MUST treat any non-zero exit
#   as a bug report.
#
# SSRF defenses (every curl invocation):
#   - HTTPS-only: URLs not starting with https:// are pre-rejected.
#   - --max-redirs 0: no redirect chain (so a 30x cannot lead to a private host).
#   - --max-time <per-fetch-timeout>: bounded fetch.
#   - --noproxy '*': bypass any environment proxy (CONNECT to private hosts via
#     proxy is the most common SSRF in practice).
#   - Hostname pre-rejection for RFC1918/IPv6 link-local/RFC6598 literal hosts.
#   - DNS resolved-IP private-range check via host→nslookup fallback chain;
#     multi-answer DNS where ANY answer is private fails closed (rebinding
#     defense).
#   - Connection-pinning via --resolve <host>:443:<ip> using the FIRST
#     non-private resolved IP, so a TOCTOU rebinding (DNS answers re-randomized
#     between check and connect) cannot escape the validated IP set.
#
# MUST-NOT (asserted by test-validate-citations.sh):
#   --insecure, -k, --proxy, --socks*, --cacert.
#
# Idempotency: rerun against an unchanged --report produces a byte-identical
# --output. No timestamps in the body; ledger rows are sorted by claim type
# then sanitized excerpt. Audit context (date, branch) is the orchestrator's
# concern (research-report-final.md prelude lines).
#
# Process-group kill on budget exhaustion:
#   Linux (setsid available): setsid puts curl children in the script's
#     session, so a single kill -- -$$ signals every descendant. Gated on
#     __VC_SETSID_DONE=1 (the dedicated-session marker).
#   Linux (setsid absent): the re-exec is skipped; the timeout path falls
#     back to per-PID kill of CURL_PIDS — `kill -- -$$` would self-signal
#     the validator (which is not a session leader on this branch) and
#     break the fail-soft contract. Cleanup is best-effort: orphan curl
#     children are bounded by --per-fetch-timeout, not by the global kill.
#   macOS: set -m places each backgrounded fetch_url subshell in its own
#     process group (pgid == $!). The script records every $! in CURL_PIDS
#     and on timeout runs kill -- -<pid> for each one, terminating the
#     subshell + its curl substitution + any descendants together.
#     `kill -- -$$` is intentionally NOT a fallback on this branch: it
#     would also signal the validator itself (which lives in $$'s group),
#     producing exit 143 with no sidecar and breaking the fail-soft
#     contract.
#
# Portability: bash 3.2 (macOS default) and bash 5+ (Ubuntu CI). Uses awk
# (POSIX), grep -E (BSD + GNU), curl >= 7.21 for --noproxy. Optional: host
# (preferred) or nslookup for DNS resolution.

# Intentionally NOT setting -e: this validator is fail-soft. Per-claim failures
# are recorded in the sidecar; the script exits 0 on validation paths and exit
# 2 only for argument/flag errors (operator or harness bug). Per-statement non-zero
# exits are expected (grep returning 1 on no-match, kill -0 on dead PIDs, etc.)
# and MUST NOT abort the script. A defense-in-depth EXIT trap writes a degraded
# sidecar if the script is about to exit non-zero AND no sidecar was produced
# yet — Step 3 splice always sees a consumer file.
set -uo pipefail
# shellcheck disable=SC2317  # invoked indirectly via `trap ... EXIT`
__vc_exit_trap() {
    local rc=$?
    if [[ "$rc" -ne 0 && -n "${OUTPUT:-}" && ! -s "${OUTPUT:-/dev/null}" ]]; then
        printf '## Citation Validation\n\n**Validator**: validate-citations.sh v1\n**Status**: validator aborted with rc=%s; sidecar is degraded\n' "$rc" > "$OUTPUT" 2>/dev/null || true
    fi
    return 0
}
trap __vc_exit_trap EXIT

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
# shellcheck source=scripts/file-line-regex-lib.sh
# shellcheck disable=SC1091
. "$REPO_ROOT/scripts/file-line-regex-lib.sh"

REPORT=""
OUTPUT=""
TMPDIR=""
BUDGET_SECONDS=300
PER_FETCH_TIMEOUT=10
MAX_CLAIMS=200

# Test seam: when set, a fake-curl path (must be absolute) replaces the real
# binary for fixture-driven argv assertions. NOT a documented operator flag.
__VC_FAKE_CURL="${__VC_FAKE_CURL:-}"
# Test seam: when set, skip DNS resolution (fixture provides resolved IPs).
__VC_SKIP_DNS="${__VC_SKIP_DNS:-}"
# Test seam: stub allow-list for hostname → IP (semicolon-separated host=ip pairs).
__VC_STUB_RESOLVE="${__VC_STUB_RESOLVE:-}"
# Test seam: when set, exit 0 immediately after extraction so harnesses can
# assert claim parsing without making any network call.
__VC_DRY_RUN="${__VC_DRY_RUN:-}"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --report) REPORT="${2:?--report requires a value}"; shift 2 ;;
        --output) OUTPUT="${2:?--output requires a value}"; shift 2 ;;
        --tmpdir) TMPDIR="${2:?--tmpdir requires a value}"; shift 2 ;;
        --budget-seconds) BUDGET_SECONDS="${2:?--budget-seconds requires a value}"; shift 2 ;;
        --per-fetch-timeout) PER_FETCH_TIMEOUT="${2:?--per-fetch-timeout requires a value}"; shift 2 ;;
        --max-claims) MAX_CLAIMS="${2:?--max-claims requires a value}"; shift 2 ;;
        --help)
            sed -n '1,40p' "$0"
            exit 0 ;;
        *)
            echo "validate-citations.sh: unknown argument: $1" >&2
            exit 2 ;;
    esac
done

[[ -n "$REPORT" ]] || { echo "validate-citations.sh: --report is required" >&2; exit 2; }
[[ -n "$OUTPUT" ]] || { echo "validate-citations.sh: --output is required" >&2; exit 2; }

# FINDING_5: validate optional numeric flags as positive integers. Without
# this, `--max-claims foo` would abort the script under `set -u` mid-run with
# no sidecar produced, violating the fail-soft contract. Rejecting at parse
# time is the only fail-soft posture (the EXIT trap can still write a
# degraded sidecar if OUTPUT is set, but a typo deserves a precise diagnostic
# on stderr too).
__vc_check_positive_int() {
    local name="$1" value="$2"
    if [[ ! "$value" =~ ^[0-9]+$ ]] || [[ "$value" -le 0 ]]; then
        echo "validate-citations.sh: $name must be a positive integer (got: $value)" >&2
        # Write a degraded sidecar pre-emptively so Step 3 splice still has a
        # consumer file, then exit 2 (programmer/operator error). The EXIT
        # trap will not run for exit 2 with no sidecar (sidecar exists by then).
        if [[ -n "${OUTPUT:-}" ]]; then
            printf '## Citation Validation\n\n**Validator**: validate-citations.sh v1\n**Status**: invalid argument (%s=%s); sidecar is degraded\n' "$name" "$value" > "$OUTPUT" 2>/dev/null || true
        fi
        exit 2
    fi
}
__vc_check_positive_int "--budget-seconds" "$BUDGET_SECONDS"
__vc_check_positive_int "--per-fetch-timeout" "$PER_FETCH_TIMEOUT"
__vc_check_positive_int "--max-claims" "$MAX_CLAIMS"
[[ -n "$TMPDIR" ]] || { echo "validate-citations.sh: --tmpdir is required" >&2; exit 2; }

# ---------- helpers ----------

# Sidecar writer: takes a precomputed body and writes to OUTPUT atomically.
write_sidecar() {
    local body="$1"
    local tmp
    tmp=$(mktemp "${OUTPUT}.XXXXXX")
    printf '%s\n' "$body" > "$tmp"
    mv "$tmp" "$OUTPUT"
}

# Emit machine summary line (always last). pass/fail/unknown/total integers.
emit_summary() {
    local pass="$1" fail="$2" unknown="$3" total="$4"
    printf 'SUMMARY=PASS=%d FAIL=%d UNKNOWN=%d TOTAL=%d\n' \
        "$pass" "$fail" "$unknown" "$total"
}

# Sanitize an excerpt for the ledger row (single-line, no pipe).
sanitize_excerpt() {
    local s="$1"
    # collapse whitespace runs to single space; strip pipes; truncate to 80 chars
    s=$(printf '%s' "$s" | tr '\n' ' ' | tr -s ' ' | tr -d '|')
    # trim leading/trailing
    s="${s#"${s%%[! ]*}"}"
    s="${s%"${s##*[! ]}"}"
    if [[ ${#s} -gt 80 ]]; then
        s="${s:0:77}..."
    fi
    printf '%s' "$s"
}

# Hostname pre-rejection for RFC1918, IPv6 link-local, RFC6598 literal hosts.
# Returns 0 = host IS pre-rejected (blocked); non-zero = host is allowed.
# (FINDING_2 fix — comment was inverted in the initial version. The function
# name and semantics match: a `host_pre_rejected` returning 0 means YES, the
# host is pre-rejected.)
host_pre_rejected() {
    local host="$1"
    # Strip surrounding brackets from IPv6 literal hosts (FINDING_1):
    # `[::1]` → `::1`, `[fe80::1]` → `fe80::1`. Without this, the host
    # extraction at the call site (which strips at the first `:`) leaves
    # `[` or `[fc00`, which matches no case below — IPv6 literal SSRF
    # bypasses the entire pre-rejection layer.
    if [[ "$host" == \[*\] ]]; then
        host="${host:1:${#host}-2}"
    fi
    case "$host" in
        # IPv4 literals: RFC1918 (10/8, 172.16-31/12, 192.168/16), loopback,
        # link-local (169.254), RFC6598 shared-CGN (100.64-127), test-net.
        10.*) return 0 ;;
        127.*) return 0 ;;
        169.254.*) return 0 ;;
        192.168.*) return 0 ;;
        172.16.*|172.17.*|172.18.*|172.19.*) return 0 ;;
        172.2[0-9].*|172.3[01].*) return 0 ;;
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
        0.*) return 0 ;;
        # IPv6 loopback, link-local fe80::, unique-local fc00::/7 (fc??:* + fd??:*).
        ::1) return 0 ;;
        fe80::*|fe80:*) return 0 ;;
        fc??::*|fc??:*) return 0 ;;
        fd??::*|fd??:*) return 0 ;;
        # IPv6 unspecified.
        ::|::0) return 0 ;;
        # Loopback hostnames
        localhost|localhost.localdomain|*.localhost) return 0 ;;
    esac
    return 1
}

# Private-range check on a resolved IP literal (IPv4 or IPv6).
# Returns 0 = ip is private; non-zero = ip is public.
# (FINDING_3 fix — was previously named `ipv4_private` and only checked v4
# patterns, allowing AAAA records resolving to fc00::/fe80::/::1 to bypass
# the SSRF-block path.)
is_private_ip() {
    local ip="$1"
    case "$ip" in
        # IPv4 private ranges.
        10.*|127.*|169.254.*|192.168.*) return 0 ;;
        172.16.*|172.17.*|172.18.*|172.19.*) return 0 ;;
        172.2[0-9].*|172.3[01].*) return 0 ;;
        100.6[4-9].*|100.[7-9][0-9].*|100.1[01][0-9].*|100.12[0-7].*) return 0 ;;
        0.*) return 0 ;;
        # IPv6 loopback, link-local, unique-local, unspecified.
        ::1) return 0 ;;
        ::|::0) return 0 ;;
        fe80::*|fe80:*) return 0 ;;
        fc??::*|fc??:*) return 0 ;;
        fd??::*|fd??:*) return 0 ;;
    esac
    return 1
}

# Resolve a hostname to its A-record IPs. Echo space-separated IPs to stdout
# on success, empty on failure. Use host first; fall back to nslookup.
resolve_host() {
    local host="$1"
    if [[ -n "$__VC_SKIP_DNS" ]]; then
        # Fixture path: consult __VC_STUB_RESOLVE (host=ip;host=ip;...).
        local ips=""
        local pair
        local IFS=';'
        for pair in $__VC_STUB_RESOLVE; do
            local k="${pair%%=*}"
            local v="${pair#*=}"
            if [[ "$k" == "$host" ]]; then
                ips="$ips $v"
            fi
        done
        printf '%s' "${ips# }"
        return 0
    fi
    # FINDING_3: resolve BOTH A and AAAA records and union them. The previous
    # code only resolved A records, leaving AAAA-only hostnames (or hostnames
    # with mixed records where AAAA points to a private v6 address) able to
    # slip past the private-range check.
    if command -v host >/dev/null 2>&1; then
        {
            host -t A -W 5 "$host" 2>/dev/null \
                | awk '/has address/ {print $NF}'
            host -t AAAA -W 5 "$host" 2>/dev/null \
                | awk '/has IPv6 address/ {print $NF}'
        } | tr '\n' ' ' | sed 's/ *$//'
        return 0
    fi
    if command -v nslookup >/dev/null 2>&1; then
        # nslookup output is messy; extract literal addresses (v4 + v6).
        nslookup -timeout=5 "$host" 2>/dev/null \
            | awk '/^Address: / && NR > 2 {print $2}' \
            | tr '\n' ' ' \
            | sed 's/ *$//'
        return 0
    fi
    printf ''
}

# Extract URLs from the report. Stdout: one URL per line, deduplicated, sorted.
extract_urls() {
    local report="$1"
    grep -oE 'https?://[A-Za-z0-9._~:/?#@!$&'\''()*+,;=%-]+' "$report" 2>/dev/null \
        | sed -E 's/[.,;:]+$//' \
        | LC_ALL=C sort -u
}

# Extract DOIs from the report. Stdout: one DOI per line, deduplicated, sorted.
# Pattern is intentionally narrow: 10.NNNN/<rest> with a non-trivial suffix.
extract_dois() {
    local report="$1"
    grep -oE '\b10\.[0-9]{4,9}/[A-Za-z0-9._;()/:-]+' "$report" 2>/dev/null \
        | sed -E 's/[.,;:]+$//' \
        | LC_ALL=C sort -u
}

# Extract file:line citations. Stdout: one `file:line` per line (line ref optional),
# deduplicated, sorted. Uses the shared regex library's any-tier matcher.
extract_filelines() {
    local report="$1"
    grep -oE "$__filelinelib_any_re|$__filelinelib_extensionless_re" "$report" 2>/dev/null \
        | sed -E 's/^[^A-Za-z0-9._/-]//; s/[^A-Za-z0-9._/:-]$//' \
        | grep -E '\.[A-Za-z]+(:[0-9]+(-[0-9]+)?)?$|^(Makefile|Dockerfile|GNUmakefile)(:[0-9]+(-[0-9]+)?)?$' \
        | LC_ALL=C sort -u
}

# Determine domain-credibility tier for a host. Echoes "allow" or "unknown".
# Allow-list is intentionally short and well-known reputable sources only.
credibility_tier() {
    local host="$1"
    case "$host" in
        *.wikipedia.org|*.arxiv.org|arxiv.org) printf 'allow' ;;
        *.acm.org|*.ietf.org|*.python.org|*.rust-lang.org) printf 'allow' ;;
        doi.org|*.doi.org) printf 'allow' ;;
        github.com|*.github.com|*.githubusercontent.com) printf 'allow' ;;
        anthropic.com|*.anthropic.com) printf 'allow' ;;
        *) printf 'unknown' ;;
    esac
}

# HEAD-fetch a single URL, write status token to a per-URL result file.
# Argument: URL. Side-effect: writes one line to $RESULT_DIR/<hash>.result of
# the form "STATUS=<token>" (PASS / FAIL(<reason>) / UNKNOWN(<reason>)).
fetch_url() {
    local url="$1"
    local hash
    hash=$(printf '%s' "$url" | shasum 2>/dev/null | awk '{print $1}')
    [[ -z "$hash" ]] && hash=$(printf '%s' "$url" | md5sum 2>/dev/null | awk '{print $1}')
    [[ -z "$hash" ]] && hash="$(date +%s%N)-$RANDOM"
    local out="$RESULT_DIR/$hash.result"

    # HTTPS-only.
    if [[ "$url" != https://* ]]; then
        printf 'STATUS=FAIL(non-https)\n' > "$out"
        return 0
    fi

    # Curl absent → emit the contract-promised reason (FINDING_6).
    if [[ "${__VC_CURL_MISSING:-false}" == "true" ]]; then
        printf 'STATUS=UNKNOWN(curl-unavailable)\n' > "$out"
        return 0
    fi

    # Extract host. Strip scheme, then take everything before the first `/`,
    # `?`, `#`. Then handle IPv6 bracket-literal hosts vs IPv4/hostname: a
    # bracket-literal preserves all colons inside the brackets (FINDING_1),
    # while a non-bracket host strips at the first `:` (port separator).
    local hostport host
    hostport="${url#https://}"
    hostport="${hostport%%/*}"
    hostport="${hostport%%\?*}"
    hostport="${hostport%%#*}"
    if [[ "$hostport" == \[*\]* ]]; then
        # Bracketed IPv6: take through the closing `]`, drop the brackets.
        host="${hostport#\[}"
        host="${host%%\]*}"
    else
        host="${hostport%%:*}"
    fi

    if host_pre_rejected "$host"; then
        printf 'STATUS=FAIL(ssrf-private-host)\n' > "$out"
        return 0
    fi

    # DNS resolution + private-range check.
    local ips ip first_public_ip=""
    ips=$(resolve_host "$host")
    if [[ -z "$ips" ]]; then
        # No DNS resolution available: best-effort fall back to fetching without
        # --resolve pinning. Marked UNKNOWN-on-failure (network-error) below.
        first_public_ip=""
    else
        for ip in $ips; do
            if is_private_ip "$ip"; then
                printf 'STATUS=FAIL(ssrf-private-resolved)\n' > "$out"
                return 0
            fi
            if [[ -z "$first_public_ip" ]]; then
                first_public_ip="$ip"
            fi
        done
    fi

    # Build curl args. The MUST-NOT list (--insecure, -k, --proxy, --socks*,
    # --cacert) is enforced by code review and the test harness's argv pin.
    local curl_args=(
        -sS -I
        --max-redirs 0
        --max-time "$PER_FETCH_TIMEOUT"
        --noproxy '*'
        -o /dev/null
        -w '%{http_code}'
    )
    if [[ -n "$first_public_ip" ]]; then
        curl_args+=(--resolve "$host:443:$first_public_ip")
    fi
    curl_args+=("$url")

    local curl_bin="${__VC_FAKE_CURL:-curl}"
    local code rc
    code=$("$curl_bin" "${curl_args[@]}" 2>/dev/null)
    rc=$?

    if [[ "$rc" -ne 0 ]]; then
        # curl failure: timeout, connection error, etc.
        if [[ "$rc" -eq 28 ]]; then
            printf 'STATUS=UNKNOWN(timeout)\n' > "$out"
        else
            printf 'STATUS=UNKNOWN(network-error)\n' > "$out"
        fi
        return 0
    fi

    case "$code" in
        2??) printf 'STATUS=PASS\n' > "$out" ;;
        3??) printf 'STATUS=UNKNOWN(redirect-not-followed)\n' > "$out" ;;
        403|405|501) printf 'STATUS=UNKNOWN(head-not-supported)\n' > "$out" ;;
        404|410) printf 'STATUS=FAIL(head-not-found)\n' > "$out" ;;
        4??) printf 'STATUS=FAIL(head-client-error-%s)\n' "$code" > "$out" ;;
        5??) printf 'STATUS=FAIL(head-server-error-%s)\n' "$code" > "$out" ;;
        '') printf 'STATUS=UNKNOWN(no-status-line)\n' > "$out" ;;
        *) printf 'STATUS=UNKNOWN(unrecognized-status-%s)\n' "$code" > "$out" ;;
    esac
}

# Read a result file and echo just the STATUS=... value (without the prefix).
read_status() {
    local hash="$1"
    local f="$RESULT_DIR/$hash.result"
    if [[ -r "$f" ]]; then
        local line
        line=$(cat "$f")
        printf '%s' "${line#STATUS=}"
    else
        printf 'UNKNOWN(no-result)'
    fi
}

# Validate a file:line citation against the git tree.
# Echoes one of: PASS / FAIL(<reason>) / UNKNOWN(<reason>).
check_fileline() {
    local cite="$1"
    local path lineref start end git_root
    # Split on the LAST colon for line ref (`a/b/c.go:42-45`).
    if [[ "$cite" =~ ^([^:]+):([0-9]+)(-([0-9]+))?$ ]]; then
        path="${BASH_REMATCH[1]}"
        start="${BASH_REMATCH[2]}"
        end="${BASH_REMATCH[4]:-$start}"
        lineref=1
    else
        path="$cite"
        start=0
        end=0
        lineref=0
    fi

    git_root=$(git rev-parse --show-toplevel 2>/dev/null)
    if [[ -z "$git_root" ]]; then
        printf 'UNKNOWN(git-root-unavailable)'
        return 0
    fi

    # Resolve the cited path against the git root.
    local target="$git_root/$path"
    [[ -e "$target" ]] || {
        # Try relative-to-cwd as a secondary anchor (some citations use bare basenames).
        if [[ -e "$path" ]]; then
            target="$path"
        else
            printf 'FAIL(file-not-found)'
            return 0
        fi
    }

    # Realpath canonical-path containment: target must resolve under git_root.
    local rp_target rp_root
    if command -v realpath >/dev/null 2>&1; then
        rp_target=$(realpath "$target" 2>/dev/null)
        rp_root=$(realpath "$git_root" 2>/dev/null)
    else
        rp_target=$(cd "$(dirname "$target")" 2>/dev/null && pwd -P)/$(basename "$target")
        rp_root=$(cd "$git_root" 2>/dev/null && pwd -P)
    fi
    if [[ -z "$rp_target" ]]; then
        printf 'UNKNOWN(broken-symlink)'
        return 0
    fi
    case "$rp_target" in
        "$rp_root"|"$rp_root"/*) ;;
        *)
            printf 'UNKNOWN(out-of-tree-path-after-realpath)'
            return 0
            ;;
    esac

    [[ -f "$rp_target" ]] || {
        if [[ -d "$rp_target" ]]; then
            printf 'FAIL(path-is-directory)'
            return 0
        fi
        printf 'UNKNOWN(broken-symlink)'
        return 0
    }

    if [[ "$lineref" == "0" ]]; then
        # Bare path citation; no line range to validate.
        printf 'PASS'
        return 0
    fi

    # Line-range existence check.
    if [[ "$start" -gt "$end" ]]; then
        printf 'FAIL(line-range-empty)'
        return 0
    fi
    local file_lines
    file_lines=$(wc -l < "$rp_target" 2>/dev/null || echo 0)
    if [[ "$end" -gt "$file_lines" ]]; then
        printf 'FAIL(line-out-of-range)'
        return 0
    fi
    printf 'PASS'
}

# DOI validation is inlined into the main fetch loop below — we (a) syntactically
# validate the DOI via the same regex, (b) fork fetch_url for the doi.org HEAD,
# and (c) collapse PASS/UNKNOWN/FAIL into PASS/UNKNOWN(doi-unresolved) per the
# table in validate-citations.md.

# ---------- preflight ----------

if [[ ! -r "$REPORT" ]]; then
    write_sidecar "## Citation Validation

**Validator**: validate-citations.sh v1
**Status**: input report not readable: \`$REPORT\`

No claims were extracted; Step 3 splice will display this notice."
    emit_summary 0 0 0 0
    exit 0
fi

if [[ ! -d "$TMPDIR" ]]; then
    mkdir -p "$TMPDIR" 2>/dev/null || true
fi
RESULT_DIR="$TMPDIR/citation-fetches"
mkdir -p "$RESULT_DIR" 2>/dev/null || true

# FINDING_6 fix: pre-flight curl check. Without this, a missing curl produces
# per-URL `UNKNOWN(network-error)` rows (curl exit 127 in fetch_url, mapped
# to network-error), but the contract docs promise `UNKNOWN(curl-unavailable)`.
# When curl is missing, every URL+DOI claim cannot be fetched, so set a flag
# that the fetch loop honors.
__VC_CURL_MISSING=false
if ! command -v "${__VC_FAKE_CURL:-curl}" >/dev/null 2>&1; then
    __VC_CURL_MISSING=true
fi

# Synthesis stats (line/byte counts for the sidecar header).
SYNTH_BYTES=$(wc -c < "$REPORT" 2>/dev/null | tr -d ' ' || echo 0)
SYNTH_LINES=$(wc -l < "$REPORT" 2>/dev/null | tr -d ' ' || echo 0)

# ---------- extraction ----------

URLS=$(extract_urls "$REPORT")
DOIS=$(extract_dois "$REPORT")
FILELINES=$(extract_filelines "$REPORT")

# Apply --max-claims cap (combined, soft DoS guard).
TOTAL_RAW=0
[[ -n "$URLS" ]]      && TOTAL_RAW=$((TOTAL_RAW + $(printf '%s\n' "$URLS"      | grep -c .)))
[[ -n "$DOIS" ]]      && TOTAL_RAW=$((TOTAL_RAW + $(printf '%s\n' "$DOIS"      | grep -c .)))
[[ -n "$FILELINES" ]] && TOTAL_RAW=$((TOTAL_RAW + $(printf '%s\n' "$FILELINES" | grep -c .)))

CLAIMS_TRUNCATED=false
if [[ "$TOTAL_RAW" -gt "$MAX_CLAIMS" ]]; then
    CLAIMS_TRUNCATED=true
    # FINDING_4 fix: enforce ONE combined cap across URL+DOI+file-line buckets,
    # not three independent caps (the previous per-bucket head allowed up to
    # 3*MAX_CLAIMS to slip through). Drain in stable order URL → DOI →
    # file-line so the soft DoS guard is actually bounded by MAX_CLAIMS.
    REMAINING=$MAX_CLAIMS
    if [[ -n "$URLS" ]]; then
        TAKE=$(( REMAINING < $(printf '%s\n' "$URLS" | grep -c .) ? REMAINING : $(printf '%s\n' "$URLS" | grep -c .) ))
        URLS=$(printf '%s\n' "$URLS" | head -n "$TAKE")
        REMAINING=$(( REMAINING - TAKE ))
    fi
    if [[ -n "$DOIS" && "$REMAINING" -gt 0 ]]; then
        TAKE=$(( REMAINING < $(printf '%s\n' "$DOIS" | grep -c .) ? REMAINING : $(printf '%s\n' "$DOIS" | grep -c .) ))
        DOIS=$(printf '%s\n' "$DOIS" | head -n "$TAKE")
        REMAINING=$(( REMAINING - TAKE ))
    elif [[ "$REMAINING" -le 0 ]]; then
        DOIS=""
    fi
    if [[ -n "$FILELINES" && "$REMAINING" -gt 0 ]]; then
        TAKE=$(( REMAINING < $(printf '%s\n' "$FILELINES" | grep -c .) ? REMAINING : $(printf '%s\n' "$FILELINES" | grep -c .) ))
        FILELINES=$(printf '%s\n' "$FILELINES" | head -n "$TAKE")
    elif [[ "$REMAINING" -le 0 ]]; then
        FILELINES=""
    fi
fi

# Empty-report path: synthesis exists but has no extractable claims.
if [[ -z "$URLS" && -z "$DOIS" && -z "$FILELINES" ]]; then
    write_sidecar "## Citation Validation

**Validator**: validate-citations.sh v1
**Synthesis**: ${SYNTH_BYTES} bytes, ${SYNTH_LINES} lines
**Claims extracted**: 0
**Status counts**: 0 PASS · 0 FAIL · 0 UNKNOWN

_No citable provenance (URLs, DOIs, file:line) found in the synthesis. Citation validation is a no-op for this report._"
    emit_summary 0 0 0 0
    exit 0
fi

# ---------- dry-run test seam ----------

if [[ -n "$__VC_DRY_RUN" ]]; then
    {
        printf 'EXTRACTED_URLS=\n%s\n' "$URLS"
        printf 'EXTRACTED_DOIS=\n%s\n' "$DOIS"
        printf 'EXTRACTED_FILELINES=\n%s\n' "$FILELINES"
        printf 'CLAIMS_TRUNCATED=%s\n' "$CLAIMS_TRUNCATED"
    } >&2
    emit_summary 0 0 0 0
    exit 0
fi

# ---------- URL + DOI fetch (parallel, budget-bounded) ----------

# Process-group setup for clean budget kill.
case "$(uname -s 2>/dev/null)" in
    Linux*)
        if [[ "${__VC_SETSID_DONE:-}" != "1" ]]; then
            if command -v setsid >/dev/null 2>&1; then
                # Set the marker BEFORE exec so the re-exec'd child inherits
                # it (preventing an infinite re-exec loop) AND so the kill
                # site below can use it as a "running in dedicated session"
                # signal. Setting it earlier — before `command -v setsid` —
                # would make `kill -- -$$` unsafe in the setsid-missing
                # branch because the original (non-re-exec'd) process would
                # carry the marker without actually being in its own session.
                export __VC_SETSID_DONE=1
                # Re-exec under setsid so curl children share our session.
                exec setsid -w "$0" \
                    --report "$REPORT" --output "$OUTPUT" --tmpdir "$TMPDIR" \
                    --budget-seconds "$BUDGET_SECONDS" \
                    --per-fetch-timeout "$PER_FETCH_TIMEOUT" \
                    --max-claims "$MAX_CLAIMS"
            fi
        fi
        ;;
    Darwin*)
        # Enable job control so each `fetch_url &` subshell becomes a
        # process group leader. The budget-exhaustion handler iterates
        # CURL_PIDS and runs `kill -- -<pid>` per recorded subshell PID
        # to terminate each subshell + its curl substitution. If `set -m`
        # silently fails (rare on macOS bash 3.2+), background subshells
        # share $$'s process group and per-PGID kills cannot reach their
        # curl children — emit a warning so operators know orphan
        # cleanup is degraded; we cannot fall back to `kill -- -$$`
        # because that would also signal the validator itself and break
        # the fail-soft contract.
        set -m 2>/dev/null || true
        case "$-" in
            *m*) : ;;  # job control active — normal path
            *)   printf 'WARNING: validate-citations.sh: set -m failed; budget-exhaustion kill cannot guarantee orphan-curl cleanup\n' >&2 ;;
        esac
        ;;
esac

START_TS=$(date +%s)
declare -a CURL_PIDS
CURL_PIDS=()

# Background-fetch each URL.
if [[ -n "$URLS" ]]; then
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        fetch_url "$url" &
        CURL_PIDS+=($!)
    done <<< "$URLS"
fi
# Background-fetch each DOI's resolved doi.org URL (the in-script DOI
# checker forks fetch_url for the doi.org HEAD).
if [[ -n "$DOIS" ]]; then
    while IFS= read -r doi; do
        [[ -z "$doi" ]] && continue
        # Skip syntactically invalid DOIs (no fetch).
        if printf '%s' "$doi" | grep -Eq '^10\.[0-9]{4,9}/[A-Za-z0-9._;()/:-]+$'; then
            fetch_url "https://doi.org/$doi" &
            CURL_PIDS+=($!)
        fi
    done <<< "$DOIS"
fi

# Wait with overall budget. wait -n is bash 4+; bash 3.2 fallback uses a
# polling loop with `kill -0`.
WAIT_DEADLINE=$((START_TS + BUDGET_SECONDS))
TIMED_OUT=false
if [[ ${#CURL_PIDS[@]} -gt 0 ]]; then
    while :; do
        # All children done?
        local_running=0
        for pid in "${CURL_PIDS[@]}"; do
            if kill -0 "$pid" 2>/dev/null; then
                local_running=1
                break
            fi
        done
        if [[ "$local_running" == "0" ]]; then
            break
        fi
        local_now=$(date +%s)
        if [[ "$local_now" -ge "$WAIT_DEADLINE" ]]; then
            TIMED_OUT=true
            break
        fi
        sleep 1
    done
fi

if [[ "$TIMED_OUT" == "true" ]]; then
    # Process-group kill.
    case "$(uname -s 2>/dev/null)" in
        Linux*)
            # `kill -- -$$` is only safe when this process is the leader of
            # its own session (set up by the setsid re-exec earlier). When
            # setsid was absent at startup, __VC_SETSID_DONE is unset, the
            # validator runs in its caller's process group, and signaling
            # $$ would also signal the validator itself — breaking the
            # documented "always exits 0" fail-soft contract. Fall back to
            # per-PID kill of the recorded subshells in that case; orphan
            # curl children are bounded by $PER_FETCH_TIMEOUT.
            if [[ "${__VC_SETSID_DONE:-}" == "1" ]]; then
                kill -- -$$ 2>/dev/null || true
            else
                for _kill_pid in "${CURL_PIDS[@]}"; do
                    kill "$_kill_pid" 2>/dev/null || true
                done
            fi
            ;;
        Darwin*)
            # The earlier Darwin case stanza enables `set -m`, which puts
            # each backgrounded `fetch_url &` in its own process group
            # (pgid == subshell pid), so `kill -- -$$` would only signal
            # the parent's group and leak each subshell's curl child.
            # `kill -- -$$` is intentionally NOT used as a fallback here:
            # when `set -m` did take effect, $$'s group contains the
            # validator itself, and signaling it kills the script before
            # it can write the per-claim UNKNOWN(timeout) rows and the
            # sidecar — i.e. it breaks the fail-soft contract (script
            # must exit 0 with a consumable sidecar).
            for _kill_pid in "${CURL_PIDS[@]}"; do
                kill -- -"$_kill_pid" 2>/dev/null || true
            done
            ;;
    esac
    # Mark every still-missing result as UNKNOWN(timeout).
    if [[ -n "$URLS" ]]; then
        while IFS= read -r url; do
            [[ -z "$url" ]] && continue
            local_hash=$(printf '%s' "$url" | shasum 2>/dev/null | awk '{print $1}')
            [[ -z "$local_hash" ]] && local_hash=$(printf '%s' "$url" | md5sum 2>/dev/null | awk '{print $1}')
            if [[ ! -e "$RESULT_DIR/$local_hash.result" ]]; then
                printf 'STATUS=UNKNOWN(timeout)\n' > "$RESULT_DIR/$local_hash.result"
            fi
        done <<< "$URLS"
    fi
    if [[ -n "$DOIS" ]]; then
        while IFS= read -r doi; do
            [[ -z "$doi" ]] && continue
            local_hash=$(printf '%s' "https://doi.org/$doi" | shasum 2>/dev/null | awk '{print $1}')
            [[ -z "$local_hash" ]] && local_hash=$(printf '%s' "https://doi.org/$doi" | md5sum 2>/dev/null | awk '{print $1}')
            if [[ ! -e "$RESULT_DIR/$local_hash.result" ]]; then
                printf 'STATUS=UNKNOWN(timeout)\n' > "$RESULT_DIR/$local_hash.result"
            fi
        done <<< "$DOIS"
    fi
fi

# ---------- ledger composition ----------

PASS=0; FAIL=0; UNKNOWN=0; TOTAL=0
LEDGER=""
CRED_SEEN=""

append_row() {
    local excerpt="$1" claim_type="$2" status="$3" reason="$4"
    LEDGER="${LEDGER}| \`$(sanitize_excerpt "$excerpt")\` | $claim_type | $status | $reason |  |"$'\n'
}

# URL rows.
if [[ -n "$URLS" ]]; then
    while IFS= read -r url; do
        [[ -z "$url" ]] && continue
        TOTAL=$((TOTAL + 1))
        local_hash=$(printf '%s' "$url" | shasum 2>/dev/null | awk '{print $1}')
        [[ -z "$local_hash" ]] && local_hash=$(printf '%s' "$url" | md5sum 2>/dev/null | awk '{print $1}')
        raw=$(read_status "$local_hash")
        case "$raw" in
            PASS) status=PASS; reason=""; PASS=$((PASS + 1)) ;;
            FAIL\(*) status=FAIL; reason="${raw#FAIL\(}"; reason="${reason%\)}"; FAIL=$((FAIL + 1)) ;;
            UNKNOWN\(*) status=UNKNOWN; reason="${raw#UNKNOWN\(}"; reason="${reason%\)}"; UNKNOWN=$((UNKNOWN + 1)) ;;
            *) status=UNKNOWN; reason="parse-error"; UNKNOWN=$((UNKNOWN + 1)) ;;
        esac
        append_row "$url" "url" "$status" "$reason"
        # Domain credibility row (deduplicate per host).
        local_host="${url#https://}"
        local_host="${local_host%%/*}"
        local_host="${local_host%%\?*}"
        local_host="${local_host%%#*}"
        local_host="${local_host%%:*}"
        if ! printf '%s' "$CRED_SEEN" | grep -Fxq "$local_host"; then
            CRED_SEEN="${CRED_SEEN}${local_host}"$'\n'
        fi
    done <<< "$URLS"
fi

# DOI rows.
if [[ -n "$DOIS" ]]; then
    while IFS= read -r doi; do
        [[ -z "$doi" ]] && continue
        TOTAL=$((TOTAL + 1))
        if ! printf '%s' "$doi" | grep -Eq '^10\.[0-9]{4,9}/[A-Za-z0-9._;()/:-]+$'; then
            append_row "$doi" "doi" "FAIL" "doi-syntax"
            FAIL=$((FAIL + 1))
            continue
        fi
        local_hash=$(printf '%s' "https://doi.org/$doi" | shasum 2>/dev/null | awk '{print $1}')
        [[ -z "$local_hash" ]] && local_hash=$(printf '%s' "https://doi.org/$doi" | md5sum 2>/dev/null | awk '{print $1}')
        raw=$(read_status "$local_hash")
        # doi.org is a redirect resolver by design — a 3xx HEAD on https://doi.org/<doi>
        # is the success signal for DOI registration, so treat redirect-not-followed as PASS.
        case "$raw" in
            PASS|UNKNOWN\(redirect-not-followed\)) status=PASS; reason=""; PASS=$((PASS + 1)) ;;
            UNKNOWN\(*|FAIL\(*) status=UNKNOWN; reason="doi-unresolved"; UNKNOWN=$((UNKNOWN + 1)) ;;
            *) status=UNKNOWN; reason="doi-unresolved"; UNKNOWN=$((UNKNOWN + 1)) ;;
        esac
        append_row "$doi" "doi" "$status" "$reason"
    done <<< "$DOIS"
fi

# File:line rows.
if [[ -n "$FILELINES" ]]; then
    while IFS= read -r cite; do
        [[ -z "$cite" ]] && continue
        TOTAL=$((TOTAL + 1))
        raw=$(check_fileline "$cite")
        case "$raw" in
            PASS) status=PASS; reason=""; PASS=$((PASS + 1)) ;;
            FAIL\(*) status=FAIL; reason="${raw#FAIL\(}"; reason="${reason%\)}"; FAIL=$((FAIL + 1)) ;;
            UNKNOWN\(*) status=UNKNOWN; reason="${raw#UNKNOWN\(}"; reason="${reason%\)}"; UNKNOWN=$((UNKNOWN + 1)) ;;
            *) status=UNKNOWN; reason="parse-error"; UNKNOWN=$((UNKNOWN + 1)) ;;
        esac
        append_row "$cite" "file-line" "$status" "$reason"
    done <<< "$FILELINES"
fi

# Sort the ledger rows for determinism (idempotency rerun).
LEDGER_SORTED=$(printf '%s' "$LEDGER" | LC_ALL=C sort -u)

# ---------- domain credibility table ----------

CRED_TABLE=""
if [[ -n "$CRED_SEEN" ]]; then
    CRED_TABLE="| Domain | Tier | Notes |"$'\n'
    CRED_TABLE+="|---|---|---|"$'\n'
    while IFS= read -r host; do
        [[ -z "$host" ]] && continue
        tier=$(credibility_tier "$host")
        case "$tier" in
            allow) note="well-known reputable origin" ;;
            *)     note="no allow-list entry; classification heuristic only — NOT a FAIL signal" ;;
        esac
        CRED_TABLE+="| $host | $tier | $note |"$'\n'
    done <<< "$CRED_SEEN"
fi

# ---------- sidecar render ----------

TRUNCATION_NOTICE=""
if [[ "$CLAIMS_TRUNCATED" == "true" ]]; then
    TRUNCATION_NOTICE="

_Note: claim count exceeded \`--max-claims=$MAX_CLAIMS\`. Excess claims were dropped from the ledger; consider re-running with \`--max-claims\` raised._"
fi

CRED_BLOCK=""
if [[ -n "$CRED_TABLE" ]]; then
    CRED_BLOCK="

<details><summary>Domain credibility (advisory only)</summary>

$CRED_TABLE
</details>"
fi

write_sidecar "## Citation Validation

**Validator**: validate-citations.sh v1
**Synthesis**: ${SYNTH_BYTES} bytes, ${SYNTH_LINES} lines
**Claims extracted**: ${TOTAL}
**Status counts**: ${PASS} PASS · ${FAIL} FAIL · ${UNKNOWN} UNKNOWN

| Claim | Type | Status | Reason | Cited by |
|---|---|---|---|---|
${LEDGER_SORTED}${TRUNCATION_NOTICE}${CRED_BLOCK}"

emit_summary "$PASS" "$FAIL" "$UNKNOWN" "$TOTAL"
exit 0
