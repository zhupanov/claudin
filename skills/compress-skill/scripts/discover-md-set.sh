#!/usr/bin/env bash
# discover-md-set.sh — Thin shell wrapper around discover-md-set.py. The parser
# lives in Python because robust Markdown link extraction with fenced-block
# exclusion and path canonicalization is awkward in pure bash.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
exec python3 "$SCRIPT_DIR/discover-md-set.py" "$@"
