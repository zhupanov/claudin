#!/usr/bin/env bash
# validate-plugin-structure.sh — Validate the larch plugin's manifest, layout, and references.
#
# Called by:
#   1. .github/workflows/ci.yaml (plugin-structure job) — gates PR merges
#   2. .claude/skills/relevant-checks/scripts/run-checks.sh — runs after pre-commit succeeds
#   3. Developers, directly: bash scripts/validate-plugin-structure.sh
#
# Validators (run in order; errors collected via fail() and reported at the end):
#   1. plugin.json           — file exists, valid JSON, name+version present, strict semver
#   2. marketplace.json      — file exists, valid JSON, name+owner.name, plugins[] non-empty,
#                              every plugin has name and source (string or object)
#   3. hooks/hooks.json      — file exists, valid JSON, top-level "hooks" key,
#                              every command path under ${CLAUDE_PLUGIN_ROOT}/ exists+executable
#   4. .claude/settings.json — every hook command path containing ${CLAUDE_PLUGIN_ROOT}/ or
#                              $PWD/ exists+executable (matches the .sh files referenced
#                              by hook handlers; the broad "allow" list is not validated here)
#   5. skills/* layout       — every skills/*/ (excluding shared/) has SKILL.md
#   6. SKILL.md frontmatter  — name+description present, name == basename(dirname),
#                              optional argument-hint and allowed-tools, if present, non-empty
#   7. agents/*.md           — directory exists, ≥1 .md, each .md has frontmatter with
#                              name+description (scalar fields only — list-valued tools:
#                              fields are intentionally not parsed)
#   8. ${CLAUDE_PLUGIN_ROOT} hygiene — public skills/*/SKILL.md must not use $PWD/, ${PWD}/,
#                              or hardcoded paths (/Users/, /home/, /opt/)
#   9. Script reference integrity — every ${CLAUDE_PLUGIN_ROOT}/(scripts|skills|.claude/skills)/...sh
#                              and $PWD/.claude/skills/...sh referenced from any SKILL.md
#                              or skills/shared/*.md must exist on disk
#  10. Executability         — every .sh file under scripts/, skills/*/scripts/, and
#                              .claude/skills/*/scripts/ must be chmod +x
#  11. Dead-script detection — every scripts/*.sh must have a STRUCTURED invocation reference
#                              somewhere in the codebase (path-shaped tokens only — prose
#                              and comments are not counted as references)
#  12. Marketplace enriched metadata — marketplace.json has $schema (non-empty string),
#                              top-level description (non-empty), owner.email (non-empty),
#                              every plugin entry has category (non-empty)
#  13. Plugin enriched metadata — plugin.json has description (non-empty), author.email
#                              (non-empty), keywords (non-empty array with ≥1 element)
#  14. SECURITY.md presence  — SECURITY.md exists at repo root
#
# Exemption from PWD hygiene check (validator 8):
#   .claude/skills/bump-version/SKILL.md
#   .claude/skills/relevant-checks/SKILL.md
# These are private repo utilities that intentionally use $PWD by design. Validator 8
# only iterates skills/*/SKILL.md, so .claude/skills/*/SKILL.md files are never visited;
# the exemption is enforced by the iteration scope, not a runtime check.
#
# Frontmatter parser scope: pure-awk extractor that supports flat key-value YAML only.
# Multi-line block scalars and YAML lists (e.g., the agents/ files' `tools:` field) are
# NOT parsed. This is acceptable because we only validate scalar fields (name, description).
# The limitation is documented intentionally — switch to a real YAML parser if richer
# validation is needed in the future.
#
# IMPORTANT: set -e is intentionally OMITTED from this script. The collect-then-report
# design depends on fail() incrementing ERROR_COUNT without aborting. With set -e, any
# non-zero return from a validator's internal command would abort the script and skip
# remaining validators, defeating the entire design. We use `set -uo pipefail` (NO -e)
# for unset-variable detection and pipeline error propagation while allowing individual
# commands to return non-zero.
#
# Exit codes:
#   0  — all validators passed (ERROR_COUNT == 0)
#   1  — one or more validators failed (ERROR_COUNT > 0)
#   2  — environment failure (not inside a git repository)
#
# Dependencies: bash 3.2+, awk (POSIX), jq, grep (BRE/ERE), find, sed, basename, dirname.
# All standard on macOS and Linux. No python/ruby/yq dependency.

set -uo pipefail

