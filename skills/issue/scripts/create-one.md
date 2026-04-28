# create-one.sh contract

**Purpose**: create a single GitHub issue with defensive guards (`[OOS]` double-prefix normalization, optional-label probe, dry-run preview), defense-in-depth secret redaction on title and body, and (since issue #546) capture of the issue's internal numeric `id` alongside its display number and URL on the success path.

**Label-existence probe**: implemented as `gh label list --repo "$REPO" --search "$L" --json name --jq '.[].name' | grep -Fqx -- "$L"`. The `-Fqx` flag set is load-bearing per issue #775 (unified grep -F doctrine): `-F` interprets `$L` as a fixed string (not a BRE), so a label name containing regex metacharacters like `bug.feature` or `release[2026]` cannot false-match a sibling label whose name happens to match the BRE interpretation; `-x` requires whole-line match (matches `gh`'s name-per-line output exactly); `-q` suppresses output. The previous `grep -qx -- "$L"` interpreted `$L` as a BRE — `bug.feature` would have falsely accepted `bug-feature` (`.` matches any char). Active-current-path concern: `/umbrella` forwards operator `--label` values verbatim through `/issue` to here, so labels with regex metacharacters are a live shipped-path input. Regression coverage: `scripts/test-redact-secrets.sh` section 4e exercises `bug.feature` and `release[2026]` against sibling labels that would have BRE-matched but must NOT fixed-string-match.

**Caller**: `/issue` SKILL.md Step 6 per-item iteration. Single-purpose helper — owns create semantics, output parsing, and redaction in one tested choke point.

**Output schema** (key=value on stdout):

| Field | When | Meaning |
|---|---|---|
| `ISSUE_NUMBER=<N>` | non-dry-run success | display number |
| `ISSUE_URL=<url>` | non-dry-run success | html_url for the created issue |
| `ISSUE_ID=<numeric-id>` | non-dry-run success | internal numeric id (used by `add-blocked-by.sh` POST body) |
| `ISSUE_TITLE=<title>` | success or dry-run | final title after `[OOS]` double-prefix normalization |
| `ISSUE_FAILED=true` | failure | helper failed; `ISSUE_ERROR` populated |
| `ISSUE_ERROR=<msg>` | failure only | flattened, redacted, capped at 500 chars |
| `DRY_RUN=true` | dry-run only | no API call; `DRY_RUN_TITLE` / `DRY_RUN_LABELS` / `DRY_RUN_BODY_PREVIEW` follow |

**`ISSUE_ID` is emitted only on the non-dry-run CREATE path.** The dry-run branch makes no API call, so there is no real id to fetch. Consumers must NOT assume `ISSUE_ID` is present alongside `DRY_RUN=true`.

**Capture strategy** (post-#546):

1. Try `gh issue create --json id,number,url` (modern gh CLI supports this — single round-trip captures all three fields). On success: parse the JSON via `jq`, emit `ISSUE_NUMBER` / `ISSUE_URL` / `ISSUE_ID` / `ISSUE_TITLE`, exit 0.
2. If `--json` is unsupported (older gh CLI — detected by stderr matching `unknown flag` / `unknown option` / `flag provided but not defined` near `--json`): fall back to plain `gh issue create` + a follow-up `gh api /repos/.../issues/$ISSUE_NUM --jq .id`. The fallback adds one round-trip and inherits the orphan-failure risk (issue created but id-lookup fails); /issue Step 6 handles this via `cleanup-failed-issue.sh` rollback, fail-closed by design.
3. Other failures (genuine API errors): redact stderr, emit `ISSUE_FAILED=true ISSUE_ERROR=<redacted>`, exit 2.

**gh CLI version requirement**: `gh issue create --json` requires gh CLI ≥ 2.27 (released April 2023). On older versions, the fallback path activates automatically. No explicit version probe in the script — the flag-not-recognized error is the trigger.

**Edit-in-sync rules**:

- The single-response `--json` capture is preferred over the fallback. Any change to the JSON field set requires updating both the success-path jq filter and the JSON-incomplete failure check.
- The fallback path's `gh api /repos/.../issues/$N --jq .id` is the second-best option; consumers (`/issue` Step 6) are expected to invoke `cleanup-failed-issue.sh` if it returns `ISSUE_FAILED=true` so an orphan issue does not persist on GitHub.
- The `[OOS]` double-prefix normalization, label probe, and redaction logic are unchanged from the pre-#546 contract. /issue's existing test coverage (`test-redact-secrets.sh`) continues to assert title/body redaction behavior; the new `ISSUE_ID` field is additive and does not require redaction (numeric integer from server response).
- Backward-compat: existing parsers that look for `ISSUE_NUMBER=` and `ISSUE_URL=` continue to work. Parsers that ignore unknown lines transparently absorb `ISSUE_ID=`.

**Test harness**: covered by `scripts/test-redact-secrets.sh` (existing) for the redaction-and-output-shape invariants. The new `ISSUE_ID` field is exercised indirectly via `test-add-blocked-by.sh` fixtures that simulate the create-one.sh stdout shape.

**Exit codes**: 0 on success (real or dry-run); 1 on usage error; 2 on API failure or JSON-incomplete; 3 on redaction-helper failure.
