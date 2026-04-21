# Dev-only PostToolUse audit log

Contributor-only debug aid. Record JSONL audit trail of every `Edit` and `Write` tool call Claude Code make in this project.

`scripts/audit-edit-write.sh` ship as part of larch plugin (live in plugin install tree), but **not registered or enabled by default**. Only run when contributor opt in locally by add `PostToolUse` entry to `.claude/settings.local.json` (gitignored — see `.gitignore`).

## Enable

Paste one of two snippets below into `.claude/settings.local.json` (make file if not exist — rest of file stay untouched). Pick snippet that match how larch available:

### In-repo dev (editing the larch repo itself)

If larch contributor work inside clone of this repo and shell cwd is repo root, `$PWD/scripts/audit-edit-write.sh` resolve correctly:

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

If larch installed as plugin in consumer repo, `$PWD` is consumer project root and no resolve larch helper. Use `${CLAUDE_PLUGIN_ROOT}/scripts/audit-edit-write.sh` instead — same resolution pattern used by `hooks/hooks.json` for shipped PreToolUse hooks:

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

Restart Claude Code (or reload session). Later `Edit` / `Write` calls append JSONL line to `.claude/hook-audit.log` in project where Claude Code run (honor `CLAUDE_PROJECT_DIR`).

## Log format

One JSON object per line:

| Field     | Type   | Meaning                                                  |
|-----------|--------|----------------------------------------------------------|
| `ts`      | string | UTC timestamp, ISO-8601 (e.g. `2026-04-19T18:44:12Z`)    |
| `event`   | string | Always `"PostToolUse"`                                   |
| `payload` | object | Full hook stdin as emitted by Claude Code                |

`payload` object is whatever Claude Code sent to hook on stdin — typically object with `tool_name`, `tool_input`, related metadata. No fields stripped or redacted.

Example:

```json
{"ts":"2026-04-19T18:44:12Z","event":"PostToolUse","payload":{"tool_name":"Edit","tool_input":{"file_path":"/Users/you/repo/file.go","old_string":"...","new_string":"..."}}}
```

## Disable

Remove `PostToolUse` entry from `.claude/settings.local.json` (or delete file if nothing else in it).

## Rotate / clear the log

Script only append. Clear without delete file:

```bash
truncate -s 0 .claude/hook-audit.log
```

Or remove outright:

```bash
rm .claude/hook-audit.log
```

No auto rotation — log grow until you clear.

## Privacy

**Log sensitive.** `payload` capture `tool_input`, which include:

- **Full file paths** Claude Code edited or wrote (may leak private project layout, user dirs, temp file locations).
- **Full file contents** for `Write` (`content` field), and **before/after strings** for `Edit` (`old_string` / `new_string` fields). May contain secrets, PII, proprietary code.

Log gitignored by default (`.gitignore` list `.claude/hook-audit.log`), but raw file on disk is dev responsibility:

- **Never commit.**
- **Never paste into issue, PR, screenshot, screen share.**
- **Clear after debug**: `truncate -s 0 .claude/hook-audit.log`.
- If enable hook on project with secrets (e.g. edit `.env`, private keys, credentials), treat log as secret-bearing artifact with same retention rules.

See `SECURITY.md` for project security posture on this audit log.

## Concurrency note

Under parallel tool use, two `PostToolUse` hook calls may run concurrent. Shell `>>` append best-effort: if two writes interleave bytes, **line can corrupt** (not just drop), making physically malformed JSON record.

Consumers parsing log should tolerate parse errors on individual lines, not abort on first error. Streaming `jq … file.log` does NOT skip malformed records — abort whole run at first parse error. Read one line at time instead, e.g.:

```bash
# Process each line independently; skip any that fail to parse.
while IFS= read -r line; do
    printf '%s\n' "$line" | jq -ec 'select(.event == "PostToolUse")' 2>/dev/null || true
done < .claude/hook-audit.log
```

Or use `jq -R 'fromjson? | select(.event == "PostToolUse")' .claude/hook-audit.log` — parse each input line as raw string first, silently drop lines where `fromjson` fail. `?` operator suppress parse error and emit nothing for that line, so `select` never see malformed record.

Line locking (`flock`) intentionally not implemented — for contributor-local debug aid, added complexity outweigh occasional corrupt line.

## Testing

`scripts/test-audit-edit-write.sh` is regression harness. Use `mktemp -d` plus `CLAUDE_PROJECT_DIR` override so test never touch repo real `.claude/hook-audit.log`. Wired into `make lint` via `test-audit-edit-write` target.
