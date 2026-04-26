# render-batch-input.sh — sibling contract

**Purpose**: convert an LLM-emitted `pieces.json` (an array of `{title, body, depends_on:[int,...]}`) into the markdown batch-input file consumed by `/issue --input-file`. Validates JSON shape (≥2 entries; each has non-empty `title` + `body`; each `depends_on` is an array of 1-based integers strictly less than the entry's index — i.e. only references earlier pieces).

**CLI**: `--tmpdir DIR --pieces-file FILE`. Both required; `--tmpdir` must exist and be writable; `--pieces-file` must be non-empty.

**Output**: writes `$TMPDIR/batch-input.md` (one `### <title>` block per piece followed by the body). Stdout grammar:
```
BATCH_INPUT_FILE=<absolute path>
PIECES_TOTAL=<N>
PIECE_<i>_TITLE=<title>           # i is 1-based, repeated for each piece
PIECE_<i>_DEPENDS_ON=<csv-of-ints> # may be empty
```

**Exit codes**: `0` success; `1` invalid input (`ERROR=…` on stderr).

**Dependencies**: `jq` is required (matches the rest of the larch toolchain — `/issue` already requires `jq`).

**Edit-in-sync rules**: any change to the `pieces.json` schema OR the markdown output shape OR stdout grammar requires a same-PR update to `SKILL.md` Step 3B.1 (which writes `pieces.json` and parses the stdout) and `/issue`'s batch-mode parser at `skills/issue/scripts/parse-input.sh` (which consumes the markdown).

**Test coverage**: the malformed-`pieces.json` gatekeeper contract is pinned by `test-render-batch-input.sh` (sibling `test-render-batch-input.md`), wired into `make lint` via the `test-umbrella-render-batch-input` Makefile target. The harness pins FOUR failure modes at the script boundary: (a) JSON parse failure (unclosed brackets, garbage payloads) under the `ERROR=invalid pieces.json: <reason>` stderr prefix + exit 1 contract; (b) valid JSON whose top-level value is not an array (object root with ≥2 keys, string root, etc.) under the same `ERROR=invalid pieces.json:` prefix; (c) per-entry `depends_on` containing a non-integer number (e.g. `[1.5]`) under the `ERROR=pieces.json entry <i> has out-of-range depends_on values:` prefix + exit 1 — pinned by case 7, closes #647; and (d) per-entry `title` containing an embedded LF under the `ERROR=pieces.json entry <i> title contains embedded newline` prefix + exit 1 — pinned by case 9, closes #648. Without the case-(d) guard, a multi-line `title` would later be emitted via `printf 'PIECE_<i>_TITLE=%s\n' "$title"` and split one logical KV into multiple physical stdout lines, silently breaking the one-KV-per-line grammar that `umbrella` SKILL.md Step 3B.1 parses. The remaining per-entry shape validation (`title` / `body` non-empty) is covered by integration via `SKILL.md` end-to-end runs.

**Single-line stdout free-text fields (which are guarded, which are exempt)**: only `title` is emitted as a `KEY=value` stdout line that carries free-text from `pieces.json` (`PIECE_<i>_TITLE=<title>`); the case-(d) guard rejects embedded LF on this field. `body` is exempt — it flows into the markdown output file (`### <title>` heading, then body) where multi-line content is allowed by the markdown grammar. `depends_on` is exempt — it is emitted as `PIECE_<i>_DEPENDS_ON=<csv>` but is built by `jq` from values already validated as integers in `[1, idx]` (per the `bad_deps` predicate), so structurally cannot contain newlines. `BATCH_INPUT_FILE` and `PIECES_TOTAL` are script-owned values, not `pieces.json`-derived. **Residual gap**: the case-(d) guard rejects only LF (`\n`); CR-only (`\r`), Unicode line separators (U+2028 / U+2029), and other line-break code points are NOT rejected. Downstream consumers that treat stdout as strictly line-oriented should rely on the documented "no embedded LF" guarantee — broader sanitization is out of scope for #648.
