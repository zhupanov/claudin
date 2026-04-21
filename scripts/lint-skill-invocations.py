#!/usr/bin/env python3
"""Lint SKILL.md files: when `Skill` is in `allowed-tools`, enforce two checks.

This lint enforces the sub-skill-invocation style guide
(skills/shared/subskill-invocation.md) at two levels:

1. **Total omission** (file-level): a SKILL.md that declares `Skill` in its
   `allowed-tools` frontmatter must contain at least one of the canonical
   phrases somewhere in its body — either PATTERN_A_PHRASE
   ("Invoke the Skill tool") or PATTERN_B_PHRASE ("via the Skill tool"). One
   message per file.

2. **Per-invocation** (line-level, line-local): for each body line that
   describes a direct slash-skill invocation — a line matching
   INVOCATION_LINE_REGEX — the same line must also contain PATTERN_B_PHRASE
   ("via the Skill tool"). One message per offending line, naming the
   absolute file line number for editor jump-to-line.

Both checks are gated on `Skill` appearing as an exact token in the
frontmatter's `allowed-tools` field. Both contribute to the exit-1 violation
count. Lines inside fenced code blocks (delimited by ``` lines) are exempt
from the per-invocation check.

The per-invocation regex is intentionally narrow: it matches imperative
"Invoke" (or "re-invoke") followed by an optional "the" and an optional
**bold span**, with a backticked `/<name>` token immediately after. This
shape catches direct slash-skill invocations like
``Invoke `/foo` via the Skill tool`` while exempting:
  - sub-procedure references like "Invoke the **Rebase + Re-bump
    Sub-procedure** ... `/bump-version`" where `/bump-version` is a later
    citation, not the immediate object;
  - helper/script references like "always invoke the helper script before
    calling `/bump-version`" — same reason.

Scans skills/*/SKILL.md and .claude/skills/*/SKILL.md under --root (defaults
to the repo root derived from this script's path).

Exit codes: 0 = clean, 1 = violations found, 2 = internal error. When a run
produces both violations and internal errors simultaneously, exit 2 wins —
the violation messages are still printed to stderr, but the process-level
signal prioritizes the internal error so callers keyed on exit code do not
treat a broken environment as a clean policy decision.
"""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

import yaml

# Canonical phrases — first element is the original style-guide form, the
# caveman-compressed variant (with the leading article "the" dropped) is the
# second element. Both are accepted; error messages reference the canonical
# form for readability.
PATTERN_A_PHRASES = (
    "Invoke the Skill tool",
    "Invoke Skill tool",
    "Call the Skill tool",
    "Call Skill tool",
)
PATTERN_B_PHRASES = ("via the Skill tool", "via Skill tool")
PATTERN_A_PHRASE = PATTERN_A_PHRASES[0]
PATTERN_B_PHRASE = PATTERN_B_PHRASES[0]

# Per-invocation regex: matches imperative "Invoke" or "re-invoke" with the
# backticked /<name> as the immediate object. The optional bold-span slot
# (≤40 chars) tolerates "Invoke the **Sub-procedure** `/name`" while still
# requiring the slash command to appear adjacent to the verb. The "skill"
# trailing word is optional ("Invoke the `/design` skill" → match).
INVOCATION_LINE_REGEX = re.compile(
    r"\b(?:re-)?[Ii]nvoke\b\s+(?:the\s+)?(?:\*\*[^*\n]{1,40}\*\*\s+)?`/[\w-]+`(?:\s+skill\b)?"
)

# A code fence is a line whose first non-whitespace content is at least three
# backticks, optionally followed by a language tag.
CODE_FENCE_REGEX = re.compile(r"^\s*```")

GLOB_PATTERNS = (
    "skills/*/SKILL.md",
    ".claude/skills/*/SKILL.md",
)


