#!/usr/bin/env bash
# build-feature-description.sh — Resolve target skill, enumerate in-scope .md files,
# and compose the /implement feature description for /simplify-skill.
#
# Required flag:
#   --name <skill-name>   Bare target skill name ([a-z0-9-]+), no colons.
#
# Stdout contract (always one KEY=VALUE per line):
#   On success:
#     STATUS=ok
#     TARGET_SKILL_MD=<absolute-path-to-target-SKILL.md>
#     TARGET_DIR=<absolute-path-to-target-skill-dir>
#     INCLUDED_FILES=<absolute-path-1>[:<absolute-path-2>...]   # colon-separated, SKILL.md first
#     FEATURE_FILE=<absolute-path-to-feature-description-temp-file>
#   On failure:
#     STATUS=not_found|bad_name
#     ERROR=<human-readable message>
#
# Fail-closed contract: exit 0 in all STATUS branches so the caller can parse stdout;
# exit 1 only on internal errors (unparseable args, mktemp failure).
#
# Enumeration scope (per /simplify-skill NEVER #1):
#   - SKILL.md (always)
#   - Every *.md file under <target-dir>/ EXCLUDING scripts/, tests/ subtrees.
#   - Does NOT follow Skill-tool invocations to other skills.
#   - Does NOT follow citations into skills/shared/ or other skill directories — those
#     have broader blast radius and must be refactored separately.

set -euo pipefail

NAME=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --name) NAME="$2"; shift 2 ;;
    *) echo "ERROR=Unknown argument: $1" >&2; exit 1 ;;
  esac
done

if [[ -z "$NAME" ]]; then
  echo "ERROR=Missing required argument --name" >&2
  exit 1
fi

# --- Validate name ---

# Strip leading slash if the caller passed `/implement` style.
NAME="${NAME#/}"

# Reject plugin-qualified forms and any non-kebab chars.
if [[ "$NAME" =~ : ]]; then
  printf 'STATUS=bad_name\n'
  printf 'ERROR=Target skill name %s contains ":" — pass the bare name only (e.g., "implement", not "larch:implement").\n' "$NAME"
  exit 0
fi

if ! [[ "$NAME" =~ ^[a-z][a-z0-9-]*$ ]]; then
  printf 'STATUS=bad_name\n'
  printf 'ERROR=Target skill name %s is invalid. Must match ^[a-z][a-z0-9-]*$.\n' "$NAME"
  exit 0
fi

# --- Resolve target directory ---

# Prefer plugin tree (published skills) over consumer-repo dev skills.
TARGET_DIR=""
if [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -f "${CLAUDE_PLUGIN_ROOT}/skills/${NAME}/SKILL.md" ]]; then
  TARGET_DIR="${CLAUDE_PLUGIN_ROOT}/skills/${NAME}"
elif [[ -f "$(pwd)/.claude/skills/${NAME}/SKILL.md" ]]; then
  TARGET_DIR="$(pwd)/.claude/skills/${NAME}"
elif [[ -n "${CLAUDE_PLUGIN_ROOT:-}" ]] && [[ -f "${CLAUDE_PLUGIN_ROOT}/.claude/skills/${NAME}/SKILL.md" ]]; then
  TARGET_DIR="${CLAUDE_PLUGIN_ROOT}/.claude/skills/${NAME}"
else
  printf 'STATUS=not_found\n'
  # Single quotes are intentional — we want to show the literal path tokens (${CLAUDE_PLUGIN_ROOT}, $PWD) to the user, not expand them.
  # shellcheck disable=SC2016
  printf 'ERROR=Skill %s not found. Probed ${CLAUDE_PLUGIN_ROOT}/skills/%s/SKILL.md, $PWD/.claude/skills/%s/SKILL.md, and ${CLAUDE_PLUGIN_ROOT}/.claude/skills/%s/SKILL.md.\n' "$NAME" "$NAME" "$NAME" "$NAME"
  exit 0
fi

TARGET_SKILL_MD="${TARGET_DIR}/SKILL.md"

