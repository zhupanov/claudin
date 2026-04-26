---
name: alias
description: "Use when creating shortcut aliases for existing larch skills with preset flags. Auto-routes to plugin tree skills/ inside Claude plugin source repos, dev-only .claude/skills/ elsewhere; --private forces dev-only. --merge / --no-slack passthrough."
argument-hint: "[--merge] [--no-slack] [--private] <alias-name> <target-skill> [preset-flags...]"
allowed-tools: Bash, Skill
---

# Alias Skill

This skill follows the Process pattern: numbered steps, checkpointed delegation, fail-closed verification.

Create an alias skill that forwards to an existing larch skill with preset flags. Delegates to `/implement --quick --auto` for the full pipeline (implementation, code review, version bump, PR), then verifies the artifact landed on disk.

**Target directory** is resolved automatically:

- A **git repository is required** — the helper (`skills/alias/scripts/resolve-target.sh`) anchors all paths at `git rev-parse --show-toplevel` and fail-closes outside a git working tree. Run `git init` first if you want to use `/alias` in a fresh project.
- Inside a Claude plugin source repo (detected via the two-file predicate `.claude-plugin/plugin.json` AND `skills/implement/SKILL.md` at the git repo root, matching `validate-args.sh`), the alias is generated under `skills/<alias-name>/SKILL.md` (exported plugin skill, ships with the plugin).
- In any other git repository (consumer repos with their own larch installation), the alias is generated under `.claude/skills/<alias-name>/SKILL.md` (dev-only repo-private skill).
- `--private` forces `.claude/skills/<alias-name>/` even inside a plugin repo (escape hatch when the operator wants a private alias in plugin source). In non-plugin repos `--private` is a no-op.

Example (in a plugin source repo): `/alias i implement --merge` creates `<repo-root>/skills/i/SKILL.md` so that `/i <feature>` is equivalent to `/implement --merge <feature>`.

Example (in a consumer repo, OR with `--private` in a plugin repo): `/alias i implement --merge` creates `<repo-root>/.claude/skills/i/SKILL.md` (dev-only).

Example with merge: `/alias --merge i implement --merge` creates the alias AND merges the PR after CI passes.

## NEVER

