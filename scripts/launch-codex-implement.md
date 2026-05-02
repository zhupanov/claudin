# launch-codex-implement.sh

**Purpose**: Wrap the Codex agent launch pattern (agent-model-args + run-external-agent) for implementation tasks. Uses `codex exec --full-auto` (`approval: never`, `sandbox: workspace-write`). Parallel to `launch-codex-review.sh` but for write-capable implementation, not read-only review. No specialist prompt rendering, no `--agent-file`, no `--competition-notice`.

**Invariants**:
- Prompt passed only as argv; no `eval`; no unsafe expansion
- No additional stdout/stderr beyond what `run-external-agent.sh` produces
- Uses `exec` to replace shell process with `run-external-agent.sh` (clean exit code passthrough)
- Uses `--output-last-message` for Codex output (no `--capture-stdout`)
- Model/effort defaults come from `agent-model-args.sh` (gpt-5.5, high)

**Stdout contract**: Same as `run-external-agent.sh` (sentinel files, `.meta`, `.diag`).

**Prompt sanitization**: Callers MUST sanitize prompt content before passing to this script. Apply the same redaction rules as execution-issues.md (secrets → `<REDACTED-TOKEN>`, internal URLs → `<INTERNAL-URL>`, PII → `<REDACTED-PII>`). The prompt may flow to external API endpoints.

**Security note**: Unlike `launch-codex-review.sh` (read-only), this script's `--full-auto` mode enables Codex to modify files in the working directory. The Edit/Write PreToolUse hook chain (including `block-submodule-edit.sh`) does NOT cover Codex process writes — callers must perform post-Codex validation (submodule check, path scope, branch state).

**Call sites**:
- `skills/implement/SKILL.md` Step 2 (Codex-delegated implementation)

**Edit-in-sync**: `scripts/agent-model-args.sh`, `scripts/run-external-agent.sh`.
