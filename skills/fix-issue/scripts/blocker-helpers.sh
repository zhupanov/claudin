#!/usr/bin/env bash
# blocker-helpers.sh — shared blocker-resolution helpers for /fix-issue.
#
# Sourced by both skills/fix-issue/scripts/find-lock-issue.sh and
# skills/fix-issue/scripts/umbrella-handler.sh. Owns the canonical
# implementations of `native_open_blockers`, `prose_open_blockers`, and
# `all_open_blockers` so both scripts apply the same native+prose dependency
# semantics to a candidate issue.
#
# This library is sourced-only — it is never executed directly. Callers MUST:
#   1. Set REPO (e.g., via `gh repo view`) BEFORE sourcing or before calling
#      any function defined here. Functions read `$REPO` at call time.
#   2. Run with `set -euo pipefail`. The functions below are written to be
#      safe under that pragma (empty-pipeline edges produce empty output, not
#      pipefail aborts).
#   3. Tolerate a missing or unreadable library file: an unguarded `source`
#      under `set -e` aborts the script before any stdout contract is emitted,
#      breaking callers that parse `KEY=VALUE` output. Both find-lock-issue.sh
#      and umbrella-handler.sh wrap their `source` call with explicit failure
#      handling so the documented `ELIGIBLE=false ERROR=...` (or per-subcommand
#      equivalent) contract is preserved on load failure.
#
# All functions follow a fail-open posture: any gh / parser / state-lookup
# failure degrades to "no blockers known" (empty output, exit 0). The
# rationale is intentional — dependency-API availability must not become a
# hard gate on the automation. The Known Limitations sections in
# skills/fix-issue/SKILL.md document the user-visible consequences.

