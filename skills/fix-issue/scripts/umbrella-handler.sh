#!/usr/bin/env bash
# umbrella-handler.sh — Detect umbrella issues, enumerate their children, pick
# the next eligible child for /fix-issue dispatch.
#
# Invoked by skills/fix-issue/scripts/find-lock-issue.sh in the explicit-issue
# path (auto-pick mode never selects umbrellas — DECISION_1 from the design
# dialectic). The handler owns three decisions:
#   1. Is this issue an umbrella?
#   2. What are its children, in body order?
#   3. Which child is next-eligible for /fix-issue to lock and process?
#
# Subcommands:
#   detect       --issue N
#   list-children --issue N
#   pick-child   --issue N
#
# Detection (title-only, post-#846):
#   A title where, after stripping zero or more leading bracket-blocks of the
#   form `[...]` and/or `(...)` (each with optional surrounding whitespace)
#   via a bounded peel loop (cap=16, fail-closed on unbalanced/unclosed
#   leading bracket), the remainder starts with `Umbrella: ` or `Umbrella — `
#   — case-sensitive. The marker matches both /umbrella-created umbrellas
#   (orchestrator-composed summaries conventionally start with "Umbrella:",
#   not code-enforced — see existing umbrellas #774, #773, #770, #784) and
#   hand-authored umbrellas like #348, including titles that already carry
#   an operator tag (e.g. `[IN PROGRESS] Umbrella: foo`,
#   `(urgent) Umbrella: foo`). The body is NOT consulted — see
#   `is_umbrella_title` (below) for the implementation and the sibling
#   `umbrella-handler.md` Detection section for the full grammar contract
#   (non-nesting, cap=16, silent fail-closed). Body-based detection was
#   removed in #846 because the prior substring match on the literal
#   `Umbrella tracking issue.` produced false positives on issues that
#   *quoted* the marker in prose or code spans (e.g., #753).
#
# Child enumeration grammar (DECISION_3 — task-list checklist only):
#   Only matches markdown task-list items with a same-repo `#N` reference:
#     ^[[:space:]]*- \[[ xX]\] .*#([0-9]+)
#   Captures both /umbrella-rendered children ("- [ ] #N — title") and
#   hand-authored operator checklists ("- [ ] /fix-issue executes #N" as in
#   #348). Same-repo only — the regex requires `#<digits>` not preceded by `/`,
#   so `owner/repo#150` is NOT matched. Self-references (the umbrella's own
#   number) are filtered out so an umbrella that mentions itself in its body
#   cannot create a self-deadlock. Children are deduplicated, preserving
#   first-occurrence body order.
#
# pick-child eligibility (no GO required on children — children inherit
# approval from the umbrella's own existence as the approval signal):
#   - issue is OPEN
#   - title does not start with a managed lifecycle prefix
#     ([IN PROGRESS] / [DONE] / [STALLED])
#   - last comment is NOT exactly "IN PROGRESS" (not locked by a concurrent
#     /fix-issue runner)
#   - child_native_blockers is empty — the native-only blocker probe
#     (defined below, called from child_eligible) so pick-child iterates past
#     natively-blocked siblings to the next ready child. The full
#     all_open_blockers (native + prose) pass is owned by find-lock-issue.sh
#     and runs once on the chosen child before locking — defense in depth
#     on top of the native-only filter inside pick-child.
#
# pick-child outcomes (one of three on stdout):
#   CHILD_NUMBER=<C>
#   CHILD_TITLE=<T>            ← first eligible child; caller proceeds to lock
#
#   ALL_CLOSED=true             ← every parsed child is CLOSED; caller
#                                 finalizes umbrella (FINDING_3: requires
#                                 AT LEAST ONE child parsed)
#
#   NO_ELIGIBLE_CHILD=true
#   BLOCKING_REASON=<one-line>  ← children exist but none are pickable, OR
#                                 zero parseable children found (FINDING_3
#                                 — explicitly NOT vacuous-truth ALL_CLOSED)
#
# All subcommands fail-closed: gh CLI errors propagate to non-zero exit with
# ERROR= on stdout. Detection alone (`detect`) is fail-closed too — if `gh`
# can't fetch the issue, we cannot decide and must surface the failure to the
# caller (find-lock-issue.sh already exits 2 on its own gh failures).
#
# Exit codes:
#   0 — success (subcommand-specific stdout)
#   1 — gh API error or other internal failure
#   2 — usage error

