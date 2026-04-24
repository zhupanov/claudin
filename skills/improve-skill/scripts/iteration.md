# iteration.sh — contract sibling

**Consumer**: `/improve-skill` SKILL.md (standalone user-facing invocation) and `/loop-improve-skill/scripts/driver.sh` (loop body, one invocation per iteration up to 10 rounds).

**Contract**: byte-preserved per-iteration kernel semantics — argv, flag validation, work-dir ownership, per-iteration artifact filenames under `$WORK_DIR`, `claude -p` subprocess invocation with FINDING_9 (STDIN prompt) + FINDING_10 (stderr sidecar), redact-secrets.sh before gh issue comment, verify-skill-called.sh mechanical gate, the KV footer schema emitted on stdout via EXIT trap, and the amended `/design` prompt that carries the four-rule directive set (no-minor-self-curtail, no-budget-self-curtail, no-no-plan-sentinels, narrow per-finding pushback carve-out).

**When to load**: before editing `iteration.sh` or any consumer that parses its KV footer; before adjusting the pushback carve-out wording.

## Invocation

```
iteration.sh [--slack] [--issue <N>] [--breadcrumb-prefix <P>] [--work-dir <path>] [--iter-num <N>] <skill-name>
```

## Modes

**Standalone mode** (no `--work-dir`):
- Calls `session-setup.sh --prefix claude-improve` to create a fresh work-dir under `/tmp` or `/private/tmp`.
- Owns work-dir cleanup via EXIT trap (`cleanup-tmpdir.sh`).
- Invoked by `/improve-skill/SKILL.md` for single-iteration user runs.
- Creates its own GitHub tracking issue unless `--issue <N>` is supplied.

**Loop mode** (`--work-dir <path>` supplied):
- Uses caller-supplied work-dir (required to be under `/tmp` / `/private/tmp`, no `..` path components).
- Does NOT clean up the work-dir — driver owns LOOP_TMPDIR cleanup via its own EXIT trap.
- Invoked by `/loop-improve-skill/scripts/driver.sh` with `--work-dir $LOOP_TMPDIR --iter-num $ITER --issue $ISSUE_NUM`, so all `iter-${ITER_NUM}-*.txt` artifacts accumulate in LOOP_TMPDIR and the driver's close-out (Step 5) reads them directly at known paths.

## Per-iteration artifacts (under `$WORK_DIR`)

- `iter-${ITER_NUM}-judge-prompt.txt` / `iter-${ITER_NUM}-judge.txt` — `/skill-judge` in/out.
- `iter-${ITER_NUM}-grade.txt` — `parse-skill-judge-grade.sh` output.
- `iter-${ITER_NUM}-design-prompt.txt` / `iter-${ITER_NUM}-design.txt` — `/design` in/out.
- `iter-${ITER_NUM}-design-rescue-prompt.txt` — when rescue re-invocation fires.
- `iter-${ITER_NUM}-im-prompt.txt` / `iter-${ITER_NUM}-im.txt` — `/larch:im` in/out.
- `iter-${ITER_NUM}-judge-comment.md` / `iter-${ITER_NUM}-plan-comment.md` — redacted tracking-issue comments.
- `iter-${ITER_NUM}-infeasibility.md` — written when `ITER_STATUS` is `no_plan` / `design_refusal` / `im_verification_failed`; consumed by `driver.sh`'s Step 5 close-out.
- `grade-history.txt` — one line per iteration; driver.sh's Step 5 close-out reads this.
- `*.stderr` sidecar per `invoke_claude_p` call (FINDING_10 — never posted to issue comments).

The filename template `iter-${ITER_NUM}-*.{txt,md}` and `grade-history.txt` are **load-bearing** — `driver.sh`'s Step 5 close-out reads `$LOOP_TMPDIR/iter-${IT}-infeasibility.md` and `$LOOP_TMPDIR/grade-history.txt` at byte-identical paths. Changing any of these names requires a matching edit in `driver.sh` in the same PR.

## KV footer (stdout)

Emitted via `trap emit_kv_footer EXIT` — guarantees the footer is present on every exit path (normal, error, `set -e` abort). Delimited by the `### iteration-result` header. 9 keys, each always present:

| Key | Value shape | Purpose |
|---|---|---|
| `ITER_STATUS` | `grade_a` / `ok` / `no_plan` / `design_refusal` / `im_verification_failed` / `judge_failed` / `unknown` | Terminal state for this iteration. Loop driver breaks on any terminal status except `ok` (which continues). |
| `EXIT_REASON` | free-text string | Byte-compatible with pre-#273 driver.sh exit-reason strings. Consumed by close-out. |
| `PARSE_STATUS` | `ok` / `missing_table` / `missing_file` / `bad_row` / `empty_file` / `unknown` | Result of `parse-skill-judge-grade.sh`. |
| `GRADE_A` | `true` / `false` | Convenience mirror of grade-parse output. |
| `NON_A_DIMS` | comma-separated `D1,D2,…` or empty | Dimensions below the per-dim threshold. |
| `TOTAL_NUM` / `TOTAL_DEN` | integer or `N/A` | Total score from the grade parse. |
| `ITERATION_TMPDIR` | absolute path | Work-dir actually used (caller-supplied in loop mode; fresh in standalone). |
| `ISSUE_NUM` | integer | Tracking issue number (adopted or created). |

