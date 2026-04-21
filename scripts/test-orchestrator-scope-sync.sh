#!/usr/bin/env bash
# test-orchestrator-scope-sync.sh — Cross-validation harness asserting exact
# set equality between two independently-maintained representations of the
# anti-halt orchestrator/delegator classification (closes #285):
#
#   (1) Shell arrays ORCHESTRATORS=( … ) and DELEGATORS=( … ) in
#       scripts/test-anti-halt-banners.sh — the executable contract.
#   (2) Bulleted scope lists under "### Scope list" in
#       skills/shared/subskill-invocation.md — the human-readable contract.
#
# Drift between the two is silent today: adding or reclassifying a skill in
# one place without the other goes undetected until a reviewer notices. This
# harness mechanically enforces the invariant so edits to either source
# immediately fail `make lint` until the other side is updated.
#
# Invoked via:  bash scripts/test-orchestrator-scope-sync.sh
# Wired into:   make lint (via the test-orchestrator-scope-sync Makefile
#               target). Listed in agent-lint.toml exclude because agent-lint
#               does not follow Makefile-only references.
#
# GRAMMAR ASSUMPTIONS (pinned — editing either source requires editing this
# script in the same PR):
#
#   - scripts/test-anti-halt-banners.sh declares the arrays as
#       ORCHESTRATORS=(         and         DELEGATORS=(
#         "skills/<name>/SKILL.md"            "skills/<name>/SKILL.md"
#         …                                   …
#       )                                   )
#     Each element is on its own line, optionally surrounded by double
#     quotes, optionally followed by an inline `# …` trailing comment; array
#     open is `^NAME=\($` and close is `^\)$` on their own lines.
#
#   - skills/shared/subskill-invocation.md contains a `### Scope list`
#     heading, followed by prose, followed by the literal sentence
#     `The banner MUST appear in these orchestrator SKILL.md files:`
#     then bullets, then the literal sentence
#     `The banner MUST NOT appear in pure-delegator SKILL.md files:`
#     then bullets, then the `## Session-env handoff` top-level heading
#     which ends the scope-list section. Each bullet is
#     `- ` + backticked `skills/<name>/SKILL.md`, anchored end-of-line
#     (trailing whitespace tolerated — see FINDING_5 mitigation below).
#     No `###` subsubheadings may appear under `### Scope list` (would
#     partition the list silently if the parser exited on them).
#
# PARSER DESIGN NOTES:
#
#   - The awk entry rule `/^### Scope list$/` is placed BEFORE the
#     `/^## / && in_scope { exit }` rule so that the entry line itself is
#     not shadowed by the exit rule (closes a FINDING_1 ordering hazard).
#   - The exit fires ONLY on a top-level `^## ` heading, not on `^### ` —
#     so any future `###` inserted inside Scope list becomes detectable
#     drift rather than a silent early-exit with partial data.
#   - `tr -d '\r'` strips CRLF line endings on Windows clones and guards
#     against pre-commit normalization drift; dropping it would make
#     trailing-\r lines silently miss the anchored bullet regex.
#   - `gsub(/[[:space:]]+$/, "")` in the bullet matcher strips trailing
#     spaces/tabs so editor noise after the closing backtick does not make
#     the anchored regex silently drop a legitimate bullet.
#   - Fail-closed on empty: if any of the four sets (HARNESS_ORCH /
#     HARNESS_DEL / DOC_ORCH / DOC_DEL) parses to empty, the harness
#     FAILS — this is the correct behavior when either source's grammar
#     drifts (heading renamed, intro sentence rephrased, array format
#     changed). A silent empty-set "sets equal, PASS" would be the wrong
#     outcome.

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
export LC_ALL=C

HARNESS_FILE="$REPO_ROOT/scripts/test-anti-halt-banners.sh"
DOC_FILE="$REPO_ROOT/skills/shared/subskill-invocation.md"

PASS_COUNT=0
FAIL_COUNT=0

check_file_exists() {
  local rel="$1"
  local abs="$REPO_ROOT/$rel"
  if [[ ! -f "$abs" ]]; then
    echo "FAIL: required source $rel does not exist" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi
  return 0
}

