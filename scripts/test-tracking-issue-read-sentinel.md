# test-tracking-issue-read-sentinel.sh contract

## Purpose

Regression harness for the `--sentinel` branch of `scripts/tracking-issue-read.sh`. Pins the `ADOPTED=` field contract defined by issue #359 for Phase 3 consumption.

## Invariants

1. **Allowed `ADOPTED` values**: exactly `true` or `false` when the key is present with a valid value, or empty (key absent or explicit `ADOPTED=`). No other non-empty value is accepted — strict equality on the extracted value (case-sensitive, no whitespace trimming other than trailing `\r`).
2. **Absence semantics**: an empty `ADOPTED=` line means "sentinel unusable". Absent key and explicit empty are semantically identical on stdout. Consumers MUST NOT treat empty as `false`.
3. **Parser behavior**:
   - Column-0 keys only: indented lines are silently treated as absent.
   - First match wins for duplicate keys (`grep -m1`).
   - Leading UTF-8 BOM stripped from the sentinel file's content before parsing.
   - Trailing `\r` stripped from extracted values (CRLF tolerance).
   - Other trailing whitespace NOT stripped (e.g., a value like `true` followed by a trailing space is rejected).
4. **Stdout shape on success**: exactly three lines — `ISSUE_NUMBER=<val>\n`, `ANCHOR_COMMENT_ID=<val>\n`, `ADOPTED=<val>\n` — in that order.
5. **Stdout shape on failure**: exactly two lines — `FAILED=true\n` followed by `ERROR=<single-line message>\n` — and exit 1.

## Test cases (15 total)

| ID | Input                                      | Expected exit | Expected stdout (exact)                                                                                      |
|----|--------------------------------------------|---------------|--------------------------------------------------------------------------------------------------------------|
| a  | `ADOPTED=true`                             | 0             | `ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=true\n`                                                          |
| b  | `ADOPTED=false`                            | 0             | `ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=false\n`                                                         |
| c  | empty file                                 | 0             | `ISSUE_NUMBER=\nANCHOR_COMMENT_ID=\nADOPTED=\n`                                                              |
| d  | `ADOPTED=` (explicit empty)                | 0             | same as (c)                                                                                                  |
| e  | `ADOPTED=yes`                              | 1             | `FAILED=true\nERROR=invalid ADOPTED value in sentinel: 'yes' (expected 'true' or 'false' or absent)\n`        |
| f  | `ADOPTED=TRUE`                             | 1             | envelope names `'TRUE'`                                                                                      |
| g  | `ADOPTED=1`                                | 1             | envelope names `'1'`                                                                                         |
| h  | `ADOPTED=true` + trailing space            | 1             | envelope names the trailing-space value                                                                      |
| i  | sentinel file does not exist              | 1             | `FAILED=true\nERROR=sentinel file not found: <path>\n`                                                       |
| j  | all three keys valid                       | 0             | `ISSUE_NUMBER=123\nANCHOR_COMMENT_ID=456\nADOPTED=true\n`                                                    |
| k  | duplicate `ADOPTED=` lines                 | 0             | first wins: `ADOPTED=true`                                                                                   |
| l  | CRLF on ALL three keys                     | 0             | `\r` stripped from every value: `ISSUE_NUMBER=123\nANCHOR_COMMENT_ID=456\nADOPTED=true\n`                    |
| m  | UTF-8 BOM-prefixed file                    | 0             | BOM stripped: first key on first line parses correctly                                                       |
| n  | leading whitespace before key              | 0             | column-0 rule: line unmatched, emits `ADOPTED=`                                                              |
| o  | sentinel file exists but unreadable (mode 000) | 1         | `FAILED=true\nERROR=sentinel file not readable: <path>\n` (skipped when running as root — chmod 000 is bypassed by root) |

Happy-path cases (a, b, c, d, j, k, l, m, n) use `assert_equal_stdout` against the full expected stdout string to pin exact 3-line shape and ordering. Failure cases (e, i, o) assert the exact envelope; cases (f, g, h) use `assert_contains` to verify the quoted rejected value appears in the ERROR line.

## Makefile wiring

Makefile target: `test-tracking-issue-read-sentinel` — `bash scripts/test-tracking-issue-read-sentinel.sh`. Listed in `.PHONY` and in the `test-harnesses` prerequisites (both at line 4 and line 14 of the current Makefile). CI invokes via `make lint` → `test-harnesses` → this target.

## `agent-lint.toml` exclusion

The harness is Makefile-only (not referenced from any `SKILL.md`), so agent-lint would flag it as dead. An exclusion entry in `agent-lint.toml` sits next to the existing `scripts/test-tracking-issue-write.sh` exclusion, with the same rationale.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/tracking-issue-read.sh` | Script under test. Every behavioral change in its `--sentinel` branch must be mirrored here — add / update assertions in the same PR. |
| `scripts/tracking-issue-read.md` | Canonical contract document. Any new allowed `ADOPTED` value or parser behavior change requires updating the contract AND the harness in sync. |
| `Makefile` | `test-harnesses` target invokes this harness. Adding / removing targets must stay in sync with the `.PHONY` line. |
| `agent-lint.toml` | Exclusion entry for this Makefile-only harness. |

## Conventions

Bash 3.2-safe. No external `gh` stub needed — `--sentinel` mode is purely local (no network).
