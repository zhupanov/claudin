# parse-args.sh — sibling contract

**Purpose**: parse `/umbrella`'s flag surface and emit a stable KV stdout grammar that `SKILL.md` Step 0 consumes. Owns creation of `$UMBRELLA_TMPDIR` (via `mktemp -d`) so Step 5's cleanup has a single owner. Single positional argument is the entire `$ARGUMENTS` string.

**Stdout grammar** — exactly these keys, in this order, one per line:

```
LABELS=<newline-joined labels — empty if none>
TITLE_PREFIX=<prefix string — empty if none>
REPO=<owner/repo — empty if not specified>
CLOSED_WINDOW_DAYS=<integer — empty if not specified>
DRY_RUN=<true|false>
GO=<true|false>
DEBUG=<true|false>
TASK=<everything after the last flag — may be empty; preserves embedded whitespace>
UMBRELLA_TMPDIR=<absolute path — newly-created mktemp dir>
```

**Flag spec**: `--label LABEL` (repeatable, accumulates into `LABELS`), `--title-prefix PREFIX`, `--repo OWNER/REPO`, `--closed-window-days N` (validated as non-negative integer), `--dry-run`, `--go`, `--debug`. `--` is supported as an explicit end-of-flags marker. Any unknown `--flag` aborts with `ERROR=Unknown flag: …`.

**Exit codes**: `0` success; `1` parse failure (`ERROR=…` on stderr).

**Edit-in-sync rules**: any change to flag set OR stdout grammar OR `UMBRELLA_TMPDIR` ownership requires a same-PR update to `SKILL.md` Step 0 (which parses the grammar) and Step 5 (which removes the tmpdir).

**Test harness**: covered indirectly via SKILL.md integration; no dedicated harness — flag parsing is a thin shim and breakage surfaces immediately on any `/umbrella` invocation.
