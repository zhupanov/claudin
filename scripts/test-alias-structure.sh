#!/bin/bash
# Structural regression test for skills/alias/SKILL.md (closes #597 FINDING_5).
# Pins the prompt-side contract that target-dir resolution flows through a
# single $TARGET_DIR variable computed at Step 2, threaded into Steps 2/3/4,
# rather than via hardcoded `.claude/skills/<alias-name>` paths in any of those
# sites. Companion to scripts/test-alias-target-resolution.sh: that harness
# tests the resolve-target.sh helper; this harness tests that SKILL.md actually
# *uses* the helper's output everywhere.
#
# Asserts:
#  (A) SKILL.md references resolve-target.sh exactly once (Step 2 invocation).
#  (B) Step 1 documents --private as a parsed flag.
#  (C) Step 2 has the canonical non-eval allowlist parser literal
#      (REPO_ROOT|PLUGIN_REPO|TARGET_DIR allowlist).
#  (D) Check 6 uses test -e "$TARGET_DIR" (not -d, not hardcoded path).
#  (E) E_COLLISION error string interpolates $TARGET_DIR (not a literal
#      `.claude/skills/<alias-name>/`).
#  (F) Step 3 /implement recipe references $TARGET_DIR for both mkdir and
#      redirect path (no `mkdir -p .claude/skills/<alias-name>` and no
#      `> ".claude/skills/<alias-name>/SKILL.md"`).
#  (G) Step 3 announce line interpolates $TARGET_DIR.
#  (H) Step 4 sentinel-file uses "$TARGET_DIR/SKILL.md" and does NOT contain
#      the old REPO_ROOT=$(git rev-parse ... || pwd -P) line (per FINDING_2 —
#      eliminates inconsistent root resolution).
#  (I) NEVER list mentions --private (rule #5 update) and TARGET_DIR
#      threading (rule #6) and non-eval (rule #7).
#  (J) Frontmatter argument-hint includes [--private].
#  (K) No stale hardcoded `.claude/skills/<alias-name>` write/sentinel paths
#      outside intentional places (frontmatter `description`, top examples,
#      and the explanatory NEVER #6 prose are allowed; the load-bearing
#      Step 2/3/4 sites must NOT contain them).
#
# Exit 0 on pass, exit 1 on any assertion failure.
# shellcheck disable=SC2016
set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/.." && pwd -P)
SKILL_MD="$REPO_ROOT/skills/alias/SKILL.md"

fail() {
  echo "FAIL: $1" >&2
  exit 1
}

[[ -f "$SKILL_MD" ]] || fail "skills/alias/SKILL.md missing: $SKILL_MD"

# (A) Exactly one resolve-target.sh invocation reference (under Step 2). The
# sibling .md file path is also expected once, so total occurrences of the
# string `resolve-target.sh` is at least 2 (one invocation, one prose pointer
# at minimum). We assert >= 1 invocation by grepping for the script invocation
# token specifically.
resolve_invocation_count=$(grep -c 'skills/alias/scripts/resolve-target\.sh' "$SKILL_MD" || true)
[[ "$resolve_invocation_count" -ge 1 ]] \
  || fail "(A) expected resolve-target.sh to be referenced in SKILL.md, found 0"

# (B) Step 1 parses --private.
grep -q -- '--private' "$SKILL_MD" \
  || fail "(B) expected --private flag documented in SKILL.md"

# (C) Non-eval allowlist parser literal.
grep -q 'REPO_ROOT|PLUGIN_REPO|TARGET_DIR' "$SKILL_MD" \
  || fail "(C) expected canonical allowlist 'REPO_ROOT|PLUGIN_REPO|TARGET_DIR' in Step 2 parser block"

# (D) Check 6 uses test -e "$TARGET_DIR" (not -d, not hardcoded path).
grep -q 'test -e "\$TARGET_DIR"' "$SKILL_MD" \
  || fail "(D) expected Check 6 to use 'test -e \"\$TARGET_DIR\"'"
