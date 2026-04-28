# skills/research/scripts/validate-citations.sh — Contract

Citation-credibility validator for `/research` Step 2.7. Reads a synthesis
report, extracts cited provenance (URL / DOI / file:line), and writes a
3-state ledger (PASS / FAIL / UNKNOWN with reason classifier) sidecar
markdown file.

## Argv

```
validate-citations.sh --report <path> --output <path> --tmpdir <path>
                      [--budget-seconds N] [--per-fetch-timeout N]
                      [--max-claims N]
```

| Flag | Required | Default | Purpose |
|---|---|---|---|
| `--report` | yes | — | input synthesis (`research-report.txt`) |
| `--output` | yes | — | output sidecar markdown (overwritten) |
| `--tmpdir` | yes | — | scratch dir for parallel fetch results |
| `--budget-seconds` | no | 300 | overall wall-clock budget |
| `--per-fetch-timeout` | no | 10 | per-curl HEAD timeout |
| `--max-claims` | no | 200 | soft DoS guard on extracted claim count |

## Exit code

Exit 0 for all fail-soft validation runs; exit 2 only for argument/flag
errors — operator or harness bug. Per-claim failures land in the sidecar
Status column.

## Stdout machine surface

The script's last stdout line is the summary the orchestrator parses:

```
SUMMARY=PASS=<n> FAIL=<n> UNKNOWN=<n> TOTAL=<n>
```

Test seam: `__VC_DRY_RUN=1` makes the script exit after extraction and
print extracted URLs / DOIs / file-line citations to **stderr** (one per
line per bucket) so harnesses can pin the regex extractor without making
network calls.

## Sidecar schema

```markdown
## Citation Validation

**Validator**: validate-citations.sh v1
**Synthesis**: <byte-count> bytes, <line-count> lines
**Claims extracted**: <total>
**Status counts**: <pass> PASS · <fail> FAIL · <unknown> UNKNOWN

| Claim | Type | Status | Reason | Cited by |
|---|---|---|---|---|
| `<excerpt>` | url | PASS |  |  |
| `<excerpt>` | doi | UNKNOWN | doi-unresolved |  |
| `<excerpt>` | file-line | FAIL | line-out-of-range |  |

<details><summary>Domain credibility (advisory only)</summary>

| Domain | Tier | Notes |
|---|---|---|
| ... | allow | well-known reputable origin |

</details>
```

`Type` is one of `url` / `doi` / `file-line`. `Status` is one of `PASS` /
`FAIL` / `UNKNOWN`. `Reason` is empty on `PASS` and a short token on
`FAIL` / `UNKNOWN`. The ledger rows are sorted for idempotency.

## Reason vocabulary