def extract_frontmatter_and_body(text: str) -> tuple[str | None, str, int]:
    """Return (frontmatter_text, body_text, body_start_line_1based).

    `body_start_line_1based` is the absolute file line number of the first
    body line. For a file with no frontmatter, body starts at line 1. For a
    file with frontmatter, body starts on the line *after* the closing
    `---\\n` marker.

    Strips a leading UTF-8 BOM and normalizes CRLF to LF before the prefix
    test so files authored on Windows or by editors that insert a BOM are not
    silently skipped.
    """
    text = text.lstrip("\ufeff").replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return None, text, 1
    remainder = text[len("---\n"):]
    end_marker = "\n---\n"
    idx = remainder.find(end_marker)
    if idx < 0:
        end_marker_eof = "\n---"
        if remainder.endswith(end_marker_eof):
            # Frontmatter consumes the entire file; body is empty. Body
            # start line is past EOF; emit a placeholder that won't be
            # consulted because body is "" (no lines to iterate).
            return remainder[: -len(end_marker_eof)], "", 0
        return None, text, 1
    frontmatter = remainder[:idx]
    body = remainder[idx + len(end_marker):]
    # Frontmatter spans: opening "---\n" (line 1) + frontmatter lines
    # (frontmatter.count("\n") since each "\n" terminates a frontmatter line)
    # + closing "---\n" (one line). Body's first line is one past that.
    frontmatter_lines = frontmatter.count("\n") + 1  # frontmatter content lines
    # File line numbering: line 1 is opening "---", lines 2..1+frontmatter_lines
    # are the frontmatter content, line 2+frontmatter_lines is closing "---",
    # line 3+frontmatter_lines is the first body line.
    body_start_line = 2 + frontmatter_lines + 1
    return frontmatter, body, body_start_line


def allowed_tools_contains_skill(frontmatter_text: str) -> bool:
    """True iff the frontmatter's `allowed-tools` field lists `Skill` as an exact token."""
    try:
        data = yaml.safe_load(frontmatter_text)
    except yaml.YAMLError:
        return False
    if not isinstance(data, dict):
        return False
    value = data.get("allowed-tools")
    if value is None:
        return False
    if isinstance(value, str):
        tokens = [t.strip() for t in value.split(",")]
    elif isinstance(value, list):
        tokens = [str(t).strip() for t in value]
    else:
        return False
    return "Skill" in tokens


def body_has_invocation_phrase(body: str) -> bool:
    return any(p in body for p in PATTERN_A_PHRASES + PATTERN_B_PHRASES)


def body_per_invocation_violations(
    body: str, body_start_line: int
) -> list[tuple[int, str]]:
    """Return (absolute_file_line, line_text) for each per-invocation violation.

    A line is a violation when it (a) is outside any fenced code block,
    (b) matches INVOCATION_LINE_REGEX, and (c) does NOT contain
    PATTERN_B_PHRASE on the same line.
    """
    violations: list[tuple[int, str]] = []
    in_fence = False
    # Iterate body line by line. body.split("\n") gives one element per line;
    # if body is empty, this yields [""], which we tolerate (no matches).
    for body_line_idx, line in enumerate(body.split("\n")):
        if CODE_FENCE_REGEX.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        if INVOCATION_LINE_REGEX.search(line) and not any(p in line for p in PATTERN_B_PHRASES):
            absolute_line = body_start_line + body_line_idx
            violations.append((absolute_line, line))
    return violations


def find_skill_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in GLOB_PATTERNS:
        files.extend(sorted(root.glob(pattern)))
    return files


class LintError(Exception):
    """Raised for internal errors (file unreadable, non-UTF-8 bytes). Exit 2."""


def lint_file(path: Path, root: Path) -> list[str]:
    """Return a list of violation messages (empty if clean).

    Raises LintError for internal I/O errors.
    """
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise LintError(f"lint-skill-invocations: {path}: cannot read file: {e}") from e
    frontmatter, body, body_start_line = extract_frontmatter_and_body(text)
    if frontmatter is None:
        return []
    if not allowed_tools_contains_skill(frontmatter):
        return []
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    messages: list[str] = []
    if not body_has_invocation_phrase(body):
        messages.append(
            f"lint-skill-invocations: {rel}: declares 'Skill' in allowed-tools but "
            f"contains no '{PATTERN_A_PHRASE}' or '{PATTERN_B_PHRASE}' invocation step"
        )
    for absolute_line, _line_text in body_per_invocation_violations(body, body_start_line):
        messages.append(
            f"lint-skill-invocations: {rel}:{absolute_line}: 'Invoke `/<cmd>`' "
            f"without '{PATTERN_B_PHRASE}' on the same line — see "
            f"skills/shared/subskill-invocation.md"
        )
    return messages


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="Repository root to scan (default: this script's parent directory).",
    )
    args = parser.parse_args()

    root: Path = args.root.resolve()
    if not root.is_dir():
        print(f"lint-skill-invocations: --root is not a directory: {root}", file=sys.stderr)
        return 2

    violations: list[str] = []
    errors: list[str] = []
    for path in find_skill_files(root):
        try:
            msgs = lint_file(path, root)
        except LintError as e:
            errors.append(str(e))
            continue
        violations.extend(msgs)

    for e in errors:
        print(e, file=sys.stderr)
    for v in violations:
        print(v, file=sys.stderr)
    if errors:
        return 2
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
