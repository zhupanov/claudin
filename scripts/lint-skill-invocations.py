#!/usr/bin/env python3
"""Lint SKILL.md files: when `Skill` is in `allowed-tools`, require an invocation phrase.

This lint is a minimal guardrail for *total omission* of the sub-skill-invocation
style guide (skills/shared/subskill-invocation.md). It does NOT enforce per-invocation
alignment; a SKILL.md that declares `Skill` in its `allowed-tools` frontmatter passes
as long as either canonical phrase appears somewhere in the body. A stricter
per-invocation check is tracked as a separate follow-up issue.

Scans skills/*/SKILL.md and .claude/skills/*/SKILL.md under --root (defaults to the
repo root derived from this script's path). For each file that declares `Skill` in
its allowed-tools frontmatter, checks that the body contains either PATTERN_A_PHRASE
or PATTERN_B_PHRASE.

Exit codes: 0 = clean, 1 = violations found, 2 = internal error. When a run
produces both violations and internal errors simultaneously, exit 2 wins — the
violation messages are still printed to stderr, but the process-level signal
prioritizes the internal error so callers keyed on exit code do not treat a
broken environment as a clean policy decision.
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

import yaml

PATTERN_A_PHRASE = "Invoke the Skill tool"
PATTERN_B_PHRASE = "via the Skill tool"

GLOB_PATTERNS = (
    "skills/*/SKILL.md",
    ".claude/skills/*/SKILL.md",
)


def extract_frontmatter_and_body(text: str) -> tuple[str | None, str]:
    """Return (frontmatter_text, body_text). frontmatter_text is None if absent.

    Recognizes the first `---\\n`-delimited block at the top of the file. Strips
    a leading UTF-8 BOM and normalizes CRLF to LF before the prefix test so files
    authored on Windows or by editors that insert a BOM are not silently skipped.
    Everything after the second `---` line is body.
    """
    text = text.lstrip("\ufeff").replace("\r\n", "\n")
    if not text.startswith("---\n"):
        return None, text
    remainder = text[len("---\n"):]
    end_marker = "\n---\n"
    idx = remainder.find(end_marker)
    if idx < 0:
        end_marker_eof = "\n---"
        if remainder.endswith(end_marker_eof):
            return remainder[: -len(end_marker_eof)], ""
        return None, text
    frontmatter = remainder[:idx]
    body = remainder[idx + len(end_marker):]
    return frontmatter, body


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
    return PATTERN_A_PHRASE in body or PATTERN_B_PHRASE in body


def find_skill_files(root: Path) -> list[Path]:
    files: list[Path] = []
    for pattern in GLOB_PATTERNS:
        files.extend(sorted(root.glob(pattern)))
    return files


class LintError(Exception):
    """Raised for internal errors (file unreadable, non-UTF-8 bytes). Exit 2."""


def lint_file(path: Path, root: Path) -> str | None:
    """Return a violation message or None. Raises LintError for internal I/O errors."""
    try:
        text = path.read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as e:
        raise LintError(f"lint-skill-invocations: {path}: cannot read file: {e}") from e
    frontmatter, body = extract_frontmatter_and_body(text)
    if frontmatter is None:
        return None
    if not allowed_tools_contains_skill(frontmatter):
        return None
    if body_has_invocation_phrase(body):
        return None
    try:
        rel = path.relative_to(root)
    except ValueError:
        rel = path
    return (
        f"lint-skill-invocations: {rel}: declares 'Skill' in allowed-tools but "
        f"contains no '{PATTERN_A_PHRASE}' or '{PATTERN_B_PHRASE}' invocation step"
    )


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
            msg = lint_file(path, root)
        except LintError as e:
            errors.append(str(e))
            continue
        if msg is not None:
            violations.append(msg)

    for e in errors:
        print(e, file=sys.stderr)
    for v in violations:
        print(v, file=sys.stderr)
    if errors:
        return 2
    return 1 if violations else 0


if __name__ == "__main__":
    sys.exit(main())
