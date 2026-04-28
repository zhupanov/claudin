#!/usr/bin/env bash
# validate-args.sh — Validate /create-skill <skill-name> and <description>.
#
# Required flags:
#   --name <name>            Skill name (as produced by parse-args.sh).
#   --description <desc>     Description (as produced by parse-args.sh).
#
# Optional flags:
#   --plugin                 Validate that CWD is the larch plugin repo.
#
# Output (stdout):
#   VALID=true       on success
#   VALID=false
#   ERROR=<message>  on failure (exits 1)
#
# Reserved-name union (rejects the name if it matches any):
#   Anthropic:     anthropic, claude
#   larch static:  design, implement, review, research, loop-review,
#                  alias, relevant-checks, bump-version, fix-issue,
#                  im, imaq, create-skill, issue
#   Plugin skills: ls "${CLAUDE_PLUGIN_ROOT}/skills" (if present)
#   Local skills:  ls "$PWD/.claude/skills" (if present)
#
# Description rules:
#   - non-empty, length ≤ 1024
#   - no XML tags (patterns <...>)
#   - no shell-dangerous literals: backticks, $(
#   - no heredoc-terminator or frontmatter-breaking literals on their own line:
#     EOF, HEREDOC, ---
#   - no newlines, no ASCII control characters

set -euo pipefail

NAME=""
DESCRIPTION=""
PLUGIN_MODE=false

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name)        NAME="$2";        shift 2 ;;
    --description) DESCRIPTION="$2"; shift 2 ;;
    --plugin)      PLUGIN_MODE=true; shift ;;
    *)
      echo "ERROR=Unknown argument: $1"
      exit 1
      ;;
  esac
done

fail() {
  echo "VALID=false"
  echo "ERROR=$1"
  exit 1
}

# --- Name checks ---

if [[ -z "$NAME" ]]; then
  fail "Skill name is empty."
fi

if [[ ${#NAME} -gt 64 ]]; then
  fail "Skill name '$NAME' exceeds 64 characters."
fi

if ! [[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  fail "Skill name '$NAME' must match ^[a-z][a-z0-9-]*$ (lowercase letters, digits, hyphens; must start with a letter)."
fi

# Static Anthropic-reserved names.
ANTHROPIC_RESERVED=(anthropic claude)
for n in "${ANTHROPIC_RESERVED[@]}"; do
  if [[ "$NAME" == "$n" ]]; then
    fail "Skill name '$NAME' is reserved by Anthropic (cannot use 'anthropic' or 'claude')."
  fi
done

# Static larch-reserved names — aligned with alias name-shadowing intent (see /alias Step 2 for the dynamic-probe rationale). Serves as a fast pre-check before the plugin-skills directory probe below; the dynamic probe remains authoritative and catches anything missed here.
LARCH_RESERVED=(
  alias
  bump-version
  create-skill
  design
  fix-issue
  im
  imaq
  implement
  issue
  loop-review
  relevant-checks
  research
  review
)
for n in "${LARCH_RESERVED[@]}"; do
  if [[ "$NAME" == "$n" ]]; then
    fail "Skill name '$NAME' is reserved (matches an existing larch or common project-level skill)."
  fi
done

# Lowercase conversion portable to bash 3.2 (macOS default).
NAME_LC="$(printf '%s' "$NAME" | tr '[:upper:]' '[:lower:]')"

# Dynamic collision with plugin-public skills.
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -d "${CLAUDE_PLUGIN_ROOT}/skills" ]]; then
  for dir in "${CLAUDE_PLUGIN_ROOT}/skills"/*/; do
    [[ -d "$dir" ]] || continue
    existing="$(basename "$dir")"
    existing_lc="$(printf '%s' "$existing" | tr '[:upper:]' '[:lower:]')"
    if [[ "$NAME_LC" == "$existing_lc" ]]; then
      fail "Skill name '$NAME' collides with existing plugin skill '${existing}' under ${CLAUDE_PLUGIN_ROOT}/skills/."
    fi
  done
fi

# Dynamic collision with project-local skills.
if [[ -d "$PWD/.claude/skills" ]]; then
  for dir in "$PWD/.claude/skills"/*/; do
    [[ -d "$dir" ]] || continue
    existing="$(basename "$dir")"
    existing_lc="$(printf '%s' "$existing" | tr '[:upper:]' '[:lower:]')"
    if [[ "$NAME_LC" == "$existing_lc" ]]; then
      fail "Skill name '$NAME' collides with existing project-local skill '${existing}' under \$PWD/.claude/skills/."
    fi
  done
fi

# --- Plugin-mode repo check ---

if [[ "$PLUGIN_MODE" == "true" ]]; then
  if [[ ! -f "$PWD/.claude-plugin/plugin.json" ]] || [[ ! -f "$PWD/skills/implement/SKILL.md" ]]; then
    fail "--plugin requires running inside the larch plugin repo (expected .claude-plugin/plugin.json and skills/implement/SKILL.md in \$PWD)."
  fi
fi

# --- Description checks ---

if [[ -z "$DESCRIPTION" ]]; then
  fail "Description is empty."
fi

if [[ ${#DESCRIPTION} -gt 1024 ]]; then
  fail "Description length (${#DESCRIPTION}) exceeds 1024 characters."
fi

# Reject newlines and ASCII control characters. Portable: use tr to strip
# control chars and compare lengths. If lengths differ, the description
# contained at least one control character or newline.
STRIPPED="$(printf '%s' "$DESCRIPTION" | LC_ALL=C tr -d '[:cntrl:]')"
if [[ "${#STRIPPED}" -ne "${#DESCRIPTION}" ]]; then
  fail "Description contains newlines or control characters. Provide a single-line plain-text description."
fi

# XML tags.
if [[ "$DESCRIPTION" =~ \<[^\>]+\> ]]; then
  fail "Description contains an XML tag pattern <...>. XML tags are not allowed per Anthropic's frontmatter rules."
fi

# Shell-dangerous literals.
if [[ "$DESCRIPTION" == *'`'* ]]; then
  fail "Description contains a backtick. Backticks break heredoc rendering; please rephrase."
fi
# shellcheck disable=SC2016  # the pattern intentionally matches the literal two-char sequence $(
if [[ "$DESCRIPTION" == *'$('* ]]; then
  fail "Description contains '\$('. Command-substitution syntax is not allowed in descriptions."
fi

# Heredoc-terminator / frontmatter-breaking literals.
for bad in 'EOF' 'HEREDOC' '---'; do
  if [[ "$DESCRIPTION" == "$bad" ]] || [[ "$DESCRIPTION" == *" $bad "* ]] || [[ "$DESCRIPTION" == "$bad "* ]] || [[ "$DESCRIPTION" == *" $bad" ]]; then
    fail "Description contains the literal token '$bad' as a standalone word, which could break heredoc or YAML frontmatter rendering."
  fi
done

echo "VALID=true"
