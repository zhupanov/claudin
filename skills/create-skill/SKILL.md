---
name: create-skill
description: "Use when scaffolding a new larch skill (new SKILL.md). Validates name and description, then delegates to /im --quick --auto which runs render-skill-md.sh and auto-merges. Default: .claude/skills/; --plugin: skills/."
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

## Design Mindset

Before scaffolding, ask yourself:

- **Before picking `--multi-step` vs minimal:** does the new skill have ≥2 distinct phases that each need their own `## Step N` heading, or is it a single-call forwarder? One-shot delegators read cleaner as `minimal`; the `multi-step` template only earns its scaffolding when there is genuine sequencing.
- **Before choosing a name:** will this name graze a harness keyword? `validate-args.sh` probes the Anthropic/larch-static list + plugin skills + local `.claude/skills/` — but a name that approximates a common verb (`review`, `test`, `run`) or an Anthropic-adjacent prefix (`claude-*`) risks ambiguous `Skill` permission matching even when the static check passes.
- **Before writing the description:** will `description` alone disambiguate this skill from every other installed skill the harness might surface? In typical agent/skill UIs the harness matches triggers against the description first; a vague or name-echo description is the #1 cause of a skill that installs but never fires.
- **Before inlining prompt logic:** would a shared script at `${CLAUDE_PLUGIN_ROOT}/scripts/` or a skill-private `scripts/` file be a better home? Mechanical rule A (see Principles) says non-trivial shell logic always belongs in a `.sh`. Inline Bash in `SKILL.md` is the #1 source of copy-paste drift across sibling skills.
- **Before forwarding to `/im`:** is the scaffold complete enough to merge, or does the new skill still need a follow-up PR to land its real logic? `/im` auto-merges — a half-scaffolded skill becomes a live trigger the moment the PR lands.

## Anti-patterns

- **NEVER** write a `description:` field that starts with the skill's name or a generic verb (e.g. "Create a skill that…", "foo skill"). **Why**: the harness matches triggers against the description; a name-echo description never fires on anything except the skill's own slash command. Start with `Use when…` + the real trigger.
- **NEVER** paste the full `skill-design-principles.md` into the scaffolded `SKILL.md`. **Why**: Section II progressive disclosure — `SKILL.md` is the always-loaded body layer; copying principles burns tokens on every invocation. Reference via a `MANDATORY — READ ENTIRE FILE` pointer in the feature-description handoff instead.
- **NEVER** inline multi-line `bash -c` strings, pipelines, or `for`-loops inside `SKILL.md` Bash-tool calls. **Why**: Mechanical rule B — wrappers centralize error handling and make each step auditable. Inline shell is the #1 source of sibling-skill copy-paste drift.
- **NEVER** emit two back-to-back Bash tool calls inside one logical step. **Why**: Mechanical rule C — each Bash call is a separate audit artifact; consecutive calls fragment the trail and hide partial failures (call 1 succeeds, call 2 fails silently, step still appears to have "made progress").
- **NEVER** invoke `render-skill-md.sh` without completing Steps 1–2 (parse + validate) first — the legitimate path runs through Step 3's `/im` delegation, which calls the renderer after the validator. **Why**: the validator is the only guard against reserved-name collisions and heredoc-breaking descriptions — skipping it lets a malformed skill land in the target repo before `/im` creates a PR that is impossible to merge cleanly.
- **NEVER** reuse a kebab name whose sibling just retired. **Why**: `validate-args.sh` scans `${CLAUDE_PLUGIN_ROOT}/skills/*` at scaffold time but does NOT see in-flight PRs or recently-deleted directories still on origin — the resulting double-merge conflict surfaces only in CI, after the PR has been opened.
- **NEVER** forward `--merge` through `/create-skill` expecting it to be a hard gate. **Why**: `/im` already auto-merges; `--merge` on `/create-skill` is a no-op retained for backward compat. Treating it as load-bearing leads to surprise when callers omit it and merge still happens.
- **NEVER** rewrite the Step 3 `/im` feature-description template as freeform prose. **Why**: the literal `render-skill-md.sh --name … --description …` invocation shape keeps argument binding explicit for the `/im` implementing agent — deterministic name/description/target/plugin-token wiring. Freeform prose forces the agent to reconstruct those bindings from narrative and measurably raises the risk of a silently-wrong scaffold.

## Principles

**MANDATORY — READ ENTIRE FILE** before emitting the Step 3 `/im` feature description: `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md`. It is the canonical source of the knowledge-delta rule (Section I), the progressive-disclosure layering (Section II), the larch mechanical rules A/B/C (Section III — overrides Section IV on conflict), and the writing-style guidance (Sections IV–IX). Section III is forwarded as a compact excerpt into the Step 3 `/im` feature description, but every scaffolded skill must follow the full file.

