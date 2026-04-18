# Security Policy

## Supported Versions

| Version | Supported |
|---------|-----------|
| Latest  | Yes       |
| Older   | No        |

Only the latest released version receives security updates.

## Reporting a Vulnerability

If you discover a security vulnerability in larch, please report it responsibly:

1. **Email**: Send details to <zhupanov@yahoo.com>
2. **Do not** open a public GitHub issue for security vulnerabilities
3. Include steps to reproduce the issue and any relevant context

You should receive an acknowledgment within 72 hours. We will work with you to understand the issue and coordinate a fix before any public disclosure.

## Trust Model

Larch is a Claude Code plugin that runs within Claude Code's permission boundary. It does not bypass Claude Code's built-in permission system — all tool calls (file edits, shell commands, etc.) go through the standard permission flow.

**External tool delegation**: When Codex or Cursor are available, larch delegates review tasks to them. These tools run with the same filesystem access as the user. The `/research` skill's read-only contract is enforced mechanically for the orchestrating agent (via `allowed-tools` frontmatter that omits `Edit`, `Write`, and `Skill`) but is only prompt-enforced for external reviewers — Codex and Cursor are instructed not to modify files, but this is a behavioral constraint, not a sandbox.

**Slack tokens**: If configured, `LARCH_SLACK_BOT_TOKEN` is used to post PR announcements. The token should have minimal OAuth scopes (`chat:write`, `reactions:write`). Never commit tokens to version control.

**Reviewer archetype security lane**: The Code Reviewer archetype (`agents/code-reviewer.md`, generated from `skills/shared/reviewer-templates.md`) includes a first-class §5 Security focus area covering injection, authN/authZ, secret scanning, crypto, deserialization, SSRF, path traversal, and dependency CVEs. Review findings may be tagged `security` as their primary focus area. Reviewer `{CONTEXT_BLOCK}` material (diffs, plans, commits) is wrapped in namespaced `<reviewer_*>` XML tags with a prepended instruction sentence that the tags are literal input delimiters. This is a model-level convention that reduces prompt-injection attack surface; it is NOT a parser-enforced security boundary. A crafted payload inside the content (e.g., a diff line containing a literal matching closing tag) can theoretically defeat the wrapper, and the primary defense is the instruction sentence combined with the namespaced prefix. See `docs/review-agents.md` for the full residual-risk discussion and possible stronger follow-up mitigations.