## Stdout discipline

Stdout is reserved for:
1. Breadcrumb lines via the four helpers — `breadcrumb_done` (`✅`), `breadcrumb_inprogress` (`> **🔶`), `breadcrumb_warn` (`**⚠`), and `breadcrumb_skip` (`⏩`). Only the first three prefixes are matched by the Monitor-tail filter regex on the consumer SKILL.md's live stream (`breadcrumb_skip` is defined for future use and for symmetry with `driver.sh`; skip lines land in the retained log but not on the live Monitor view).
2. The `### iteration-result` header + 9 KV lines from the EXIT trap.

All `claude -p` child I/O stays in files under `$WORK_DIR` (via `invoke_claude_p`'s `> "$out_file"` and `2> "$stderr_file"` redirects). No third-party `KEY=value` text leaks onto iteration.sh's own stdout, so the loop driver's awk KV extraction is always unambiguous.

## Security invariants

- `$WORK_DIR` MUST start with `/tmp/` or `/private/tmp/` and contain no `..` path component.
- `invoke_claude_p` uses `--plugin-dir "$CLAUDE_PLUGIN_ROOT"` (FINDING_7) and routes prompts via STDIN (FINDING_9: prompts may exceed macOS default `ARG_MAX=262144`).
- Stderr is captured to a `.stderr` sidecar beside each out-file (FINDING_10: stderr may contain filesystem paths, hostnames, and unredacted `gh` diagnostics).
- `gh issue comment` bodies always pass through `redact-secrets.sh`.
- In loop mode, iteration.sh does NOT clean up the caller-supplied work-dir (`OWNS_WORK_DIR=false`) — driver owns `cleanup-tmpdir.sh`.

## Amended `/design` prompt — four-rule directive set

The design phase emits four directive clauses (byte-parallel to pre-#273 driver.sh plus one new clause):

1. **Rule 1** (pre-existing): `/design` MUST produce a concrete plan for ANY actionable finding, including "minor" ones — "minor" = "small plan", not "no plan".
2. **Rule 2** (pre-existing): `/design` MUST NOT self-curtail on token/context budget grounds; narrow scope to the highest-leverage finding and emit a micro-plan conforming to the schema.
3. **Rule 3** (pre-existing): `/design` MUST NOT emit any no-plan sentinel phrases when `/skill-judge` surfaced any actionable finding.
4. **Rule 4 (new — narrow per-finding pushback carve-out)**: `/design` MAY disagree with specific `/skill-judge` findings that appear erroneous. Disagreement MUST be surfaced via a dedicated `## Pushback on judge findings` subsection at the plan's end, with (a) the specific finding identified, (b) specific reasoning for why the finding is erroneous or misapplied, and (c) concrete codebase evidence (file:line) supporting the pushback. Pushback is strictly per-finding — the plan MUST still address every undisputed non-A dimension. The carve-out does NOT override rules 1-3.

The four-rule directive set is load-bearing prompt content; test-improve-skill-iteration.sh pins key phrases.

## Edit-in-sync rules

When editing `iteration.sh`:
- Update `iteration.md` (this file) if any of the load-bearing contracts change (KV footer keys, per-iter artifact filename template, directive set, stdout discipline).
- Update `scripts/test-improve-skill-iteration.sh` needles if any pinned token moves.
- Update `skills/loop-improve-skill/scripts/driver.sh`'s KV-footer parser if keys are renamed; byte-close the `driver.sh`'s awk pattern and the KV-emitter here.
- Per AGENTS.md "Per-script contracts live beside the script" rule, edit this sibling `.md` in the same PR as any behavioral change to `iteration.sh`.

## Makefile wiring

- `test-improve-skill-iteration` target runs `bash scripts/test-improve-skill-iteration.sh`.
- Listed in `test-harnesses:` aggregate and `.PHONY:` lines.
- Excluded from agent-lint's dead-script scan (Makefile-only reference pattern, mirroring the existing `test-loop-improve-skill-driver.sh` entry).

## Test-harness opt-in env vars

- `IMPROVE_SKILL_SKIP_PREFLIGHT=1`: adds `--skip-preflight` to the standalone-mode `session-setup.sh` call so fixture harnesses can exercise control-flow under a mktemp'd fixture workdir that is not a real git repo with origin/main configured. **Never enable in production.** Parallels the existing `LOOP_IMPROVE_SKIP_PREFLIGHT` env var in `driver.sh`.
