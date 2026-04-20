#!/usr/bin/env bash
# parse-prose-blockers.sh — Extract same-repo issue numbers from one document's
# prose, matched against the conservative dependency-keyword set.
#
# Reads ONE document's text from stdin (the issue body, or a single comment
# body — caller invokes once per document to prevent cross-document match
# fabrication). Emits a deduplicated, sorted, one-per-line list of same-repo
# issue numbers referenced via the five case-insensitive keyword phrases:
# "Depends on", "Blocked by", "Blocked on", "Requires", "Needs", each followed
# by `#<digits>`. Emphasis wrappers (`*`, `_`) between the keyword's
# whitespace and the `#` are tolerated (normalized away via sed) so the
# common GitHub-issue formatting `Depends on **#150**` is matched — this is
# the motivating case (issue #152's body used exactly this formatting).
# Link brackets (`[`) are NOT stripped, so link-target forms like
# `Depends on [#150](url)` remain NON-matches — this preserves the "same-repo
# only" invariant at the parser level (link targets could point anywhere).
#
# Fail-open contract: empty stdout + exit 0 on any internal error (no-match,
# empty input, regex miss, etc.). The fail-open behavior is mandatory —
# upstream callers rely on "no output means no prose blockers known" and must
# not distinguish between "there were no prose deps" and "the parser failed".
#
# Usage:
#   echo "Depends on #150" | parse-prose-blockers.sh
#   # → 150
#
# Exit code: always 0 (fail-open).

set -euo pipefail

# Read stdin into a variable. `cat` on closed/empty stdin returns empty string
# without failure.
text=$(cat)

# Normalize emphasis wrappers (bold/italic) so `**#150**`, `_#150_`, etc. match
# the downstream whitespace+# regex. Link brackets `[` / `]` are preserved —
# they stay in place so link-target forms remain NON-matches.
#
# Example transformations:
#   "Depends on **#150 (fix) only**" → "Depends on #150 (fix) only"  (matches)
#   "Depends on [#150](url)"          → unchanged                     (no match — `[` blocks it)
#   "Depends on owner/repo#150"       → unchanged                     (no match — `owner/repo` blocks it)
normalized=$(printf '%s\n' "$text" | sed 's/[*_]//g')

# Extract keyword+whitespace+#N matches. grep returns 1 when no matches exist,
# which would abort the script under `set -e` — wrap the call in a command
# group with `|| true` to neutralize the no-match exit. The fail-open contract
# requires empty stdout + exit 0 in the no-match case.
#
# POSIX ERE: `[[:space:]]+` is portable (GNU `grep -E` does not recognize `\s`
# on Linux CI). The trailing boundary `([^0-9]|$)` prevents `#12` from matching
# inside `#123` (greedy `[0-9]+` already captures all digits, but the boundary
# guards against future regex tweaks breaking the number-extraction sed).
matches=$({ grep -oiE '(Depends on|Blocked by|Blocked on|Requires|Needs)[[:space:]]+#[0-9]+([^0-9]|$)' <<< "$normalized"; } 2>/dev/null || true)

# If no matches, exit cleanly with empty stdout.
if [[ -z "$matches" ]]; then
    exit 0
fi

# Extract the numeric portion from each match and dedupe. `sed -nE` with `/p`
# prints only lines that match the substitution pattern. Empty input yields
# empty output; `sort` on empty input is a successful no-op.
printf '%s\n' "$matches" | sed -nE 's/.*#([0-9]+).*/\1/p' | sort -u -n
