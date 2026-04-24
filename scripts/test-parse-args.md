# test-parse-args.sh

**Purpose**: regression harness for `skills/create-skill/scripts/parse-args.sh`. Pins the stdout grammar (`NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`, `NO_SLACK`), flag list, and error-message format so downstream parsers (the `/create-skill` SKILL.md body and the `/im` delegation arg composer) don't silently break on unrelated edits.

## When to run

- Wired into `make lint` via the standard `scripts/test-*.sh` discovery pattern.
- Also suitable for ad-hoc runs: `bash scripts/test-parse-args.sh`.

## When to update

Per `skills/create-skill/scripts/parse-args.md`, a material change to the stdout grammar (new key, renamed key, new error code) requires updating this harness in the same PR. Add new test cases before changing the script so the change is test-driven.

## Edit-in-sync triggers

- Flag added / renamed / removed → add flag test case; update the "all flags set" case; update the "unknown flag" usage-line assertion if the valid-flag list changed.
- Stdout key renamed → update every `check` whose `want` references the old key.
- Error-message wording changed → update the substring match in the corresponding error test.
