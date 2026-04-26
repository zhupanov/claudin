# scripts/file-line-regex-lib.sh — Contract

Source-only library exposing the file:line provenance regex tier rules used
by `scripts/validate-research-output.sh` (provenance probe in `/research`
output validation) and `skills/research/scripts/validate-citations.sh`
(file:line claim extraction in `/research` Step 2.7).

## Invariants

- **Source-only**. The library does NOT use `set -euo pipefail`, has no
  top-level `exit`, never reads CLI args, and does not mutate any global
  outside the `__filelinelib_*` namespace. Calling shells must be safe to
  source it idempotently from any context.
- **Namespace**. All exposed identifiers are prefixed `__filelinelib_*`.
  Consumers MUST NOT redefine these symbols.
- **Portable extended-regex**. Patterns work under BSD `grep -E` (macOS
  default), GNU `grep -E` (Ubuntu CI), and Bash 3.2 `[[ =~ ]]`. No PCRE,
  no lookarounds, no `\d`/`\w`.
- **Tier rules** mirror `validate-research-output.sh`'s header documentation
  byte-for-byte; both files MUST be edited in sync when a tier changes.

## Exposed identifiers

| Name | Type | Purpose |
|---|---|---|
| `__filelinelib_long_exts` | alternation string | Long-tier extension list (relaxed rule). |
| `__filelinelib_short_exts` | alternation string | Short-tier extension list (strict rule). |
| `__filelinelib_long_re` | extended-regex | Full match for long-tier extensions; bare `foo.go` accepted. |
| `__filelinelib_short_path_re` | extended-regex | Short-tier match requiring a path-likeness signal (`/`, `_`, `-`) in the stem. |
| `__filelinelib_short_line_re` | extended-regex | Short-tier match requiring a trailing `:line-ref`. |
| `__filelinelib_extensionless_re` | extended-regex | `Makefile` / `Dockerfile` / `GNUmakefile` match. |
| `__filelinelib_any_re` | extended-regex | Combined long-tier OR short-path OR short-line regex for one-shot grep. |

## Test coverage

- `scripts/test-validate-research-output.sh` — pins the consumer-side
  behavior of `validate-research-output.sh` after refactor; assertions
  against bare `foo.go` (long-tier accept), `notes.txt` standing alone
  (short-tier reject), `Cargo.lock:7` (short-tier accept via line-ref),
  `parser_state.h` (short-tier accept via path signal).
- `skills/research/scripts/test-validate-citations.sh` — pins the
  citation-extraction consumer; uses the same library to extract claims
  from synthesis prose under TDD fixtures.

## Edit-in-sync

When the tier rules change, update **all four** of:

1. This `.md` (the contract).
2. `scripts/file-line-regex-lib.sh` (the library body).
3. `scripts/validate-research-output.sh` header (the human-readable doc
   in the consumer's `--help` output).
4. The two test harnesses pinned above.

The `make lint` `test-validate-research-output` and
`test-validate-citations` targets run the harnesses and fail-fast on tier
drift between the library and either consumer.
