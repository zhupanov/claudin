# Citation Validation Phase Reference

**Consumer**: `/research` Step 2.7 — loaded via the `MANDATORY — READ ENTIRE FILE` directive at Step 2.7 entry in SKILL.md.

**Contract**: scale-agnostic citation-credibility check. Runs unconditionally on every `/research` invocation that produced a `research-report.txt` (every scale: `quick`/`standard`/`deep`), executing between Step 2.5 (adjudication) and Step 3 (final report). The phase reads the validated synthesis at `$RESEARCH_TMPDIR/research-report.txt`, extracts cited provenance (file:line, URL, DOI), HEAD-fetches each unique URL with bounded timeout in parallel under SSRF guards (HTTPS-only, `--max-redirs 0`, `--noproxy '*'`, RFC1918/IPv6 link-local/RFC6598 hostname pre-rejection, DNS resolved-IP private-range check via `host`→`nslookup` fallback chain, connection-pinning via `--resolve` to mitigate rebinding TOCTOU), classifies domain credibility heuristically (advisory only — never flips PASS to FAIL), validates DOIs syntactically + via `HEAD https://doi.org/<doi>` under the same SSRF rules, spot-checks file:line existence + line-range against `git rev-parse --show-toplevel` with `realpath` canonical-path containment check, and writes a 3-state per-claim ledger (`PASS` / `FAIL` / `UNKNOWN` with reason classifier on `UNKNOWN`) to `$RESEARCH_TMPDIR/citation-validation.md` (sidecar). Step 3 splices the sidecar as a `## Citation Validation` section into `research-report-final.md` after the standard report block. **Fail-soft**: per-claim failures surface as warnings only; the validator script always exits 0; Step 3 is never blocked.

**When to load**: once Step 2.7 is about to execute. Do NOT load during Step 0, Step 1, Step 2, Step 2.5, Step 3, or Step 4. SKILL.md emits the Step 2.7 entry breadcrumb and the Step 2.7 completion print; this file does NOT emit those — it owns body content only.

---

## Step 2.7 — Citation Validation

**IMPORTANT: Citation validation runs unconditionally on every scale that produced a synthesis. The phase is fail-soft: every per-claim failure is recorded in the sidecar; the validator exits 0; Step 3 never blocks on this phase. Domain credibility is advisory only — it never flips a `PASS` to `FAIL`. Quick mode runs the same validation against its single-lane synthesis output as standard/deep — there is no scale-specific skip path.**

### 2.7.1 — Skip preconditions (input gate)

Evaluate the two skip conditions in this order — matching `SKILL.md` Step 2.7's emission order. Each condition has a distinct downstream branch and they must not be conflated.

**Budget-abort gate (evaluated FIRST → proceed to Step 4).** If `BUDGET_ABORTED=true` (set by any of the budget gates after Steps 1, 2, or 2.5): skip Step 2.7 entirely and proceed directly to Step 4 (Step 3 was already skipped by the abort path). Print:

```
⏩ 2.7: citation-validation — skipped (--token-budget aborted upstream) (<elapsed>)
```

The shell validator does not consume measurable Claude tokens, but skipping it on a budget-aborted run preserves the "Step 3 skipped" semantics of the abort path (Step 3 is not rendered, so a sidecar splice has no consumer).

**Empty-synthesis gate (evaluated SECOND → proceed to Step 3).** If `$RESEARCH_TMPDIR/research-report.txt` does not exist OR is empty (zero bytes), skip Step 2.7 entirely and proceed to Step 3. Print:

```
⏩ 2.7: citation-validation — skipped (no synthesis to validate) (<elapsed>)
```

The empty-synthesis path is reachable when (a) Step 1 inline-fallback synthesis failed and produced no body, or (b) a prior step's tmpdir cleanup left an empty placeholder. Neither warrants a citation pass. (`BUDGET_ABORTED=true` is handled by the budget-abort gate above and never reaches this branch — the two skip conditions have different downstream targets and must stay separate.)

### 2.7.2 — Invoke the validator

