# write-sentinel.sh

`skills/issue/scripts/write-sentinel.sh` writes the `/issue` post-success sentinel KV file atomically. Called from `/issue` Step 7 after aggregate counters have been emitted on stdout. The sentinel is the load-bearing mechanical signal a parent skill (e.g. `/research`'s `## Filing findings as issues` numbered procedure) reads via `${CLAUDE_PLUGIN_ROOT}/scripts/verify-skill-called.sh --sentinel-file` to confirm the child completed before continuing — defense in depth on top of stdout parsing of `ISSUES_*` counters.

## Gate

Write the sentinel only when `ISSUES_FAILED=0` AND `--dry-run` is NOT set. The sentinel proves **execution**, not **creation count**: the all-dedup case (`ISSUES_CREATED=0`, `ISSUES_DEDUPLICATED>=1`, `ISSUES_FAILED=0`) DOES write the sentinel — that is a legitimate `/issue` success outcome, and gating on `ISSUES_CREATED>=1` would create a false-failure mode in `/research` (issue #509 plan review FINDING_1; the original issue body's stricter gate was overruled by review). Counters are recorded inside the sentinel so downstream consumers can still distinguish all-create vs all-dedup vs mixed outcomes if they care.

Partial-failure (`ISSUES_FAILED>=1`) suppresses the sentinel by design: this is fail-closed for `/research` — research-result-filing semantics require all items to succeed; partial failure is operator-investigation territory. Operators wanting partial-recovery inspect per-item `ISSUE_<i>_FAILED=true` lines on stdout.

## Atomicity

Writes the full content to a same-directory `mktemp`, then `mv` to the final path. Same pattern as `scripts/write-session-env.sh`. The `mv` is atomic on a single filesystem, so the target path is either the complete final content or absent — never partial. If the helper crashes mid-`mv` the temp file is left orphaned in the same directory but the target path is never half-written.

This is **rename-atomicity**, not durability — the script does NOT call `fsync(2)`. A host crash before the kernel flushes the dirty page cache could lose the rename. That is acceptable for this signal because the parent runs in the same session as the child: a host crash mid-run discards both processes (#509 review FINDING_1).

## Channel discipline

All status output goes to **stderr**, not stdout. `/issue` Step 7's published stdout grammar is `^(ISSUES?_[A-Z0-9_]+)=(.*)$`; this helper preserves that contract for downstream parsers like `/implement` Step 9a.1 (issue #509 plan review FINDING_5). Argument errors (caller misuse) emit `ERROR=<msg>` to stderr and exit 1.

## Usage

```bash
write-sentinel.sh --path <path> \
                  --issues-created <N> \
                  --issues-deduplicated <N> \
                  --issues-failed <N> \
                  [--dry-run]
```

`--path` must be absolute and must not contain `..`. Counter args must be non-negative integers. `--dry-run` is a boolean flag (presence-only), forwarded explicitly from `/issue`'s argument parse — do not infer dry-run from counters because `/issue` Step 6 conceptually counts dry-run as `ISSUES_CREATED+=1` (issue #509 plan review FINDING_1 sub-concern).

## Outputs

### Stderr (KV)

- `WROTE=true` — sentinel file written successfully.
- `WROTE=false REASON=dry_run` — `--dry-run` was set, sentinel suppressed.
- `WROTE=false REASON=failures` — `ISSUES_FAILED >= 1`, sentinel suppressed.
- `ERROR=<msg>` — argument error (caller misuse). Exit 1.

### Sentinel content (KV at `<path>`)

```
ISSUE_SENTINEL_VERSION=1
ISSUES_CREATED=<N>
ISSUES_DEDUPLICATED=<N>
ISSUES_FAILED=<N>
TIMESTAMP=<ISO 8601 UTC>
```

`ISSUE_SENTINEL_VERSION=1` allows future format changes without silent mis-parse.

## Exit codes

- `0` — always for the gate paths (skipped-on-dry-run, skipped-on-failures, written). Skipped is normal.
- `1` — argument error (missing required flags, non-absolute path, `..` in path, non-numeric counters).

## Lifecycle

The parent that supplied `--path` (via `/issue --sentinel-file <path>`) owns the sentinel's lifecycle and is expected to clean it up when its session tmpdir is removed. When `/issue` is invoked WITHOUT an explicit `--sentinel-file`, it uses a child-local default path and removes the sentinel itself in Step 9 cleanup (issue #509 plan review FINDING_3 fix — prevents `/tmp` accumulation for callers that don't opt in).

## Test harness

Regression coverage at `skills/issue/scripts/test-sentinel-write.sh` (sibling `test-sentinel-write.md`). Wired into `make lint` via the `test-sentinel-write` target. Cases covered:

- (a) all-success → sentinel written with all 5 keys.
- (b) all-dedup (CREATED=0, FAILED=0) → sentinel **written** (proves execution per FINDING_1).
- (c) partial-failure (FAILED>=1) → no write; stderr `WROTE=false REASON=failures`.
- (d) dry-run → no write; stderr `WROTE=false REASON=dry_run`.
- (e) `--path` honored at an explicit location.
- (f) status routes to stderr only (stdout is empty when invoked from this helper).
- (g) structural same-directory mktemp+mv assertion (grep the script source — atomicity is a structural property, not race-tested).

## Edit-in-sync

When editing `write-sentinel.sh`, update this `.md` and the test harness in the same PR. The gate predicates and stdout/stderr discipline are part of the public contract that `/research` and any future consumer relies on; changing them silently breaks downstream.
