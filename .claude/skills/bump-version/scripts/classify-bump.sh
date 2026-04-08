#!/usr/bin/env bash
# classify-bump.sh — Deterministic semver classifier for /bump-version skill.
#
# Scope: only inspects public plugin surface (skills/**, agents/**).
# Changes under .claude/**, scripts/**, hooks/**, docs/**, .github/**, etc.
# contribute only to the default PATCH baseline.
#
# Rules (highest severity wins):
#   MAJOR — deleted/renamed SKILL.md or agents/*.md, changed `name:` frontmatter,
#           removed `--flag` bullet, removed `--flag` in argument-hint
#   MINOR — new SKILL.md or agents/*.md, new `--flag` bullet, new `--flag` in argument-hint
#   PATCH — default (every PR bumps at least PATCH)
#
# Idempotent no-op: if HEAD..BASE already contains a commit matching
# `^Bump version to X\.Y\.Z$`, emits BUMP_TYPE=NONE and exits 0.
#
# Output (stdout, KEY=VALUE):
#   CURRENT_VERSION=<x.y.z>
#   NEW_VERSION=<x.y.z>                (same as current if BUMP_TYPE=NONE)
#   BUMP_TYPE=MAJOR|MINOR|PATCH|NONE
#   REASONING_FILE=<path>
#
# Reasoning log: ${IMPLEMENT_TMPDIR:-$PWD/.git}/bump-version-reasoning.md
#
# Exit codes: 0 success, 1 validation failure

set -euo pipefail

PLUGIN_JSON="$PWD/.claude-plugin/plugin.json"

err() {
  echo "ERROR: $*" >&2
  exit 1
}

# Validate plugin.json exists and parses.
[[ -f "$PLUGIN_JSON" ]] || err "$PLUGIN_JSON not found"
jq empty "$PLUGIN_JSON" 2>/dev/null || err "$PLUGIN_JSON is not valid JSON"

