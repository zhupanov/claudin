#!/usr/bin/env bash
# dialectic-smoke-test.sh — offline regression guard for /design Step 2a.5.
#
# Walks every fixture directory under tests/fixtures/dialectic/ and asserts
# that the dialectic artifacts (debater outputs, ballot, judge outputs)
# match the per-decision dispositions and tallies declared in the fixture's
# expected.txt manifest.
#
# Scope:
#   - Parser tolerance (skills/shared/dialectic-protocol.md, "Parser tolerance"
#     section): trim, strip paired **/__ wrappers, case-insensitive DECISION_N:
#     prefix, THESIS/ANTI_THESIS token with preserved underscore, rationale
#     after em-dash — or ASCII hyphen -, first-valid line on duplicates,
#     whole-output ineligibility on STATUS=non-OK sentinel.
#   - Threshold rules ("Threshold Rules" section): 3 voters → 2+ same-side
#     wins; 2 voters → unanimous wins or 1-1 tie → fallback-to-synthesis;
#     <2 voters → fallback-to-synthesis.
#   - Debater structural invariants: 5 required tags per side (claim,
#     evidence, strongest_concession, counter_to_opposition, risk_if_wrong),
#     exactly one RECOMMEND: line, role-vs-RECOMMEND consistency, file:line
#     citation in <evidence>.
#   - Ballot anonymity: Cursor/Codex/Claude tokens MUST NOT appear in the
#     ballot body (see "Attribution stripping" section).
#   - Drift guard: protocol file contains the stable anchor sentence
#     "Recognize exactly these four Disposition values" with the four
#     canonical values backticked nearby.
#
# Out of scope:
#   - Wrapping scripts/collect-reviewer-results.sh (STATUS / REVIEWER_FILE /
#     retry-file routing). Collector integration regression guards live
#     elsewhere.
#   - Fixtures with zero contested decisions (covered by the orchestrator's
#     NO_CONTESTED_DECISIONS sentinel path, which bypasses 2a.5 entirely).
#
# Bash 3.2 compatible (uses parallel indexed arrays, no `declare -A`).

set -euo pipefail
export LC_ALL=C

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FIXTURE_ROOT="$REPO_ROOT/tests/fixtures/dialectic"
PROTOCOL_FILE="$REPO_ROOT/skills/shared/dialectic-protocol.md"

fail_count=0
pass_count=0

