#!/usr/bin/env bash
# parse-args.sh — argument parser for /umbrella
#
# Stdout grammar (one KV per line):
#   LABELS=<newline-joined labels — empty if none>
#   TITLE_PREFIX=<prefix string — empty if none>
#   REPO=<owner/repo — empty if not specified>
#   CLOSED_WINDOW_DAYS=<integer — empty if not specified>
#   DRY_RUN=<true|false>
#   GO=<true|false>
#   DEBUG=<true|false>
#   TASK=<everything after the last flag — may be empty>
#   UMBRELLA_TMPDIR=<absolute path to mktemp dir owned by this run>
# On error, print `ERROR=<message>` to stderr and exit non-zero.

set -euo pipefail

LABELS=""
TITLE_PREFIX=""
REPO=""
CLOSED_WINDOW_DAYS=""
DRY_RUN="false"
GO="false"
DEBUG="false"

# Single positional argument: the entire $ARGUMENTS string from the SKILL.
# Tokenize manually so we can stop at the first non-flag token and preserve
# the remainder verbatim as TASK (including its embedded whitespace).
ARGS_STR="${1:-}"

# shellcheck disable=SC2206
TOKENS=( $ARGS_STR )

i=0
n="${#TOKENS[@]}"
TASK_START=-1

while [ "$i" -lt "$n" ]; do
  tok="${TOKENS[$i]}"
  case "$tok" in
    --label)
      i=$((i + 1))
      if [ "$i" -ge "$n" ]; then
        echo "ERROR=--label requires a value" >&2
        exit 1
      fi
      if [ -z "$LABELS" ]; then
        LABELS="${TOKENS[$i]}"
      else
        LABELS="${LABELS}"$'\n'"${TOKENS[$i]}"
      fi
      ;;
    --title-prefix)
      i=$((i + 1))
      if [ "$i" -ge "$n" ]; then
        echo "ERROR=--title-prefix requires a value" >&2
        exit 1
      fi
      TITLE_PREFIX="${TOKENS[$i]}"
      ;;
    --repo)
      i=$((i + 1))
      if [ "$i" -ge "$n" ]; then
        echo "ERROR=--repo requires a value" >&2
        exit 1
      fi
      REPO="${TOKENS[$i]}"
      ;;
    --closed-window-days)
      i=$((i + 1))
      if [ "$i" -ge "$n" ]; then
        echo "ERROR=--closed-window-days requires a value" >&2
        exit 1
      fi
      CLOSED_WINDOW_DAYS="${TOKENS[$i]}"
      case "$CLOSED_WINDOW_DAYS" in
        ''|*[!0-9]*)
          echo "ERROR=--closed-window-days must be a non-negative integer; got '$CLOSED_WINDOW_DAYS'" >&2
          exit 1
          ;;
      esac
      ;;
    --dry-run) DRY_RUN="true" ;;
    --go) GO="true" ;;
    --debug) DEBUG="true" ;;
    --) i=$((i + 1)); TASK_START=$i; break ;;
    --*)
      echo "ERROR=Unknown flag: $tok" >&2
      exit 1
      ;;
    *)
      TASK_START=$i
      break
      ;;
  esac
  i=$((i + 1))
done

# Reconstruct TASK from TASK_START to end of original string. Cheap approach:
# walk the original string, skip the first TASK_START whitespace-delimited
# tokens, take the rest verbatim.
TASK=""
if [ "$TASK_START" -ge 0 ] && [ "$TASK_START" -lt "$n" ]; then
  # Skip leading $TASK_START tokens from $ARGS_STR. Use awk for whitespace-aware token skipping.
  TASK=$(printf '%s' "$ARGS_STR" | awk -v skip="$TASK_START" '
    {
      out = ""
      kept = 0
      for (i = 1; i <= NF; i++) {
        if (i <= skip) continue
        if (kept == 0) { out = $i; kept = 1 } else { out = out " " $i }
      }
      printf "%s", out
    }
  ')
fi

UMBRELLA_TMPDIR=$(mktemp -d -t claude-umbrella-XXXXXX)

printf 'LABELS=%s\n' "$LABELS"
printf 'TITLE_PREFIX=%s\n' "$TITLE_PREFIX"
printf 'REPO=%s\n' "$REPO"
printf 'CLOSED_WINDOW_DAYS=%s\n' "$CLOSED_WINDOW_DAYS"
printf 'DRY_RUN=%s\n' "$DRY_RUN"
printf 'GO=%s\n' "$GO"
printf 'DEBUG=%s\n' "$DEBUG"
printf 'TASK=%s\n' "$TASK"
printf 'UMBRELLA_TMPDIR=%s\n' "$UMBRELLA_TMPDIR"
