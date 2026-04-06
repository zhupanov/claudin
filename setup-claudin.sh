#!/usr/bin/env bash
# setup-claudin.sh — Sync symlinks from a client repo's .claude/ into claudin/.claude/ (the submodule).
#
# Intended to be run from the root of a client repo that has claudin as a git submodule.
# The script derives the submodule path from its own location, so it works regardless of
# the submodule directory name.
#
# Symlink strategy (hybrid):
#   - Skill directories (contain SKILL.md) → directory-level symlinks
#   - Everything else (scripts, agents, shared docs) → file-level symlinks
#   - settings*.json → always skipped (client must maintain their own)
#
# Conflict handling:
#   - If a non-symlink file or directory exists at a target path → exit 1 with error
#   - If a correct symlink exists → skip (idempotent)
#   - If a symlink exists but points to wrong target → update it
#
# Dead symlink cleanup:
#   - Removes symlinks under .claude/ whose resolved target points into the claudin
#     submodule but whose target no longer exists.
#
# Usage:
#   ./claudin/setup-claudin.sh
#
# Exit codes:
#   0 — success
#   1 — error (conflict, missing submodule, not a git repo, etc.)

set -euo pipefail

# --- Derive paths ---
# CLAUDIN_DIR: absolute path to the claudin submodule (where this script lives)
CLAUDIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# REPO_ROOT: the git repository root of the client repo
REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: Not inside a git repository." >&2
    exit 1
}
REPO_ROOT="$(cd "$REPO_ROOT" && pwd -P)"

# Verify we are running from the repo root
if [[ "$(pwd -P)" != "$REPO_ROOT" ]]; then
    echo "ERROR: Must run from the repository root ($REPO_ROOT), not $(pwd -P)." >&2
    exit 1
fi

# Verify the claudin .claude directory exists
if [[ ! -d "$CLAUDIN_DIR/.claude" ]]; then
    echo "ERROR: $CLAUDIN_DIR/.claude does not exist. Is the submodule checked out?" >&2
    exit 1
fi

# Verify the claudin submodule is inside the repo root
if [[ "$CLAUDIN_DIR" != "$REPO_ROOT/"* ]]; then
    echo "ERROR: claudin submodule ($CLAUDIN_DIR) is not inside the repo root ($REPO_ROOT)." >&2
    echo "  Run this script from the repository that contains claudin as a submodule." >&2
    exit 1
fi

# CLAUDIN_REL: relative path from repo root to the claudin submodule
CLAUDIN_REL="${CLAUDIN_DIR#"$REPO_ROOT"/}"

# --- Helper: compute relative symlink target ---
# Given a symlink path relative to repo root (e.g., .claude/skills/design)
# and a target path relative to repo root (e.g., claudin/.claude/skills/design),
# compute the relative path from the symlink's parent to the target.
compute_relpath() {
    local link_path="$1"  # e.g., .claude/scripts/generic/claudin/foo.sh
    local target_path="$2"  # e.g., claudin/.claude/scripts/generic/claudin/foo.sh

    local parent_dir
    parent_dir="$(dirname "$link_path")"

    # Count depth of parent directory (number of / separated components)
    local depth=0
    local tmp="$parent_dir"
    while [[ "$tmp" != "." && -n "$tmp" ]]; do
        tmp="$(dirname "$tmp")"
        depth=$((depth + 1))
    done

    # Build ../ prefix
    local prefix=""
    local i
    for ((i = 0; i < depth; i++)); do
        prefix="../${prefix}"
    done

    echo "${prefix}${target_path}"
}

# --- Helper: create a symlink with validation ---
create_link() {
    local link_path="$1"   # relative to repo root
    local target_path="$2" # relative to repo root (in claudin)
    local link_type="$3"   # "dir" or "file" (for messages only)

    # Ensure parent directory exists
    mkdir -p "$(dirname "$link_path")"

    if [[ -L "$link_path" ]]; then
        # Symlink already exists — check if it points to the right target
        local current_target
        current_target="$(readlink "$link_path")"
        local expected_target
        expected_target="$(compute_relpath "$link_path" "$target_path")"

        if [[ "$current_target" == "$expected_target" ]]; then
            # Correct symlink, skip
            return 0
        else
            # Wrong target, update
            rm "$link_path"
            ln -s "$expected_target" "$link_path"
            echo "  updated ($link_type): $link_path -> $expected_target"
        fi
    elif [[ -e "$link_path" ]]; then
        # Non-symlink exists — conflict
        echo "ERROR: Conflict at '$link_path' — a non-symlink file or directory already exists." >&2
        echo "  Remove or rename it before re-running this script." >&2
        exit 1
    else
        # Create new symlink
        local rel_target
        rel_target="$(compute_relpath "$link_path" "$target_path")"
        ln -s "$rel_target" "$link_path"
        echo "  linked ($link_type): $link_path -> $rel_target"
    fi

    # Validate the symlink resolves to an existing target
    if [[ ! -e "$link_path" ]]; then
        echo "ERROR: Symlink '$link_path' was created but does not resolve to an existing target." >&2
        echo "  This indicates a bug in relative path computation." >&2
        exit 1
    fi
}

# --- Phase 1: Create symlinks ---
echo "Phase 1: Creating symlinks from .claude/ into $CLAUDIN_REL/.claude/..."

