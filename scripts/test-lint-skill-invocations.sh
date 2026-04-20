#!/usr/bin/env bash
# test-lint-skill-invocations.sh — Regression harness for scripts/lint-skill-invocations.py.
#
# Black-box contract test. For each case, writes a synthetic SKILL.md under
# $TMPROOT/<subtree>/<name>/SKILL.md, invokes the lint with --root "$TMPROOT",
# and asserts on exit code and stderr content.
#
# Cases (indexed a-l in the table below):
#   a  Skill + Pattern A ("Invoke the Skill tool")           → exit 0
#   b  Skill + Pattern B ("Invoke `/foo` via the Skill tool") → exit 0
#   c  no Skill in allowed-tools + no invocation phrase       → exit 0 (lint does not apply)
#   d  Skill + no invocation phrase                           → exit 1 (violation)
#   e  YAML list allowed-tools: [Bash, Skill] + Pattern B     → exit 0
#   f  Only SkillCheck listed (no exact `Skill`) + no phrase  → exit 0 (exact-token discipline)
#   g  Quoted allowed-tools: "Bash, Skill" + Pattern A        → exit 0
#   h  Two violations in the same run                          → exit 1, both named in stderr
#   i  CRLF-formatted file + Skill + Pattern B                → exit 0 (CRLF normalized)
#   j  UTF-8 BOM + CRLF + Skill + no phrase                   → exit 1 (BOM stripped, violation seen)
#   k  Non-UTF-8 bytes in SKILL.md                             → exit 2 (internal error path)
#   l  Mixed: non-UTF-8 file + valid violation in same run    → exit 2 (priority), both in stderr
#
# Usage: bash scripts/test-lint-skill-invocations.sh
# Exit: 0 — all assertions passed; 1 — at least one assertion failed.

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
LINT="$REPO_ROOT/scripts/lint-skill-invocations.py"

if [[ ! -f "$LINT" ]]; then
    echo "ERROR: lint script not found: $LINT" >&2
    exit 1
fi

if ! command -v python3 >/dev/null 2>&1; then
    echo "FAIL: python3 not on PATH" >&2
    exit 1
fi

if ! python3 -c 'import yaml' 2>/dev/null; then
    echo "FAIL: python3 PyYAML (yaml module) not importable — install via pre-commit additional_dependencies or 'pip install pyyaml'" >&2
    exit 1
fi

TMPROOT=$(mktemp -d -t lint-skill-invocations-test-XXXXXX)
trap 'rm -rf "$TMPROOT"' EXIT

PASS=0
FAIL=0

assert_case() {
    local label="$1" expected_exit="$2" stderr_file="$3" exit_code="$4"
    shift 4
    if [[ "$exit_code" -ne "$expected_exit" ]]; then
        echo "FAIL [$label]: expected exit $expected_exit, got $exit_code" >&2
        echo "--- stderr ---" >&2
        cat "$stderr_file" >&2
        echo "--------------" >&2
        FAIL=$((FAIL + 1))
        return
    fi
    for needle in "$@"; do
        if ! grep -Fq "$needle" "$stderr_file"; then
            echo "FAIL [$label]: stderr missing expected needle: $needle" >&2
            echo "--- stderr ---" >&2
            cat "$stderr_file" >&2
            echo "--------------" >&2
            FAIL=$((FAIL + 1))
            return
        fi
    done
    PASS=$((PASS + 1))
    echo "PASS [$label]"
}

write_skill() {
    local path="$1"
    mkdir -p "$(dirname "$path")"
    cat > "$path"
}

reset_tree() {
    rm -rf "$TMPROOT"/skills "$TMPROOT"/.claude
}

run_lint() {
    local stderr_file="$1"
    set +e
    python3 "$LINT" --root "$TMPROOT" 2>"$stderr_file"
    local rc=$?
    set -e
    echo "$rc"
}

# --- Case a: Skill + Pattern A --------------------------------------------
reset_tree
write_skill "$TMPROOT/skills/case-a/SKILL.md" <<'EOF'
---
name: case-a
description: case a
allowed-tools: Bash, Skill
---

# Case A

Invoke the Skill tool:
- skill: "foo"
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "a (Skill + Pattern A)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case b: Skill + Pattern B --------------------------------------------
reset_tree
write_skill "$TMPROOT/skills/case-b/SKILL.md" <<'EOF'
---
name: case-b
description: case b
allowed-tools: Bash, Read, Skill
---

# Case B

1. Invoke `/foo` via the Skill tool to do the thing.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "b (Skill + Pattern B)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case c: no Skill in allowed-tools (lint does not apply) --------------
reset_tree
write_skill "$TMPROOT/skills/case-c/SKILL.md" <<'EOF'
---
name: case-c
description: case c
allowed-tools: Bash, Read
---

# Case C

No invocation phrase here, but allowed-tools does not include Skill.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "c (no Skill, no phrase — exempt)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case d: Skill + NO invocation phrase (violation) ---------------------
reset_tree
write_skill "$TMPROOT/skills/case-d/SKILL.md" <<'EOF'
---
name: case-d
description: case d
allowed-tools: Bash, Skill
---

# Case D

