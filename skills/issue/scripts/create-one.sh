#!/usr/bin/env bash
# create-one.sh — Create a single GitHub issue with defensive-guards that
# preserve the compatibility behavior of the deleted scripts/create-oos-issues.sh.
#
# Guards:
#   - [OOS] double-prefix normalization: strip any leading `[OOS]` (case-
#     insensitive, with optional whitespace) from the input title before
#     applying --title-prefix, so `[OOS] [OOS] …` cannot happen.
#   - Optional-label probe: for each --label value, probe `gh label list
#     --search <L>`; if the label does not exist in the target repo, silently
#     drop that label with a stderr warning. Matches create-oos-issues.sh:71-75.
#   - --dry-run: no network calls, emit DRY_RUN=true plus the final title/body
#     preview.
#
# The OOS-specific body template (Out-of-Scope heading, Surfaced by / Phase /
# Vote tally lines, Description heading, automated-larch footer — as in the
# deleted scripts/create-oos-issues.sh:149-162) is assembled by the caller
# (/issue's SKILL.md in batch mode) and passed via --body-file, not by this
# script. create-one.sh deliberately knows only about title / body-file /
# labels / prefix / dry-run so it stays composable.
#
# Usage:
#   create-one.sh --title TITLE [--title-prefix PREFIX] [--label L]... \
#                 [--body FILE | --body-file FILE] \
#                 [--repo OWNER/REPO] [--dry-run]
#
# Arguments:
#   --title TITLE            — issue title (required).
#   --title-prefix PREFIX    — optional prefix (e.g. "[OOS]"). Applied after
#                              normalizing any existing matching prefix on TITLE.
#   --label L                — repeatable. Each label is probed against the repo
#                              and silently dropped if missing.
#   --body FILE              — alias for --body-file.
#   --body-file FILE         — path to a file containing the issue body verbatim.
#   --repo OWNER/REPO        — target repo (otherwise inferred).
#   --dry-run                — do not call gh; emit DRY_RUN=true and preview.
#
# Output (key=value on stdout; warnings on stderr):
#   ISSUE_NUMBER=<N>   ISSUE_URL=<url>   ISSUE_ID=<numeric-id>    on success
#   ISSUE_FAILED=true  ISSUE_ERROR=<msg>                           on failure
#   DRY_RUN=true                                                   on --dry-run success path
#
# ISSUE_ID is the issue's internal numeric id (NOT the display number). It is
# emitted only on the non-dry-run CREATE path because the dry-run branch makes
# no API call. Required by /issue's dependency-analysis path (issue #546):
# add-blocked-by.sh's POST body needs the BLOCKER's internal id, and capturing
# it here at create-time avoids a separate `gh api` round-trip per intra-batch
# blocker (which would introduce an orphan-failure mode where the issue is
# created but a transient id-lookup fails).
#
# Exit code:
#   0 — success (issue created OR --dry-run emitted preview)
#   1 — arg or usage error
#   2 — gh create failure (ISSUE_FAILED=true already emitted on stdout)
#   3 — redaction helper failure (ISSUE_FAILED=true with ISSUE_ERROR=redaction:…)
#
# Defense-in-depth: TITLE and BODY_CONTENT are piped through
# scripts/redact-secrets.sh before being passed to gh. This scrubs a fixed
# set of token families (sk-*, ghp_, AKIA, xox, JWT, PEM) as a deterministic
# backstop to prompt-level sanitization. See SECURITY.md.

set -euo pipefail

# Resolve the repo-root path to scripts/redact-secrets.sh. This file sits at
# skills/issue/scripts/create-one.sh, so the repo root is three levels up.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/../../.." && pwd)
REDACT_HELPER="$REPO_ROOT/scripts/redact-secrets.sh"

