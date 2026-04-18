#!/usr/bin/env bash
# Generate agents/code-reviewer.md from the canonical archetype in
# skills/shared/reviewer-templates.md. The generated file is not hand-edited;
# CI enforces that the committed agent file matches generator output.
#
# Usage:
#   bash scripts/generate-code-reviewer-agent.sh            # write mode
#   bash scripts/generate-code-reviewer-agent.sh --check    # CI mode: fail if drift
#
# Determinism: no timestamps, no git state, no locale-dependent output
# (LC_ALL=C). Substitutions are hard-coded:
#   - {REVIEW_TARGET} -> "code, plans, or conflict resolutions"
#   - {CONTEXT_BLOCK} -> omitted (agent receives context via invocation prompt)
#   - {OUTPUT_INSTRUCTION} -> two context-keyed replacements (In-Scope + OOS)
# The YAML frontmatter and preamble comment are hard-coded below.

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
TEMPLATE="$REPO_ROOT/skills/shared/reviewer-templates.md"
AGENT_FILE="$REPO_ROOT/agents/code-reviewer.md"

MODE="write"
if [[ "${1:-}" == "--check" ]]; then
  MODE="check"
elif [[ -n "${1:-}" ]]; then
  echo "Usage: $0 [--check]" >&2
  exit 2
fi

if [[ ! -f "$TEMPLATE" ]]; then
  echo "Template not found: $TEMPLATE" >&2
  exit 2
fi

REVIEW_TARGET_VALUE='code, plans, or conflict resolutions'

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

cat >"$TMP" <<'HEADER'
---
name: code-reviewer
description: Unified code reviewer combining code quality (bugs, reuse, tests, backward compat, style), risk/integration (breaking changes, thread safety, deployment, regressions, CI), correctness (logic errors, off-by-one, nil, types, races, errors, math), architecture (separation of concerns, contract boundaries, invariants, semantic boundaries), and security (injection, authn/authz, secrets, crypto, deserialization, SSRF, path traversal, dependency CVEs).
model: sonnet
tools:
  - Read
  - Grep
  - Glob
---

<!-- AUTO-GENERATED: Derived from skills/shared/reviewer-templates.md. Do not edit. Regenerate via: bash scripts/generate-code-reviewer-agent.sh -->

HEADER

awk '
  # Extract lines strictly between the BEGIN and END markers. The archetype
  # body is wrapped in a bare ``` fence pair as the very first and very last
  # lines inside the markers; drop those two structural lines directly by
  # position, so nested fenced blocks inside the body (e.g., calibration
  # examples, future code samples with language tags) are preserved
  # untouched regardless of their count or syntax.
  /<!-- BEGIN GENERATED_BODY -->/ { in_body = 1; skipped_open = 0; next }
  /<!-- END GENERATED_BODY -->/   { in_body = 0; next }
  in_body {
    if (!skipped_open) { skipped_open = 1; next }
    buf[bn++] = $0
  }
  END {
    if (bn == 0) {
      print "ERROR: no content found between BEGIN/END GENERATED_BODY markers" > "/dev/stderr"
      exit 1
    }
    # Drop the outer close fence (last line of the body region).
    if (buf[bn-1] != "```") {
      print "ERROR: expected outer close fence ``` as last line inside GENERATED_BODY markers; got: " buf[bn-1] > "/dev/stderr"
      exit 1
    }
    bn--
    for (i = 0; i < bn; i++) print buf[i]
  }
' "$TEMPLATE" \
| awk -v rtv="$REVIEW_TARGET_VALUE" '
  # Substitute {REVIEW_TARGET}. Strip the {CONTEXT_BLOCK} line and, if followed
  # by a blank line, that blank line too, to avoid a stray blank in the output.
  {
    gsub(/\{REVIEW_TARGET\}/, rtv)
    if ($0 == "{CONTEXT_BLOCK}") {
      skip_next_blank = 1
      next
    }
    if (skip_next_blank) {
      skip_next_blank = 0
      if ($0 == "") next
    }
    print
  }
' \
| awk '
  # Context-keyed replacement of {OUTPUT_INSTRUCTION}: the bullet under
  # "### In-Scope Findings" expands to the in-scope code-review instruction
  # set; the bullet under "### Out-of-Scope Observations" expands to the
  # OOS code-review instruction set.
  /^### In-Scope Findings$/          { section = "in_scope"; print; next }
  /^### Out-of-Scope Observations$/  { section = "oos";      print; next }
  /^- \{OUTPUT_INSTRUCTION\}$/ {
    if (section == "in_scope") {
      print "- File path and line number(s) (if reviewing code) or the specific concern (if reviewing a plan)"
      print "- What the issue is"
      print "- Suggested fix (be specific)"
    } else if (section == "oos") {
      print "- File path and line number(s) or the specific concern (use `<expected-path>:1` for absent-artifact observations)"
      print "- What the issue is"
      print "- Suggested fix"
    } else {
      print "ERROR: {OUTPUT_INSTRUCTION} encountered outside a known section" > "/dev/stderr"
      exit 1
    }
    next
  }
  { print }
' >>"$TMP"

if [[ "$MODE" == "check" ]]; then
  if ! diff -u "$AGENT_FILE" "$TMP"; then
    echo "" >&2
    echo "agents/code-reviewer.md is out of sync with skills/shared/reviewer-templates.md." >&2
    echo "Run: bash scripts/generate-code-reviewer-agent.sh" >&2
    exit 1
  fi
  exit 0
fi

cp "$TMP" "$AGENT_FILE"
echo "Wrote $AGENT_FILE"
