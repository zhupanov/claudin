# parse-args.sh contract

`skills/create-skill/scripts/parse-args.sh` parses `/create-skill`'s `$ARGUMENTS` string and emits the seven named values (`NAME`, `DESCRIPTION`, `PLUGIN`, `MULTI_STEP`, `MERGE`, `DEBUG`, `NO_SLACK`) that Step 1 of `skills/create-skill/SKILL.md` consumes. The authoritative developer-facing specification is the in-file header (lines 1–33 of the script) — edits that change the flag list, the stdout `KEY=VALUE` grammar, the positional-argument rules, or the error-message format MUST update both the in-file header and this sibling in the same PR per `AGENTS.md § Editing rules` (per-script contract rule).

## Stdout contract (success, one line per `KEY=VALUE`)

- `NAME=<skill-name>` — first positional, leading `/` stripped, passed verbatim downstream (not validated here — `validate-args.sh` owns the regex and reserved-name checks).
- `DESCRIPTION=<description>` — space-joined remainder after the first positional, verbatim.
- `PLUGIN=true|false` — whether `--plugin` was present.
- `MULTI_STEP=true|false` — whether `--multi-step` was present.
- `MERGE=true|false` — whether `--merge` was present. Retained for backward compatibility only; `/create-skill` already delegates to `/im` (which prepends `--merge`), so this value is NOT forwarded at delegation time.
- `DEBUG=true|false` — whether `--debug` was present. Forwarded to `/im` (and thence to `/implement`) when `true`.
- `NO_SLACK=true|false` — whether `--no-slack` was present. Forwarded to `/im` (and thence to `/implement`) when `true`, suppressing the delegated run's Slack announcement. When `false` (the default), the delegated run posts per `/implement`'s default-on behavior (gated on Slack env vars).

## Error contract

- Unknown flag → emits `ERROR=Unknown flag '<flag>'. Valid flags: --plugin, --multi-step, --merge, --debug, --no-slack.` to stdout and exits non-zero.
- Missing `<skill-name>` → emits `ERROR=Missing <skill-name>. Usage: ...` to stdout and exits non-zero.
- Missing `<description>` → emits `ERROR=Missing <description>. Usage: ...` to stdout and exits non-zero.

## Positional-argument rules

- Flags are parsed from the start of `$ARGUMENTS`. Parsing stops at the first token that does not start with `--`.
- A single leading `/` is stripped from `<skill-name>` so `/foo` and `foo` are equivalent inputs.
- `<description>` is the space-joined verbatim remainder — no validation here; `validate-args.sh` enforces length, XML, and shell-dangerous pattern rejection.

## Test coverage

A dedicated offline harness exists at `scripts/test-parse-args.sh` and is wired into `make lint`. Add new test cases there whenever the stdout grammar, flag list, or error-message format changes. The script is also exercised indirectly via every `/create-skill` invocation and by the repo's `agent-lint` pass over `SKILL.md`.
