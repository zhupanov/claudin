#!/usr/bin/env bash
# find-lock-issue.sh — Find an eligible issue, lock it, and rename it to [IN PROGRESS].
#
# Combined Find + Lock + Rename pipeline invoked by /fix-issue Step 0. Runs
# three operations in sequence:
#   1. Find candidate (eligibility scan or explicit-issue verification).
#   2. Acquire the comment-based concurrency lock by delegating to
#      issue-lifecycle.sh comment --lock (verifies tail GO, deletes GO,
#      posts "IN PROGRESS", post-checks for duplicate IN PROGRESS races).
#      The comment lock is the correctness invariant.
#   3. Rename the issue title to "[IN PROGRESS] <title>" by delegating to
#      tracking-issue-write.sh rename --state in-progress. Best-effort: a
#      rename failure does NOT undo the lock — the script still exits 0
#      with LOCK_ACQUIRED=true RENAMED=false. /implement Step 0.5 Branch 2
#      is the safety net (idempotent re-attempt on the next run-segment).
#
# Without --issue: lists open issues, checks each for the "GO" sentinel as
# the last comment, excludes issues locked with "IN PROGRESS", excludes
# issues blocked by other open issues (via GitHub's native issue dependencies
# and prose blockers), excludes issues whose titles start with a managed
# lifecycle prefix ([IN PROGRESS], [DONE], [STALLED]), and emits the first
# match (oldest first).
#
# With --issue: targets a specific issue (by number or GitHub URL), verifies
# it is open, does not carry a managed lifecycle title prefix, has "GO" as
# the last comment, and has no currently-open blocking dependencies.
#
# Two orthogonal mechanisms coexist:
#   1) Comment-based "IN PROGRESS" lock — concurrency control on the
#      fix-issue subject issue. Acquired here at /fix-issue Step 0 (last
#      comment = exactly "IN PROGRESS"); cleared when work completes.
#      Prevents two concurrent /fix-issue runners from picking the same
#      subject.
#   2) Title-based "[IN PROGRESS]" / "[DONE]" / "[STALLED]" lifecycle —
#      machine-owned tracking-issue state. Applied here at lock time so
#      the title reflects active work immediately, instead of the
#      multi-minute delay incurred when only /implement Step 0.5 Branch 2
#      did the rename. /implement still re-attempts the rename idempotently
#      so /implement remains standalone-correct when invoked with --issue
#      against a non-pre-marked issue.
#
# Usage:
#   find-lock-issue.sh [<number-or-url>]
#   find-lock-issue.sh [--issue <number-or-url>]  (deprecated)
#
# Output (KEY=value lines on stdout):
#   ELIGIBLE=true|false
#   ISSUE_NUMBER=<N>          (when ELIGIBLE=true)
#   ISSUE_TITLE=<title>       (when ELIGIBLE=true)
#   LOCK_ACQUIRED=true|false  (true on exit 0; false on exit 3 — lock-fail)
#   RENAMED=true|false        (when LOCK_ACQUIRED=true; false = idempotent
#                              no-op OR rename API failure; rename errors
#                              additionally surfaced on stderr)
#   ERROR=<message>           (when ELIGIBLE=false and exit 2, or when exit 3)
#
# Exit codes:
#   0 — eligible issue found, comment lock acquired (rename may have failed
#       best-effort — RENAMED=false signals this on stdout)
#   1 — no eligible issues (auto-pick mode only)
#   2 — error: gh CLI failure, or explicit issue not eligible
#   3 — eligible issue found but comment lock could not be acquired
#       (concurrent runner won the race, or GO sentinel changed between
#       eligibility scan and lock attempt)
#
# Stdout contract policy: delegate stdout (issue-lifecycle.sh, tracking-
# issue-write.sh) is captured into local shell variables and parsed
# key-by-key; never streamed. find-lock-issue.sh emits ONLY the keys
# declared above. Auxiliary delegate keys (COMMENTED, FAILED, NEW_TITLE,
# etc.) are filtered out so the SKILL.md parser sees a clean unified
# contract.

set -euo pipefail

# Returns 0 if the title starts with a managed lifecycle prefix
# ("[IN PROGRESS] ", "[DONE] ", "[STALLED] "), 1 otherwise. Anchored at
# the start; trailing-space-sensitive (matches the helper exactly — no
# fuzzy match, so user titles containing the literal substring "[IN
# PROGRESS]" mid-text are NOT excluded).
has_managed_prefix() {
    local t="$1"
    case "$t" in
        '[IN PROGRESS] '*) return 0 ;;
        '[DONE] '*)        return 0 ;;
        '[STALLED] '*)     return 0 ;;
        *)                 return 1 ;;
    esac
}

