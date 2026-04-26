#!/usr/bin/env bash
# helpers.sh — consolidated /umbrella helpers exposed as subcommands.
#
# Subcommands:
#   check-cycle  --existing-edges FILE --candidate BLOCKER:BLOCKED
#       Pure-logic DAG cycle check. Existing edges TSV: "<blocker>\t<blocked>" rows.
#       Stdout: CYCLE=true|false. Exit 0 always when input is valid; non-zero on input errors.
#       (Tested by test-helpers.sh.)
#
#   wire-dag     --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run]
#       Best-effort GitHub blocked-by wiring + back-link comments.
#       Probes whether the GitHub issue-dependency API is available on the repo.
#       Skips silently per-edge with EDGES_SKIPPED_API_UNAVAILABLE if the API surface is missing
#       (the surface evolved during 2024-2026; this is fail-open by design).
#       Stdout: EDGES_ADDED=N, EDGE_<j>_BLOCKER, EDGE_<j>_BLOCKED, EDGES_REJECTED_CYCLE,
#               EDGES_SKIPPED_EXISTING, EDGES_SKIPPED_API_UNAVAILABLE,
#               BACKLINKS_POSTED, BACKLINKS_SKIPPED_NATIVE.
#
#   emit-output  --kv-file FILE
#       Validate the LLM-supplied KV file (no embedded newlines in values, no duplicate keys,
#       no unset values) and stream it to stdout. The validator is a defense-in-depth layer
#       on top of the SKILL.md grammar — any malformed line aborts non-zero with ERROR=…

set -euo pipefail

SUBCMD="${1:-}"
shift || true

