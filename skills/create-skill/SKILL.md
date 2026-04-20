---
name: create-skill
description: "Use when creating a new larch skill. Validates name and description, then delegates to /im --quick --auto to scaffold via render-skill-md.sh (auto-merges by default). Writes under .claude/skills/ by default; --plugin writes under skills/."
argument-hint: "[--plugin] [--multi-step] [--merge] [--debug] <skill-name> <description>  (--merge is a backward-compat no-op; /im auto-merges)"
allowed-tools: Bash, Skill
---

# Create Skill

Scaffold a new larch-style skill and delegate to `/im --quick --auto` for the full pipeline (implementation, code review, version bump, PR, auto-merge). `/im` is larch's `/implement --merge` alias — auto-merge is now the default for scaffolded skills. Pass `--merge` if you want to be explicit (it is a backward-compat no-op since `/im` already merges).

Example: `/create-skill foo "Use when doing X"` creates `.claude/skills/foo/SKILL.md` in the consumer repo. With `--plugin`, creates `skills/foo/SKILL.md` inside the larch plugin repo.

## Step 1 — Parse Arguments

Invoke the argument parser:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/parse-args.sh $ARGUMENTS
```

Parse the output for `NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`. (`MERGE` is kept in the parse output for backward compat but is a no-op — delegation via `/im` always auto-merges.)

If the script exits non-zero or emits an `ERROR=` line, print the error and abort.

## Step 2 — Validate Arguments

Invoke the validator. Include `--plugin` only when `PLUGIN=true`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/validate-args.sh --name "$NAME" --description "$DESCRIPTION" [--plugin]
```

Parse the output for `VALID`. If `VALID=false` or the script exits non-zero, print the `ERROR=` message and abort.

The validator enforces:
- Name matches `^[a-z][a-z0-9-]*$`, length ≤ 64.
- Name is not in the reserved-name union: Anthropic reserved names + larch's static reserved list + existing plugin skills under `${CLAUDE_PLUGIN_ROOT}/skills` + existing project-local skills under the caller's `.claude/skills/` directory. Missing directories are treated as empty. Comparisons are case-insensitive.
- When `--plugin` is set, the CWD must be the larch plugin repo (`.claude-plugin/plugin.json` + `skills/implement/SKILL.md` present).
- Description is non-empty, ≤ 1024 chars, contains no XML tags, no backticks, no `$(`, no heredoc terminators or frontmatter breakers, no newlines or control characters.

## Principles

Principles for every skill scaffolded by `/create-skill` are documented in `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md`. They still apply to every scaffolded skill and are forwarded verbatim as a compact A/B/C excerpt into the `/im` feature description handed off by Step 3.

## Step 3 — Delegate to /im

Construct a concise feature description for `/im`:

- Target directory (in consumer mode): `.claude/skills/<NAME>/`
- Target directory (plugin mode, `--plugin`): `skills/<NAME>/`
- Local path token (in consumer mode): the working-directory shell variable (the consumer-repo root).
- Local path token (plugin mode): `${CLAUDE_PLUGIN_ROOT}`
- Plugin path token (always): `${CLAUDE_PLUGIN_ROOT}`
- Template: `multi-step` if `MULTI_STEP=true`, else `minimal`.

Feature description template (fill placeholders from the parsed values):

