#!/usr/bin/env bash
# helpers.sh — consolidated /umbrella helpers exposed as subcommands.
#
# Subcommands:
#   check-cycle  --existing-edges FILE --candidate BLOCKER:BLOCKED
#       Pure-logic DAG cycle check. Existing edges TSV: "<blocker>\t<blocked>" rows.
#       Stdout: CYCLE=true|false. Exit 0 always when input is valid; non-zero on input errors.
#       (Tested by test-helpers.sh.)
#
#   wire-dag     --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run] [--no-backlinks]
#       Best-effort GitHub blocked-by wiring + back-link comments.
#       --no-backlinks (created-eq-1 bypass): omit back-link comments AND the
#       umbrella-rooted API probe; probe the first child in CHILDREN_FILE for
#       API availability instead. --umbrella may be empty when --no-backlinks
#       is set; otherwise --umbrella is required.
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
#               PROBE_FAILED (parse-only, 0|1, issue #728 — disambiguates the cause
#                 behind any EDGES_SKIPPED_API_UNAVAILABLE bulk-skip; see helpers.md),
#               BACKLINKS_POSTED, BACKLINKS_SKIPPED_EXISTING.
#
#   prefix-titles --umbrella N --children-file F --repo R [--dry-run]
#       Prepend "(Umbrella: <N>) " to the title of every issue listed in
#       CHILDREN_FILE. Idempotent: a title that already starts with the exact
#       "(Umbrella: <N>) " prefix is left alone (TITLES_SKIPPED_EXISTING).
#       Best-effort gh issue edit per row; failures are bucketed in
#       TITLES_FAILED with one redacted stderr warning per failure.
#       Caller is expected to filter CHILDREN_FILE down to newly-created
#       children only (dedup'd / failed / dry-run children must not be passed
#       in — they belong to other umbrellas or do not exist on GitHub).
#       Stdout: TITLES_RENAMED=N, TITLES_SKIPPED_EXISTING=N, TITLES_FAILED=N.
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
    NO_BACKLINKS="false"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --tmpdir)         TMPDIR="$2"; shift 2 ;;
        --umbrella)       UMBRELLA="$2"; shift 2 ;;
        --umbrella-title) UMBRELLA_TITLE="$2"; shift 2 ;;
        --children-file)  CHILDREN_FILE="$2"; shift 2 ;;
        --edges-file)     EDGES_FILE="$2"; shift 2 ;;
        --repo)           REPO="$2"; shift 2 ;;
        --dry-run)        DRY_RUN="true"; shift ;;
        --no-backlinks)   NO_BACKLINKS="true"; shift ;;
        *) echo "ERROR=Unknown flag for wire-dag: $1" >&2; exit 1 ;;
      esac
    done
    # --umbrella is required UNLESS --no-backlinks is set (created-eq-1 bypass path
    # has no umbrella issue; see SKILL.md Step 3B.2 created-eq-1 branch).
    if [ -z "$TMPDIR" ] || [ ! -d "$TMPDIR" ] || [ -z "$REPO" ] \
       || [ -z "$CHILDREN_FILE" ] || [ ! -f "$CHILDREN_FILE" ] \
       || [ -z "$EDGES_FILE" ] || [ ! -f "$EDGES_FILE" ]; then
      echo "ERROR=wire-dag requires --tmpdir, --repo, --children-file, --edges-file (all valid)" >&2; exit 1
    fi
    if [ "$NO_BACKLINKS" != "true" ] && [ -z "$UMBRELLA" ]; then
      echo "ERROR=wire-dag requires --umbrella (use --no-backlinks to omit it on the created-eq-1 bypass path)" >&2; exit 1
    fi
    # Numeric grammar guard (closes #775 — unified grep -F doctrine, input-boundary
    # hardening). Reject any non-empty UMBRELLA that is not a positive integer:
    # leading zeros ('01'), embedded decimals ('1.2'), regex metacharacters
    # ('1[', '[abc]'), and whitespace-padded values (' 5 ') all fail. The
    # [ -n "$UMBRELLA" ] gate preserves the empty-string + --no-backlinks bypass
    # path (test-helpers.sh case (m) — empty --umbrella with --no-backlinks).
    # Mirrors the WD_NODE_CAP validation pattern
    # at line ~417 below. CLI tightening is intentional: junk on the --no-backlinks
    # bypass path was a latent contract gap; any future caller supplying
    # non-numeric UMBRELLA now fails fast at parse time rather than producing an
    # invalid-ERE grep that swallows silently into a surrounding "|| true".
    if [ -n "$UMBRELLA" ] && ! printf '%s' "$UMBRELLA" | grep -qE '^[1-9][0-9]*$'; then
      echo "ERROR=wire-dag --umbrella must be a positive integer (got: '$UMBRELLA')" >&2; exit 1
    fi

    # Dry-run short-circuit: hoisted ahead of the probe block (issue #769) so
    # `--dry-run` is side-effect-free — no GitHub API round-trip, no stderr
    # warnings, no UMBRELLA_PROBE_TARGET_FILE write. Mirrors the prefix-titles
    # subcommand's pattern below. Stdout grammar is preserved (8 keys including
    # PROBE_FAILED=0 as a literal so the parse-only contract holds without
    # depending on the variable's later initialization).
    if [ "$DRY_RUN" = "true" ]; then
      printf 'EDGES_ADDED=0\nEDGES_REJECTED_CYCLE=0\nEDGES_SKIPPED_EXISTING=0\nEDGES_SKIPPED_API_UNAVAILABLE=0\nEDGES_FAILED=0\nPROBE_FAILED=0\nBACKLINKS_POSTED=0\nBACKLINKS_SKIPPED_EXISTING=0\n'
      exit 0
    fi

    # Feature-detect the GitHub blocked-by API surface. As of late-2024 / 2026 GitHub
    # exposed REST endpoints under /repos/{owner}/{repo}/issues/{number}/dependencies/blocked_by
    # but availability is org/feature-flag dependent. We probe with a HEAD/GET on the
    # umbrella's blocked_by collection; if it 404s we mark the surface unavailable and
    # skip per-edge add. Back-links via plain comments still work and always run.
    #
    # On --no-backlinks (created-eq-1 bypass), there is no umbrella to probe; fall
    # back to probing the FIRST CHILD in CHILDREN_FILE (children always exist on
    # the bypass path). Without this fallback, an empty $UMBRELLA would 404 and
    # incorrectly mark the API unavailable repo-wide.
    if [ "$NO_BACKLINKS" = "true" ]; then
      probe_target=$(awk -F'\t' 'NR == 1 && $1 != "" { print $1; exit }' "$CHILDREN_FILE")
      if [ -z "$probe_target" ]; then
        # No children in CHILDREN_FILE — leave api_available=false (no edges to wire anyway).
        probe_target=""
      fi
    else
      probe_target="$UMBRELLA"
    fi

    # PROBE_FAILED=0|1 (issue #728): parse-only disambiguator distinguishing
    # confirmed feature-missing (PROBE_FAILED=0) from transient/operational
    # probe failure (PROBE_FAILED=1). Initialized here so it has a defined
    # value on every code path including the empty-probe-target path below.
    # The DRY_RUN early-exit (above) emits PROBE_FAILED=0 as a literal in its
    # stdout printf and never reaches this initialization.
    PROBE_FAILED=0

    # Resolve the canonical secret-scrubber and the one-time redact-fallback
    # guard early so emit_probe_failure_warning (defined below) can use them.
    # The per-edge emit_edge_failure_warning helper later in this branch
    # references the same names — these initializations are intentionally
    # placed before the probe block to avoid forward references.
    REDACT_SCRIPT="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/scripts/redact-secrets.sh"
    REDACT_FALLBACK_WARNED=0

    # _wd_is_feature_missing_404 <body>: dual-regex fingerprint shared by the
    # repo-wide probe (issue #728) and the per-edge POST handler (issue #720).
    # Returns 0 when both regexes match the body, 1 otherwise.
    _wd_is_feature_missing_404() {
      local body="$1"
      if printf '%s' "$body" | grep -qiE '(dependencies|blocked_by|sub.?issue)' \
           && printf '%s' "$body" | grep -qiE 'not (be )?found|does not exist|no longer (available|supported)'; then
        return 0
      fi
      return 1
    }

    # emit_probe_failure_warning <status> <raw>: emit one redacted stderr
    # warning when the repo-wide probe failed transiently / operationally
    # (issue #728). Mirrors emit_edge_failure_warning's fail-closed redaction
    # discipline. See helpers.md stderr-prefix section.
    emit_probe_failure_warning() {
      local code="$1" raw="$2"
      local flat redacted
      flat=$(printf '%s' "$raw" | tr '\n\r' '  ' | head -c 200)
      if [ -x "$REDACT_SCRIPT" ]; then
        if redacted=$(printf '%s' "$flat" | "$REDACT_SCRIPT" 2>/dev/null); then
          : # success path
        else
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
      echo "**⚠ /umbrella: wire-dag probe failed (HTTP ${code}): ${redacted}**" >&2
    }

    # Status-aware probe (issue #728) — replaces the old binary
    # `gh api ... --silent && echo ok || echo fail` with a three-way classification:
    #   2xx                  -> api_available=true,  PROBE_FAILED=0
    #   404 + fingerprint    -> api_available=false, PROBE_FAILED=0  (feature missing)
    #   429 / other 4xx      -> api_available=false, PROBE_FAILED=1  (no retry — clear HTTP response, not transport blip)
    #   5xx / empty-status   -> retry once. If second attempt also fails to classify,
    #                           api_available=false, PROBE_FAILED=1.
    # Retry policy (DECISION_1, dialectic 2-1 ANTI_THESIS): one retry only,
    # scoped to 5xx and empty-status (the unclassifiable transport-blip class).
    api_available="false"
    # probe_attempted distinguishes "probe ran and concluded feature-missing"
    # (PROBE_FAILED=0, fire legacy "API not available" warning) from
    # "no probe was attempted at all" because probe_target is empty
    # (PROBE_FAILED=0, suppress the warning — the diagnosis would be false).
    probe_attempted=0
    if [ -n "$probe_target" ]; then
      probe_attempted=1
      # Optional test-stub hook: when set, record the probe URL so test-helpers.sh
      # can assert which issue was targeted. Production callers leave this unset.
      if [ -n "${UMBRELLA_PROBE_TARGET_FILE:-}" ]; then
        printf '/repos/%s/issues/%s/dependencies/blocked_by\n' "$REPO" "$probe_target" > "$UMBRELLA_PROBE_TARGET_FILE"
      fi
      probe_attempt=1
      while [ "$probe_attempt" -le 2 ]; do
        set +e
        probe_resp=$(gh api -i "/repos/$REPO/issues/$probe_target/dependencies/blocked_by" 2>/dev/null)
        set -e
        probe_status=$(printf '%s\n' "$probe_resp" | awk 'NR==1{print $2; exit}')
        probe_body=$(printf '%s\n' "$probe_resp" | awk 'BEGIN{skip=1} /^[[:space:]]*\r?$/{skip=0;next} !skip{print}')
        case "$probe_status" in
          2*)
            api_available="true"
            break
            ;;
          404)
            if _wd_is_feature_missing_404 "$probe_body"; then
              # Confirmed feature-missing. PROBE_FAILED stays 0.
              :
            else
              # Ambiguous 404 (e.g., stale child issue on --no-backlinks first-child path)
              # — operational, not feature-off.
              PROBE_FAILED=1
              emit_probe_failure_warning "$probe_status" "$probe_body"
            fi
            break
            ;;
          5*|"")
            if [ "$probe_attempt" -eq 1 ]; then
              probe_attempt=$((probe_attempt + 1))
              continue
            fi
            # Second attempt also failed — bucket as transient/operational probe failure.
            PROBE_FAILED=1
            emit_probe_failure_warning "${probe_status:-network}" "${probe_body:-$probe_resp}"
            break
            ;;
          *)
            # Other 4xx (403, 429, etc.) — clear HTTP response, not a transport blip.
            # 429 is non-retriable per DECISION_1 simplification (no Retry-After parse).
            PROBE_FAILED=1
            emit_probe_failure_warning "$probe_status" "$probe_body"
            break
            ;;
        esac
      done
    fi

    EDGES_ADDED=0
    EDGES_REJECTED_CYCLE=0
    EDGES_SKIPPED_EXISTING=0
    EDGES_SKIPPED_API_UNAVAILABLE=0
    EDGES_FAILED=0
    BACKLINKS_POSTED=0
    BACKLINKS_SKIPPED_EXISTING=0
    edge_lines=""
    j=0

    # REDACT_SCRIPT and REDACT_FALLBACK_WARNED are initialized earlier (above
    # the probe block) so emit_probe_failure_warning can use them. The
    # per-edge emit_edge_failure_warning helper below references the same
    # names; do NOT re-initialize REDACT_FALLBACK_WARNED here — the probe path
    # may have already flipped it to 1 (one-time-per-run guard, issue #720
    # FINDING_6).

    # Per-run caches for wire-dag (Bash 3.2-safe storage; issue #744).
    #
    # Bash 3.2 (stock macOS /bin/bash) does not support `declare -A`, so caches
    # use parallel-array + colon-delimited present-string primitives matching
    # skills/issue/scripts/allocate-candidates.sh. Cross-skill portability
    # invariant; static-guard backstop in test-helpers.sh.
    #
    # BLOCKER_ID_CACHE: blocker display number -> blocker internal numeric id.
    # The GitHub Issue Dependencies POST body requires `issue_id` (internal id),
    # not `issue_number` (display number) — see add-blocked-by.sh:170.
    BIC_KEYS=()
    BIC_VALS=()

    # BLOCKED_BY_CACHE (issue #718): node display number -> space-separated
    # blocker numbers, the literal sentinel "_GH_FAIL_" on transient lookup
    # failure, or empty on successful zero-blocker lookup. BBC_PRESENT records
    # `+x`-style presence: presence is true even when the stored value is empty
    # so a successful zero-blocker lookup does not re-fire on cache hit.
    BBC_KEYS=()
    BBC_VALS=()
    BBC_PRESENT=":"

    # _WD_LOOKUP_FAILED: per-node warn-once flag for transient blocked_by
    # failures (membership-only).
    WDL_PRESENT=":"

    # bic_get key  -> echoes stored value (empty if not cached or empty value).
    # bic_set key value  -> replace-on-duplicate-key; preserves associative-array
    #                       assignment semantics (issue #744 FINDING_4).
    bic_get() {
      local k="$1" i=0
      while [ "$i" -lt "${#BIC_KEYS[@]}" ]; do
        if [ "${BIC_KEYS[$i]:-}" = "$k" ]; then
          printf '%s' "${BIC_VALS[$i]:-}"
          return 0
        fi
        i=$((i + 1))
      done
      printf ''
    }
    bic_set() {
      local k="$1" v="$2" i=0
      while [ "$i" -lt "${#BIC_KEYS[@]}" ]; do
        if [ "${BIC_KEYS[$i]:-}" = "$k" ]; then
          BIC_VALS[i]="$v"
          return 0
        fi
        i=$((i + 1))
      done
      BIC_KEYS+=("$k")
      BIC_VALS+=("$v")
    }

    # bbc_has key  -> 0 if key recorded (any value, including empty), else 1.
    # bbc_get key  -> echoes stored value (empty for both not-recorded AND
    #                 empty-value-recorded; callers must use bbc_has to disambiguate).
    # bbc_set key value  -> records presence in BBC_PRESENT (on first set only)
    #                       AND stores value unconditionally on every call,
    #                       including empty/sentinel values (issue #744
    #                       FINDING_5). Re-setting an existing key updates
    #                       BBC_VALS in place without re-appending to BBC_PRESENT.
    bbc_has() {
      case "$BBC_PRESENT" in
        *:"$1":*) return 0 ;;
        *)        return 1 ;;
      esac
    }
    bbc_get() {
      local k="$1" i=0
      while [ "$i" -lt "${#BBC_KEYS[@]}" ]; do
        if [ "${BBC_KEYS[$i]:-}" = "$k" ]; then
          printf '%s' "${BBC_VALS[$i]:-}"
          return 0
        fi
        i=$((i + 1))
      done
      printf ''
    }
    bbc_set() {
      local k="$1" v="$2" i=0
      while [ "$i" -lt "${#BBC_KEYS[@]}" ]; do
        if [ "${BBC_KEYS[$i]:-}" = "$k" ]; then
          BBC_VALS[i]="$v"
          return 0
        fi
        i=$((i + 1))
      done
      BBC_KEYS+=("$k")
      BBC_VALS+=("$v")
      BBC_PRESENT="${BBC_PRESENT}${k}:"
    }

    # wdl_marked key  -> 0 if marked, else 1.
    # wdl_mark key    -> idempotent set-marker.
    wdl_marked() {
      case "$WDL_PRESENT" in
        *:"$1":*) return 0 ;;
        *)        return 1 ;;
      esac
    }
    wdl_mark() {
      if ! wdl_marked "$1"; then
        WDL_PRESENT="${WDL_PRESENT}$1:"
      fi
    }

    # Set when the transitive traversal hit WIRE_DAG_TRAVERSAL_NODE_CAP. When 1,
    # the per-edge cycle-check loop routes any CYCLE=false candidate to
    # EDGES_FAILED with reason "bound-exhausted" (DECISION_1, voted 3-0):
    # the negative cycle answer cannot be trusted on a known-incomplete TSV.
    _wd_traversal_truncated=0

    # Per-run cap on distinct nodes the BFS may materialize. Override via
    # WIRE_DAG_TRAVERSAL_NODE_CAP. Total gh API calls across the run are
    # bounded by min(cap, |reachable closure|) once BLOCKED_BY_CACHE de-dups
    # repeat queries (DECISION_2, voted 2-1). Validate the override is a
    # positive integer (FINDING_2): a non-numeric or zero value would trip the
    # `-gt` integer comparison under `set -e` and abort wire-dag with no
    # documented `EDGES_FAILED` signal. On invalid input, emit a one-time
    # stderr warning and fall back to the default 200.
    WD_NODE_CAP="${WIRE_DAG_TRAVERSAL_NODE_CAP:-200}"
    if ! printf '%s' "$WD_NODE_CAP" | grep -qE '^[1-9][0-9]*$'; then
      echo "**⚠ /umbrella: wire-dag — WIRE_DAG_TRAVERSAL_NODE_CAP=\"$WD_NODE_CAP\" is not a positive integer; falling back to default 200**" >&2
      WD_NODE_CAP=200
    fi

    EXISTING_EDGES_TSV="$TMPDIR/existing-edges.tsv"
    : > "$EXISTING_EDGES_TSV"

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
      if bbc_has "$node"; then
        local cached
        cached=$(bbc_get "$node")
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
        bbc_set "$node" "_GH_FAIL_"
        if ! wdl_marked "$node"; then
          wdl_mark "$node"
          echo "**⚠ /umbrella: wire-dag blocked_by lookup failed for #${node} — treating as no edges**" >&2
        fi
        printf ''
        return 0
      fi
      # Convert newline-delimited gh output to a space-separated string suitable
      # for unquoted iteration via `for b in $(bbc_get $node)` (per FINDING_1 —
      # pinning the capture/iterate mechanism explicitly).
      local flat
      flat=$(printf '%s' "$raw" | tr '\n' ' ')
      flat="${flat% }"
      bbc_set "$node" "$flat"
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
    #   (b) only mark seen and enqueue `b` if not yet in _seen.
    # The seen-set guards re-querying only — it MUST NOT short-circuit append.
    _wd_populate_existing_edges_transitively() {
      local existing_tsv="$1"
      # Bash 3.2-safe seen-set: colon-delimited present-string (issue #744).
      local _seen=":"
      local queue=()
      local distinct_count=0
      local start_ts="$SECONDS"

      # Seed from CHILDREN_FILE (one issue per line, tab-separated columns).
      while IFS=$'\t' read -r child_num _title _url; do
        [ -z "$child_num" ] && continue
        case "$_seen" in
          *:"$child_num":*) ;;
          *)
            _seen="${_seen}${child_num}:"
            queue+=("$child_num")
            distinct_count=$((distinct_count + 1))
            ;;
        esac
      done < "$CHILDREN_FILE"

      # Seed from EDGES_FILE endpoints (both blocker AND blocked).
      while IFS=$'\t' read -r blocker blocked; do
        [ -z "$blocker" ] || [ -z "$blocked" ] && continue
        for endpoint in "$blocker" "$blocked"; do
          case "$_seen" in
            *:"$endpoint":*) ;;
            *)
              _seen="${_seen}${endpoint}:"
              queue+=("$endpoint")
              distinct_count=$((distinct_count + 1))
              ;;
          esac
        done
      done < "$EDGES_FILE"

      # Post-seed cap check (FINDING_1). If the seed set already exceeds the
      # cap, no BFS expansion is safe — set the truncated flag and emit the
      # cap warning before any candidate processing. Without this, an over-cap
      # seed would silently bypass the fail-closed posture because the in-loop
      # check below only fires when a NEW blocker is discovered.
      if [ "$distinct_count" -gt "$WD_NODE_CAP" ]; then
        _wd_traversal_truncated=1
        echo "**⚠ /umbrella: wire-dag traversal cap reached (cap=${WD_NODE_CAP}, queue=${#queue[@]}, elapsed=0s) — seed set already over-cap; pending candidates will fail closed**" >&2
        return 0
      fi

      while [ "${#queue[@]}" -gt 0 ]; do
        local node="${queue[0]}"
        queue=("${queue[@]:1}")
        local blockers
        blockers=$(_wd_blocked_by_lookup "$node")
        for b in $blockers; do
          [ -z "$b" ] && continue
          # Append unconditionally (FINDING_3).
          printf '%s\t%s\n' "$b" "$node" >> "$existing_tsv"
          case "$_seen" in
            *:"$b":*) ;;
            *)
              _seen="${_seen}${b}:"
              distinct_count=$((distinct_count + 1))
              if [ "$distinct_count" -gt "$WD_NODE_CAP" ]; then
                _wd_traversal_truncated=1
                local elapsed=$((SECONDS - start_ts))
                echo "**⚠ /umbrella: wire-dag traversal cap reached (cap=${WD_NODE_CAP}, queue=${#queue[@]}, elapsed=${elapsed}s) — pending candidates will fail closed**" >&2
                return 0
              fi
              queue+=("$b")
              ;;
          esac
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
        # Existing? skip. Fixed-string field-equality (closes #775 — unified
        # grep -F doctrine). Previously `grep -qE "^${blocker}\t${blocked}$"`,
        # which interpolated EDGES_FILE-derived values into an ERE; though
        # current callers numerically validate IDs, the input boundary lacked
        # the property — fixing here closes the regex-injection class on the
        # wire-dag surface alongside the back-link probe and label probe.
        # The `""` empty-string concatenation forces awk to treat both
        # operands as strings; without it, awk's auto-numeric-coercion would
        # compare numerically when both `$1` (from input) and `b` (from -v)
        # look like numbers (e.g., `b="5."` would equal `$1="5"` numerically).
        if awk -F$'\t' -v b="$blocker" -v t="$blocked" \
             '($1 "") == b && ($2 "") == t {found=1; exit} END{exit !found}' "$EXISTING_EDGES_TSV"; then
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
        blocker_id=$(bic_get "$blocker")
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
          bic_set "$blocker" "$blocker_id"
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
            # Conservative dual-regex fingerprint: BOTH a "dependencies /
            # blocked_by / sub-issue" keyword AND a "not found / does not
            # exist / no longer (available|supported)" phrase must appear in
            # the body before we credit "feature missing". Ambiguous 404s
            # (e.g., stale child issue) fall to EDGES_FAILED so operators
            # see a real diagnostic instead of a silent skip.
            # Predicate is shared with the repo-wide probe (issue #728) via
            # _wd_is_feature_missing_404 — single source of truth, no drift.
            if _wd_is_feature_missing_404 "$body"; then
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

    # Back-links: post a comment on each child unless an existing back-link
    # comment is already present. The previous implementation probed the
    # child's blocked_by list for the umbrella (intended to detect GitHub's
    # native umbrella-rendering surface), but no path in the skill ever
    # creates the umbrella↔child native edge in the direction that probe
    # tested, so the check was unreachable and re-runs accumulated duplicate
    # comments (issue #716). The new check scans the child's existing
    # comments for the literal prefix `Part of umbrella #${UMBRELLA} — `
    # (the exact prefix the tool itself emits at line 507; the trailing
    # ` — ` separator prevents prefix-collision on numeric umbrella numbers
    # — e.g., `#1` would otherwise false-match `#12`). Matches both
    # newly-posted and operator-edited variants (anything that begins with
    # the canonical prefix counts as already-linked). The check runs
    # unconditionally — independent of `api_available`, since the comments
    # API is a separate GitHub surface from the dependencies API; on `gh
    # api` failure the existing flag stays false (fail-open: post the
    # comment, matching the rest of wire-dag's fail-open posture).
    #
    # On --no-backlinks (created-eq-1 bypass), the entire loop is skipped: there is
    # no umbrella, so the comment body — which references $UMBRELLA — would be malformed.
    if [ "$NO_BACKLINKS" != "true" ]; then
      backlink_marker="Part of umbrella #${UMBRELLA} — "
      while IFS=$'\t' read -r child_num _title _url; do
        [ -z "$child_num" ] && continue
        existing="false"
        # Idempotency probe: extract the FIRST LINE of each comment body
        # (`split("\n")[0]`) and use awk's `index($0, m) == 1` (literal
        # position-1 anchor) to test whether that first line begins with the
        # canonical marker. Pure fixed-string match — no regex interpretation
        # of $backlink_marker (closes #775 — unified grep -F doctrine; replaces
        # the prior `grep -qE "^${backlink_marker}"` which would have
        # over-matched or invalid-ERE-failed had UMBRELLA contained ERE
        # metacharacters). The position-1 semantic preserves the line-start
        # anchor that issue #716 review FINDING (Codex) deliberately added:
        # a discussion comment that quotes or mentions the marker mid-prose
        # will not false-match. Awk's `index()` is POSIX-mandated (identical
        # across BSD/GNU); the early `exit` short-circuits at the first
        # matching comment; END `exit !found` returns 0/1 for shell-if usage.
        if gh api "/repos/$REPO/issues/${child_num}/comments" --paginate --jq '.[].body | split("\n")[0]' 2>/dev/null \
             | awk -v m="$backlink_marker" 'index($0, m) == 1 { found=1; exit } END { exit !found }'; then
          existing="true"
        fi
        if [ "$existing" = "true" ]; then
          BACKLINKS_SKIPPED_EXISTING=$((BACKLINKS_SKIPPED_EXISTING + 1))
          continue
        fi
        backlink_body="Part of umbrella #${UMBRELLA} — ${UMBRELLA_TITLE}"
        if gh issue comment -R "$REPO" "$child_num" --body "$backlink_body" >/dev/null 2>&1; then
          BACKLINKS_POSTED=$((BACKLINKS_POSTED + 1))
        fi
      done < "$CHILDREN_FILE"
    fi

    printf 'EDGES_ADDED=%d\n' "$EDGES_ADDED"
    printf 'EDGES_REJECTED_CYCLE=%d\n' "$EDGES_REJECTED_CYCLE"
    printf 'EDGES_SKIPPED_EXISTING=%d\n' "$EDGES_SKIPPED_EXISTING"
    printf 'EDGES_SKIPPED_API_UNAVAILABLE=%d\n' "$EDGES_SKIPPED_API_UNAVAILABLE"
    printf 'EDGES_FAILED=%d\n' "$EDGES_FAILED"
    printf 'PROBE_FAILED=%d\n' "$PROBE_FAILED"
    printf 'BACKLINKS_POSTED=%d\n' "$BACKLINKS_POSTED"
    printf 'BACKLINKS_SKIPPED_EXISTING=%d\n' "$BACKLINKS_SKIPPED_EXISTING"
    if [ -n "$edge_lines" ]; then
      printf '%s' "$edge_lines"
    fi
    # Repo-wide "API not available" warning fires only on confirmed
    # feature-missing (issue #728): PROBE_FAILED=0 AND api_available=false
    # AND probe_attempted=1 (otherwise we never made an HTTP request and
    # cannot truthfully diagnose the surface as unavailable; the empty-
    # probe_target case on the --no-backlinks path is silent by design).
    # Transient probe failure (PROBE_FAILED=1) emits the dedicated
    # "wire-dag probe failed (HTTP <status>)" stderr earlier inside the probe
    # block; emitting both would double-warn on the same condition.
    if [ "$api_available" = "false" ] && [ "$PROBE_FAILED" = "0" ] && [ "$probe_attempted" = "1" ]; then
      if [ "$NO_BACKLINKS" = "true" ]; then
        # On the created-eq-1 bypass path, back-links are intentionally suppressed —
        # the legacy "Back-links posted via comments" tail would be factually false.
        echo "**⚠ /umbrella: GitHub blocked-by dependency API not available on $REPO; skipped DAG wiring. Back-links suppressed (--no-backlinks)." >&2
      else
        echo "**⚠ /umbrella: GitHub blocked-by dependency API not available on $REPO; skipped DAG wiring. Back-links posted via comments." >&2
      fi
    fi
    ;;

  prefix-titles)
    UMBRELLA=""
    CHILDREN_FILE=""
    REPO=""
    DRY_RUN="false"
    while [ "$#" -gt 0 ]; do
      case "$1" in
        --umbrella)       UMBRELLA="$2"; shift 2 ;;
        --children-file)  CHILDREN_FILE="$2"; shift 2 ;;
        --repo)           REPO="$2"; shift 2 ;;
        --dry-run)        DRY_RUN="true"; shift ;;
        *) echo "ERROR=Unknown flag for prefix-titles: $1" >&2; exit 1 ;;
      esac
    done
    if [ -z "$UMBRELLA" ] || ! printf '%s' "$UMBRELLA" | grep -qE '^[1-9][0-9]*$'; then
      echo "ERROR=prefix-titles requires --umbrella as a positive integer" >&2; exit 1
    fi
    if [ -z "$CHILDREN_FILE" ] || [ ! -f "$CHILDREN_FILE" ]; then
      echo "ERROR=prefix-titles requires --children-file pointing to an existing file" >&2; exit 1
    fi
    if [ -z "$REPO" ]; then
      echo "ERROR=prefix-titles requires --repo" >&2; exit 1
    fi

    TITLES_RENAMED=0
    TITLES_SKIPPED_EXISTING=0
    TITLES_FAILED=0

    if [ "$DRY_RUN" = "true" ]; then
      printf 'TITLES_RENAMED=0\nTITLES_SKIPPED_EXISTING=0\nTITLES_FAILED=0\n'
      exit 0
    fi

    REDACT_SCRIPT="$(cd "$(dirname "$0")/../../.." 2>/dev/null && pwd)/scripts/redact-secrets.sh"
    REDACT_FALLBACK_WARNED=0

    emit_title_failure_warning() {
      local num="$1" code="$2" raw="$3"
      local flat redacted
      flat=$(printf '%s' "$raw" | tr '\n\r' '  ' | head -c 200)
      if [ -x "$REDACT_SCRIPT" ]; then
        if redacted=$(printf '%s' "$flat" | "$REDACT_SCRIPT" 2>/dev/null); then
          :
        else
          if [ "$REDACT_FALLBACK_WARNED" = "0" ]; then
            echo "**⚠ /umbrella: prefix-titles — redact-secrets.sh exited non-zero; suppressing reason text for safety**" >&2
            REDACT_FALLBACK_WARNED=1
          fi
          redacted="<REDACTION_FAILED>"
        fi
      else
        if [ "$REDACT_FALLBACK_WARNED" = "0" ]; then
          echo "**⚠ /umbrella: prefix-titles — redact-secrets.sh not found at $REDACT_SCRIPT; using inline-fallback scrub**" >&2
          REDACT_FALLBACK_WARNED=1
        fi
        redacted="$flat"
      fi
      echo "**⚠ /umbrella: prefix-titles edit #${num} failed (${code}): ${redacted}**" >&2
    }

    prefix_marker="(Umbrella: ${UMBRELLA}) "

    while IFS=$'\t' read -r child_num child_title _rest; do
      # Empty rows (blank lines, trailing newlines) are silently skipped — they
      # are the byte-exact shape an empty TSV produces and not a caller bug.
      [ -z "$child_num" ] && continue
      # Non-numeric or non-positive first column is a caller bug (the orchestrator
      # filters /issue stdout for ISSUE_<i>_NUMBER, which is always a positive
      # integer). Bucket as TITLES_FAILED with an input-class warning so the
      # bug is visible rather than silently masked.
      if ! printf '%s' "$child_num" | grep -qE '^[1-9][0-9]*$'; then
        TITLES_FAILED=$((TITLES_FAILED + 1))
        emit_title_failure_warning "$child_num" "input" "non-numeric or non-positive issue number column"
        continue
      fi
      if [ -z "$child_title" ]; then
        # Title column missing — refuse to rewrite blindly; bucket as failure.
        TITLES_FAILED=$((TITLES_FAILED + 1))
        emit_title_failure_warning "$child_num" "input" "missing title column for #${child_num}"
        continue
      fi
      case "$child_title" in
        "$prefix_marker"*)
          TITLES_SKIPPED_EXISTING=$((TITLES_SKIPPED_EXISTING + 1))
          continue
          ;;
      esac
      new_title="${prefix_marker}${child_title}"
      set +e
      err_out=$(gh issue edit "$child_num" -R "$REPO" --title "$new_title" 2>&1 >/dev/null)
      rc=$?
      set -e
      if [ "$rc" -eq 0 ]; then
        TITLES_RENAMED=$((TITLES_RENAMED + 1))
      else
        TITLES_FAILED=$((TITLES_FAILED + 1))
        emit_title_failure_warning "$child_num" "exit ${rc}" "${err_out:-no stderr captured}"
      fi
    done < "$CHILDREN_FILE"

    printf 'TITLES_RENAMED=%d\n' "$TITLES_RENAMED"
    printf 'TITLES_SKIPPED_EXISTING=%d\n' "$TITLES_SKIPPED_EXISTING"
    printf 'TITLES_FAILED=%d\n' "$TITLES_FAILED"
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
  check-cycle    --existing-edges FILE --candidate BLOCKER:BLOCKED
  wire-dag       --tmpdir DIR --umbrella N --umbrella-title T --children-file F --edges-file E --repo R [--dry-run] [--no-backlinks]
  prefix-titles  --umbrella N --children-file F --repo R [--dry-run]
  emit-output    --kv-file FILE
EOF
    ;;

  *)
    echo "ERROR=Unknown subcommand: $SUBCMD (try check-cycle / wire-dag / prefix-titles / emit-output)" >&2; exit 1
    ;;
esac
