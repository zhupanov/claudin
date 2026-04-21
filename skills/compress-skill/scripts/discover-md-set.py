#!/usr/bin/env python3
"""discover-md-set.py — Transitively discover .md files reachable from SKILL.md
within a target skill's own directory tree.

Input:
  --skill-dir <abs path>   Directory containing SKILL.md.
  --output    <path>       NUL-delimited file list (absolute paths, BFS order).

Output (stdout):
  FILE_COUNT=<n>

Rules:
  - Start BFS from SKILL.md.
  - Outside fenced code blocks (``` or ~~~), extract .md path tokens from:
      * Markdown link parens:  `](target.md[#anchor])`
      * Backticked spans:      `` `target.md[#anchor]` ``  (path-shaped only)
    A token is "path-shaped" if it contains '/' or starts with an expandable
    token like `${VAR}` or `$PWD`. Bare filenames in backticks
    (e.g. `README.md`) are skipped to avoid false positives.
  - Expand `${CLAUDE_PLUGIN_ROOT}` (inferred from SKILL_DIR ancestors — the
    parent whose child is `skills/`) and `$PWD` / `${PWD}` before resolution.
  - Strip optional `#fragment` and any whitespace suffix (`foo.md § Step 3`
    — a common larch citation form inside backticked spans — is reduced to
    `foo.md`). Percent-encoded path segments (`%20`, etc.) are NOT decoded;
    link targets with unencoded whitespace (`](My File.md)`) are not matched
    by `MD_LINK_RE` and are therefore missed on purpose — larch SKILL.md
    paths never contain spaces.
  - Resolve relative targets against the referring file's directory.
  - Canonicalize via os.path.realpath.
  - Keep only paths inside SKILL_DIR (exact match or subpath).
  - Skip non-existent files silently.
  - Deduplicate by canonical path, preserving first-seen order.

Rationale: larch SKILL.md files cite sibling references predominantly via
backticked paths like `${CLAUDE_PLUGIN_ROOT}/skills/<name>/references/foo.md`
rather than Markdown link syntax. A discovery pass that only recognizes
`](...)` would miss every MANDATORY-READ pointer inside a larch skill.
"""
import argparse
import os
import re
import sys

FENCE_RE = re.compile(r'^\s*(`{3,}|~{3,})')

# Markdown inline link: ](target ...)
MD_LINK_RE = re.compile(r'\]\(\s*([^)\s]+)(?:\s+"[^"]*")?\s*\)')

# Backticked span: `...`. Non-greedy; inline code (single-backtick) only.
# Avoids double-backtick spans for simplicity — rare in larch SKILL.md.
BACKTICK_RE = re.compile(r'`([^`\n]+)`')


def infer_plugin_root(skill_dir: str) -> str:
    """Infer ${CLAUDE_PLUGIN_ROOT} from the skill dir. For `<X>/skills/<name>`
    or `<X>/.claude/skills/<name>`, return `<X>`. Fall back to env var or "".
    """
    parent = os.path.dirname(skill_dir)  # .../skills
    if os.path.basename(parent) == 'skills':
        grand = os.path.dirname(parent)
        if os.path.basename(grand) == '.claude':
            return os.path.dirname(grand)
        return grand
    return os.environ.get('CLAUDE_PLUGIN_ROOT', '')


PLUGIN_ROOT_TOKENS = ('${CLAUDE_PLUGIN_ROOT}', '$CLAUDE_PLUGIN_ROOT')


def expand_tokens(target: str, plugin_root: str, pwd: str) -> str:
    """Expand ${CLAUDE_PLUGIN_ROOT}, $CLAUDE_PLUGIN_ROOT, ${PWD}, $PWD."""
    out = target
    for token in PLUGIN_ROOT_TOKENS:
        if plugin_root:
            out = out.replace(token, plugin_root)
    for token in ('${PWD}', '$PWD'):
        out = out.replace(token, pwd)
    return out


