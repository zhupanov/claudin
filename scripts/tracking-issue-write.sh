#!/usr/bin/env bash
# tracking-issue-write.sh — outbound helper for the tracking-issue lifecycle.
#
# Phase 1 (umbrella #348) foundation layer. Ships three narrow subcommands
# that each perform exactly one GitHub write, all sharing the same KEY=value
# stdout envelope and fail-closed redaction posture as
# skills/issue/scripts/create-one.sh.
#
# Subcommands:
#   create-issue   --title T --body-file F [--repo OWNER/REPO]
#   append-comment --issue N --body-file F [--lifecycle-marker ID] [--repo OWNER/REPO]
#   upsert-anchor  --issue N [--anchor-id ID] --body-file F [--repo OWNER/REPO]
#
# Output contract (KEY=value on stdout; warnings on stderr). NAMESPACE note:
# this script emits FAILED=true / ERROR=<msg> on failure — NOT the
# ISSUE_FAILED=true / ISSUE_ERROR=<msg> prefix used by
# skills/issue/scripts/create-one.sh. The divergence is intentional; this
# script is not an /issue layer component. Consumers must parse for the
# FAILED= / ERROR= prefix exactly. Parsers must also use the ERROR= field
# (not exit code alone) to distinguish error kinds because exit 1 covers
# both invocation-usage errors and validated-content rejections.
#
# Success keys:
#   create-issue:   ISSUE_NUMBER=<N>  ISSUE_URL=<url>
#   append-comment: COMMENT_ID=<id>   COMMENT_URL=<url>
#   upsert-anchor:  ANCHOR_COMMENT_ID=<id>  ANCHOR_COMMENT_URL=<url>  UPDATED=true|false
#
# Failure keys:
#   FAILED=true  ERROR=<single-line message>
#
# Exit codes:
#   0 — success
#   1 — invocation-usage error OR validated-content rejection (disambiguate via ERROR=)
#   2 — gh failure (FAILED=true / ERROR= already emitted on stdout)
#   3 — redaction helper failure (FAILED=true / ERROR=redaction:…)
#
# Security posture (see SECURITY.md "tracking-issue-write.sh outbound path"):
#   * Structural choke point — compose full logical body in memory, pipe
#     through scripts/redact-secrets.sh, THEN apply truncation. Never the
#     reverse. Token-shaped byte sequences must not be sliced before
#     redaction. Placement mirrors create-one.sh's single-choke-point
#     comment (create-one.sh:202-208).
#   * gh-failure redaction — every gh invocation captures stdout and
#     stderr separately. On non-success paths, captured stderr is piped
#     through scripts/redact-secrets.sh before emission in ERROR=. This
#     mirrors create-one.sh:247-280's posture for /issue outbound.
#   * Anchor skeleton preservation — truncation operates on section
#     interiors, NEVER on section marker literals or the HTML anchor
#     first-line marker. Phase 3 consumers parse by these markers.
#
# Anchor version policy (strict v1):
#   This script matches and emits only <!-- larch:implement-anchor v1 … -->.
#   Future versions (v2, …) introduce a new marker handled by a new tool
#   version. Mixed-version state on a single issue is fail-closed via
#   upsert-anchor's "multiple anchor comments" branch.
#
# Conventions:
#   Uses Bash 3.2-compatible constructs (indexed arrays only; no
#   associative arrays, no `mapfile`) so macOS-default bash runs match
#   Ubuntu CI. Precedent: scripts/dialectic-smoke-test.sh.
#   Truncation is byte-length based with line-boundary snapping (inline
#   TRUNCATED marker always begins on its own line so open code fences
#   cannot consume the marker or subsequent section markers). Multibyte
#   UTF-8 splitting is tolerated as section interiors are machine-composed
#   (no human multibyte content expected).

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)
REDACT_HELPER="$REPO_ROOT/scripts/redact-secrets.sh"

# 8 canonical section slugs in declaration order.
SECTION_MARKERS=(plan-goals-test plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics)

# Per-section 8000-char cap. Exceeded interiors are replaced in place with
# a single inline [TRUNCATED — <id> exceeded 8000 chars] marker snapped to
# the next newline boundary.
PER_SECTION_CAP=8000