# ---------------------------------------------------------------------------
# native_open_blockers <issue-number>
#
# Queries GitHub's native issue-dependencies API and prints a space-separated
# list of open blocker issue numbers (e.g., "42 57") on stdout. Empty output
# means no open blockers known via this source — the caller may still consult
# `prose_open_blockers` before declaring the issue eligible.
#
# API errors (404 on repos without the dependencies feature, transient gh
# failures) are treated as "no blockers known": the function prints nothing
# and returns 0. Rationale: do not let dependency-API availability become a
# hard gate on the automation — if the feature isn't used or is unreachable,
# fall back to pre-existing behavior (GO sentinel alone).
# ---------------------------------------------------------------------------
native_open_blockers() {
    local num="$1"
    local nums
    # Use --paginate with --jq so the filter runs per page and outputs are concatenated
    # (one number per line). Using --paginate without --jq returns one JSON array per
    # page as separate documents, and `jq '.[] ...'` only consumes the first — missing
    # blockers beyond the default page size.
    nums=$(gh api --paginate "repos/${REPO}/issues/${num}/dependencies/blocked_by" \
        --jq '.[] | select(.state == "open") | .number' 2>/dev/null) || return 0
    # Collapse newline-separated numbers into a single space-separated line, trimming trailing whitespace.
    echo "$nums" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# prose_open_blockers <issue-number>
#
# Scans the issue body and every comment body (fetched separately — see
# note below) for the conservative prose-dependency keyword set, resolves
# each referenced same-repo issue's current state, and prints a space-
# separated list of referenced issues that are currently OPEN.
#
# The parser helper at `skills/fix-issue/scripts/parse-prose-blockers.sh`
# handles the regex matching and number extraction — this function owns
# the orchestration (fetch → per-document iteration → state resolution).
#
# Per-document iteration (body separately from each comment) prevents
# cross-document match fabrication: concatenating all bodies into one
# stream would let a body ending with "Depends on" plus a comment starting
# with "#123" fabricate a dependency that neither document actually states.
#
# Every boundary (body fetch, comments fetch, parser invocation, per-ref
# state lookup) is fail-open: any failure degrades to "no additional
# prose blockers known", mirroring `native_open_blockers`'s contract.
#
# Self-references (the candidate's own number) are filtered out so an
# issue that mentions itself in prose cannot create a self-deadlock.
# ---------------------------------------------------------------------------
prose_open_blockers() {
    local num="$1"
    local parser_script
    parser_script="$(dirname "${BASH_SOURCE[0]}")/parse-prose-blockers.sh"

    # If the parser is missing (should never happen in a shipped install),
    # fail open silently.
    if [[ ! -x "$parser_script" ]]; then
        return 0
    fi

    # Fetch the issue body and all comment bodies. Failures at either fetch
    # degrade to empty — the prose path then contributes no blockers.
    local body comments_array
    body=$(gh issue view "$num" --json body --jq '.body // ""' 2>/dev/null) || body=""
    comments_array=$(gh api --paginate --slurp "repos/${REPO}/issues/${num}/comments" 2>/dev/null \
        | jq 'add // []' 2>/dev/null) || comments_array="[]"

    # Accumulate extracted numbers across documents. The parser is invoked
    # ONCE PER DOCUMENT (body, then each comment body separately) so a
    # body ending with "Depends on" plus a comment starting with "#123"
    # cannot fabricate a cross-document match.
    local refs=""

    if [[ -n "$body" ]]; then
        local body_refs
        body_refs=$(printf '%s' "$body" | "$parser_script" 2>/dev/null) || body_refs=""
        if [[ -n "$body_refs" ]]; then
            refs="$refs"$'\n'"$body_refs"
        fi
    fi

    local count
    count=$(echo "$comments_array" | jq 'length' 2>/dev/null) || count=0
    local i=0
    while [[ $i -lt $count ]]; do
        local comment_body comment_refs
        comment_body=$(echo "$comments_array" | jq -r ".[$i].body // \"\"" 2>/dev/null) || comment_body=""
        if [[ -n "$comment_body" ]]; then
            comment_refs=$(printf '%s' "$comment_body" | "$parser_script" 2>/dev/null) || comment_refs=""
            if [[ -n "$comment_refs" ]]; then
                refs="$refs"$'\n'"$comment_refs"
            fi
        fi
        i=$((i + 1))
    done

    # Dedupe across all documents, drop the candidate's own number to prevent
    # self-deadlock, and resolve each remaining number's state.
    local unique_refs
    unique_refs=$(echo "$refs" | grep -E '^[0-9]+$' | sort -u -n | grep -v "^${num}$" || true)

    local open_list=""
    while IFS= read -r ref; do
        [[ -z "$ref" ]] && continue
        local state
        state=$(gh issue view "$ref" --json state --jq '.state' 2>/dev/null) || continue
        if [[ "$state" == "OPEN" ]]; then
            open_list="$open_list $ref"
        fi
    done <<< "$unique_refs"

    # Trim leading/trailing whitespace for consistent output with native_open_blockers.
    echo "$open_list" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

# ---------------------------------------------------------------------------
# all_open_blockers <issue-number>
#
# Unions the native-dependency and prose-dependency blocker sets, dedupes,
# and returns a space-separated list of OPEN blocker issue numbers.
#
# Short-circuit optimization: if `native_open_blockers` returns a non-empty
# list, the prose path is skipped entirely. The issue is already ineligible,
# so resolving prose blockers would only add API volume without changing the
# decision. The documented tradeoff is that user-visible skip/error messages
# may list only the native blocker numbers when both sources apply — see
# skills/fix-issue/SKILL.md Known Limitations. Closing all listed native
# blockers and re-running /fix-issue will surface any remaining prose
# blockers on the next run.
# ---------------------------------------------------------------------------
all_open_blockers() {
    local num="$1"
    local native prose
    native=$(native_open_blockers "$num")
    if [[ -n "$native" ]]; then
        # Short-circuit: issue is already ineligible by native check.
        echo "$native"
        return 0
    fi
    prose=$(prose_open_blockers "$num")
    # Native is empty; prose is the whole set. Dedupe defensively in case
    # prose_open_blockers emits duplicates (it doesn't currently, but the
    # dedupe is cheap).
    if [[ -n "$prose" ]]; then
        echo "$prose" | tr ' ' '\n' | sort -u -n | tr '\n' ' ' | sed 's/[[:space:]]*$//'
    fi
}
