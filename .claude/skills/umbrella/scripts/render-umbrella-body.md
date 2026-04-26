# render-umbrella-body.sh — sibling contract

**Purpose**: compose the umbrella issue body from an LLM-supplied summary plus the resolved children TSV. Derive a one-line `UMBRELLA_TITLE_HINT` (≤80 chars, ellipsis on overflow) from the first sentence of the summary so `SKILL.md` Step 3B.3 can pass it to `/issue` as the title-deriving first line of the trailing description.

**CLI**: `--tmpdir DIR --summary-file FILE --children-file FILE`. All three required and non-empty.

**Children TSV format**: each row has exactly 3 tab-separated fields: `<number>\t<title>\t<url>`. Rows are validated; first field must be numeric. Any malformed row aborts with `ERROR=…`.

**Output**: writes `$TMPDIR/umbrella-body.md` (a markdown body with `## Summary` paragraph + `## Children` checklist using GitHub-native `- [ ] #<N> — <title>` rendering). Stdout: `UMBRELLA_BODY_FILE=<path>`, `UMBRELLA_TITLE_HINT=<derived>`.

**Exit codes**: `0` success; `1` invalid input.

**Edit-in-sync rules**: changes to children TSV format or output markdown shape require updating `SKILL.md` Step 3B.3 (which writes the TSV and forwards the body to `/issue`).