# Body-level 60000-char cap. Exceeding collapses sections to a single
# placeholder in priority order (most-ephemeral first, most user-value
# last). All slugs below come from SECTION_MARKERS above.
BODY_CAP=60000
COLLAPSE_PRIORITY=(execution-issues plan-review-tally code-review-tally oos-issues run-statistics version-bump-reasoning diagrams plan-goals-test)

ANCHOR_MARKER_V1_PREFIX='<!-- larch:implement-anchor v1'

usage() {
    cat <<'USAGE' >&2
Usage:
  tracking-issue-write.sh create-issue   --title T --body-file F [--repo OWNER/REPO]
  tracking-issue-write.sh append-comment --issue N --body-file F [--lifecycle-marker ID] [--repo OWNER/REPO]
  tracking-issue-write.sh upsert-anchor  --issue N [--anchor-id ID] --body-file F [--repo OWNER/REPO]
USAGE
}

# emit_redaction_failure — runs outside command substitution (via `|| ...`)
# so its echo lines reach the parent's stdout for callers parsing
# ^FAILED= / ^ERROR= on stdout, then exits 3. The helper is required:
# there is no fallback to un-redacted content per the fail-closed
# defense-in-depth design.
emit_redaction_failure() {
    echo "FAILED=true"
    echo "ERROR=redaction: helper $REDACT_HELPER failed or missing"
    exit 3
}

# redact <text> — prints redacted text on stdout, returns the helper's
# exit code. Callers MUST invoke this via command substitution combined
# with `|| emit_redaction_failure`, because inside command substitution any
# stdout emission is captured into the assigning variable rather than the
# parent's stdout. Do NOT swallow stderr: redact-secrets.sh emits a WARN on
# stderr when an unterminated PEM block forces fail-closed truncation, and
# that signal is the only log-visibility mechanism for that condition.
redact() {
    printf '%s' "$1" | "$REDACT_HELPER"
}

# redact_gh_error <captured-stderr-text> — same as redact but used on gh
# failure paths to scrub 4xx API responses / token-bearing error text
# before emission in ERROR=. Flattens newlines and truncates to 500 chars
# matching create-one.sh's outbound pattern.
redact_gh_error() {
    local err_text="$1"
    local redacted
    redacted=$(redact "$err_text") || emit_redaction_failure
    printf '%s' "$redacted" | tr '\n' ' ' | head -c 500
}

# emit_gh_failure <captured-stderr-text> — redact + emit the KEY=value
# failure envelope and exit 2.
emit_gh_failure() {
    local flat
    flat=$(redact_gh_error "$1")
    echo "FAILED=true"
    echo "ERROR=$flat"
    exit 2
}