This file declares Skill but never says the canonical phrase.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "d (Skill + no phrase — violation)" 1 "$stderr_file" "$rc" \
    "skills/case-d/SKILL.md" "declares 'Skill' in allowed-tools"
rm -f "$stderr_file"

# --- Case e: YAML list allowed-tools + Pattern B --------------------------
reset_tree
write_skill "$TMPROOT/skills/case-e/SKILL.md" <<'EOF'
---
name: case-e
description: case e
allowed-tools: [Bash, Read, Skill]
---

# Case E

Invoke `/thing` via the Skill tool.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "e (YAML list + Pattern B)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case f: only SkillCheck listed (substring check discipline) ----------
reset_tree
write_skill "$TMPROOT/skills/case-f/SKILL.md" <<'EOF'
---
name: case-f
description: case f
allowed-tools: Bash, SkillCheck
---

# Case F

No invocation phrase — but the lint should NOT trigger because the exact token
`Skill` is not in allowed-tools (only `SkillCheck` is).
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "f (only SkillCheck, no Skill — exempt)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case g: quoted allowed-tools string + Pattern A ----------------------
reset_tree
write_skill "$TMPROOT/skills/case-g/SKILL.md" <<'EOF'
---
name: case-g
description: case g
allowed-tools: "Bash, Skill"
---

# Case G

Invoke the Skill tool:
- skill: "foo"
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "g (quoted allowed-tools + Pattern A)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case h: two violations in one run (both named in stderr) -------------
reset_tree
write_skill "$TMPROOT/skills/case-h1/SKILL.md" <<'EOF'
---
name: case-h1
description: case h1
allowed-tools: Bash, Skill
---

# Case H1

Missing phrase.
EOF
write_skill "$TMPROOT/.claude/skills/case-h2/SKILL.md" <<'EOF'
---
name: case-h2
description: case h2
allowed-tools: Skill
---

# Case H2

Also missing phrase.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "h (two violations named)" 1 "$stderr_file" "$rc" \
    "skills/case-h1/SKILL.md" ".claude/skills/case-h2/SKILL.md"
rm -f "$stderr_file"

# --- Case i: CRLF line endings (should be normalized) --------------------
reset_tree
mkdir -p "$TMPROOT/skills/case-i"
# shellcheck disable=SC2016  # literal backticks and /foo are intentional fixture content
printf '%s\r\n' \
    '---' \
    'name: case-i' \
    'description: case i' \
    'allowed-tools: Bash, Skill' \
    '---' \
    '' \
    '# Case I' \
    '' \
    'Invoke `/foo` via the Skill tool.' > "$TMPROOT/skills/case-i/SKILL.md"
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "i (CRLF + Skill + Pattern B — normalized)" 0 "$stderr_file" "$rc"
rm -f "$stderr_file"

# --- Case j: UTF-8 BOM + CRLF + Skill + no phrase (violation) -------------
reset_tree
mkdir -p "$TMPROOT/skills/case-j"
{
    printf '\xef\xbb\xbf'
    printf '%s\r\n' \
        '---' \
        'name: case-j' \
        'description: case j' \
        'allowed-tools: Bash, Skill' \
        '---' \
        '' \
        '# Case J' \
        '' \
        'No invocation phrase here.'
} > "$TMPROOT/skills/case-j/SKILL.md"
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "j (BOM+CRLF + Skill + no phrase — violation seen)" 1 "$stderr_file" "$rc" \
    "skills/case-j/SKILL.md" "declares 'Skill' in allowed-tools"
rm -f "$stderr_file"

# --- Case k: non-UTF-8 bytes trigger exit-2 internal-error path -----------
reset_tree
mkdir -p "$TMPROOT/skills/case-k"
# Write raw 0xFF 0xFE bytes (invalid UTF-8 start) so read_text(encoding="utf-8")
# raises UnicodeDecodeError and the lint routes it to LintError → exit 2.
printf '\xff\xfe' > "$TMPROOT/skills/case-k/SKILL.md"
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "k (non-UTF-8 bytes — exit 2 internal error)" 2 "$stderr_file" "$rc" \
    "case-k/SKILL.md" "cannot read file"
rm -f "$stderr_file"

# --- Case l: mixed error + violation; exit 2 takes priority --------------
reset_tree
mkdir -p "$TMPROOT/skills/case-l-err"
printf '\xff\xfe' > "$TMPROOT/skills/case-l-err/SKILL.md"
write_skill "$TMPROOT/skills/case-l-vio/SKILL.md" <<'EOF'
---
name: case-l-vio
description: case l violation
allowed-tools: Bash, Skill
---

# Case L (violation)

No invocation phrase here.
EOF
stderr_file=$(mktemp)
rc=$(run_lint "$stderr_file")
assert_case "l (mixed error+violation — exit 2 wins, both in stderr)" 2 "$stderr_file" "$rc" \
    "case-l-err/SKILL.md" "cannot read file" \
    "case-l-vio/SKILL.md" "declares 'Skill' in allowed-tools"
rm -f "$stderr_file"

# --- Summary --------------------------------------------------------------
echo ""
echo "Summary: $PASS passed, $FAIL failed"
if [[ "$FAIL" -ne 0 ]]; then
    exit 1
fi
exit 0
