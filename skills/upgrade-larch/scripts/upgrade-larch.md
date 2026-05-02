# scripts/upgrade-larch.sh — contract

Upgrades the larch plugin to the latest version by removing and re-adding the marketplace from GitHub, then reinstalling.

## Purpose

Automates the full teardown-and-reinstall sequence needed to pick up the latest larch version. Invoked by `/upgrade-larch`.

## Behavior

1. Uninstalls `larch@larch-local` (best-effort — may not be installed).
2. Removes the `larch-local` marketplace (best-effort — may not be registered).
3. Re-adds the marketplace from `zhupanov/larch` on GitHub.
4. Installs the `larch` plugin from the freshly-added marketplace.

Steps 1–2 use `|| true` because the plugin/marketplace may not exist (first install, or already removed). Steps 3–4 run under `set -e` and will fail loudly on network errors, auth issues, or CLI problems. On failure after teardown, the script prints recovery commands so the user can manually re-add.

## Edit-in-sync

- `skills/upgrade-larch/SKILL.md` — the skill that invokes this script
- `docs/installation-and-setup.md` — documents the Upgrade flow
