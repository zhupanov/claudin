# skills/implement/scripts/check-review-changes.sh — contract

`skills/implement/scripts/check-review-changes.sh` is the `/implement` Step 6 (Relevant Checks, second pass) probe that decides whether the code-review step modified the working tree. Output: a single `FILES_CHANGED=true|false` line on stdout. Detection unions three sources — unstaged modifications (`git diff --name-only`), staged modifications (`git diff --name-only --cached`), and untracked files (`git ls-files --others --exclude-standard`); any non-empty source flips the flag. Always exits 0 (read-only probe; transient `git` errors degrade to empty output rather than non-zero exit).

**Known limitation**: any pre-existing untracked file in the working tree at Step 6 entry flips `FILES_CHANGED=true` even when the code-review step itself made no changes. Step 6 then runs a no-op `/relevant-checks` pass and Step 7 may attempt to commit the unrelated untracked files. Operators should keep the working tree clean of untracked scratch files before invoking `/implement`.

**Invariants**: read-only (no working-tree mutation); idempotent (repeated calls return the same `FILES_CHANGED` value when the working tree is unchanged); exit code is always 0 — callers parse `FILES_CHANGED` rather than branching on `$?`.

**Call sites**: `skills/implement/SKILL.md` Step 6 (sole consumer) — the printed `FILES_CHANGED` value gates whether Step 6 runs `/relevant-checks` and whether Step 7 creates a `Address code review feedback` commit. No test harness or Makefile wiring; the script's behavior is exercised end-to-end by `/implement` runs.

**Edit-in-sync**: behavior changes (new detection source, exit-code semantics, output token rename) must be mirrored in this file AND in Step 6 of `skills/implement/SKILL.md` in the same PR — Step 6's branch logic parses the `FILES_CHANGED` token verbatim.