ISSUE_ARG=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --issue)
            echo "WARNING: --issue is deprecated; pass the issue number or URL as a positional argument instead." >&2
            if [[ $# -lt 2 ]]; then
                echo "ELIGIBLE=false"
                echo "ERROR=--issue requires a value"
                exit 2
            fi
            ISSUE_ARG="$2"; shift 2
            ;;
        -*)
            echo "ELIGIBLE=false"
            echo "ERROR=Unknown option: $1"
            exit 2
            ;;
        *)
            # Positional argument: issue number or URL
            if [[ -n "$ISSUE_ARG" ]]; then
                echo "ELIGIBLE=false"
                echo "ERROR=Unexpected extra argument: $1 (issue already set to $ISSUE_ARG)"
                exit 2
            fi
            ISSUE_ARG="$1"; shift
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Resolve repo identity
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ELIGIBLE=false"
    echo "ERROR=Failed to resolve repository name"
    exit 2
}

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

# ---------------------------------------------------------------------------
# lock_and_rename_then_emit <issue-num> <issue-title>
#
# Acquires the comment lock by delegating to issue-lifecycle.sh comment --lock,
# then attempts a best-effort title rename via tracking-issue-write.sh rename
# --state in-progress. Emits the unified stdout contract and exits.
#
# Stdout filtering: delegate stdout is captured into local variables and parsed
# key-by-key. Only the unified contract keys (ELIGIBLE, ISSUE_NUMBER,
# ISSUE_TITLE, LOCK_ACQUIRED, RENAMED, ERROR) are echoed. Auxiliary delegate
# keys (COMMENTED, FAILED, NEW_TITLE, etc.) are filtered out so the SKILL.md
# parser sees a clean contract.
#
# set -e guards: the lock and rename calls are wrapped with `|| <var>=$?` so
# a non-zero exit from the delegate does not prematurely abort find-lock-
# issue.sh under `set -euo pipefail` — the script must still emit its own
# unified contract before exiting.
#
# Exit codes (terminal — does not return):
#   0  — lock acquired (rename may have succeeded or failed best-effort)
#   3  — eligibility passed but lock acquisition failed
# ---------------------------------------------------------------------------
lock_and_rename_then_emit() {
    local issue_num="$1"
    local issue_title="$2"
    local script_dir lock_script rename_script
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    lock_script="${script_dir}/issue-lifecycle.sh"
    rename_script="${script_dir}/../../../scripts/tracking-issue-write.sh"

    # ---- Step 2: acquire comment lock (correctness invariant) ----
    local lock_out lock_exit=0
    lock_out=$("$lock_script" comment --issue "$issue_num" --body "IN PROGRESS" --lock 2>&1) || lock_exit=$?

    # Parse LOCK_ACQUIRED and ERROR from delegate stdout. Use awk's last-line-
    # wins for each key so the same key appearing multiple times resolves to
    # the final value. Auxiliary keys (COMMENTED, etc.) are not extracted.
    local lock_acquired lock_error
    lock_acquired=$(echo "$lock_out" | awk -F= '/^LOCK_ACQUIRED=/ { v=$2 } END { print v }')
    lock_error=$(echo "$lock_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')

    if [ "$lock_acquired" != "true" ] || [ "$lock_exit" -ne 0 ]; then
        # Lock failed. Surface the unified contract; preserve eligibility
        # signal so callers can distinguish "no candidate" from "candidate
        # found but lost the race".
        echo "ELIGIBLE=true"
        echo "ISSUE_NUMBER=$issue_num"
        echo "ISSUE_TITLE=$issue_title"
        echo "LOCK_ACQUIRED=false"
        if [ -n "$lock_error" ]; then
            echo "ERROR=$lock_error"
        else
            echo "ERROR=Lock acquisition failed (issue-lifecycle.sh exit $lock_exit)"
        fi
        exit 3
    fi

    # ---- Step 3: rename title (best-effort) ----
    local rename_out rename_exit=0 renamed=false rename_error=""
    rename_out=$("$rename_script" rename --issue "$issue_num" --state in-progress 2>&1) || rename_exit=$?

    # Parse RENAMED (true/false). RENAMED=false is BOTH the idempotent no-op
    # path AND the failure path; distinguish via FAILED= or non-zero exit.
    local rename_failed
    renamed=$(echo "$rename_out" | awk -F= '/^RENAMED=/ { v=$2 } END { print v }')
    rename_failed=$(echo "$rename_out" | awk -F= '/^FAILED=/ { v=$2 } END { print v }')
    rename_error=$(echo "$rename_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')

    if [ "$rename_exit" -ne 0 ] || [ "$rename_failed" = "true" ]; then
        # Rename failed. Best-effort: lock is the correctness boundary; do
        # not undo it. Surface the failure on stderr; emit RENAMED=false on
        # stdout. /implement Step 0.5 Branch 2's idempotent rename is the
        # safety net.
        if [ -n "$rename_error" ]; then
            echo "WARNING: title rename failed for issue #$issue_num: $rename_error" >&2
        else
            echo "WARNING: title rename failed for issue #$issue_num (tracking-issue-write.sh exit $rename_exit)" >&2
        fi
        renamed="false"
    fi

    # Normalize: empty (older script versions or unexpected output) → false.
    if [ -z "$renamed" ]; then
        renamed="false"
    fi

    # ---- Emit unified contract ----
    echo "ELIGIBLE=true"
    echo "ISSUE_NUMBER=$issue_num"
    echo "ISSUE_TITLE=$issue_title"
    echo "LOCK_ACQUIRED=true"
    echo "RENAMED=$renamed"
    exit 0
}

# ---------------------------------------------------------------------------
# Explicit issue mode (--issue provided)
# ---------------------------------------------------------------------------
if [[ -n "$ISSUE_ARG" ]]; then
    # gh issue view accepts both bare numbers and full GitHub URLs natively.
    # For URLs, it resolves the repo from the URL — we must verify it matches
    # the current repo to prevent cross-repo misoperation.
    ISSUE_JSON=$(gh issue view "$ISSUE_ARG" --json number,state,title,url 2>/dev/null) || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch issue (invalid number, URL, or inaccessible): $ISSUE_ARG"
        exit 2
    }

    ISSUE_NUM=$(echo "$ISSUE_JSON" | jq -r '.number')
    ISSUE_STATE=$(echo "$ISSUE_JSON" | jq -r '.state')
    ISSUE_TITLE=$(echo "$ISSUE_JSON" | jq -r '.title')
    ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.url // empty')

    # Verify issue belongs to the current repo by parsing owner/repo from the
    # issue URL (format: https://github.com/OWNER/REPO/issues/N).
    if [[ -z "$ISSUE_URL" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Cannot verify repository ownership for issue: $ISSUE_ARG"
        exit 2
    fi
    ISSUE_REPO=$(echo "$ISSUE_URL" | sed -n 's|https://github.com/\([^/]*/[^/]*\)/issues/.*|\1|p')
    if [[ -z "$ISSUE_REPO" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Cannot parse repository from issue URL: $ISSUE_URL"
        exit 2
    fi
    if [[ "$ISSUE_REPO" != "$REPO" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue belongs to $ISSUE_REPO, not the current repo ($REPO)"
        exit 2
    fi

    # Verify issue is open
    if [ "$ISSUE_STATE" != "OPEN" ]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is not open (state: $ISSUE_STATE)"
        exit 2
    fi

    # Exclude issues with a managed lifecycle title prefix
    # ([IN PROGRESS] / [DONE] / [STALLED]). These are machine-owned
    # tracking issues (/implement, /improve-skill, /loop-improve-skill),
    # not candidates for /fix-issue automated work. Placed BEFORE the
    # comment pagination to save API calls on an obviously-excluded
    # issue.
    if has_managed_prefix "$ISSUE_TITLE"; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM has a managed lifecycle title prefix ([IN PROGRESS] / [DONE] / [STALLED]); not a fix-issue candidate"
        exit 2
    fi

    # Verify last comment is GO.
    # Using --slurp so `jq` sees a single array-of-arrays and can select the
    # globally-last comment via `add // [] | .[-1]`. The older `--jq '.[-1].body'`
    # pattern ran the filter per page and was only accidentally correct because
    # the last page contains the globally-last comment. See `prose_open_blockers`
    # above for the canonical reference use of this pattern.
    LAST_COMMENT=$(gh api --paginate --slurp "repos/${REPO}/issues/${ISSUE_NUM}/comments" 2>/dev/null \
        | jq -r 'add // [] | .[-1].body // empty') || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch comments for issue #$ISSUE_NUM"
        exit 2
    }

    TRIMMED=$(echo "$LAST_COMMENT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Reject with a lock-specific error when the issue is locked by a
    # concurrent /fix-issue run. Mirrors the auto-pick path's IN PROGRESS
    # skip below; without this branch the GO check would still reject but
    # with the misleading "not approved" framing.
    if [ "$TRIMMED" = "IN PROGRESS" ]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is locked by another /fix-issue run (last comment: IN PROGRESS)"
        exit 2
    fi

    if [ "$TRIMMED" != "GO" ]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is not approved (last comment: ${TRIMMED:-empty})"
        exit 2
    fi

    BLOCKERS=$(all_open_blockers "$ISSUE_NUM")
    if [ -n "$BLOCKERS" ]; then
        # Format as comma-separated #N list for the error message
        FORMATTED=$(echo "$BLOCKERS" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
        echo "ELIGIBLE=false"
        echo "ERROR=Issue #$ISSUE_NUM is blocked by open dependencies: $FORMATTED"
        exit 2
    fi

    # Eligibility confirmed — acquire lock + best-effort title rename, emit
    # unified contract, exit (terminal).
    lock_and_rename_then_emit "$ISSUE_NUM" "$ISSUE_TITLE"
fi

# ---------------------------------------------------------------------------
# Auto-pick mode (no --issue): scan open issues oldest-first
#
# Use `gh api --paginate` so there is no fixed cap — `gh issue list --limit N`
# has no "unlimited" sentinel (0 and -1 are rejected), and a hardcoded ceiling
# silently starves older issues once a repo exceeds it. The REST issues
# endpoint returns PRs alongside issues; filter them with
# `select(.pull_request == null)` since `gh issue list` does this implicitly.
# ---------------------------------------------------------------------------
ISSUES_JSONL=$(gh api --paginate "repos/${REPO}/issues?state=open&per_page=100" \
    --jq '.[] | select(.pull_request == null) | {number, title}' 2>/dev/null) || {
    echo "ELIGIBLE=false"
    echo "ERROR=Failed to list issues"
    exit 2
}

# Sort by number ascending (oldest first) and iterate. `-s` slurps the JSONL
# stream emitted by `--jq '.[]'` into an array so we can sort it.
SORTED=$(echo "$ISSUES_JSONL" | jq -s -c 'sort_by(.number) | .[]')

if [ -z "$SORTED" ]; then
    echo "ELIGIBLE=false"
    exit 1
fi

while IFS= read -r issue_row; do
    ISSUE_NUM=$(echo "$issue_row" | jq -r '.number')
    ISSUE_TITLE=$(echo "$issue_row" | jq -r '.title')

    # Skip issues with a managed lifecycle title prefix
    # ([IN PROGRESS] / [DONE] / [STALLED]) — machine-owned tracking
    # issues, not fix-issue candidates. Placed BEFORE the comment
    # pagination to save one API round-trip per excluded issue.
    if has_managed_prefix "$ISSUE_TITLE"; then
        echo "Skipping issue #$ISSUE_NUM: managed lifecycle title prefix" >&2
        continue
    fi

    # Get the globally-last comment body. See the explicit-issue path above for
    # the rationale on `--slurp` + `add // [] | .[-1]`.
    LAST_COMMENT=$(gh api --paginate --slurp "repos/${REPO}/issues/${ISSUE_NUM}/comments" 2>/dev/null \
        | jq -r 'add // [] | .[-1].body // empty') || {
        echo "ELIGIBLE=false"
        echo "ERROR=Failed to fetch comments for issue #$ISSUE_NUM"
        exit 2
    }

    # Trim whitespace for strict comparison
    TRIMMED=$(echo "$LAST_COMMENT" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

    # Skip if last comment is IN PROGRESS (locked by another run)
    if [ "$TRIMMED" = "IN PROGRESS" ]; then
        continue
    fi

    # Check if last comment is exactly GO (case-sensitive)
    if [ "$TRIMMED" = "GO" ]; then
        BLOCKERS=$(all_open_blockers "$ISSUE_NUM")
        if [ -n "$BLOCKERS" ]; then
            # Blocked by at least one open dependency — log on stderr and keep scanning.
            FORMATTED=$(echo "$BLOCKERS" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
            echo "Skipping issue #$ISSUE_NUM: blocked by open dependencies ($FORMATTED)" >&2
            continue
        fi
        # Eligibility confirmed — acquire lock + best-effort title rename, emit
        # unified contract, exit (terminal).
        lock_and_rename_then_emit "$ISSUE_NUM" "$ISSUE_TITLE"
    fi
done <<< "$SORTED"

# No eligible issues found
echo "ELIGIBLE=false"
exit 1