Invoke the scale-agnostic shell validator (it owns argv/curl-flag/SSRF/regex contracts):

```bash
${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/validate-citations.sh \
  --report "$RESEARCH_TMPDIR/research-report.txt" \
  --output "$RESEARCH_TMPDIR/citation-validation.md" \
  --tmpdir "$RESEARCH_TMPDIR"
```

The script writes the sidecar to the path passed via `--output` and exits 0 on every path (fail-soft contract). On any internal error (curl missing, git rev-parse failure, etc.), the script writes a minimally-formed sidecar that explains the degraded path and still exits 0 — Step 3's splice consumer must always have a sidecar to read.

See `${CLAUDE_PLUGIN_ROOT}/skills/research/scripts/validate-citations.md` for the full contract (argv, exit codes, sidecar schema, SSRF defenses, regex tiers, idempotency rerun semantics, budget-exhaustion process-group kill — Linux `setsid` + single `kill -- -$$`, macOS `set -m` + per-background `kill -- -<pid>` with no `kill -- -$$` fallback because that would self-signal the validator).

### 2.7.3 — Sidecar schema

The sidecar is an operator-readable Markdown document. The single source of truth lives in `validate-citations.md` § Sidecar Schema; the structural shape is:

```markdown
## Citation Validation

**Validator**: validate-citations.sh v1
**Synthesis**: <byte-count> bytes, <line-count> lines
**Claims extracted**: <total>
**Status counts**: <pass> PASS · <fail> FAIL · <unknown> UNKNOWN

| Claim | Type | Status | Reason | Cited by |
|---|---|---|---|---|
| `<excerpt>` | url | PASS |  |  |
| `<excerpt>` | doi | UNKNOWN | head-not-supported |  |
| `<excerpt>` | file-line | FAIL | line-out-of-range |  |

<details><summary>Domain credibility (advisory only)</summary>

| Domain | Tier | Notes |
|---|---|---|
| ...  | allow | well-known reputable origin |
| ...  | unknown | no allow-list entry; classification heuristic only — NOT a FAIL signal |

</details>
```

`Status` is one of `PASS` / `FAIL` / `UNKNOWN`. `Reason` is empty on `PASS` and a short token on `FAIL` / `UNKNOWN` per `validate-citations.md` § Reason vocabulary. URL and DOI claims are deduplicated — a single fetch produces one ledger row. The `Cited by` column is reserved for a future enhancement that will list every claim-index reference (`claim-<N>` matching the synthesis-walk index); v1 of the validator emits an empty `Cited by` cell while preserving the 1:1 fetch-to-row contract. Operators inspecting the sidecar can grep the synthesis directly for now.

### 2.7.4 — Idempotency rerun

The sidecar path (`--output`) is overwritten on every invocation. Two consecutive runs against an unchanged synthesis MUST produce byte-identical sidecars (deterministic stdout ordering, no timestamps in the body — the audit-context line is captured externally by the orchestrator's prelude prints). Operators can re-invoke the validator against the same `$RESEARCH_TMPDIR/research-report.txt` to re-validate after a transient network failure without polluting the audit trail.

### 2.7.5 — Failure surfaces

Per-claim failures are written into the sidecar's `Status` column. The orchestrator does NOT print per-claim failures to stdout; instead, the Step 2.7 completion line summarizes:

```
✅ 2.7: citation-validation — <pass> PASS, <fail> FAIL, <unknown> UNKNOWN (<total> claims) (<elapsed>)
```

When `<fail> > 0` OR `<unknown> > 0`, ALSO print one of these advisory warnings (not errors — fail-soft contract):

- `<fail> > 0`: `**⚠ 2.7: citation-validation — <fail> claim(s) FAILED. See ## Citation Validation in the report.**`
- `<unknown> > 0` (regardless of `<fail>`): `**ℹ 2.7: citation-validation — <unknown> claim(s) UNKNOWN. Common reasons: HEAD not supported (try GET manually), DNS resolution unavailable, git tree not detected. See ## Citation Validation in the report.**`

The script's stdout summary (parsed by the orchestrator from the validator's last line `SUMMARY=PASS=<n> FAIL=<n> UNKNOWN=<n> TOTAL=<n>`) drives both the completion line and the conditional warnings.

