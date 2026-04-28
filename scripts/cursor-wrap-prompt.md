# cursor-wrap-prompt.sh

**Purpose**: single source of truth for the Cursor max-mode prompt-level prefix. Wraps a prompt so that Cursor activates max-mode for that invocation regardless of user CLI config.

## Contract

- **Input**: exactly one positional argument — the raw prompt string.
- **Output (stdout)**: <code>&nbsp;/max-mode on. Prompt: &lt;prompt&gt;</code> (leading `U+0020` space intentional, no trailing newline).
- **Exit codes**: `0` on success; `1` if no argument supplied.
- **Implementation**: `printf ' /max-mode on. Prompt: %s'` (not `echo`) so the prompt content passes through literally without re-interpreting backslash escapes.

## Why

Cursor supports `~/.cursor/cli-config.json` for model pinning and max-mode, but that config path is user-managed and cannot be enforced programmatically across contributor environments or CI. The prompt-level `/max-mode on.` slash command is the mechanism larch controls from its own invocations. This wrapper owns the literal so every Cursor invocation goes through one file.

Cursor also has no way to configure a non-default model via config file that overrides the CLI's own fallback; larch passes `--model` on the command line via `scripts/reviewer-model-args.sh`. The two concerns are kept in separate single-source-of-truth files.

## Callers (15 wrapped launch strings in 11 files)

- `skills/research/references/research-phase.md` (3 — standard-mode Cursor lane and deep-mode Cursor slots 1 and 2)
- `skills/research/references/validation-phase.md` (1)
- `skills/research/references/adjudication-phase.md` (1 — Cursor judge launch)
- `skills/design/SKILL.md` (1 — plan-review Cursor reviewer)
- `skills/design/references/sketch-launch.md` (2 — Architecture/Standards and Edge-cases/Failure-modes sketch slots)
- `skills/design/references/dialectic-execution.md` (1 — Cursor debater launch template)
- `skills/shared/voting-protocol.md` (1 — Cursor voter template)
- `skills/shared/dialectic-protocol.md` (1 — Cursor judge template)
- `skills/review/SKILL.md` (2 — diff-mode and slice-mode Cursor reviewer blocks)
- `skills/implement/SKILL.md` (1 — quick-mode Cursor reviewer; block stays inline in SKILL.md per NEVER #6 in that skill)
- `scripts/run-negotiation-round.sh` (1 — Cursor negotiation-round branch)

## Non-callers (intentional exclusions)

- `scripts/check-reviewers.sh` — health probe. The probe's sole purpose is reachability and auth validation; max-mode adds latency and cost without diagnostic value. The two cursor-agent lines in that file (initial probe and retry probe) deliberately pass the probe prompt `"Respond with OK"` verbatim.
- `scripts/run-external-reviewer.sh` header example — illustrative of the wrapper's own tool interface, not a real invocation.

## Edit-in-sync rules

- If the prefix literal changes, update `scripts/cursor-wrap-prompt.sh`, this file, and `scripts/reviewer-model-args.sh`'s `Cursor max-mode:` comment block in the same PR.
- When adding a new Cursor call site, append the file to the callers list above and route through this wrapper.