# ---------------------------------------------------------------------------
# Globals
# ---------------------------------------------------------------------------

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "ERROR: not inside a git repository" >&2
    exit 2
}
cd "$REPO_ROOT" || {
    echo "ERROR: cannot cd to repo root: $REPO_ROOT" >&2
    exit 2
}

ERROR_COUNT=0

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# Print error to stderr and increment counter (does not exit).
fail() {
    printf 'PLUGIN STRUCTURE ERROR: %s\n' "$*" >&2
    ERROR_COUNT=$((ERROR_COUNT + 1))
}

# Extract YAML frontmatter (lines between first --- and second ---).
# REQUIRES the file to start with `---` on line 1.
# REQUIRES an explicit closing `---` line.
# Returns 1 (and outputs nothing) if the file is malformed.
extract_frontmatter() {
    local file="$1"
    awk '
        NR == 1 && $0 != "---" { exit 1 }
        NR == 1 && $0 == "---" { next }
        /^---$/ { found_close = 1; exit 0 }
        { print }
        END { if (!found_close) exit 1 }
    ' "$file"
}

# Get the value of a top-level scalar key from frontmatter.
# Strips outer double quotes from the value.
# Uses index() instead of dynamic regex to avoid metacharacter issues.
get_field() {
    local file="$1" key="$2"
    extract_frontmatter "$file" 2>/dev/null \
        | awk -v k="$key" '
            index($0, k ":") == 1 {
                val = substr($0, length(k) + 2)
                sub(/^ +/, "", val)
                sub(/^"/, "", val)
                sub(/"$/, "", val)
                print val
                exit
            }'
}

# Emit only the executable text from a YAML/shell file by stripping full-line
# and trailing # comments. Lines starting with optional whitespace then `#` are
# dropped; ` # ...` trailing comments are stripped from the rest. JSON has no
# comments so this function is not used for .json files.
strip_yaml_comments() {
    awk '
        /^[[:space:]]*#/ { next }
        { sub(/[[:space:]]+#.*$/, ""); print }
    ' "$1"
}

# Emit only content inside fenced code blocks (``` or ~~~) from a markdown file.
# Toggles state on each fence line, prints the body lines.
extract_code_fences() {
    awk '
        /^[[:space:]]*```/ || /^[[:space:]]*~~~/ {
            in_code = !in_code
            next
        }
        in_code { print }
    ' "$1"
}

# Validate hook command paths in a JSON file.
# Args: $1 = JSON file path, $2 = label for error messages.
# Reads ALL string values from the JSON, filters to those containing
# ${CLAUDE_PLUGIN_ROOT}/ or $PWD/ AND ending in .sh, then verifies each
# resolved path exists on disk and is executable.
# Uses process substitution to keep ERROR_COUNT in the parent shell.
validate_hook_command_paths() {
    local f="$1" label="$2"
    [ -f "$f" ] || return 0

    local raw rel
    # shellcheck disable=SC2016  # intentional literal ${CLAUDE_PLUGIN_ROOT} and $PWD in grep -F -e patterns
    while IFS= read -r raw; do
        # Strip ${CLAUDE_PLUGIN_ROOT}/ or $PWD/ prefix to get repo-relative path
        rel="${raw#\$\{CLAUDE_PLUGIN_ROOT\}/}"
        rel="${rel#\$PWD/}"
        # Skip if no prefix was stripped (defensive)
        [ "$rel" = "$raw" ] && continue
        [ -f "$rel" ] || fail "$label: hook command missing on disk: $raw"
        [ -x "$rel" ] || fail "$label: hook command not executable: $raw"
    done < <(jq -r '.. | strings' "$f" 2>/dev/null \
                | grep -F -e '${CLAUDE_PLUGIN_ROOT}/' -e '$PWD/' \
                | grep -E '\.sh$' \
                || true)
}

# ---------------------------------------------------------------------------
# Validator 1: plugin.json
# ---------------------------------------------------------------------------

validate_plugin_json() {
    local f=".claude-plugin/plugin.json"
    if [ ! -f "$f" ]; then
        fail "$f is missing"
        return 0
    fi
    if ! jq empty "$f" 2>/dev/null; then
        fail "$f is not valid JSON"
        return 0
    fi
    local name version
    name=$(jq -r '.name // empty' "$f")
    version=$(jq -r '.version // empty' "$f")
    [ -n "$name" ] || fail "$f missing required field: name"
    [ -n "$version" ] || fail "$f missing required field: version"
    if [ -n "$version" ] && ! [[ "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        fail "$f version '$version' is not strict MAJOR.MINOR.PATCH semver"
    fi
}

# ---------------------------------------------------------------------------
# Validator 2: marketplace.json
# ---------------------------------------------------------------------------

validate_marketplace_json() {
    local f=".claude-plugin/marketplace.json"
    if [ ! -f "$f" ]; then
        fail "$f is missing"
        return 0
    fi
    if ! jq empty "$f" 2>/dev/null; then
        fail "$f is not valid JSON"
        return 0
    fi
    local mp_name mp_owner mp_plugins_len
    mp_name=$(jq -r '.name // empty' "$f")
    mp_owner=$(jq -r '.owner.name // empty' "$f")
    mp_plugins_len=$(jq '.plugins | length' "$f")
    [ -n "$mp_name" ] || fail "$f missing required field: name"
    [ -n "$mp_owner" ] || fail "$f missing required field: owner.name"
    [ "$mp_plugins_len" -gt 0 ] || fail "$f has empty plugins array"
    # Each plugin must have a non-empty name AND a source (non-empty string or object).
    if ! jq -e '.plugins | all(
            (.name | type == "string" and length > 0)
            and (
                (.source | type == "string" and length > 0)
                or (.source | type == "object")
            )
        )' "$f" >/dev/null 2>&1; then
        fail "$f has plugin entry with missing/invalid name or source"
    fi
}

# ---------------------------------------------------------------------------
# Validator 3: hooks/hooks.json
# ---------------------------------------------------------------------------

validate_hooks_json() {
    local f="hooks/hooks.json"
    if [ ! -f "$f" ]; then
        fail "$f is missing"
        return 0
    fi
    if ! jq empty "$f" 2>/dev/null; then
        fail "$f is not valid JSON"
        return 0
    fi
    jq -e '.hooks' "$f" >/dev/null 2>&1 || fail "$f missing top-level 'hooks' key"
    validate_hook_command_paths "$f" "hooks/hooks.json"
}

# ---------------------------------------------------------------------------
# Validator 4: .claude/settings.json hook command paths
# ---------------------------------------------------------------------------

validate_settings_hooks() {
    local f=".claude/settings.json"
    [ -f "$f" ] || return 0
    if ! jq empty "$f" 2>/dev/null; then
        fail "$f is not valid JSON"
        return 0
    fi
    validate_hook_command_paths "$f" ".claude/settings.json"
}

# ---------------------------------------------------------------------------
# Validator 5: skills/* layout
# ---------------------------------------------------------------------------

validate_skills_layout() {
    local skill_count=0 d base
    for d in skills/*/; do
        base=$(basename "$d")
        [ "$base" = "shared" ] && continue
        if [ ! -f "${d}SKILL.md" ]; then
            fail "skills/${base}/ missing SKILL.md"
            continue
        fi
        skill_count=$((skill_count + 1))
    done
    [ "$skill_count" -gt 0 ] || fail "no plugin-exported skills found under skills/"
}

# ---------------------------------------------------------------------------
# Validator 6: SKILL.md frontmatter
# ---------------------------------------------------------------------------

validate_skill_frontmatter() {
    local skill_md base name desc field val
    for skill_md in skills/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        # Skip skills/shared/ (no SKILL.md should exist there, but defend anyway)
        case "$skill_md" in
            skills/shared/*) continue ;;
        esac
        base=$(basename "$(dirname "$skill_md")")
        if ! extract_frontmatter "$skill_md" >/dev/null 2>&1; then
            fail "$skill_md: malformed frontmatter (must start with '---' on line 1, must have closing '---')"
            continue
        fi
        name=$(get_field "$skill_md" "name")
        desc=$(get_field "$skill_md" "description")
        [ -n "$name" ] || fail "$skill_md: missing required frontmatter field 'name'"
        [ -n "$desc" ] || fail "$skill_md: missing required frontmatter field 'description'"
        if [ -n "$name" ] && [ "$name" != "$base" ]; then
            fail "$skill_md: frontmatter name '$name' does not match directory '$base'"
        fi
        # Optional scalar fields: if present in the frontmatter, value must be non-empty.
        # Scope the presence check to extracted frontmatter only — searching the whole
        # file would false-positive on body lines that happen to start with the key
        # (e.g., a SKILL.md documenting frontmatter syntax in its prose).
        for field in "argument-hint" "allowed-tools"; do
            if extract_frontmatter "$skill_md" 2>/dev/null | grep -qE "^${field}:"; then
                val=$(get_field "$skill_md" "$field")
                [ -n "$val" ] || fail "$skill_md: optional field '$field' is present but empty"
            fi
        done
    done
}

# ---------------------------------------------------------------------------
# Validator 7: agents/*.md frontmatter (scalar fields only)
# ---------------------------------------------------------------------------

validate_agents() {
    local agents_dir="agents"
    if [ ! -d "$agents_dir" ]; then
        fail "$agents_dir/ directory is missing"
        return 0
    fi
    local found=0 agent_md name desc
    for agent_md in "$agents_dir"/*.md; do
        [ -f "$agent_md" ] || continue
        found=1
        if ! extract_frontmatter "$agent_md" >/dev/null 2>&1; then
            fail "$agent_md: malformed frontmatter (must start with '---' on line 1, must have closing '---')"
            continue
        fi
        name=$(get_field "$agent_md" "name")
        desc=$(get_field "$agent_md" "description")
        [ -n "$name" ] || fail "$agent_md: missing required frontmatter field 'name'"
        [ -n "$desc" ] || fail "$agent_md: missing required frontmatter field 'description'"
        # Note: list-valued fields like 'tools:' are intentionally not parsed.
    done
    [ "$found" = 1 ] || fail "$agents_dir/ has no .md files"
}

# ---------------------------------------------------------------------------
# Validator 8: ${CLAUDE_PLUGIN_ROOT} hygiene
# ---------------------------------------------------------------------------

validate_pwd_hygiene() {
    # Check public skills/*/SKILL.md only. Private .claude/skills/*/SKILL.md
    # files are exempt from this check by design (enforced by iteration scope).
    #
    # Pattern catches:
    #   $PWD/        — non-portable path construction
    #   ${PWD}/      — brace form, morally equivalent to $PWD/
    #   /Users/      — hardcoded macOS user path
    #   /home/       — hardcoded Linux user path
    #   /opt/        — hardcoded install prefix
    #
    # Pattern does NOT catch bare "$PWD" used as workspace argument
    # (e.g., --workspace "$PWD", -C "$PWD") which is legitimate.
    #
    # NOTE: an intermediate variable is used to side-step shellcheck SC2016
    # (which would otherwise fire on a single-quoted pattern containing $PWD).
    local pattern='[$]PWD/|[$][{]PWD[}]/|/Users/|/home/|/opt/'
    local skill_md
    for skill_md in skills/*/SKILL.md; do
        [ -f "$skill_md" ] || continue
        case "$skill_md" in
            skills/shared/*) continue ;;
        esac
        if grep -nE "$pattern" "$skill_md" >/dev/null; then
            fail "$skill_md uses \$PWD/ or hardcoded path; use \${CLAUDE_PLUGIN_ROOT}/ instead"
        fi
    done
}

# ---------------------------------------------------------------------------
# Validator 9: script reference integrity
# ---------------------------------------------------------------------------

# Process substitution keeps ERROR_COUNT increments in the parent shell.
# Extracts:
#   - ${CLAUDE_PLUGIN_ROOT}/(scripts|skills|.claude/skills)/...sh (public)
#   - $PWD/.claude/skills/...sh                                   (private)
#   - ${CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-$PWD}/.claude/skills/...sh (legacy private placeholder
#                                                                  used by .claude/skills/bump-version/SKILL.md)
validate_script_references() {
    # shellcheck disable=SC2016  # intentional literal ${CLAUDE_PLUGIN_ROOT} and $PWD in regex
    local pattern_pub='\$\{CLAUDE_PLUGIN_ROOT\}/(scripts|skills|\.claude/skills)/[a-zA-Z0-9._/-]+\.sh'
    # shellcheck disable=SC2016  # intentional literal $PWD in regex
    local pattern_priv='\$PWD/\.claude/skills/[a-zA-Z0-9._/-]+\.sh'
    # shellcheck disable=SC2016  # intentional literal ${CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-$PWD} in regex
    local pattern_placeholder='\$\{CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-\$PWD\}/\.claude/skills/[a-zA-Z0-9._/-]+\.sh'
    local ref rel

    # Public references via ${CLAUDE_PLUGIN_ROOT}
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        rel="${ref#\$\{CLAUDE_PLUGIN_ROOT\}/}"
        [ -f "$rel" ] || fail "script reference missing on disk: $ref (expected $rel)"
    done < <(grep -rhoE "$pattern_pub" skills/ .claude/skills/ 2>/dev/null | sort -u)

    # Private references via $PWD (only the two private skills use this form)
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        rel="${ref#\$PWD/}"
        [ -f "$rel" ] || fail "script reference missing on disk: $ref (expected $rel)"
    done < <(grep -rhoE "$pattern_priv" .claude/skills/ 2>/dev/null | sort -u)

    # Legacy placeholder form: ${CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-$PWD}/.claude/skills/...
    # Used by .claude/skills/bump-version/SKILL.md to remain compatible with both
    # plugin-runtime invocation and direct $PWD invocation.
    while IFS= read -r ref; do
        [ -z "$ref" ] && continue
        rel="${ref#\$\{CLAUDE_PLUGIN_ROOT_PLACEHOLDER:-\$PWD\}/}"
        [ -f "$rel" ] || fail "script reference missing on disk: $ref (expected $rel)"
    done < <(grep -rhoE "$pattern_placeholder" .claude/skills/ 2>/dev/null | sort -u)
}

# ---------------------------------------------------------------------------
# Validator 10: executability of all .sh files
# ---------------------------------------------------------------------------

validate_executability() {
    local script
    while IFS= read -r script; do
        [ -z "$script" ] && continue
        [ -x "$script" ] || fail "script not executable: $script"
    done < <(find scripts skills/*/scripts .claude/skills/*/scripts \
                  -type f -name '*.sh' 2>/dev/null | sort)

    # Preserve specific check from the legacy CI inline block.
    [ -x scripts/block-submodule-edit.sh ] \
        || fail "scripts/block-submodule-edit.sh missing or not executable"
}

# ---------------------------------------------------------------------------
# Validator 11: dead-script detection (structured references only)
# ---------------------------------------------------------------------------

# A scripts/*.sh file is "live" if (and only if) it appears in at least one
# STRUCTURED invocation context, where structured means a path-shaped token
# inside one of:
#
#   A. ${CLAUDE_PLUGIN_ROOT}/(scripts|.claude/skills/*/scripts)/<name>.sh
#   B. $PWD/scripts/<name>.sh   or   $PWD/.claude/skills/*/scripts/<name>.sh
#   C. "$SCRIPT_DIR/<name>.sh"  (script-to-script invocation pattern)
#   D. scripts/<name>.sh tokens in workflow `run:` blocks or JSON command fields
#   E. scripts/<name>.sh tokens in shared markdown code blocks
#
# Plain prose mentions in narrative text or shell comments do NOT count.
validate_dead_scripts() {
    local references_file
    references_file=$(mktemp -t valpsXXXXXX) || {
        fail "validate_dead_scripts: cannot create temp file"
        return 0
    }
    # shellcheck disable=SC2064
    trap "rm -f '$references_file'" RETURN

    local wf_file json_file md_file

    # Collect references from all patterns into the temp file in a single redirect.
    # shellcheck disable=SC2016  # all single-quoted patterns contain intentional literal $ tokens
    {
        # Pattern A & B: ${CLAUDE_PLUGIN_ROOT}/... and $PWD/... path-shaped references
        grep -rhoE '\$(\{CLAUDE_PLUGIN_ROOT\}|PWD)/(scripts|\.claude/skills/[^/]+/scripts)/[a-zA-Z0-9._-]+\.sh' \
            skills/ .claude/skills/ hooks/ .github/workflows/ scripts/ .claude/settings.json 2>/dev/null \
            | sed -E -e 's|^\$\{CLAUDE_PLUGIN_ROOT\}/||' -e 's|^\$PWD/||'

        # Pattern C: "$SCRIPT_DIR/<name>.sh" inside scripts (script-to-script)
        grep -rhoE '\$SCRIPT_DIR/[a-zA-Z0-9._-]+\.sh' scripts/ 2>/dev/null \
            | sed -E 's|^\$SCRIPT_DIR/|scripts/|'

        # Pattern D: bare scripts/<name>.sh tokens in workflow run: blocks and
        # JSON command fields. To honor the contract that comments and prose
        # do not count as live references, strip YAML comments from workflow
        # files first; JSON files have no comments and pass through unchanged.
        for wf_file in .github/workflows/*.yaml .github/workflows/*.yml; do
            [ -f "$wf_file" ] || continue
            strip_yaml_comments "$wf_file" \
                | grep -oE '(^|[^a-zA-Z0-9._/-])scripts/[a-zA-Z0-9._-]+\.sh' \
                | grep -oE 'scripts/[a-zA-Z0-9._-]+\.sh'
        done
        for json_file in .claude/settings.json hooks/hooks.json; do
            [ -f "$json_file" ] || continue
            grep -hoE '(^|[^a-zA-Z0-9._/-])scripts/[a-zA-Z0-9._-]+\.sh' "$json_file" \
                | grep -oE 'scripts/[a-zA-Z0-9._-]+\.sh'
        done

        # Pattern E: bare scripts/<name>.sh tokens in shared markdown
        # code fences ONLY — narrative prose mentions do not count.
        if [ -d skills/shared ]; then
            while IFS= read -r md_file; do
                extract_code_fences "$md_file" \
                    | grep -oE '(^|[^a-zA-Z0-9._/-])scripts/[a-zA-Z0-9._-]+\.sh' \
                    | grep -oE 'scripts/[a-zA-Z0-9._-]+\.sh'
            done < <(find skills/shared -type f -name '*.md' 2>/dev/null)
        fi
    } >> "$references_file"

    sort -u "$references_file" -o "$references_file"

    local script base
    for script in scripts/*.sh; do
        [ -f "$script" ] || continue
        base="$(basename "$script")"
        if ! grep -qFx "scripts/$base" "$references_file"; then
            fail "dead script (no structured invocation reference found): $script"
        fi
    done
}

# ---------------------------------------------------------------------------
# Validator 12: marketplace.json enriched metadata
# ---------------------------------------------------------------------------

validate_marketplace_enriched() {
    local f=".claude-plugin/marketplace.json"
    [ -f "$f" ] || return 0
    jq empty "$f" 2>/dev/null || return 0  # skip if invalid JSON (validator 2 catches this)

    local schema desc email
    schema=$(jq -r '.["$schema"] // empty' "$f")
    [ -n "$schema" ] || fail "$f missing required field: \$schema"

    desc=$(jq -r '.description // empty' "$f")
    [ -n "$desc" ] || fail "$f missing required top-level field: description"

    email=$(jq -r '.owner.email // empty' "$f")
    [ -n "$email" ] || fail "$f missing required field: owner.email"

    # Every plugin entry must have a category
    local plugin_count i entry_cat
    plugin_count=$(jq '.plugins | length' "$f")
    for i in $(seq 0 $((plugin_count - 1))); do
        entry_cat=$(jq -r ".plugins[$i].category // empty" "$f")
        [ -n "$entry_cat" ] || fail "$f plugins[$i] missing required field: category"
    done
}

# ---------------------------------------------------------------------------
# Validator 13: plugin.json enriched metadata
# ---------------------------------------------------------------------------

validate_plugin_enriched() {
    local f=".claude-plugin/plugin.json"
    [ -f "$f" ] || return 0
    jq empty "$f" 2>/dev/null || return 0  # skip if invalid JSON (validator 1 catches this)

    local desc email
    desc=$(jq -r '.description // empty' "$f")
    [ -n "$desc" ] || fail "$f missing required field: description"

    email=$(jq -r '.author.email // empty' "$f")
    [ -n "$email" ] || fail "$f missing required field: author.email"

    if ! jq -e '.keywords | type == "array" and length > 0' "$f" >/dev/null 2>&1; then
        fail "$f keywords must be a non-empty array"
    fi
}

# ---------------------------------------------------------------------------
# Validator 14: SECURITY.md presence
# ---------------------------------------------------------------------------

validate_security_md() {
    [ -f "SECURITY.md" ] || fail "SECURITY.md is missing from repo root"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    validate_plugin_json
    validate_marketplace_json
    validate_hooks_json
    validate_settings_hooks
    validate_skills_layout
    validate_skill_frontmatter
    validate_agents
    validate_pwd_hygiene
    validate_script_references
    validate_executability
    validate_dead_scripts
    validate_marketplace_enriched
    validate_plugin_enriched
    validate_security_md

    if [ "$ERROR_COUNT" -eq 0 ]; then
        echo "Plugin structure OK"
        exit 0
    else
        printf 'Plugin structure: %d error(s)\n' "$ERROR_COUNT" >&2
        exit 1
    fi
}

main "$@"