# --- Enumerate in-scope .md files ---

# SKILL.md is always first. Then every other *.md under the skill dir, excluding
# scripts/ and tests/ subtrees. Sort for stable output across runs.
INCLUDED=()
INCLUDED+=("$TARGET_SKILL_MD")

# Fail-closed enumeration: run find to a temp file so its exit status is
# observable, then iterate. Suppressing stderr and piping directly into a
# process substitution hides permission/IO errors and can produce a partial
# list that the caller treats as a complete enumeration (STATUS=ok).
FIND_OUTPUT="$(mktemp -t simplify-skill-find.XXXXXX)"
if ! find "$TARGET_DIR" -type f -name '*.md' \
  -not -path '*/scripts/*' -not -path '*/tests/*' \
  > "$FIND_OUTPUT"; then
  rm -f "$FIND_OUTPUT"
  echo "ERROR=find failed while enumerating .md files under $TARGET_DIR" >&2
  exit 1
fi
# macOS find supports these flags in bash 3.2.
while IFS= read -r f; do
  # Skip SKILL.md itself (already in the list).
  [[ "$f" == "$TARGET_SKILL_MD" ]] && continue
  INCLUDED+=("$f")
done < <(LC_ALL=C sort < "$FIND_OUTPUT")
rm -f "$FIND_OUTPUT"

# Colon-join for stdout emission. Contract note: paths must not contain `:`.
# On macOS/Linux skill trees this holds by construction — skill directories
# are kebab-case and paths never embed a colon. Filing a follow-up is the
# right move only if some future tooling breaks that assumption.
INCLUDED_JOINED=""
for f in "${INCLUDED[@]}"; do
  if [[ -z "$INCLUDED_JOINED" ]]; then
    INCLUDED_JOINED="$f"
  else
    INCLUDED_JOINED="${INCLUDED_JOINED}:${f}"
  fi
done

# --- Compose feature description ---

FEATURE_FILE="$(mktemp -t simplify-skill-feature.XXXXXX)"

# Count lines for the Token budget baseline the feature description pins.
SKILL_MD_LINES=$(wc -l < "$TARGET_SKILL_MD" | tr -d ' ')
SKILL_MD_CHARS=$(wc -c < "$TARGET_SKILL_MD" | tr -d ' ')

# Build the included-files prose block (one per line, indented).
INCLUDED_PROSE=""
for f in "${INCLUDED[@]}"; do
  INCLUDED_PROSE="${INCLUDED_PROSE}  - ${f}"$'\n'
done

cat >"$FEATURE_FILE" <<FEATURE_EOF
Refactor the /${NAME} skill for stronger adherence to larch skill-design principles and to reduce SKILL.md token footprint. BEHAVIOR-PRESERVING REFACTOR ONLY — no feature changes, no semantic drift, no new capabilities. The refactor is successful only if every existing use case of /${NAME} behaves identically post-refactor.

Target skill directory: ${TARGET_DIR}
Primary file: ${TARGET_SKILL_MD} (${SKILL_MD_LINES} lines, ${SKILL_MD_CHARS} chars baseline — track in the PR body "Token budget" section below)

In-scope .md files (SKILL.md plus every .md file under the target skill directory, excluding scripts/ and tests/):
${INCLUDED_PROSE}
OUT OF SCOPE (do NOT edit):
  - Any skill invoked by /${NAME} via the Skill tool (each sub-skill is an independent refactor target with its own PR history and CI footprint).
  - Files under \${CLAUDE_PLUGIN_ROOT}/skills/shared/ (cross-skill blast radius — must be refactored separately).
  - Any .md file outside ${TARGET_DIR}/ even if cited from within.