# redact <text> — prints redacted text on stdout, returns the helper's
# exit code. Callers MUST invoke this via command substitution combined
# with `|| emit_redaction_failure`, because inside command substitution any
# stdout emission is captured into the assigning variable rather than the
# parent's stdout. emit_redaction_failure runs in the parent's process so
# its ISSUE_FAILED/ISSUE_ERROR echoes actually reach the machine-readable
# stdout contract documented in the header above.
redact() {
    # Do NOT swallow stderr: redact-secrets.sh emits a WARN on stderr when
    # an unterminated PEM block forces fail-closed truncation, and that
    # signal is the only log-visibility mechanism for that condition.
    printf '%s' "$1" | "$REDACT_HELPER"
}

# emit_redaction_failure — runs outside command substitution (via `|| ...`)
# so its echo lines reach the parent's stdout for callers parsing
# ^ISSUE_FAILED=/^ISSUE_ERROR= on stdout, then exits 3. The helper is
# required: there is no fallback to un-redacted content per the fail-closed
# defense-in-depth design.
emit_redaction_failure() {
    echo "ISSUE_FAILED=true"
    echo "ISSUE_ERROR=redaction: helper $REDACT_HELPER failed or missing"
    exit 3
}

TITLE=""
TITLE_PREFIX=""
BODY_FILE=""
REPO=""
DRY_RUN=false
LABELS=()

usage() {
    cat <<USAGE >&2
Usage: create-one.sh --title TITLE [--title-prefix PREFIX] [--label L]... \\
                     [--body FILE | --body-file FILE] \\
                     [--repo OWNER/REPO] [--dry-run]
USAGE
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --title) TITLE="${2:?--title requires a value}"; shift 2 ;;
        --title-prefix) TITLE_PREFIX="${2:?--title-prefix requires a value}"; shift 2 ;;
        --label) LABELS+=("${2:?--label requires a value}"); shift 2 ;;
        --body|--body-file) BODY_FILE="${2:?--body-file requires a value}"; shift 2 ;;
        --repo) REPO="${2:?--repo requires a value}"; shift 2 ;;
        --dry-run) DRY_RUN=true; shift ;;
        *) echo "Unknown option: $1" >&2; usage; exit 1 ;;
    esac
done

if [[ -z "$TITLE" ]]; then
    usage
    exit 1
fi

# Redact TITLE before [OOS] double-prefix normalization so the normalization
# operates on scrubbed content and downstream FINAL_TITLE / DRY_RUN_TITLE /
# ISSUE_TITLE are uniformly redacted.
TITLE=$(redact "$TITLE") || emit_redaction_failure

# Resolve repo if not provided.
if [[ -z "$REPO" ]]; then
    REPO=$(gh repo view --json nameWithOwner --jq '.nameWithOwner' 2>/dev/null) || REPO=""
    if [[ -z "$REPO" ]] && [[ "$DRY_RUN" == false ]]; then
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=could not determine repo"
        exit 2
    fi
fi

# ---------------------------------------------------------------------------
# [OOS] double-prefix normalization.
#
# If TITLE_PREFIX is set and TITLE already starts with the same prefix (case-
# insensitive, with optional whitespace), strip it so applying the prefix a
# second time produces a clean result.
# ---------------------------------------------------------------------------
if [[ -n "$TITLE_PREFIX" ]]; then
    # Build a case-insensitive regex-style check. Compare the normalized lowercase
    # variants of the starts-with check.
    prefix_lower=$(echo "$TITLE_PREFIX" | tr '[:upper:]' '[:lower:]')
    title_lower=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]')
    if [[ "$title_lower" == "$prefix_lower"* ]]; then
        # Strip the prefix and any whitespace after it.
        TITLE="${TITLE:${#TITLE_PREFIX}}"
        TITLE="${TITLE#"${TITLE%%[![:space:]]*}"}"
    fi
    FINAL_TITLE="$TITLE_PREFIX $TITLE"
else
    FINAL_TITLE="$TITLE"
fi

