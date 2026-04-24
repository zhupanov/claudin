---
name: compress-skill
description: "Use when compressing an existing skill's prose. Rewrites SKILL.md and all transitively included .md files (excluding sub-skills), applying Strunk & White's Elements of Style adapted for technical writing. Delegates to /imaq so changes ship as a PR."
argument-hint: "[--debug] [--no-slack] <skill-name-or-path>"
allowed-tools: Bash, Skill
---

# compress-skill

Rewrite an existing skill's Markdown prose to reduce size while preserving meaning, grammar, and every structural element. Pure delegator: validates the target, enumerates the transitively-reachable `.md` set inside the skill directory, snapshots baseline sizes, and hands off to `/imaq` (= `/implement --merge --auto --quick`) for branch creation, implementation, code review, PR creation, and auto-merge.

Example: `/compress-skill implement` compresses `skills/implement/SKILL.md` plus every `.md` file reachable from it that resolves inside the `skills/implement/` directory tree.

## Scope

- **In scope**: `.md` files inside the target skill's directory (`SKILL.md`, `references/*.md`, and any `.md` file reachable from `SKILL.md` via either Markdown link syntax `](path.md)` **or** path-shaped backticked references like `` `${CLAUDE_PLUGIN_ROOT}/skills/<name>/references/foo.md` ``, that resolve to a path inside the skill dir). Both forms are followed because larch `SKILL.md` files cite most sibling references via backticks rather than Markdown links.
- **Out of scope**: sub-skills invoked via the `Skill` tool (separate skills — never compressed from here), shared larch files (`skills/shared/*.md`, top-level `*.md` like `AGENTS.md`, `README.md`, `SECURITY.md`), any `.md` reached by a reference whose resolved path is outside the target skill directory.

The directory-tree restriction is the mechanical filter: references to files outside the skill dir are skipped, which naturally excludes shared docs and callee skills.

**Known limitations**:

- Link targets containing unencoded spaces (e.g. `](My File.md)`) are not followed — the regex stops at whitespace. larch `SKILL.md` paths never use spaces, so this does not affect any in-corpus file.
- Reference-style Markdown links (`[text][ref]` + `[ref]: path.md`) are not followed — only inline links `](path.md)` and path-shaped backticked spans are extracted. No larch `SKILL.md` or reference uses this syntax today; if a future skill starts using it, extend `discover-md-set.py` to collect link-definition lines alongside inline links.

## NEVER

1. **NEVER descend into sub-skills invoked via the `Skill` tool.** **Why:** sub-skills are independent compression targets with their own PR histories — pulling them into one refactor produces a PR too large to review. The coordinator enumerates only `.md` files physically under the target skill directory (plus transitive references that resolve inside it).
2. **NEVER run `/compress-skill` on a skill with no `SKILL.md`.** **Why:** the resolver probes the plugin tree (`${CLAUDE_PLUGIN_ROOT}/skills/`), the in-plugin-repo `skills/` layout (for working inside larch itself), and the consumer-repo `.claude/skills/` layout — and fails closed when none contains the target. A missing `SKILL.md` means there is nothing to compress.
3. **NEVER introduce feature or behavior changes during the compression pass.** **Why:** behavior-preserving is the contract; a semantic change disguised as a prose rewrite violates reviewer expectations and destabilizes downstream callers. The feature description pinned for `/implement` names this explicitly.
4. **NEVER target a plugin-namespaced form (e.g., `larch:implement`).** **Why:** the colon is not a valid directory character in the resolver's probed paths; the resolver rejects it. Pass the bare skill name only.
5. **NEVER inline shell logic in this `SKILL.md`.** **Why:** Mechanical rule B — non-trivial shell lives in `.sh` scripts. Keeps this `SKILL.md` scannable; avoids copy-paste drift with `/simplify-skill`, `/alias`, and `/create-skill`.

## Step 1 — Parse Arguments

Parse flags from the start of `$ARGUMENTS` before the first positional token.

- `--debug`: Set `debug_mode=true`. Default: `debug_mode=false`. Forwarded to `/imaq` (and thence to `/implement`).
- `--no-slack`: Set `slack_enabled=false`. Default: `slack_enabled=true`. Forwarded to `/imaq` (and thence to `/implement`) so the delegated run does NOT post a Slack announcement. Default (no `--no-slack`): delegated run posts per `/implement`'s default-on behavior (gated on Slack env vars).

After flag stripping, the next positional token is the **target skill name** (bare form, e.g. `implement`) or an **absolute path** to a skill directory. Strip a leading `/` if present on a bare name. Reject names containing `:` (no plugin-qualified forms — see NEVER #4).

If zero positional tokens remain, print: `**ERROR: Usage: /compress-skill [--debug] [--no-slack] <skill-name-or-path>**` and abort.

## Step 2 — Resolve Target and Build Feature Description

Resolve the target skill directory, enumerate the in-scope `.md` files, snapshot baseline sizes, and compose the feature description for `/implement`. All of this runs in a single coordinator script per mechanical rule C (no consecutive Bash calls). The full stdout contract, exit-code semantics, and resolution order are documented in the sibling contract `${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/build-feature-description.md`.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/compress-skill/scripts/build-feature-description.sh <skill-name-or-path>
```

**Fail-closed verification.** Parse stdout for `STATUS`, `TARGET_DIR`, `SKILL_NAME`, `FILE_COUNT`, and `FEATURE_FILE`, then validate the result before proceeding:

- **`STATUS=ok`** — verify that `FEATURE_FILE` exists and is non-empty; read its contents as `FEATURE_DESCRIPTION`; then remove the temp file with `rm -f "$FEATURE_FILE"` (the caller owns its lifetime — see the sibling contract). Proceed to Step 3. If the file is missing or empty, treat it as a script failure and abort (do NOT `rm` on this failure path).
- **`STATUS=not_found`** — print the `ERROR=<message>` line from stdout and abort.
- **`STATUS=bad_name`** — print the `ERROR=<message>` line from stdout and abort.
- **No `STATUS=` line (script exited non-zero)** — print the error text from stderr and abort.

The coordinator invokes `discover-md-set.sh` internally to BFS the transitive `.md` set from `SKILL.md`, then measures each file's byte and line count for the baseline. The style guide, anti-patterns, and judgment rules are embedded in the feature description so that `/implement`'s Step 2 has them inline.

Print: `✅ 2: resolve — <FILE_COUNT> file(s) under <TARGET_DIR>`

## Step 3 — Delegate to /imaq

Print: `**compress-skill /<SKILL_NAME> — delegating to /imaq [--debug] [--no-slack]**` (omit `--debug` when `debug_mode=false`; omit `--no-slack` when `slack_enabled=true`).

Invoke the Skill tool:
- Try skill: `"imaq"` first (bare name). If no skill matches, try skill: `"larch:imaq"` (fully-qualified plugin name).
- args: `"[--debug] [--no-slack] <FEATURE_DESCRIPTION>"` — prepend `--debug` only if `debug_mode=true`; prepend `--no-slack` only if `slack_enabled=false`. `--merge --auto --quick` are not forwarded (`/imaq` prepends them itself).

The `/imaq` → `/implement --merge --auto --quick` chain runs branch creation, inline plan, implementation (the actual file-by-file prose rewrite), single-reviewer code review loop, `/relevant-checks`, version bump, PR creation with the token-budget delta table in the body, CI wait, and auto-merge. No post-invocation verification is needed at this level — `/implement`'s own internal gates (CI green, merge) are the authoritative signal, and this skill runs no further steps after `/imaq` returns.