### 2.7.6 — Step 3 splice contract

Step 3 (final-report write) is the sole consumer of the sidecar. After writing the report block to `research-report-final.md` and BEFORE the helper-driven sidecar generation (`render-findings-batch.sh`), Step 3:

1. Checks `$RESEARCH_TMPDIR/citation-validation.md` exists and is non-empty.
2. Appends the sidecar's full content to `research-report-final.md` with a single blank line separator. The sidecar already opens with `## Citation Validation` so no extra header is added.
3. On missing or empty sidecar (Step 2.7 was skipped per § 2.7.1): no splice, no warning. The skip breadcrumb at Step 2.7 already informed the operator.

The splice happens BEFORE `cat`-ing the report for user-visible output, so the final report displayed to the operator includes the citation-validation section.

### Why a separate phase, not a 6th Step 2 reviewer

Per the design dialectic on issue #516 DECISION_1 (resolved via the plan-review panel's 2-1 sidecar vote, user-confirmed at Step 3.5 round 2), Step 2.7 is a separate phase that writes a sidecar — NOT a 6th reviewer added to Step 2's validation panel. Phase separation:

1. Keeps Step 2's voting machinery focused on the synthesis content and accept/reject votes; citation validation has no vote — it is mechanical.
2. Lets the validator be a deterministic shell script with no LLM call, costing zero measurable Claude tokens (parallel to Step 0.5's classifier).
3. Keeps the validator failure mode local — a transient network failure during URL HEAD-fetch surfaces as `UNKNOWN(network-error)` rows in the sidecar, NOT as a vote-skewing reviewer fallback.

### Composition with `--token-budget`

The validator does not consume measurable Claude subagent tokens (it is a shell script invocation; Bash is unmeasurable per the `RESEARCH_TOKEN_BUDGET` contract in SKILL.md). Step 2.7 therefore has no budget gate of its own — the post-Step-2.5 budget gate is the last enforcement point before Step 3.

### Composition with `--keep-sidecar`

`--keep-sidecar` preserves the **`/issue`-batch** sidecar (`research-findings-batch.md`), NOT the citation-validation sidecar. The citation-validation sidecar is spliced into `research-report-final.md` (which the operator already sees on stdout); it is removed by Step 4's `cleanup-tmpdir.sh` along with the rest of `$RESEARCH_TMPDIR`. Operators wanting a long-lived audit trail of citation validation should preserve the printed report.

### Failure modes and fail-soft posture

The validator script always exits 0. Failure modes that would otherwise abort a strict validator are reclassified into `UNKNOWN` reasons in the per-claim ledger:

| Failure mode | Sidecar reason |
|---|---|
| `curl` binary missing | `UNKNOWN(curl-unavailable)` for every URL/DOI claim |
| `git rev-parse --show-toplevel` fails (not a git tree) | `UNKNOWN(git-root-unavailable)` for every file:line claim |
| Hostname pre-rejected by RFC1918/IPv6 link-local/RFC6598 rules | `FAIL(ssrf-private-host)` |
| DNS resolves to a private IP range | `FAIL(ssrf-private-resolved)` |
| Multi-answer DNS where ANY answer is private (rebinding defense) | `FAIL(ssrf-private-resolved)` |
| HEAD returns 4xx/5xx that does not indicate non-support (e.g., 404, 410) | `FAIL(head-not-found)` for 404/410; `FAIL(head-server-error)` for ≥500 |
| HEAD returns 403/405/501 | `UNKNOWN(head-not-supported)` (some servers reject HEAD; an optional constrained GET retry MAY upgrade to PASS — see `validate-citations.md`) |
| HEAD 2xx response inside per-fetch timeout window | `PASS` |
| HEAD 3xx response inside per-fetch timeout window | `UNKNOWN(redirect-not-followed)` (redirect destination not fetched; `--max-redirs 0`) |
| HEAD response after timeout (per-claim or overall budget) | `UNKNOWN(timeout)` |
| Realpath escape (`..`-traversal or symlink-escape outside repo root) | `UNKNOWN(out-of-tree-path-after-realpath)` |
| Broken symlink on the resolved path | `UNKNOWN(broken-symlink)` |
| File exists but the cited line range exceeds the file length | `FAIL(line-out-of-range)` |
| File exists, line range valid, but range is empty (start > end) | `FAIL(line-range-empty)` |
| DOI fails syntactic validation (e.g., not `10.NNNN/...`) | `FAIL(doi-syntax)` |
| DOI is syntactically valid but doi.org HEAD does not resolve to a permanent URL | `UNKNOWN(doi-unresolved)` (a 3xx HEAD on `https://doi.org/<doi>` IS the registry's success signal — the DOI path interprets `UNKNOWN(redirect-not-followed)` as PASS, not as `doi-unresolved`) |

The `UNKNOWN` bucket is deliberately broad: every transient or environment-dependent failure ends there so the validator's strictness scales with the operator's environment without false negatives skewing the audit.

### Process-group kill semantics for budget exhaustion

When the overall validator budget elapses (`--budget-seconds`, default 300), in-flight curl HEAD fetches MUST be terminated cleanly — orphaned curl processes can outlive the validator and skew network telemetry. Linux supports `setsid` directly (the script self-execs into a new session if not already a session leader, then a single `kill -- -$$` sweeps every descendant). macOS `setsid` is non-portable, so the script enables `set -m` (job control) which places each backgrounded `fetch_url` subshell in its own process group; on timeout the script signals each recorded `$!` via `kill -- -<pid>` (terminating the subshell + curl substitution + descendants together). `kill -- -$$` is **not** used as a Darwin fallback: with `set -m` active, `$$`'s process group still contains the validator itself, so signaling it would kill the script before it writes the per-claim `UNKNOWN(timeout)` rows and the sidecar — exit 143, sidecar absent, fail-soft contract broken. The OS detection branch lives in `validate-citations.sh`; the macOS path is asserted by Test 20 in `test-validate-citations.sh` (Darwin-only — Linux runners print a skip note and rely on the existing CI pipeline to exercise the `setsid` branch end-to-end).

### Curl-flag MUST / MUST-NOT contract

Every curl invocation in `validate-citations.sh` MUST include `--max-redirs 0`, `--max-time <per-fetch>`, `--noproxy '*'`, AND HTTPS-only enforcement (the URL passed as the last positional argument MUST start with `https://`). MUST-NOT include `--insecure`, `-k`, `--proxy`, `--socks*`, `--cacert` — these would weaken the SSRF posture. The test harness pins this via fake-curl argv assertions; a future edit that adds `--insecure` for "local-CA convenience" fails the harness immediately.

### Domain-credibility heuristic (advisory only)

A small allow-list of widely-recognized reputable hosts (e.g., `*.wikipedia.org`, `*.arxiv.org`, `*.acm.org`, `*.ietf.org`, `doi.org`, `github.com`, `*.python.org`, `*.rust-lang.org`) tags matching domains as `allow` in the credibility table. Other domains are tagged `unknown`. The credibility tier NEVER flips a claim's primary status (`PASS` stays `PASS` even for an `unknown` domain). The operator allow-list flag (`--trusted-domains=`) is deferred to issue #514 — that flag will, when shipped, expand the heuristic into operator-supplied policy.

### Step 2.7 → Step 3 control-flow summary

```
2.7 entry breadcrumb (SKILL.md)
  → § 2.7.1 input gates (evaluated in order):
      1. budget-abort gate → skip 2.7 → Step 4 (Step 3 was already skipped)
      2. empty-synthesis gate → skip 2.7 → Step 3
    → § 2.7.2 validator invocation (always exits 0)
    → § 2.7.5 completion line + conditional advisory warnings
  → Step 3 splice (§ 2.7.6) appends sidecar to research-report-final.md
  → Step 3 cat displays the spliced report to stdout
```
