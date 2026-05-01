# scripts/promote-release.sh — contract

`scripts/promote-release.sh` promotes a GitHub Release to "Latest" and clears its pre-release flag by semver version number. Used to designate which release appears on the repo's front page.

## Purpose

Every merge to main creates a GitHub Release with `--latest=false --prerelease` (via `.github/workflows/release-tag.yaml`). This script manually promotes one of those releases to "Latest" and clears the pre-release flag, making it the version shown on the repo's front page and installed by default via `claude plugin marketplace add`.

## Usage

```bash
scripts/promote-release.sh 12.4.5
```

The argument is a bare semver (`X.Y.Z`) — no `v` prefix. The script prepends `v` internally.

## Behavior

1. Validates the argument matches `^[0-9]+\.[0-9]+\.[0-9]+$`.
2. Checks that `v<VERSION>` exists as a GitHub Release via `gh release view`.
3. Queries `gh release list --json tagName,isLatest` to find the current "Latest" release.
4. If `v<VERSION>` is already "Latest", prints a message and exits 0.
5. Otherwise, runs `gh release edit v<VERSION> --latest --prerelease=false` to promote it (marks as latest and clears the pre-release flag).

## Exit codes

| Code | Meaning |
|------|---------|
| 0 | Release promoted (or already latest) |
| 1 | Release not found or `gh` error |
| 2 | Usage / argument error |

## Dependencies

- `gh` — authenticated with repo access

## Edit-in-sync

- `scripts/promote-release.sh` — the script itself
- `.github/workflows/release-tag.yaml` — creates releases with `--latest=false --prerelease`; this script is the manual promotion counterpart (sets latest, clears pre-release)
- `docs/installation-and-setup.md` — documents the "Latest" release concept and version pinning
