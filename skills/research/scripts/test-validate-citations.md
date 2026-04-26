# skills/research/scripts/test-validate-citations.sh — Contract

Offline regression harness for `validate-citations.sh`. Pins the consumer-side
behavior of the citation validator under fail-soft semantics: every scenario
asserts (a) exit 0, (b) sidecar created at the configured path, (c) the
`SUMMARY=...` line on stdout has the expected counts, (d) where applicable,
the sidecar body contains the expected `Status` / `Reason` tokens.

## What it pins

| Scenario | Assertion target |
|---|---|
| Empty synthesis (no claims) | exit 0 + `SUMMARY=PASS=0 FAIL=0 UNKNOWN=0 TOTAL=0` + sidecar header |
| Provenance extraction | dry-run seam emits URLs / DOIs / file:line to stderr |
| Idempotency rerun | byte-identical sidecar across two consecutive runs |
| HTTPS-only enforcement | `http://` URL → `FAIL(non-https)` row |
| RFC1918 host literal | `https://10.0.0.1/...` → `FAIL(ssrf-private-host)` |
| DNS resolved to private IP | stub-resolved private IP → `FAIL(ssrf-private-resolved)` |
| Multi-answer DNS rebinding | mixed public+private answers → `FAIL(ssrf-private-resolved)` |
| HEAD 403 / 501 mapping | both return `UNKNOWN(head-not-supported)` |
| HEAD 404 mapping | returns `FAIL(head-not-found)` |
| HEAD 301 mapping | returns `UNKNOWN(redirect-not-followed)` |
| Curl argv MUST / MUST-NOT | `--max-redirs`, `--max-time`, `--noproxy`, HTTPS URL last; absent: `--insecure`, `-k`, `--proxy`, `--socks*`, `--cacert` |
| Hostile `http_proxy` env | `--noproxy '*'` still in argv |
| File:line PASS (existing) | `AGENTS.md:1` → `PASS` |
| File:line line-out-of-range | `AGENTS.md:99999` → `FAIL(line-out-of-range)` |
| File:line file-not-found | non-existent path → `FAIL(file-not-found)` |
| Git-root-unavailable | non-git cwd → `UNKNOWN(git-root-unavailable)` |
| DOI syntax | malformed `10.123/...` (3 digits) → not extracted (regex tier) |
| URL dedup | duplicate URL appears in exactly one ledger row |
| Darwin budget exhaustion (Test 20, Darwin-only) | hung fake-curl + `--budget-seconds 1` → exit 0, sidecar present with `UNKNOWN`/`timeout` rows for hung URLs, no surviving fake-curl PIDs after kill loop. Linux runners skip and rely on the existing CI pipeline to exercise the `setsid` branch end-to-end. |

## Test seams (env vars exercised by the harness)

| Var | Effect on `validate-citations.sh` |
|---|---|
| `__VC_FAKE_CURL` | replaces real `curl` for argv pinning + scripted HTTP codes per URL pattern |
| `__VC_LAST_ARGV` | absolute path the fake-curl shim writes argv records to |
| `__VC_SKIP_DNS` | skip real DNS resolution |
| `__VC_STUB_RESOLVE` | `host=ip;host=ip;...` for fake resolution |
| `__VC_DRY_RUN` | exit after extraction; print extracted lists to stderr |

## Edit-in-sync

When this harness changes:

1. This `.md` (the contract).
2. `test-validate-citations.sh` (the harness body).
3. `Makefile` `test-validate-citations` target if a new fixture file is added
   to the test invocation.
4. `validate-citations.md` § Test harness (the contract's mirrored summary
   in the validator's sibling contract).

## Wiring

`make lint` invokes this harness via the `test-validate-citations` target,
which is a prerequisite of `test-harnesses`. The harness exits non-zero on
any assertion failure; CI fails the same way.
