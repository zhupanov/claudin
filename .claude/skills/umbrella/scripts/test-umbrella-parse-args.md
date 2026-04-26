# test-umbrella-parse-args.sh

**Purpose**: regression harness for `.claude/skills/umbrella/scripts/parse-args.sh`. Pins the stdout grammar (`LABELS_COUNT` + indexed `LABEL_<i>`, `TITLE_PREFIX`, `REPO`, `CLOSED_WINDOW_DAYS`, `DRY_RUN`, `GO`, `DEBUG`, `TASK`, `UMBRELLA_TMPDIR`), the frozen `ERROR=` template list, the quoting subset (single quotes, double quotes with `\"`/`\\`/`\$` escapes, outside-quote backslash escapes, space/tab/newline as unquoted separators), and the TASK byte-preservation contract documented in `parse-args.md` so downstream parsers (`SKILL.md` Step 0 + `/issue` forwarding prose in Steps 3A / 3B.2 / 3B.3) don't silently break on unrelated edits.

## When to run

- Wired into `make lint` via the `test-umbrella-parse-args` Makefile target (parallel to `test-umbrella-helpers`), included in the `test-harnesses` aggregate.
- Also suitable for ad-hoc runs: `bash .claude/skills/umbrella/scripts/test-umbrella-parse-args.sh`.

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
| 8 | Boolean flags (`--dry-run`, `--go`, `--debug`). |
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
