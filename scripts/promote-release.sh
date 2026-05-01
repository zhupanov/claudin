#!/usr/bin/env bash
# promote-release.sh — Promote a GitHub Release to "Latest" and clear pre-release.
#
# Takes a semver version (X.Y.Z, no "v" prefix) and marks the
# corresponding GitHub Release as "Latest" and clears the pre-release
# flag via gh release edit.
#
# Usage:
#   promote-release.sh X.Y.Z
#
# Exit codes:
#   0 — release promoted (or already latest)
#   1 — release not found or gh error
#   2 — usage/argument error

set -euo pipefail

usage() { echo "Usage: promote-release.sh X.Y.Z" >&2; }

if [[ $# -ne 1 ]]; then
    usage
    exit 2
fi

VERSION="$1"

if [[ ! "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: invalid semver format: $VERSION (expected X.Y.Z)" >&2
    usage
    exit 2
fi

TAG="v${VERSION}"

if ! gh release view "$TAG" >/dev/null; then
    echo "ERROR: release $TAG not found." >&2
    exit 1
fi

CURRENT_LATEST=$(gh release list --json tagName,isLatest --jq '.[] | select(.isLatest) | .tagName') || exit 1

if [[ "$CURRENT_LATEST" == "$TAG" ]]; then
    IS_PRERELEASE=$(gh release view "$TAG" --json isPrerelease --jq '.isPrerelease')
    if [[ "$IS_PRERELEASE" == "true" ]]; then
        gh release edit "$TAG" --prerelease=false || exit 1
        echo "$TAG is already the latest release; cleared pre-release flag."
    else
        echo "$TAG is already the latest release."
    fi
    exit 0
fi

gh release edit "$TAG" --latest --prerelease=false || exit 1
echo "Promoted $TAG to latest release."
