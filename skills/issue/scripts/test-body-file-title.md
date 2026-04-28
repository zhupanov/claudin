# test-body-file-title.sh — sibling contract

**Purpose**: structural regression harness pinning the `--body-file` + trailing title semantics in `/issue` SKILL.md. Asserts that the two-source branching logic (EXPLICIT_TITLE from trailing arg, DESCRIPTION from file) and the backward-compatible derive-from-first-line path are both present in SKILL.md.

**Makefile wiring**: `make test-body-file-title` (listed in both `.PHONY` and `test-harnesses`).

**Assertions** (all positive presence via `grep -qF`):
1. `--body-file` bullet contains "trailing arg is the explicit title" — pins two-source semantics.
2. After-flag-stripping logic contains `EXPLICIT_TITLE` — pins the variable name.
3. Step 3 single-mode contains "if \`EXPLICIT_TITLE\` is set" — pins the two-branch rule.
4. Derive-from-first-line path contains "derived from \`DESCRIPTION\`" — pins backward compatibility.

**Edit-in-sync rules**: if the asserted strings in SKILL.md change (e.g., renaming `EXPLICIT_TITLE` or rewording the `--body-file` bullet), update this harness's `assert_present` needles in the same PR.
