# cursor-wrap-prompt.sh

**Purpose**: single source of truth for the Cursor max-mode prompt-level prefix. Wraps a prompt so that Cursor activates max-mode for that invocation regardless of user CLI config.

## Contract

- **Input**: exactly one positional argument — the raw prompt string.
- **Output (stdout)**: <code>&nbsp;/max-mode on. Prompt: &lt;prompt&gt;</code> (leading `U+0020` space intentional, no trailing newline).
- **Exit codes**: `0` on success; `1` if no argument supplied.
- **Implementation**: `printf ' /max-mode on. Prompt: %s'` (not `echo`) so the prompt content passes through literally without re-interpreting backslash escapes.

## Why

Cursor supports `~/.cursor/cli-config.json` for model pinning and max-mode, but that config path is user-managed and cannot be enforced programmatically across contributor environments or CI. The prompt-level `/max-mode on.` slash command is the mechanism larch controls from its own invocations. This wrapper owns the literal so every Cursor invocation goes through one file.

Cursor also has no way to configure a non-default model via config file that overrides the CLI's own fallback; larch passes `--model` on the command line via `scripts/agent-model-args.sh`. The two concerns are kept in separate single-source-of-truth files.

## Callers (10 wrapped launch strings in 7 files)

- `scripts/launch-cursor-review.sh` (1 — canonical Cursor launch wrapper; all SKILL.md Cursor reviewer/sketch/debater launches now route through this script)
- `skills/research/references/research-phase.md` (3 — standard-mode Cursor lane and deep-mode Cursor slots 1 and 2)
- `skills/research/references/validation-phase.md` (1)
- `skills/research/references/adjudication-phase.md` (1 — Cursor judge launch)
- `skills/shared/voting-protocol.md` (1 — Cursor voter template)
- `skills/shared/dialectic-protocol.md` (1 — Cursor judge template)
- `scripts/run-negotiation-round.sh` (1 — Cursor negotiation-round branch)

**Migrated to `launch-cursor-review.sh`** (no longer direct callers):
- `skills/design/SKILL.md` (was 1 — plan-review Cursor reviewer)
- `skills/design/references/sketch-launch.md` (was 5 — sketch slots)
- `skills/design/references/dialectic-execution.md` (was 1 — debater launch)
- `skills/review/SKILL.md` (was 2 — diff/slice Cursor reviewer blocks)
- `skills/implement/SKILL.md` (was 1 — quick-mode Cursor reviewer)

## Non-callers (intentional exclusions)

- `scripts/check-reviewers.sh` — health probe. The probe's sole purpose is reachability and auth validation; max-mode adds latency and cost without diagnostic value. The two cursor-agent lines in that file (initial probe and retry probe) deliberately pass the probe prompt `"Respond with OK"` verbatim.
- `scripts/run-external-agent.sh` header example — illustrative of the wrapper's own tool interface, not a real invocation.

## Edit-in-sync rules

- If the prefix literal changes, update `scripts/cursor-wrap-prompt.sh`, this file, and `scripts/agent-model-args.sh`'s `Cursor max-mode:` comment block in the same PR.
- When adding a new Cursor call site, append the file to the callers list above and route through this wrapper.