log()  { printf '[smoke] %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; fail_count=$((fail_count + 1)); }
warn() { printf 'WARN: %s\n' "$*" >&2; }

upper() { printf '%s' "$1" | tr '[:lower:]' '[:upper:]'; }

trim() {
    local s=$1
    s="${s#"${s%%[![:space:]]*}"}"
    s="${s%"${s##*[![:space:]]}"}"
    printf '%s' "$s"
}

strip_wrappers() {
    local s=$1
    if [[ "$s" =~ ^\*\*(.*)\*\*$ ]]; then
        s="${BASH_REMATCH[1]}"
    elif [[ "$s" =~ ^__(.*)__$ ]]; then
        s="${BASH_REMATCH[1]}"
    fi
    printf '%s' "$s"
}

# check_protocol_drift — assert the anchor sentence is present and the four
# canonical disposition values are backticked within 40 lines after it.
check_protocol_drift() {
    local anchor='Recognize exactly these four Disposition values'
    if ! grep -Fq "$anchor" "$PROTOCOL_FILE"; then
        fail "drift guard: anchor sentence not found in $PROTOCOL_FILE"
        return
    fi
    local anchor_line
    anchor_line=$(grep -nF "$anchor" "$PROTOCOL_FILE" | head -1 | cut -d: -f1)
    local window
    window=$(sed -n "${anchor_line},$((anchor_line + 40))p" "$PROTOCOL_FILE")
    local val
    for val in 'voted' 'fallback-to-synthesis' 'bucket-skipped' 'over-cap'; do
        if ! printf '%s\n' "$window" | grep -Fq "\`$val\`"; then
            fail "drift guard: disposition value '$val' not found (as backticked token) within 40 lines of anchor"
            return
        fi
    done
    log "drift guard: protocol anchor + 4 dispositions OK"
    pass_count=$((pass_count + 1))
}

# validate_debater <file> <role> <fixture_name>
validate_debater() {
    local file=$1 role=$2 fixture=$3

    if [[ ! -s "$file" ]]; then
        fail "$fixture: debater file $(basename "$file") is empty"
        return 1
    fi

    local tag
    for tag in '<claim>' '<evidence>' '<strongest_concession>' '<counter_to_opposition>' '<risk_if_wrong>'; do
        if ! grep -Fq "$tag" "$file"; then
            fail "$fixture: debater $(basename "$file") missing tag $tag"
            return 1
        fi
    done

    local rec_count=0 rec_token="" line stripped up
    while IFS= read -r line; do
        stripped=$(strip_wrappers "$(trim "$line")")
        up=$(upper "$stripped")
        if [[ "$up" == RECOMMEND:* ]]; then
            rec_count=$((rec_count + 1))
            rec_token=$(trim "${stripped#*:}")
        fi
    done < "$file"

    if [[ $rec_count -ne 1 ]]; then
        fail "$fixture: debater $(basename "$file") has $rec_count RECOMMEND: lines (expected 1)"
        return 1
    fi

    local up_token
    up_token=$(upper "$rec_token")
    if [[ "$up_token" != "THESIS" && "$up_token" != "ANTI_THESIS" ]]; then
        fail "$fixture: debater $(basename "$file") RECOMMEND token '$rec_token' not in {THESIS, ANTI_THESIS}"
        return 1
    fi

    case "$role" in
        thesis)
            if [[ "$up_token" != "THESIS" ]]; then
                fail "$fixture: thesis role file $(basename "$file") declares RECOMMEND: $rec_token (expected THESIS)"
                return 1
            fi
            ;;
        antithesis)
            if [[ "$up_token" != "ANTI_THESIS" ]]; then
                fail "$fixture: antithesis role file $(basename "$file") declares RECOMMEND: $rec_token (expected ANTI_THESIS)"
                return 1
            fi
            ;;
    esac

    local evidence_body
    evidence_body=$(awk '/<evidence>/,/<\/evidence>/' "$file")
    if ! printf '%s' "$evidence_body" | grep -Eq '[A-Za-z0-9._/-]+:[0-9]+'; then
        fail "$fixture: debater $(basename "$file") <evidence> missing file:line citation"
        return 1
    fi
    return 0
}

# validate_ballot_anonymity <ballot_file> <fixture_name>
# Per skills/shared/dialectic-protocol.md "Attribution stripping" section, tool
# names must not appear anywhere in the ballot body. Check case-insensitively
# to catch mixed-case leaks (CURSOR, claude, Codex, etc.).
validate_ballot_anonymity() {
    local file=$1 fixture=$2 leak=0 term
    for term in 'Cursor' 'Codex' 'Claude'; do
        if grep -Fiq "$term" "$file"; then
            fail "$fixture: ballot $(basename "$file") contains attribution leak '$term' (case-insensitive — must not appear anywhere in ballot body)"
            leak=1
        fi
    done
    return $leak
}

