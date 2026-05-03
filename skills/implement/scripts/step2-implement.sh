#!/usr/bin/env bash
# step2-implement.sh — Dispatcher for /implement Step 2 (Codex implementer + Claude fallback).
#
# This is the SINGLE entrypoint /implement Step 2 invokes. It is the only place
# that branches on codex_available. There is no main-agent Edit/Write code-edit
# path reachable from Step 2 when codex_available=true — the orchestrator only
# falls back to Claude when this script returns STATUS=claude_fallback (which
# it does ONLY when --codex-available false is passed in).
#
# See:
#   - skills/implement/SKILL.md Step 2 (caller)
#   - skills/implement/references/codex-manifest-schema.md (manifest contract)
#   - agents/codex-implementer.md (Codex prompt)
#   - scripts/launch-codex-implement.sh (leaf launcher)
#
# Stdout contract (KEY=VALUE lines, parsed by SKILL.md Step 2):
#   STATUS=<complete|needs_qa|bailed|claude_fallback>
#   MANIFEST=<path>          # set when STATUS=complete or needs_qa
#   QA_PENDING=<path>        # set when STATUS=needs_qa
#   REASON=<token>           # set when STATUS=bailed
#   TRANSCRIPT=<path>        # set when launcher actually ran
#   SIDECAR_LOG=<path>       # set when launcher actually ran
#
# Exit code is always 0 unless flag validation fails (exit 2).

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"

TMPDIR_ARG=""
PLAN_FILE=""
FEATURE_FILE=""
AUTO_MODE=""
CODEX_AVAILABLE=""
ANSWERS_FILE=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --tmpdir)            TMPDIR_ARG="${2:?--tmpdir requires a value}"; shift 2 ;;
        --plan-file)         PLAN_FILE="${2:?--plan-file requires a value}"; shift 2 ;;
        --feature-file)      FEATURE_FILE="${2:?--feature-file requires a value}"; shift 2 ;;
        --auto-mode)         AUTO_MODE="${2:?--auto-mode requires a value}"; shift 2 ;;
        --codex-available)   CODEX_AVAILABLE="${2:?--codex-available requires a value}"; shift 2 ;;
        --answers)           ANSWERS_FILE="${2:?--answers requires a value}"; shift 2 ;;
        *) echo "step2-implement.sh: unknown flag: $1" >&2; exit 2 ;;
    esac
done

for var in TMPDIR_ARG PLAN_FILE FEATURE_FILE AUTO_MODE CODEX_AVAILABLE; do
    if [[ -z "${!var}" ]]; then
        flag_lc=$(printf '%s' "$var" | tr '[:upper:]' '[:lower:]' | tr '_' '-')
        echo "step2-implement.sh: --$flag_lc is required" >&2
        exit 2
    fi
done

[[ -d "$TMPDIR_ARG" ]] || { echo "step2-implement.sh: --tmpdir not a directory: $TMPDIR_ARG" >&2; exit 2; }
[[ -f "$PLAN_FILE" ]]  || { echo "step2-implement.sh: --plan-file not found: $PLAN_FILE" >&2; exit 2; }
[[ -f "$FEATURE_FILE" ]] || { echo "step2-implement.sh: --feature-file not found: $FEATURE_FILE" >&2; exit 2; }
case "$CODEX_AVAILABLE" in
    true|false) ;;
    *) echo "step2-implement.sh: --codex-available must be 'true' or 'false', got: $CODEX_AVAILABLE" >&2; exit 2 ;;
esac
case "$AUTO_MODE" in
    true|false) ;;
    *) echo "step2-implement.sh: --auto-mode must be 'true' or 'false', got: $AUTO_MODE" >&2; exit 2 ;;
esac

# Branch 1: codex_available=false → emit claude_fallback and return.
if [[ "$CODEX_AVAILABLE" == "false" ]]; then
    printf 'STATUS=claude_fallback\n'
    exit 0
fi

