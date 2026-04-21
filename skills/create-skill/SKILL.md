---
name: create-skill
description: "Use when scaffolding a new larch skill (new SKILL.md). Validates name and description, then delegates to /im --quick --auto which runs render-skill-md.sh and auto-merges. Default: .claude/skills/; --plugin: skills/."
argument-hint: "[--plugin] [--multi-step] [--merge] [--debug] <skill-name> <description>  (--merge is a backward-compat no-op; /im auto-merges)"
allowed-tools: Bash, Skill
---

# Create Skill

Scaffold new larch skill. Delegate to `/im --quick --auto` for full pipeline (implement, review, version bump, PR, auto-merge). `/im` = larch alias for `/implement --merge` — auto-merge now default for scaffolded skills. Pass `--merge` if want explicit (no-op since `/im` already merges).

Example: `/create-skill foo "Use when doing X"` makes `.claude/skills/foo/SKILL.md` in consumer repo. With `--plugin`, makes `skills/foo/SKILL.md` in larch plugin repo.

## Step 1 — Parse Arguments

Call arg parser:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/parse-args.sh $ARGUMENTS
```

Parse output for `NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`. (`MERGE` kept for backward compat — no-op, `/im` always auto-merges.)

If script exits non-zero or emits `ERROR=` line, print error and abort.

## Step 2 — Validate Arguments

Call validator. Include `--plugin` only when `PLUGIN=true`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/validate-args.sh --name "$NAME" --description "$DESCRIPTION" [--plugin]
```

Parse output for `VALID`. If `VALID=false` or exits non-zero, print `ERROR=` message and abort.

Validator enforce:
- Name match `^[a-z][a-z0-9-]*$`, length ≤ 64.
- Name not in reserved-name union: Anthropic reserved + larch static reserved list + plugin skills in `${CLAUDE_PLUGIN_ROOT}/skills` + project-local skills in caller's `.claude/skills/`. Missing dirs = empty. Case-insensitive.
- When `--plugin` set, CWD must be larch plugin repo (`.claude-plugin/plugin.json` + `skills/implement/SKILL.md` present).
- Description non-empty, ≤ 1024 chars, no XML tags, no backticks, no `$(`, no heredoc terminators or frontmatter breakers, no newlines or control chars.

## Design Mindset

Before scaffold, ask:

- **Before pick `--multi-step` vs minimal:** new skill have ≥2 distinct phases each need own `## Step N` heading, or single-call forwarder? One-shot delegators read cleaner as `minimal`; `multi-step` template earn scaffolding only when real sequencing exist.
- **Before pick name:** name graze harness keyword? `validate-args.sh` probe Anthropic/larch-static list + plugin skills + local `.claude/skills/` — but name approximating common verb (`review`, `test`, `run`) or Anthropic-adjacent prefix (`claude-*`) risk ambiguous `Skill` permission match even when static check pass.
- **Before write description:** `description` alone disambiguate skill from every other installed skill harness might surface? In typical agent/skill UI harness match triggers against description first; vague or name-echo description = #1 cause of skill that install but never fire.
- **Before inline prompt logic:** shared script at `${CLAUDE_PLUGIN_ROOT}/scripts/` or skill-private `scripts/` file better home? Mechanical rule A (see Principles) say non-trivial shell logic always belong in `.sh`. Inline Bash in `SKILL.md` = #1 source of copy-paste drift across sibling skills.
- **Before forward to `/im`:** scaffold complete enough to merge, or new skill still need follow-up PR for real logic? `/im` auto-merges — half-scaffolded skill become live trigger moment PR lands.

## Anti-patterns

