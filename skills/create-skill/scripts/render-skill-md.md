# render-skill-md.sh contract

`skills/create-skill/scripts/render-skill-md.sh` is the scaffold renderer for the `/create-skill` Step 3 `/im` delegation path. It writes a fresh skill directory with a `SKILL.md` (frontmatter + body scaffold) and a `scripts/.gitkeep` placeholder, atomically. The authoritative developer-facing specification is the in-file header (lines 1–53 of the script) — edits that change the flag list, the YAML escape rules, the body-vs-frontmatter contract, the stdout/stderr channel split, or any of the directory-creation invariants MUST update both the in-file header and this sibling in the same PR per `AGENTS.md § Editing rules`.

## Inputs

### Required flags

- `--name <name>` — Validated skill name (already sanitized by `validate-args.sh` upstream).
- `--description <desc>` — Validated single-line description, used as the YAML frontmatter `description:` field. YAML-escaped via `ESCAPED_DESC` (always double-quoted; backslashes and double-quotes are escaped). Newlines and ASCII control characters are pre-rejected upstream by `validate-args.sh`.
- `--target-dir <absolute-path>` — Absolute path where the new skill directory will live (e.g. `/path/.claude/skills/foo` or `/path/skills/foo`). The path's penultimate component (`/.claude/skills/<name>` or `/skills/<name>`) drives the `SKILL_REL` derivation used for `${LOCAL_TOKEN}/${SKILL_REL}/scripts/` reminders inside the scaffolded body.
- `--local-token <token>` — Literal path token to embed in the generated `SKILL.md` for the new skill's OWN scripts directory: either `$PWD` (consumer mode) or `${CLAUDE_PLUGIN_ROOT}` (plugin-dev mode).
- `--plugin-token <token>` — Literal path token to embed for SHARED larch references — always `${CLAUDE_PLUGIN_ROOT}`.
- `--multi-step true|false` — Selects scaffold variant. `true` emits the multi-step body template (extra Flags / Progress Reporting / multiple Step headings); `false` emits the minimal one-shot delegator body template.

### Optional flags

- `--feature-spec-file <path>` — Path to a file containing the freeform feature spec for the scaffolded skill's body. When provided, the body's opening paragraph is the file's content (raw passthrough — multi-line allowed; **NOT** YAML-escaped — the body is markdown prose, not a YAML scalar). When omitted, the body falls back to `${DESCRIPTION}` for backward compatibility (matches the script's pre-#568 behavior — every existing direct caller continues to work without modification).

## Body-vs-frontmatter contract (#568)

The two slots are deliberately distinct:

