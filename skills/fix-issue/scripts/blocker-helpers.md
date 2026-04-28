# blocker-helpers.sh

**Consumer**: sourced by `skills/fix-issue/scripts/find-lock-issue.sh` and `skills/fix-issue/scripts/umbrella-handler.sh`. Provides the canonical implementation of `native_open_blockers`, `prose_open_blockers`, and `all_open_blockers` so both callers apply the same native+prose dependency semantics to a candidate issue.

**Contract**: single normative source for the three blocker-resolution functions. Functions are sourced (never executed directly) and operate on `$REPO`, which the caller MUST set before sourcing or before calling any function defined here. Permissions are `0644` (matches the `lib-*.sh` sourced-only convention in `scripts/`).

## Functions

### `native_open_blockers <issue-number>`

Queries GitHub's native issue-dependencies API (`repos/<REPO>/issues/<N>/dependencies/blocked_by`) and prints a space-separated list of OPEN blocker issue numbers on stdout. Empty output means no native blockers known. Fail-open on any gh error (404 on repos without the dependencies feature, transient `gh` failures): prints nothing, returns 0.

### `prose_open_blockers <issue-number>`

Scans the issue body and every comment body separately (per-document iteration to prevent cross-document fabrication) for the conservative prose-dependency keyword set defined in `parse-prose-blockers.sh`, resolves each referenced same-repo issue's current state, and prints a space-separated list of OPEN refs on stdout. Self-references (the candidate's own number) are filtered out. Every boundary (body fetch, comments fetch, parser invocation, per-ref state lookup) is fail-open: any failure degrades to "no additional prose blockers known".

### `all_open_blockers <issue-number>`

Unions native and prose blocker sets, dedupes, and returns a space-separated list of OPEN blockers. Native-first short-circuit: if `native_open_blockers` returns a non-empty list, the prose path is skipped entirely (the issue is already ineligible). Documented tradeoff: skip/error messages may list only native blocker numbers when both sources apply — see `skills/fix-issue/SKILL.md` Known Limitations.

## Sourcing requirements

1. **`REPO` must be set first.** The functions read `$REPO` at call time; sourcing the library does not resolve it for you. Both callers (`find-lock-issue.sh`, `umbrella-handler.sh`) resolve `REPO` via `gh repo view --json nameWithOwner --jq '.nameWithOwner'` before sourcing, with their own error-emission contract on resolution failure.
2. **`set -euo pipefail`-safe.** The functions are written so empty-pipeline edges (no native blockers found, no prose refs found) produce empty output rather than triggering `pipefail`. The library can be sourced into a script running with `set -euo pipefail`.
3. **Source-failure guard required.** An unguarded `source` of a missing or unreadable file under `set -e` aborts the script before any stdout is emitted, breaking callers that parse `KEY=VALUE` output. Both callers wrap their `source` call with explicit failure handling — find-lock-issue.sh emits `ELIGIBLE=false ERROR=...` and exits 2 on source failure; umbrella-handler.sh emits the per-subcommand `ERROR=...` shape and exits 1.

## Edit-in-sync pointers

| File | Relationship |
|---|---|
| `scripts/parse-prose-blockers.sh` | The regex parser invoked by `prose_open_blockers`. Resolved at function call time via `$(dirname "${BASH_SOURCE[0]}")/parse-prose-blockers.sh` so the path stays correct regardless of which script sources the library. |
| `scripts/parse-prose-blockers.md` | Sibling-doc contract for the parser. Names this library as the orchestration owner. |
| `scripts/find-lock-issue.sh` | Caller; sources this library after `REPO` is resolved. Existing call sites (`handle_umbrella` post-pick guard, explicit-issue gate, etc.) are unchanged from before the extraction. |
| `scripts/umbrella-handler.sh` | Caller; sources this library after `REPO` is resolved. `child_eligible` calls `all_open_blockers` (instead of the previous native-only `child_native_blockers`). |
| `scripts/test-find-lock-issue.sh` | Test harness; covers the explicit-issue blocker pipeline including prose paths. New e2e umbrella-dispatch fixture covers the post-extraction integration. |
| `scripts/test-umbrella-handler.sh` | Test harness; new fixtures cover prose-skip iteration and fail-open negative paths. |
| `agent-lint.toml` | Both `blocker-helpers.sh` and `blocker-helpers.md` are excluded from agent-lint — the script is sourced-only (agent-lint does not follow `source`); the sibling `.md` mirrors the `parse-prose-blockers.md` exclusion pattern. |

## When edits to this file require updates elsewhere

- **Function signature change** (rename, argument order, return semantics) → update both callers (`find-lock-issue.sh`, `umbrella-handler.sh`); update `parse-prose-blockers.md` if the parser-invocation contract shifts; update both test harnesses.
- **Fail-open posture change** → update SKILL.md Known Limitations; rerun the fail-open negative regression in `test-umbrella-handler.sh`.
- **Native-first short-circuit removal** → update SKILL.md Known Limitations to drop the "only native blocker numbers visible when both apply" caveat; expect higher API volume.
