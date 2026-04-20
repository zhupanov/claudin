#!/usr/bin/env bash
# test-render-skill-md.sh — Regression harness for render-skill-md.sh.
#
# Black-box contract test: runs render-skill-md.sh for both scaffold variants
# (--multi-step true / --multi-step false) into a temp dir, then asserts:
#   (1) RENDERED=<path> line appears on stdout,
#   (2) rendered SKILL.md file exists at that path,
#   (3) frontmatter contains the skill `name:` line,
#   (4) frontmatter contains the skill `description: "<escaped>"` line
#       (exercises the validate-args.sh ESCAPED_DESC YAML-quoting pipeline —
#       a regression dropping description or breaking YAML escaping fails here),
#   (5) a `## Sub-skill Invocation` section is present,
#   (6) the Sub-skill Invocation section references
#       skills/shared/subskill-invocation.md with a NON-EMPTY prefix (guards
#       against empty ${PLUGIN_TOKEN} expansion silently producing a rooted
#       "/skills/shared/subskill-invocation.md" pointer that would resolve
#       to a filesystem root rather than the plugin tree),
#   (7) the rendered body cites
#       skills/shared/skill-design-principles.md (closes #216 — the canonical
#       principles doc must be surfaced to scaffold authors at creation time).
#
# Invoked via:  bash skills/create-skill/scripts/test-render-skill-md.sh
# Wired into:   make lint (via the test-render-skill Makefile target).

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)"
RENDER_SCRIPT="${REPO_ROOT}/skills/create-skill/scripts/render-skill-md.sh"

if [[ ! -x "$RENDER_SCRIPT" && ! -f "$RENDER_SCRIPT" ]]; then
  echo "FAIL: render-skill-md.sh not found at $RENDER_SCRIPT" >&2
  exit 1
fi

TMPROOT="$(mktemp -d "${TMPDIR:-/tmp}/test-render-skill-md.XXXXXX")"
trap 'rm -rf "$TMPROOT"' EXIT

# shellcheck disable=SC2016  # literal ${CLAUDE_PLUGIN_ROOT} string, no expansion intended
PLUGIN_TOKEN='${CLAUDE_PLUGIN_ROOT}'  # literal — scaffolds embed this as-is
LOCAL_TOKEN="$PLUGIN_TOKEN"

FAIL_COUNT=0
PASS_COUNT=0

