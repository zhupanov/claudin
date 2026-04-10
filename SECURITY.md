# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

Only the latest released version receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in larch, please report it responsibly:

1. **Email**: Send details to <sergey@zhupanov.com>
2. **Do not** open a public GitHub issue for security vulnerabilities
3. Include steps to reproduce the issue and any relevant context

You should receive an acknowledgment within 72 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Trust Model

Larch is a Claude Code plugin that runs within Claude Code's permission boundary. It does not bypass Claude Code's built-in permission system — all tool calls (file edits, shell commands, etc.) go through the standard permission flow.

**External tool delegation**: When Codex or Cursor are available, larch delegates review tasks to them. These tools run with the same filesystem access as the user. The `/research` skill's read-only contract is enforced mechanically for the orchestrating agent (via `allowed-tools` frontmatter that omits `Edit`, `Write`, and `Skill`) but is only prompt-enforced for external reviewers — Codex and Cursor are instructed not to modify files, but this is a behavioral constraint, not a sandbox.

**Slack tokens**: If configured, `LARCH_SLACK_BOT_TOKEN` is used to post PR announcements. The token should have minimal OAuth scopes (`chat:write`, `reactions:write`). Never commit tokens to version control.
