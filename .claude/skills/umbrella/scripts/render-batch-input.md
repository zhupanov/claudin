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

**Test coverage**: the malformed-`pieces.json` gatekeeper contract is pinned by `test-render-batch-input.sh` (sibling `test-render-batch-input.md`), wired into `make lint` via the `test-umbrella-render-batch-input` Makefile target. The harness pins TWO failure modes under the same `ERROR=invalid pieces.json: <reason>` stderr prefix + exit 1 contract: (a) JSON parse failure (unclosed brackets, garbage payloads), and (b) valid JSON whose top-level value is not an array (object root with ≥2 keys, string root, etc.) — both surface as the documented stable grammar instead of leaking jq's raw error and exit code. Per-entry shape validation (`title` / `body` / `depends_on`) is covered by integration via `SKILL.md` end-to-end runs — JSON-shape validation is dense enough that bad input is caught at the script boundary rather than leaking into `/issue`.
