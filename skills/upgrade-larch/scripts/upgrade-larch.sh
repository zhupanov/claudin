#!/usr/bin/env bash
set -euo pipefail

recover() {
    echo "" >&2
    echo "Recovery: run these commands manually to reinstall:" >&2
    echo "  claude plugin marketplace add zhupanov/larch" >&2
    echo "  claude plugin install larch@larch-local" >&2
}
trap recover ERR

echo "Uninstalling larch plugin..."
claude plugin uninstall larch@larch-local 2>&1 || true

echo "Removing larch-local marketplace..."
claude plugin marketplace remove larch-local 2>&1 || true

echo "Re-adding larch marketplace from GitHub..."
claude plugin marketplace add zhupanov/larch 2>&1

echo "Installing larch plugin..."
claude plugin install larch@larch-local 2>&1

echo ""
echo "Upgrade complete. Restart Claude Code to apply the new version."
