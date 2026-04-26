# test-loop-fix-issue-skill-md.sh contract

**Purpose**: Structural regression harness for `skills/loop-fix-issue/SKILL.md`. Companion to `test-loop-fix-issue-driver.sh` (which pins driver.sh contract tokens).

**Wired into**: `make lint` (via the `test-harnesses` aggregate) and the explicit `test-loop-fix-issue-skill-md` target.

## Assertions

| ID | Concern |
|----|---------|
| A | Frontmatter `allowed-tools` line contains both `Bash` and `Monitor` tokens (order-insensitive) |
| B | SKILL.md body declares `LOOP_FIX_ISSUE_DRIVER_LOG_FILE` env-overridable default AND the `/tmp/`+`/private/tmp/` case-arm validation AND the `..` path-component guard (security boundary; parity with `driver.sh`'s `LOOP_TMPDIR` `..` guard pinned by Assertion E in the sibling driver harness) |
| C | SKILL.md body surfaces the log path: at least one `📄 Full driver log:` pre-launch line AND at least one `📄 Full driver log (retained):` completion line |
| D | SKILL.md body contains `run_in_background: true` AND `persistent: true` (load-bearing per the bash-driver + Monitor pattern) |
| E | Filter-regex byte-verbatim: `tail -F "$LOG_FILE" \| grep --line-buffered -E '^(✅\|> \*\*🔶\|\*\*⚠)'` |
| F | Filter-regex parity with driver.sh breadcrumb helpers: each of the three alternatives (`✅`, `> **🔶`, `**⚠`) has a corresponding `printf` line in driver.sh |

## Why these tokens are byte-pinned

- The filter regex (Assertion E) is the bridge between SKILL.md's Monitor invocation and driver.sh's breadcrumb output. Any drift between the two breaks the live stream silently — the user sees no output but the driver runs to completion. CI must fail loudly on either side changing without the other.
- The `LOOP_FIX_ISSUE_DRIVER_LOG_FILE` security guards (Assertion B) MUST stay in parity with `driver.sh`'s `LOOP_TMPDIR` guards on BOTH dimensions: the `/tmp/*|/private/tmp/*` prefix check AND the `*/..|*/../*` path-component check. Without the `..` guard, a value like `LOOP_FIX_ISSUE_DRIVER_LOG_FILE=/tmp/foo/../etc/crontab` passes the prefix check yet escapes the intended directory. The sibling `test-loop-fix-issue-driver.sh` Assertion E pins the parallel `..` guard on `driver.sh`'s `LOOP_TMPDIR`; this harness's Assertion B pins the same shape on SKILL.md. If either dimension of the security boundary diverges between the two files, an attacker who can set the env var could write to arbitrary paths.
- The `📄 Full driver log:` literal (Assertion C) is the user-facing log-path visibility contract. Without it, the user has no way to inspect the full output if Monitor is unavailable.

## Edit-in-sync rules

- When editing `skills/loop-fix-issue/SKILL.md`, run this harness to confirm contract tokens stay intact.
- The filter literal in Assertion E is byte-pinned. Changing the breadcrumb prefixes in driver.sh REQUIRES updating BOTH the filter literal in SKILL.md AND this assertion in the same PR.
- This file mirrors `scripts/test-loop-review-skill-md.md` since `/loop-fix-issue` adopts the same bash-driver + Bash-background + Monitor-attach topology. The only meaningful divergence is the env-overridable log-path name (`LOOP_FIX_ISSUE_DRIVER_LOG_FILE` rather than `LOOP_DRIVER_LOG_FILE`).