set -euo pipefail

# ---------------------------------------------------------------------------
# Resolve repo identity (shared across subcommands)
# ---------------------------------------------------------------------------
REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || {
    echo "ERROR=Failed to resolve repository name"
    exit 1
}

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# is_umbrella_title — return 0 if the title, after stripping zero or more
# leading bracket-blocks of the form [...] and/or (...) (each with optional
# surrounding whitespace), starts with "Umbrella: " or "Umbrella — "
# (case-sensitive). The trailing space-or-em-dash distinguishes the marker
# prefix from a leading word like "Umbrellas" or "Umbrella-Like".
#
# Grammar: an arbitrary sequence of `[...]` and `(...)` peeled left-to-right,
# bounded by an iteration cap of 16 (defensive guard against pathological
# titles). Bracket blocks are non-nesting — the peel finds the FIRST `]` or
# `)` after the opening delimiter; nested bracket content within a block
# (e.g., `[outer [inner] outer]`) is intentionally NOT supported (false
# negative — see `umbrella-handler.md` Title-grammar limitations).
# Fail-closed on unbalanced/unclosed leading bracket: `is_umbrella_title`
# returns 1 (NOT umbrella). Callers (cmd_detect) treat any non-zero return
# as "not umbrella" — the malformed-bracket case is intentionally
# indistinguishable from the standard non-match on stdout (no `ERROR=`
# emitted; see umbrella-handler.md silent-fail-closed contract note).
#
# Positive examples (#819): "Umbrella: foo", "[IN PROGRESS] Umbrella: foo",
# "[IN PROGRESS] (urgent) Umbrella: foo".
# Negative examples (#819): "[IN PROGRESS] Do something umbrella related"
# (Umbrella not at front after prefix strip), "/umbrella ..." (lowercase /
# command syntax).
is_umbrella_title() {
    local title="$1"
    local remainder="$title"
    local i=0
    while [ "$i" -lt 16 ]; do
        i=$((i + 1))
        # Strip leading whitespace.
        remainder="${remainder#"${remainder%%[![:space:]]*}"}"
        case "$remainder" in
            '['*)
                # Find first ']' after the opening '['.
                local after_open="${remainder#?}"
                case "$after_open" in
                    *']'*)
                        # Strip up to and including the first ']'.
                        remainder="${after_open#*]}"
                        ;;
                    *)
                        # Unclosed '[' → fail-closed.
                        return 1
                        ;;
                esac
                ;;
            '('*)
                local after_open="${remainder#?}"
                case "$after_open" in
                    *')'*)
                        remainder="${after_open#*)}"
                        ;;
                    *)
                        return 1
                        ;;
                esac
                ;;
            *)
                break
                ;;
        esac
    done
    # If we exhausted the cap without exiting via 'break' or an explicit
    # return, the title had >16 bracket blocks — treat as not umbrella.
    case "$remainder" in
        '['*|'('*) return 1 ;;
    esac
    # Strip leading whitespace before the marker check.
    remainder="${remainder#"${remainder%%[![:space:]]*}"}"
    case "$remainder" in
        'Umbrella: '*)  return 0 ;;
        'Umbrella — '*) return 0 ;;
        *)              return 1 ;;
    esac
}

# has_managed_prefix — same shape as find-lock-issue.sh's helper. Returns 0
# if the title starts with [IN PROGRESS] / [DONE] / [STALLED] followed by a
# single space.
has_managed_prefix() {
    local t="$1"
    case "$t" in
        '[IN PROGRESS] '*) return 0 ;;
        '[DONE] '*)        return 0 ;;
        '[STALLED] '*)     return 0 ;;
        *)                 return 1 ;;
    esac
}