```
Scaffold new skill /<NAME> at <TARGET_DIR>. Description: "<DESCRIPTION>". Path mode: <plugin-dev|consumer>. Template: <minimal|multi-step>.

Use ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/render-skill-md.sh to write the scaffold:
  render-skill-md.sh --name "<NAME>" --description "<DESCRIPTION>" \
    --target-dir "<TARGET_DIR>" \
    --local-token "<LOCAL_TOKEN>" --plugin-token "${CLAUDE_PLUGIN_ROOT}" \
    --multi-step <MULTI_STEP>

After scaffolding, run ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/post-scaffold-hints.sh --target-dir "<TARGET_DIR>" --plugin <PLUGIN>. The hints script is the single source of truth for the post-scaffold doc-sync checklist — execute every reminder it emits (README catalog + feature matrix row, .claude/settings.json dual-form Skill permission entries, docs/workflow-lifecycle.md orchestration-hierarchy / delegation-topology / standalone-usage updates, docs/agents.md and docs/review-agents.md when applicable, AGENTS.md Canonical sources when the new skill introduces a shared script or itself becomes a canonical source). Include the hints output verbatim in the PR body under a "Post-scaffold sync checklist" section.

Implementation principles (MUST follow — sourced from ${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md):
  MUST read ${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md (full file) before writing any code. Larch mechanical rules A/B/C below override any general writing-style guidance from that doc.
  A. Express content and logic as bash scripts. Shared at ${CLAUDE_PLUGIN_ROOT}/scripts/ when reusable across skills; private at ${CLAUDE_PLUGIN_ROOT}/skills/<NAME>/scripts/ when skill-specific. Grep existing scripts/ before creating a new one.
  B. No direct command calls via the Bash tool. Every shell command invoked from the scaffolded SKILL.md must be a call to a .sh wrapper. Do NOT inline pipelines, loops, or multi-line bash -c strings into SKILL.md.
  C. No consecutive Bash tool calls. When a step needs two or more shell actions, combine them into a single coordinator .sh that invokes the individual scripts internally. The scaffolded SKILL.md step should issue exactly one Bash tool call per logical unit of work.

If --plugin, also (these rules are also emitted by post-scaffold-hints.sh — follow its output as canonical):
  - Add a row for /<NAME> to README.md Skills catalog and feature matrix.
  - Add three permission entries to .claude/settings.json permissions.allow, then re-sort the whole permissions.allow block by strict ASCII code-point order (e.g. via `sort -u`) so the new entries interleave correctly with existing ones (do NOT assume the new entries always append; `Skill(larch:<NAME>)` may sort before `Skill(loop-review)`, `Skill(research)`, or `Skill(review)` depending on <NAME>):
      - Bash entry for the new skill's scripts directory (using the working-directory shell variable prefix + skills/<NAME>/scripts/*).
      - Skill(<NAME>) entry (bare name).
      - Skill(larch:<NAME>) entry (fully-qualified plugin name).
  - Rationale: larch's `.claude/settings.json` runs under `defaultMode: "bypassPermissions"` so both Skill forms are cosmetic in the plugin-dev harness, but they document the dual-form convention consumers running in strict permissions must adopt. See the README subsection "Strict-permissions consumers — Skill permission entries" for the consumer-side rationale and the canonical copy-paste block.
  - Add /<NAME> to docs/workflow-lifecycle.md — either to the Skill Orchestration Hierarchy mermaid (if /<NAME> is a stateful orchestrator that invokes other skills) or to the Delegation Topology subsection (if /<NAME> is a pure forwarder/delegator). Also add a Standalone Usage bullet.
  - When applicable (new skill spawns subagents via the Agent tool), update docs/agents.md.
  - When applicable (new skill alters reviewer composition or archetypes), update docs/review-agents.md.
  - When applicable (new skill introduces a shared script used by multiple skills, or is itself a canonical source), add a bullet to AGENTS.md Canonical sources.
```

Print: `**Create-skill /<NAME> (<plugin-dev|consumer>, <minimal|multi-step>) — delegating to /im --quick --auto [--debug]**` (omit `--debug` if `false`). `/im` auto-merges; `--merge` on `/create-skill` is a backward-compat no-op and is not forwarded.

Invoke the Skill tool:
- Try skill: `"im"` first (bare name). If no skill matches, try skill: `"larch:im"` (fully-qualified plugin name).
- args: `"--quick --auto [--debug] <feature-description>"` — include `--debug` only if `DEBUG=true`. `--merge` is NOT forwarded (`/im` prepends it itself); the `MERGE` parse value is ignored at delegation time.

The implementing agent will execute `render-skill-md.sh`, run validation checks, commit, review, bump the version, create the PR, and merge it (via `/im` → `/implement --merge`).
