# driver.sh contract

**Purpose**: Bash driver for `/loop-review`. Owns loop control, repo partitioning, per-slice `claude -p /review` invocations, KV-footer counter aggregation, and security-finding aggregation.

**Topology**: inversion of loop control. The `/loop-review` SKILL.md is a thin (~80-line) shell that background-launches this driver and attaches Monitor to a tail of its log file. All real work lives here in bash.

## Invocation

```
driver.sh [--debug] [partition criteria...]
```

- `--debug`: optional flag (currently no-op; reserved for future verbosity control).
- `[partition criteria]`: remaining argv concatenated as freeform partition criteria appended to the partition prompt (e.g., `driver.sh focus on the design skill and its references`).

## Topology

| Step | Action |
|------|--------|
| 1 | argv parse + claude/gh CLI preflight |
| 2 | `session-setup.sh` → `LOOP_TMPDIR` (with `/tmp/`-prefix + no-`..` security guards) |
| 3 | preflight: `loop-review` GitHub label exists in current repo (warn if not) |
| 4 | partition step: `invoke_claude_p_freeform` with partition prompt → `$LOOP_TMPDIR/partitions.txt` (one verbal slice per line, 1–20) |
| 5 | per-slice loop: for each slice line N, write `slice-N-desc.txt`, build single-line slash-command prompt, invoke `invoke_claude_p_skill`, parse `### slice-result` KV footer, aggregate counters |
| 6 | final summary: aggregate counters, security-findings concatenated, SECURITY.md disclaimer |
| 7 | cleanup-tmpdir.sh on success via EXIT trap (retained on failure) |

## Per-slice claude -p invocation contract

The driver writes a single-line slash-command prompt to `$LOOP_TMPDIR/slice-${N}-cmd.txt`:

```
/review --slice-file $LOOP_TMPDIR/slice-${N}-desc.txt --create-issues --label loop-review --security-output $LOOP_TMPDIR/security-findings-slice-${N}.md
```

The slice text itself (the verbal description) lives in `slice-${N}-desc.txt`. File-based handoff bypasses argv shell-quoting entirely, so verbal descriptions containing quotes, parens, ampersands, dollar signs, etc. cannot break the invocation.

## `### slice-result` KV footer

`/review` (in slice + create-issues mode) MUST emit a KV footer immediately before exiting:

```
### slice-result
ISSUES_CREATED=<n>
ISSUES_DEDUPLICATED=<n>
ISSUES_FAILED=<n>
SECURITY_FINDINGS_HELD=<n>
PARSE_STATUS=ok
```

Mirrors `### iteration-result` from `skills/improve-skill/scripts/iteration.sh`. Driver awk-scopes the KV parse to lines AFTER the `### slice-result` header.

`PARSE_STATUS=ok` indicates a successful slice run. Any other value (or absence of the footer) is treated as slice failure: the driver logs a warning, increments the failure counter, sets `LOOP_PRESERVE_TMPDIR=true`, and continues to the next slice.

## Security-findings handoff

`/review` writes accepted security-tagged findings to the `--security-output <path>` argument. Driver passes `$LOOP_TMPDIR/security-findings-slice-${N}.md`. After all slices complete, the driver concatenates non-empty per-slice files into the final summary block, prints the SECURITY.md disclaimer, and sets `LOOP_PRESERVE_TMPDIR=true` so the per-slice files survive cleanup.

## Security boundaries

- **`LOOP_TMPDIR`** MUST begin with `/tmp/` or `/private/tmp/` AND MUST NOT contain `..` as a path component. Validated immediately after `session-setup.sh` returns; non-conforming values abort the driver.
- **All subprocess `claude -p` invocations** follow:
  - `--plugin-dir "$CLAUDE_PLUGIN_ROOT"` (FINDING_7: plugin resolution)
  - prompt on STDIN, not argv (FINDING_9: avoids macOS ARG_MAX = 262144)
  - stderr redirected to `<out>.stderr` sidecar (FINDING_10: never posted to GitHub)
- **On any subprocess failure**, redacted stderr+stdout-tail diagnostics are dumped via `dump_subprocess_diagnostics`; `LOOP_PRESERVE_TMPDIR` flips `true` so the EXIT trap retains the workdir for inspection.
- **`$LOOP_TMPDIR`** cleaned via EXIT trap on success; retained on any abnormal exit.

## Test-only override

`LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE=<path>` redirects `claude -p` invocations at a stub shim. Used ONLY by `scripts/test-loop-review-driver.sh` Tier-2 fixtures. Documented in SECURITY.md as test-only; never set in production. Same-user arbitrary-executable risk if set in a production environment.

## Removed behaviors (from prior `/loop-review` implementation)

The pre-overhaul `/loop-review` (driver-in-prompt) had several behaviors that this driver intentionally drops:

- **Sub-slicing (>50 files per slice)**: removed. Per-slice `/review` handles its own context internally; the new partition step is expected to produce semantically sensible slice sizes via LLM judgment rather than a 50-file mechanical split.
- **Batched `/issue` flushes across slices**: removed. Each slice's `/review --create-issues` files its own findings inline immediately; no cross-slice batching.
- **Negotiation Protocol with external reviewers**: removed. `/review`'s voting protocol (3-voter panel, YES/NO/EXONERATE, 2+ YES threshold) replaces external negotiation.
- **JSON partition config (`.claude/loop-review-partitions.json`)**: removed. LLM partitioning replaces this. If a consumer repo has a stale config file, this driver leaves it untouched; it is no longer consulted.
- **Auto-discovery of source directories**: removed. LLM partitioning replaces this.
- **Per-item retry on `/issue` partial failure at the driver level**: removed. Per-item retry now lives inside `/review`'s `/issue` invocation per `/issue`'s `ITEM_<i>_FAILED=true` contract; the driver only sees aggregate counters via the `### slice-result` KV footer. If a slice's `/review` reports `ISSUES_FAILED > 0`, those failures are surfaced in the final summary but not retried at the driver level.

## Edit-in-sync rules

- When editing `driver.sh`, read this file first; update it in the same PR as any behavioral change.
- The breadcrumb prefix families `^✅`, `^> \*\*🔶`, `^\*\*⚠` MUST stay in parity with the filter regex in `skills/loop-review/SKILL.md` (Step 4 Monitor invocation). The regex is byte-pinned by `scripts/test-loop-review-skill-md.sh`.
- The `### slice-result` KV footer schema (5 keys above) is consumed by `parse_slice_kv` in this driver. If `/review`'s footer schema changes, both `skills/review/SKILL.md` and this driver must be updated together.
- The `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` env-var name is referenced in `SECURITY.md` and `scripts/test-loop-review-driver.sh`. Renaming it requires updating both.

## Test harness

`scripts/test-loop-review-driver.sh` validates this driver:

- **Tier-1 structural tests**: file is executable, has `set -euo pipefail`, derives `CLAUDE_PLUGIN_ROOT` correctly, has cleanup trap, has `/tmp/`-prefix + no-`..` security guards on `LOOP_TMPDIR`, defines both `invoke_claude_p_freeform` and `invoke_claude_p_skill` with FINDING_7/9/10 contracts, has `parse_slice_kv` awk-scoped to lines after `### slice-result`.
- **Tier-2 stub-shim tests**: with `LARCH_LOOP_REVIEW_CLAUDE_OVERRIDE` pointed at a fixture stub that emits canned partition output + canned per-slice `/review` output (including a valid `### slice-result` KV footer), verify the driver completes the full loop, aggregates counters correctly, and exits cleanly.
