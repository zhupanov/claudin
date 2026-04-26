# merge-pr.sh

Squash-merges a PR via `gh pr merge`, with a re-verified `--admin` fallback for branch-protection denials. The canonical `--admin` implementation in this repo — see `skills/implement/SKILL.md` Step 12b for the orchestrator-side contract.

## Usage

```
scripts/merge-pr.sh --pr NUMBER --repo OWNER/REPO [--no-admin-fallback]
```

Emits `MERGE_RESULT=...` and `ERROR=...` on stdout via an EXIT trap. Exits 0 unconditionally on usage success (the outcome is in `MERGE_RESULT`); exits 1 only on argument-validation errors.

## MERGE_RESULT enum

| Value | Meaning |
|-------|---------|
| `merged` | Standard squash merge succeeded. |
| `admin_merged` | Standard merge was rejected (typically by branch protection); CI re-verified green + branch fresh; `--admin` retry succeeded. **Only emitted when `--no-admin-fallback` is NOT set.** |
| `main_advanced` | Standard merge failed because the branch is behind main. Caller should rebase and retry. |
| `ci_not_ready` | Standard merge failed; re-verification did not find all checks passing. Caller should poll CI. |
| `admin_failed` | `--admin` retry was attempted but failed. Hard error. |
| `policy_denied` | Standard merge was rejected; CI re-verified green + branch fresh (admin-eligible); `--no-admin-fallback` is set so `--admin` was NOT invoked. Caller should bail to manual reviewer-approval flow. |
| `error` | Catch-all unexpected failure. |

## --no-admin-fallback

When set, the script reaches the same admin-eligible gate (CI good + branch fresh) but emits `MERGE_RESULT=policy_denied` instead of invoking `gh pr merge --squash --admin`. This is opt-out: the default behavior (no flag) is unchanged from the historical `--admin`-retry behavior.

The flag applies to **all admin-eligible mergeStateStatus values** — `CLEAN`, `UNSTABLE`, `HAS_HOOKS`, and `BLOCKED`. Any state where `--admin` would have been retried becomes `policy_denied` when the flag is set; this is broader than just review-required denials. Document this in caller-side flag specs so operators understand the scope.

`ERROR` on the `policy_denied` path is a fixed string: `"branch protection denied merge; --no-admin-fallback set"`. The orchestrator surfaces this verbatim as `FINAL_BAIL_REASON` when bailing to Step 12d.

## Safety invariant

`--admin` overrides ALL branch protection rules, including review-required policies. The script enforces a re-verification gate before the privileged path:

1. All CI checks must have `bucket == "pass"` (verified via `gh pr checks --json`).
2. `mergeStateStatus` must be `CLEAN`, `UNSTABLE`, `BLOCKED`, or `HAS_HOOKS` (NOT `BEHIND`, `DIRTY`, `DRAFT`, or `UNKNOWN`).

Both gates are checked **before** either the `--admin` retry OR the `policy_denied` short-circuit. The `--no-admin-fallback` opt-out is not a way to skip the safety invariant — it is a way to decline the override that the safety invariant has already approved.

## Non-responsibilities

This script does NOT post audit comments, Slack messages, or any human-facing observability about the bypass. The orchestrator (`skills/implement/SKILL.md` Step 12b's `admin_merged` branch) is responsible for posting a best-effort PR comment recording the bypass when `--admin` actually fires. Keeping audit side effects out of this script preserves the narrow `MERGE_RESULT`/`ERROR` stdout contract that callers parse.

## Edit-in-sync rules

- When the `MERGE_RESULT` enum changes, update both this file's enum table and `skills/implement/SKILL.md` Step 12b's parse table in the same PR.
- When `--no-admin-fallback` semantics change (e.g., the gate set, the `ERROR` text), update `skills/implement/SKILL.md` flag spec, `skills/fix-issue/SKILL.md` flag forwarding, and `docs/configuration-and-permissions.md`.
- The script's header comment also documents the enum and flag — keep it byte-aligned with this file's "MERGE_RESULT enum" table.

## Test harness

No dedicated harness exists. Validation is via:
- `make lint` (shellcheck on the script).
- `bash scripts/merge-pr.sh --help` to verify Usage line.
- Manual integration testing on a real PR for new behavior changes.

A future PR may add a dedicated test harness; pre-existing concern.