# fetch_issue_basics — fetches title and body for a single issue in one gh
# call. Sets shell variables ISSUE_TITLE and ISSUE_BODY on success. Returns
# non-zero on gh failure (caller surfaces ERROR=). State is not consumed by
# any current caller (umbrella detection happens BEFORE the explicit-issue
# OPEN check in find-lock-issue.sh, so the umbrella's own state has already
# been verified by the time `detect` is invoked). If a future caller needs
# state, fetch it explicitly via gh issue view --json state in that caller.
fetch_issue_basics() {
    local n="$1"
    local json
    json=$(gh issue view "$n" --json title,body --jq '{title, body}' 2>/dev/null) || return 1
    ISSUE_TITLE=$(printf '%s' "$json" | jq -r '.title // ""')
    ISSUE_BODY=$(printf '%s' "$json" | jq -r '.body // ""')
}

# parse_children_from_body — given an umbrella body (stdin) and the umbrella's
# own issue number ($1), emit one child issue number per line in body-order
# first-occurrence dedup. Same-repo only: the grep pattern requires the `#`
# to appear after whitespace or `(` (so "owner/repo#150" — where `/` precedes
# `#` — does not match). Self-references are filtered.
#
# DECISION_3 grammar: only markdown task-list items
#   ^[[:space:]]*- \[[ x]\] .*#([0-9]+)
parse_children_from_body() {
    local self_num="$1"
    local body
    body=$(cat)
    # Step 1: keep only task-list lines.
    # GNU grep on Linux/macOS supports -E. The pattern is:
    #   start-of-line + optional whitespace + "- [" + (space|x|X) + "] "
    local task_lines
    task_lines=$({ printf '%s\n' "$body" | grep -E '^[[:space:]]*- \[[ xX]\]' ; } 2>/dev/null || true)
    if [[ -z "$task_lines" ]]; then
        return 0
    fi
    # Step 2: extract `#N` references that are NOT preceded by `/`. We use a
    # two-pass approach:
    #   (a) convert any `<owner/repo>#N` patterns into a sentinel that we will
    #       drop;
    #   (b) extract `#N` tokens.
    # Simpler: use sed to delete same-line cross-repo segments before the
    # extraction, leaving only same-repo `#N` matches.
    local same_repo
    same_repo=$(printf '%s\n' "$task_lines" \
        | sed -E 's@[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+#[0-9]+@@g')
    # Step 3: extract `#<digits>` matches and emit numbers.
    local nums
    nums=$({ printf '%s\n' "$same_repo" | grep -oE '#[0-9]+' | sed -E 's/^#//' ; } 2>/dev/null || true)
    if [[ -z "$nums" ]]; then
        return 0
    fi
    # Step 4: dedup preserving first-occurrence order, drop self-reference.
    awk -v self="$self_num" '
        $0 == self { next }
        !seen[$0]++ { print $0 }
    ' <<< "$nums"
}

# child_native_blockers — minimal blocker probe inlined into umbrella-handler
# so pick-child can iterate past blocked children rather than aborting on the
# first one. Mirrors find-lock-issue.sh's `native_open_blockers` exactly:
# queries GitHub's blocked_by dependency API with --paginate + per-page jq
# filter; emits a space-separated list of OPEN blocker issue numbers (empty
# = no native blockers known); fail-open on API failure (returns empty +
# exit 0). The full prose-blocker scan from find-lock-issue.sh is NOT
# duplicated here — pick-child uses native blockers only as a cheap
# proportionate filter, and the caller (find-lock-issue.sh handle_umbrella)
# applies the full all_open_blockers (native + prose) once on the chosen
# child as a final guard before locking. This keeps umbrella-handler.sh
# focused without re-implementing the full blocker pipeline.
child_native_blockers() {
    local num="$1"
    local nums
    nums=$(gh api --paginate "repos/${REPO}/issues/${num}/dependencies/blocked_by" \
        --jq '.[] | select(.state == "open") | .number' 2>/dev/null) || return 0
    echo "$nums" | tr '\n' ' ' | sed 's/[[:space:]]*$//'
}