# parse_judge_file <file>
# stdout:
#   "WHOLE_INELIGIBLE\n" — if STATUS=<non-OK> sentinel detected, OR file missing/empty.
#   "DECISION_<N>:<VOTE>\n" (one per decision, first-valid on duplicates).
parse_judge_file() {
    local file=$1
    if [[ ! -s "$file" ]]; then
        printf 'WHOLE_INELIGIBLE\n'
        return 0
    fi

    local first
    first=$(awk 'NF{print; exit}' "$file")
    first=$(strip_wrappers "$(trim "$first")")
    if [[ "$first" =~ ^[Ss][Tt][Aa][Tt][Uu][Ss]= ]]; then
        local val="${first#*=}"
        val=$(trim "$val")
        if [[ "$(upper "$val")" != "OK" ]]; then
            printf 'WHOLE_INELIGIBLE\n'
            return 0
        fi
    fi

    # Bash 3.2 compat: parallel indexed arrays in place of declare -A.
    local seen_keys=() seen_vals=()
    local file_basename
    file_basename=$(basename "$file")
    local line stripped up tok rest n up_tok
    while IFS= read -r line; do
        stripped=$(strip_wrappers "$(trim "$line")")
        up=$(upper "$stripped")
        if [[ ! "$up" =~ ^DECISION_([0-9]+): ]]; then
            continue
        fi
        n="${BASH_REMATCH[1]}"
        rest="${stripped#*:}"
        rest=$(trim "$rest")
        # Per dialectic-protocol.md Parser tolerance (step 5), the vote line
        # format is `DECISION_N: TOKEN <separator> <rationale>` where
        # <separator> is em-dash `—` or ASCII hyphen `-`. A bare token with no
        # separator is not a valid vote line — treat as abstention.
        tok=""
        if [[ "$rest" =~ ^([A-Za-z_]+)[[:space:]]*—[[:space:]]* ]]; then
            tok="${BASH_REMATCH[1]}"
        elif [[ "$rest" =~ ^([A-Za-z_]+)[[:space:]]+-[[:space:]]* ]]; then
            tok="${BASH_REMATCH[1]}"
        else
            continue
        fi
        up_tok=$(upper "$tok")
        if [[ "$up_tok" != "THESIS" && "$up_tok" != "ANTI_THESIS" ]]; then
            continue
        fi
        # First-valid wins on duplicates.
        local dup=0 i
        for i in "${!seen_keys[@]}"; do
            if [[ "${seen_keys[$i]}" == "$n" ]]; then
                dup=1
                break
            fi
        done
        if [[ $dup -eq 1 ]]; then
            warn "duplicate DECISION_$n line in $file_basename — keeping first valid"
            continue
        fi
        seen_keys+=("$n")
        seen_vals+=("$up_tok")
    done < "$file"

    local i
    for i in "${!seen_keys[@]}"; do
        printf 'DECISION_%s:%s\n' "${seen_keys[$i]}" "${seen_vals[$i]}"
    done | sort -t_ -k2,2n
}

# compute_decision <N> <j1> <j2> <j3>
# prints "disposition|thesis|anti|reason"
compute_decision() {
    local n=$1 j1=$2 j2=$3 j3=$4
    local thesis=0 anti=0 eligible=0
    local j vote tok
    for j in "$j1" "$j2" "$j3"; do
        if [[ "$j" == "WHOLE_INELIGIBLE" ]]; then
            continue
        fi
        vote=$(printf '%s\n' "$j" | grep "^DECISION_${n}:" | head -1 || true)
        if [[ -z "$vote" ]]; then
            continue
        fi
        tok="${vote#*:}"
        case "$tok" in
            THESIS)      thesis=$((thesis + 1)); eligible=$((eligible + 1)) ;;
            ANTI_THESIS) anti=$((anti + 1));     eligible=$((eligible + 1)) ;;
            *)           ;; # abstention / unknown
        esac
    done

    if [[ $eligible -ge 3 ]]; then
        if [[ $thesis -ge 2 || $anti -ge 2 ]]; then
            printf 'voted|%s|%s|\n' "$thesis" "$anti"
        else
            printf 'fallback-to-synthesis|%s|%s|no majority with 3 voters\n' "$thesis" "$anti"
        fi
    elif [[ $eligible -eq 2 ]]; then
        if [[ $thesis -eq 2 || $anti -eq 2 ]]; then
            printf 'voted|%s|%s|\n' "$thesis" "$anti"
        else
            printf 'fallback-to-synthesis|%s|%s|1-1 tie with 2 voters\n' "$thesis" "$anti"
        fi
    else
        printf 'fallback-to-synthesis|%s|%s|%s judges eligible\n' "$thesis" "$anti" "$eligible"
    fi
}

