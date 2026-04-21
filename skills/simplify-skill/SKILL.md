---
name: simplify-skill
description: "Use when refactoring a larch skill to improve adherence to skill-design principles and reduce SKILL.md footprint. Partitions large files into references/*.md. Excludes sub-skills invoked via Skill tool. Behavior-preserving; delegates to /implement."
argument-hint: "[--debug] <skill-name>"
allowed-tools: Bash, Skill
---

# Simplify Skill

Refactor an existing larch skill for stronger adherence to the principles in `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` and to reduce SKILL.md token footprint. Pure delegator: validates the target, builds a deterministic feature description, and hands off to `/im` (= `/implement --merge`) for design, implementation, review, version bump, PR, and auto-merge.

Example: `/simplify-skill implement` refactors `skills/implement/SKILL.md` and every `.md` it transitively includes (excluding skills it invokes via the `Skill` tool).

## NEVER

1. **NEVER descend into sub-skills invoked via the `Skill` tool.** **Why:** sub-skills are independent refactor targets with their own harnesses and PR histories — pulling them into one refactor produces a PR too large to review and creates cross-skill coupling. Enforced at enumeration time by the helper script: only `MANDATORY — READ ENTIRE FILE` pointers and explicit `references/*.md` citations are followed.
2. **NEVER run `/simplify-skill` on a skill with no `SKILL.md`.** **Why:** the resolver probes both the plugin tree and the consumer-repo `.claude/skills/` and fails closed when neither exists — a missing SKILL.md means there is nothing to refactor.
3. **NEVER introduce feature changes during the refactor.** **Why:** behavior-preserving is the contract; a feature change disguised as a refactor violates reviewer expectations and destabilizes the target skill's CI footprint. The feature description pinned for `/implement` names this explicitly.
4. **NEVER inline the feature description inside the `SKILL.md` body.** **Why:** Mechanical rule B — shell logic (and the enumeration + feature-prose assembly) lives in a `.sh`. Keeps this SKILL.md scannable; avoids copy-paste drift with `/alias` and `/create-skill`.
5. **NEVER target a skill name that is actually a plugin-namespaced form (e.g., `larch:implement`).** **Why:** the colon is not a valid directory character in the resolver's probed paths; the resolver rejects it. Pass the bare skill name only.

## Step 1 — Parse Arguments

Parse flags from the start of `$ARGUMENTS` before the first positional token.

- `--debug`: Set `debug_mode=true`. Default: `debug_mode=false`. Forwarded to `/im` (and thence to `/implement` → `/design` and `/review`).

After flag stripping, the next positional token is the **target skill name** — bare form (`implement`) or slash-prefixed (`/implement`). Strip a leading `/` if present. Reject names containing `:` (no plugin-qualified forms — see NEVER #5) or non-`[a-z0-9-]` characters.

If zero positional tokens remain, print: `**ERROR: Usage: /simplify-skill [--debug] <skill-name>**` and abort.

## Step 2 — Validate Target and Build Feature Description

Resolve the target skill directory, enumerate its in-scope `.md` files, and compose the feature description for `/implement`. All of this runs in a single helper script per mechanical rule C (no consecutive Bash calls):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/simplify-skill/scripts/build-feature-description.sh --name "<skill-name>"
```

Parse stdout for `STATUS`, `TARGET_SKILL_MD`, `TARGET_DIR`, `INCLUDED_FILES`, and `FEATURE_FILE`:

- **`STATUS=ok`** — `FEATURE_FILE` is an absolute path to a temp file containing the full feature description. Read the file's contents as `FEATURE_DESCRIPTION` and proceed to Step 3.
- **`STATUS=not_found`** — print the `ERROR=<message>` line from stdout and abort.
- **`STATUS=bad_name`** — print the `ERROR=<message>` line from stdout and abort.

The helper enforces NEVER #1 (sub-skills not enumerated), NEVER #2 (missing SKILL.md → fail closed), and NEVER #5 (reject `:` in name). It does NOT enforce NEVER #3 — that contract lives inside the feature description passed to `/implement`.

## Step 3 — Delegate to /im

Print: `**Simplify-skill /<skill-name> — delegating to /im [--debug]**` (omit `--debug` if `debug_mode=false`).

Invoke the Skill tool:
- Try skill: `"im"` first (bare name). If no skill matches, try skill: `"larch:im"` (fully-qualified plugin name).
- args: `"[--debug] <FEATURE_DESCRIPTION>"` — prepend `--debug` only if `debug_mode=true`. `--merge` is not forwarded (`/im` prepends it itself).

The `/im` → `/implement --merge` chain runs design, implementation, code review, `/relevant-checks`, version bump, PR creation, CI monitoring, and auto-merge. No post-invocation verification is needed at this level — `/implement`'s own internal gates (rebase + re-bump, CI green, merge) are the authoritative signal, and this skill runs no further steps after `/im` returns.
