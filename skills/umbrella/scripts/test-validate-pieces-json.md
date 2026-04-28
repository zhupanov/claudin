# test-validate-pieces-json.sh

Offline regression harness for `validate-pieces-json.sh`. No network calls.

## Makefile

`make test-validate-pieces-json` → `bash skills/umbrella/scripts/test-validate-pieces-json.sh`

## Coverage

- Valid 2-entry and 3-entry pieces.json with correct depends_on
- Valid pieces.json with missing depends_on (defaults to [])
- Missing --pieces-file / --count arguments
- Non-integer --count
- File not found
- Non-JSON file
- Non-array JSON (object)
- Count mismatch
- depends_on is string not array
- Forward reference (entry 1 depends on entry 2)
- Self-reference (entry 2 depends on itself)
- Zero-based reference (must be 1-based)
- Unknown argument

## Edit-in-sync

- `skills/umbrella/scripts/validate-pieces-json.sh` (the script under test)
- `skills/umbrella/scripts/validate-pieces-json.md` (frozen ERROR= templates)
