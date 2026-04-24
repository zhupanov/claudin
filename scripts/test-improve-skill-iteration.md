# test-improve-skill-iteration.sh — contract sibling

**Consumer**: `make lint` (via the `test-improve-skill-iteration` Makefile target).

**Contract**: two-tier regression harness for `skills/improve-skill/scripts/iteration.sh` — the shared per-iteration kernel invoked standalone by `/improve-skill` and once per round by `/loop-improve-skill/scripts/driver.sh`.

**Tier 1 — Structural**: pins contract tokens in `iteration.sh` source:
- subprocess invocation and security contracts: `parse-skill-judge-grade.sh`, `claude --version`, `set -euo pipefail`, `verify-skill-called.sh --stdout-line '^✅ 18: cleanup'`, work-dir `/tmp/` + `/private/tmp/` prefix literals, `'..'` rejection, `--plugin-dir` + `"$CLAUDE_PLUGIN_ROOT"` (FINDING_7), fully-qualified `/larch:design` / `/larch:im`, `2> "$stderr_file"` + `local stderr_file="${out_file}.stderr"` (FINDING_10), `< "$prompt_file"` (FINDING_9), `redact-secrets.sh`, `cleanup-tmpdir.sh`, `gh issue comment` + `gh issue create`, `session-setup.sh`, `IMPROVE_SKILL_SKIP_PREFLIGHT` opt-in;
- argv flags: `--no-slack`, `--issue`, `--work-dir`, `--iter-num`, `--breadcrumb-prefix`; `NO_SLACK_FLAG="--no-slack "` byte-parallel literal;
- per-iteration artifact filename template: `iter-${ITER_NUM}-judge-prompt.txt`, `iter-${ITER_NUM}-design-prompt.txt`, `iter-${ITER_NUM}-im-prompt.txt`, `iter-${ITER_NUM}-infeasibility.md`;
- KV-footer machinery: `trap cleanup_on_exit EXIT`, `emit_kv_footer`, the `### iteration-result` delimiter, and all 9 KV keys (`ITER_STATUS`, `EXIT_REASON`, `PARSE_STATUS`, `GRADE_A`, `NON_A_DIMS`, `TOTAL_NUM`, `TOTAL_DEN`, `ITERATION_TMPDIR`, `ISSUE_NUM`);
- amended `/design` prompt four-rule directive set — rules 1-3 byte-present alongside rule 4 (pushback carve-out: `MAY disagree with specific /skill-judge findings`, `## Pushback on judge findings`, `does NOT override rules 1-3`);
- breadcrumb printf format strings so filter-regex parity with the SKILL.md's Monitor-tail grep regex stays byte-close.

**Tier 2 — Behavioral**: four fixtures stubbing `claude` and `gh` on PATH, invoking the kernel with `--work-dir $iter_workdir --iter-num 1 --issue 42` (loop-mode, no `session-setup.sh` call), and asserting on the `ITER_STATUS=` line in the KV footer emitted to stdout. Cases: `grade_a` (non-A short-circuit path validation), `no_plan`, `design_refusal`, `im_verification_failed`.

**Why two tiers**: structural-only coverage is too weak for a script that hosts the halt-class-critical /design + /im kernel logic; behavioral fixtures exercise the actual control flow. Matches the pre-refactor `test-loop-improve-skill-driver.sh` two-tier pattern (now applied to the factored-out kernel where the logic actually lives).

**Invoked via**: `bash scripts/test-improve-skill-iteration.sh`. Wired into `make lint` via `test-harnesses`. Listed in `agent-lint.toml` dead-script exclusion (mirroring `test-loop-improve-skill-driver.sh`'s entry — harness is Makefile-only, its consumer SKILL.md does not reference it).

**Edit-in-sync rules**:
- When editing `skills/improve-skill/scripts/iteration.sh`, read `skills/improve-skill/scripts/iteration.md` (the kernel contract sibling) first and update needles here if any pinned token moves.
- Any KV-footer key addition/rename must appear in BOTH this test AND `scripts/test-loop-improve-skill-driver.sh` (which pins the driver's awk parse).
- Rules 1-3 of the `/design` directive set must remain byte-preserved; rule 4 (pushback carve-out) may evolve but its key phrases (`MAY disagree with specific`, `## Pushback on judge findings`, `does NOT override rules 1-3`) are load-bearing.