# ---------------------------------------------------------------------------
# Codex path. Set up paths inside $TMPDIR_ARG.
# ---------------------------------------------------------------------------

BASELINE_FILE="$TMPDIR_ARG/step2-baseline.txt"
RESUME_COUNT_FILE="$TMPDIR_ARG/codex-resume-count.txt"
SPAWN_BRANCH_FILE="$TMPDIR_ARG/step2-spawn-branch.txt"
PLUGIN_JSON_BASELINE_FILE="$TMPDIR_ARG/step2-plugin-json-baseline.txt"
MANIFEST_PATH="$TMPDIR_ARG/manifest.json"
MANIFEST_RAW_PATH="$TMPDIR_ARG/manifest-raw.json"
QA_PENDING_PATH="$TMPDIR_ARG/qa-pending.json"
TRANSCRIPT_PATH="$TMPDIR_ARG/codex-impl-transcript.txt"
SIDECAR_LOG="$TMPDIR_ARG/codex-impl.log"
AGENT_PROMPT="$REPO_ROOT/agents/codex-implementer.md"
LAUNCHER="$REPO_ROOT/scripts/launch-codex-implement.sh"

[[ -f "$AGENT_PROMPT" ]] || { echo "step2-implement.sh: agent prompt missing: $AGENT_PROMPT" >&2; exit 2; }
[[ -x "$LAUNCHER" ]]     || { echo "step2-implement.sh: launcher not executable: $LAUNCHER" >&2; exit 2; }

# Helper: emit a STATUS=bailed envelope and exit 0.
emit_bailed() {
    local reason="$1"
    printf 'STATUS=bailed\n'
    printf 'REASON=%s\n' "$reason"
    if [[ -s "$TRANSCRIPT_PATH" ]]; then printf 'TRANSCRIPT=%s\n' "$TRANSCRIPT_PATH"; fi
    if [[ -s "$SIDECAR_LOG" ]];     then printf 'SIDECAR_LOG=%s\n' "$SIDECAR_LOG"; fi
    exit 0
}

# Step 1: write spawn-time baseline + branch + plugin.json SHA on FIRST invocation.
# Subsequent invocations (resume cycles) reuse the existing files.
if [[ ! -f "$BASELINE_FILE" ]]; then
    git -C "$REPO_ROOT" rev-parse HEAD > "$BASELINE_FILE.tmp"
    mv "$BASELINE_FILE.tmp" "$BASELINE_FILE"
fi
BASELINE_SHA=$(cat "$BASELINE_FILE")

if [[ ! -f "$SPAWN_BRANCH_FILE" ]]; then
    git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD > "$SPAWN_BRANCH_FILE.tmp"
    mv "$SPAWN_BRANCH_FILE.tmp" "$SPAWN_BRANCH_FILE"
fi
SPAWN_BRANCH=$(cat "$SPAWN_BRANCH_FILE")

if [[ ! -f "$PLUGIN_JSON_BASELINE_FILE" ]]; then
    if [[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]]; then
        git -C "$REPO_ROOT" hash-object "$REPO_ROOT/.claude-plugin/plugin.json" > "$PLUGIN_JSON_BASELINE_FILE.tmp"
    else
        printf '\n' > "$PLUGIN_JSON_BASELINE_FILE.tmp"
    fi
    mv "$PLUGIN_JSON_BASELINE_FILE.tmp" "$PLUGIN_JSON_BASELINE_FILE"
fi
PLUGIN_JSON_BASELINE=$(cat "$PLUGIN_JSON_BASELINE_FILE")

# Step 2: resume counter (incremented on each --answers invocation).
RESUME_COUNT=0
if [[ -f "$RESUME_COUNT_FILE" ]]; then
    raw_count=$(cat "$RESUME_COUNT_FILE")
    if [[ "$raw_count" =~ ^[0-9]+$ ]]; then
        RESUME_COUNT=$raw_count
    else
        emit_bailed "manifest-schema-invalid"
    fi
