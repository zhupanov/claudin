# validate-args.sh — sibling contract

Single coordinator that parses and validates the argument set for `/skill-evolver`. Invoked from `skills/skill-evolver/SKILL.md` Step 1.

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/skill-evolver/scripts/validate-args.sh $ARGUMENTS
```

`$ARGUMENTS` is unquoted at the call site so the shell tokenizes on whitespace. The script consumes argv normally (`$@`/`shift`/`$#`).

## Flag grammar

| Token | Type | Effect | Default |
|-------|------|--------|---------|
| `--debug` | boolean | Forward `DEBUG=true` through to the orchestrator (which forwards it to `/research` and `/umbrella`). | `false` |
| `--` | separator | End-of-flags marker; subsequent tokens are positionals. | n/a |
| anything else starting with `--` | error | `VALID=false ERROR=Unknown flag '<flag>'`. | n/a |

Flag parsing stops at the first non-flag token. Flags after the positional are rejected as "Unexpected extra arguments".

## Positional grammar

| Position | Name | Required | Validation |
|----------|------|----------|------------|
| 1 | `<skill-name>` | yes | Leading `/` is stripped. Must match `^[a-z][a-z0-9-]*$`, length ≤ 64. Must resolve to `skills/<name>/SKILL.md` (preferred — plugin tree) or `.claude/skills/<name>/SKILL.md` (project-local fallback). |

Extra positional arguments after `<skill-name>` are rejected.

## CWD precondition

The script enforces that CWD is a larch plugin repo by checking for **both**:
- `.claude-plugin/plugin.json`
- `skills/implement/SKILL.md`

This matches the gate in `skills/create-skill/scripts/validate-args.sh`. The skill is only meaningful inside the plugin source tree (or a checkout of it) because the research prompt's "repo-local survey" step depends on `skills/` and `.claude/skills/` being present.

## Stdout grammar

Every successful exit prints exactly one of two shapes, byte-aligned:

**Valid** (4 lines, in this order):
```
VALID=true
SKILL_NAME=<kebab name, leading '/' stripped>
SKILL_DIR=<absolute path to the skill directory>
DEBUG=true|false
```

**Invalid** (3 lines, in this order):
```
VALID=false
DEBUG=true|false
ERROR=<single-line human-readable message>
```

Both shapes exit `0`. `VALID=false` is the orchestrator's branch signal — exit-code-based branching would conflict with `set -euo pipefail` callers and with the SKILL.md "parse `VALID`" contract.

## ERROR taxonomy (canonical messages)

The orchestrator does not parse `ERROR` strings semantically — they are surfaced verbatim to the user. Keep these messages stable across patch versions to avoid breaking operator muscle memory:

- `Unknown flag '<flag>'. Valid flags: --debug.`
- `Missing <skill-name>. Usage: /skill-evolver [--debug] <skill-name>`
- `Unexpected extra arguments after <skill-name>: <args>`
- `Mandatory <skill-name> argument is empty after stripping leading '/'.`
- `Skill name must match ^[a-z][a-z0-9-]*$ (got: <name>).`
- `Skill name too long (<n> chars > 64).`
- `CWD is not a larch plugin repo (.claude-plugin/plugin.json + skills/implement/SKILL.md required).`
- `Target skill not found at skills/<name>/SKILL.md or .claude/skills/<name>/SKILL.md.`

## Edit-in-sync rules

Update this contract in the same PR as any of the following edits to `validate-args.sh`:
- New or renamed flag.
- New or renamed positional argument.
- Change to the stdout grammar (key names, line order, value format).
- Change to the CWD precondition or skill-existence search order.
- Change to the ERROR message text.

The orchestrator (`skills/skill-evolver/SKILL.md` Step 1) parses the four `VALID=true` keys (`SKILL_NAME`, `SKILL_DIR`, `DEBUG`) and the `ERROR` key on the failure path. Adding a new key without updating SKILL.md silently drops the value; removing a parsed key breaks Step 2.

## Test posture

Behavior is small enough to verify by hand at edit time:

- `validate-args.sh design` (CWD = plugin repo, `skills/design/SKILL.md` exists) → `VALID=true SKILL_NAME=design SKILL_DIR=<abs>/skills/design DEBUG=false`.
- `validate-args.sh /design` → same as above (leading `/` stripped).
- `validate-args.sh --debug design` → same plus `DEBUG=true`.
- `validate-args.sh nonexistent-skill` → `VALID=false ERROR=Target skill not found …`.
- `validate-args.sh BadName` → `VALID=false ERROR=Skill name must match …`.
- `validate-args.sh design extra` → `VALID=false ERROR=Unexpected extra arguments …`.
- `validate-args.sh` (no args) → `VALID=false ERROR=Missing <skill-name> …`.
- `validate-args.sh --unknown design` → `VALID=false ERROR=Unknown flag …`.

A scripted regression harness is not warranted at this size (per Section IX "verifiable quality criteria" — skills with only one private script and a flat flag grammar do not require a `test-*.sh` companion). If the script grows (e.g., gains compose-prompt logic or external-resource lookups), add a sibling `test-validate-args.sh` and wire it into `make lint`.
