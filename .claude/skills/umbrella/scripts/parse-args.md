# parse-args.sh — sibling contract

**Purpose**: parse `/umbrella`'s flag surface and emit a stable `KEY=VALUE` stdout grammar that `SKILL.md` Step 0 consumes. Owns creation of `$UMBRELLA_TMPDIR` (via `mktemp -d`) so Step 5's cleanup has a single owner. Single positional argument is the entire `$ARGUMENTS` string.

**Locale**: `parse-args.sh` pins `LC_ALL=C` at the top so `${var:offset:1}` and `${#var}` substring/length operations are byte-deterministic regardless of caller `LC_ALL` / `LANG`. Flag values are expected to be ASCII; non-ASCII bytes are passed through verbatim but offset semantics are bytes, not characters.

**Stdout grammar** — exactly these keys, in this order, one KV per line:

```
LABELS_COUNT=<integer ≥ 0>
LABEL_1=<value>
LABEL_2=<value>
...
LABEL_<LABELS_COUNT>=<value>
TITLE_PREFIX=<prefix string — empty if none>
REPO=<owner/repo — empty if not specified>
CLOSED_WINDOW_DAYS=<integer — empty if not specified>
DRY_RUN=<true|false>
GO=<true|false>
DEBUG=<true|false>
TASK=<verbatim remainder of $ARGS_STR after the flag prefix — may be empty; preserves embedded whitespace AND any quote/escape characters>
UMBRELLA_TMPDIR=<absolute path — newly-created mktemp dir>
```

**Consumer-side parsing rule**: each line is a `KEY=VALUE` pair. Consumers MUST split each line on the **first** `=` only — values may contain literal `=` characters (e.g., `LABEL_1=priority=high` is one label whose value is `priority=high`).

When `LABELS_COUNT=0`, no `LABEL_*` lines are emitted (the `LABEL_<i>` block is empty).

**Flag spec**:
- `--label LABEL` — repeatable; appends to the indexed `LABEL_<i>` list.
- `--title-prefix PREFIX` — single value.
- `--repo OWNER/REPO` — single value.
- `--closed-window-days N` — non-negative integer; validated.
- `--dry-run` / `--go` / `--debug` — booleans (default `false`; presence sets `true`).
- `--` — explicit end-of-flags marker; subsequent text is TASK verbatim.
- Any unknown `--flag` aborts with `ERROR=Unknown flag: <flag>`.

**Quoting subset** (phase-1 flag-prefix lexer only — phase 2 TASK is verbatim):
- **Double quotes** (`"..."`): the lexer recognizes `\"`, `\\`, `\$` as escape sequences (the `\` is consumed; the next char is literal). Any other `\X` inside double quotes is preserved as the literal two-character sequence `\X`. Literal newline bytes inside the run are rejected.
- **Single quotes** (`'...'`): no escape processing — every byte until the next `'` is literal. Literal newline bytes inside the run are rejected.
- **Outside quotes**: backslash escapes the next character (`\<c>` → literal `<c>`). Stray trailing backslash is rejected.
- **Whitespace separators outside quotes**: space, tab, newline.

**TASK contract**: TASK is the verbatim remainder of `$ARGS_STR` from a recorded byte offset to end-of-string. Phase 1 stops at the first non-flag-looking token (or after a bare unquoted `--`); the byte offset is the first character of that next token (NOT including any preceding separator whitespace). Phase 2 slices `${ARGS_STR:offset}` and emits it AS-IS — no quote handling, no escape processing, no validation. Unbalanced quotes inside TASK are not lexer errors. Embedded multi-space runs and trailing whitespace are preserved.

**Frozen ERROR= templates** (the harness keys off these exact substrings):

```
ERROR=--label requires a value
ERROR=--title-prefix requires a value
ERROR=--repo requires a value
ERROR=--closed-window-days requires a value
ERROR=--closed-window-days must be a non-negative integer; got '<value>'
ERROR=Unknown flag: <flag>
ERROR=unclosed double quote at offset <N>
ERROR=unclosed single quote at offset <N>
ERROR=stray backslash at end of input
ERROR=embedded newline in quoted value at offset <N>
```

**Exit codes**: `0` success; `1` parse failure (one `ERROR=...` line on stderr).

**Edit-in-sync rules**: any change to flag set OR stdout grammar OR the frozen ERROR= list OR the quoting subset OR `UMBRELLA_TMPDIR` ownership requires a same-PR update to `SKILL.md` Step 0 (which parses the grammar) and Step 5 (which removes the tmpdir). The harness `test-umbrella-parse-args.sh` keys off the frozen ERROR= templates and stdout shape — update it in lockstep.

**Test harness**: `.claude/skills/umbrella/scripts/test-umbrella-parse-args.sh` (sibling `test-umbrella-parse-args.md`); wired into `make lint` via the `test-umbrella-parse-args` Makefile target alongside `test-umbrella-helpers`.
