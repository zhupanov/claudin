#!/usr/bin/env bash
set -euo pipefail

# Upgrade the larch plugin to the latest version by removing and re-adding
# the marketplace, then reinstalling the plugin.

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
