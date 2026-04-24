# test-improve-skill-skill-md.sh — contract sibling

**Consumer**: `make lint` (via the `test-improve-skill-skill-md` Makefile target).

**Contract**: structural regression harness for `skills/improve-skill/SKILL.md`. Companion to `test-improve-skill-iteration.sh` (which pins `iteration.sh` source tokens); this harness pins the SKILL.md contract tokens introduced by the live-streaming pattern: frontmatter `allowed-tools: Bash, Monitor`, env-overridable log-path (`IMPROVE_SKILL_LOG_FILE`) with `/tmp/` + `/private/tmp/` validation, visible log-path emission (pre-launch `📄 Full iteration log:` + completion `📄 Full iteration log (retained):`), background-Bash launch directive + Monitor persistence directive, byte-verbatim filter regex (`tail -F "$LOG_FILE" | grep --line-buffered -E '^(✅|> \*\*🔶|\*\*⚠)'`), and filter-regex parity with `iteration.sh`'s three breadcrumb printf emitters.

**Why a parallel harness**: SKILL.md surface is byte-close to `/loop-improve-skill/SKILL.md`, and the same live-streaming contract governs both. A parallel harness mirrors the existing `test-loop-improve-skill-skill-md.sh` so drift on either side is detected at `make lint` time.

**Invoked via**: `bash scripts/test-improve-skill-skill-md.sh`. Wired into `make lint` via `test-harnesses`. Listed in `agent-lint.toml` dead-script exclusion.

**Edit-in-sync rules**:
- When editing `skills/improve-skill/SKILL.md`, verify assertions A-E still match the canonical tokens; update here if any literal shifts.
- When editing `skills/improve-skill/scripts/iteration.sh` breadcrumb helpers, confirm assertion F's three `printf` patterns still match.
