# render-umbrella-body.sh — sibling contract

**Purpose**: compose the umbrella issue body from an LLM-supplied summary plus the resolved children TSV. Derive a one-line `UMBRELLA_TITLE_HINT` (≤80 chars, ellipsis on overflow) from the first sentence of the summary so `SKILL.md` Step 3B.3 can pass it to `/issue` as the title-deriving first line of the trailing description.

**CLI**: `--tmpdir DIR --summary-file FILE --children-file FILE`. All three required and non-empty. `--tmpdir` must additionally be **writable** by the current user — typically a session-private directory minted by the caller via `mktemp -d`. The script does NOT defend against concurrent renderers sharing the same `--tmpdir` (caller responsibility).

**Children TSV format**: each row has exactly 3 tab-separated fields: `<number>\t<title>\t<url>`. Rows are validated; first field must be numeric. Any malformed row aborts with `ERROR=…`.

**Output**: writes `$TMPDIR/umbrella-body.md` (a markdown body with `## Summary` paragraph + `## Children` checklist using GitHub-native `- [ ] #<N> — <title>` rendering). The body file write uses a **checked write + atomic rename** pattern: stage to an unpredictable `mktemp` partial under `$TMPDIR`, verify the partial is non-empty, reject pre-existing non-regular `$OUT` (so a caller-injected directory at the destination cannot make `mv` silently nest the partial inside it on BSD/macOS), then `mv` into place. Consumers see either the fully-written file or no file at all — no truncated intermediate state. An `EXIT` trap installed immediately after the staging `mktemp` succeeds also unlinks the partial on every error-exit path (empty staged body, pre-existing non-regular `$OUT`, `mv` failure), so the caller's `--tmpdir` does not accumulate `umbrella-body.md.*` partials across retries or CI reruns; on the success path the trap is a no-op because `mv` has already moved the partial. Stdout: `UMBRELLA_BODY_FILE=<path>`, `UMBRELLA_TITLE_HINT=<derived>`. Stdout success KVs are emitted ONLY past the `mv` gate — a failed body write produces a non-zero exit with `ERROR=…` on stderr and no `UMBRELLA_BODY_FILE=` / `UMBRELLA_TITLE_HINT=` lines.

**Exit codes**: `0` success; `1` on any of the documented `ERROR=` paths.

**`ERROR=` taxonomy** (stderr, paired with exit `1`):

- `ERROR=Unknown flag: <flag>` — unrecognized CLI flag.
- `ERROR=--tmpdir is required and must exist` — missing or non-existent `--tmpdir`.
- `ERROR=tmpdir not writable: <path>` — `--tmpdir` exists but is not writable by the current user.
- `ERROR=--summary-file is required and must be non-empty` — missing or empty `--summary-file`.
- `ERROR=--children-file is required and must be non-empty` — missing or empty `--children-file`.
- `ERROR=children.tsv malformed at line <N> (expected "<number><TAB><title><TAB><url>")` — children TSV row violates the 3-field-numeric-first contract.
- `ERROR=failed to write umbrella body: <path>` — could not stage the partial, or the staged partial was empty, or the atomic `mv` failed.

**Edit-in-sync rules**: changes to children TSV format or output markdown shape require updating `SKILL.md` Step 3B.3 (which writes the TSV and forwards the body to `/issue`). Changes to the `ERROR=` taxonomy or stdout grammar require updating the runtime conformance harness `test-render-umbrella-body.sh` so its assertions stay aligned.