# ---------------------------------------------------------------------------
# Probe labels. Drop any label that does not exist in the target repo, with a
# stderr warning. Matches compatibility behavior of create-oos-issues.sh:71-75.
# In --dry-run mode without a resolvable repo, skip the probe entirely and
# accept all labels as-is.
# ---------------------------------------------------------------------------
VALID_LABELS=()
for L in "${LABELS[@]+"${LABELS[@]}"}"; do
    if [[ -z "$REPO" ]] && [[ "$DRY_RUN" == true ]]; then
        VALID_LABELS+=("$L")
        continue
    fi
    # Probe. gh label list --search returns partial matches; require exact name.
    # Fixed-string whole-line match (closes #775 — unified grep -F doctrine).
    # Without -F, $L is interpreted as a BRE: labels like `bug.feature` or
    # `release[2026]` would have BRE metacharacters in `.` and `[]` change the
    # match semantics from byte-exact to pattern-matched. Active current path:
    # /umbrella forwards operator --label values verbatim through /issue.
    if gh label list --repo "$REPO" --search "$L" --json name --jq '.[].name' 2>/dev/null | grep -Fqx -- "$L"; then
        VALID_LABELS+=("$L")
    else
        echo "WARN: label '$L' does not exist in $REPO, skipping" >&2
    fi
done

# ---------------------------------------------------------------------------
# Assemble the body.
# ---------------------------------------------------------------------------
BODY_CONTENT=""
BODY_TMP=""
ERR_TMP=""
# shellcheck disable=SC2317  # reachable via EXIT trap; shellcheck can't see indirect invocation
cleanup() {
    if [[ -n "${BODY_TMP:-}" ]] && [[ -f "$BODY_TMP" ]]; then
        rm -f "$BODY_TMP"
    fi
    if [[ -n "${ERR_TMP:-}" ]] && [[ -f "$ERR_TMP" ]]; then
        rm -f "$ERR_TMP"
    fi
}
trap cleanup EXIT

if [[ -n "$BODY_FILE" ]]; then
    if [[ ! -f "$BODY_FILE" ]]; then
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=body file not found: $BODY_FILE"
        exit 1
    fi
    BODY_CONTENT=$(cat "$BODY_FILE")
fi

# Single structural choke point: redact BODY_CONTENT after all body-assembly
# paths converge, before dry-run branching or gh invocation. Any future body
# source added above the fi must still go through this point — that is the
# invariant this placement encodes.
if [[ -n "$BODY_CONTENT" ]]; then
    BODY_CONTENT=$(redact "$BODY_CONTENT") || emit_redaction_failure
fi

