#!/usr/bin/env bash
# write-sentinel.sh — Write the /issue post-success sentinel KV file atomically.
#
# Called from /issue Step 7 after aggregate counters have been emitted. The
# sentinel proves /issue ran to completion of Step 7 successfully — it is the
# load-bearing mechanical signal a parent skill (e.g. /research's "## Filing
# findings as issues" numbered procedure) reads via verify-skill-called.sh
# --sentinel-file to confirm the child completed before continuing.
#
# Gate:
#   Write the sentinel only when ISSUES_FAILED=0 AND --dry-run is not set.
#   The sentinel proves *execution*, not *creation count*: the all-dedup case
#   (ISSUES_CREATED=0, ISSUES_DEDUPLICATED>=1, ISSUES_FAILED=0) DOES write the
#   sentinel — that is a legitimate /issue success outcome (issue #509 plan
#   review FINDING_1). Counters are recorded inside the sentinel for any
#   consumer that wants them.
#
# Atomicity:
#   Writes the full content to a same-directory mktemp, then `mv` to the
#   target path. Same pattern as scripts/write-session-env.sh. The mv is
#   atomic on a single filesystem, so the target is either the complete
#   final content or absent — never partial. NOTE: this is rename-atomicity,
#   not durability. The script does NOT call fsync(2); a host crash before
#   the kernel flushes the dirty page cache could lose the rename. That is
#   acceptable for this signal because the parent runs in the same session
#   as the child — a host crash mid-run discards both processes.
#
# Channel discipline:
#   All status output goes to STDERR, not stdout. /issue Step 7's published
#   stdout grammar is `^(ISSUES?_[A-Z0-9_]+)=(.*)$`; this helper preserves
#   that contract for downstream parsers like /implement Step 9a.1 (issue
#   #509 plan review FINDING_5).
#
# Usage:
#   write-sentinel.sh --path <path> \
#                     --issues-created <N> \
#                     --issues-deduplicated <N> \
#                     --issues-failed <N> \
#                     [--dry-run]
#
# Stderr (KV):
#   WROTE=true                      — sentinel file written successfully
#   WROTE=false REASON=dry_run      — --dry-run was set, sentinel suppressed
#   WROTE=false REASON=failures     — ISSUES_FAILED >= 1, sentinel suppressed
#   ERROR=<msg>                     — argument error (caller misuse)
#
# Sentinel content (KV at <path>):
#   ISSUE_SENTINEL_VERSION=1
#   ISSUES_CREATED=<N>
#   ISSUES_DEDUPLICATED=<N>
#   ISSUES_FAILED=<N>
#   TIMESTAMP=<ISO 8601 UTC>
#
# Exit codes: 0 always (skipped is normal). Argument errors → 1.

set -euo pipefail

PATH_ARG=""
ISSUES_CREATED=""
ISSUES_DEDUPLICATED=""
ISSUES_FAILED=""
DRY_RUN="false"

# require_value: emit a stable ERROR= line when a value-taking flag has no
# value (e.g., final argv token is `--path` with nothing after it). Uses
# ${2-} so `set -u` does not abort with a cryptic "unbound variable" before
# the script can emit its documented stderr contract (#509 review FINDING_3).
require_value() {
  local flag="$1" value="${2-}"
  if [[ -z "$value" ]]; then
    echo "ERROR=Missing value for $flag" >&2
    exit 1
  fi
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --path)                require_value "$1" "${2-}"; PATH_ARG="$2"; shift 2 ;;
    --issues-created)      require_value "$1" "${2-}"; ISSUES_CREATED="$2"; shift 2 ;;
    --issues-deduplicated) require_value "$1" "${2-}"; ISSUES_DEDUPLICATED="$2"; shift 2 ;;
    --issues-failed)       require_value "$1" "${2-}"; ISSUES_FAILED="$2"; shift 2 ;;
    --dry-run)             DRY_RUN="true"; shift ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$PATH_ARG" ]]; then
  echo "ERROR=Missing required argument: --path" >&2
  exit 1
fi
if [[ -z "$ISSUES_CREATED" || -z "$ISSUES_DEDUPLICATED" || -z "$ISSUES_FAILED" ]]; then
  echo "ERROR=Missing required arguments: --issues-created, --issues-deduplicated, --issues-failed" >&2
  exit 1
fi

# Path validation: must be absolute, no `..` components.
case "$PATH_ARG" in
  /*) ;;
  *)
    echo "ERROR=--path must be absolute: $PATH_ARG" >&2
    exit 1
    ;;
esac
case "$PATH_ARG" in
  *..*)
    echo "ERROR=--path must not contain '..': $PATH_ARG" >&2
    exit 1
    ;;
esac

# Numeric validation.
if ! [[ "$ISSUES_CREATED" =~ ^[0-9]+$ && "$ISSUES_DEDUPLICATED" =~ ^[0-9]+$ && "$ISSUES_FAILED" =~ ^[0-9]+$ ]]; then
  echo "ERROR=Counter values must be non-negative integers" >&2
  exit 1
fi

# Gate.
if [[ "$DRY_RUN" == "true" ]]; then
  echo "WROTE=false REASON=dry_run" >&2
  exit 0
fi

if [[ "$ISSUES_FAILED" -gt 0 ]]; then
  echo "WROTE=false REASON=failures" >&2
  exit 0
fi

# Write atomically: same-directory mktemp + mv.
PARENT_DIR=$(dirname "$PATH_ARG")
mkdir -p "$PARENT_DIR"
TMPFILE=$(mktemp "${PATH_ARG}.tmp.XXXXXX")

TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat > "$TMPFILE" <<EOF
ISSUE_SENTINEL_VERSION=1
ISSUES_CREATED=$ISSUES_CREATED
ISSUES_DEDUPLICATED=$ISSUES_DEDUPLICATED
ISSUES_FAILED=$ISSUES_FAILED
TIMESTAMP=$TIMESTAMP
EOF

mv "$TMPFILE" "$PATH_ARG"
echo "WROTE=true" >&2