def has_plugin_root_token(target: str) -> bool:
    return any(token in target for token in PLUGIN_ROOT_TOKENS)


def strip_anchor(target: str) -> str:
    """Strip trailing `#fragment` and ` § heading` / multi-space suffixes."""
    target = target.split('#', 1)[0]
    # larch citation form: `path.md § Heading` — split on whitespace, keep first.
    parts = target.split()
    return parts[0] if parts else target


def looks_like_path(target: str) -> bool:
    """Filter backticked tokens to path-shaped ones only."""
    if '/' in target:
        return True
    if target.startswith('$'):
        return True
    return False


def extract_md_refs(path: str, plugin_root: str, pwd: str) -> list[str]:
    try:
        with open(path, 'r', encoding='utf-8', errors='replace') as fh:
            text = fh.read()
    except OSError:
        return []
    refs: list[str] = []
    in_fence = False
    for line in text.splitlines():
        if FENCE_RE.match(line):
            in_fence = not in_fence
            continue
        if in_fence:
            continue
        # Markdown links: accept any .md target.
        for m in MD_LINK_RE.finditer(line):
            t = strip_anchor(m.group(1))
            if t.endswith('.md'):
                refs.append(expand_tokens(t, plugin_root, pwd))
        # Backticked spans: accept path-shaped .md targets only.
        for m in BACKTICK_RE.finditer(line):
            raw = m.group(1).strip()
            t = strip_anchor(raw)
            if t.endswith('.md') and looks_like_path(t):
                refs.append(expand_tokens(t, plugin_root, pwd))
    return refs


def canonical(path: str) -> str:
    return os.path.realpath(path)


def inside(child: str, parent: str) -> bool:
    return child == parent or child.startswith(parent + os.sep)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--skill-dir', required=True)
    ap.add_argument('--output', required=True)
    args = ap.parse_args()

    skill_dir = canonical(args.skill_dir)
    if not os.path.isdir(skill_dir):
        print(f'ERROR=Skill directory does not exist: {skill_dir}', file=sys.stderr)
        return 1
    skill_md = os.path.join(skill_dir, 'SKILL.md')
    if not os.path.isfile(skill_md):
        print(f'ERROR=SKILL.md not found at {skill_md}', file=sys.stderr)
        return 1

    plugin_root = infer_plugin_root(skill_dir)
    pwd = os.environ.get('PWD', os.getcwd())

    queue: list[str] = [canonical(skill_md)]
    seen: set[str] = set()
    order: list[str] = []

    while queue:
        current = queue.pop(0)
        if current in seen:
            continue
        seen.add(current)
        order.append(current)
        base = os.path.dirname(current)
        for target in extract_md_refs(current, plugin_root, pwd):
            # Fail-closed: if a reference contains ${CLAUDE_PLUGIN_ROOT} but
            # the plugin root could not be inferred from the skill-dir layout
            # AND the env var is unset, silently skipping would drop real
            # references from the compression set. Report and abort instead.
            if has_plugin_root_token(target) and not plugin_root:
                print(
                    f'ERROR=Reference uses ${{CLAUDE_PLUGIN_ROOT}} but plugin root could not be inferred '
                    f'from skill-dir ancestors and $CLAUDE_PLUGIN_ROOT is unset. Referring file: {current}; '
                    f'target: {target}',
                    file=sys.stderr,
                )
                return 1
            if os.path.isabs(target):
                resolved = target
            else:
                resolved = os.path.join(base, target)
            resolved = canonical(resolved)
            if not inside(resolved, skill_dir):
                continue
            if not os.path.isfile(resolved):
                continue
            if resolved in seen:
                continue
            queue.append(resolved)

    with open(args.output, 'wb') as fh:
        for p in order:
            fh.write(p.encode('utf-8'))
            fh.write(b'\0')

    print(f'FILE_COUNT={len(order)}')
    return 0


if __name__ == '__main__':
    sys.exit(main())