# ---------------------------------------------------------------------------
# Dry-run path.
# ---------------------------------------------------------------------------
if [[ "$DRY_RUN" == true ]]; then
    echo "DRY_RUN=true"
    echo "DRY_RUN_TITLE=$FINAL_TITLE"
    echo "ISSUE_TITLE=$FINAL_TITLE"
    if [[ ${#VALID_LABELS[@]} -gt 0 ]]; then
        DRY_LABELS_JOINED=$(IFS=,; echo "${VALID_LABELS[*]}")
        echo "DRY_RUN_LABELS=$DRY_LABELS_JOINED"
    fi
    # Body preview: first 300 chars.
    if [[ -n "$BODY_CONTENT" ]]; then
        PREVIEW="${BODY_CONTENT:0:300}"
        # Flatten to single line for key=value.
        PREVIEW_FLAT=$(printf '%s' "$PREVIEW" | tr '\n' ' ' | tr -s ' ')
        echo "DRY_RUN_BODY_PREVIEW=$PREVIEW_FLAT"
    fi
    exit 0
fi

# ---------------------------------------------------------------------------
# Real create. Write body to a temp file so quoting is safe.
# ---------------------------------------------------------------------------
BODY_TMP=$(mktemp)
printf '%s' "$BODY_CONTENT" > "$BODY_TMP"

GH_ARGS=(issue create --repo "$REPO" --title "$FINAL_TITLE" --body-file "$BODY_TMP")
for L in "${VALID_LABELS[@]+"${VALID_LABELS[@]}"}"; do
    GH_ARGS+=(--label "$L")
done

# Capture stdout and stderr separately so a stray stderr line (progress,
# warning) on the success path cannot corrupt URL extraction below. ERR_TMP
# holds stderr; ISSUE_URL holds stdout only. Cleanup happens via the EXIT
# trap, so every exit path — including emit_redaction_failure — removes the
# stderr temp file.
ERR_TMP=$(mktemp)
# Try modern `gh issue create --json` first to capture id+number+url in a
# single response. This avoids a separate post-create `gh api ... --jq .id`
# call that would introduce an orphan-failure mode (issue #546 plan-review
# FINDING_8: an issue exists on GitHub but a transient lookup-failure would
# mark /issue as failed, causing reruns to duplicate).
USE_FALLBACK=false
if ISSUE_JSON=$(gh "${GH_ARGS[@]}" --json id,number,url 2>"$ERR_TMP"); then
    # Validate that the output parses as JSON with the expected fields. If
    # not (older gh ignored --json, or a stubbed `gh` returns plain text),
    # fall through to the fallback path which extracts via URL-line +
    # gh-api-id-lookup. This makes the helper robust to both genuinely-old
    # gh CLI versions AND test-harness stubs that don't implement --json.
    if echo "$ISSUE_JSON" | jq -e 'has("number") and has("url") and has("id")' >/dev/null 2>&1; then
        ISSUE_NUM=$(echo "$ISSUE_JSON" | jq -r '.number')
        ISSUE_URL=$(echo "$ISSUE_JSON" | jq -r '.url')
        ISSUE_ID=$(echo "$ISSUE_JSON" | jq -r '.id')
        if [[ -z "$ISSUE_NUM" || -z "$ISSUE_URL" || -z "$ISSUE_ID" ]]; then
            REDACTED_OUTPUT=$(redact "$ISSUE_JSON") || emit_redaction_failure
            REDACTED_OUTPUT_FLAT=$(echo "$REDACTED_OUTPUT" | tr '\n' ' ' | head -c 500)
            echo "ISSUE_FAILED=true"
            echo "ISSUE_ERROR=gh issue create returned JSON with empty field(s) (output: $REDACTED_OUTPUT_FLAT)"
            exit 2
        fi
        echo "ISSUE_NUMBER=$ISSUE_NUM"
        echo "ISSUE_URL=$ISSUE_URL"
        echo "ISSUE_ID=$ISSUE_ID"
        echo "ISSUE_TITLE=$FINAL_TITLE"
        exit 0
    fi
    # JSON-parse-failure path: the success-coded output isn't valid JSON.
    # Treat as if --json wasn't honored and use the fallback. ISSUE_JSON
    # here might be a plain URL line from an older gh or a test stub.
    USE_FALLBACK=true
    : >"$ERR_TMP"
fi
# `gh issue create --json` failed. Three possibilities: (a) the gh CLI
# version does not support `--json` on `issue create` (older versions), in
# which case stderr will mention an unrecognized flag; (b) genuine API
# failure (any other stderr); (c) USE_FALLBACK=true above (success-but-non-JSON).
# Detect (a) or (c) and fall back to plain `gh issue create` + a follow-up
# `gh api ... --jq .id` lookup. (b) flows to the redacted-error emission below.
ERR_CONTENT=$(cat "$ERR_TMP")
if [[ "$USE_FALLBACK" == "true" ]] || (echo "$ERR_CONTENT" | grep -qiE 'unknown flag|unknown option|flag provided but not defined' && echo "$ERR_CONTENT" | grep -qE -- '--json'); then
    # Fallback path for older gh: plain create, then id lookup.
    : >"$ERR_TMP"
    if ISSUE_URL=$(gh "${GH_ARGS[@]}" 2>"$ERR_TMP"); then
        URL_LINE=$(echo "$ISSUE_URL" | grep -oE 'https?://[^[:space:]]+/issues/[0-9]+' | tail -1 || true)
        if [[ -z "$URL_LINE" ]]; then
            REDACTED_OUTPUT=$(redact "$ISSUE_URL") || emit_redaction_failure
            REDACTED_OUTPUT_FLAT=$(echo "$REDACTED_OUTPUT" | tr '\n' ' ' | head -c 500)
            echo "ISSUE_FAILED=true"
            echo "ISSUE_ERROR=gh issue create did not emit a URL (output: $REDACTED_OUTPUT_FLAT)"
            exit 2
        fi
        ISSUE_NUM=$(echo "$URL_LINE" | grep -oE '[0-9]+$')
        # rollback_orphan — best-effort `gh issue close` on the just-created
        # issue when the post-create id lookup fails on the old-gh fallback
        # path. Without this, an id-lookup transient leaves the issue open on
        # GitHub even though /issue reports failure (issue #546 plan-review
        # FINDING_2 / code-review FINDING_2). Failure to close is logged on
        # stderr (redacted) but does not change the exit path — the operator
        # still sees ISSUE_FAILED=true.
        rollback_orphan() {
            local rollback_err
            rollback_err=$(mktemp)
            if gh issue close --repo "$REPO" "$ISSUE_NUM" --reason "not planned" >/dev/null 2>"$rollback_err"; then
                echo "ROLLBACK: closed orphan issue #$ISSUE_NUM after id-lookup failure" >&2
            else
                local rb_redacted rb_flat
                rb_redacted=$(redact "$(cat "$rollback_err")") || rb_redacted="(redaction-helper failed)"
                rb_flat=$(echo "$rb_redacted" | tr '\n' ' ' | head -c 300)
                echo "ROLLBACK_FAILED: could not close orphan issue #$ISSUE_NUM ($URL_LINE): $rb_flat. Manually close." >&2
            fi
            rm -f "$rollback_err"
        }
        # Best-effort id lookup. Failure rolls back the just-created orphan
        # via rollback_orphan() (above) before emitting ISSUE_FAILED=true.
        if ISSUE_ID=$(gh api "/repos/$REPO/issues/$ISSUE_NUM" --jq '.id' 2>"$ERR_TMP"); then
            if [[ -z "$ISSUE_ID" || ! "$ISSUE_ID" =~ ^[0-9]+$ ]]; then
                ID_ERR=$(cat "$ERR_TMP")
                REDACTED_ERR=$(redact "$ID_ERR") || emit_redaction_failure
                ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
                rollback_orphan
                echo "ISSUE_FAILED=true"
                echo "ISSUE_ERROR=id-lookup returned non-numeric id for #$ISSUE_NUM (output: $ERR_FLAT)"
                exit 2
            fi
            echo "ISSUE_NUMBER=$ISSUE_NUM"
            echo "ISSUE_URL=$URL_LINE"
            echo "ISSUE_ID=$ISSUE_ID"
            echo "ISSUE_TITLE=$FINAL_TITLE"
            exit 0
        else
            ID_ERR=$(cat "$ERR_TMP")
            REDACTED_ERR=$(redact "$ID_ERR") || emit_redaction_failure
            ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
            rollback_orphan
            echo "ISSUE_FAILED=true"
            echo "ISSUE_ERROR=id-lookup failed for #$ISSUE_NUM after create: $ERR_FLAT"
            exit 2
        fi
    else
        ERR_CONTENT=$(cat "$ERR_TMP")
        REDACTED_ERR=$(redact "$ERR_CONTENT") || emit_redaction_failure
        ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
        echo "ISSUE_FAILED=true"
        echo "ISSUE_ERROR=$ERR_FLAT"
        exit 2
    fi
fi
# Genuine API failure (not a flag-incompatibility). Redact and surface.
REDACTED_ERR=$(redact "$ERR_CONTENT") || emit_redaction_failure
ERR_FLAT=$(echo "$REDACTED_ERR" | tr '\n' ' ' | head -c 500)
echo "ISSUE_FAILED=true"
echo "ISSUE_ERROR=$ERR_FLAT"
exit 2
