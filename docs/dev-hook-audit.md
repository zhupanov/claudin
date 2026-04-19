# Dev-only PostToolUse audit log

Contributor-only debugging aid that records a JSONL audit trail of every
`Edit` and `Write` tool invocation Claude Code makes in this project.

`scripts/audit-edit-write.sh` is shipped as part of the larch plugin
(it lives in the plugin install tree), but it is **not registered or
enabled by default**. It only runs when a contributor opts in locally
by adding a `PostToolUse` entry to `.claude/settings.local.json`
(which is gitignored — see `.gitignore`).

## Enable

Paste one of the two snippets below into `.claude/settings.local.json`
(create the file if it does not exist — the rest of the file can stay
untouched). Pick the snippet that matches how you have larch available:

### In-repo dev (editing the larch repo itself)

If you are a larch contributor working inside a clone of this repo and
your shell cwd is the repo root, `$PWD/scripts/audit-edit-write.sh`
resolves correctly:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "$PWD/scripts/audit-edit-write.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### Installed plugin (larch installed into another project)

If larch is installed as a plugin in a consumer repo, `$PWD` is the
consumer project root and will not resolve the larch helper. Use
`${CLAUDE_PLUGIN_ROOT}/scripts/audit-edit-write.sh` instead — this is
the same resolution pattern used by `hooks/hooks.json` for the shipped
PreToolUse hooks:

```json
{
  "hooks": {
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          {
            "type": "command",
            "command": "${CLAUDE_PLUGIN_ROOT}/scripts/audit-edit-write.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

Restart Claude Code (or reload the session). Subsequent `Edit` / `Write`
tool calls will append a JSONL line to `.claude/hook-audit.log` in the
project where Claude Code is running (honoring `CLAUDE_PROJECT_DIR`).

## Log format

One JSON object per line:

| Field     | Type   | Meaning                                                  |
|-----------|--------|----------------------------------------------------------|
| `ts`      | string | UTC timestamp, ISO-8601 (e.g. `2026-04-19T18:44:12Z`)    |
| `event`   | string | Always `"PostToolUse"`                                   |
| `payload` | object | Full hook stdin as emitted by Claude Code                |

The `payload` object is whatever Claude Code sent to the hook on stdin
— typically an object containing `tool_name`, `tool_input`, and
related metadata. No fields are stripped or redacted.

Example:

```json
{"ts":"2026-04-19T18:44:12Z","event":"PostToolUse","payload":{"tool_name":"Edit","tool_input":{"file_path":"/Users/you/repo/file.go","old_string":"...","new_string":"..."}}}
```

## Disable

Remove the `PostToolUse` entry from `.claude/settings.local.json`
(or delete the file entirely if it contained nothing else).

## Rotate / clear the log

The script only appends. To clear without deleting the file:

```bash
truncate -s 0 .claude/hook-audit.log
```

Or remove it outright:

```bash
rm .claude/hook-audit.log
```

There is no automatic rotation — the log grows until you clear it.

## Privacy

**The log is sensitive.** The `payload` object captures `tool_input`,
which includes:

- **Full file paths** Claude Code edited or wrote (may expose private
  project layout, user directories, temp file locations).
- **Full file contents** for `Write` (the `content` field), and the
  **before/after strings** for `Edit` (the `old_string` / `new_string`
  fields). These may contain secrets, personally identifiable
  information, or proprietary code.

The log is gitignored by default (`.gitignore` lists
`.claude/hook-audit.log`), but the raw file on disk is the developer's
responsibility:

- **Never commit it.**
- **Never paste its contents into an issue, pull request, screenshot,
  or screen share.**
- **Clear it after debugging**: `truncate -s 0 .claude/hook-audit.log`.
- If you enable this hook on a project that handles secrets (e.g.
  editing `.env`, private keys, credentials), consider the log itself
  a secret-bearing artifact with the same retention discipline.

See `SECURITY.md` for the project's security posture on this audit log.

## Concurrency note

Under parallel tool use, two `PostToolUse` hook invocations may run
concurrently. Shell `>>` append is best-effort: if two writes
interleave their bytes, **a line can be corrupted** (not merely
omitted), producing a physically malformed JSON record.

Consumers parsing the log should tolerate parse errors on individual
lines rather than aborting on the first error. A streaming `jq …
file.log` does NOT skip malformed records — it aborts the whole run at
the first parse error. Read one line at a time instead, e.g.:

```bash
# Process each line independently; skip any that fail to parse.
while IFS= read -r line; do
    printf '%s\n' "$line" | jq -ec 'select(.event == "PostToolUse")' 2>/dev/null || true
done < .claude/hook-audit.log
```

Or use `jq -R 'fromjson? | select(.event == "PostToolUse")' .claude/hook-audit.log`
which parses each input line as a raw string first and silently drops
lines where `fromjson` fails to parse — the `?` operator suppresses
the parse error and emits no output for that line, so `select` never
sees a malformed record.

Line locking (`flock`) is intentionally not implemented — for a
contributor-local debugging aid, the added complexity outweighs the
occasional corrupted line.

## Testing

`scripts/test-audit-edit-write.sh` is the regression harness. It uses
`mktemp -d` plus `CLAUDE_PROJECT_DIR` override so the test never
touches the repo's real `.claude/hook-audit.log`. Wired into
`make lint` via the `test-audit-edit-write` target.