1. **NEVER create an alias that targets `/alias`** — no alias-to-alias recursion. **Why:** would multiply indirection and break the flat forwarding contract. Enforced by Step 2 check #5.
2. **NEVER let an alias name shadow an existing larch skill** — neither in `skills/` (public) nor `.claude/skills/` (dev-only). **Why:** shadowing silently reroutes `/<name>` invocations. Enforced by Step 2 check #2 via dynamic probe.
3. **NEVER auto-remediate when `VERIFIED=false` in Step 4** — do NOT retry `/implement`, roll back, or delete the PR. **Why:** under `--merge` the PR may already be merged; retry would create a divergent PR. Human judgment required.
4. **NEVER assume success on `VERIFIED=false` just because `/implement` returned.** **Why:** `/implement` can return cleanly while writing the file to the wrong path, skipping the generator, or failing silently — the sentinel-file gate is the only authoritative signal.
5. **NEVER parse `--merge`, `--no-slack`, or `--private` tokens after the first positional argument as flags for `/alias`.** **Why:** all three flags have a dual role (consumed by `/alias` when before the first positional; passed through to the alias's preset flags otherwise); conflating the two is a silent footgun.
6. **NEVER hardcode `.claude/skills/<alias-name>` or `skills/<alias-name>` paths anywhere in Steps 2/3/4 — always thread `$TARGET_DIR`.** **Why:** the resolved target directory is the single source of truth (computed once at Step 2 by `resolve-target.sh`); a partial edit that re-introduces a hardcoded path in one site (e.g., the `/implement` recipe) but not another (e.g., the verify sentinel) creates a silent path split where `/implement` writes one tree and Step 4 verifies a different tree. Enforced by `scripts/test-alias-structure.sh` (CI).
7. **NEVER use `eval "$(resolve-target.sh ...)"` to consume the helper's stdout.** **Why:** `eval` of a path that contains shell metacharacters (spaces, `$(...)`, backticks) creates shell-injection risk if the script's stdout contract ever drifts. Use the non-eval allowlist parser shown in Step 2's bash block. See `skills/alias/scripts/resolve-target.md` "Caller parsing requirement" for the required pattern.

**Anti-halt continuation reminder.** After every child `Skill` tool call (e.g., `/implement`) returns, IMMEDIATELY continue with this skill's NEXT numbered step — do NOT end the turn on the child's cleanup output, and do NOT write a summary, handoff, status recap, or "returning to parent" message — those are halts in disguise. The rule is strictly subordinate to any explicit non-sequential control-flow directive in THIS file (e.g., `bail`, `skip to Step N`). A normal sequential `proceed to Step N+1` instruction is the default continuation this rule reinforces, NOT an exception. Every `/relevant-checks` invocation anywhere in this file is covered by this rule. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder for the canonical rule. **Do NOT load** that reference for routine invocations — the inline rule above is sufficient. Load it only when debugging a child-Skill halt symptom or when adding a new child-Skill invocation to this file.

## Step 1 — Parse Arguments

Parse flags from the start of `$ARGUMENTS` before treating the remainder as positional arguments. Stop at the first non-flag token (a token not starting with `--`). Only `--merge`, `--no-slack`, and `--private` appearing before the first positional argument are consumed as flags for `/alias` itself; any occurrence in the preset-flags remainder is passed through verbatim to the alias.

- `--merge`: Set `alias_merge=true`. Default: `alias_merge=false`. When true, `--merge` is forwarded to the `/implement` invocation so the resulting PR is also merged.
- `--no-slack`: Set `alias_no_slack=true`. Default: `alias_no_slack=false`. When true, `--no-slack` is forwarded to the `/implement` invocation so `/alias`'s own creation-time `/implement` run does NOT post to Slack. Default (no `--no-slack`): `/alias`'s own `/implement` run posts to Slack per `/implement`'s default-on behavior (gated on Slack env vars). This flag controls only `/alias`'s creation-time `/implement` run — it does NOT add `--no-slack` to the generated alias's preset flags (put `--no-slack` after the first positional for that behavior).
- `--private`: Set `alias_private=true`. Default: `alias_private=false`. When true, the new alias is forced under `.claude/skills/<alias-name>/` regardless of plugin-repo detection (escape hatch for creating a private alias inside a plugin source repo). When absent: target is `skills/<alias-name>/` if running in a plugin source repo, else `.claude/skills/<alias-name>/`. In non-plugin repos `--private` is a no-op (the default is already `.claude/skills/`). The flag is consumed by `/alias` only — it does NOT appear in the generated alias's preset flags.

**`--merge` / `--no-slack` / `--private` dual-role reference**:

| Position | Meaning |
|----------|---------|
| Before first positional token | Consumed by /alias (`--merge` → `alias_merge=true`; `--no-slack` → `alias_no_slack=true`; `--private` → `alias_private=true`) |
| After first positional token | Pass-through to the generated alias's preset flags |

After flag stripping, parse the remaining positional arguments:
- First token = **alias name**
- Second token = **target skill name** (without `/` prefix)
- Remainder = **preset flags** (may be empty — a pure rename shortcut is valid)

If fewer than 2 positional tokens are provided, print: `**ERROR: Usage: /alias [--merge] [--no-slack] [--private] <alias-name> <target-skill> [preset-flags...]**` and abort.

## Step 2 — Validate

All validation uses Bash since `${CLAUDE_PLUGIN_ROOT}` is a shell variable not resolvable in Read/Glob.

### Plugin-repo detection + target-dir resolution

Before running the validation table below, resolve the target directory (`$TARGET_DIR`) once via the helper script. The script's stdout is the single source of truth for `(plugin-detect, --private) → TARGET_DIR`; thread the resolved value through Check 6, Step 3 (`/implement` recipe + announce line), and Step 4 (verify sentinel). Distinct from `${CLAUDE_PLUGIN_ROOT}` (the plugin install path used by Check 2): `$REPO_ROOT` is the git working tree where the alias is materialized; the two can diverge in practice and Check 2's shadow probe is orthogonal to where the new alias is written.

```bash
# Build the optional --private flag dynamically.
PRIVATE_FLAG=()
if [[ "$alias_private" == "true" ]]; then
  PRIVATE_FLAG=(--private)
fi

# Non-eval line-by-line parse with explicit allowlist (per NEVER #7).
# Do NOT use `eval "$(resolve-target.sh ...)"` — paths containing spaces / $(...) /
# backticks would be re-interpreted by the shell.
REPO_ROOT=""; PLUGIN_REPO=""; TARGET_DIR=""
while IFS='=' read -r key val; do
  case "$key" in
    REPO_ROOT|PLUGIN_REPO|TARGET_DIR) declare "$key=$val" ;;
  esac
done < <("${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/resolve-target.sh" \
           --alias-name "<alias-name>" "${PRIVATE_FLAG[@]}")

# Fail-closed if the helper exited with empty values (e.g., not in a git repo).
# resolve-target.sh writes its diagnostic to stderr; surface a usable error to the operator.
if [[ -z "$TARGET_DIR" || -z "$REPO_ROOT" || -z "$PLUGIN_REPO" ]]; then
  echo "**ERROR: resolve-target.sh failed (likely not in a git repository, or git binary missing). Cannot determine target directory for alias '<alias-name>'.**"
  exit 1
fi
```

The helper's stdout schema and the two-file plugin-detect predicate (`.claude-plugin/plugin.json` AND `skills/implement/SKILL.md`, matching `validate-args.sh:133`) are documented in `skills/alias/scripts/resolve-target.md`. Operators wanting a private alias inside a plugin repo use `--private`.

### Validation table

| # | Check | Rule | On fail |
|---|-------|------|---------|
| 1 | Alias name format | Must match `^[a-z][a-z0-9-]*$` (lowercase, alphanumeric + hyphens, must start with a letter) | `E_ALIAS_NAME` |
| 2 | Reserved name (dynamic probe) | `${CLAUDE_PLUGIN_ROOT}` must be set; alias name must not collide with any directory under `${CLAUDE_PLUGIN_ROOT}/skills/<alias-name>` OR `${CLAUDE_PLUGIN_ROOT}/.claude/skills/<alias-name>`. See `### Check 2` block below. | `E_PLUGIN_ROOT_UNSET` or `E_SHADOW` |
| 3 | Target name format | Must match `^[a-z][a-z0-9-]*$` (same format as alias names) | `E_TARGET_NAME` |
| 4 | Target skill exists | `test -f "${CLAUDE_PLUGIN_ROOT}/skills/<target>/SKILL.md"`; if missing, also run `ls "${CLAUDE_PLUGIN_ROOT}/skills/"` for discoverability | `E_TARGET_MISSING` |
| 5 | Target is not `alias` | Forbid alias-to-alias recursion | `E_RECURSION` |
| 6 | Collision check | `test -e "$TARGET_DIR"` must be false (uses `-e` not `-d` so a regular file at that path is also caught) | `E_COLLISION` |

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
| `E_COLLISION` | `**ERROR: '$TARGET_DIR/' already exists. Remove it first or choose a different name.**` (interpolate the resolved `$TARGET_DIR` so the operator sees the actual path) |

## Step 3 — Delegate to /implement

### Before delegating, ask

- **What does `/implement` need to build this deterministically?** `/implement` has no codebase context about `/alias` — it will research and guess unless the feature description cites the generator script path, its required flags, the version source, and the write target. The explicit recipe below supplies all four.
- **What could make the Step 4 verification silently pass when it shouldn't?** Nothing — the `verify-skill-called.sh --sentinel-file` gate reads a child-produced artifact at `$TARGET_DIR/SKILL.md` (resolved at Step 2 from the `resolve-target.sh` helper) that the outer orchestrator cannot synthesize. A parent-writable gate would not be load-bearing.
- **Why no retry on `VERIFIED=false`?** Under `--merge` the PR may already be merged by the time control returns; any automated retry would create a divergent PR. Step 4 surfaces branch-specific diagnostic messages instead, leaving recovery to human judgment.

Construct an explicit feature description for `/implement`. The description MUST cite the generator script path, its required flags, the version source, and the write target so `/implement` has a complete, deterministic build recipe — no codebase research required. The write target uses the `$TARGET_DIR` resolved at the top of Step 2 (NOT a hardcoded `.claude/skills/<alias-name>` path — see NEVER #6):

```
Add /<alias-name> alias for /<target-skill> <preset-flags>.

Generate the alias skill by running:
  mkdir -p "$TARGET_DIR"
  "${CLAUDE_PLUGIN_ROOT}/skills/alias/scripts/generate-alias.sh" \
    --name "<alias-name>" \
    --target "<target-skill>" \
    --flags "<preset-flags>" \
    --version "$(jq -r .version "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")" \
    > "$TARGET_DIR/SKILL.md"

If jq fails or plugin.json is malformed, proceed with an empty --version value (the generator handles this — the footer simply omits the vX.Y.Z suffix).
```

When constructing the feature description string, substitute the actual `$TARGET_DIR` value resolved at Step 2 into the recipe so `/implement`'s child run sees a fully-expanded literal path (rather than depending on `$TARGET_DIR` being set in `/implement`'s child environment, which it would not be).

Omit the `<preset-flags>` segment from the leading sentence when empty (pure rename shortcut).

Print: `**Alias /<alias-name> -> /<target-skill> <preset-flags> — target: $TARGET_DIR — delegating to /implement --quick --auto [--merge] [--no-slack]**` (interpolate the resolved `$TARGET_DIR` so the operator sees at a glance which target was selected; omit `<preset-flags>` if empty; omit `--merge` if `alias_merge=false`; omit `--no-slack` if `alias_no_slack=false`).

Invoke the Skill tool:
- Try skill: `"implement"` first (bare name). If no skill matches, try skill: `"larch:implement"` (fully-qualified plugin name).
- args: `"--quick --auto [--merge] [--no-slack] <feature-description>"`

Only include `--merge` in the args if `alias_merge=true`. Only include `--no-slack` in the args if `alias_no_slack=true`.

> **Continue after child returns.** When `/implement` returns, execute Step 4 — do NOT end the turn, and do NOT write a summary, handoff, or "returning to parent" message. See `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` section Anti-halt continuation reminder. **Do NOT load** that reference for routine `/implement` returns — load only when adding a new child-Skill invocation to this file or when debugging a halt symptom.

## Step 4 — Verify

After `/implement` returns, verify the alias SKILL.md actually landed on disk. The sentinel path uses the `$TARGET_DIR` resolved at Step 2 (no separate `git rev-parse` here — the resolved value is the single source of truth, fail-closed at Step 2 if git failed):

```bash
"${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh" \
  --sentinel-file "$TARGET_DIR/SKILL.md"
```

Parse stdout for `VERIFIED=true|false` and `REASON=<token>`.

- **If `VERIFIED=true`**: print `✅ /alias — created $TARGET_DIR/SKILL.md` (interpolate the resolved path) and exit 0.
- **If `VERIFIED=false`**: print a fail-closed error and exit 1. Branch the message on `alias_merge`:
  - **If `alias_merge=false`** (PR created but not merged):
    ```
    **ERROR: /implement returned but $TARGET_DIR/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. Inspect the PR/branch manually — /implement may have written the file elsewhere, skipped the generator, or failed silently.**
    ```
  - **If `alias_merge=true`** (PR may already be merged):
    ```
    **ERROR: /implement returned but $TARGET_DIR/SKILL.md was not written (REASON=<token>). The PR may have already been merged — do not assume success. Inspect the PR/branch/merged-main manually; a revert or follow-up PR may be required.**
    ```
  Do not attempt auto-remediation — `/implement` has already created (and possibly merged) the PR, so any recovery requires human judgment.

### Authoritative exit states

| State | Condition | Printed string (summary) |
|-------|-----------|--------------------------|
| Success | `VERIFIED=true` | `✅ /alias — created $TARGET_DIR/SKILL.md` (interpolated) |
| Validation fail | Any Step 2 check fails | one of the `E_*` strings from the Step 2 `Error strings (reference)` table |
| Verify fail (unmerged) | `VERIFIED=false` AND `alias_merge=false` | `**ERROR: /implement returned but $TARGET_DIR/SKILL.md was not written (REASON=<token>). DO NOT merge the PR. ...**` (full string above) |
| Verify fail (merged) | `VERIFIED=false` AND `alias_merge=true` | `**ERROR: /implement returned but $TARGET_DIR/SKILL.md was not written (REASON=<token>). The PR may have already been merged ...**` (full string above) |
