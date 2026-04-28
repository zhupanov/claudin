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
# match. Selection order is two-key: titles matching the whole word "urgent"
# (case-insensitive, word-boundary regex — does NOT match "non-urgent")
# come first, then within each tier oldest-first by issue number. The
# preference is a soft re-ordering, not an eligibility filter — a non-
# Urgent issue is still picked when no Urgent eligible candidate exists.
#
# With --issue: targets a specific issue (by number or GitHub URL), verifies
# it is open, runs umbrella detection FIRST (issue #819 DECISION_1 — if the
# issue is an umbrella, the umbrella branch is taken and managed-prefix
# rejection is bypassed so umbrellas with `[IN PROGRESS]` / `[DONE]` /
# `[STALLED]` titles remain explicitly targetable), then for non-umbrellas
# verifies the title does not carry a managed lifecycle title prefix, has
# "GO" as the last comment, and has no currently-open blocking dependencies.
# Auto-pick path is intentionally NOT mirrored — it excludes umbrellas
# regardless of order.
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
#   ISSUE_NUMBER=<N>          (when ELIGIBLE=true; on the umbrella-dispatch
#                              path, this is the CHOSEN CHILD's number)
#   ISSUE_TITLE=<title>       (when ELIGIBLE=true; the chosen child's title
#                              on the umbrella-dispatch path)
#   LOCK_ACQUIRED=true|false  (true on exit 0; false on exit 3 — lock-fail —
#                              and false on exit 4 — umbrella complete, no
#                              lock attempted)
#   RENAMED=true|false        (when LOCK_ACQUIRED=true; false = idempotent
#                              no-op OR rename API failure; rename errors
#                              additionally surfaced on stderr)
#   ERROR=<message>           (when ELIGIBLE=false and exit 2, or when exit 3,
#                              or when exit 5 — no eligible umbrella child)
#
#   Umbrella-only keys (FINDING_1 from the umbrella-PR plan review — emitted
#   ONLY when the umbrella detector returned IS_UMBRELLA=true):
#   IS_UMBRELLA=true          (only on umbrella paths — exit 0 dispatch,
#                              exit 3 child-lock-fail, exit 4 complete,
#                              exit 5 no-eligible-child)
#   UMBRELLA_NUMBER=<U>       (the umbrella issue number; ALWAYS absent on
#                              non-umbrella paths and on auto-pick exits)
#   UMBRELLA_TITLE=<title>    (umbrella's title, when IS_UMBRELLA=true)
#   UMBRELLA_ACTION           (one of: dispatched | complete | no-eligible-
#                              child — describes the umbrella outcome)
#
# Exit codes:
#   0 — eligible issue found, comment lock acquired. On umbrella paths,
#       UMBRELLA_ACTION=dispatched and ISSUE_NUMBER refers to the chosen
#       child (rename may have failed best-effort — RENAMED=false signals).
#   1 — no eligible issues (auto-pick mode only)
#   2 — error: gh CLI failure, or explicit issue not eligible (or umbrella
#       blocked by open dependencies)
#   3 — eligible issue found but comment lock could not be acquired
#       (concurrent runner won the race, or GO sentinel changed between
#       eligibility scan and lock attempt; on umbrella paths, the failure
#       is on the chosen child and ERROR carries umbrella context)
#   4 — umbrella complete: all parsed children are CLOSED. SKILL.md Step 0
#       invokes finalize-umbrella.sh on this path. ELIGIBLE=true with
#       LOCK_ACQUIRED=false (no lock; finalization is a different state
#       transition).
#   5 — umbrella detected but has no eligible child (some children open but
#       all blocked / locked / managed-prefixed, OR zero parseable children
#       found in the umbrella body — FINDING_3). ELIGIBLE=false, ERROR
#       carries the blocking reason.
#
# Stdout contract policy: delegate stdout (issue-lifecycle.sh, tracking-
# issue-write.sh) is captured into local shell variables and parsed
# key-by-key; never streamed. find-lock-issue.sh emits ONLY the keys
# declared above. Auxiliary delegate keys (COMMENTED, FAILED, NEW_TITLE,
# etc.) are filtered out so the SKILL.md parser sees a clean unified
# contract.
#
# Umbrella support (explicit-issue path only — auto-pick mode never selects
# umbrellas, per the design dialectic's DECISION_1):
#   When the explicit issue is detected as an umbrella (body literal
#   "Umbrella tracking issue." OR title — case-sensitive, after stripping
#   zero or more leading bracket-blocks of the form `[...]` and/or `(...)`
#   per #819 — that begins with `Umbrella: ` or `Umbrella — `), delegate to
#   umbrella-handler.sh to either:
#     - dispatch to the next-eligible child (pick-child returns CHILD_NUMBER),
#       lock the CHILD using --lock-no-go (no GO required), rename the CHILD
#       to [IN PROGRESS]. Emit IS_UMBRELLA=true UMBRELLA_NUMBER=<U>
#       UMBRELLA_TITLE=<T> UMBRELLA_ACTION=dispatched alongside the existing
#       ISSUE_NUMBER (= child) keys. Exit 0.
#     - finalize the umbrella when all parsed children are CLOSED
#       (pick-child returns ALL_CLOSED=true). Emit IS_UMBRELLA=true
#       UMBRELLA_NUMBER=<U> UMBRELLA_TITLE=<T> UMBRELLA_ACTION=complete.
#       Exit 4. SKILL.md Step 0 invokes finalize-umbrella.sh.
#     - report no-eligible-child (pick-child returns NO_ELIGIBLE_CHILD).
#       Emit IS_UMBRELLA=true UMBRELLA_NUMBER=<U> UMBRELLA_ACTION=
#       no-eligible-child + ERROR=<reason>. Exit 5.
#   On child lock failure, emit exit 3 with ERROR carrying the umbrella
#   context ("Failed to lock chosen child #C of umbrella #U: <reason>").
#   UMBRELLA_NUMBER is emitted ONLY when an umbrella was detected — absent
#   on the normal (non-umbrella) explicit-issue exit-0 path AND on auto-pick
#   exits, per FINDING_1 from the umbrella-PR plan review.

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
# lock_no_go_and_rename_then_emit_for_child <child-num> <child-title>
#                                           <umbrella-num> <umbrella-title>
#
# Umbrella child-dispatch lock path. Same shape as
# lock_and_rename_then_emit (above), but uses issue-lifecycle.sh comment
# --lock-no-go (no GO requirement) and emits the unified contract WITH
# umbrella-context keys (IS_UMBRELLA, UMBRELLA_NUMBER, UMBRELLA_TITLE,
# UMBRELLA_ACTION=dispatched).
#
# On child lock failure, exits 3 with an ERROR string that names BOTH the
# child and the umbrella so SKILL.md Step 0's exit-3 branch can present a
# clear error to the operator.
# ---------------------------------------------------------------------------
lock_no_go_and_rename_then_emit_for_child() {
    local child_num="$1"
    local child_title="$2"
    local umbrella_num="$3"
    local umbrella_title="$4"
    local script_dir lock_script rename_script
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    lock_script="${script_dir}/issue-lifecycle.sh"
    rename_script="${script_dir}/../../../scripts/tracking-issue-write.sh"

    # ---- Lock without GO ----
    local lock_out lock_exit=0
    lock_out=$("$lock_script" comment --issue "$child_num" --body "IN PROGRESS" --lock-no-go 2>&1) || lock_exit=$?

    local lock_acquired lock_error
    lock_acquired=$(echo "$lock_out" | awk -F= '/^LOCK_ACQUIRED=/ { v=$2 } END { print v }')
    lock_error=$(echo "$lock_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')

    if [ "$lock_acquired" != "true" ] || [ "$lock_exit" -ne 0 ]; then
        echo "ELIGIBLE=true"
        echo "IS_UMBRELLA=true"
        echo "UMBRELLA_NUMBER=$umbrella_num"
        echo "UMBRELLA_TITLE=$umbrella_title"
        echo "ISSUE_NUMBER=$child_num"
        echo "ISSUE_TITLE=$child_title"
        echo "LOCK_ACQUIRED=false"
        if [ -n "$lock_error" ]; then
            echo "ERROR=Failed to lock chosen child #$child_num of umbrella #$umbrella_num: $lock_error"
        else
            echo "ERROR=Failed to lock chosen child #$child_num of umbrella #$umbrella_num (issue-lifecycle.sh exit $lock_exit)"
        fi
        exit 3
    fi

    # ---- Rename the child to [IN PROGRESS] (best-effort) ----
    local rename_out rename_exit=0 renamed=false rename_error=""
    rename_out=$("$rename_script" rename --issue "$child_num" --state in-progress 2>&1) || rename_exit=$?
    local rename_failed
    renamed=$(echo "$rename_out" | awk -F= '/^RENAMED=/ { v=$2 } END { print v }')
    rename_failed=$(echo "$rename_out" | awk -F= '/^FAILED=/ { v=$2 } END { print v }')
    rename_error=$(echo "$rename_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')
    if [ "$rename_exit" -ne 0 ] || [ "$rename_failed" = "true" ]; then
        if [ -n "$rename_error" ]; then
            echo "WARNING: title rename failed for child #$child_num (umbrella #$umbrella_num): $rename_error" >&2
        else
            echo "WARNING: title rename failed for child #$child_num (umbrella #$umbrella_num) (tracking-issue-write.sh exit $rename_exit)" >&2
        fi
        renamed="false"
    fi
    if [ -z "$renamed" ]; then
        renamed="false"
    fi

    # ---- Emit unified contract ----
    echo "ELIGIBLE=true"
    echo "IS_UMBRELLA=true"
    echo "UMBRELLA_NUMBER=$umbrella_num"
    echo "UMBRELLA_TITLE=$umbrella_title"
    echo "UMBRELLA_ACTION=dispatched"
    echo "ISSUE_NUMBER=$child_num"
    echo "ISSUE_TITLE=$child_title"
    echo "LOCK_ACQUIRED=true"
    echo "RENAMED=$renamed"
    exit 0
}

# ---------------------------------------------------------------------------
# handle_umbrella <umbrella-num> <umbrella-title>
#
# Invoked from the explicit-issue path AFTER the umbrella detector has
# returned IS_UMBRELLA=true. Calls umbrella-handler.sh pick-child and
# branches on the outcome:
#   - CHILD_NUMBER → lock_no_go_and_rename_then_emit_for_child (terminal)
#   - ALL_CLOSED   → emit exit-4 contract (SKILL.md finalizes umbrella)
#   - NO_ELIGIBLE_CHILD → emit exit-5 contract
# ---------------------------------------------------------------------------
handle_umbrella() {
    local umbrella_num="$1"
    local umbrella_title="$2"
    local script_dir handler_script
    script_dir="$(dirname "${BASH_SOURCE[0]}")"
    handler_script="${script_dir}/umbrella-handler.sh"

    local pick_out pick_exit=0
    pick_out=$("$handler_script" pick-child --issue "$umbrella_num" 2>&1) || pick_exit=$?
    if [ "$pick_exit" -ne 0 ]; then
        local err
        err=$(echo "$pick_out" | awk -F= '/^ERROR=/ { sub(/^ERROR=/, "", $0); v=$0 } END { print v }')
        echo "ELIGIBLE=false"
        echo "IS_UMBRELLA=true"
        echo "UMBRELLA_NUMBER=$umbrella_num"
        echo "ERROR=Failed to pick child for umbrella #$umbrella_num: ${err:-pick-child failed}"
        exit 2
    fi
    local child_number child_title all_closed no_eligible blocking_reason
    child_number=$(echo "$pick_out" | awk -F= '/^CHILD_NUMBER=/ { v=$2 } END { print v }')
    child_title=$(echo "$pick_out" | awk -F= '/^CHILD_TITLE=/ { sub(/^CHILD_TITLE=/, "", $0); v=$0 } END { print v }')
    all_closed=$(echo "$pick_out" | awk -F= '/^ALL_CLOSED=/ { v=$2 } END { print v }')
    no_eligible=$(echo "$pick_out" | awk -F= '/^NO_ELIGIBLE_CHILD=/ { v=$2 } END { print v }')
    blocking_reason=$(echo "$pick_out" | awk -F= '/^BLOCKING_REASON=/ { sub(/^BLOCKING_REASON=/, "", $0); v=$0 } END { print v }')

    if [ -n "$child_number" ]; then
        # Before locking the child, run the same blocker check we would for
        # any explicit issue. all_open_blockers is fail-open on API errors
        # (see its docstring above), so a blocker check that returns empty
        # could mean either "no blockers" or "API blip" — same posture as
        # the existing explicit-issue path uses for non-umbrella issues.
        local child_blockers
        child_blockers=$(all_open_blockers "$child_number")
        if [ -n "$child_blockers" ]; then
            local formatted
            formatted=$(echo "$child_blockers" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
            echo "ELIGIBLE=false"
            echo "IS_UMBRELLA=true"
            echo "UMBRELLA_NUMBER=$umbrella_num"
            echo "UMBRELLA_ACTION=no-eligible-child"
            echo "ERROR=Umbrella #$umbrella_num child #$child_number is blocked by open dependencies: $formatted"
            exit 5
        fi
        lock_no_go_and_rename_then_emit_for_child "$child_number" "$child_title" "$umbrella_num" "$umbrella_title"
        # terminal — exits 0 or 3
    fi
    if [ "$all_closed" = "true" ]; then
        echo "ELIGIBLE=true"
        echo "IS_UMBRELLA=true"
        echo "UMBRELLA_NUMBER=$umbrella_num"
        echo "UMBRELLA_TITLE=$umbrella_title"
        echo "UMBRELLA_ACTION=complete"
        echo "LOCK_ACQUIRED=false"
        exit 4
    fi
    if [ "$no_eligible" = "true" ]; then
        echo "ELIGIBLE=false"
        echo "IS_UMBRELLA=true"
        echo "UMBRELLA_NUMBER=$umbrella_num"
        echo "UMBRELLA_ACTION=no-eligible-child"
        echo "ERROR=Umbrella #$umbrella_num has no eligible child: ${blocking_reason:-no blocking reason given}"
        exit 5
    fi
    # Defensive: pick-child should always emit one of the three outcomes.
    echo "ELIGIBLE=false"
    echo "IS_UMBRELLA=true"
    echo "UMBRELLA_NUMBER=$umbrella_num"
    echo "ERROR=umbrella-handler.sh pick-child returned no recognized outcome"
    exit 2
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
    # issue URL. Host is intentionally not pinned to github.com so the parser
    # works for GitHub Enterprise / self-hosted GHE deployments too — the
    # cross-repo guard below (ISSUE_REPO != REPO) is the actual safety net,
    # since $REPO already comes from `gh repo view` in the current repo. The
    # `gh` CLI always emits `https://` URLs (no plain `http://`), so a literal
    # `https://` keeps the regex BRE-compatible across BSD sed / GNU sed.
    if [[ -z "$ISSUE_URL" ]]; then
        echo "ELIGIBLE=false"
        echo "ERROR=Cannot verify repository ownership for issue: $ISSUE_ARG"
        exit 2
    fi
    ISSUE_REPO=$(echo "$ISSUE_URL" | sed -n 's|https://[^/]*/\([^/]*/[^/]*\)/issues/.*|\1|p')
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

    # Umbrella detection (explicit-issue path only — auto-pick mode never
    # runs this; per the design dialectic's DECISION_1, auto-pick keeps its
    # GO-tail invariant). Detection runs BEFORE both the managed-prefix
    # early-reject AND the GO-tail check so umbrella issues do NOT need a
    # GO comment AND so umbrella titles carrying a managed lifecycle prefix
    # (e.g. `[IN PROGRESS] Umbrella: foo`, `[DONE] Umbrella: foo`,
    # `[STALLED] Umbrella: foo`) reach the umbrella dispatcher. Without
    # this ordering, `is_umbrella_title`'s post-#819 bracket-prefix peel
    # would be unreachable in the explicit-target path for hand-authored
    # umbrellas without the body literal — see issue #819 design DECISION_1
    # (voted, 2-1) for the rationale. Auto-pick path is intentionally NOT
    # mirrored: auto-pick excludes umbrellas regardless of order. The
    # umbrella's body literal AND/OR title prefix is the approval signal —
    # children inherit approval from the umbrella's existence.
    UMBRELLA_HANDLER="$(dirname "${BASH_SOURCE[0]}")/umbrella-handler.sh"
    if [[ -x "$UMBRELLA_HANDLER" ]]; then
        UMBRELLA_DETECT_OUT=""
        if UMBRELLA_DETECT_OUT=$("$UMBRELLA_HANDLER" detect --issue "$ISSUE_NUM" 2>&1); then
            IS_UMBRELLA_DETECT=$(echo "$UMBRELLA_DETECT_OUT" | awk -F= '/^IS_UMBRELLA=/ { v=$2 } END { print v }')
            if [ "$IS_UMBRELLA_DETECT" = "true" ]; then
                # Apply the umbrella's own blocker check (parallel to non-
                # umbrella behavior — an umbrella that is itself blocked by
                # an open issue should not dispatch). The umbrella's parsed
                # children are filtered out of the blocker set: per #716,
                # /umbrella now wires native child→umbrella edges so each
                # open child appears in the umbrella's blocked_by, but the
                # umbrella is meant to be GATED on its children (and
                # handle_umbrella dispatches them) — not deadlocked. Only
                # blockers that are NOT parsed children of this umbrella
                # count as umbrella-blockers.
                #
                # Bypass `all_open_blockers` here: it short-circuits on
                # any native blocker without ever consulting prose blockers
                # (see all_open_blockers comment block above), which would
                # let an umbrella with native child-blockers + a separate
                # prose blocker pass our filter and dispatch incorrectly.
                # Fetch native and prose independently, filter children
                # only from native, then union before deciding eligibility.
                NATIVE_BLOCKERS=$(native_open_blockers "$ISSUE_NUM")
                if [ -n "$NATIVE_BLOCKERS" ]; then
                    set +e
                    LIST_CHILDREN_OUT=$("$UMBRELLA_HANDLER" list-children --issue "$ISSUE_NUM" 2>/dev/null)
                    LIST_CHILDREN_EXIT=$?
                    set -e
                    if [ "$LIST_CHILDREN_EXIT" -ne 0 ]; then
                        echo "WARNING: list-children failed for umbrella #$ISSUE_NUM (exit $LIST_CHILDREN_EXIT) — children-filter degraded; native blockers not filtered" >&2
                    fi
                    UMBRELLA_CHILDREN=$(echo "$LIST_CHILDREN_OUT" | awk -F= '/^CHILDREN=/ { v=$2 } END { print v }')
                    FILTERED_NATIVE=""
                    for b in $NATIVE_BLOCKERS; do
                        is_child="false"
                        for c in $UMBRELLA_CHILDREN; do
                            if [ "$b" = "$c" ]; then
                                is_child="true"
                                break
                            fi
                        done
                        if [ "$is_child" = "false" ]; then
                            FILTERED_NATIVE="$FILTERED_NATIVE $b"
                        fi
                    done
                    NATIVE_BLOCKERS=$(echo "$FILTERED_NATIVE" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
                fi
                PROSE_BLOCKERS=$(prose_open_blockers "$ISSUE_NUM")
                # Union + dedupe (sort -u tolerates leading/trailing space and
                # an empty-line input from concatenated empty sets). The
                # `grep -v '^$'` filter exits 1 when given all-empty input
                # (zero matches), which under `set -euo pipefail` would abort
                # the script and silently swallow the umbrella with no
                # blockers — `|| true` brackets the filter so empty unions
                # propagate as empty strings instead of fatal exits.
                BLOCKERS=$(printf '%s %s' "$NATIVE_BLOCKERS" "$PROSE_BLOCKERS" \
                    | tr ' ' '\n' | { grep -v '^$' || true; } | sort -u -n \
                    | tr '\n' ' ' | sed 's/[[:space:]]*$//')
                if [ -n "$BLOCKERS" ]; then
                    FORMATTED=$(echo "$BLOCKERS" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
                    echo "ELIGIBLE=false"
                    echo "IS_UMBRELLA=true"
                    echo "UMBRELLA_NUMBER=$ISSUE_NUM"
                    echo "ERROR=Umbrella #$ISSUE_NUM is blocked by open dependencies: $FORMATTED"
                    exit 2
                fi
                handle_umbrella "$ISSUE_NUM" "$ISSUE_TITLE"
                # terminal — exits 0/3/4/5
            fi
        fi
    fi

    # Exclude issues with a managed lifecycle title prefix
    # ([IN PROGRESS] / [DONE] / [STALLED]). These are machine-owned
    # tracking issues (/implement, /improve-skill, /loop-improve-skill),
    # not candidates for /fix-issue automated work. Runs AFTER umbrella
    # detection (per #819 DECISION_1) so an umbrella whose title carries
    # a managed-prefix (e.g. `[IN PROGRESS] Umbrella: foo`) reaches
    # `handle_umbrella` above and never falls through here.
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
# Auto-pick mode (no --issue): scan open issues — Urgent-first, then
# oldest-first within each tier (see the two-key sort comment below).
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

# Sort with two keys, then iterate. `-s` slurps the JSONL stream emitted by
# `--jq '.[]'` into an array so we can sort it.
#
# Sort keys (jq sorts arrays lexicographically; false < true for booleans):
#   1. (title | test("(?<![-A-Za-z0-9_])urgent(?![-A-Za-z0-9_])"; "i") | not)
#      — Urgent-tagged issues (case-insensitive whole-word match anywhere in
#      the title, with hyphens treated as word-internal so "non-urgent" is
#      NOT a match) get `false` and sort BEFORE non-Urgent issues. The
#      explicit lookaround character class `[-A-Za-z0-9_]` is required
#      because jq's Oniguruma regex (a) does not accept `\w` inside a
#      lookbehind ("invalid pattern in look-behind"), and (b) jq's `\b`
#      word boundary treats `-` as a non-word char, so `\burgent\b` would
#      match "non-urgent" — producing the wrong tier. The class is
#      deliberately broader than `\b`: it rejects compound forms like
#      "non-urgent", "insurgent", and "urgently" (the last because the
#      following `l` is in the class, so the lookahead fails).
#   2. .number ascending — within each preference tier, fall back to the
#      pre-existing oldest-first selection order.
#
# The preference is a soft signal: it only changes the order in which
# candidates are evaluated, not which candidates are eligible. A non-Urgent
# eligible issue is still picked when no Urgent eligible issue exists.
SORTED=$(echo "$ISSUES_JSONL" | jq -s -c 'sort_by([((.title // "") | test("(?<![-A-Za-z0-9_])urgent(?![-A-Za-z0-9_])"; "i") | not), .number]) | .[]')

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
        # Auto-pick must NEVER select umbrella issues, per the design dialectic
        # DECISION_1 (voted 2-1 ANTI_THESIS): umbrella handling is restricted to
        # the explicit-issue path. Even when /umbrella --go posts GO on the
        # umbrella itself, the auto-pick scan must skip it — otherwise the
        # umbrella body text would be sent to /implement as a normal feature
        # spec, defeating the umbrella state machine. Operators wanting umbrella
        # children processed must explicitly invoke `/fix-issue <umbrella#>`.
        UMBRELLA_HANDLER="$(dirname "${BASH_SOURCE[0]}")/umbrella-handler.sh"
        if [[ -x "$UMBRELLA_HANDLER" ]]; then
            UMBRELLA_DETECT_OUT=""
            if UMBRELLA_DETECT_OUT=$("$UMBRELLA_HANDLER" detect --issue "$ISSUE_NUM" 2>/dev/null); then
                IS_UMBRELLA_DETECT=$(echo "$UMBRELLA_DETECT_OUT" | awk -F= '/^IS_UMBRELLA=/ { v=$2 } END { print v }')
                if [ "$IS_UMBRELLA_DETECT" = "true" ]; then
                    echo "Skipping issue #$ISSUE_NUM: umbrella issue (auto-pick excludes umbrellas; use \`/fix-issue $ISSUE_NUM\` to dispatch a child)" >&2
                    continue
                fi
            fi
            # detect failure (non-zero exit) — fail-open: treat as non-umbrella
            # and continue with the standard auto-pick flow rather than
            # blocking the queue. The explicit-issue path's handler-missing
            # branch is the user-facing diagnostic surface; auto-pick is best-
            # effort.
        fi
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
