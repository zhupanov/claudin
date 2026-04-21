# External Reviewer Procedures (Codex + Cursor)

Shared mechanical procedures for running Codex and Cursor as external reviewers. Each skill provides its own reviewer invocation commands (prompts, output paths, tmpdir variables) — this file covers the common scaffolding.

## Binary Check and Health Probe (Step 0)

The binary check, health probe, and health status file write are now handled by `session-setup.sh` with the `--check-reviewers` flag. Skills call a single script in Step 0:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix <name> [--skip-preflight] [--skip-branch-check] \
  [--skip-slack-check] [--skip-repo-check] --check-reviewers [--caller-env <path>] \
  [--skip-codex-probe] [--skip-cursor-probe] [--write-health <path>]
```

The `--check-reviewers` flag runs `check-reviewers.sh --probe` internally and emits `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY` on stdout.

**Session-env override**: If `--caller-env` provides `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, the script auto-sets the corresponding `--skip-codex-probe` / `--skip-cursor-probe` flag internally — you do not need to pass these explicitly when using `--caller-env`.

Set mental flags `codex_available` and `cursor_available` based on the output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed: <CODEX_PROBE_ERROR>). Using Claude replacement.**` where `<CODEX_PROBE_ERROR>` is the `CODEX_PROBE_ERROR` value from `session-setup.sh` output (if available; omit the parenthetical detail if not present).
- Else: `codex_available=true`
- Same logic for Cursor (using `CURSOR_PROBE_ERROR`).

**Note**: `*_AVAILABLE` is a pure install-state signal (binary exists on PATH). `*_HEALTHY` indicates whether the tool actually responded to a trivial prompt within the 60-second probe timeout. Callers must combine both to determine runtime usability.

## Runtime Timeout Fallback

When processing reviewer results (after `wait-for-reviewers.sh` returns), check each reviewer's sentinel file exit code and output validity. If any of the following are true for a reviewer, set the corresponding `*_available` mental flag to `false` for **all subsequent steps in this session**:

- Sentinel exit code is `124` (timeout — the common case when `run-external-reviewer.sh` enforces its timeout)
- Sentinel exit code is non-zero (any other failure)
- Output is empty/invalid after the retry-once procedure (per "Validating External Reviewer Output" below)
- `wait-for-reviewers.sh` reports `TIMEOUT` for the reviewer (sentinel never appeared — wrapper killed externally)

Print: `**⚠ <Reviewer> failed — <FAILURE_REASON>. Using Claude replacement for remainder of session.**`

Where `<FAILURE_REASON>` is the `FAILURE_REASON` value from `collect-reviewer-results.sh` output (or from the `.diag` file if collecting results manually). Always include the reason so the user can diagnose the root cause (e.g., timeout duration, exit code, last error output).

This is a mental flag flip within the current skill invocation. For cross-skill propagation within `/implement`, child skills write a structured health status file — see the `/implement` SKILL.md for details.

**Note**: Once a reviewer is marked unhealthy during a session, it stays unhealthy for the remainder of that session. This is intentional — it prevents oscillation and wasted time on flaky tools during extended outages.

## Collecting External Reviewer Results

After launching Codex and/or Cursor as background tasks (via `run-external-reviewer.sh` with `run_in_background: true`), continue working on other tasks (e.g., processing Claude subagent results) while external reviewers run.

After all other tasks are done, collect and validate external reviewer outputs using the shared collection script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout <seconds> [--write-health <path>] <output-file> [<output-file> ...]
```

Only include output file paths for reviewers that were actually launched. For the Bash tool call, use `timeout: <seconds>000` (milliseconds) and **do NOT** set `run_in_background: true` — this call must block. The script internally calls `wait-for-reviewers.sh` to poll for `.done` sentinel files, validates each output, and retries once on empty output (using `.meta` files written by `run-external-reviewer.sh`).

**Output**: The script emits structured `KEY=value` blocks on stdout (one block per reviewer, separated by blank lines):
```
REVIEWER_FILE=<output-path>
TOOL=<codex|cursor|unknown>
STATUS=<OK|TIMED_OUT|FAILED|EMPTY_OUTPUT|SENTINEL_TIMEOUT>
EXIT_CODE=<N>
HEALTHY=<true|false>
FAILURE_REASON=<explanation>
```

Parse each reviewer's `STATUS`, `REVIEWER_FILE`, and `FAILURE_REASON`:
- `STATUS=OK`: Read the output file — it is non-empty and validated. `FAILURE_REASON` is empty.
- Any other status: The reviewer failed. `FAILURE_REASON` explains why (e.g., "Timed out after 1800s (limit: 1800s). Process was killed after exceeding the timeout." or "Failed with exit code 1 after 5s. Last output: error message here"). Follow the **Runtime Timeout Fallback** procedure above, including `FAILURE_REASON` in the message.

**Important**: Do NOT read output files before calling `collect-reviewer-results.sh`. Cursor buffers all stdout until exit — its output file is empty until the process finishes. The collection script handles all sentinel polling and validation internally.

## Negotiation Protocol

> **Note**: `/design` and `/review` now use the **Voting Protocol** in `voting-protocol.md` instead of this Negotiation Protocol. This section is retained for skills that still use negotiation: `/loop-review` and `/research`.

> **Variable substitution**: Replace `<skill-tmpdir>` in all paths below with the session tmpdir variable passed by the caller (e.g., `$DESIGN_TMPDIR` or `$REVIEW_TMPDIR`).

> **Parameters**: `max_rounds` (default: 3) — the maximum number of negotiation rounds. Callers may override this (e.g., `/loop-review` uses `max_rounds=1` to keep runtime manageable across multiple slices).

Negotiate with each external reviewer (Codex, Cursor) for up to **`max_rounds` rounds** of back-and-forth:

1. Evaluate each finding. **Accept** it unless it is factually incorrect (references wrong file/line, misunderstands the code) or contradicts a project convention documented in CLAUDE.md.
2. For findings you disagree with, write a response to a negotiation prompt file explaining your reasoning. Use the Write tool if available; if the skill does not allow Write (e.g., `/research`), write the prompt file via the `run-negotiation-round.sh` script's `--prompt-file` argument (the caller must create the file through whatever means the skill permits). The prompt should include the original finding, your counter-argument, and ask the reviewer to either maintain its position with additional justification or withdraw the finding.
   - **Codex**: Write to `<skill-tmpdir>/codex-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-negotiation-round.sh --tool codex --prompt-file "<skill-tmpdir>/codex-negotiation-prompt.txt" --output "<skill-tmpdir>/codex-negotiation-output.txt" --workspace "$PWD"
     ```
   - **Cursor**: Write to `<skill-tmpdir>/cursor-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-negotiation-round.sh --tool cursor --prompt-file "<skill-tmpdir>/cursor-negotiation-prompt.txt" --output "<skill-tmpdir>/cursor-negotiation-output.txt" --workspace "$PWD"
     ```
   Use `timeout: 300000` on both Bash tool calls.
3. Repeat up to 3 rounds total. After round 3 (or earlier if all disagreements are resolved), **Claude makes the final call** on any remaining disputes.