# child_eligible — returns 0 if the child issue is eligible for dispatch; 1
# otherwise. Sets CHILD_TITLE on eligibility-success or BLOCKING_REASON on
# ineligibility (closed cases excluded — those are checked by the caller).
#
# Eligibility:
#   - state == OPEN
#   - title does NOT start with a managed lifecycle prefix
#   - last comment is NOT exactly "IN PROGRESS"
#   - child_native_blockers returns empty (no open native blockers)
# Native blocker check is INSIDE child_eligible so pick-child iterates past
# blocked children to the next ready one (FINDING_5 from the umbrella-PR
# code-review panel). The caller still runs the full all_open_blockers
# (native + prose) on the chosen child once before locking — this is
# defense in depth: prose blockers are rare on /umbrella-rendered children
# and the redundant final check costs at most one paginated comment fetch.
child_eligible() {
    local n="$1"
    local title state
    local json
    json=$(gh issue view "$n" --json title,state --jq '{title, state}' 2>/dev/null) || {
        BLOCKING_REASON="failed to fetch issue #$n"
        return 1
    }
    title=$(printf '%s' "$json" | jq -r '.title // ""')
    state=$(printf '%s' "$json" | jq -r '.state // ""')
    if [[ "$state" != "OPEN" ]]; then
        BLOCKING_REASON="child #$n is not OPEN (state=$state)"
        return 1
    fi
    if has_managed_prefix "$title"; then
        BLOCKING_REASON="child #$n has managed lifecycle title prefix"
        return 1
    fi
    # Last comment check
    local last_comment trimmed
    last_comment=$(gh api --paginate --slurp "repos/${REPO}/issues/${n}/comments" 2>/dev/null \
        | jq -r 'add // [] | .[-1].body // ""') || {
        BLOCKING_REASON="failed to fetch comments for #$n"
        return 1
    }
    trimmed=$(printf '%s' "$last_comment" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    if [[ "$trimmed" == "IN PROGRESS" ]]; then
        BLOCKING_REASON="child #$n is locked (last comment: IN PROGRESS)"
        return 1
    fi
    # Native blocker check (FINDING_5) — pick-child must iterate past
    # blocked children, not abort on the first one.
    local blockers
    blockers=$(child_native_blockers "$n")
    if [[ -n "$blockers" ]]; then
        local formatted
        formatted=$(echo "$blockers" | tr ' ' '\n' | sed 's/^/#/' | paste -sd ',' -)
        BLOCKING_REASON="child #$n is blocked by open dependencies: $formatted"
        return 1
    fi
    CHILD_TITLE="$title"
    return 0
}

# ---------------------------------------------------------------------------
# Subcommand: detect
# ---------------------------------------------------------------------------
cmd_detect() {
    local issue=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            *) echo "ERROR=Unknown option for detect: $1"; exit 2 ;;
        esac
    done
    if [[ -z "$issue" ]]; then
        echo "ERROR=Usage: umbrella-handler.sh detect --issue N"
        exit 2
    fi
    fetch_issue_basics "$issue" || {
        echo "ERROR=Failed to fetch issue #$issue"
        exit 1
    }
    # Title-only detection (post-#846 — body is no longer consulted).
    if is_umbrella_title "$ISSUE_TITLE"; then
        echo "IS_UMBRELLA=true"
        echo "UMBRELLA_TITLE=$ISSUE_TITLE"
        return 0
    fi
    echo "IS_UMBRELLA=false"
}

