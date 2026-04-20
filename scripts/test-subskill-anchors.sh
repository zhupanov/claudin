#!/usr/bin/env bash
# test-subskill-anchors.sh - Regression harness for heading-anchor
# citations in skills/shared/subskill-invocation.md (closes #236).
#
# Asserts that every backticked citation of the shape
#   `<path>/SKILL.md § <heading>`
# inside skills/shared/subskill-invocation.md resolves to a line
#   ## <heading>
# or
#   ### <heading>
# in the referenced file (exact string match on the heading text;
# trailing whitespace on the target line is tolerated but nothing else).
#
# Contract (follow-up from #227 / PR #229):
#   - Fenced code blocks in the source doc are skipped (any fence opener
#     of 3-or-more backticks toggles state; note the file uses both
#     triple- and quadruple-backtick fences).
#   - Citation extraction uses a path-anchored pattern: the backticked
#     span must begin with something ending in "SKILL.md" followed by a
#     literal " \xc2\xa7 " separator (that is, a U+00A7 section sign
#     between spaces) and a non-empty heading. Prose continuation spans
#     without a path prefix are deliberately not matched.
#   - Heading match uses grep -Fxq (fixed-string, exact-line) against
#     a copy of the target file with trailing whitespace stripped. No
#     regex interpolation of heading text anywhere - heading titles
#     containing regex metacharacters (such as ".", "(", "[", "+") are
#     compared byte-for-byte.
#   - A minimum-citation floor guards against an extractor regression
#     silently validating zero or few anchors. The floor is set below
#     the current live count to tolerate small editorial drift.
#
# Invoked via:  bash scripts/test-subskill-anchors.sh
# Wired into:   make lint (via the test-subskill-anchors Makefile target).
#
# Fail-closed: any IO or parse anomaly exits non-zero. All failures in
# one run are reported (the script does NOT short-circuit on first).
#
# Scope: this harness scans only skills/shared/subskill-invocation.md.
# It is a companion to scripts/lint-skill-invocations.py, which
# enforces a different contract (sub-skill invocation wording inside
# SKILL.md bodies). Together they give two orthogonal doc guardrails:
# heading-anchor resolution (this script) and invocation phrasing
# (the Python lint).

set -euo pipefail
export LC_ALL=C

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd -P)"
SOURCE_MD="$REPO_ROOT/skills/shared/subskill-invocation.md"

# Minimum-citation floor. 12 live citations exist as of the closing
# commit for #236; this floor catches any serious extractor regression
# (>15% citation loss) while tolerating small editorial drift.
MIN_CITATIONS=10

if [[ ! -f "$SOURCE_MD" ]]; then
  printf 'FAIL: source file not found: %s\n' "$SOURCE_MD" >&2
  exit 1
fi

# Extract (source_line, path, heading) tuples from the source doc.
# awk toggles fence state on any line beginning with 3-or-more backticks.
# Outside fences, it pulls every backticked span matching
#   `<path>.../SKILL.md <section-sign> <heading>`
# and emits "<line>\t<path>\t<heading>" records.
#
# Uses POSIX ERE via the heredoc-embedded awk program. The section-sign
# byte sequence (0xc2 0xa7) is referenced as a string literal from the
# source file itself - awk parses the input bytes and matches them
# verbatim against the pattern stored in the `sep` variable.
tuples_file="$(mktemp -t subskill-anchors.XXXXXX)"
trap 'rm -f "$tuples_file"' EXIT

awk '
  BEGIN {
    in_fence = 0
    # Section-sign " U+00A7 " bracketed by spaces. Built byte-wise to
    # keep this awk program ASCII-safe at the source level; the file
    # contents themselves are UTF-8 and pass through untouched.
    sep = " " sprintf("%c%c", 194, 167) " "
    # Fence opener: any line starting with 3-or-more backticks.
    fence_re = "^`{3,}"
  }
  {
    if ($0 ~ fence_re) {
      in_fence = 1 - in_fence
      next
    }
    if (in_fence) { next }
    line = $0
    while (match(line, /`[^`]+SKILL\.md[^`]+`/)) {
      span = substr(line, RSTART + 1, RLENGTH - 2)
      idx = index(span, sep)
      if (idx > 0) {
        path = substr(span, 1, idx - 1)
        heading = substr(span, idx + length(sep))
        if (path != "" && heading != "") {
          printf "%d\t%s\t%s\n", NR, path, heading
        }
      }
      line = substr(line, RSTART + RLENGTH)
    }
  }
' "$SOURCE_MD" > "$tuples_file"

count=0
failures=0

while IFS=$'\t' read -r src_line rel_path heading; do
  count=$((count + 1))
  target="$REPO_ROOT/$rel_path"
  if [[ ! -f "$target" ]]; then
    printf 'FAIL: %s:%s: %s \xc2\xa7 %s - file not found\n' \
      "skills/shared/subskill-invocation.md" "$src_line" "$rel_path" "$heading" >&2
    failures=$((failures + 1))
    continue
  fi
  # Strip trailing whitespace from target lines, then exact-match against
  # "## <heading>" or "### <heading>". No regex interpolation. grep is
  # invoked WITHOUT -q to avoid a SIGPIPE race against awk under
  # pipefail: with -q, grep exits on first match before awk finishes
  # writing, awk receives SIGPIPE, and pipefail propagates exit 141.
  # Routing stdout to /dev/null makes grep consume the full input.
  stripped_target="$(mktemp -t subskill-target.XXXXXX)"
  awk '{ sub(/[[:space:]]+$/, ""); print }' "$target" > "$stripped_target"
  if grep -Fxq -- "## $heading" "$stripped_target"; then
    rm -f "$stripped_target"
    continue
  fi
  if grep -Fxq -- "### $heading" "$stripped_target"; then
    rm -f "$stripped_target"
    continue
  fi
  rm -f "$stripped_target"
  # shellcheck disable=SC2016 # backticks in the format string are literal markdown, not command substitution
  printf 'FAIL: %s:%s: %s \xc2\xa7 %s - no matching `## %s` or `### %s` in %s\n' \
    "skills/shared/subskill-invocation.md" "$src_line" "$rel_path" "$heading" \
    "$heading" "$heading" "$rel_path" >&2
  failures=$((failures + 1))
done < "$tuples_file"

if (( count < MIN_CITATIONS )); then
  printf 'FAIL: extracted only %d citations, expected >= %d - parser regression suspected\n' \
    "$count" "$MIN_CITATIONS" >&2
  failures=$((failures + 1))
fi

if (( failures > 0 )); then
  printf '%d failure(s). Checked %d citation(s) in %s.\n' \
    "$failures" "$count" "skills/shared/subskill-invocation.md" >&2
  exit 1
fi

printf 'PASS: test-subskill-anchors.sh - %d citation(s) resolved\n' "$count"
exit 0
