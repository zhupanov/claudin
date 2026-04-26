#!/usr/bin/env bash
# allocate-candidates.sh — Apply per-item floor + confidence-ranked spillover
# selection to /issue Phase 1 Tier-1 candidate flags, under a hard 30-cap.
#
# Resolves issue #554: previously the union CANDIDATES list was capped at 30
# globally with no per-item floor, so early items in a batch could exhaust all
# 30 Phase 2 slots and starve later items of deep-dedup coverage.
#
# Reads CAND rows from stdin (one per line):
#
#   CAND <item-i> <issue-N> <kind:dup|dep|both> <confidence:high|medium|low>
#
# Writes EXACTLY ONE line to stdout on success (exit 0):
#
#   CANDIDATES=<comma-separated issue numbers, ascending>
#
# All diagnostics (parse warnings, dropped-row notices, N>30 warning) go to
# stderr. Stdout MUST stay parseable by the calling SKILL prompt.
#
# Algorithm (single normative source: skills/issue/scripts/allocate-candidates.md):
#   N = --total-items value (count of NON-MALFORMED items per /issue Step 3).
#   F = 0 if N>30 else min(3, floor(30/N)).
#   Pass A (floor reservation): process items in ascending item index. Within
#     each item, sort the item's valid CAND rows by confidence-desc, then
#     issue-asc. For each row: if the candidate is already in the union,
#     increment floor_credits[item] WITHOUT adding to the union (union-credit
#     semantics). Else if floor_credits[item] < F, add to union and increment
#     floor_credits for THIS item AND every other item that nominated this
#     candidate at any confidence. Stop adding for this item once
#     floor_credits[item] >= F.
#   Pass B (spillover): collect leftover (item, issue, confidence) tuples not
#     yet in the union; sort by confidence-desc → issue-asc → item-asc; add to
#     union until |union| == 30 or list exhausted.
#
# Defensive defaults (skip-with-warning, NOT abort):
#   - Non-numeric or out-of-range item index → drop row, stderr warning.
#   - Non-numeric issue number → drop row, stderr warning.
#   - Unknown kind → treat as `dup` (most conservative — preserves the row).
#   - Unknown / missing confidence → treat as `low` (most conservative position
#     in the ranking).
#
# Exit codes:
#   0  — success (including N=0, empty stdin, all-rows-dropped → CANDIDATES=).
#   1  — usage error only (missing or invalid --total-items).
#
# Bash 3.2-compatible: no `declare -A`, no `mapfile`, no `${var,,}` lowercasing.
# macOS /bin/bash is 3.2 and the rest of skills/issue/scripts/* avoids Bash 4+.
#
# Edit-in-sync rule: any change to CAND row schema, algorithm, defensive
# defaults, or exit-code semantics requires updating both this script AND
# skills/issue/scripts/allocate-candidates.md AND the SKILL.md Step 4 prose
# (worked examples, syntax line) in the same PR.

set -euo pipefail

N_TOTAL=""

usage() {
    echo "Usage: allocate-candidates.sh --total-items N" >&2
    echo "       (reads CAND rows from stdin, writes CANDIDATES= to stdout)" >&2
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --total-items)
            N_TOTAL="${2:?--total-items requires a value}"
            shift 2
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$N_TOTAL" ]]; then
    usage
    exit 1
fi