# ---------------------------------------------------------------------------
# Subcommand: list-children
# ---------------------------------------------------------------------------
cmd_list_children() {
    local issue=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            *) echo "ERROR=Unknown option for list-children: $1"; exit 2 ;;
        esac
    done
    if [[ -z "$issue" ]]; then
        echo "ERROR=Usage: umbrella-handler.sh list-children --issue N"
        exit 2
    fi
    fetch_issue_basics "$issue" || {
        echo "ERROR=Failed to fetch issue #$issue"
        exit 1
    }
    local children
    children=$(printf '%s' "$ISSUE_BODY" | parse_children_from_body "$issue")
    if [[ -z "$children" ]]; then
        echo "CHILDREN="
        return 0
    fi
    # Single-line space-separated representation for downstream parsing.
    local joined
    joined=$(printf '%s\n' "$children" | tr '\n' ' ' | sed 's/[[:space:]]*$//')
    echo "CHILDREN=$joined"
}

# ---------------------------------------------------------------------------
# Subcommand: pick-child
# ---------------------------------------------------------------------------
cmd_pick_child() {
    local issue=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --issue) issue="${2:?--issue requires a value}"; shift 2 ;;
            *) echo "ERROR=Unknown option for pick-child: $1"; exit 2 ;;
        esac
    done
    if [[ -z "$issue" ]]; then
        echo "ERROR=Usage: umbrella-handler.sh pick-child --issue N"
        exit 2
    fi
    fetch_issue_basics "$issue" || {
        echo "ERROR=Failed to fetch issue #$issue"
        exit 1
    }
    local children
    children=$(printf '%s' "$ISSUE_BODY" | parse_children_from_body "$issue")
    # FINDING_3: zero parsed children is NOT vacuous ALL_CLOSED — emit
    # NO_ELIGIBLE_CHILD with a specific reason.
    if [[ -z "$children" ]]; then
        echo "NO_ELIGIBLE_CHILD=true"
        echo "BLOCKING_REASON=no parseable children found in umbrella body"
        return 0
    fi
    # Walk children in body order. Track per-child state for the aggregate
    # ALL_CLOSED test. Any child whose state is not CLOSED makes ALL_CLOSED
    # false. The first eligible (open + not-blocked-equivalent) child wins.
    local all_closed=true
    local first_blocking_reason=""
    local first_blocking_set=false
    while IFS= read -r child_num; do
        [[ -z "$child_num" ]] && continue
        local cstate cjson
        cjson=$(gh issue view "$child_num" --json state,title --jq '{state,title}' 2>/dev/null) || {
            # Treat fetch failures as ineligible-but-not-closed (defensive).
            all_closed=false
            if ! $first_blocking_set; then
                first_blocking_reason="failed to fetch child #$child_num"
                first_blocking_set=true
            fi
            continue
        }
        cstate=$(printf '%s' "$cjson" | jq -r '.state // ""')
        if [[ "$cstate" == "CLOSED" ]]; then
            continue
        fi
        # Open child — try eligibility.
        all_closed=false
        if child_eligible "$child_num"; then
            echo "CHILD_NUMBER=$child_num"
            echo "CHILD_TITLE=$CHILD_TITLE"
            return 0
        fi
        if ! $first_blocking_set; then
            first_blocking_reason="${BLOCKING_REASON:-child #$child_num ineligible}"
            first_blocking_set=true
        fi
    done <<< "$children"
    # Walked all children without finding an eligible one.
    if $all_closed; then
        # FINDING_3: at least one child was parsed AND all were CLOSED.
        echo "ALL_CLOSED=true"
        return 0
    fi
    # Some children open but none eligible.
    echo "NO_ELIGIBLE_CHILD=true"
    echo "BLOCKING_REASON=${first_blocking_reason:-no eligible child found}"
}

# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------
if [[ $# -lt 1 ]]; then
    echo "ERROR=Usage: umbrella-handler.sh <detect|list-children|pick-child> --issue N"
    exit 2
fi

SUBCOMMAND="$1"
shift

case "$SUBCOMMAND" in
    detect)        cmd_detect "$@" ;;
    list-children) cmd_list_children "$@" ;;
    pick-child)    cmd_pick_child "$@" ;;
    *)             echo "ERROR=Unknown subcommand: $SUBCOMMAND"; exit 2 ;;
esac