# Extract a bash array from the harness source into a sorted-unique set.
# Usage: extract_harness_array ORCHESTRATORS
# Emits one path per line on stdout.
extract_harness_array() {
  local name="$1"
  tr -d '\r' < "$HARNESS_FILE" | awk -v name="$name" '
    $0 == name "=(" { in_arr=1; next }
    in_arr && /^\)$/ { in_arr=0; next }
    in_arr {
      # Strip inline # ... trailing comment.
      sub(/[[:space:]]*#.*$/, "")
      # Strip leading/trailing whitespace.
      gsub(/^[[:space:]]+|[[:space:]]+$/, "")
      # Skip empty lines (including lines that were only comments).
      if ($0 == "") next
      # Strip surrounding double quotes (array elements are quoted). Uses
      # two sub() calls for BSD-awk portability (3-arg match() is gawk-only).
      sub(/^"/, "")
      sub(/"$/, "")
      print $0
    }
  ' | sort -u
}

# Extract bullets from the scope-list section of the doc into a sorted-unique
# set, partitioned by the pinned mode-selection intro sentences.
# Usage: extract_doc_list orch
#        extract_doc_list deleg
extract_doc_list() {
  local which="$1"
  tr -d '\r' < "$DOC_FILE" | awk -v which="$which" '
    # Entry rule MUST precede exit rule (FINDING_1 — prevents the entry line
    # itself being shadowed by the "exit on ## heading" rule).
    /^### Scope list$/ { in_scope=1; mode=""; next }
    # Exit only on top-level ## — not ### — so any future ### inside becomes
    # detectable drift rather than silent partition (FINDING_6).
    /^## / && in_scope { exit }
    !in_scope { next }
    # Mode-selection on the two pinned literal intro sentences.
    /^The banner MUST appear in these orchestrator SKILL\.md files:$/ { mode="orch"; next }
    /^The banner MUST NOT appear in pure-delegator SKILL\.md files:$/ { mode="deleg"; next }
    # Bullet extraction. Strip trailing whitespace first (FINDING_5) so
    # editor noise after the closing backtick does not silently drop a path.
    {
      line=$0
      gsub(/[[:space:]]+$/, "", line)
      if (line ~ /^- `skills\/[^`]+\/SKILL\.md`$/) {
        if (mode == which) {
          # Strip leading "- `" (4 chars including backtick) and trailing "`".
          sub(/^- `/, "", line)
          sub(/`$/, "", line)
          print line
        }
      }
    }
  ' | sort -u
}

emit_diff() {
  local label="$1"
  local harness_file="$2"
  local doc_file="$3"

  local only_in_harness only_in_doc
  only_in_harness=$(comm -23 "$harness_file" "$doc_file" || true)
  only_in_doc=$(comm -13 "$harness_file" "$doc_file" || true)

  if [[ -z "$only_in_harness" && -z "$only_in_doc" ]]; then
    echo "PASS: $label sets match (harness ↔ doc)"
    PASS_COUNT=$((PASS_COUNT + 1))
    return 0
  fi

  echo "FAIL: $label sets drift between scripts/test-anti-halt-banners.sh and skills/shared/subskill-invocation.md:" >&2
  if [[ -n "$only_in_harness" ]]; then
    echo "  only in harness array ($label):" >&2
    printf '%s\n' "$only_in_harness" | sed 's/^/    /' >&2
  fi
  if [[ -n "$only_in_doc" ]]; then
    echo "  only in doc scope list ($label):" >&2
    printf '%s\n' "$only_in_doc" | sed 's/^/    /' >&2
  fi
  FAIL_COUNT=$((FAIL_COUNT + 1))
}

check_nonempty() {
  local label="$1"
  local file="$2"
  if [[ ! -s "$file" ]]; then
    echo "FAIL: $label parsed to empty set — check grammar assumptions in header comment of scripts/test-orchestrator-scope-sync.sh" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return 1
  fi
  echo "PASS: $label parsed $(wc -l < "$file" | tr -d ' ') entries"
  PASS_COUNT=$((PASS_COUNT + 1))
  return 0
}

tmpdir=""
cleanup() {
  if [[ -n "$tmpdir" && -d "$tmpdir" ]]; then
    rm -rf "$tmpdir"
  fi
}
trap cleanup EXIT

main() {
  check_file_exists "scripts/test-anti-halt-banners.sh" || exit 1
  check_file_exists "skills/shared/subskill-invocation.md" || exit 1

  tmpdir=$(mktemp -d)

  extract_harness_array ORCHESTRATORS > "$tmpdir/harness-orch.txt"
  extract_harness_array DELEGATORS    > "$tmpdir/harness-del.txt"
  extract_doc_list orch               > "$tmpdir/doc-orch.txt"
  extract_doc_list deleg              > "$tmpdir/doc-del.txt"

  # Fail-closed empty check on each of the four sets BEFORE set-equality
  # comparison — guards against both-empty "sets equal, silent PASS".
  check_nonempty "harness ORCHESTRATORS" "$tmpdir/harness-orch.txt" || true
  check_nonempty "harness DELEGATORS"    "$tmpdir/harness-del.txt"  || true
  check_nonempty "doc orchestrator list" "$tmpdir/doc-orch.txt"     || true
  check_nonempty "doc delegator list"    "$tmpdir/doc-del.txt"      || true

  # Only run set-equality if all four sets are non-empty.
  if [[ -s "$tmpdir/harness-orch.txt" && -s "$tmpdir/doc-orch.txt" ]]; then
    emit_diff "orchestrator" "$tmpdir/harness-orch.txt" "$tmpdir/doc-orch.txt"
  fi
  if [[ -s "$tmpdir/harness-del.txt" && -s "$tmpdir/doc-del.txt" ]]; then
    emit_diff "delegator" "$tmpdir/harness-del.txt" "$tmpdir/doc-del.txt"
  fi

  echo "----"
  echo "PASS_COUNT=$PASS_COUNT  FAIL_COUNT=$FAIL_COUNT"

  if [[ $FAIL_COUNT -gt 0 ]]; then
    exit 1
  fi
}

main "$@"