if ! [[ "$N_TOTAL" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --total-items must be a non-negative integer (got: $N_TOTAL)" >&2
    exit 1
fi

CAP=30

# Compute per-item floor F.
if (( N_TOTAL > CAP )); then
    F=0
    echo "**⚠ /issue: dedup batch exceeds 30 non-malformed items (N=$N_TOTAL); per-item floor disabled, 30 slots filled by confidence ranking only.**" >&2
elif (( N_TOTAL == 0 )); then
    # Nothing to allocate. Drain stdin defensively (don't error on broken pipe).
    cat >/dev/null || true
    echo "CANDIDATES="
    exit 0
else
    # min(3, floor(30/N))
    F_DIV=$(( CAP / N_TOTAL ))
    if (( F_DIV < 3 )); then
        F=$F_DIV
    else
        F=3
    fi
fi

# Read + validate stdin into a tmpfile of normalized rows:
#   <conf-rank> <item> <issue> <kind>
# where conf-rank is 3=high, 2=medium, 1=low. Sort/awk operate on this.
TMPDIR_LOCAL="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_LOCAL"' EXIT

ROWS_FILE="$TMPDIR_LOCAL/rows.tsv"
: > "$ROWS_FILE"

# Read every line from stdin; tolerate empty stdin (no-op).
DROPPED=0
while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim trailing CR (defensive against CRLF input).
    line="${line%$'\r'}"
    # Skip blank lines.
    [[ -z "$line" ]] && continue
    # Skip lines not starting with CAND (allow leading whitespace).
    # Strip leading whitespace (Bash 3.2-safe; no extglob required).
    trimmed="$line"
    while [[ "$trimmed" == [[:space:]]* ]]; do
        trimmed="${trimmed#?}"
    done
    [[ "$trimmed" != CAND\ * ]] && continue

    # Tokenize: expect 5 tokens (CAND item issue kind conf).
    # Use read -a for portable splitting (Bash 3.2 ok).
    set +e
    read -r -a TOK <<< "$trimmed"
    set -e

    if (( ${#TOK[@]} < 4 )); then
        # Need at least item + issue + kind. Confidence is optional (defaults to low).
        echo "**⚠ /issue: dropped malformed CAND row (too few fields): $line**" >&2
        DROPPED=$((DROPPED + 1))
        continue
    fi

    ITEM="${TOK[1]}"
    ISSUE="${TOK[2]}"
    KIND="${TOK[3]:-dup}"
    CONF="${TOK[4]:-low}"

    # Validate item index: numeric, 1..N_TOTAL inclusive.
    if ! [[ "$ITEM" =~ ^[0-9]+$ ]]; then
        echo "**⚠ /issue: dropped malformed CAND row (non-numeric item index): $line**" >&2
        DROPPED=$((DROPPED + 1))
        continue
    fi
    if (( ITEM < 1 || ITEM > N_TOTAL )); then
        echo "**⚠ /issue: dropped malformed CAND row (item index $ITEM out of range 1..$N_TOTAL): $line**" >&2
        DROPPED=$((DROPPED + 1))
        continue
    fi

    # Validate issue number: positive integer.
    if ! [[ "$ISSUE" =~ ^[1-9][0-9]*$ ]]; then
        echo "**⚠ /issue: dropped malformed CAND row (non-numeric or non-positive issue number): $line**" >&2
        DROPPED=$((DROPPED + 1))
        continue
    fi

    # Normalize kind: dup|dep|both pass through; anything else → dup.
    case "$KIND" in
        dup|dep|both) ;;
        *) KIND=dup ;;
    esac

    # Normalize confidence to numeric rank (3=high, 2=medium, 1=low).
    case "$CONF" in
        high)   CONF_RANK=3 ;;
        medium) CONF_RANK=2 ;;
        low)    CONF_RANK=1 ;;
        *)      CONF_RANK=1 ;;
    esac

    printf '%s\t%s\t%s\t%s\n' "$CONF_RANK" "$ITEM" "$ISSUE" "$KIND" >> "$ROWS_FILE"
done

# If no valid rows: empty CANDIDATES, exit 0.
if [[ ! -s "$ROWS_FILE" ]]; then
    echo "CANDIDATES="
    exit 0
fi

# Deduplicate (item, issue) pairs at the SAME row level — keep the
# highest-confidence row for each (item, issue). awk over rows sorted by
# (item asc, issue asc, conf-rank desc) → keep first per (item, issue).
DEDUP_FILE="$TMPDIR_LOCAL/rows_dedup.tsv"
sort -t$'\t' -k2,2n -k3,3n -k1,1nr "$ROWS_FILE" \
    | awk -F'\t' '!seen[$2"|"$3]++ { print }' > "$DEDUP_FILE"

# ----------------------------------------------------------------------
# Pass A — floor reservation.
# ----------------------------------------------------------------------
# Strategy with parallel arrays (Bash 3.2-safe):
#   FLOOR_CREDIT_FOR_ITEM_<i>=<n>  (track via a sparse array of files-per-item
#                                   in TMPDIR? simpler: keep a sentinel string).
# Since item indices are 1..N_TOTAL, we can use plain indexed arrays.

# Initialize floor_credits[1..N_TOTAL] = 0.
FLOOR=()
for ((i=0; i<=N_TOTAL; i++)); do
    FLOOR[i]=0
done

# Union: a list of issue numbers, plus a presence-set via a colon-delimited
# string for cheap membership tests (Bash 3.2 — no associative arrays).
UNION_LIST=""    # space-separated issue numbers
UNION_PRESENT=":"  # ":<issue>:<issue>:" for `case`-based membership test

union_contains() {
    case "$UNION_PRESENT" in
        *:"$1":*) return 0 ;;
        *)        return 1 ;;
    esac
}