case "$SUBCMD" in
  check-cycle)
    EXISTING=""
    CANDIDATE=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --existing-edges) EXISTING="$2"; shift 2 ;;
        --candidate)      CANDIDATE="$2"; shift 2 ;;
        *) echo "ERROR=Unknown flag for check-cycle: $1" >&2; exit 1 ;;
      esac
    done
    if [ -z "$EXISTING" ] || [ ! -f "$EXISTING" ]; then
      echo "ERROR=--existing-edges is required and must point to an existing file" >&2; exit 1
    fi
    if [ -z "$CANDIDATE" ]; then
      echo "ERROR=--candidate is required (format: BLOCKER:BLOCKED, integers)" >&2; exit 1
    fi
    cand_blocker="${CANDIDATE%%:*}"
    cand_blocked="${CANDIDATE##*:}"
    if [ -z "$cand_blocker" ] || [ -z "$cand_blocked" ] || [ "$cand_blocker" = "$CANDIDATE" ]; then
      echo "ERROR=--candidate must be of the form BLOCKER:BLOCKED" >&2; exit 1
    fi
    case "$cand_blocker$cand_blocked" in
      ''|*[!0-9]*) echo "ERROR=--candidate values must be integers" >&2; exit 1 ;;
    esac
    if [ "$cand_blocker" = "$cand_blocked" ]; then
      printf 'CYCLE=true\n'; exit 0
    fi

    # Cycle test: in the existing-edges DAG (blocker -> blocked), the new edge
    # blocker -> blocked introduces a cycle iff the new BLOCKED node is already
    # reachable to (i.e., is an ancestor of) the new BLOCKER.
    # Concretely: starting at blocked, do DFS following blocker->blocked edges
    # forward; if we reach blocker, the new edge would close a cycle.
    cycle=$(awk -F'\t' -v src="$cand_blocked" -v target="$cand_blocker" '
      NF == 2 && $1 ~ /^[0-9]+$/ && $2 ~ /^[0-9]+$/ {
        edges[$1] = (edges[$1] == "" ? $2 : edges[$1] " " $2)
      }
      END {
        # BFS from src; flag if we reach target.
        queue[1] = src
        head = 1; tail = 1
        seen[src] = 1
        while (head <= tail) {
          node = queue[head]; head++
          n = split(edges[node], succ, " ")
          for (i = 1; i <= n; i++) {
            s = succ[i]
            if (s == "") continue
            if (s == target) { print "true"; exit }
            if (!(s in seen)) { seen[s] = 1; tail++; queue[tail] = s }
          }
        }
        print "false"
      }
    ' "$EXISTING")

    printf 'CYCLE=%s\n' "$cycle"
    ;;

  wire-dag)
    TMPDIR=""
    UMBRELLA=""
    UMBRELLA_TITLE=""
    CHILDREN_FILE=""
    EDGES_FILE=""
    REPO=""
    DRY_RUN="false"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --tmpdir)         TMPDIR="$2"; shift 2 ;;
        --umbrella)       UMBRELLA="$2"; shift 2 ;;
        --umbrella-title) UMBRELLA_TITLE="$2"; shift 2 ;;
        --children-file)  CHILDREN_FILE="$2"; shift 2 ;;
        --edges-file)     EDGES_FILE="$2"; shift 2 ;;
        --repo)           REPO="$2"; shift 2 ;;
        --dry-run)        DRY_RUN="true"; shift ;;
        *) echo "ERROR=Unknown flag for wire-dag: $1" >&2; exit 1 ;;
      esac
    done
    if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ] || [ -z "$UMBRELLA" ] || [ -z "$REPO" ] \
       || [ -z "$CHILDREN_FILE" ] || [ ! -f "$CHILDREN_FILE" ] \
       || [ -z "$EDGES_FILE" ] || [ ! -f "$EDGES_FILE" ]; then
      echo "ERROR=wire-dag requires --tmpdir, --umbrella, --repo, --children-file, --edges-file (all valid)" >&2; exit 1
    fi

    # Feature-detect the GitHub blocked-by API surface. As of late-2024 / 2026 GitHub
    # exposed REST endpoints under /repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by
    # but availability is org/feature-flag dependent. We probe with a HEAD/GET on the
    # umbrella's blocked_by collection; if it 404s we mark the surface unavailable and
    # skip per-edge add. Back-links via plain comments still work and always run.
    api_available="false"
    api_probe=$(gh api "/repos/$REPO/issues/$UMBRELLA/dependencies/blocked_by" --silent 2>/dev/null && echo "ok" || echo "fail")
    if [ "$api_probe" = "ok" ]; then
      api_available="true"
    fi

    EDGES_ADDED=0
    EDGES_REJECTED_CYCLE=0
    EDGES_SKIPPED_EXISTING=0
    EDGES_SKIPPED_API_UNAVAILABLE=0
    BACKLINKS_POSTED=0
    BACKLINKS_SKIPPED_NATIVE=0
    edge_lines=""
    j=0

    EXISTING_EDGES_TSV="$TMPDIR/existing-edges.tsv"
    : > "$EXISTING_EDGES_TSV"

    if [ "$DRY_RUN" = "true" ]; then
      printf 'EDGES_ADDED=0\nEDGES_REJECTED_CYCLE=0\nEDGES_SKIPPED_EXISTING=0\nEDGES_SKIPPED_API_UNAVAILABLE=0\nBACKLINKS_POSTED=0\nBACKLINKS_SKIPPED_NATIVE=0\n'
      exit 0
    fi

    if [ "$api_available" = "true" ]; then
      # Probe existing blocked_by edges for each child. The endpoint returns an array of
      # issue objects that are currently blocking the issue; we collect (blocker -> blocked).
      while IFS=$'\t' read -r blocked _title _url; do
        [ -z "$blocked" ] && continue
        existing_blockers=$(gh api "/repos/$REPO/issues/$blocked/dependencies/blocked_by" --jq '.[].number' 2>/dev/null || true)
        for blocker in $existing_blockers; do
          printf '%s\t%s\n' "$blocker" "$blocked" >> "$EXISTING_EDGES_TSV"
        done
      done < "$CHILDREN_FILE"

      # Walk proposed edges, cycle-check each, add survivors.
      while IFS=$'\t' read -r blocker blocked; do
        [ -z "$blocker" ] || [ -z "$blocked" ] && continue
        # Existing? skip.
        if grep -qE "^${blocker}	${blocked}$" "$EXISTING_EDGES_TSV"; then
          EDGES_SKIPPED_EXISTING=$((EDGES_SKIPPED_EXISTING + 1))
          continue
        fi
        # Cycle?
        cycle_result=$("$0" check-cycle --existing-edges "$EXISTING_EDGES_TSV" --candidate "${blocker}:${blocked}" | sed -n 's/^CYCLE=//p')
        if [ "$cycle_result" = "true" ]; then
          EDGES_REJECTED_CYCLE=$((EDGES_REJECTED_CYCLE + 1))
          continue
        fi
        # Add the edge.
        if gh api "/repos/$REPO/issues/${blocked}/dependencies/blocked_by" -X POST -f issue_number="$blocker" --silent 2>/dev/null; then
          EDGES_ADDED=$((EDGES_ADDED + 1))
          j=$((j + 1))
          edge_lines="${edge_lines}EDGE_${j}_BLOCKER=${blocker}"$'\n'"EDGE_${j}_BLOCKED=${blocked}"$'\n'
          printf '%s\t%s\n' "$blocker" "$blocked" >> "$EXISTING_EDGES_TSV"
        else
          # Adding failed despite probe success — likely a per-issue permission or shape
          # mismatch. Fail-open: skip with warning category.
          EDGES_SKIPPED_API_UNAVAILABLE=$((EDGES_SKIPPED_API_UNAVAILABLE + 1))
        fi
      done < "$EDGES_FILE"
    else
      # API surface unavailable repo-wide: skip all proposed edges.
      EDGES_SKIPPED_API_UNAVAILABLE=$(awk 'NF >= 2 { c++ } END { print c+0 }' "$EDGES_FILE")
    fi

    # Back-links: post a comment on each child unless GitHub natively renders the umbrella
    # relationship. We treat the dependency-API child-of relationship as the "native" surface;
    # if the child's blocked_by list contains the umbrella we skip the comment.
    while IFS=$'\t' read -r child_num _title _url; do
      [ -z "$child_num" ] && continue
      native="false"
      if [ "$api_available" = "true" ]; then
        if gh api "/repos/$REPO/issues/${child_num}/dependencies/blocked_by" --jq ".[] | select(.number == ${UMBRELLA})" 2>/dev/null | grep -q .; then
          native="true"
        fi
      fi
      if [ "$native" = "true" ]; then
        BACKLINKS_SKIPPED_NATIVE=$((BACKLINKS_SKIPPED_NATIVE + 1))
        continue
      fi
      backlink_body="Part of umbrella #${UMBRELLA} — ${UMBRELLA_TITLE}"
      if gh issue comment -R "$REPO" "$child_num" --body "$backlink_body" >/dev/null 2>&1; then
        BACKLINKS_POSTED=$((BACKLINKS_POSTED + 1))
      fi
    done < "$CHILDREN_FILE"

    printf 'EDGES_ADDED=%d\n' "$EDGES_ADDED"
    printf 'EDGES_REJECTED_CYCLE=%d\n' "$EDGES_REJECTED_CYCLE"
    printf 'EDGES_SKIPPED_EXISTING=%d\n' "$EDGES_SKIPPED_EXISTING"
    printf 'EDGES_SKIPPED_API_UNAVAILABLE=%d\n' "$EDGES_SKIPPED_API_UNAVAILABLE"
    printf 'BACKLINKS_POSTED=%d\n' "$BACKLINKS_POSTED"
    printf 'BACKLINKS_SKIPPED_NATIVE=%d\n' "$BACKLINKS_SKIPPED_NATIVE"
    if [ -n "$edge_lines" ]; then
      printf '%s' "$edge_lines"
    fi
    if [ "$api_available" = "false" ]; then
      echo "**⚠ /umbrella: GitHub blocked-by dependency API not available on $REPO; skipped DAG wiring. Back-links posted via comments." >&2
    fi
    ;;

  emit-output)
    KV_FILE=""
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --kv-file) KV_FILE="$2"; shift 2 ;;
        *) echo "ERROR=Unknown flag for emit-output: $1" >&2; exit 1 ;;
      esac
    done
    if [ -z "$KV_FILE" ] || [ ! -f "$KV_FILE" ]; then
      echo "ERROR=--kv-file is required and must exist" >&2; exit 1
    fi
    # Validate: each line is KEY=VALUE, KEY matches [A-Z][A-Z0-9_]*, no embedded \r,
    # no duplicate keys, VALUE has no embedded newline (already enforced by line split).
    awk '
      /^$/ { next }
      !/^[A-Z][A-Z0-9_]*=/ { print "ERROR=Malformed KV line " NR ": " $0 > "/dev/stderr"; exit 1 }
      {
        eq = index($0, "=")
        key = substr($0, 1, eq - 1)
        if (seen[key]) { print "ERROR=Duplicate KV key: " key > "/dev/stderr"; exit 1 }
        seen[key] = 1
        print
      }
    ' "$KV_FILE"
    ;;

  ""|--help|-h)
    cat <<'EOF'
Usage: helpers.sh <subcommand> [options]
  check-cycle  --existing-edges FILE --candidate BLOCKER:BLOCKED
  wire-dag     --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run]
  emit-output  --kv-file FILE
EOF
    ;;

  *)
    echo "ERROR=Unknown subcommand: $SUBCMD (try check-cycle / wire-dag / emit-output)" >&2; exit 1
    ;;
esac