**Do NOT Load** `skill-design-principles.md` when Step 1 parse aborts (`ERROR=` in `parse-args.sh` output) — `NAME`/`DESCRIPTION` are not yet defined, so the principles cannot be applied to any concrete scaffold. Print the error and stop.

**Do NOT Load** `skill-design-principles.md` when Step 2 validation fails (`VALID=false` in `validate-args.sh` output) — the skill will not be written, so the principles are irrelevant to the abort message. Print the `ERROR=` line and stop.

## Decision Tables

### Path mode

| Scenario | CWD | Flag | `TARGET_DIR` |
|----------|-----|------|--------------|
| Consumer repo adding a project-local skill | any | (default) | `.claude/skills/<NAME>/` |
| larch plugin repo adding a first-class skill | `.claude-plugin/plugin.json` + `skills/implement/SKILL.md` present | `--plugin` | `skills/<NAME>/` |

### Template

| Skill shape | Flag | Scaffold |
|-------------|------|----------|
| Single step — pure delegator or one-shot | (default) | `minimal` |
| Two or more distinct steps with per-step headings | `--multi-step` | `multi-step` |

### Troubleshooting

| Symptom | Most likely cause | Fix |
|---------|-------------------|-----|
| `validate-args.sh` emits `VALID=false` with `ERROR=…is reserved` | Name collides with Anthropic/larch-static list or an existing plugin/local skill | Pick a different name; rerun |
| `validate-args.sh` emits `ERROR=Description contains an XML tag pattern` | Description contains `<…>` (often an angle-bracketed placeholder) | Rephrase without angle brackets |
| `/im` auto-merges but the live skill never fires | Description was name-echo or generic | Edit the landed skill's `description:` to start with `Use when…` |
| `parse-args.sh` emits `ERROR=Unknown argument` | Flag typo (e.g. `--multi_step`) or flag placed after positional args | Use canonical hyphenated flags before positional arguments |
| Scaffold commits but PR cannot merge | Name collision with in-flight PR (not caught by `validate-args.sh`) | Rename locally, rebase, force-push |

### Skill-tool resolution (Step 3)

| Attempt order | Skill name | Condition to fall through |
|---------------|------------|---------------------------|
| 1 | `im` (bare) | No bare match in the harness |
| 2 | `larch:im` (fully-qualified plugin name) | — terminal |

This ordering matches the bare-name-then-fully-qualified rule in `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md`.

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

After scaffolding, run ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/post-scaffold-hints.sh --target-dir "<TARGET_DIR>" --plugin <PLUGIN>. The hints script is the single source of truth for the post-scaffold doc-sync checklist — execute every reminder it emits verbatim (including README Skills catalog row + the README "Strict-permissions consumers — Skill permission entries" subsection pointer, .claude/settings.json dual-form Skill permission entries with `sort -u`, docs/workflow-lifecycle.md orchestration/delegation/standalone updates, docs/agents.md, docs/review-agents.md, AGENTS.md Canonical sources, and any additional lines the hints script prints). Include the hints output verbatim in the PR body under a "Post-scaffold sync checklist" section.

MUST read ${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md (full file) before writing any code. Section III mechanical rules A/B/C below override Section IV writing-style guidance on conflict:
  A. Content and logic live in .sh scripts — shared at ${CLAUDE_PLUGIN_ROOT}/scripts/ when reusable, private at ${CLAUDE_PLUGIN_ROOT}/skills/<NAME>/scripts/ otherwise. Grep existing scripts/ before creating a new one.
  B. No direct Bash-tool commands in SKILL.md — every shell command is a .sh wrapper call; no inline pipelines, loops, or multi-line `bash -c`.
  C. No consecutive Bash-tool calls per step — combine multi-action steps into one coordinator .sh that invokes the individual scripts internally.
```

Print: `**Create-skill /<NAME> (<plugin-dev|consumer>, <minimal|multi-step>) — delegating to /im --quick --auto [--debug]**` (omit `--debug` if `false`). `/im` auto-merges; `--merge` on `/create-skill` is a backward-compat no-op and is not forwarded.

Invoke the Skill tool:
- Try skill: `"im"` first (bare name). If no skill matches, try skill: `"larch:im"` (fully-qualified plugin name).
- args: `"--quick --auto [--debug] <feature-description>"` — include `--debug` only if `DEBUG=true`. `--merge` is NOT forwarded (`/im` prepends it itself); the `MERGE` parse value is ignored at delegation time.

The implementing agent will execute `render-skill-md.sh`, run validation checks, commit, review, bump the version, create the PR, and merge it (via `/im` → `/implement --merge`).