fi
if [[ -n "$ANSWERS_FILE" ]]; then
    [[ -f "$ANSWERS_FILE" ]] || { echo "step2-implement.sh: --answers given but path does not exist: $ANSWERS_FILE" >&2; exit 2; }
    RESUME_COUNT=$((RESUME_COUNT + 1))
    printf '%s\n' "$RESUME_COUNT" > "$RESUME_COUNT_FILE.tmp"
    mv "$RESUME_COUNT_FILE.tmp" "$RESUME_COUNT_FILE"
fi
if (( RESUME_COUNT > 5 )); then
    emit_bailed "qa-loop-exceeded"
fi

# Step 3: clean stale Codex outputs from prior invocations BEFORE launching.
rm -f "$MANIFEST_PATH" "$MANIFEST_RAW_PATH" "$QA_PENDING_PATH" "$TRANSCRIPT_PATH" "$SIDECAR_LOG"

# Step 4: launch Codex. Up to 1 retry on transient failure (timeout / non-zero
# exit before manifest written) — but only when post-failure state is clean.
LAUNCHER_TIMEOUT=1800

run_launcher() {
    local launcher_args=(
        --transcript-path "$TRANSCRIPT_PATH"
        --sidecar-log "$SIDECAR_LOG"
        --manifest-path "$MANIFEST_PATH"
        --qa-pending-path "$QA_PENDING_PATH"
        --plan-file "$PLAN_FILE"
        --feature-file "$FEATURE_FILE"
        --agent-prompt "$AGENT_PROMPT"
        --timeout "$LAUNCHER_TIMEOUT"
    )
    if [[ -n "$ANSWERS_FILE" ]]; then
        launcher_args+=(--answers-file "$ANSWERS_FILE")
    fi
    "$LAUNCHER" "${launcher_args[@]}"
}

LAUNCHER_OUT=$(run_launcher 2>&1) || true

# Parse launcher KV lines.
LAUNCHER_EXIT=$(printf '%s\n' "$LAUNCHER_OUT" | awk -F= '$1=="LAUNCHER_EXIT"{print $2; exit}')
MANIFEST_WRITTEN=$(printf '%s\n' "$LAUNCHER_OUT" | awk -F= '$1=="MANIFEST_WRITTEN"{print $2; exit}')

# Default to 'false' / 99 when missing (e.g., launcher itself crashed before emitting).
LAUNCHER_EXIT=${LAUNCHER_EXIT:-99}
MANIFEST_WRITTEN=${MANIFEST_WRITTEN:-false}

# Retry once on transient failure: launcher exit non-zero AND no manifest, AND clean state.
if [[ "$MANIFEST_WRITTEN" != "true" || "$LAUNCHER_EXIT" != "0" ]]; then
    if [[ "$MANIFEST_WRITTEN" != "true" ]]; then
        # Check post-failure state is clean enough to retry.
        DIRTY=$(git -C "$REPO_ROOT" status --porcelain)
        INDEX_LOCK_EXISTS=false
        [[ -e "$REPO_ROOT/.git/index.lock" ]] && INDEX_LOCK_EXISTS=true
        CURRENT_HEAD=$(git -C "$REPO_ROOT" rev-parse HEAD)
        if [[ -n "$DIRTY" || "$INDEX_LOCK_EXISTS" == "true" || "$CURRENT_HEAD" != "$BASELINE_SHA" ]]; then
            emit_bailed "dirty-state-after-timeout"
        fi
        # Clean state — single retry.
        LAUNCHER_OUT=$(run_launcher 2>&1) || true
        LAUNCHER_EXIT=$(printf '%s\n' "$LAUNCHER_OUT" | awk -F= '$1=="LAUNCHER_EXIT"{print $2; exit}')
        MANIFEST_WRITTEN=$(printf '%s\n' "$LAUNCHER_OUT" | awk -F= '$1=="MANIFEST_WRITTEN"{print $2; exit}')
        LAUNCHER_EXIT=${LAUNCHER_EXIT:-99}
        MANIFEST_WRITTEN=${MANIFEST_WRITTEN:-false}
    fi
