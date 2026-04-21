# lib-count-commits.sh — Shared sourced library that defines count_commits().
#
# This file has NO shebang and is NOT executable — it is intended to be
# sourced (via `source` / `.`) by scripts that need to count commits ahead of
# the repository's main branch.
#
# Sourced by:
#   - scripts/check-bump-version.sh (Step 8/12 bump verification)
#   - scripts/verify-skill-called.sh (generic post-invocation verifier, #160)
#
# Contract:
#   count_commits
#     Prints the number of commits on the current HEAD that are not on main
#     (via `git rev-list main..HEAD --count`) to stdout. Prefers a local
#     `main` ref; falls back to `origin/main` if only the remote ref exists.
#
#     Status side-channel (optional): if the caller sets the environment
#     variable `COUNT_COMMITS_STATUS_FILE` to a writable path before calling
#     count_commits, the function writes one of the following tokens to
#     that file:
#       ok                — count is trustworthy (git rev-list succeeded
#                           against a real base ref).
#       missing_main_ref  — neither local `main` nor `origin/main` exists.
#                           Count is forced to 0; caller MUST treat the
#                           output as untrustworthy.
#       git_error         — a base ref was found, but `git rev-list` failed
#                           (corrupted pack, shallow-clone object boundary,
#                           permission error, etc.). Count is forced to 0;
#                           caller MUST treat the output as untrustworthy.
#     Callers that don't care about status (e.g., check-bump-version.sh's
#     existing callers) leave COUNT_COMMITS_STATUS_FILE unset; the function
#     then only emits the count on stdout. This file-based side channel
#     survives the `$(count_commits)` subshell that bash's command
#     substitution creates (a nameref or unexported global would not).
#
#     Always returns 0 to preserve the KEY=VALUE stdout contract of callers
#     that compose `count_commits` output into their own structured output.
#
# Stderr on the missing-main path:
#   Emits the literal string
#     WARN: check-bump-version.sh: neither local 'main' nor 'origin/main' exists; cannot determine bump base. Returning 0.
#   The `check-bump-version.sh:` prefix is retained for log-parity with
#   operators' existing grep patterns (see #160 FINDING_7). Consumers MAY
#   grep `WARN: check-bump-version.sh:` for this condition. The prefix is
#   intentionally a historical alias — do not rename to `lib-count-commits.sh`
#   without coordinating consumer updates (e.g., skills/implement/references/
#   rebase-rebump-subprocedure.md step 4 notes).
#
# Scope boundary (distinct from classify-bump.sh):
#   `.claude/skills/bump-version/scripts/classify-bump.sh` also resolves a
#   main-vs-origin/main base ref, but uses `git merge-base` to scope the diff
#   for bump-type classification. That is a STRUCTURALLY DIFFERENT question
#   from `git rev-list base..HEAD --count`, so classify-bump.sh is
#   intentionally NOT migrated to this library. If a future issue wants to
#   unify both paths, it must reconcile the merge-base-vs-rev-list semantics
#   first.
#
# shellcheck shell=bash

count_commits() {
    local base_ref="" status="" count=""
    if git rev-parse --verify main >/dev/null 2>&1; then
        base_ref="main"
    elif git rev-parse --verify origin/main >/dev/null 2>&1; then
        base_ref="origin/main"
    fi
    if [[ -z "$base_ref" ]]; then
        echo "WARN: check-bump-version.sh: neither local 'main' nor 'origin/main' exists; cannot determine bump base. Returning 0." >&2
        status="missing_main_ref"
        count="0"
    elif count=$(git rev-list "${base_ref}..HEAD" --count 2>/dev/null); then
        status="ok"
    else
        status="git_error"
        count="0"
    fi
    if [[ -n "${COUNT_COMMITS_STATUS_FILE:-}" ]]; then
        printf '%s\n' "$status" >"$COUNT_COMMITS_STATUS_FILE" 2>/dev/null || true
    fi
    echo "$count"
    return 0
}