| Reason token | Status | Meaning |
|---|---|---|
| `non-https` | FAIL | URL did not start with `https://` |
| `curl-unavailable` | UNKNOWN | `curl` binary not found on PATH |
| `ssrf-private-host` | FAIL | URL host literal matched RFC1918 / IPv6 link-local / RFC6598 / loopback |
| `ssrf-private-resolved` | FAIL | DNS resolved to a private IP (any answer in a multi-answer set) |
| `head-not-found` | FAIL | HEAD returned 404 / 410 |
| `head-client-error-<code>` | FAIL | HEAD returned 4xx (excl. 403/404/405/410/501) |
| `head-server-error-<code>` | FAIL | HEAD returned 5xx |
| `head-not-supported` | UNKNOWN | HEAD returned 403 / 405 / 501 (some servers reject HEAD) |
| `redirect-not-followed` | UNKNOWN | HEAD returned 3xx; redirect destination not fetched (`--max-redirs 0`) |
| `timeout` | UNKNOWN | per-fetch or overall budget elapsed |
| `network-error` | UNKNOWN | curl exited non-zero (connection error, DNS failure) |
| `no-status-line` | UNKNOWN | curl exited 0 but `%{http_code}` was empty |
| `unrecognized-status-<code>` | UNKNOWN | curl returned a code outside 2xx-5xx |
| `doi-syntax` | FAIL | DOI does not match `^10\.[0-9]{4,9}/...` |
| `doi-unresolved` | UNKNOWN | DOI passed syntactic check but doi.org HEAD did not return PASS or a 3xx redirect (doi.org is a redirect resolver — a 3xx HEAD on `https://doi.org/<doi>` is the registry's success signal, so the DOI path interprets `UNKNOWN(redirect-not-followed)` as PASS) |
| `git-root-unavailable` | UNKNOWN | `git rev-parse --show-toplevel` failed (not a git tree) |
| `file-not-found` | FAIL | path does not exist relative to git root or cwd |
| `path-is-directory` | FAIL | resolved path is a directory, not a file |
| `out-of-tree-path-after-realpath` | UNKNOWN | realpath escaped the git root (`..`-traversal or symlink-escape) |
| `broken-symlink` | UNKNOWN | symlink resolved to a non-existent target |
| `line-range-empty` | FAIL | `start > end` in the cited range |
| `line-out-of-range` | FAIL | end of cited range exceeds file length |
| `parse-error` | UNKNOWN | result file content did not match the expected `STATUS=...` shape (bug indicator) |

The `UNKNOWN` bucket is deliberately broad: every transient or
environment-dependent failure ends there so the validator's strictness
scales with the operator's environment without false negatives skewing
the audit.

## SSRF defenses

Every `curl` invocation includes:

- `--max-redirs 0` — no redirect chain (so a 30x cannot lead to a private host)
- `--max-time <per-fetch-timeout>` — bounded fetch
- `--noproxy '*'` — bypass any environment proxy
- HTTPS-only — non-`https://` URLs are pre-rejected before the fork

In addition:

- **Hostname pre-rejection** for IPv4 RFC1918, IPv6 link-local (`fe80::*`)
  and unique-local (`fc00::/7`), RFC6598 shared-CGN (`100.64.0.0/10`),
  loopback (`127.0.0.0/8`, `::1`, `localhost`), and "this network"
  (`0.0.0.0/8`).
- **DNS resolution + private-range check** via `host` (preferred) or
  `nslookup` fallback. ANY answer in a multi-answer set being private
  fails closed (`FAIL(ssrf-private-resolved)`) — defense against DNS
  rebinding where one record is public to pass the check and another
  is private to direct the connection.
- **Connection pinning** via `--resolve <host>:443:<ip>` using the FIRST
  non-private resolved IP, so a TOCTOU rebinding (DNS answers re-randomized
  between check and connect) cannot escape the validated IP set.

## Curl flag MUST / MUST-NOT

**MUST** include: `--max-redirs 0`, `--max-time`, `--noproxy '*'`,
HTTPS URL last positional. **MUST NOT** include: `--insecure`, `-k`,
`--proxy`, `--socks*`, `--cacert`. The test harness pins this contract
via fake-curl argv assertions.

## Idempotency

Two consecutive runs against an unchanged `--report` produce a byte-identical
`--output`. Determinism comes from:

- Extracted URL / DOI / file-line lists deduplicated and sorted (`LC_ALL=C
  sort -u`).
- Ledger rows sorted (`LC_ALL=C sort -u`) before sidecar render.
- No timestamps in the body (the audit context lives in
  `research-report-final.md`'s prelude lines, not in this sidecar).
- Domain credibility rows in first-seen order (which mirrors URL sort
  order, so it is also deterministic).

## Process-group kill on budget exhaustion

When the overall `--budget-seconds` elapses, in-flight curl HEAD fetches
must be terminated cleanly. OS-specific:

- **Linux**: when `setsid` is available, `setsid` puts curl children in
  the script's session. The script self-execs into a new session if not
  already a session leader; `__VC_SETSID_DONE=1` is exported just before
  the `exec setsid` so the re-exec'd child inherits it (idempotency guard
  preventing infinite recursion) AND so the budget-exhaustion handler can
  use it as a "running in dedicated session" signal. A single `kill -- -$$`
  then signals every descendant. When `setsid` is unavailable, the re-exec
  is skipped, `__VC_SETSID_DONE` stays unset, and the budget-exhaustion
  handler falls back to per-PID `kill "$pid"` over `CURL_PIDS` — the
  validator runs in its caller's process group on this branch, so
  `kill -- -$$` would also signal the validator itself and break the
  fail-soft contract (issue #779). Orphan curl children on this fallback
  are bounded by `$PER_FETCH_TIMEOUT`.
- **macOS**: `set -m` (job control) places each backgrounded `fetch_url`
  subshell in its own process group with `pgid == $!`. The script records
  every `$!` in `CURL_PIDS` and on timeout runs `kill -- -<pid>` for each
  recorded PID, terminating the subshell + its curl substitution + any
  descendants together. `kill -- -$$` is **intentionally not** used as a
  fallback on this branch: with `set -m` active, `$$`'s process group
  contains the validator itself, so signaling it would kill the script
  before it writes the per-claim `UNKNOWN(timeout)` rows and the sidecar
  — i.e. exit 143, sidecar absent, fail-soft contract broken.

The test harness asserts the macOS branch via Test 20 (Darwin-only) using
a stub-curl fixture that hangs deliberately past the budget; the Linux
`setsid` branch is exercised end-to-end by the existing CI pipeline.

## Test seams (NOT operator flags)

| Env var | Purpose |
|---|---|
| `__VC_FAKE_CURL` | absolute path to a fake-curl shim (replaces real `curl` for argv pinning) |
| `__VC_SKIP_DNS` | skip real DNS resolution |
| `__VC_STUB_RESOLVE` | semicolon-separated `host=ip` pairs for fake resolution |
| `__VC_DRY_RUN` | exit after extraction; print extracted lists to stderr |
| `__VC_SETSID_DONE` | internal marker for the Linux `setsid` re-exec — set just before `exec setsid` so the re-exec'd child inherits it (idempotency guard preventing infinite recursion) AND the budget-exhaustion handler reads it as the "running in dedicated session" gate that authorizes `kill -- -$$` on Linux |

These are NOT documented in `--help` and MUST NOT be relied upon by
operators or callers — they are private to the test harness.

## Edit-in-sync surfaces

When this script's behavior changes:

1. This `.md` (the contract).
2. `validate-citations.sh` (the script body).
3. `skills/research/references/citation-validation-phase.md` (the phase
   reference; specifically the Reason vocabulary and SSRF defenses
   sections, which mirror the tables here).
4. `skills/research/scripts/test-validate-citations.sh` (regression harness).
5. `Makefile` `test-validate-citations` target.

## Test harness

`skills/research/scripts/test-validate-citations.sh` runs offline against
fixture inputs with stubbed curl and stubbed DNS. Verified scenarios:

- Provenance extraction (URL, DOI, file:line; LONG-tier and SHORT-tier
  per `scripts/file-line-regex-lib.sh`).
- SSRF rejections: `file://` URL, RFC1918 host literal, IPv6 link-local
  literal, RFC6598 host literal, hostname → private-range DNS,
  multi-answer DNS rebinding (one public + one private answer).
- Idempotency rerun (sidecar overwrite, byte-identical output).
- URL dedup (one fetch + one ledger row).
- Empty report (header + placeholder body, exit 0).
- Fake-curl argv MUST / MUST-NOT split assertions.
- Env `http_proxy=http://attacker.invalid/` set → `--noproxy '*'`
  blocks.
- `git rev-parse --show-toplevel` failure → all file:line UNKNOWN
  (`git-root-unavailable`).
- Realpath escape (`..`-traversal + symlink-escape) →
  `out-of-tree-path-after-realpath` / `broken-symlink`.
- HEAD 403/405/501 → `head-not-supported`.
- HEAD 3xx → `redirect-not-followed`.
- Darwin budget-exhaustion no-orphan-curl (Test 20, Darwin-only): a hanging
  fake-curl fixture is run with `--budget-seconds 1`; after the kill loop
  no fake-curl PID survives. Linux runners skip this assertion and rely on
  CI to exercise the `setsid` branch end-to-end.
