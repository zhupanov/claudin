#!/bin/bash
# Regression test for check-reviewers.sh probe acceptance logic.
# Tests the case-insensitive exact-match rule: after whitespace strip + lowercase,
# the probe reply must equal exactly "ok". Rejects substrings like "token", "broken".
#
# Wired into: make test-harnesses
# Exit codes: 0 all pass, 1 any failure

set -euo pipefail

FAIL=0

fail() {
    echo "FAIL: $1" >&2
    FAIL=1
}

# Simulate the normalization pipeline from check-reviewers.sh:
# tr -d '[:space:]' | tr '[:upper:]' '[:lower:]'
normalize_and_check() {
    local input="$1"
    local reply
    reply=$(printf '%s' "$input" | tr -d '[:space:]' | tr '[:upper:]' '[:lower:]')
    if [[ "$reply" == "ok" ]]; then
        echo "healthy"
    else
        echo "unhealthy"
    fi
}

# --- Should be healthy ---
check_healthy() {
    local label="$1" input="$2"
    local result
    result=$(normalize_and_check "$input")
    if [[ "$result" != "healthy" ]]; then
        fail "Expected healthy for '$label', got unhealthy"
    fi
}

# --- Should be unhealthy ---
check_unhealthy() {
    local label="$1" input="$2"
    local result
    result=$(normalize_and_check "$input")
    if [[ "$result" != "unhealthy" ]]; then
        fail "Expected unhealthy for '$label', got healthy"
    fi
}

# Positive cases (should pass probe)
check_healthy "exact OK"          "OK"
check_healthy "lowercase ok"      "ok"
check_healthy "mixed case Ok"     "Ok"
check_healthy "mixed case oK"     "oK"
check_healthy "with whitespace"   "  OK  "
check_healthy "with newline"      "OK
"
check_healthy "with tab"          "$(printf 'OK\t')"

# Negative cases (should fail probe)
check_unhealthy "empty"                  ""
check_unhealthy "token"                  "token"
check_unhealthy "broken"                 "broken"
check_unhealthy "NotOK"                  "NotOK"
check_unhealthy "OK with suffix"         "OK sure"
check_unhealthy "Sure OK"               "Sure OK"
check_unhealthy "error with ok substr"   "Please look at the docs"
check_unhealthy "wok"                    "wok"
check_unhealthy "okay"                   "okay"
check_unhealthy "OK."                    "OK."
check_unhealthy "auth error"             "Error: Password not found for account"
check_unhealthy "thinking prefix"        "Thinking about this... OK"

if [[ "$FAIL" -eq 1 ]]; then
    echo "FAIL: test-check-reviewers.sh — some probe acceptance tests failed" >&2
    exit 1
fi

echo "PASS: test-check-reviewers.sh — all probe acceptance tests passed"
exit 0