- **NEVER** write `description:` field starting with skill's name or generic verb (e.g. "Create a skill that…", "foo skill"). **Why**: harness match triggers against description; name-echo description never fire except on skill's own slash command. Start with `Use when…` + real trigger.
- **NEVER** paste full `skill-design-principles.md` into scaffolded `SKILL.md`. **Why**: Section II progressive disclosure — `SKILL.md` = always-loaded body layer; copying principles burn tokens on every invocation. Reference via `MANDATORY — READ ENTIRE FILE` pointer in feature-description handoff instead.
- **NEVER** inline multi-line `bash -c` strings, pipelines, or `for`-loops inside `SKILL.md` Bash-tool calls. **Why**: Mechanical rule B — wrappers centralize error handling, make each step auditable. Inline shell = #1 source of sibling-skill copy-paste drift.
- **NEVER** emit two back-to-back Bash tool calls inside one logical step. **Why**: Mechanical rule C — each Bash call = separate audit artifact; consecutive calls fragment trail and hide partial failures (call 1 succeed, call 2 fail silent, step still look like "made progress").
- **NEVER** invoke `render-skill-md.sh` without completing Steps 1–2 (parse + validate) first — legit path runs through Step 3's `/im` delegation, which calls renderer after validator. **Why**: validator = only guard against reserved-name collisions and heredoc-breaking descriptions — skip it and malformed skill land in target repo before `/im` creates PR impossible to merge cleanly.
- **NEVER** reuse kebab name whose sibling just retired. **Why**: `validate-args.sh` scan `${CLAUDE_PLUGIN_ROOT}/skills/*` at scaffold time but NOT see in-flight PRs or recently-deleted dirs still on origin — double-merge conflict surface only in CI, after PR opened.
- **NEVER** forward `--merge` through `/create-skill` expecting hard gate. **Why**: `/im` already auto-merges; `--merge` on `/create-skill` = no-op kept for backward compat. Treat as load-bearing → surprise when callers omit and merge still happen.
- **NEVER** rewrite Step 3 `/im` feature-description template as freeform prose. **Why**: literal `render-skill-md.sh --name … --description …` invocation shape keep argument binding explicit for `/im` implementing agent — deterministic name/description/target/plugin-token wiring. Freeform prose force agent to reconstruct bindings from narrative, measurably raise risk of silently-wrong scaffold.

## Principles

**MANDATORY — READ ENTIRE FILE** before emit Step 3 `/im` feature description: `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md`. Canonical source of knowledge-delta rule (Section I), progressive-disclosure layering (Section II), larch mechanical rules A/B/C (Section III — overrides Section IV on conflict), writing-style guidance (Sections IV–IX). Section III forwarded as compact excerpt into Step 3 `/im` feature description, but every scaffolded skill must follow full file.

**Do NOT Load** `skill-design-principles.md` when Step 1 parse aborts (`ERROR=` in `parse-args.sh` output) — `NAME`/`DESCRIPTION` not yet defined, principles cannot apply to concrete scaffold. Print error and stop.

**Do NOT Load** `skill-design-principles.md` when Step 2 validation fails (`VALID=false` in `validate-args.sh` output) — skill not written, principles irrelevant to abort message. Print `ERROR=` line and stop.

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

Order match bare-name-then-fully-qualified rule in `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md`.

## Step 3 — Delegate to /im

Build concise feature description for `/im`:

- Target dir (consumer mode): `.claude/skills/<NAME>/`
- Target dir (plugin mode, `--plugin`): `skills/<NAME>/`
- Local path token (consumer mode): working-dir shell variable (consumer-repo root).
- Local path token (plugin mode): `${CLAUDE_PLUGIN_ROOT}`
- Plugin path token (always): `${CLAUDE_PLUGIN_ROOT}`
- Template: `multi-step` if `MULTI_STEP=true`, else `minimal`.

Feature description template (fill placeholders from parsed values):

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

Print: `**Create-skill /<NAME> (<plugin-dev|consumer>, <minimal|multi-step>) — delegating to /im --quick --auto [--debug]**` (omit `--debug` if `false`). `/im` auto-merges; `--merge` on `/create-skill` = backward-compat no-op, not forwarded.

Call Skill tool:
- Try skill: `"im"` first (bare name). If no match, try skill: `"larch:im"` (fully-qualified plugin name).
- args: `"--quick --auto [--debug] <feature-description>"` — include `--debug` only if `DEBUG=true`. `--merge` NOT forwarded (`/im` prepends itself); `MERGE` parse value ignored at delegation time.

Implementing agent execute `render-skill-md.sh`, run validation checks, commit, review, bump version, create PR, merge it (via `/im` → `/implement --merge`).
