# scripts/check-changelog-present.sh — contract

`scripts/check-changelog-present.sh` is the `/implement` Step 8a presence probe for the project-root `CHANGELOG.md`. It exists to replace the prior model-judgment branch in Step 8a — the SKILL.md instruction "Skip and proceed to Step 8b if `CHANGELOG.md` does not exist in the project root" had no scripted enforcement, so a sloppy model could emit the skip line without actually testing for the file (observed false-negative: a `/imaq` run printed `skipped (no CHANGELOG.md)` on a repo whose `CHANGELOG.md` had 3065 lines and was current as of the most recent commit).

The script always exits 0 — presence is informational, not an error condition — and prints exactly one stdout line `CHANGELOG_PRESENT=true|false`. The repo root is resolved via `git rev-parse --show-toplevel` with `$PWD` fallback when not inside a git work tree (defensive — Step 8a always runs inside a git repo, but keep the script standalone-callable).

Step 8a parses the printed value and includes it verbatim in the skip-print breadcrumb (`⏩ 8a: changelog — skipped (CHANGELOG_PRESENT=false) (<elapsed>)`) so a false skip is visible in the transcript.

No regression harness yet — the script is small, dependency-free, and called only from `/implement` Step 8a; manual verification at write time covers both branches. Add a harness if behavior is extended (e.g., supporting alternative changelog filenames or non-root locations).
