#!/usr/bin/env bash
# Quick K-vote state helper: read/write LANES_SUCCEEDED for /research --scale=quick.
# Contract: skills/research/scripts/quick-vote-state.md
set -euo pipefail

SCRIPT_NAME="$(basename "$0")"

usage() {
  cat <<EOF >&2
Usage: $SCRIPT_NAME <subcommand> [args]

Subcommands:
  write --dir <RESEARCH_TMPDIR> --succeeded <N>
        Write LANES_SUCCEEDED=N to <RESEARCH_TMPDIR>/quick-vote-state.txt.
        N must be one of {0,1,2,3}.
  read  --dir <RESEARCH_TMPDIR>
        Print LANES_SUCCEEDED=<N> to stdout.
        Missing file or unparseable content prints LANES_SUCCEEDED=0.
EOF
  exit 2
}

[[ $# -ge 1 ]] || usage
SUBCOMMAND="$1"
shift

DIR=""
SUCCEEDED=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir)
      DIR="${2:-}"
      shift 2
      ;;
    --succeeded)
      SUCCEEDED="${2:-}"
      shift 2
      ;;
    *)
      echo "$SCRIPT_NAME: unknown arg: $1" >&2
      usage
      ;;
  esac
done

[[ -n "$DIR" ]] || { echo "$SCRIPT_NAME: --dir is required" >&2; exit 2; }

STATE_FILE="$DIR/quick-vote-state.txt"

case "$SUBCOMMAND" in
  write)
    [[ -n "$SUCCEEDED" ]] || { echo "$SCRIPT_NAME: --succeeded is required for write" >&2; exit 2; }
    case "$SUCCEEDED" in
      0|1|2|3) ;;
      *) echo "$SCRIPT_NAME: --succeeded must be one of {0,1,2,3} (got: $SUCCEEDED)" >&2; exit 2 ;;
    esac
    [[ -d "$DIR" ]] || { echo "$SCRIPT_NAME: --dir does not exist: $DIR" >&2; exit 2; }
    TMP_FILE="$(mktemp "$DIR/quick-vote-state.XXXXXX.tmp")"
    printf 'LANES_SUCCEEDED=%s\n' "$SUCCEEDED" > "$TMP_FILE"
    mv "$TMP_FILE" "$STATE_FILE"
    echo "WROTE=$STATE_FILE"
    echo "LANES_SUCCEEDED=$SUCCEEDED"
    ;;
  read)
    if [[ ! -f "$STATE_FILE" ]]; then
      echo "LANES_SUCCEEDED=0"
      exit 0
    fi
    LINE="$(grep -E '^LANES_SUCCEEDED=' "$STATE_FILE" 2>/dev/null | head -1 || true)"
    VALUE="${LINE#LANES_SUCCEEDED=}"
    case "$VALUE" in
      0|1|2|3) echo "LANES_SUCCEEDED=$VALUE" ;;
      *) echo "LANES_SUCCEEDED=0" ;;
    esac
    ;;
  *)
    echo "$SCRIPT_NAME: unknown subcommand: $SUBCOMMAND" >&2
    usage
    ;;
esac