fi

if [[ "$MANIFEST_WRITTEN" != "true" ]]; then
    emit_bailed "codex-runtime-failure"
fi

# Treat a non-zero launcher exit as failure even when a manifest was written —
# the manifest may be a stale .tmp leftover, half-written, or otherwise
# unreliable when the wrapper itself reports failure.
if [[ "$LAUNCHER_EXIT" != "0" ]]; then
    emit_bailed "codex-runtime-failure"
fi

# Step 5: validate manifest schema with jq.
[[ -s "$MANIFEST_PATH" ]] || emit_bailed "manifest-missing"
cp "$MANIFEST_PATH" "$MANIFEST_RAW_PATH"

# Pull status field; verify schema_version and status enum.
STATUS=$(jq -r 'if type=="object" then .status // "" else "" end' "$MANIFEST_RAW_PATH" 2>/dev/null || true)
SCHEMA_VERSION=$(jq -r 'if type=="object" then .schema_version // "" else "" end' "$MANIFEST_RAW_PATH" 2>/dev/null || true)

if [[ "$SCHEMA_VERSION" != "1" ]]; then
    emit_bailed "manifest-schema-invalid"
fi
case "$STATUS" in
    complete|needs_qa|bailed) ;;
    *) emit_bailed "manifest-schema-invalid" ;;
esac

# Per-status structural validation.
case "$STATUS" in
    complete)
        # Required: files_touched (array, non-empty), commit_message (string, non-empty),
        # summary_bullets (array length 1..5), tests_added_or_modified (array), todos_left (array),
        # oos_observations (array).
        jq -e '
            (.files_touched | type == "array" and length > 0) and
            (.files_touched | all(. | type == "object" and (.path | type == "string"))) and
            (.commit_message | type == "string" and length > 0) and
            (.summary_bullets | type == "array" and length >= 1 and length <= 5) and
            (.tests_added_or_modified | type == "array") and
            (.todos_left | type == "array") and
            (.oos_observations | type == "array")
        ' "$MANIFEST_RAW_PATH" >/dev/null 2>&1 || emit_bailed "manifest-schema-invalid"
        ;;
    needs_qa)
        jq -e '
            (.needs_qa | type == "object") and
            (.needs_qa.questions | type == "array" and length > 0)
        ' "$MANIFEST_RAW_PATH" >/dev/null 2>&1 || emit_bailed "manifest-schema-invalid"
        # qa-pending.json must exist, be non-empty, and contain a non-empty
        # questions array — Step 2.3 of /implement reads it directly via
        # AskUserQuestion. A missing companion file would strand the orchestrator.
        if [[ ! -s "$QA_PENDING_PATH" ]]; then
            emit_bailed "qa-pending-missing"
        fi
        jq -e '(.questions | type == "array" and length > 0)' "$QA_PENDING_PATH" >/dev/null 2>&1 \
            || emit_bailed "qa-pending-missing"
        ;;
    bailed)
        jq -e '(.bail_reason | type == "string" and length > 0)' "$MANIFEST_RAW_PATH" >/dev/null 2>&1 \
            || emit_bailed "manifest-schema-invalid"
        ;;
esac

