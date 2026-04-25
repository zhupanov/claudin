# test-sentinel-write.sh

`skills/issue/scripts/test-sentinel-write.sh` is the regression harness for `skills/issue/scripts/write-sentinel.sh`. Pure-Bash, hermetic — no `gh` calls, no network, no GitHub state required. Wired into `make lint` via the `test-sentinel-write` target.

## Cases

The harness covers seven scenarios from the issue #509 plan plus four argument-validation cases:

- **(a)** all-success → sentinel written with all 5 keys (`ISSUE_SENTINEL_VERSION=1`, `ISSUES_CREATED`, `ISSUES_DEDUPLICATED`, `ISSUES_FAILED`, `TIMESTAMP`).
- **(b)** all-dedup (`ISSUES_CREATED=0`, `ISSUES_FAILED=0`, `ISSUES_DEDUPLICATED>=1`) → sentinel **written**. Pins the FINDING_1 fix: sentinel proves execution, not creation count, so a successful dedup-only run does not false-fail in `/research`.
- **(c)** partial-failure (`ISSUES_FAILED>=1`) → no write; stderr `WROTE=false REASON=failures`.
- **(d)** dry-run → no write; stderr `WROTE=false REASON=dry_run` (even with `ISSUES_CREATED>=1`, because `/issue` Step 6 conceptually counts dry-run as `ISSUES_CREATED+=1`).
- **(e)** `--path` honored at an explicit deep-nested location; helper creates parent dirs with `mkdir -p`.
- **(f)** channel discipline — stdout is strictly empty when invoked successfully; status routes to stderr only. Pins the FINDING_5 fix.
- **(g)** atomicity — structural assertion that the script uses same-directory `mktemp` (`${PATH_ARG}.tmp.XXXXXX`) + `mv` to promote. Replaces the originally-proposed race-stress test (FINDING_7 exoneration).

Argument-validation cases (defense in depth):

- **(h)** missing `--path` → `ERROR=`, exit 1.
- **(i)** non-absolute `--path` → `ERROR=` mentions "absolute", exit 1.
- **(j)** `..` in `--path` → `ERROR=` mentions `'..'`, exit 1.
- **(k)** non-numeric counter → `ERROR=` mentions "non-negative integers", exit 1.
- **(l)** missing value for value-taking flag (final argv token is `--issues-failed` with nothing after it) → `ERROR=Missing value for --issues-failed`, exit 1. Pins the FINDING_3 fix from review: under `set -u`, dereferencing `$2` without a presence check would have aborted with a cryptic `unbound variable` instead of the documented stable `ERROR=` contract.

## Running

```bash
bash skills/issue/scripts/test-sentinel-write.sh
```

Or via the Makefile:

```bash
make test-sentinel-write
```

Exits 0 with a `... pass, 0 fail` summary on success. Exits 1 on the first failed assertion with detail to stderr.

## Edit-in-sync

When editing `write-sentinel.sh` (signature, gate predicates, output format, channel discipline, path validation rules), add or update cases here in the same PR. The harness is the executable contract enforcing the documented behavior in `write-sentinel.md`. shellcheck (via pre-commit) lints this file automatically.
