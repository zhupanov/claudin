# shellcheck shell=bash
# anchor-section-markers.sh — single source of truth for the 8 canonical
# anchor section slugs, in assembly / truncation order.
#
# Sourced by:
#   - scripts/tracking-issue-write.sh  (per-section + body-level truncation)
#   - scripts/assemble-anchor.sh       (anchor-body assembly)
#
# NOT a standalone script: no set -euo pipefail, no main entry, no flag
# parsing. The file exposes one read-only contract: the SECTION_MARKERS
# array. Consumers source this file early (after SCRIPT_DIR resolution)
# and reference the array thereafter.
#
# Edit-in-sync:
#   - skills/implement/references/anchor-comment-template.md documents the
#     same 8 slugs as a human-readable anchor body template. The array
#     below is the executable source of truth.
#   - scripts/tracking-issue-write.sh's COLLAPSE_PRIORITY array is the
#     body-cap collapse order (different ordering, same slug set).
#     An invariant assertion in scripts/test-tracking-issue-write.sh
#     pins that every SECTION_MARKERS slug appears in COLLAPSE_PRIORITY.

# shellcheck disable=SC2034
# SECTION_MARKERS is consumed by the callers that source this file
# (scripts/tracking-issue-write.sh and scripts/assemble-anchor.sh). It is
# not referenced inside this file — that is by design.
SECTION_MARKERS=(plan-goals-test plan-review-tally code-review-tally diagrams version-bump-reasoning oos-issues execution-issues run-statistics)