# Step 6: post-Codex mechanical validation (only meaningful for complete/needs_qa;
# bailed is passed through verbatim).
if [[ "$STATUS" != "bailed" ]]; then
    # 6a: branch unchanged.
    CURRENT_BRANCH=$(git -C "$REPO_ROOT" rev-parse --abbrev-ref HEAD)
    if [[ "$CURRENT_BRANCH" != "$SPAWN_BRANCH" ]]; then
        emit_bailed "branch-changed"
    fi

    # 6b: .claude-plugin/plugin.json unchanged.
    if [[ -f "$REPO_ROOT/.claude-plugin/plugin.json" ]]; then
        CURRENT_PLUGIN_JSON=$(git -C "$REPO_ROOT" hash-object "$REPO_ROOT/.claude-plugin/plugin.json")
    else
        CURRENT_PLUGIN_JSON=$'\n'
    fi
    if [[ "$CURRENT_PLUGIN_JSON" != "$PLUGIN_JSON_BASELINE" ]]; then
        emit_bailed "protected-path-modified"
    fi

    # 6c: submodules clean.
    SUBMODULE_STATUS=$(git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null || true)
    if [[ -n "$SUBMODULE_STATUS" ]]; then
        # any leading char other than space indicates dirty/uninitialized/conflict
        if printf '%s\n' "$SUBMODULE_STATUS" | grep -qE '^[+\-U]'; then
            emit_bailed "submodule-dirty"
        fi
    fi
fi