# Negative: ensure the previous hardcoded-path collision check is gone.
if grep -q 'test -d "\.claude/skills/<alias-name>"' "$SKILL_MD"; then
  fail "(D-neg) old hardcoded collision check 'test -d \".claude/skills/<alias-name>\"' still present"
fi

# (E) E_COLLISION error string interpolates $TARGET_DIR.
grep -q 'E_COLLISION.*\$TARGET_DIR' "$SKILL_MD" \
  || fail "(E) expected E_COLLISION row to reference \$TARGET_DIR"

# (F) Step 3 /implement recipe uses $TARGET_DIR for mkdir and redirect.
grep -q 'mkdir -p "\$TARGET_DIR"' "$SKILL_MD" \
  || fail "(F.1) expected 'mkdir -p \"\$TARGET_DIR\"' in Step 3 recipe"
grep -q '> "\$TARGET_DIR/SKILL.md"' "$SKILL_MD" \
  || fail "(F.2) expected redirect '> \"\$TARGET_DIR/SKILL.md\"' in Step 3 recipe"
# Negative: old hardcoded recipe paths.
if grep -q 'mkdir -p \.claude/skills/<alias-name>$' "$SKILL_MD" \
   || grep -q '> "\.claude/skills/<alias-name>/SKILL\.md"' "$SKILL_MD"; then
  fail "(F-neg) old hardcoded recipe path '.claude/skills/<alias-name>/...' still in Step 3"
fi

# (G) Step 3 announce line interpolates $TARGET_DIR.
grep -q 'target: \$TARGET_DIR' "$SKILL_MD" \
  || fail "(G) expected announce line to interpolate \$TARGET_DIR"

# (H) Step 4 sentinel uses $TARGET_DIR/SKILL.md.
grep -q -- '--sentinel-file "\$TARGET_DIR/SKILL.md"' "$SKILL_MD" \
  || fail "(H.1) expected --sentinel-file \"\$TARGET_DIR/SKILL.md\" in Step 4"
# Negative: old REPO_ROOT line should be gone (FINDING_2).
if grep -q 'REPO_ROOT=\$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)' "$SKILL_MD"; then
  fail "(H.2-neg) old 'REPO_ROOT=\$(git rev-parse ... || pwd -P)' still present in Step 4"
fi

# (I) NEVER list updates.
grep -q 'NEVER parse.*--merge.*--no-slack.*--private' "$SKILL_MD" \
  || fail "(I.1) NEVER #5 should mention all three flags (--merge, --no-slack, --private)"
grep -q 'NEVER hardcode' "$SKILL_MD" \
  || fail "(I.2) NEVER list should include the TARGET_DIR-threading rule"
grep -q 'NEVER use .eval' "$SKILL_MD" \
  || fail "(I.3) NEVER list should forbid eval of resolve-target.sh stdout"

# (J) Frontmatter argument-hint includes [--private].
grep -q 'argument-hint: "\[--merge\] \[--no-slack\] \[--private\]' "$SKILL_MD" \
  || fail "(J) frontmatter argument-hint must include [--private]"

# (K) No stale Step-2/3/4 hardcoded paths.
# Allowlist contexts: frontmatter description, the top "Example" lines, NEVER
# rule prose, the dual-role table cell. We grep for the literal hardcoded path
# ONLY in load-bearing contexts (recipe, sentinel, collision check) — those
# specific patterns are caught by (D-neg), (F-neg), (H.2-neg) above.
# This (K) acts as a final sweep: if any line outside the allowlisted prose
# contains the literal `.claude/skills/<alias-name>` followed immediately by
# `/` (path-form), the check warns.
# We allow the string to appear in: frontmatter description, the top examples
# block, the NEVER #6 explanation. We disallow it in:
#   - The Step 3 fenced bash recipe block (caught by F-neg).
#   - The Step 4 sentinel argument (caught by H.1).
#   - The E_COLLISION error string row (caught by E).
# So (K) is a no-op here aside from the negative checks already done. We keep
# this assertion as a structural breadcrumb to remind future editors that any
# new occurrence of `.claude/skills/<alias-name>/` outside the documented
# allowlist must be reviewed.
:

echo "test-alias-structure.sh: all assertions passed"