MUST read the full file before editing anything:
  \${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md

Apply the principles across all nine sections, with Section III mechanical rules A/B/C taking precedence over Section IV writing-style guidance where they conflict:
  - Section I (Knowledge delta): delete any prose that explains to Claude concepts Claude already knows. Every paragraph must earn its tokens.
  - Section II (Progressive disclosure): move heavy content out of SKILL.md into references/*.md files loaded via explicit \`MANDATORY — READ ENTIRE FILE\` triggers, with matching \`Do NOT Load\` guidance on branches that skip the reference. Target SKILL.md under 500 lines.
  - Section III (Larch mechanical rules): A — non-trivial shell logic lives in .sh scripts (shared at \${CLAUDE_PLUGIN_ROOT}/scripts/ when reusable, private at \${CLAUDE_PLUGIN_ROOT}/skills/${NAME}/scripts/ otherwise; grep existing scripts before creating new ones); B — no direct Bash-tool commands in SKILL.md (every shell command wraps a .sh script; no inline pipelines, loops, or multi-line bash -c strings); C — no consecutive Bash-tool calls per step (combine multi-action steps into one coordinator .sh).
  - Section V (Description activation gate): if the description is vague or name-echo, rewrite it to answer WHAT/WHEN/KEYWORDS concretely.
  - Section VI (Anti-patterns with WHY): every NEVER/MUST item states a specific reason, not generic filler.
  - Section IX (Verifiable quality criteria): cross-check the final artifact against the full bulleted list.

Partitioning rules when splitting SKILL.md or a large included .md file:
  - Prefer new \`references/<topic>.md\` files inside ${TARGET_DIR}/references/ loaded with explicit \`MANDATORY — READ ENTIRE FILE\` triggers for the branches that actually need them.
  - Promote a cohesive section to a private sub-skill under ${TARGET_DIR}/<sub-name>/ only when it has independent reuse potential beyond this skill. Default preference is references/ — a new sub-skill adds a Skill-tool boundary and should be justified.
  - Every new reference file MUST be loaded by at least one step (no orphans per Section IX).

Preserve invariants:
  - All frontmatter fields stay valid and compatible (name unchanged; description may be tightened per Section V but not semantically changed).
  - All existing flags, exit codes, stdout contracts, sentinel-file names, and breadcrumb-literal tokens remain byte-identical.
  - Any harness-asserted literal token (e.g., Step Name Registry rows, NEVER-list titles, Rebase Checkpoint Macro invocation shape) is preserved exactly.
  - Test harnesses that currently pass for /${NAME} must continue to pass unchanged.

Test / validation plan:
  - Grep the repo Makefile and agent-lint.toml for any test-* target that references /${NAME}'s SKILL.md, helper scripts, or reference files. List each such target in the PR body.
  - Run /relevant-checks after the refactor. All existing harnesses MUST pass without modification. If a harness asserts a literal that the refactor changes, update the harness in the SAME PR with a one-sentence rationale — per larch convention, harness and source stay in sync.
  - Manual smoke: if /${NAME} has a quick happy-path invocation documented in its SKILL.md or README, mention it in the PR body as the recommended manual verification step.

PR body MUST include a \`## Token budget\` section with this exact table shape:

\`\`\`markdown
## Token budget

| File | Before (lines / chars) | After (lines / chars) | Delta |
|------|------------------------|------------------------|-------|
| SKILL.md | ${SKILL_MD_LINES} / ${SKILL_MD_CHARS} | <new-lines> / <new-chars> | <signed-delta-lines> / <signed-delta-chars> |
| (each new references/*.md)   | —                      | <lines> / <chars>      | +<lines> / +<chars> |
| **Total in-scope** |  |  |  |
\`\`\`

Negative total deltas on SKILL.md are the success criterion. A net-zero or positive SKILL.md delta means the refactor did not achieve its stated goal — flag this in the PR body and justify (acceptable when the added content is genuinely necessary invariants per Section VI).
FEATURE_EOF

# --- Emit machine output ---

printf 'STATUS=ok\n'
printf 'TARGET_SKILL_MD=%s\n' "$TARGET_SKILL_MD"
printf 'TARGET_DIR=%s\n' "$TARGET_DIR"
printf 'INCLUDED_FILES=%s\n' "$INCLUDED_JOINED"
printf 'FEATURE_FILE=%s\n' "$FEATURE_FILE"
