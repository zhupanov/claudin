# External Reviewer Procedures (Codex + Cursor)

Shared mechanical procedures for running Codex and Cursor as external reviewers. Each skill provides its own reviewer invocation commands (prompts, output paths, tmpdir variables) — this file covers the common scaffolding.

## Binary Check (Step 0b)

Run the shared `check-reviewers.sh` script to check for Codex and Cursor binaries:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/larch/check-reviewers.sh
```

Parse the output for `CODEX_AVAILABLE` and `CURSOR_AVAILABLE`.

Set mental flags `codex_available` and `cursor_available` from the script output. For each that is `false`, print a **bold** warning:
- `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- `**⚠ Cursor not available (binary not found). Proceeding without Cursor reviewer.**`

**Note**: If either tool is installed but fails during the actual review (e.g., auth issues, timeout), the failure is handled gracefully — the review proceeds with warnings.

## Monitoring External Reviewers

After launching Codex and/or Cursor as background tasks, **poll for `.done` sentinel files** to detect completion. The wrapper script (`run-external-reviewer.sh`) writes `<output-file>.done` (containing the exit code) when it finishes. Do NOT poll the output files directly — Cursor buffers all stdout until exit, so its output file is empty until the process finishes.

1. Continue working on other tasks (e.g., processing Claude subagent results) while external reviewers run in the background.
2. After all other tasks are done, invoke the wait script with the sentinel file paths for all launched reviewers:
   ```bash
   ${CLAUDE_PLUGIN_ROOT}/scripts/larch/wait-for-reviewers.sh "<cursor-output-file>.done" "<codex-output-file>.done"
   ```
   Only include paths for reviewers that were actually launched. For this `wait-for-reviewers.sh` Bash tool call, use `timeout: 960000` (960 seconds = 960 000 ms) and **do NOT** set `run_in_background: true` — this call must block until all sentinels are found. The script polls every 5 seconds, prints compact dot-based progress to stderr, and outputs machine-parseable `DONE <name>: exit=<code>` or `TIMEOUT <name>` lines to stdout. It always exits 0. **Important**: Invoke the wait script exactly ONCE with ALL sentinel file paths in a SINGLE Bash tool call. Do NOT make multiple Bash calls or write ad-hoc polling loops. If you launched the reviewer with a custom timeout via `run-external-reviewer.sh`, pass the matching value plus 60 seconds grace with `--timeout <seconds>` (seconds) and set the Bash tool `timeout` to the same value in milliseconds.
3. **Do NOT read output files until the corresponding `.done` sentinel file exists.** Reading early will see an empty file (especially for Cursor, whose stdout is fully buffered). Parse the script's stdout `DONE`/`TIMEOUT` lines to determine which reviewers completed.
4. For any reviewer that shows `TIMEOUT` in the script output, print `**⚠ <Reviewer> sentinel file not found after timeout. The wrapper may have been killed externally. Proceeding without <Reviewer> findings.**` and continue without that reviewer.

## Validating External Reviewer Output

**Only after** the corresponding `.done` sentinel file exists, read the output file. The exit code is in the sentinel file (e.g., `cat "<output-file>.done"`). The wrapper script (`run-external-reviewer.sh`) also prints diagnostic lines to its own stdout (captured in the background task output):
- `✓ <tool> review: completed (exit code 0, Xs elapsed, output N bytes)` — success
- `❌ <tool> review: FAILED (exit code N, Xs elapsed, output N bytes)` — failure with details
- `⚠ <tool> review: completed but OUTPUT IS EMPTY` — process succeeded but wrote nothing

**Validation steps:**
1. Read the output file with the Read tool.
2. Check that it is non-empty and looks like a review (contains numbered findings or "NO_ISSUES_FOUND").
3. If the output is empty despite exit code 0, **retry the reviewer once** with a fresh invocation (same prompt, new output file path with `-retry` suffix). Some tools have transient startup failures that resolve on retry.
4. If the output is empty after retry, or if the reviewer exited non-zero, print a detailed warning including the exit code and elapsed time from the wrapper's diagnostic output: `**⚠ <Reviewer> review failed (exit code X, Ys elapsed, 0 bytes output). Proceeding without <Reviewer> findings.**`

## Negotiation Protocol

> **Note**: `/design` and `/review` now use the **Voting Protocol** in `voting-protocol.md` instead of this Negotiation Protocol. This section is retained for skills that still use negotiation: `/loop-review` and `/research`.

> **Variable substitution**: Replace `<skill-tmpdir>` in all paths below with the session tmpdir variable passed by the caller (e.g., `$DESIGN_TMPDIR` or `$REVIEW_TMPDIR`).

> **Parameters**: `max_rounds` (default: 3) — the maximum number of negotiation rounds. Callers may override this (e.g., `/loop-review` uses `max_rounds=1` to keep runtime manageable across multiple slices).

Negotiate with each external reviewer (Codex, Cursor) for up to **`max_rounds` rounds** of back-and-forth:

1. Evaluate each finding. **Accept** it unless it is factually incorrect (references wrong file/line, misunderstands the code) or contradicts a project convention documented in CLAUDE.md.
2. For findings you disagree with, write a response to a negotiation prompt file explaining your reasoning. Use the Write tool if available; if the skill does not allow Write (e.g., `/research`), write the prompt file via the `run-negotiation-round.sh` script's `--prompt-file` argument (the caller must create the file through whatever means the skill permits). The prompt should include the original finding, your counter-argument, and ask the reviewer to either maintain its position with additional justification or withdraw the finding.
   - **Codex**: Write to `<skill-tmpdir>/codex-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-negotiation-round.sh --tool codex --prompt-file "<skill-tmpdir>/codex-negotiation-prompt.txt" --output "<skill-tmpdir>/codex-negotiation-output.txt" --workspace "$PWD"
     ```
   - **Cursor**: Write to `<skill-tmpdir>/cursor-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/larch/run-negotiation-round.sh --tool cursor --prompt-file "<skill-tmpdir>/cursor-negotiation-prompt.txt" --output "<skill-tmpdir>/cursor-negotiation-output.txt" --workspace "$PWD"
     ```
   Use `timeout: 300000` on both Bash tool calls.
3. Repeat up to 3 rounds total. After round 3 (or earlier if all disagreements are resolved), **Claude makes the final call** on any remaining disputes.