- `--description` always feeds the YAML frontmatter `description:` field. It is single-line, validated by `validate-args.sh`, and YAML-escaped via the `ESCAPED_DESC` step (escape backslashes first, then double-quotes; emit always-double-quoted). Length is capped at 1024 chars upstream.
- `--feature-spec-file` (when present) feeds ONLY the body's opening paragraph. The file's bytes are emitted verbatim into an unquoted heredoc — bash parameter expansion is single-pass, so substituted file content is data, NOT re-parsed shell syntax (no nested `${VAR}` / `` ` `` / `$(…)` evaluation). Heredoc terminator scan happens on the literal source code, NOT on substituted parameter values, so a file whose content includes a line literally matching `MULTI_STEP_BODY` or `MINIMAL_BODY` is still safe.
- When `--feature-spec-file` is omitted, `FEATURE_SPEC` defaults to the **raw** (pre-YAML-escape) `$DESCRIPTION` value, NOT `$ESCAPED_DESC`. Routing `$ESCAPED_DESC` to the body would surface visible `\"` and `\\` artifacts in body markdown. This default preserves byte-identical body output relative to the pre-#568 behavior.
- `--feature-spec-file` content is intentionally **NOT** routed through `validate-args.sh`. The body is freeform prose by design — multi-line specs, markdown formatting, and arbitrary unicode are expected. Upstream `prepare-description.sh` F9 has already rejected any spec containing XML tags, backticks, `$(`, or standalone heredoc/frontmatter tokens (`EOF` / `HEREDOC` / `---`) BEFORE the orchestrator forwards the path here. Future maintainers must NOT "fix" the body by re-routing `--feature-spec-file` through `validate-args.sh`; doing so would break the legitimate multi-line spec contract.

## Output channels

Success and failure go to **different streams** — do not conflate them.

- **Stdout** (success path only): exactly one line `RENDERED=<absolute-path-to-SKILL.md>` after the atomic `mv` completes. Exit 0.
- **Stderr** (failure paths): one line `ERROR=<message>`, then exit 1. Failure causes:
  - `ERROR=Unknown argument: <arg>` — argv contains an unrecognized flag.
  - `ERROR=Missing required argument --<flag>` — one of the 5 required flags is empty.
  - `ERROR=Cannot read --feature-spec-file: <path>` — `--feature-spec-file` was provided but the path does not exist or is not readable.
  - `ERROR=Target directory already exists: <path>` — `mkdir` (no `-p`) on the leaf failed (collision or concurrent run).
  - `ERROR=Unable to derive skill-relative path from --target-dir=<path> (...)` — `TARGET_DIR` doesn't contain `/.claude/skills/` or `/skills/`.

The split is intentional: machine consumers grep `RENDERED=` from stdout (single deterministic line); failure diagnostics go to stderr where they don't pollute the success-output channel.

## Behavior invariants

- `mkdir -p` for the parent directory (safe on fresh consumer repos).
- `mkdir` (no `-p`) for the final leaf — fails loudly on collision or concurrent run, surfacing as `ERROR=Target directory already exists: <path>`.
- Atomic write: `<target>/SKILL.md.tmp` first, then `mv` into place. A killed render leaves a `.tmp` artifact, never a half-written `SKILL.md`.
- `scripts/.gitkeep` placeholder created — no skeleton step scripts are scaffolded so the rendered SKILL.md never points at non-existent helper files.
- YAML escape pipeline: `ESCAPED_DESC="${DESCRIPTION//\\/\\\\}"` first (backslash-escape backslashes), then `ESCAPED_DESC="${ESCAPED_DESC//\"/\\\"}"` (backslash-escape double-quotes). Order is load-bearing — reversing it double-escapes the introduced backslashes.

## set -euo pipefail caveat

The script runs under `set -euo pipefail`. The `cat "$FEATURE_SPEC_FILE"` command-substitution in `FEATURE_SPEC="$(cat "$FEATURE_SPEC_FILE")"` strips ALL trailing newlines from the file's content (this is bash command-substitution semantics — not a `cat` quirk). For specs that intentionally end with blank lines, this changes the rendered body relative to the on-disk file's trailing whitespace. This matches today's `${DESCRIPTION}` heredoc semantics (variable values are emitted without their trailing whitespace either way).

## Edit-in-sync rules

When changing this script:

1. Update both the in-file header AND this sibling `.md` together (per `AGENTS.md § Editing rules`).
2. Update the sibling test harness `skills/create-skill/scripts/test-render-skill-md.sh` and its sibling contract `skills/create-skill/scripts/test-render-skill-md.md` to cover the new behavior.
3. Update `skills/create-skill/SKILL.md` Step 3 if the renderer's CLI surface changed (the orchestrator's invocation template must match).
4. Run `make test-render-skill` (or `make lint` for the full lint sweep) to verify all cases pass before committing.

## Test coverage

`scripts/test-render-skill-md.sh` is the regression harness; it is wired into `make lint` via `make test-render-skill` and the broader `test-harnesses` target. The harness covers:

- Both scaffold variants (`--multi-step true` and `--multi-step false`).
- Both target-dir layouts (consumer-mode `.claude/skills/<name>` and plugin-mode `skills/<name>`).
- Frontmatter assertions: `name:` and `description: "..."` lines (exercises the YAML-escape pipeline).
- Body assertions: presence of `## Sub-skill Invocation`, the `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` reference (closes #177's empty-token rooted-path injection guard), the `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` reference (closes #216's canonical-principles surfacing).
- Empty `--plugin-token` rejected with `ERROR=Missing required argument --plugin-token`.
- `--feature-spec-file` cases (closes #568): multi-line file content distinct from `--description` lands in the body's opening paragraph; backward-compat (no `--feature-spec-file`) keeps body content equal to `--description`; missing/unreadable `--feature-spec-file` path produces `ERROR=Cannot read --feature-spec-file: ...` on stderr with exit 1.

Add new test cases there whenever the flag list, frontmatter contract, body-vs-frontmatter contract, or error-message strings change.
