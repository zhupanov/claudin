# skills/fix-issue/scripts/finalize-umbrella.sh — contract

`skills/fix-issue/scripts/finalize-umbrella.sh` is the umbrella-finalization composer invoked when an umbrella's tracked children are all closed. It composes `tracking-issue-write.sh rename --state done` plus `issue-lifecycle.sh close --comment ...` into a single idempotent operation, addressing FINDING_2 from the design plan-review panel: `issue-lifecycle.sh close` posts the `--comment` BEFORE its idempotency probe, so concurrent finalize attempts could double-post the closing comment without an upstream guard.

## Subcommand

- **`finalize --issue N`** — finalize the umbrella issue if it has not already been finalized. Performs (1) idempotency probe → (2) best-effort rename to `[DONE]` → (3) post closing comment + close.

## Idempotency guard (FINDING_2 + FINDING_3 from the umbrella-PR review panel)

The guard probes three signals. **Only `state=CLOSED` is a strict short-circuit** that emits `FINALIZED=false ALREADY_FINALIZED=true REASON=already CLOSED`. The title-prefix and marker signals do NOT short-circuit on their own — they MUST drive a close-only retry path instead, because a prior attempt may have completed rename and/or comment-post but failed `gh issue close` (the "close-failed partial-success" window: `issue-lifecycle.sh close` posts the comment BEFORE the close call, so a transient close failure leaves rename and comment in place but the issue still OPEN). FINDING_3 from the umbrella-PR code-review panel: an aggressive short-circuit on title or marker alone leaves the umbrella stuck OPEN with no recovery path — every retry returns `ALREADY_FINALIZED=true` and skips the close call. The guard semantics:

1. **State is `CLOSED`** — strict short-circuit. Emit `FINALIZED=false ALREADY_FINALIZED=true REASON=already CLOSED` and exit 0.
2. **State is `OPEN` AND title starts with `[DONE]` followed by a space** — partial-success signal: prior rename succeeded, but close did not complete. Skip the rename API call (do not re-rename); proceed to the close path. The runtime emits `RENAMED=false` reflecting "no rename happened in this call" — but `FINALIZED=true CLOSED=true` if the close-only retry succeeds.
3. **State is `OPEN` AND a comment with the literal marker `<!-- larch:fix-issue:umbrella-finalized -->` already exists** — partial-success signal: prior comment-post succeeded. Skip the comment-post step (avoid double-comment under concurrency); call `gh issue close` directly via `issue-lifecycle.sh close --issue N` (no `--comment`). On success: `FINALIZED=true CLOSED=true RENAMED=<rename outcome>`. On close failure: standard `FINALIZED=false CLOSED=false ERROR=<reason>` exit 1.

These three signals are independent — an attempt may have completed any subset of (rename, comment, close), and the guard handles each combination correctly:

- only rename done: skip rename → post comment + close
- only comment done: rename → skip comment, close-only
- rename + comment done: skip both, close-only
- close done (state=CLOSED): strict short-circuit

If the comment-stream probe itself fails (transient `gh` API blip), the helper treats the marker as absent and proceeds to attempt the full sequence. The state+title checks already cover the common already-finalized paths; this fallback is conservative — letting a transient blip block finalization would leave a stale-open umbrella.

## Sequence on the executed path

1. **Rename** the umbrella's title to `[DONE] <title>` via `tracking-issue-write.sh rename --state done`. **Best-effort**: a rename failure (transient `gh` API error, rate limiting) is logged on stderr but does NOT abort finalization. The close step is the correctness boundary; the title prefix is a visual lifecycle marker. Operators can manually fix the title with one `gh issue edit` after-the-fact.
2. **Post closing comment + close** via `issue-lifecycle.sh close --issue N --comment "<marker>\nAll tracked issues are closed. Marking umbrella as DONE and closing."` The closing-comment template embeds the sentinel marker as its first line so subsequent finalize probes detect this run. `issue-lifecycle.sh close` is idempotent on `state == CLOSED` (skips the `gh issue close` call); the comment is always posted first per the existing partial-success contract.

## Stdout contract

| Key | Emitted when | Value |
|-----|--------------|-------|
| `FINALIZED` | always | `true` (executed path success) or `false` (idempotency hit OR error) |
| `ALREADY_FINALIZED` | only on idempotency hit | `true` |
| `REASON` | only on idempotency hit | `already CLOSED` / `title already prefixed [DONE]` / `existing closing-comment marker detected` |
| `RENAMED` | executed path only | `true` (rename succeeded) or `false` (best-effort failure) |
| `CLOSED` | executed path only | `true` (close succeeded) or `false` (close failed → `FINALIZED=false`) |
| `ERROR` | only on `FINALIZED=false` non-idempotent failure | one-line reason |

## Exit codes

| Exit | Meaning |
|------|---------|
| 0 | Success (`FINALIZED=true`) OR already-finalized (`ALREADY_FINALIZED=true`). Both are non-fatal for the caller. |
| 1 | Non-idempotent failure — `gh` API error, close call failed. Caller logs to `Tool Failures` and continues; the umbrella remains open and the next `/fix-issue <umbrella#>` run will re-attempt finalization via the Step 0 exit-4 path. |
| 2 | Usage error. |

## Edit-in-sync rules

- **Sentinel marker literal** (`<!-- larch:fix-issue:umbrella-finalized -->`) is byte-pinned in this script and the test harness. The marker is part of the public stdout-and-comment contract; renaming it requires a coordinated update to `test-finalize-umbrella.sh` and any future caller that reads it. The marker is intentionally an HTML comment (renders invisibly on the GitHub web UI but is part of the comment body for marker-detection).
- **Closing comment template** ("All tracked issues are closed. Marking umbrella as DONE and closing.") is documentation-grade prose; minor edits are allowed but the marker MUST remain on its own first line so the marker-detection regex (substring containment) keeps working regardless of comment-body formatting.
- **Caller contract**: the helper is invoked from FOUR call sites in `skills/fix-issue/SKILL.md`: Step 0 (exit-4 from `find-lock-issue.sh`), Step 3's not-material close (FINDING_7 — ordering: AFTER child rename, BEFORE Slack), Step 5a's adopted-issue-closed bailout (FINDING_8), and Step 6 after the just-closed child was the umbrella's last open child. Adding new call sites requires verifying that the idempotency guard handles the new context.

## Test harness

`skills/fix-issue/scripts/test-finalize-umbrella.sh` is the offline regression harness. PATH-prepended `gh` stub. Fixtures cover: finalize-success, finalize-idempotent-when-marker-comment-exists (FINDING_2), finalize-idempotent-when-already-DONE-prefix, finalize-idempotent-when-already-CLOSED, rename-failed-but-close-success (best-effort rename invariant). Run manually via `bash skills/fix-issue/scripts/test-finalize-umbrella.sh`. Wired into `make lint` via the `test-finalize-umbrella` target under `test-harnesses`. Both `.sh` and `.md` are in `agent-lint.toml`'s exclude list per the Makefile-only-reference pattern.
