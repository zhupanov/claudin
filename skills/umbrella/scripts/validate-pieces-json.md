# validate-pieces-json.sh

Minimal shared validator for caller-supplied `pieces.json` dep-edge schema. Used by `/umbrella` Step 3B.4 (pre-decomposed-input mode) when `--pieces-json` is supplied.

## Purpose

Validates the structural integrity of the `depends_on` fields in a caller-supplied `pieces.json` file. Deliberately narrow: checks only the dep-edge schema (array shape, integer range), NOT `title`/`body` content — those are validated by `render-batch-input.sh` in normal mode and by the batch input's own parse contract in pre-decomposed mode.

## Interface

```
validate-pieces-json.sh --pieces-file <path> --count <N>
```

- `--pieces-file`: path to the JSON file to validate
- `--count`: expected number of entries (must match `ITEMS_TOTAL` from `/issue`'s `parse-input.sh`)

## Ordering contract

`pieces.json[k]` (0-based) corresponds to batch item `k+1` (1-based) as parsed by `parse-input.sh` from the same `INPUT_FILE`. The `--count` alignment enforces that the arrays are the same length; ordering is by convention (both enumerate items in file order).

## Validation rules

1. Valid JSON (jq parse succeeds)
2. Top-level array
3. Array length equals `--count`
4. Each entry's `depends_on` (defaulting to `[]` if absent) is an array of integers where each value satisfies `1 <= v < entry_1based_index`

## Exit codes

- 0: valid
- 1: invalid — `ERROR=<msg>` on stderr

## Frozen ERROR= templates

```
ERROR=--pieces-file is required
ERROR=--count is required
ERROR=--count must be a non-negative integer; got '<value>'
ERROR=pieces-json file not found: <path>
ERROR=jq is required but was not found in PATH
ERROR=invalid pieces-json: <reason>
ERROR=invalid pieces-json: top-level value must be a JSON array, got <type>
ERROR=pieces-json length mismatch: expected <N> entries, got <M>
ERROR=pieces-json entry <N> field 'depends_on' must be an array
ERROR=pieces-json entry <N> has out-of-range depends_on values: <values> (must be 1-based ints < entry index)
ERROR=Unknown argument: <arg>
```

## Edit-in-sync

- `skills/umbrella/SKILL.md` Step 0 and Step 3B.4 (pre-decomposed-input validation)
- `skills/umbrella/scripts/test-validate-pieces-json.sh` (regression harness)
- `skills/umbrella/scripts/parse-args.md` (references this validator)

## Parallel validation in render-batch-input.sh

`render-batch-input.sh` (lines 57-101) performs similar `depends_on` validation for the normal-mode LLM decomposition path. The two validators serve different call paths and are maintained independently. When editing validation rules in either script, check the other for consistency.

## Makefile

Regression harness: `make test-validate-pieces-json` → `bash skills/umbrella/scripts/test-validate-pieces-json.sh`