run_case() {
  local label="$1"
  local multi_step="$2"
  local target_dir="$3"
  local name="$4"
  local description="$5"

  echo "--- CASE: $label (multi-step=$multi_step) ---"

  local render_stdout
  if ! render_stdout="$(bash "$RENDER_SCRIPT" \
      --name "$name" \
      --description "$description" \
      --target-dir "$target_dir" \
      --local-token "$LOCAL_TOKEN" \
      --plugin-token "$PLUGIN_TOKEN" \
      --multi-step "$multi_step" 2>&1)"; then
    echo "FAIL: render-skill-md.sh exited non-zero for $label" >&2
    echo "--- stdout/stderr ---" >&2
    printf '%s\n' "$render_stdout" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  local rendered_path
  # Use sed substring extraction (not `awk -F=`): awk splits on every `=`,
  # silently truncating paths containing a literal `=`. sed keeps the full
  # remainder after the first `=`. head -n1 caps to the first matching line.
  rendered_path="$(printf '%s\n' "$render_stdout" | sed -n 's/^RENDERED=//p' | head -n1)"
  if [[ -z "$rendered_path" ]]; then
    echo "FAIL: no RENDERED= line in stdout for $label" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  if [[ ! -f "$rendered_path" ]]; then
    echo "FAIL: RENDERED path does not exist: $rendered_path" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  local content
  content="$(cat "$rendered_path")"

  # Check frontmatter name.
  if ! printf '%s\n' "$content" | grep -Eq "^name: ${name}\$"; then
    echo "FAIL: rendered file missing expected 'name: $name' frontmatter" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check frontmatter description (must appear YAML-quoted per
  # render-skill-md.sh's always-double-quoted contract).
  if ! printf '%s\n' "$content" | grep -Fq "description: \"$description\""; then
    echo "FAIL: rendered file missing expected 'description: \"$description\"' frontmatter" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check that the ## Sub-skill Invocation section is present.
  if ! printf '%s\n' "$content" | grep -Fq '## Sub-skill Invocation'; then
    echo "FAIL: rendered file missing '## Sub-skill Invocation' section" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check that the Sub-skill Invocation section references the shared guide.
  # Must match PLUGIN_TOKEN + "/skills/shared/subskill-invocation.md" — the
  # PLUGIN_TOKEN prefix must be non-empty so an empty --plugin-token cannot
  # silently produce "/skills/shared/subskill-invocation.md" (rooted path
  # pointing at filesystem root).
  if ! printf '%s\n' "$content" | grep -Eq '\$\{CLAUDE_PLUGIN_ROOT\}/skills/shared/subskill-invocation\.md'; then
    echo "FAIL: rendered file does not cite \${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md" >&2
    echo "--- rendered content ---" >&2
    printf '%s\n' "$content" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check that the Sub-skill Invocation checklist references the anti-halt
  # continuation reminder (closes #177). This asserts that scaffolded
  # orchestrators inherit awareness of the anti-halt rule — without this the
  # scaffold would silently drop the rule for every new orchestrator.
  if ! printf '%s\n' "$content" | grep -Fq 'Anti-halt continuation reminder'; then
    echo "FAIL: rendered file does not mention 'Anti-halt continuation reminder' in the scaffold checklist" >&2
    echo "--- rendered content ---" >&2
    printf '%s\n' "$content" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  # Check that the rendered body cites the canonical skill-design-principles
  # doc (closes #216). Must match PLUGIN_TOKEN + "/skills/shared/skill-design-principles.md"
  # so an empty --plugin-token cannot silently emit a rooted pointer.
  if ! printf '%s\n' "$content" | grep -Eq '\$\{CLAUDE_PLUGIN_ROOT\}/skills/shared/skill-design-principles\.md'; then
    echo "FAIL: rendered file does not cite \${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md" >&2
    echo "--- rendered content ---" >&2
    printf '%s\n' "$content" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
    return
  fi

  echo "PASS: $label"
  PASS_COUNT=$((PASS_COUNT + 1))
}

# Case 1: multi-step variant under a plugin-mode target dir.
run_case "multi-step plugin-mode" true \
  "${TMPROOT}/plugin-root/skills/foo-multi" \
  "foo-multi" \
  "Use when doing foo across multiple steps."

# Case 2: minimal variant under a consumer-mode target dir.
run_case "minimal consumer-mode" false \
  "${TMPROOT}/consumer-root/.claude/skills/bar-minimal" \
  "bar-minimal" \
  "Use when doing bar once."

# Case 3: empty --plugin-token must be rejected — guards against silent
# "/skills/shared/subskill-invocation.md" emission (rooted-path injection
# via misconfigured caller).
echo "--- CASE: empty plugin-token rejected ---"
empty_token_out=""
if empty_token_out="$(bash "$RENDER_SCRIPT" \
    --name "empty-token-case" \
    --description "x" \
    --target-dir "${TMPROOT}/empty-token/.claude/skills/empty-token-case" \
    --local-token '$PWD' \
    --plugin-token "" \
    --multi-step false 2>&1)"; then
  echo "FAIL: render-skill-md.sh accepted empty --plugin-token (should reject)" >&2
  printf '%s\n' "$empty_token_out" >&2
  FAIL_COUNT=$((FAIL_COUNT + 1))
else
  if printf '%s\n' "$empty_token_out" | grep -Fq 'ERROR=Missing required argument --plugin-token'; then
    echo "PASS: empty plugin-token rejected with expected ERROR= line"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "FAIL: empty plugin-token rejected but wrong error message" >&2
    printf '%s\n' "$empty_token_out" >&2
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
fi

echo ""
echo "=== SUMMARY: $PASS_COUNT passed, $FAIL_COUNT failed ==="

if [[ "$FAIL_COUNT" -gt 0 ]]; then
  exit 1
fi

exit 0
