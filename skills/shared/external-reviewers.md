# External Reviewer Procedures (Codex + Cursor)

Shared mechanical procedures for running Codex and Cursor as external reviewers. Each skill give own reviewer invocation commands (prompts, output paths, tmpdir vars) — this file cover common scaffolding.

## Binary Check and Health Probe (Step 0)

Binary check, health probe, health status file write now handled by `session-setup.sh` with `--check-reviewers` flag. Skills call one script in Step 0:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/session-setup.sh --prefix <name> [--skip-preflight] [--skip-branch-check] \
  [--skip-slack-check] [--skip-repo-check] --check-reviewers [--caller-env <path>] \
  [--skip-codex-probe] [--skip-cursor-probe] [--write-health <path>]
```

`--check-reviewers` flag run `check-reviewers.sh --probe` inside, emit `CODEX_AVAILABLE`, `CURSOR_AVAILABLE`, `CODEX_HEALTHY`, `CURSOR_HEALTHY` on stdout.

**Session-env override**: If `--caller-env` give `CODEX_HEALTHY=false` or `CURSOR_HEALTHY=false`, script auto-set matching `--skip-codex-probe` / `--skip-cursor-probe` flag inside — no need pass explicit when use `--caller-env`.

Set mental flags `codex_available` and `cursor_available` from output:
- If `CODEX_AVAILABLE=false`: `codex_available=false`. Print: `**⚠ Codex not available (binary not found). Proceeding without Codex reviewer.**`
- Else if `CODEX_HEALTHY=false`: `codex_available=false`. Print: `**⚠ Codex installed but not responding (health check failed: <CODEX_PROBE_ERROR>). Using Claude replacement.**` where `<CODEX_PROBE_ERROR>` is `CODEX_PROBE_ERROR` value from `session-setup.sh` output (if present; drop parenthetical if absent).
- Else: `codex_available=true`
- Same for Cursor (use `CURSOR_PROBE_ERROR`).

**Note**: `*_AVAILABLE` pure install-state signal (binary exist on PATH). `*_HEALTHY` say if tool actually respond to trivial prompt inside 60-second probe timeout. Callers must combine both for runtime usability.

## Runtime Timeout Fallback

When process reviewer results (after `wait-for-reviewers.sh` return), check each reviewer sentinel file exit code and output validity. If any true for reviewer, set matching `*_available` mental flag to `false` for **all later steps in session**:

- Sentinel exit code `124` (timeout — common case when `run-external-reviewer.sh` enforce timeout)
- Sentinel exit code non-zero (any other fail)
- Output empty/invalid after retry-once procedure (see "Validating External Reviewer Output" below)
- `wait-for-reviewers.sh` report `TIMEOUT` for reviewer (sentinel never show — wrapper killed outside)

Print: `**⚠ <Reviewer> failed — <FAILURE_REASON>. Using Claude replacement for remainder of session.**`

Where `<FAILURE_REASON>` is `FAILURE_REASON` value from `collect-reviewer-results.sh` output (or from `.diag` file if collect manual). Always include reason so user can diagnose root cause (e.g., timeout duration, exit code, last error output).

Mental flag flip inside current skill call. For cross-skill spread inside `/implement`, child skills write structured health status file — see `/implement` SKILL.md.

**Note**: Once reviewer marked unhealthy in session, stay unhealthy rest of session. Intentional — stop oscillation and wasted time on flaky tools during long outages.

## Collecting External Reviewer Results

After launch Codex and/or Cursor as background tasks (via `run-external-reviewer.sh` with `run_in_background: true`), keep work on other tasks (e.g., process Claude subagent results) while external reviewers run.

After all other tasks done, collect and validate external reviewer outputs with shared collection script:

```bash
${CLAUDE_PLUGIN_ROOT}/scripts/collect-reviewer-results.sh --timeout <seconds> [--write-health <path>] <output-file> [<output-file> ...]
```

Only list output file paths for reviewers actually launched. For Bash tool call, use `timeout: <seconds>000` (milliseconds) and **do NOT** set `run_in_background: true` — this call must block. Script inside call `wait-for-reviewers.sh` to poll for `.done` sentinel files, validate each output, retry once on empty output (use `.meta` files written by `run-external-reviewer.sh`).

**Output**: Script emit structured `KEY=value` blocks on stdout (one block per reviewer, blank line between):
```
REVIEWER_FILE=<output-path>
TOOL=<codex|cursor|unknown>
STATUS=<OK|TIMED_OUT|FAILED|EMPTY_OUTPUT|SENTINEL_TIMEOUT>
EXIT_CODE=<N>
HEALTHY=<true|false>
FAILURE_REASON=<explanation>
```

Parse each reviewer `STATUS`, `REVIEWER_FILE`, `FAILURE_REASON`:
- `STATUS=OK`: Read output file — non-empty and validated. `FAILURE_REASON` empty.
- Any other status: Reviewer failed. `FAILURE_REASON` say why (e.g., "Timed out after 1800s (limit: 1800s). Process was killed after exceeding the timeout." or "Failed with exit code 1 after 5s. Last output: error message here"). Follow **Runtime Timeout Fallback** above, include `FAILURE_REASON` in message.

**Important**: Do NOT read output files before call `collect-reviewer-results.sh`. Cursor buffer all stdout until exit — output file empty until process finish. Collection script handle all sentinel polling and validation inside.

## Negotiation Protocol

> **Note**: `/design` and `/review` now use **Voting Protocol** in `voting-protocol.md` instead of this Negotiation Protocol. Section kept for skills that still use negotiation: `/loop-review` and `/research`.

> **Variable substitution**: Replace `<skill-tmpdir>` in all paths below with session tmpdir variable passed by caller (e.g., `$DESIGN_TMPDIR` or `$REVIEW_TMPDIR`).

> **Parameters**: `max_rounds` (default: 3) — max number of negotiation rounds. Callers may override (e.g., `/loop-review` use `max_rounds=1` to keep runtime small across many slices).

Negotiate with each external reviewer (Codex, Cursor) for up to **`max_rounds` rounds** back-and-forth:

1. Evaluate each finding. **Accept** unless factually wrong (reference wrong file/line, misunderstand code) or contradict project convention in CLAUDE.md.
2. For findings you disagree with, write response to negotiation prompt file explain reasoning. Use Write tool if available; if skill not allow Write (e.g., `/research`), write prompt file via `run-negotiation-round.sh` script `--prompt-file` arg (caller must create file through whatever means skill permits). Prompt should include original finding, counter-argument, ask reviewer to either hold position with more justification or withdraw finding.
   - **Codex**: Write to `<skill-tmpdir>/codex-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-negotiation-round.sh --tool codex --prompt-file "<skill-tmpdir>/codex-negotiation-prompt.txt" --output "<skill-tmpdir>/codex-negotiation-output.txt" --workspace "$PWD"
     ```
   - **Cursor**: Write to `<skill-tmpdir>/cursor-negotiation-prompt.txt`, then:
     ```bash
     ${CLAUDE_PLUGIN_ROOT}/scripts/run-negotiation-round.sh --tool cursor --prompt-file "<skill-tmpdir>/cursor-negotiation-prompt.txt" --output "<skill-tmpdir>/cursor-negotiation-output.txt" --workspace "$PWD"
     ```
   Use `timeout: 300000` on both Bash tool calls.
3. Repeat up to 3 rounds total. After round 3 (or earlier if all disagreements resolved), **Claude make final call** on any remain disputes.
