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
#       Skips silently per-edge with EDGES_SKIPPED_API_UNAVAILABLE for true feature-missing
#       (the surface evolved during 2024-2026; this is fail-open by design).
#       Distinguishes operational failures (rate-limit, permission denied, ambiguous 404,
#       5xx, request-shape mismatches, network) under EDGES_FAILED with one redacted
#       stderr warning per failed edge (issue #720). Idempotent 422 already-exists
#       responses land in EDGES_SKIPPED_EXISTING. Per-edge POST body uses the canonical
#       {"issue_id": <internal numeric id>} shape matching add-blocked-by.sh; blocker
#       internal ids are resolved via gh api and cached per run.
#       Stdout: EDGES_ADDED=N, EDGE_<j>_BLOCKER, EDGE_<j>_BLOCKED, EDGES_REJECTED_CYCLE,
#               EDGES_SKIPPED_EXISTING, EDGES_SKIPPED_API_UNAVAILABLE, EDGES_FAILED,
#               BACKLINKS_POSTED, BACKLINKS_SKIPPED_NATIVE.
#
#   emit-output  --kv-file FILE
#       Validate the LLM-supplied KV file (well-formed KEY=VALUE lines, no embedded newlines
#       in values, no duplicate keys) and stream it to stdout. The validator is a
#       defense-in-depth layer on top of the SKILL.md Step 4 grammar — any malformed line
#       aborts non-zero with ERROR=… Stderr is reserved for parse/validation/usage errors
#       only; the human summary breadcrumb is emitted by the orchestrator at SKILL.md
#       Step 4, not by this subcommand.

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
    EDGES_FAILED=0
    BACKLINKS_POSTED=0
    BACKLINKS_SKIPPED_NATIVE=0
    edge_lines=""
    j=0

    # One-time guard for redact-secrets.sh fallback (issue #720, FINDING_6).
    # Set to 1 after the first stderr notice so the per-edge loop does not spam.
    REDACT_FALLBACK_WARNED=0
    # Resolve canonical secret-scrubber relative to this script's location.
    # helpers.sh is at .claude/skills/umbrella/scripts/helpers.sh — climb four
    # levels to reach the repo root that owns scripts/redact-secrets.sh.
    REDACT_SCRIPT="$(cd "$(dirname "$0")/../../../.." 2>/dev/null && pwd)/scripts/redact-secrets.sh"

    # Per-run cache mapping blocker display number -> blocker internal numeric id.
    # The GitHub Issue Dependencies POST body requires `issue_id` (internal id),
    # not `issue_number` (display number) — see add-blocked-by.sh:170.
    declare -A BLOCKER_ID_CACHE 2>/dev/null || true

    # Per-run cache for blocked_by lookups (issue #718). Key: node display number;
    # value: space-separated blocker numbers, OR the literal sentinel "_GH_FAIL_"
    # when the lookup transiently failed.
    declare -A BLOCKED_BY_CACHE 2>/dev/null || true

    # Per-node lookup-failure flag: suppresses repeat warnings on cache reuse.
    declare -A _WD_LOOKUP_FAILED 2>/dev/null || true

    # Set when the transitive traversal hit WIRE_DAG_TRAVERSAL_NODE_CAP. When 1,
    # the per-edge cycle-check loop routes any CYCLE=false candidate to
    # EDGES_FAILED with reason "bound-exhausted" (DECISION_1, voted 3-0):
    # the negative cycle answer cannot be trusted on a known-incomplete TSV.
    _wd_traversal_truncated=0

    # Per-run cap on distinct nodes the BFS may materialize. Override via
    # WIRE_DAG_TRAVERSAL_NODE_CAP. Total gh API calls across the run are
    # bounded by min(cap, |reachable closure|) once BLOCKED_BY_CACHE de-dups
    # repeat queries (DECISION_2, voted 2-1).
    WD_NODE_CAP="${WIRE_DAG_TRAVERSAL_NODE_CAP:-200}"

    EXISTING_EDGES_TSV="$TMPDIR/existing-edges.tsv"
    : > "$EXISTING_EDGES_TSV"

    if [ "$DRY_RUN" = "true" ]; then
      printf 'EDGES_ADDED=0\nEDGES_REJECTED_CYCLE=0\nEDGES_SKIPPED_EXISTING=0\nEDGES_SKIPPED_API_UNAVAILABLE=0\nEDGES_FAILED=0\nBACKLINKS_POSTED=0\nBACKLINKS_SKIPPED_NATIVE=0\n'
      exit 0
    fi

    # Emit one redacted stderr warning per EDGES_FAILED event (issue #720).
    # Pipes captured response through scripts/redact-secrets.sh when present;
    # falls back to inline tr+head with a one-time process-local notice when
    # missing (degraded-layout safety). Format aligns the new warning with the
    # existing repo-wide warning prefix at the bottom of this branch — both use
    # the `/umbrella:` namespace so log triage stays consistent.
    emit_edge_failure_warning() {
      local blocker="$1" blocked="$2" code="$3" raw="$4"
      local flat redacted
      flat=$(printf '%s' "$raw" | tr '\n\r' '  ' | head -c 200)
      if [ -x "$REDACT_SCRIPT" ]; then
        if redacted=$(printf '%s' "$flat" | "$REDACT_SCRIPT" 2>/dev/null); then
          : # success path
        else
          # Redactor exists but exited non-zero — fail closed: do NOT print the
          # raw flattened body, which could leak secrets the redactor would
          # have caught. Substitute a constant placeholder and warn once
          # (issue #720 FINDING_4).
          if [ "$REDACT_FALLBACK_WARNED" = "0" ]; then
            echo "**⚠ /umbrella: wire-dag — redact-secrets.sh exited non-zero; suppressing reason text for safety**" >&2
            REDACT_FALLBACK_WARNED=1
          fi
          redacted="<REDACTION_FAILED>"
        fi
      else
        if [ "$REDACT_FALLBACK_WARNED" = "0" ]; then
          echo "**⚠ /umbrella: wire-dag — redact-secrets.sh not found at $REDACT_SCRIPT; using inline-fallback scrub**" >&2
          REDACT_FALLBACK_WARNED=1
        fi
        redacted="$flat"
      fi
      echo "**⚠ /umbrella: wire-dag edge ${blocker}->${blocked} failed (HTTP ${code}): ${redacted}**" >&2
    }

    # _wd_blocked_by_lookup <node>
    # Returns space-separated blocker numbers for <node>, or empty on either
    # "no blockers" or "transient lookup failure". Caches per run. On gh failure
    # caches the literal sentinel "_GH_FAIL_" and emits a one-time stderr
    # warning per failed node (residual fail-open posture acknowledged in
    # helpers.md; FINDING_5 was exonerated 2-1 — preserves the existing
    # individual-API-blip fail-open posture).
    _wd_blocked_by_lookup() {
      local node="$1"
      if [ -n "${BLOCKED_BY_CACHE[$node]+x}" ]; then
        local cached="${BLOCKED_BY_CACHE[$node]}"
        if [ "$cached" = "_GH_FAIL_" ]; then
          printf ''
        else
          printf '%s' "$cached"
        fi
        return 0
      fi
      local raw rc
      set +e
      raw=$(gh api "/repos/$REPO/issues/${node}/dependencies/blocked_by" --paginate --jq '.[].number' 2>/dev/null)
      rc=$?
      set -e
      if [ "$rc" -ne 0 ]; then
        BLOCKED_BY_CACHE[$node]="_GH_FAIL_"
        if [ -z "${_WD_LOOKUP_FAILED[$node]+x}" ]; then
          _WD_LOOKUP_FAILED[$node]=1
          echo "**⚠ /umbrella: wire-dag blocked_by lookup failed for #${node} — treating as no edges**" >&2
        fi
        printf ''
        return 0
      fi
      # Convert newline-delimited gh output to a space-separated string suitable
      # for unquoted iteration via `for b in ${BLOCKED_BY_CACHE[$node]}` (per
      # FINDING_1 — pinning the capture/iterate mechanism explicitly).
      local flat
      flat=$(printf '%s' "$raw" | tr '\n' ' ')
      flat="${flat% }"
      BLOCKED_BY_CACHE[$node]="$flat"
      printf '%s' "$flat"
    }

    # _wd_populate_existing_edges_transitively <existing_edges_tsv>
    # Worklist BFS over blocked_by. Seed worklist with children + both endpoints
    # of every row in EDGES_FILE. Bounded by WD_NODE_CAP distinct nodes; sets
    # _wd_traversal_truncated=1 if the cap fires. Issue #718.
    #
    # Invariant (FINDING_3): when dequeuing `node`, for every blocker `b`
    # returned by _wd_blocked_by_lookup(node):
    #   (a) ALWAYS append `b\tnode` to the TSV regardless of seen-set state,
    #   (b) only mark seen and enqueue `b` if not yet in _seen_set.
    # The seen-set guards re-querying only — it MUST NOT short-circuit append.
    _wd_populate_existing_edges_transitively() {
      local existing_tsv="$1"
      declare -A _seen_set 2>/dev/null || true
      local queue=()
      local distinct_count=0
      local start_ts="$SECONDS"

      # Seed from CHILDREN_FILE (one issue per line, tab-separated columns).
      while IFS=$'\t' read -r child_num _title _url; do
        [ -z "$child_num" ] && continue
        if [ -z "${_seen_set[$child_num]+x}" ]; then
          _seen_set[$child_num]=1
          queue+=("$child_num")
          distinct_count=$((distinct_count + 1))
        fi
      done < "$CHILDREN_FILE"

      # Seed from EDGES_FILE endpoints (both blocker AND blocked).
      while IFS=$'\t' read -r blocker blocked; do
        [ -z "$blocker" ] || [ -z "$blocked" ] && continue
        for endpoint in "$blocker" "$blocked"; do
          if [ -z "${_seen_set[$endpoint]+x}" ]; then
            _seen_set[$endpoint]=1
            queue+=("$endpoint")
            distinct_count=$((distinct_count + 1))
          fi
        done
      done < "$EDGES_FILE"

      while [ "${#queue[@]}" -gt 0 ]; do
        local node="${queue[0]}"
        queue=("${queue[@]:1}")
        local blockers
        blockers=$(_wd_blocked_by_lookup "$node")
        for b in $blockers; do
          [ -z "$b" ] && continue
          # Append unconditionally (FINDING_3).
          printf '%s\t%s\n' "$b" "$node" >> "$existing_tsv"
          if [ -z "${_seen_set[$b]+x}" ]; then
            _seen_set[$b]=1
            distinct_count=$((distinct_count + 1))
            if [ "$distinct_count" -gt "$WD_NODE_CAP" ]; then
              _wd_traversal_truncated=1
              local elapsed=$((SECONDS - start_ts))
              echo "**⚠ /umbrella: wire-dag traversal cap reached (cap=${WD_NODE_CAP}, queue=${#queue[@]}, elapsed=${elapsed}s) — pending candidates will fail closed**" >&2
              return 0
            fi
            queue+=("$b")
          fi
        done
      done
    }

    if [ "$api_available" = "true" ]; then
      # Issue #718: build EXISTING_EDGES_TSV from the full reachable blocked_by
      # subgraph (children + both endpoints of every proposed edge), not just
      # children's direct blocked_by. Cycles closing through non-child
      # intermediaries are now visible to check-cycle. Bounded by WD_NODE_CAP.
      _wd_populate_existing_edges_transitively "$EXISTING_EDGES_TSV"

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
        # Cap-hit fail-closed (DECISION_1, voted 3-0): when the transitive
        # traversal truncated, the existing-edges TSV is known-incomplete, so a
        # CYCLE=false answer cannot be trusted. Bucket the candidate as
        # EDGES_FAILED with reason "bound-exhausted" rather than POSTing.
        if [ "$_wd_traversal_truncated" = "1" ]; then
          EDGES_FAILED=$((EDGES_FAILED + 1))
          emit_edge_failure_warning "$blocker" "$blocked" "bound-exhausted" "traversal cap reached during populate; CYCLE=false on incomplete TSV cannot be trusted"
          continue
        fi

        # Resolve the blocker's internal numeric id (cached per run). The Issue
        # Dependencies POST body shape is {"issue_id": <id>}, NOT issue_number
        # — see add-blocked-by.sh:170. The previous shape silently 422'd here
        # and the ambiguous failure was bucketed as "API unavailable" (#720).
        blocker_id="${BLOCKER_ID_CACHE[$blocker]:-}"
        if [ -z "$blocker_id" ]; then
          set +e
          blocker_id=$(gh api "/repos/$REPO/issues/$blocker" --jq '.id' 2>/dev/null)
          lookup_rc=$?
          set -e
          if [ "$lookup_rc" -ne 0 ] || [ -z "$blocker_id" ] || ! printf '%s' "$blocker_id" | grep -qE '^[0-9]+$'; then
            EDGES_FAILED=$((EDGES_FAILED + 1))
            emit_edge_failure_warning "$blocker" "$blocked" "id-lookup" "blocker-id resolution failed for #$blocker"
            continue
          fi
          BLOCKER_ID_CACHE[$blocker]="$blocker_id"
        fi

        # POST {"issue_id": <id>} with -i so we can classify by HTTP status.
        # Wrap in set +e/-e so gh's non-zero exit on >=400 does not abort.
        # Stderr is dropped (NOT merged via 2>&1): gh may emit deprecation
        # notices or auth-token warnings before the HTTP response, which would
        # otherwise corrupt the first-line status parse and pollute body
        # content scanned by the feature-missing fingerprint regex (issue #720
        # FINDING_1). The non-zero exit on 4xx/5xx still propagates through
        # the subshell exit status — set +e absorbs it.
        body_json=$(jq -nc --argjson id "$blocker_id" '{issue_id: $id}')
        set +e
        resp=$(printf '%s' "$body_json" | gh api "/repos/$REPO/issues/${blocked}/dependencies/blocked_by" -X POST --input - -i 2>/dev/null)
        set -e

        # Status from first line; body skips HTTP headers (split at first blank
        # line) so the feature-missing regex cannot match a header value.
        status_code=$(printf '%s\n' "$resp" | awk 'NR==1{print $2; exit}')
        body=$(printf '%s\n' "$resp" | awk 'BEGIN{skip=1} /^[[:space:]]*\r?$/{skip=0;next} !skip{print}')

        case "$status_code" in
          2*)
            EDGES_ADDED=$((EDGES_ADDED + 1))
            j=$((j + 1))
            edge_lines="${edge_lines}EDGE_${j}_BLOCKER=${blocker}"$'\n'"EDGE_${j}_BLOCKED=${blocked}"$'\n'
            printf '%s\t%s\n' "$blocker" "$blocked" >> "$EXISTING_EDGES_TSV"
            ;;
          404)
            # Conservative: BOTH a "dependencies / blocked_by / sub-issue" keyword
            # AND a "not found / does not exist / no longer (available|supported)"
            # phrase must appear in the body before we credit "feature missing".
            # Ambiguous 404s (e.g., stale child issue) fall to EDGES_FAILED so
            # operators see a real diagnostic instead of a silent skip.
            if printf '%s' "$body" | grep -qiE '(dependencies|blocked_by|sub.?issue)' \
                 && printf '%s' "$body" | grep -qiE 'not (be )?found|does not exist|no longer (available|supported)'; then
              EDGES_SKIPPED_API_UNAVAILABLE=$((EDGES_SKIPPED_API_UNAVAILABLE + 1))
            else
              EDGES_FAILED=$((EDGES_FAILED + 1))
              emit_edge_failure_warning "$blocker" "$blocked" "$status_code" "$body"
            fi
            ;;
          422)
            # Idempotent already-exists per add-blocked-by.sh:193-196. Race-safe:
            # another runner can add the edge between our existing-edges read and
            # our POST; treating that as success keeps the counter honest.
            if printf '%s' "$body" | grep -qiE 'already (exists|tracked|added)|duplicate dependency'; then
              EDGES_SKIPPED_EXISTING=$((EDGES_SKIPPED_EXISTING + 1))
              printf '%s\t%s\n' "$blocker" "$blocked" >> "$EXISTING_EDGES_TSV"
            else
              EDGES_FAILED=$((EDGES_FAILED + 1))
              emit_edge_failure_warning "$blocker" "$blocked" "$status_code" "$body"
            fi
            ;;
          ""|*)
            EDGES_FAILED=$((EDGES_FAILED + 1))
            emit_edge_failure_warning "$blocker" "$blocked" "${status_code:-network}" "$body"
            ;;
        esac
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
    printf 'EDGES_FAILED=%d\n' "$EDGES_FAILED"
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
