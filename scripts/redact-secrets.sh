#!/usr/bin/env bash
# redact-secrets.sh — Deterministic defense-in-depth secret scrubber.
#
# Reads arbitrary text on stdin, applies a fixed set of regex replacements,
# and writes the redacted text to stdout. Intended as the outbound choke
# point for content that /issue's create-one.sh publishes as a public
# GitHub issue title or body, complementing prompt-level sanitization in
# skills/implement/SKILL.md and skills/issue/SKILL.md. See SECURITY.md
# ("Untrusted GitHub Issue Content") for the dual-layer trust model.
#
# Covered families (each replaced with <REDACTED-TOKEN> unless noted):
#   - Anthropic / OpenAI sk-* and sk-ant-* keys
#   - GitHub PATs and fine-grained tokens: ghp_, gho_, ghu_, ghs_, ghr_, github_pat_
#   - AWS long-term access key IDs (AKIA[0-9A-Z]{16})
#   - Slack tokens (xoxb-, xoxa-, xoxp-, xoxr-, xoxs-)
#   - Generic JWT (eyJ…header.payload.signature)
#   - PEM-encoded private key blocks → <REDACTED-PRIVATE-KEY> (multi-line)
#
# Explicit non-coverage (not matched; operators must treat this as partial
# defense-in-depth, not comprehensive secret detection):
#   - AWS STS temporary credentials (ASIA* prefix)
#   - Payment-provider live keys (Stripe, Square, etc.)
#   - Opaque bearer tokens without a distinctive prefix
#   - Database connection strings, private hostnames, PII
#
# Idempotence: placeholders (<REDACTED-TOKEN>, <REDACTED-PRIVATE-KEY>) are
# crafted so no covered pattern matches within them; re-running the filter
# on already-redacted output is a no-op.
#
# Portability: uses `sed -E` (BSD and GNU) and `awk` (POSIX). Does NOT
# depend on perl or GNU-specific sed features.
#
# Usage:
#   printf '%s' "$TEXT" | redact-secrets.sh
#   cat body.txt | redact-secrets.sh > redacted.txt
#
# Exit codes:
#   0 — success
#   non-zero — sed or awk failed (propagated via pipefail)

set -euo pipefail

# Single sed -E invocation collapsing all 5 line-local families into one pass.
# Patterns are byte-for-byte ports of the vetted regexes from the deleted
# scripts/create-oos-issues.sh (see commit 9cb59f5). The character classes
# use [A-Za-z0-9_-] rather than \w so the script runs on BSD sed without
# GNU-only extensions.
#
# Then awk handles the multi-line PEM case that sed cannot: awk walks the
# stream line-by-line, and when it sees a BEGIN marker it swallows lines
# until the matching END marker, emitting a single placeholder for the
# whole block. Non-PEM lines pass through unchanged.
sed -E \
    -e 's/sk-(ant-)?[A-Za-z0-9_-]{20,}/<REDACTED-TOKEN>/g' \
    -e 's/(ghp|gho|ghu|ghs|ghr|github_pat)_[A-Za-z0-9_]{20,}/<REDACTED-TOKEN>/g' \
    -e 's/AKIA[0-9A-Z]{16}/<REDACTED-TOKEN>/g' \
    -e 's/xox[baprs]-[A-Za-z0-9-]{10,}/<REDACTED-TOKEN>/g' \
    -e 's/eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/<REDACTED-TOKEN>/g' \
    | awk '
        /^-----BEGIN [A-Z ]*PRIVATE KEY-----/ {
            print "<REDACTED-PRIVATE-KEY>"
            in_pem = 1
            next
        }
        in_pem {
            if (/^-----END [A-Z ]*PRIVATE KEY-----/) {
                in_pem = 0
            }
            next
        }
        { print }
    '
