# validate-args.sh — sibling contract

Single coordinator that parses and validates the argument set for `/skill-evolver`. Invoked from `skills/skill-evolver/SKILL.md` Step 1.

## Invocation

```bash
${CLAUDE_PLUGIN_ROOT}/skills/skill-evolver/scripts/validate-args.sh $ARGUMENTS
```

`$ARGUMENTS` is unquoted at the call site so the shell tokenizes on whitespace. The script consumes argv normally (`$@`/`shift`/`$#`).

## Flag grammar

`/skill-evolver` accepts no flags. Any token starting with `--` is rejected as `VALID=false ERROR=Unknown flag '<flag>'`. The `--` end-of-flags marker is permitted as a separator.

## Positional grammar

| Position | Name | Required | Validation |
|----------|------|----------|------------|
| 1 | `<skill-name>` | yes | Leading `/` is stripped. Must match `^[a-z][a-z0-9-]*$`, length ≤ 64. Must resolve to `skills/<name>/SKILL.md` (preferred — plugin tree) or `.claude/skills/<name>/SKILL.md` (project-local fallback). |

Extra positional arguments after `<skill-name>` are rejected.

## CWD precondition

The script enforces that CWD is a larch plugin repo by checking for **both**:
- `.claude-plugin/plugin.json`
- `skills/implement/SKILL.md`

## Stdout grammar

Every successful exit prints exactly one of two shapes:

**Valid** (3 lines, in this order):
```
VALID=true
SKILL_NAME=<kebab name, leading '/' stripped>
SKILL_DIR=<absolute path to the skill directory>
```

**Invalid** (2 lines, in this order):
```
VALID=false
ERROR=<single-line human-readable message>
```

Both shapes exit `0`. `VALID=false` is the orchestrator's branch signal — exit-code-based branching would conflict with `set -euo pipefail` callers and with the SKILL.md "parse `VALID`" contract.

## ERROR taxonomy (canonical messages)

- `Unknown flag '<flag>'. /skill-evolver accepts no flags.`
- `Missing <skill-name>. Usage: /skill-evolver <skill-name>`
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

The orchestrator (`skills/skill-evolver/SKILL.md` Step 1) parses the success-path KV lines (`VALID`, `SKILL_NAME`, `SKILL_DIR`) and the `ERROR` line on the failure path.

## Test posture

Behavior is small enough to verify by hand at edit time:

- `validate-args.sh design` → `VALID=true SKILL_NAME=design SKILL_DIR=<abs>/skills/design`.
- `validate-args.sh /design` → same as above (leading `/` stripped).
- `validate-args.sh nonexistent-skill` → `VALID=false ERROR=Target skill not found …`.
- `validate-args.sh BadName` → `VALID=false ERROR=Skill name must match …`.
- `validate-args.sh design extra` → `VALID=false ERROR=Unexpected extra arguments …`.
- `validate-args.sh` (no args) → `VALID=false ERROR=Missing <skill-name> …`.
- `validate-args.sh --unknown design` → `VALID=false ERROR=Unknown flag …`.