# truncate_body <body> — two-pass truncation per the skeleton-preservation
# invariant. Prints the truncated body to stdout.
#
# Pass 1 (per-section): for each SECTION_MARKERS slug, if the interior
# between the section-open and section-end markers exceeds PER_SECTION_CAP,
# replace the interior with a truncated prefix (snapped to newline) plus
# an inline TRUNCATED marker on its own line. Section markers themselves
# are preserved.
#
# Pass 2 (body-level): if total length still exceeds BODY_CAP, walk
# COLLAPSE_PRIORITY in order. For each slug, replace the interior with
# the single-line placeholder. Stop once total length fits.
#
# Implementation: the new-interior content can contain newlines, which
# awk -v cannot accept. For each section we write the replacement
# interior to a per-section temp file and have awk splice it in via
# getline. A single TRUNCATE_WORK_DIR holds these temps; the caller's
# EXIT trap covers cleanup transitively (all writes live under the
# same per-subcommand tmp that's already trapped).
truncate_body() {
    local body="$1"
    local slug interior new_interior open_marker close_marker
    local work_dir
    work_dir=$(mktemp -d)

    # Pass 1: per-section cap
    for slug in "${SECTION_MARKERS[@]}"; do
        open_marker="<!-- section:${slug} -->"
        close_marker="<!-- section-end:${slug} -->"
        # Extract section interior: everything between open_marker line
        # and close_marker line (exclusive). Emit "__NOT_FOUND__" if the
        # section markers are absent.
        interior=$(awk -v o="$open_marker" -v c="$close_marker" '
            BEGIN { in_section = 0; found = 0 }
            $0 == o { in_section = 1; found = 1; next }
            $0 == c { in_section = 0; next }
            in_section { print }
            END { if (!found) print "__NOT_FOUND__" }
        ' <<<"$body")
        if [[ "$interior" == "__NOT_FOUND__" ]]; then
            continue
        fi
        if (( ${#interior} <= PER_SECTION_CAP )); then
            continue
        fi
        # Snap to previous newline at or before the cap so the TRUNCATED
        # marker begins on its own line (prevents open-fence corruption).
        local truncated_at="$PER_SECTION_CAP"
        while (( truncated_at > 0 )) && [[ "${interior:$truncated_at:1}" != $'\n' ]]; do
            truncated_at=$((truncated_at - 1))
        done
        if (( truncated_at == 0 )); then
            truncated_at="$PER_SECTION_CAP"
        fi
        new_interior="${interior:0:$truncated_at}"$'\n'"[TRUNCATED — ${slug} exceeded ${PER_SECTION_CAP} chars]"
        # Write the replacement to a file so awk can read it via getline
        # (awk -v does not accept newlines in the value).
        local ni_file="$work_dir/ni-$slug.txt"
        printf '%s' "$new_interior" > "$ni_file"
        body=$(awk -v o="$open_marker" -v c="$close_marker" -v nif="$ni_file" '
            BEGIN { in_section = 0; emitted = 0 }
            $0 == o { in_section = 1; print; next }
            $0 == c {
                if (in_section && !emitted) {
                    while ((getline line < nif) > 0) print line
                    close(nif)
                    emitted = 1
                }
                in_section = 0
                print
                next
            }
            in_section { next }
            { print }
        ' <<<"$body")
    done

    # Pass 2: body-level cap
    if (( ${#body} > BODY_CAP )); then
        for slug in "${COLLAPSE_PRIORITY[@]}"; do
            open_marker="<!-- section:${slug} -->"
            close_marker="<!-- section-end:${slug} -->"
            local placeholder="[section '${slug}' truncated — see execution-issues.md locally]"
            body=$(awk -v o="$open_marker" -v c="$close_marker" -v ph="$placeholder" '
                BEGIN { in_section = 0; emitted = 0 }
                $0 == o { in_section = 1; print; emitted = 0; next }
                $0 == c {
                    if (in_section && !emitted) {
                        print ph
                        emitted = 1
                    }
                    in_section = 0
                    print
                    next
                }
                in_section { next }
                { print }
            ' <<<"$body")
            if (( ${#body} <= BODY_CAP )); then
                break
            fi
        done
    fi

    rm -rf "$work_dir"
    printf '%s' "$body"
}

# list_anchor_comments <issue-number> <repo> — emits anchor comment IDs
# (one per line, order preserved) for comments whose first line starts
# with ANCHOR_MARKER_V1_PREFIX. gh api pagination handles >100 comments.
list_anchor_comments() {
    local issue="$1"
    local repo="$2"
    local err_tmp
    err_tmp=$(mktemp)
    if ! gh api "/repos/${repo}/issues/${issue}/comments" --paginate --jq '.[] | (.id|tostring) + "\t" + (.body // "" | split("\n")[0])' 2>"$err_tmp"; then
        local err
        err=$(cat "$err_tmp")
        rm -f "$err_tmp"
        emit_gh_failure "$err"
    fi
    rm -f "$err_tmp"
}

# filter_anchor_ids <tab-separated-id-firstline-lines> — stdin → ids of
# comments whose first line begins with ANCHOR_MARKER_V1_PREFIX.
filter_anchor_ids() {
    LC_ALL=C awk -F'\t' -v prefix="$ANCHOR_MARKER_V1_PREFIX" '
        { line = $2 }
        # Strip UTF-8 BOM if present on first byte.
        substr(line, 1, 3) == "\357\273\277" { line = substr(line, 4) }
        index(line, prefix) == 1 { print $1 }
    '
}

cmd="${1:-}"
if [[ -z "$cmd" ]]; then
    usage
    exit 1
fi
shift

case "$cmd" in
    create-issue)
        TITLE=""
        BODY_FILE=""
        REPO=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
                --body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
                --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
                *) echo "Unknown option for create-issue: $1" >&2; usage; exit 1 ;;
            esac
        done
        if [[ -z "$TITLE" ]] || [[ -z "$BODY_FILE" ]]; then
            usage
            exit 1
        fi
        if [[ ! -f "$BODY_FILE" ]]; then
            echo "FAILED=true"
            echo "ERROR=body file not found: $BODY_FILE"
            exit 1
        fi
        if [[ -z "$REPO" ]]; then
            REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
            if [[ -z "$REPO" ]]; then
                echo "FAILED=true"
                echo "ERROR=could not determine repo"
                exit 2
            fi
        fi
        TITLE=$(redact "$TITLE") || emit_redaction_failure
        BODY_CONTENT=$(cat "$BODY_FILE")
        if [[ -z "$BODY_CONTENT" ]]; then
            echo "FAILED=true"
            echo "ERROR=empty body"
            exit 1
        fi
        # Single structural choke point: compose (already composed above as
        # BODY_CONTENT) → redact → truncate. Do NOT reorder: truncation
        # before redaction could slice token-shaped byte sequences.
        BODY_CONTENT=$(redact "$BODY_CONTENT") || emit_redaction_failure
        BODY_CONTENT=$(truncate_body "$BODY_CONTENT")
        BODY_TMP=$(mktemp)
        ERR_TMP=$(mktemp)
        # shellcheck disable=SC2317
        cleanup() { rm -f "$BODY_TMP" "$ERR_TMP"; }
        trap cleanup EXIT
        printf '%s' "$BODY_CONTENT" > "$BODY_TMP"
        if ISSUE_URL=$(gh issue create --repo "$REPO" --title "$TITLE" --body-file "$BODY_TMP" 2>"$ERR_TMP"); then
            URL_LINE=$(echo "$ISSUE_URL" | grep -oE 'https?://[^[:space:]]+/issues/[0-9]+' | tail -1 || true)
            if [[ -z "$URL_LINE" ]]; then
                ERR_CONTENT=$(cat "$ERR_TMP")
                emit_gh_failure "gh issue create did not emit a URL (stderr: $ERR_CONTENT)"
            fi
            ISSUE_NUM=$(echo "$URL_LINE" | grep -oE '[0-9]+$')
            echo "ISSUE_NUMBER=$ISSUE_NUM"
            echo "ISSUE_URL=$URL_LINE"
            exit 0
        else
            ERR_CONTENT=$(cat "$ERR_TMP")
            emit_gh_failure "$ERR_CONTENT"
        fi
        ;;

    append-comment)
        ISSUE=""
        BODY_FILE=""
        REPO=""
        LIFECYCLE_MARKER=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --issue) ISSUE="${2:?--issue requires a value}"; shift 2 ;;
                --body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
                --lifecycle-marker) LIFECYCLE_MARKER="${2:?--lifecycle-marker requires a value}"; shift 2 ;;
                --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
                *) echo "Unknown option for append-comment: $1" >&2; usage; exit 1 ;;
            esac
        done
        if [[ -z "$ISSUE" ]] || [[ -z "$BODY_FILE" ]]; then
            usage
            exit 1
        fi
        if [[ ! -f "$BODY_FILE" ]]; then
            echo "FAILED=true"
            echo "ERROR=body file not found: $BODY_FILE"
            exit 1
        fi
        if [[ -z "$REPO" ]]; then
            REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
            if [[ -z "$REPO" ]]; then
                echo "FAILED=true"
                echo "ERROR=could not determine repo"
                exit 2
            fi
        fi
        BODY_CONTENT=$(cat "$BODY_FILE")
        if [[ -z "$BODY_CONTENT" ]]; then
            echo "FAILED=true"
            echo "ERROR=empty body"
            exit 1
        fi
        if [[ -n "$LIFECYCLE_MARKER" ]]; then
            BODY_CONTENT="<!-- larch:lifecycle-marker:${LIFECYCLE_MARKER} -->"$'\n'"$BODY_CONTENT"
        fi
        BODY_CONTENT=$(redact "$BODY_CONTENT") || emit_redaction_failure
        BODY_CONTENT=$(truncate_body "$BODY_CONTENT")
        BODY_TMP=$(mktemp)
        ERR_TMP=$(mktemp)
        # shellcheck disable=SC2317
        cleanup() { rm -f "$BODY_TMP" "$ERR_TMP"; }
        trap cleanup EXIT
        printf '%s' "$BODY_CONTENT" > "$BODY_TMP"
        if COMMENT_URL=$(gh issue comment "$ISSUE" --repo "$REPO" --body-file "$BODY_TMP" 2>"$ERR_TMP"); then
            URL_LINE=$(echo "$COMMENT_URL" | grep -oE 'https?://[^[:space:]]+#issuecomment-[0-9]+' | tail -1 || true)
            if [[ -z "$URL_LINE" ]]; then
                ERR_CONTENT=$(cat "$ERR_TMP")
                emit_gh_failure "gh issue comment did not emit a URL (stderr: $ERR_CONTENT)"
            fi
            CID=$(echo "$URL_LINE" | grep -oE '[0-9]+$')
            echo "COMMENT_ID=$CID"
            echo "COMMENT_URL=$URL_LINE"
            exit 0
        else
            ERR_CONTENT=$(cat "$ERR_TMP")
            emit_gh_failure "$ERR_CONTENT"
        fi
        ;;

    upsert-anchor)
        ISSUE=""
        ANCHOR_ID=""
        BODY_FILE=""
        REPO=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --issue) ISSUE="${2:?--issue requires a value}"; shift 2 ;;
                --anchor-id) ANCHOR_ID="${2:?--anchor-id requires a value}"; shift 2 ;;
                --body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
                --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
                *) echo "Unknown option for upsert-anchor: $1" >&2; usage; exit 1 ;;
            esac
        done
        if [[ -z "$ISSUE" ]] || [[ -z "$BODY_FILE" ]]; then
            usage
            exit 1
        fi
        if [[ ! -f "$BODY_FILE" ]]; then
            echo "FAILED=true"
            echo "ERROR=body file not found: $BODY_FILE"
            exit 1
        fi
        if [[ -z "$REPO" ]]; then
            REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
            if [[ -z "$REPO" ]]; then
                echo "FAILED=true"
                echo "ERROR=could not determine repo"
                exit 2
            fi
        fi
        BODY_CONTENT=$(cat "$BODY_FILE")
        if [[ -z "$BODY_CONTENT" ]]; then
            echo "FAILED=true"
            echo "ERROR=empty body"
            exit 1
        fi
        # Ensure anchor first-line marker is present; prepend if not.
        # Use parameter expansion (not `head -n 1 | ...`) to avoid SIGPIPE
        # under set -o pipefail for large bodies.
        FIRST_LINE="${BODY_CONTENT%%$'\n'*}"
        ANCHOR_FIRSTLINE="<!-- larch:implement-anchor v1 issue=${ISSUE} -->"
        if [[ "$FIRST_LINE" != "<!-- larch:implement-anchor v1"* ]]; then
            BODY_CONTENT="${ANCHOR_FIRSTLINE}"$'\n'"$BODY_CONTENT"
        fi
        # Compose → redact → truncate (structural choke point).
        BODY_CONTENT=$(redact "$BODY_CONTENT") || emit_redaction_failure
        BODY_CONTENT=$(truncate_body "$BODY_CONTENT")
        BODY_TMP=$(mktemp)
        ERR_TMP=$(mktemp)
        # shellcheck disable=SC2317
        cleanup() { rm -f "$BODY_TMP" "$ERR_TMP"; }
        trap cleanup EXIT
        printf '%s' "$BODY_CONTENT" > "$BODY_TMP"

        if [[ -n "$ANCHOR_ID" ]]; then
            TARGET_ID="$ANCHOR_ID"
            UPDATED=true
        else
            # Marker-search fallback. List anchor-marker comments.
            LIST_OUT=$(list_anchor_comments "$ISSUE" "$REPO")
            ANCHOR_IDS=$(printf '%s\n' "$LIST_OUT" | filter_anchor_ids)
            ANCHOR_COUNT=0
            if [[ -n "$ANCHOR_IDS" ]]; then
                ANCHOR_COUNT=$(printf '%s\n' "$ANCHOR_IDS" | wc -l | tr -d '[:space:]')
            fi
            if (( ANCHOR_COUNT == 0 )); then
                # No anchor — create fresh comment.
                if COMMENT_URL=$(gh issue comment "$ISSUE" --repo "$REPO" --body-file "$BODY_TMP" 2>"$ERR_TMP"); then
                    URL_LINE=$(echo "$COMMENT_URL" | grep -oE 'https?://[^[:space:]]+#issuecomment-[0-9]+' | tail -1 || true)
                    if [[ -z "$URL_LINE" ]]; then
                        ERR_CONTENT=$(cat "$ERR_TMP")
                        emit_gh_failure "gh issue comment did not emit a URL (stderr: $ERR_CONTENT)"
                    fi
                    CID=$(echo "$URL_LINE" | grep -oE '[0-9]+$')
                    echo "ANCHOR_COMMENT_ID=$CID"
                    echo "ANCHOR_COMMENT_URL=$URL_LINE"
                    echo "UPDATED=false"
                    exit 0
                else
                    ERR_CONTENT=$(cat "$ERR_TMP")
                    emit_gh_failure "$ERR_CONTENT"
                fi
            elif (( ANCHOR_COUNT == 1 )); then
                TARGET_ID="$ANCHOR_IDS"
                UPDATED=true
            else
                # Multiple anchors — fail closed.
                IDS_FLAT=$(printf '%s' "$ANCHOR_IDS" | tr '\n' ',' | sed 's/,$//')
                echo "FAILED=true"
                echo "ERROR=multiple anchor comments found (ids: $IDS_FLAT)"
                exit 2
            fi
        fi

        # PATCH the target comment via gh api. Build a JSON object
        # {"body": "..."} using jq -Rs (read raw, slurp) to handle all
        # escape cases (newlines, quotes, backslashes) and pass via
        # --input. This keeps --body-file / --input as the single
        # body-transport convention for the stub harness to key on.
        JSON_TMP=$(mktemp)
        # shellcheck disable=SC2317
        cleanup2() { rm -f "$BODY_TMP" "$ERR_TMP" "$JSON_TMP"; }
        trap cleanup2 EXIT
        if ! jq -Rs '{body: .}' < "$BODY_TMP" > "$JSON_TMP" 2>"$ERR_TMP"; then
            ERR_CONTENT=$(cat "$ERR_TMP")
            emit_gh_failure "jq JSON encode failed: $ERR_CONTENT"
        fi
        if PATCH_OUT=$(gh api -X PATCH "/repos/${REPO}/issues/comments/${TARGET_ID}" --input "$JSON_TMP" 2>"$ERR_TMP"); then
            # Successful PATCH returns JSON with id + html_url.
            PATCH_URL=$(printf '%s' "$PATCH_OUT" | grep -oE '"html_url":"[^"]+"' | head -n1 | sed -E 's/"html_url":"([^"]+)"/\1/')
            if [[ -z "$PATCH_URL" ]]; then
                ERR_CONTENT=$(cat "$ERR_TMP")
                emit_gh_failure "gh api PATCH did not emit html_url (stderr: $ERR_CONTENT)"
            fi
            echo "ANCHOR_COMMENT_ID=$TARGET_ID"
            echo "ANCHOR_COMMENT_URL=$PATCH_URL"
            echo "UPDATED=$UPDATED"
            exit 0
        else
            ERR_CONTENT=$(cat "$ERR_TMP")
            emit_gh_failure "$ERR_CONTENT"
        fi
        ;;

    *)
        echo "Unknown subcommand: $cmd" >&2
        usage
        exit 1
        ;;
esac
