---
name: upgrade-larch
description: "Use when upgrading the larch plugin to the latest version. Removes and re-adds the marketplace, then reinstalls the plugin to pick up the newest release."
allowed-tools: Bash
---

Upgrade the larch plugin to the latest version.

## Steps

1. Run the upgrade script:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/upgrade-larch/scripts/upgrade-larch.sh
```

2. Verify the upgrade succeeded by checking the installed version:

```bash
claude plugin list 2>&1 | grep -A2 'larch@larch-local'
```

Confirm the version line shows the expected latest version.

3. Tell the user to restart Claude Code to apply the new version.
