# post-issue-slack.sh

**Purpose**: Post a single one-line Slack status message about a tracking issue. Consumed by `/implement` Step 16a (once per run) and by `/fix-issue` Steps 4 and 8b. Replaces the former PR-scoped Slack stack (`post-pr-announce.sh` + `slack-announce.sh` + `post-merged-emoji.sh` + `add-merged-emoji.sh` + `add-slack-emoji.sh`) and the former `skills/fix-issue/scripts/post-issue-slack.sh`.

## Output contract

One-liner body (Slack mrkdwn):

```
<emoji> <https://github.com/$REPO/issues/$N|Issue #$N> (<safe-title>) — <status>[ — <detail>]
```

- **Emoji**: `✅` (`closed`), `📝` (`pr-opened`), `❌` (`blocked`), `❓` (`user-input`).
- **Link**: mrkdwn link composed from `gh issue view` output when available; falls back to `https://github.com/$REPO/issues/$N`.
- **Safe-title**: `|`, `<`, `>` are backslash-escaped; `"` is replaced with U+201C left curly quote (matching the pre-existing convention from the deleted `slack-announce.sh`).
- **Status tail**: fixed per status enum (e.g. `closed`, `PR opened, awaiting merge`). When `--pr-url` is given with `pr-opened`, the tail renders the PR URL as a nested link.
- **Detail suffix**: when `--detail` is provided, appended (preceded by ` — `) after the status tail. Used by `/fix-issue` to preserve closure reason context (Step 4 not-material reason; Step 8b WORK_SUMMARY one-liner).

## Identity

Posts as the human git user via `git config user.name` → `--username` on `post-slack-message.sh`. Falls back gracefully to the bot's display name when `git config user.name` is empty (e.g., CI environments without git config).

## Arguments

| Flag             | Required | Purpose |
|------------------|----------|---------|
| `--issue-number` | Yes      | GitHub issue number (integer). |
| `--status`       | Yes      | One of `closed`, `pr-opened`, `blocked`, `user-input`. Unknown values cause exit 1. |
| `--repo`         | Yes      | `OWNER/REPO` used for link-composition fallback when `gh issue view` fails. |
| `--token`        | Yes      | Slack bot token (whitespace-stripped before use). |
| `--channel-id`   | Yes      | Slack channel ID. |
| `--pr-url`       | No       | PR URL for `pr-opened` status tail. |
| `--detail`       | No       | Free-form tail text. Appended after the base status summary. |

## Output

On success:
```
SLACK_TS=<message timestamp>
```

On failure:
```
SLACK_TS=
SLACK_ERROR=<reason>
```

Non-zero exit on argument or API failure. Callers should never abort their run on a non-zero exit — treat Slack as best-effort and log the failure to their own `Tool Failures` category.

## Invariants

- **Fail-open**: never aborts the caller's workflow. Any failure is a soft warning at the caller.
- **Single API call**: exactly one `chat.postMessage` per invocation. Callers are responsible for invoking at-most-once per run.
- **gh best-effort**: issue metadata fetch is wrapped in `set +e` / `set -e`. A missing or failing `gh` binary degrades to the fallback URL.
- **Status enum is closed**: new outcomes require editing this script AND all call sites.

## Call sites

- `skills/implement/SKILL.md` Step 16a — once near end of run, gated on `slack_enabled AND slack_available AND ISSUE_NUMBER set AND !deferred AND !repo_unavailable`.
- `skills/fix-issue/SKILL.md` Step 4 — not-material close, `--status closed --detail "<reason>"`.
- `skills/fix-issue/SKILL.md` Step 8b — NON_PR close, `--status closed --detail "<WORK_SUMMARY one-liner>"`.

`/fix-issue` Step 8a (INTENT=PR) does NOT call this script directly — the child `/implement` invocation handles the Slack post via its Step 16a.

## Edit-in-sync

- When adding a new status enum value, update: (1) the `case "$STATUS"` validation block, (2) the emoji + base-tail case block, (3) this doc's Arguments and Emoji sections, (4) `/implement` Step 16a state machine, (5) `/fix-issue` call sites if relevant.
- When changing the one-line body format, update the "Output contract" section above AND the CHANGELOG entry describing the format.
