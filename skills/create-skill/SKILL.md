---
name: create-skill
description: "Use when scaffolding a new larch skill (new SKILL.md). Validates name and description, then delegates to /im --quick --auto which runs render-skill-md.sh and auto-merges. Default: .claude/skills/; --plugin: skills/."
argument-hint: "[--plugin] [--multi-step] [--merge] [--debug] [--no-slack] <skill-name> <description>  (--merge is a backward-compat no-op; /im auto-merges)"
allowed-tools: Bash, Skill, Write
---

# Create Skill

Scaffold a new larch-style skill and delegate to `/im --quick --auto` for the full pipeline (implementation, code review, version bump, PR, auto-merge). `/im` is larch's `/implement --merge` alias — auto-merge is now the default for scaffolded skills. Pass `--merge` to be explicit (a backward-compat no-op since `/im` already merges).

Example: `/create-skill foo "Use when doing X"` creates `.claude/skills/foo/SKILL.md` in the consumer repo. With `--plugin`, creates `skills/foo/SKILL.md` inside the larch plugin repo.

## Step 1 — Parse Arguments

Invoke the argument parser:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/parse-args.sh $ARGUMENTS
```

The full stdout grammar, error contract, positional-argument rules, and edit-in-sync obligations live in the sibling contract at `${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/parse-args.md`.

Parse the output for `NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`, `NO_SLACK`. (`MERGE` is kept in the parse output for backward compat but is a no-op — delegation via `/im` always auto-merges.) `NO_SLACK` is forwarded to `/im` (which forwards to `/implement`) when `true` — suppresses the delegated run's Slack announcement. When `false` (the default), the delegated run posts per `/implement`'s default-on behavior (gated on Slack env vars).

If the script exits non-zero or emits an `ERROR=` line, print the error and abort.

## Step 1.4 — Capture Raw Description to Tmpfile

`parse-args.sh`'s `DESCRIPTION` field is the space-joined remainder reconstructed via `"$*"`. SKILL.md Step 1's invocation passes `$ARGUMENTS` UNQUOTED to `parse-args.sh`, so word-splitting on whitespace can flatten embedded newlines from a multi-line user description before the parser sees them. For the synthesis path to handle the multi-line case from #549 reproducibly, the orchestrator must capture the user's ORIGINAL raw description (the LLM-side view of `$ARGUMENTS` before shell flattening) to a tmpfile.

Use the Write tool to create `$RAW_DESC_FILE` (mktemp under the orchestrator's working tmpdir, e.g. `/tmp/create-skill-raw-desc-<random>.txt`) and write the LLM's view of the raw description portion of `$ARGUMENTS` to it. If the original input was already a clean single-line description (the common case), the file is byte-identical to `$DESCRIPTION` from Step 1. If the original was multi-line, the tmpfile preserves the newlines that `parse-args.sh` may have flattened.

Save the path as `$RAW_DESC_FILE` for the next step.

## Step 1.5 — Validate Raw Description

Invoke the coordinator script. Include `--plugin` only when `PLUGIN=true`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/prepare-description.sh --name "$NAME" --description-file "$RAW_DESC_FILE" [--plugin]
```

Parse the output for `MODE`. The full stdout grammar, synthesis-trigger error literals, F9 pre-synthesis security scan rule, and edit-in-sync obligations live in the sibling contract at `${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/prepare-description.md`.

Branch on `MODE`:

- **`MODE=verbatim`**: read `$RAW_DESC_FILE` content into `$FRONTMATTER_DESCRIPTION` (used by `render-skill-md.sh --description` in Step 3) AND into `$FEATURE_SPEC` (forwarded as the `/im` feature brief in Step 3). Both equal the original raw description on this path. **Skip Step 1.6.** Proceed to Step 2.
- **`MODE=needs-synthesis`**: also parse `REASON` (`newlines-or-control-chars` or `length-exceeds-cap`). Distill a single-line `Use when…` frontmatter from `$RAW_DESC_FILE`'s content (LLM-side reasoning):
  - Extract the imperative kernel of the spec.
  - Prefix with `Use when` followed by a space (lowercase 'when'); cap at one line; ASCII-recommended.
  - MUST NOT contain XML tags, backticks, `$(`, control characters, or any standalone heredoc/frontmatter token (`EOF`, `HEREDOC`, `---`).
  - **Name-echo guard**: the synthesized line MUST NOT start with the lowercased `$NAME`. If it does, generate a SECOND synthesized line. If the second also fails the name-echo guard, abort with `**⚠ Step 1.5 — synthesis loop: name-echo guard rejected both attempts. Aborting.**`
  - Save the accepted synthesized line as `$SYNTHESIZED_LINE`.
  - Capture `$FEATURE_SPEC` from `$RAW_DESC_FILE`'s content NOW (read the file). This binding is final for the rest of the run — Step 1.6 must NOT overwrite `$FEATURE_SPEC`.
  - Proceed to Step 1.6.
- **`MODE=abort`**: print `ERROR` and stop.

## Step 1.6 — Re-validate Synthesized Line

Runs only on the `MODE=needs-synthesis` branch from Step 1.5.

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/prepare-description.sh --name "$NAME" --description "$SYNTHESIZED_LINE" [--plugin]
```

Parse the output for `MODE`. Branch:

- **`MODE=verbatim`**: synthesized line passed validation. Set `$FRONTMATTER_DESCRIPTION = $SYNTHESIZED_LINE`. **`$FEATURE_SPEC` stays as the original raw description** (set in Step 1.5; never overwritten). Print `> Synthesized frontmatter description: $SYNTHESIZED_LINE` so the operator sees what landed in the scaffold. Proceed to Step 2.
- **`MODE=needs-synthesis`** OR **`MODE=abort`**: synthesis failed re-validation (e.g., the LLM's synthesized line introduced a banned token, or somehow still has newlines). Print `**⚠ Step 1.6 — synthesized line failed re-validation: <ERROR>. Aborting.**` and stop. **No further retry.**

### State machine (cap reference)

| Stage | What happens | Bash calls so far |
|---|---|---|
| Step 1.5 | Initial probe via `prepare-description.sh --description-file` | 1 |
| Orchestrator synthesis (LLM-side) | Distill 1 line + name-echo guard. On name-echo violation: 1 retry. Two violations → abort. No Bash call. | 1 (no Bash call) |
| Step 1.6 (only on `MODE=needs-synthesis`) | Re-validate synthesized line via `prepare-description.sh --description` | 2 max |
| Step 1.6 failure (`MODE=abort` or `needs-synthesis`) | Abort with validator's last `ERROR`. No further retry. | 2 (terminal) |

## Step 2 — Validate Arguments

Defense-in-depth re-validation on `$FRONTMATTER_DESCRIPTION` (the validated value from Step 1.5 verbatim path or Step 1.6 synthesized path). Idempotent on both paths — guards against bugs in `prepare-description.sh`. Include `--plugin` only when `PLUGIN=true`:

```bash
${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/validate-args.sh --name "$NAME" --description "$FRONTMATTER_DESCRIPTION" [--plugin]
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
- **Before writing the description:** are you giving a one-line *frontmatter trigger* or a *feature spec*? They are TWO DISTINCT CONCEPTS in `/create-skill`. The frontmatter `description:` is a single-line YAML field used by the harness for trigger matching; the feature spec is the freeform brief forwarded to `/im` describing what the new skill should do. If your input is a multi-line spec or exceeds 1024 chars (with no other anti-patterns), Step 1.5 will trigger LLM-side synthesis: you'll see the synthesized one-liner echoed before delegation, and the original spec will reach `/im` as the feature brief. If your input is a single-line `Use when…` trigger, both the frontmatter and the feature brief will use it verbatim. Mixed inputs (multi-line spec containing XML tags / backticks / `$(` / heredoc tokens) will abort cleanly via the Step 1.5 pre-synthesis security scan rather than synthesizing around banned content.
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
- **NEVER** synthesize a frontmatter description for any validator failure other than the synthesis-trigger classes (`Description contains newlines or control characters` or `Description length (...) exceeds 1024 characters`). **Why**: synthesis on XML-tag / backtick / `$(` / heredoc-token / name-related failures would silently launder banned content into an opaque paraphrase, replacing an explicit, evidenced refusal in `validate-args.sh` with an LLM guess. Step 1.5's pre-synthesis security scan additionally aborts when a synthesis-trigger class co-occurs with any banned-token class — preserving every existing safety guarantee. Narrow gating + mixed-input scan are non-negotiable.
- **NEVER** reference `$DESCRIPTION` (the raw remainder from Step 1) downstream of Step 1.5. **Why**: after Step 1.5 the orchestrator carries TWO distinct values — `$FRONTMATTER_DESCRIPTION` (validated single-line, fed to `render-skill-md.sh --description`) and `$FEATURE_SPEC` (original raw, forwarded as the `/im` feature brief). On the synthesis path these are different content; falling back to `$DESCRIPTION` silently routes raw input to either the renderer or the validator and breaks the two-concept contract.
- **NEVER** overwrite `$FEATURE_SPEC` from Step 1.6's `prepare-description.sh` output. **Why**: Step 1.6 receives the synthesized one-liner as `--description`; on `MODE=verbatim` (synthesized line passes), the script's classification only confirms validity — it does not redefine `$FEATURE_SPEC`. The orchestrator captured `$FEATURE_SPEC` from the original raw description in Step 1.5 (`MODE=needs-synthesis` branch) before invoking Step 1.6, and that binding is final. Overwriting from Step 1.6 would route the synthesized one-liner to `/im`'s feature brief and lose the operator's full feature spec.

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
- Feature-spec file path: `<RAW_DESC_FILE_PATH>` is the **resolved absolute path** of `$RAW_DESC_FILE` (e.g. `/tmp/create-skill-raw-desc-XXXXXX.txt`) captured at Step 1.4 — substitute the actual filesystem path here, NOT the literal variable name `$RAW_DESC_FILE`. The renderer's `--feature-spec-file` flag (#568) reads this file's content (raw passthrough — multi-line preserved) and emits it as the body's opening paragraph. Without this substitution, the implementing agent would invoke `render-skill-md.sh --feature-spec-file "$RAW_DESC_FILE"` literally and the file-existence check would fail with `ERROR=Cannot read --feature-spec-file: $RAW_DESC_FILE`.

Feature description template (fill placeholders from the parsed values; note `<FRONTMATTER_DESCRIPTION>` is the validated single-line frontmatter from Step 1.5/1.6 and `<FEATURE_SPEC>` is the original raw description carried as a feature brief — these are TWO DISTINCT slots):

```
Scaffold new skill /<NAME> at <TARGET_DIR>. Frontmatter description: "<FRONTMATTER_DESCRIPTION>". Path mode: <plugin-dev|consumer>. Template: <minimal|multi-step>.

Feature spec for the new skill (verbatim user input — multi-line allowed):
<FEATURE_SPEC>

Use ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/render-skill-md.sh to write the scaffold:
  render-skill-md.sh --name "<NAME>" --description "<FRONTMATTER_DESCRIPTION>" \
    --target-dir "<TARGET_DIR>" \
    --local-token "<LOCAL_TOKEN>" --plugin-token "${CLAUDE_PLUGIN_ROOT}" \
    --multi-step <MULTI_STEP> \
    --feature-spec-file "<RAW_DESC_FILE_PATH>"

After scaffolding, run ${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/post-scaffold-hints.sh --target-dir "<TARGET_DIR>" --plugin <PLUGIN>. The hints script is the single source of truth for the post-scaffold doc-sync checklist — execute every reminder it emits verbatim (including README Skills catalog row + the docs/configuration-and-permissions.md "Strict-permissions consumers — Skill permission entries" subsection pointer, .claude/settings.json dual-form Skill permission entries with `sort -u`, docs/workflow-lifecycle.md orchestration/delegation/standalone updates, docs/agents.md, docs/review-agents.md, AGENTS.md Canonical sources, and any additional lines the hints script prints). Include the hints output verbatim in the PR body under a "Post-scaffold sync checklist" section.

The renderer mechanically scaffolds the body from `--feature-spec-file`'s content (the raw `<FEATURE_SPEC>` written to `<RAW_DESC_FILE_PATH>` at Step 1.4); use <FRONTMATTER_DESCRIPTION> ONLY for the YAML frontmatter `description:` field via `render-skill-md.sh --description`. On the verbatim path the two slots carry the same string; on the synthesis path <FRONTMATTER_DESCRIPTION> is a one-line `Use when…` distillation of <FEATURE_SPEC>, both validated. The implementing agent then evolves the scaffolded body into the real skill — the renderer-provided opening paragraph is a starting point, not the final body.

The full CLI grammar, body-vs-frontmatter contract, output-channel split (`RENDERED=` on stdout / `ERROR=` on stderr), backward-compat semantics, and edit-in-sync rules for `render-skill-md.sh` live in the sibling contract at `${CLAUDE_PLUGIN_ROOT}/skills/create-skill/scripts/render-skill-md.md`.

MUST read ${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md (full file) before writing any code. Section III mechanical rules A/B/C below override Section IV writing-style guidance on conflict:
  A. Content and logic live in .sh scripts — shared at ${CLAUDE_PLUGIN_ROOT}/scripts/ when reusable, private at ${CLAUDE_PLUGIN_ROOT}/skills/<NAME>/scripts/ otherwise. Grep existing scripts/ before creating a new one.
  B. No direct Bash-tool commands in SKILL.md — every shell command is a .sh wrapper call; no inline pipelines, loops, or multi-line `bash -c`.
  C. No consecutive Bash-tool calls per step — combine multi-action steps into one coordinator .sh that invokes the individual scripts internally.
```

Print: `**Create-skill /<NAME> (<plugin-dev|consumer>, <minimal|multi-step>) — delegating to /im --quick --auto [--debug] [--no-slack]**` (omit each optional flag if its corresponding variable is `false`). `/im` auto-merges; `--merge` on `/create-skill` is a backward-compat no-op and is not forwarded.

Invoke the Skill tool:
- Try skill: `"im"` first (bare name). If no skill matches, try skill: `"larch:im"` (fully-qualified plugin name).
- args: `"--quick --auto [--debug] [--no-slack] <feature-description>"` — include `--debug` only if `DEBUG=true`; include `--no-slack` only if `NO_SLACK=true`. `--merge` is NOT forwarded (`/im` prepends it itself); the `MERGE` parse value is ignored at delegation time.

The implementing agent will execute `render-skill-md.sh`, run validation checks, commit, review, bump the version, create the PR, and merge it (via `/im` → `/implement --merge`).