# Walk the claudin .claude directory
while IFS= read -r -d '' entry; do
    # entry is relative to CLAUDIN_DIR/.claude, e.g., "skills/design" or "agents/generic-reviewer.md"
    local_path="${entry#"$CLAUDIN_DIR/.claude/"}"

    # Skip settings*.json — client must maintain their own
    if [[ "$local_path" == settings*.json ]]; then
        # Remove any existing symlink from a prior version that linked settings files
        if [[ -L ".claude/$local_path" ]]; then
            rm ".claude/$local_path"
            echo "  removed stale symlink: .claude/$local_path (maintain your own)"
        else
            echo "  skipped: .claude/$local_path (maintain your own)"
        fi
        continue
    fi

    # Determine the link path in the client repo
    link_path=".claude/$local_path"
    target_path="$CLAUDIN_REL/.claude/$local_path"

    # Check if this is a skill directory (first-level child of skills/ with SKILL.md)
    if [[ "$entry" == "$CLAUDIN_DIR/.claude/skills/"* ]]; then
        # Extract the first-level name under skills/
        local_under_skills="${local_path#skills/}"
        first_component="${local_under_skills%%/*}"

        # Only process first-level entries under skills/
        if [[ "$local_under_skills" == "$first_component" ]]; then
            # Skip relevant-checks — repo-specific skill, client must maintain their own
            if [[ "$first_component" == "relevant-checks" ]]; then
                echo "  skipped: .claude/skills/relevant-checks (repo-specific, maintain your own)"
                continue
            fi
            if [[ -d "$entry" && -f "$entry/SKILL.md" ]]; then
                # Skill directory — directory-level symlink
                create_link "$link_path" "$target_path" "skill dir"
            elif [[ -d "$entry" ]]; then
                # Non-skill directory under skills/ (e.g., shared/) — descend into it
                # File-level symlinks will be handled when we encounter individual files
                :
            elif [[ -f "$entry" ]]; then
                # File directly under skills/ (unusual but handle it)
                create_link "$link_path" "$target_path" "file"
            fi
        else
            # Nested entry under skills/ — check if the first-level parent is a skill dir
            first_level_dir="$CLAUDIN_DIR/.claude/skills/$first_component"
            if [[ -f "$first_level_dir/SKILL.md" ]]; then
                # Inside a skill directory — already covered by directory-level symlink, skip
                :
            elif [[ -f "$entry" ]]; then
                # File inside a non-skill directory (e.g., skills/shared/voting-protocol.md)
                create_link "$link_path" "$target_path" "file"
            fi
            # Directories inside non-skill dirs are handled by mkdir -p in create_link
        fi
    elif [[ -f "$entry" ]]; then
        # Non-skills file (agents/*.md, scripts/generic/*.sh, etc.)
        create_link "$link_path" "$target_path" "file"
    fi
    # Directories outside skills/ are traversed automatically by find; we only link files
done < <(find "$CLAUDIN_DIR/.claude" -not -path "$CLAUDIN_DIR/.claude" \( -type f -o -type d \) -print0 | sort -z)

# --- Phase 2: Remove dead symlinks ---
echo "Phase 2: Removing dead symlinks pointing into $CLAUDIN_REL/.claude/..."

dead_count=0
while IFS= read -r -d '' link; do
    # Only process broken symlinks (target does not exist)
    if [[ -e "$link" ]]; then
        continue
    fi

    # Read the raw symlink target
    raw_target="$(readlink "$link")"

    # Resolve the target to an absolute path by joining with the link's parent dir
    link_parent="$(cd "$(dirname "$link")" && pwd -P)"
    # Attempt to resolve — since the target is broken, we normalize manually
    # Join parent + raw_target, then check if it would be inside CLAUDIN_DIR/.claude/
    resolved=""
    if [[ "$raw_target" == /* ]]; then
        resolved="$raw_target"
    else
        # Normalize: use a subshell to walk the path components
        # Since the target is broken, we resolve as far as we can
        resolved="$link_parent/$raw_target"
    fi

    # Normalize by collapsing .. components
    # Use Python for reliable cross-platform normalization
    normalized="$(python3 -c "import os, sys; print(os.path.normpath(sys.argv[1]))" "$resolved" 2>/dev/null)" || {
        # If python3 is not available, skip this link
        continue
    }

    # Check if the normalized path is inside the claudin .claude directory
    if [[ "$normalized" == "$CLAUDIN_DIR/.claude" || "$normalized" == "$CLAUDIN_DIR/.claude/"* ]]; then
        rm "$link"
        echo "  removed dead symlink: $link -> $raw_target"
        dead_count=$((dead_count + 1))
    fi
done < <(find .claude -type l -print0 2>/dev/null || true)

echo ""
echo "Done. Dead symlinks removed: $dead_count"
echo ""
echo "NOTE: .claude/settings*.json files were not synced. Ensure your settings.json"
echo "includes the necessary permissions for claudin scripts. At minimum:"
echo "  - Bash permission for \$PWD/.claude/scripts/generic/claudin/*"
echo "  - The block-submodule-edit.sh hook (if using submodule flow)"
echo ""
echo "MIGRATION: If upgrading from an older claudin version, update your"
echo "settings.json to replace old paths with new ones:"
echo "  - \$PWD/.claude/scripts/generic/*  →  \$PWD/.claude/scripts/generic/claudin/*"
echo "  - \$PWD/.claude/scripts/generic/block-submodule-edit.sh  →  \$PWD/.claude/scripts/generic/claudin/block-submodule-edit.sh"
echo "  - \$PWD/.claude/scripts/generic/auto-goimports.sh  →  \$PWD/.claude/scripts/generic/claudin/auto-goimports.sh"
