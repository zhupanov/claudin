---
name: alias
description: "Use when creating shortcut aliases (wrappers) for existing larch skills with preset flags. Generates a project-level skill in .claude/skills/ via /implement delegation, with optional --merge / --slack passthrough."
argument-hint: "[--merge] [--slack] <alias-name> <target-skill> [preset-flags...]"
allowed-tools: Bash, Skill
---

# Alias Skill

This skill follows the Process pattern: numbered steps, checkpointed delegation, fail-closed verification.

Create a project-level alias skill in `.claude/skills/` that forwards to an existing larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (implementation, code review, version bump, PR), then verifies the artifact landed on disk.

Example: `/alias i implement --merge` creates `.claude/skills/i/SKILL.md` so that `/i <feature>` is equivalent to `/implement --merge <feature>`.

Example with merge: `/alias --merge i implement --merge` creates the same alias AND merges the PR after CI passes.

## NEVER

1. **NEVER create an alias that targets `/alias`** — no alias-to-alias recursion. **Why:** would multiply indirection and break the flat forwarding contract. Enforced by Step 2 check #5.
2. **NEVER let an alias name shadow an existing larch skill** — neither in `skills/` (public) nor `.claude/skills/` (dev-only). **Why:** shadowing silently reroutes `/<name>` invocations. Enforced by Step 2 check #2 via dynamic probe.
3. **NEVER auto-remediate when `VERIFIED=false` in Step 4** — do NOT retry `/implement`, roll back, or delete the PR. **Why:** under `--merge` the PR may already be merged; retry would create a divergent PR. Human judgment required.
4. **NEVER assume success on `VERIFIED=false` just because `/implement` returned.** **Why:** `/implement` can return cleanly while writing the file to the wrong path, skipping the generator, or failing silently — the sentinel-file gate is the only authoritative signal.
5. **NEVER parse `--merge` or `--slack` tokens after the first positional argument as flags for `/alias`.** **Why:** both flags have a dual role (consumed by `/alias` when before the first positional; passed through to the alias's preset flags otherwise); conflating the two is a silent footgun.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `bail`, `skip to Step N`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule. **Do NOT load** that reference for routine invocations — the inline rule above is sufficient. Load it only when debugging a child-Skill halt symptom or when adding a new child-Skill invocation to this file.

## Step 1 — Parse Arguments

Parse flags from the start of `$ARGUMENTS` before treating the remainder as positional arguments. Stop at the first non-flag token (a token not starting with `--`). Only `--merge` and `--slack` appearing before the first positional argument are consumed as flags for `/alias` itself; any occurrence in the preset-flags remainder is passed through verbatim to the alias.

- `--merge`: Set `alias_merge=true`. Default: `alias_merge=false`. When true, `--merge` is forwarded to the `/implement` invocation so the resulting PR is also merged.
- `--slack`: Set `alias_slack=true`. Default: `alias_slack=false`. When true, `--slack` is forwarded to the `/implement` invocation so PR creation (and merge, if `--merge` is also set) posts to Slack. Without `--slack`, `/alias`'s own `/implement` run does not post to Slack regardless of Slack env-var presence. This flag controls only `/alias`'s creation-time `/implement` run — it does NOT add `--slack` to the generated alias's preset flags (put `--slack` after the first positional for that behavior).

**`--merge` / `--slack` dual-role reference**:

| Position | Meaning |
|----------|---------|
| Before first positional token | Consumed by /alias (`--merge` → `alias_merge=true`; `--slack` → `alias_slack=true`) |
| After first positional token | Pass-through to the generated alias's preset flags |

After flag stripping, parse the remaining positional arguments:
- First token = **alias name**
- Second token = **target skill name** (without `/` prefix)
- Remainder = **preset flags** (may be empty — a pure rename shortcut is valid)

If fewer than 2 positional tokens are provided, print: `**ERROR: Usage: /alias [--merge] <alias-name> <target-skill> [preset-flags...]**` and abort.

## Step 2 — Validate

All validation uses Bash since `${CLAUDE_PLUGIN_ROOT}` is a shell variable not resolvable in Read/Glob.

| # | Check | Rule | On fail |
|---|-------|------|---------|
| 1 | Alias name format | Must match `^[a-z][a-z0-9-]*$` (lowercase, alphanumeric + hyphens, must start with a letter) | `E_ALIAS_NAME` |
| 2 | Reserved name (dynamic probe) | `${CLAUDE_PLUGIN_ROOT}` must be set; alias name must not collide with any directory under `${CLAUDE_PLUGIN_ROOT}/skills/<alias-name>` OR `${CLAUDE_PLUGIN_ROOT}/.claude/skills/<alias-name>`. See `### Check 2` block below. | `E_PLUGIN_ROOT_UNSET` or `E_SHADOW` |
| 3 | Target name format | Must match `^[a-z][a-z0-9-]*$` (same format as alias names) | `E_TARGET_NAME` |
| 4 | Target skill exists | `test -f "${CLAUDE_PLUGIN_ROOT}/skills/<target>/SKILL.md"`; if missing, also run `ls "${CLAUDE_PLUGIN_ROOT}/skills/"` for discoverability | `E_TARGET_MISSING` |
| 5 | Target is not `alias` | Forbid alias-to-alias recursion | `E_RECURSION` |
| 6 | Collision check | `test -d ".claude/skills/<alias-name>"` must be false | `E_COLLISION` |

### Check 2 — reserved-name dynamic probe

Fail-closed on unset `${CLAUDE_PLUGIN_ROOT}`, then probe both plugin-tree roots for a directory collision:

```bash
if [[ -z "${CLAUDE_PLUGIN_ROOT:-}" ]]; then
  echo "**ERROR: CLAUDE_PLUGIN_ROOT is unset — cannot probe larch skill tree for reserved-name collision.**"
  exit 1
fi
# probe BOTH roots: skills/ (public) and .claude/skills/ (dev-only: bump-version, relevant-checks)
if test -d "${CLAUDE_PLUGIN_ROOT}/skills/<alias-name>" \
  || test -d "${CLAUDE_PLUGIN_ROOT}/.claude/skills/<alias-name>"; then
  echo "**ERROR: alias name '<alias-name>' shadows an existing larch skill.**"
  exit 1
fi
```

One conceptual rule — "alias cannot shadow any larch skill" — replacing the prior static enumeration that was drifting as new skills shipped.

### Error strings (reference)

| ID | Printed string |
|----|----------------|
| `E_ALIAS_NAME` | `**ERROR: Alias name '<name>' is invalid. Must start with a lowercase letter and contain only lowercase letters, digits, and hyphens.**` |
| `E_PLUGIN_ROOT_UNSET` | `**ERROR: CLAUDE_PLUGIN_ROOT is unset — cannot probe larch skill tree for reserved-name collision.**` |
| `E_SHADOW` | `**ERROR: alias name '<alias-name>' shadows an existing larch skill.**` |
| `E_TARGET_NAME` | `**ERROR: Target name '<target>' is invalid. Must contain only lowercase letters, digits, and hyphens.**` |
| `E_TARGET_MISSING` | `**ERROR: Target skill '<target>' does not exist.**` (then run `ls "${CLAUDE_PLUGIN_ROOT}/skills/"` and abort) |
| `E_RECURSION` | `**ERROR: Cannot create an alias that targets /alias (no alias-to-alias recursion).**` |
| `E_COLLISION` | `**ERROR: '.claude/skills/<alias-name>/' already exists. Remove it first or choose a different name.**` |

## Step 3 — Delegate to /implement

### Before delegating, ask

- **What does `/implement` need to build this deterministically?** `/implement` has no codebase context about `/alias` — it will research and guess unless the feature description cites the generator script path, its required flags, the version source, and the write target. The explicit recipe below supplies all four.
- **What could make the Step 4 verification silently pass when it shouldn't?** Nothing — the `verify-skill-called.sh --sentinel-file` gate reads a child-produced artifact (`.claude/skills/<alias-name>/SKILL.md`) that the outer orchestrator cannot synthesize. A parent-writable gate would not be load-bearing.
- **Why no retry on `VERIFIED=false`?** Under `--merge` the PR may already be merged by the time control returns; any automated retry would create a divergent PR. Step 4 surfaces branch-specific diagnostic messages instead, leaving recovery to human judgment.

Construct an explicit feature description for `/implement`. The description MUST cite the generator script path, its required flags, the version source, and the write target so `/implement` has a complete, deterministic build recipe — no codebase research required:

```
Add /<alias-name> alias for /<target-skill> <preset-flags>.

Generate the alias skill by running:
  mkdir -p .claude/skills/<alias-name>
  "${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh" \
    --name "<alias-name>" \
    --target "<target-skill>" \
    --flags "<preset-flags>" \
    --version "$(jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")" \
    > ".claude/skills/<alias-name>/SKILL.md"

If jq fails or plugin.json is malformed, proceed with an empty --version value (the generator handles this — the footer simply omits the vX.Y.Z suffix).
```

Omit the `<preset-flags>` segment from the leading sentence when empty (pure rename shortcut).

Print: `**Alias /<alias-name> -> /<target-skill> <preset-flags> — delegating to /implement --quick --auto [--merge] [--slack]**` (omit `<preset-flags>` if empty; omit `--merge` if `alias_merge=false`; omit `--slack` if `alias_slack=false`).

Invoke the Skill tool:
- Try skill: `"implement"` first (bare name). If no skill matches, try skill: `"larch:implement"` (fully-qualified plugin name).
- args: `"--quick --auto [--merge] [--slack] <feature-description>"`

Only include `--merge` in the args if `alias_merge=true`. Only include `--slack` in the args if `alias_slack=true`.

> **Continue after child returns.** When `/implement` returns, execute Step 4 — do NOT end the turn. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder. **Do NOT load** that reference for routine `/implement` returns — load only when adding a new child-Skill invocation to this file or when debugging a halt symptom.

## Step 4 — Verify

After `/implement` returns, verify the alias SKILL.md actually landed on disk. Run from repo root (resolved robustly regardless of agent cwd):

```bash
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd -P)
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
  --sentinel-file "${REPO_ROOT}/.claude/skills/<alias-name>/SKILL.md"
```

Parse stdout for `VERIFIED=true|false` and `REASON=<token>`.

- **If `VERIFIED=true`**: print `✅ /alias — created .claude/skills/<alias-name>/SKILL.md` and exit 0.
- **If `VERIFIED=false`**: print a fail-closed error and exit 1. Branch the message on `alias_merge`:
  - **If `alias_merge=false`** (PR created but not merged):
    ```
    **ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. Inspect the PR/branch manually — /implement may have written the file elsewhere, skipped the generator, or failed silently.**
    ```
  - **If `alias_merge=true`** (PR may already be merged):
    ```
    **ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). The PR may have already been merged — do not assume success. Inspect the PR/branch/merged-main manually; a revert or follow-up PR may be required.**
    ```
  Do not attempt auto-remediation — `/implement` has already created (and possibly merged) the PR, so any recovery requires human judgment.

### Authoritative exit states

| State | Condition | Printed string (summary) |
|-------|-----------|--------------------------|
| Success | `VERIFIED=true` | `✅ /alias — created .claude/skills/<alias-name>/SKILL.md` |
| Validation fail | Any Step 2 check fails | one of the `E_*` strings from the Step 2 `Error strings (reference)` table |
| Verify fail (unmerged) | `VERIFIED=false` AND `alias_merge=false` | `**ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. ...**` (full string above) |
| Verify fail (merged) | `VERIFIED=false` AND `alias_merge=true` | `**ERROR: /implement returned but .claude/skills/<alias-name>/SKILL.md was not written (REASON=<token>). The PR may have already been merged ...**` (full string above) |