# run_fixture <fixture_dir>
run_fixture() {
    local fixture_dir=$1
    local fixture
    fixture=$(basename "$fixture_dir")
    local manifest="$fixture_dir/expected.txt"

    if [[ ! -f "$manifest" ]]; then
        fail "$fixture: expected.txt manifest missing"
        return
    fi

    # Bash 3.2 compat: parallel indexed arrays.
    local exp_ns=() exp_disps=() exp_tallies=()
    local skip_debater=0 skip_anon=0
    local line n disp_val tally_val kv

    while IFS= read -r line; do
        line="${line%%#*}"
        line=$(trim "$line")
        [[ -z "$line" ]] && continue
        case "$line" in
            skip_debater_validation=true) skip_debater=1; continue ;;
            skip_ballot_anonymity=true)   skip_anon=1;    continue ;;
        esac
        if [[ "$line" != DECISION_* ]]; then
            continue
        fi
        n="${line%% *}"
        n="${n#DECISION_}"
        disp_val=""
        tally_val=""
        for kv in $line; do
            case "$kv" in
                expected_disposition=*) disp_val="${kv#expected_disposition=}" ;;
                expected_tally=*)       tally_val="${kv#expected_tally=}" ;;
            esac
        done
        exp_ns+=("$n")
        exp_disps+=("$disp_val")
        exp_tallies+=("$tally_val")
    done < "$manifest"

    if [[ $skip_debater -eq 0 ]]; then
        local tf af
        for tf in "$fixture_dir"/debate-*-thesis.txt; do
            [[ -e "$tf" ]] || continue
            validate_debater "$tf" thesis "$fixture" || true
        done
        for af in "$fixture_dir"/debate-*-antithesis.txt; do
            [[ -e "$af" ]] || continue
            validate_debater "$af" antithesis "$fixture" || true
        done
    fi

    local ballot="$fixture_dir/ballot.txt"
    if [[ -f "$ballot" && $skip_anon -eq 0 ]]; then
        validate_ballot_anonymity "$ballot" "$fixture" || true
    fi

    local cursor_file="$fixture_dir/cursor-judge-output.txt"
    local codex_file="$fixture_dir/codex-judge-output.txt"
    local claude_file="$fixture_dir/claude-judge-output.txt"
    local cs cxs cls
    if [[ -f "$cursor_file" ]]; then cs=$(parse_judge_file "$cursor_file"); else cs="WHOLE_INELIGIBLE"; fi
    if [[ -f "$codex_file"  ]]; then cxs=$(parse_judge_file "$codex_file");  else cxs="WHOLE_INELIGIBLE"; fi
    if [[ -f "$claude_file" ]]; then cls=$(parse_judge_file "$claude_file"); else cls="WHOLE_INELIGIBLE"; fi

    local i
    for i in "${!exp_ns[@]}"; do
        local n="${exp_ns[$i]}"
        local exp_disp="${exp_disps[$i]}"
        local exp_tally="${exp_tallies[$i]}"
        local result act_disp act_t act_a act_reason
        result=$(compute_decision "$n" "$cs" "$cxs" "$cls")
        IFS='|' read -r act_disp act_t act_a act_reason <<< "$result"
        local act_tally="THESIS=${act_t},ANTI_THESIS=${act_a}"

        local match=0
        case "$exp_disp" in
            voted)
                [[ "$act_disp" == "voted" ]] && match=1
                ;;
            bucket-skipped|over-cap)
                # For bucket-skipped / over-cap the orchestrator decides the
                # disposition before any judge votes exist. The parser-visible
                # representation is 0/0 fallback-to-synthesis (no eligible
                # voters for this decision). Assert the structural conditions
                # that distinguish a genuine bucket-skipped / over-cap from a
                # broken fixture that happens to produce 0/0:
                #   - no debate-<n>-thesis.txt or debate-<n>-antithesis.txt
                #   - no DECISION_<n> line in any judge output
                #   - no DECISION_<n>: heading in ballot.txt
                # Any of these being present means the decision was actually
                # debated / voted and the manifest is wrong (or vice versa).
                if [[ "$act_disp" == "fallback-to-synthesis" && "$act_t" == "0" && "$act_a" == "0" ]]; then
                    local struct_ok=1
                    if [[ -f "$fixture_dir/debate-${n}-thesis.txt" || -f "$fixture_dir/debate-${n}-antithesis.txt" ]]; then
                        fail "$fixture DECISION_$n: '$exp_disp' expected but debate-${n}-*.txt files exist (should be absent)"
                        struct_ok=0
                    fi
                    local jf
                    for jf in "$cursor_file" "$codex_file" "$claude_file"; do
                        if [[ -f "$jf" ]] && grep -Eiq "^[[:space:]]*(\*\*|__)?[[:space:]]*DECISION_${n}:" "$jf"; then
                            fail "$fixture DECISION_$n: '$exp_disp' expected but $(basename "$jf") contains a DECISION_${n}: line (should be absent)"
                            struct_ok=0
                        fi
                    done
                    if [[ -f "$ballot" ]] && grep -Eq "^###[[:space:]]+DECISION_${n}:" "$ballot"; then
                        fail "$fixture DECISION_$n: '$exp_disp' expected but ballot.txt contains a DECISION_${n} heading (should be absent)"
                        struct_ok=0
                    fi
                    [[ $struct_ok -eq 1 ]] && match=1
                fi
                ;;
            fallback-to-synthesis)
                [[ "$act_disp" == "fallback-to-synthesis" ]] && match=1
                ;;
            *)
                fail "$fixture DECISION_$n: unknown expected_disposition '$exp_disp' in manifest"
                continue
                ;;
        esac

        if [[ $match -eq 0 ]]; then
            fail "$fixture DECISION_$n: disposition mismatch — expected '$exp_disp', got '$act_disp' tally=$act_tally (reason: ${act_reason:-none})"
            continue
        fi
        if [[ "$exp_disp" == "voted" && -n "$exp_tally" && "$exp_tally" != "$act_tally" ]]; then
            fail "$fixture DECISION_$n: tally mismatch — expected '$exp_tally', got '$act_tally'"
            continue
        fi
        if [[ "$exp_disp" == "fallback-to-synthesis" && -n "$exp_tally" && "$exp_tally" != "$act_tally" ]]; then
            fail "$fixture DECISION_$n: tally mismatch (fallback) — expected '$exp_tally', got '$act_tally'"
            continue
        fi
        pass_count=$((pass_count + 1))
    done
    log "$fixture: checks complete"
}

log "Running dialectic smoke test from $REPO_ROOT"
check_protocol_drift

if [[ ! -d "$FIXTURE_ROOT" ]]; then
    fail "fixture root $FIXTURE_ROOT missing"
fi

if [[ -d "$FIXTURE_ROOT" ]]; then
    shopt -s nullglob
    found=0
    for fixture_dir in "$FIXTURE_ROOT"/*/; do
        found=1
        run_fixture "${fixture_dir%/}"
    done
    if [[ $found -eq 0 ]]; then
        fail "no fixtures found under $FIXTURE_ROOT"
    fi
fi

if [[ $fail_count -ne 0 ]]; then
    printf '\n%d FAILURE(S), %d CHECK(S) PASSED\n' "$fail_count" "$pass_count" >&2
    exit 1
fi
printf '\n%d CHECK(S) PASSED, 0 FAILURE(S)\n' "$pass_count"
