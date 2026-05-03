# test-umbrella-parse-args.sh

**Purpose**: regression harness for `skills/umbrella/scripts/parse-args.sh`. Pins the stdout grammar (`LABELS_COUNT` + indexed `LABEL_<i>`, `TITLE_PREFIX`, `REPO`, `CLOSED_WINDOW_DAYS`, `DRY_RUN`, `GO`, `INPUT_FILE`, `UMBRELLA_SUMMARY_FILE`, `TASK`, `UMBRELLA_TMPDIR`), the frozen `ERROR=` template list, the quoting subset (single quotes, double quotes with `\"`/`\\`/`\$` escapes, outside-quote backslash escapes, space/tab/newline as unquoted separators), the paired-flag and TASK-mutual-exclusion validation rules for `--input-file` / `--umbrella-summary-file`, and the TASK byte-preservation contract documented in `parse-args.md` so downstream parsers (`SKILL.md` Step 0 + `/issue` forwarding prose in Steps 3A / 3B.2 / 3B.3) don't silently break on unrelated edits.

## Helpers

- `run_parser` — runs the parser, captures stdout/stderr/exit code, removes the parser-owned `UMBRELLA_TMPDIR`, and `sed`-strips three lines from stdout: the `UMBRELLA_TMPDIR=...` line (always — non-deterministic across runs), the `INPUT_FILE=` line **only when its value is empty**, and the `UMBRELLA_SUMMARY_FILE=` line **only when its value is empty**. The empty-value strip preserves the byte-exact expected strings of the 25 pre-existing `assert_stdout` cases (which were authored before these flags existed) without churning every case body.
- `assert_stdout LABEL ARGS EXPECTED` — asserts parser exits 0 and the stripped stdout equals EXPECTED. Used by all 25 pre-existing cases plus the cases that don't exercise the new flags.
- `assert_raw_stdout_contains LABEL ARGS EXPECTED_LINE` — asserts parser exits 0 and the raw stdout (only `UMBRELLA_TMPDIR=` stripped, `INPUT_FILE=` / `UMBRELLA_SUMMARY_FILE=` preserved) contains EXPECTED_LINE as an exact full-line match. Used by new cases that verify the flag-emission KV lines.
- `assert_error LABEL ARGS EXPECTED_SUBSTRING` — asserts parser exits non-zero and stderr contains EXPECTED_SUBSTRING.

## When to run

- Wired into `make lint` via the `test-umbrella-parse-args` Makefile target (parallel to `test-umbrella-helpers`), included in the `test-harnesses` aggregate.
- Also suitable for ad-hoc runs: `bash skills/umbrella/scripts/test-umbrella-parse-args.sh`.

## Naming distinction

Distinct from `scripts/test-parse-args.sh` (top-level) which tests `skills/create-skill/scripts/parse-args.sh` — a completely unrelated parser. The Makefile targets `test-parse-args` (create-skill) and `test-umbrella-parse-args` (this harness) are independent and cover non-overlapping scripts.

## When to update

Per `scripts/parse-args.md`'s "Edit-in-sync rules", a material change to:

- the flag set (new flag, renamed flag, removed flag),
- the stdout grammar (new key, renamed key, reordered emission),
- the frozen ERROR= template list (new error, renamed error, changed wording),
- the quoting subset, or
- the TASK byte-preservation contract

requires updating this harness in the same PR. Add new test cases before changing the script so the change is test-driven.

## Edit-in-sync triggers

- Flag added / renamed / removed → add flag test case; update the "missing value" / "unknown flag" cases if the valid-flag list changed.
- Stdout key renamed / reordered → update every `assert_stdout` whose `expected` references the old key or order.
- ERROR= wording changed → update the substring match in the corresponding `assert_error` call AND update the frozen list in `parse-args.md`.
- Quoting subset extended (e.g., support new escape) → add a positive test case for the new behavior plus a negative test that previously-rejected input is still rejected.

## Coverage map

| Case | What it pins |
|------|--------------|
| 1 | Single `--label` → indexed emission. |
| 2 | Quoted whitespace in `--label`. |
| 3 | Repeated `--label` → `LABEL_1..LABEL_N` indexed. |
| 4 | Quoted whitespace in `--title-prefix`. |
| 5-6 | Other scalar flags (`--repo`, `--closed-window-days`). |
| 7 | `--closed-window-days` integer validation error. |
| 8 | Boolean flags (`--dry-run`, `--go`). |
| 9 | TASK preserves embedded multi-space + trailing whitespace; **no leading whitespace contamination**. |
| 10 | Bare `--` end-of-flags marker. |
| 11 | Unclosed double quote → ERROR. |
| 12 | Stray trailing backslash → ERROR. |
| 13 | Missing value for `--label` → ERROR. |
| 14 | Unknown flag → ERROR. |
| 15 | Empty input. |
| 16 | Escaped quote inside double-quoted value. |
| 17 | Unclosed single quote → ERROR (symmetric with case 11). |
| 18 | Embedded newline INSIDE quoted value → ERROR. |
| 19 | LABEL value containing literal `=` survives in stdout. |
| 20 | Quoted positional starting with `--` — phase 1 stops; TASK is verbatim. |
| 21 | Newline as unquoted separator outside quotes. |
| 22 | Unbalanced quote inside TASK — verbatim, lexer does NOT validate TASK. |
| 23 | Embedded newline in TASK → ERROR (post-Phase-2 guard; would break single-line KV grammar). |
| 24 | Backslash-escaped newline in unquoted value → ERROR (distinct frozen template `embedded newline in unquoted value`; cases 18 and 25 carry the parallel `embedded newline in quoted value` template for genuinely quoted-value paths). |
| 25 | Backslash-escaped newline INSIDE double-quoted value → ERROR (closes the double-quoted reader's `\\)` arm). |
| 26 | Both `--input-file` AND `--umbrella-summary-file` set → `INPUT_FILE=<path>` emitted in raw stdout (assert_raw_stdout_contains). |
| 26b | Both flags set → `UMBRELLA_SUMMARY_FILE=<path>` emitted in raw stdout (assert_raw_stdout_contains). |
| 27 | Half-config: `--input-file` alone → ERROR `--input-file and --umbrella-summary-file must be passed together` (paired-flag validation). |
| 28 | Half-config: `--umbrella-summary-file` alone → ERROR `--input-file and --umbrella-summary-file must be passed together` (symmetric direction of case 27). |
| 29 | `--input-file` plus a positional TASK → ERROR `--input-file is mutually exclusive with positional TASK`. |
| 30 | Missing value for `--input-file` → ERROR `--input-file requires a value` (frozen template). |
| 31 | Missing value for `--umbrella-summary-file` → ERROR `--umbrella-summary-file requires a value` (frozen template). |
