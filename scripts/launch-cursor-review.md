# launch-cursor-review.sh

**Purpose**: Wrap the Cursor agent launch pattern (agent-model-args + cursor-wrap-prompt + optional render-specialist-prompt + run-external-agent) into a single script invocation. Eliminates `$(...)` command substitution from SKILL.md Bash blocks that triggered "Contains command_substitution" permission prompts.

**Invariants**:
- Prompt passed only as argv; no `eval`; no unsafe expansion
- No additional stdout/stderr beyond what `run-external-agent.sh` produces
- Uses `exec` to replace shell process with `run-external-agent.sh` (clean exit code passthrough)
- Specialist mode calls `render-specialist-prompt.sh` internally, supporting all flags

**Stdout contract**: Same as `run-external-agent.sh` (sentinel files, `.meta`, `.diag`).

**Flags**:
- `--output FILE` — (required) output file path
- `--timeout SECS` — (required) timeout in seconds
- `--prompt TEXT` — generic mode prompt text (mutually exclusive with `--agent-file`)
- `--agent-file FILE` — specialist mode agent definition file
- `--mode diff|description` — specialist review mode (requires `--agent-file`)
- `--description-text TEXT` — review target description (required when `--mode=description`)
- `--scope-files PATH` — canonical scope files list (required when `--mode=description`)
- `--competition-notice` — append competition notice to specialist prompt

**Call sites**:
- `skills/implement/SKILL.md` Step 5 (quick-mode specialists + generic reviewers)
- `skills/design/SKILL.md` Step 3 (4 Cursor archetype reviewers)
- `skills/design/references/sketch-launch.md` (4 regular + 1 quick Cursor sketch slots)
- `skills/design/references/dialectic-execution.md` (Cursor debater launches)
- `skills/review/SKILL.md` (Cursor specialist + generic reviewer)

**Edit-in-sync**: `scripts/agent-model-args.sh`, `scripts/cursor-wrap-prompt.sh`, `scripts/render-specialist-prompt.sh`, `scripts/run-external-agent.sh`. Update `scripts/cursor-wrap-prompt.md` callers registry when adding/removing call sites.
