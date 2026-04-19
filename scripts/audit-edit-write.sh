#!/usr/bin/env bash
# audit-edit-write.sh — Dev-only PostToolUse audit hook for Edit/Write tools.
#
# Appends one JSONL line {"ts":"...","event":"PostToolUse","payload":<stdin JSON>}
# to ${CLAUDE_PROJECT_DIR:-$PWD}/.claude/hook-audit.log. Never blocks tool use;
# always exits 0. Only enabled when a developer opts in by adding a PostToolUse
# hook entry to .claude/settings.local.json (gitignored — see docs/dev-hook-audit.md).
#
# set -e is intentionally omitted: write failures (disk full, read-only fs,
# missing .claude dir) must never interrupt Claude Code's tool completion.

set -uo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$PWD}"
LOG="$PROJECT_DIR/.claude/hook-audit.log"
INPUT=$(cat)

mkdir -p "$PROJECT_DIR/.claude" 2>/dev/null || true

# jq -ec with select(type=="object"): empty/invalid/non-object stdin exits
# non-zero, `|| true` swallows it, no line appended. Valid object stdin is
# wrapped into the audit record and appended.
printf '%s' "$INPUT" | jq -ec --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    'select(type=="object") | {ts: $ts, event: "PostToolUse", payload: .}' \
    >> "$LOG" 2>/dev/null || true

exit 0
