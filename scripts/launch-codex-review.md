# launch-codex-review.sh

**Purpose**: Wrap the Codex agent launch pattern (agent-model-args + optional render-specialist-prompt + run-external-agent) into a single script invocation. Eliminates `$(...)` command substitution from SKILL.md Bash blocks that triggered "Contains command_substitution" permission prompts.

**Invariants**:
- Prompt passed only as argv; no `eval`; no unsafe expansion
- No additional stdout/stderr beyond what `run-external-agent.sh` produces
- Uses `exec` to replace shell process with `run-external-agent.sh` (clean exit code passthrough)
- Uses `--output-last-message` for Codex output (no `--capture-stdout`)
- Specialist mode calls `render-specialist-prompt.sh` internally, supporting all flags

**Stdout contract**: Same as `run-external-agent.sh` (sentinel files, `.meta`, `.diag`).

**Flags**: Same as `launch-cursor-review.sh` (see `scripts/launch-cursor-review.md`).

**Call sites**:
- `skills/implement/SKILL.md` Step 5 (quick-mode specialists + generic reviewers)
- `skills/design/SKILL.md` Step 3 (Codex generic reviewer + archetype fallbacks)
- `skills/design/references/sketch-launch.md` (4 regular + 1 quick Codex sketch slots)
- `skills/design/references/dialectic-execution.md` (Codex debater launches)
- `skills/review/SKILL.md` (Codex specialist + generic reviewer)

**Edit-in-sync**: `scripts/agent-model-args.sh`, `scripts/render-specialist-prompt.sh`, `scripts/run-external-agent.sh`. Differs from `launch-cursor-review.sh` in: no `cursor-wrap-prompt.sh` call, no `--capture-stdout`, uses `--output-last-message`.