# Step 7: complete-only checks: working tree clean + path normalization + diff cross-check.
if [[ "$STATUS" == "complete" ]]; then
    # 7a: working tree clean.
    DIRTY=$(git -C "$REPO_ROOT" status --porcelain)
    if [[ -n "$DIRTY" ]]; then
        emit_bailed "dirty-tree-after-codex"
    fi

    # 7b: path normalization on every files_touched[].path and tests_added_or_modified.
    # Reject: contains '..', starts with '/', equals .claude-plugin/plugin.json,
    # under a submodule (per submodule status), escapes repo root after symlink resolve.
    SUBMODULE_PATHS=$(git -C "$REPO_ROOT" submodule status --recursive 2>/dev/null \
        | awk '{print $2}' || true)

    paths_invalid=false
    while IFS= read -r p; do
        [[ -z "$p" ]] && continue
        # absolute path or contains ..
        if [[ "$p" == /* ]] || [[ "$p" == *..* ]] || [[ "$p" == *$'\0'* ]]; then
            paths_invalid=true; break
        fi
        # protected file
        if [[ "$p" == ".claude-plugin/plugin.json" ]]; then
            paths_invalid=true; break
        fi
        # under submodule (or the submodule gitlink pointer itself)
        if [[ -n "$SUBMODULE_PATHS" ]]; then
            while IFS= read -r sm; do
                [[ -z "$sm" ]] && continue
                if [[ "$p" == "$sm" || "$p" == "$sm"/* ]]; then
                    paths_invalid=true; break 2
                fi
            done <<< "$SUBMODULE_PATHS"
        fi
    done < <(jq -r '.files_touched[].path, .tests_added_or_modified[]' "$MANIFEST_RAW_PATH" 2>/dev/null)

    if [[ "$paths_invalid" == "true" ]]; then
        emit_bailed "protected-path-modified"
    fi

    # 7c: baseline-rooted diff cross-check (set equality).
    DIFF_PATHS=$(git -C "$REPO_ROOT" diff --name-only "$BASELINE_SHA"..HEAD | sort -u)
    MANIFEST_PATHS=$(jq -r '.files_touched[].path' "$MANIFEST_RAW_PATH" | sort -u)
    if [[ "$DIFF_PATHS" != "$MANIFEST_PATHS" ]]; then
        emit_bailed "manifest-diff-mismatch"
    fi

    # 7d: at least 1 commit since baseline.
    COMMITS_SINCE=$(git -C "$REPO_ROOT" rev-list --count "$BASELINE_SHA"..HEAD)
    if [[ "$COMMITS_SINCE" -lt 1 ]]; then
        emit_bailed "no-commit-since-baseline"
    fi

    # 7e: HEAD commit subject equals the first line of manifest.commit_message.
    # SKILL.md Step 4 and the Codex implementer prompt both rely on this
    # equality so downstream CHANGELOG / PR-body / OOS copy stays aligned with
    # the actual git history.
    HEAD_SUBJECT=$(git -C "$REPO_ROOT" log -1 --format=%s)
    MANIFEST_SUBJECT=$(jq -r '.commit_message // ""' "$MANIFEST_RAW_PATH" | head -n1)
    if [[ "$HEAD_SUBJECT" != "$MANIFEST_SUBJECT" ]]; then
        emit_bailed "commit-subject-mismatch"
    fi
fi

# Step 8: sanitization. Apply scripts/redact-secrets.sh to text fields, then
# write the canonical manifest.json (replacing the raw copy).
REDACT="$REPO_ROOT/scripts/redact-secrets.sh"
# Fail closed if the redactor file exists but is not executable — a sparse
# checkout or broken perms must NOT silently emit raw manifest text into
# downstream public surfaces (CHANGELOG, PR body, GitHub issues).
if [[ -e "$REDACT" && ! -x "$REDACT" ]]; then
    emit_bailed "redactor-not-executable"
fi
if [[ -x "$REDACT" ]]; then
    # Build a sanitized version of the manifest by piping each text field through
    # redact-secrets.sh. We use jq to extract, redact in shell, then re-inject.
    sanitize_string() {
        if [[ -z "$1" ]]; then printf '%s' ""; else printf '%s' "$1" | "$REDACT"; fi
    }

    # Extract fields, sanitize, and write a sanitized manifest.
    TMP_SAN="$TMPDIR_ARG/manifest-sanitized.json"
    # commit_message
    CM=$(jq -r '.commit_message // ""' "$MANIFEST_RAW_PATH")
    CM_SAN=$(sanitize_string "$CM")
    # bail_reason (kept verbatim - dispatcher tokens are non-sensitive)
    BR=$(jq -r '.bail_reason // ""' "$MANIFEST_RAW_PATH")

    # summary_bullets, todos_left: arrays of strings.
    # oos_observations: array of {title, description, phase}.
    # Rebuild via jq with the sanitized commit_message, then post-process arrays in shell.
    jq --arg cm "$CM_SAN" --arg br "$BR" \
        '.commit_message = $cm | .bail_reason = $br' "$MANIFEST_RAW_PATH" > "$TMP_SAN.0"

    # summary_bullets
    if jq -e '.summary_bullets | type == "array"' "$TMP_SAN.0" >/dev/null 2>&1; then
        SAN_BULLETS_FILE="$TMPDIR_ARG/manifest-bullets.json"
        : > "$SAN_BULLETS_FILE"
        printf '[' > "$SAN_BULLETS_FILE"
        first=true
        while IFS= read -r b; do
            sb=$(sanitize_string "$b")
            if [[ "$first" == "true" ]]; then first=false; else printf ',' >> "$SAN_BULLETS_FILE"; fi
            jq -Rn --arg s "$sb" '$s' >> "$SAN_BULLETS_FILE"
        done < <(jq -r '.summary_bullets[]?' "$TMP_SAN.0")
        printf ']' >> "$SAN_BULLETS_FILE"
        jq --slurpfile sb "$SAN_BULLETS_FILE" '.summary_bullets = $sb[0]' "$TMP_SAN.0" > "$TMP_SAN.1"
        mv "$TMP_SAN.1" "$TMP_SAN.0"
    fi

    # todos_left
    if jq -e '.todos_left | type == "array"' "$TMP_SAN.0" >/dev/null 2>&1; then
        SAN_TODOS_FILE="$TMPDIR_ARG/manifest-todos.json"
        : > "$SAN_TODOS_FILE"
        printf '[' > "$SAN_TODOS_FILE"
        first=true
        while IFS= read -r t; do
            st=$(sanitize_string "$t")
            if [[ "$first" == "true" ]]; then first=false; else printf ',' >> "$SAN_TODOS_FILE"; fi
            jq -Rn --arg s "$st" '$s' >> "$SAN_TODOS_FILE"
        done < <(jq -r '.todos_left[]?' "$TMP_SAN.0")
        printf ']' >> "$SAN_TODOS_FILE"
        jq --slurpfile td "$SAN_TODOS_FILE" '.todos_left = $td[0]' "$TMP_SAN.0" > "$TMP_SAN.1"
        mv "$TMP_SAN.1" "$TMP_SAN.0"
    fi

    # oos_observations: title and description only.
    if jq -e '.oos_observations | type == "array"' "$TMP_SAN.0" >/dev/null 2>&1; then
        SAN_OOS_FILE="$TMPDIR_ARG/manifest-oos.json"
        : > "$SAN_OOS_FILE"
        printf '[' > "$SAN_OOS_FILE"
        first=true
        OOS_LEN=$(jq '.oos_observations | length' "$TMP_SAN.0")
        i=0
        while (( i < OOS_LEN )); do
            ti=$(jq -r ".oos_observations[$i].title // \"\"" "$TMP_SAN.0")
            de=$(jq -r ".oos_observations[$i].description // \"\"" "$TMP_SAN.0")
            ph=$(jq -r ".oos_observations[$i].phase // \"implement\"" "$TMP_SAN.0")
            ti_san=$(sanitize_string "$ti")
            de_san=$(sanitize_string "$de")
            if [[ "$first" == "true" ]]; then first=false; else printf ',' >> "$SAN_OOS_FILE"; fi
            jq -Rn --arg t "$ti_san" --arg d "$de_san" --arg p "$ph" \
                '{title: $t, description: $d, phase: $p}' >> "$SAN_OOS_FILE"
            i=$((i + 1))
        done
        printf ']' >> "$SAN_OOS_FILE"
        jq --slurpfile oo "$SAN_OOS_FILE" '.oos_observations = $oo[0]' "$TMP_SAN.0" > "$TMP_SAN.1"
        mv "$TMP_SAN.1" "$TMP_SAN.0"
    fi

    mv "$TMP_SAN.0" "$MANIFEST_PATH"
fi

# Step 9: emit final KV envelope.
case "$STATUS" in
    complete)
        printf 'STATUS=complete\n'
        printf 'MANIFEST=%s\n' "$MANIFEST_PATH"
        printf 'TRANSCRIPT=%s\n' "$TRANSCRIPT_PATH"
        printf 'SIDECAR_LOG=%s\n' "$SIDECAR_LOG"
        ;;
    needs_qa)
        printf 'STATUS=needs_qa\n'
        printf 'MANIFEST=%s\n' "$MANIFEST_PATH"
        printf 'QA_PENDING=%s\n' "$QA_PENDING_PATH"
        printf 'TRANSCRIPT=%s\n' "$TRANSCRIPT_PATH"
        printf 'SIDECAR_LOG=%s\n' "$SIDECAR_LOG"
        ;;
    bailed)
        BR=$(jq -r '.bail_reason // "codex-bailed-no-reason"' "$MANIFEST_RAW_PATH")
        # Sanitize bail_reason for KV-grammar safety: collapse all
        # whitespace (including newlines) to single spaces, strip ASCII
        # control characters, and cap length so a Codex-authored token
        # cannot break the orchestrator's KV parser by emitting extra
        # `KEY=value` lines or control sequences.
        BR=$(printf '%s' "$BR" | tr -d '\000-\010\013\014\016-\037' | tr '\t\n\r' '   ' | sed -e 's/  */ /g' -e 's/^ //' -e 's/ $//' | cut -c1-200)
        [[ -z "$BR" ]] && BR="codex-bailed-no-reason"
        printf 'STATUS=bailed\n'
        printf 'REASON=%s\n' "$BR"
        printf 'MANIFEST=%s\n' "$MANIFEST_PATH"
        printf 'TRANSCRIPT=%s\n' "$TRANSCRIPT_PATH"
        printf 'SIDECAR_LOG=%s\n' "$SIDECAR_LOG"
        ;;
esac
exit 0
