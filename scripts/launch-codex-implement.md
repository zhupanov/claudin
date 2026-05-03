# launch-codex-implement.sh

**Purpose**: Spawn the Codex implementer subprocess for `/implement` Step 2 with a tight, machine-parseable stdout contract. Wraps `run-external-agent.sh` + `codex exec --full-auto` (parallel to `launch-codex-review.sh`) but redirects the wrapper's human-readable progress lines (⏳, ✓, ❌) to a sidecar log file so the dispatcher (`skills/implement/scripts/step2-implement.sh`) only sees deterministic `KEY=VALUE` lines.

**Invariants**:
- Stdout contract is `KEY=VALUE` lines only — `LAUNCHER_EXIT`, `MANIFEST_WRITTEN`, `QA_PENDING_WRITTEN`, `TRANSCRIPT`, `SIDECAR_LOG`. The dispatcher relies on this; any progress text leaking to stdout would be parsed as garbage.
- `run-external-agent.sh`'s stdout AND stderr are redirected (`>"$SIDECAR_LOG" 2>&1`) inside the wrapper. Operators inspecting a failed run read the sidecar log to see what went wrong.
- Codex's full transcript (the `--output-last-message` payload) lands at `--transcript-path`. This file may grow large; it is intentionally NOT echoed to stdout.
- Wrapper always exits 0 unless flag validation fails (exit 2). The Codex subprocess's exit code is reported via `LAUNCHER_EXIT=<int>` on stdout; the dispatcher decides whether that constitutes failure.
- Composes Codex's prompt by concatenating `--agent-prompt` (system-prompt body, `agents/codex-implementer.md`) with this-invocation parameters and an optional resume block. Composition is in shell, not in agent-side prose, so the contract is mechanically inspectable.
- Reuses `agent-model-args.sh --tool codex --with-effort` exactly as `launch-codex-review.sh` does — this implementer benefits from max reasoning effort.

**Stdout contract**:
```
LAUNCHER_EXIT=<int>            # exit code from run-external-agent.sh
MANIFEST_WRITTEN=<true|false>  # whether $MANIFEST_PATH exists and is non-empty
QA_PENDING_WRITTEN=<true|false># whether $QA_PENDING_PATH exists and is non-empty
TRANSCRIPT=<path>              # path to Codex's --output-last-message file
SIDECAR_LOG=<path>             # path to run-external-agent.sh chatter
```

**Flags**:

| Flag | Required | Purpose |
|------|----------|---------|
| `--transcript-path PATH` | yes | Where Codex's `--output-last-message` is written |
| `--sidecar-log PATH` | yes | Where wrapper progress chatter is captured |
| `--manifest-path PATH` | yes | Where Codex MUST atomic-write `manifest.json` |
| `--qa-pending-path PATH` | yes | Where Codex atomic-writes `qa-pending.json` on `needs_qa` |
| `--plan-file PATH` | yes | Plan to implement (read by Codex) |
| `--feature-file PATH` | yes | Original feature description (read by Codex) |
| `--agent-prompt PATH` | yes | `agents/codex-implementer.md` system prompt body |
| `--timeout SECS` | yes | Wall-clock cap for Codex subprocess |
| `--answers-file PATH` | optional | Operator answers from a prior `needs_qa` cycle (resume) |

**Call sites**:
- `skills/implement/scripts/step2-implement.sh` (dispatcher) — the only authorized caller.

**Edit-in-sync**: `scripts/run-external-agent.sh`, `scripts/agent-model-args.sh`, `agents/codex-implementer.md`, `skills/implement/references/codex-manifest-schema.md`. Differs from `launch-codex-review.sh` in: (a) progress chatter redirected to sidecar log; (b) prompt composition in shell (review launcher passes prompt as a single argv string).

**Test harness**: this launcher has no dedicated harness today. `skills/implement/scripts/test-step2-dispatch.sh` exercises only the dispatcher branches that do NOT call this launcher (claude_fallback, argument validation, resume-cap bail). Manual / end-to-end testing is the current coverage path for the launcher's `KEY=VALUE` envelope, sidecar-log redirection, and prompt composition. See `skills/implement/scripts/test-step2-dispatch.md` for the dispatcher harness's documented coverage gaps.

**Makefile wiring**: indirectly exercised by `make test-step2-dispatch` (the dispatcher harness).