# Read current version.
CURRENT_VERSION=$(jq -r '.version // empty' "$PLUGIN_JSON")
[[ -n "$CURRENT_VERSION" ]] || err "$PLUGIN_JSON missing .version field"
[[ "$CURRENT_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || err "version '$CURRENT_VERSION' is not semver (expected X.Y.Z)"

# Best-effort fetch so origin/main is fresh. Non-fatal.
git fetch origin main --quiet 2>/dev/null || true

# Resolve BASE: prefer local main, fall back to origin/main.
BASE=""
if git rev-parse --verify main >/dev/null 2>&1; then
  BASE=$(git merge-base main HEAD 2>/dev/null || true)
fi
if [[ -z "$BASE" ]] && git rev-parse --verify origin/main >/dev/null 2>&1; then
  BASE=$(git merge-base origin/main HEAD 2>/dev/null || true)
fi
[[ -n "$BASE" ]] || err "could not resolve merge-base against main or origin/main"

# Reasoning log path.
REASONING_DIR="${IMPLEMENT_TMPDIR:-$PWD/.git}"
mkdir -p "$REASONING_DIR" 2>/dev/null || true
REASONING_FILE="$REASONING_DIR/bump-version-reasoning.md"

# Helper: append to reasoning log.
log() {
  printf '%s\n' "$*" >> "$REASONING_FILE"
}

# Initialize log.
{
  echo "# Version Bump Reasoning"
  echo ""
  echo "- **Base commit**: \`$(git rev-parse --short "$BASE")\` ($(git log -1 --format=%s "$BASE" 2>/dev/null || echo '?'))"
  echo "- **Current version**: \`$CURRENT_VERSION\`"
  echo "- **Classification scope**: \`skills/**\` and \`agents/**\` only (public plugin surface)."
  echo ""
} > "$REASONING_FILE"

# Idempotency check: already-bumped branch?
ALREADY_BUMPED_SHA=$(git log --format='%H %s' "$BASE..HEAD" 2>/dev/null | \
  awk '/ Bump version to [0-9]+\.[0-9]+\.[0-9]+$/ { print $1; exit }' || true)

if [[ -n "$ALREADY_BUMPED_SHA" ]]; then
  BUMPED_SUBJECT=$(git log -1 --format=%s "$ALREADY_BUMPED_SHA")
  log "## Result: NONE (already bumped)"
  log ""
  log "Branch already contains a version bump commit: \`$(git rev-parse --short "$ALREADY_BUMPED_SHA")\` — \"$BUMPED_SUBJECT\""
  log ""
  log "No additional bump will be applied."

  echo "CURRENT_VERSION=$CURRENT_VERSION"
  echo "NEW_VERSION=$CURRENT_VERSION"
  echo "BUMP_TYPE=NONE"
  echo "REASONING_FILE=$REASONING_FILE"
  exit 0
fi

# Collect file-level changes in public surface.
# Use -M for rename detection.
NAME_STATUS=$(git diff -M --name-status "$BASE" HEAD -- skills agents 2>/dev/null || true)

# Track evidence.
MAJOR_REASONS=()
MINOR_REASONS=()

# Process file-level changes.
while IFS=$'\t' read -r status old new_or_blank; do
  [[ -z "${status:-}" ]] && continue

  case "$status" in
    D)
      # Deleted file in public surface.
      if [[ "$old" == skills/*/SKILL.md || "$old" == agents/*.md ]]; then
        MAJOR_REASONS+=("Deleted \`$old\`")
      fi
      ;;
    A)
      # Added file in public surface.
      if [[ "$old" == skills/*/SKILL.md || "$old" == agents/*.md ]]; then
        MINOR_REASONS+=("Added \`$old\`")
      fi
      ;;
    R*)
      # Renamed file: $old is source, $new_or_blank is destination.
      if [[ "$old" == skills/*/SKILL.md ]]; then
        MAJOR_REASONS+=("Renamed skill \`$old\` → \`$new_or_blank\`")
      elif [[ "$old" == agents/*.md ]]; then
        MAJOR_REASONS+=("Renamed agent \`$old\` → \`$new_or_blank\`")
      fi
      ;;
    M)
      # Modified file — inspect content diff for flag/name changes.
      if [[ "$old" == skills/*/SKILL.md || "$old" == agents/*.md ]]; then
        CONTENT_DIFF=$(git diff "$BASE" HEAD -- "$old" 2>/dev/null || true)

        # Check for name: frontmatter change.
        # Extract removed and added name: lines (only frontmatter, not body).
        OLD_NAME=$(echo "$CONTENT_DIFF" | awk '/^-name: / { sub(/^-name: */, ""); print; exit }' || true)
        NEW_NAME=$(echo "$CONTENT_DIFF" | awk '/^\+name: / { sub(/^\+name: */, ""); print; exit }' || true)
        if [[ -n "$OLD_NAME" && -n "$NEW_NAME" && "$OLD_NAME" != "$NEW_NAME" ]]; then
          MAJOR_REASONS+=("Renamed \`name:\` frontmatter in \`$old\` ($OLD_NAME → $NEW_NAME)")
        fi

        # Check for removed/added flag bullets.
        # Pattern: lines of form `- \`--flag\`:` or `- \`--flag <arg>\`:`
        REMOVED_FLAGS=$(echo "$CONTENT_DIFF" | grep -E '^-[[:space:]]*-[[:space:]]*`--[a-zA-Z0-9_-]+' || true)
        ADDED_FLAGS=$(echo "$CONTENT_DIFF" | grep -E '^\+[[:space:]]*-[[:space:]]*`--[a-zA-Z0-9_-]+' || true)

        if [[ -n "$REMOVED_FLAGS" ]]; then
          while IFS= read -r line; do
            FLAG_TOKEN=$(echo "$line" | grep -oE '\-\-[a-zA-Z0-9_-]+' | head -1 || true)
            [[ -n "$FLAG_TOKEN" ]] && MAJOR_REASONS+=("Removed flag bullet \`$FLAG_TOKEN\` from \`$old\`")
          done <<< "$REMOVED_FLAGS"
        fi
        if [[ -n "$ADDED_FLAGS" ]]; then
          while IFS= read -r line; do
            FLAG_TOKEN=$(echo "$line" | grep -oE '\-\-[a-zA-Z0-9_-]+' | head -1 || true)
            [[ -n "$FLAG_TOKEN" ]] && MINOR_REASONS+=("Added flag bullet \`$FLAG_TOKEN\` in \`$old\`")
          done <<< "$ADDED_FLAGS"
        fi

        # Check for argument-hint: token changes.
        OLD_ARG_HINT=$(echo "$CONTENT_DIFF" | awk '/^-argument-hint: / { sub(/^-argument-hint: */, ""); print; exit }' || true)
        NEW_ARG_HINT=$(echo "$CONTENT_DIFF" | awk '/^\+argument-hint: / { sub(/^\+argument-hint: */, ""); print; exit }' || true)
        if [[ -n "$OLD_ARG_HINT" || -n "$NEW_ARG_HINT" ]]; then
          # Extract --flag tokens from each.
          OLD_TOKENS=$(echo "$OLD_ARG_HINT" | grep -oE '\-\-[a-zA-Z0-9_-]+' | sort -u || true)
          NEW_TOKENS=$(echo "$NEW_ARG_HINT" | grep -oE '\-\-[a-zA-Z0-9_-]+' | sort -u || true)
          REMOVED_TOKENS=$(comm -23 <(echo "$OLD_TOKENS") <(echo "$NEW_TOKENS") 2>/dev/null || true)
          ADDED_TOKENS=$(comm -13 <(echo "$OLD_TOKENS") <(echo "$NEW_TOKENS") 2>/dev/null || true)
          if [[ -n "$REMOVED_TOKENS" ]]; then
            while IFS= read -r tok; do
              [[ -n "$tok" ]] && MAJOR_REASONS+=("Removed \`$tok\` from argument-hint in \`$old\`")
            done <<< "$REMOVED_TOKENS"
          fi
          if [[ -n "$ADDED_TOKENS" ]]; then
            while IFS= read -r tok; do
              [[ -n "$tok" ]] && MINOR_REASONS+=("Added \`$tok\` to argument-hint in \`$old\`")
            done <<< "$ADDED_TOKENS"
          fi
        fi
      fi
      ;;
  esac
done <<< "$NAME_STATUS"

# Determine bump type.
if [[ ${#MAJOR_REASONS[@]} -gt 0 ]]; then
  BUMP_TYPE="MAJOR"
elif [[ ${#MINOR_REASONS[@]} -gt 0 ]]; then
  BUMP_TYPE="MINOR"
else
  BUMP_TYPE="PATCH"
fi

# Compute new version.
IFS='.' read -r MAJ MIN PAT <<< "$CURRENT_VERSION"
case "$BUMP_TYPE" in
  MAJOR) NEW_VERSION="$((MAJ + 1)).0.0" ;;
  MINOR) NEW_VERSION="${MAJ}.$((MIN + 1)).0" ;;
  PATCH) NEW_VERSION="${MAJ}.${MIN}.$((PAT + 1))" ;;
esac

# Log reasoning.
log "## Result: $BUMP_TYPE"
log ""
log "- **New version**: \`$NEW_VERSION\`"
log ""

if [[ ${#MAJOR_REASONS[@]} -gt 0 ]]; then
  log "### MAJOR evidence"
  for r in "${MAJOR_REASONS[@]}"; do log "- $r"; done
  log ""
fi

if [[ ${#MINOR_REASONS[@]} -gt 0 ]]; then
  log "### MINOR evidence"
  for r in "${MINOR_REASONS[@]}"; do log "- $r"; done
  log ""
fi

if [[ "$BUMP_TYPE" == "PATCH" ]]; then
  log "### PATCH rationale"
  log ""
  log "No MAJOR or MINOR evidence found in the public plugin surface. Defaulting to PATCH per policy (\"every PR must bump at least PATCH\")."
  log ""
fi

# Emit machine-parseable output.
echo "CURRENT_VERSION=$CURRENT_VERSION"
echo "NEW_VERSION=$NEW_VERSION"
echo "BUMP_TYPE=$BUMP_TYPE"
echo "REASONING_FILE=$REASONING_FILE"