union_add() {
    UNION_LIST="${UNION_LIST}${UNION_LIST:+ }$1"
    UNION_PRESENT="${UNION_PRESENT}$1:"
}

# Build a list of all (item, issue) tuples for "every item that nominated this
# candidate" lookup. We index by issue → list of items via a tmp file.
NOM_FILE="$TMPDIR_LOCAL/nominators.tsv"
# Format: <issue>\t<item>
awk -F'\t' '{ print $3 "\t" $2 }' "$DEDUP_FILE" | sort -u > "$NOM_FILE"

# nominators_for_issue prints space-separated item indices that nominated $1.
nominators_for_issue() {
    awk -F'\t' -v iss="$1" '$1 == iss { print $2 }' "$NOM_FILE" | tr '\n' ' '
}

if (( F > 0 )); then
    # Process items in ascending item order.
    for (( ITEM=1; ITEM<=N_TOTAL; ITEM++ )); do
        # For this item, get all of its rows sorted by conf-rank desc, issue asc.
        # awk filter: column 2 == ITEM. Sort by -k1,1nr (conf desc) then -k3,3n (issue asc).
        ITEM_ROWS="$TMPDIR_LOCAL/item_${ITEM}.tsv"
        awk -F'\t' -v it="$ITEM" '$2 == it { print }' "$DEDUP_FILE" \
            | sort -t$'\t' -k1,1nr -k3,3n > "$ITEM_ROWS"
        [[ ! -s "$ITEM_ROWS" ]] && continue

        while IFS=$'\t' read -r _CR_RANK _CR_ITEM CR_ISSUE _CR_KIND; do
            (( FLOOR[ITEM] >= F )) && break
            if union_contains "$CR_ISSUE"; then
                # Already in union — award floor credit without growing union.
                FLOOR[ITEM]=$(( FLOOR[ITEM] + 1 ))
                continue
            fi
            # Cap on union size: never exceed CAP (30).
            CUR_LEN=$(echo "$UNION_LIST" | wc -w | tr -d ' ')
            if (( CUR_LEN >= CAP )); then
                break 2  # break out of both inner while and outer for
            fi
            union_add "$CR_ISSUE"
            # Increment floor credit for every item that nominated this candidate
            # (union-credit semantics).
            for nom_item in $(nominators_for_issue "$CR_ISSUE"); do
                FLOOR[nom_item]=$(( FLOOR[nom_item] + 1 ))
            done
        done < "$ITEM_ROWS"
    done
fi

# ----------------------------------------------------------------------
# Pass B — spillover.
# ----------------------------------------------------------------------
# Collect leftover rows (whose issue is NOT yet in union); sort by
# conf-rank desc → issue asc → item asc; add to union until |union|=CAP.
CUR_LEN=$(echo "$UNION_LIST" | wc -w | tr -d ' ')
if (( CUR_LEN < CAP )); then
    LEFTOVER_FILE="$TMPDIR_LOCAL/leftover.tsv"
    : > "$LEFTOVER_FILE"
    while IFS=$'\t' read -r LR_RANK LR_ITEM LR_ISSUE LR_KIND; do
        if ! union_contains "$LR_ISSUE"; then
            printf '%s\t%s\t%s\t%s\n' "$LR_RANK" "$LR_ITEM" "$LR_ISSUE" "$LR_KIND" >> "$LEFTOVER_FILE"
        fi
    done < "$DEDUP_FILE"

    # Sort: conf-rank desc, issue asc, item asc. Then iterate, adding unique issues.
    if [[ -s "$LEFTOVER_FILE" ]]; then
        SORTED_LEFTOVER="$TMPDIR_LOCAL/leftover_sorted.tsv"
        sort -t$'\t' -k1,1nr -k3,3n -k2,2n "$LEFTOVER_FILE" > "$SORTED_LEFTOVER"
        while IFS=$'\t' read -r _LR_RANK _LR_ITEM LR_ISSUE _LR_KIND; do
            CUR_LEN=$(echo "$UNION_LIST" | wc -w | tr -d ' ')
            (( CUR_LEN >= CAP )) && break
            if ! union_contains "$LR_ISSUE"; then
                union_add "$LR_ISSUE"
            fi
        done < "$SORTED_LEFTOVER"
    fi
fi

# Emit final CANDIDATES sorted ascending (numeric).
if [[ -z "$UNION_LIST" ]]; then
    echo "CANDIDATES="
else
    SORTED=$(echo "$UNION_LIST" | tr ' ' '\n' | sort -un | paste -sd, -)
    echo "CANDIDATES=$SORTED"
fi

exit 0
