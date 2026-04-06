#!/usr/bin/env bash
# git-commit.sh — Stage files and commit with Co-Authored-By trailer.
#
# Usage: git-commit.sh -m "message" [--no-trailer] [file1 file2 ...]
#
# Stages the specified files (if any) via `git add`, then commits using
# `git commit --file <tmpfile>` to avoid shell quoting issues with
# multi-line messages. Appends the Co-Authored-By trailer by default.
#
# Options:
#   -m <message>     Commit message (required). Written verbatim to a temp
#                    file, so newlines and special characters are safe.
#   --no-trailer     Omit the Co-Authored-By trailer.
#
# Positional args:   Files to stage via `git add`. If none are provided,
#                    commits whatever is already staged.
#
# Exit codes:
#   0  Success
#   1  Usage error (missing -m, empty message)
#   >0 git add or git commit failure (passthrough)

set -euo pipefail

TRAILER="Co-Authored-By: Claude Code <noreply@anthropic.com>"
MESSAGE=""
NO_TRAILER=false
FILES=()

# --- Parse arguments ---
while [[ $# -gt 0 ]]; do
  case "$1" in
    -m)
      if [[ $# -lt 2 ]]; then
        echo "git-commit.sh: -m requires a message argument" >&2
        exit 1
      fi
      MESSAGE="$2"
      shift 2
      ;;
    --no-trailer)
      NO_TRAILER=true
      shift
      ;;
    --)
      shift
      FILES+=("$@")
      break
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

# --- Validate message ---
TRIMMED="${MESSAGE#"${MESSAGE%%[![:space:]]*}"}"
TRIMMED="${TRIMMED%"${TRIMMED##*[![:space:]]}"}"
if [[ -z "$TRIMMED" ]]; then
  echo "git-commit.sh: commit message must be non-empty" >&2
  exit 1
fi

# --- Stage files ---
if [[ ${#FILES[@]} -gt 0 ]]; then
  git add -- "${FILES[@]}"
fi

# --- Write message and append trailer ---
TMPFILE=$(mktemp)
trap 'rm -f "$TMPFILE"' EXIT

printf '%s\n' "$MESSAGE" > "$TMPFILE"

if [[ "$NO_TRAILER" == false ]]; then
  # Use git's native trailer machinery to append Co-Authored-By.
  # --if-exists addIfDifferent avoids duplicates when the message
  # already contains a Co-Authored-By with a different value, and
  # skips appending when the exact same trailer is already present.
  git interpret-trailers --in-place \
    --if-exists addIfDifferent --if-missing add \
    --trailer "$TRAILER" "$TMPFILE"
fi

git commit --file "$TMPFILE"
