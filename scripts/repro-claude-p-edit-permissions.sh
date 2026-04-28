#!/usr/bin/env bash
# repro-claude-p-edit-permissions.sh — Isolated reproducer for the `claude -p`
# Edit-permission stall observed in #566. Runs ONE variant per invocation
# (--variant {A,B,C,D}) and validates the kernel fix in #585 plus the
# settings-audit hypothesis independently of the full skill improvement
# pipeline.
#
# The script invokes `claude -p` as a subprocess against the project's
# permission stack (settings.json + settings.local.json + PreToolUse hooks),
# asks the model to perform a trivial edit on skills/umbrella/SKILL.md,
# and classifies the outcome by combining a stall-regex grep on combined
# stdout+stderr with a `git diff` ground-truth check on the edit target.
#
# Opt-in operator instrumentation. NOT a CI gate. Depends on a real
# authenticated `claude` binary, costs API tokens, and is timing-sensitive.
# See scripts/repro-claude-p-edit-permissions.md for the full contract.
#
# Usage:
#   bash scripts/repro-claude-p-edit-permissions.sh --variant {A|B|C|D} [--smoke-test]
#   bash scripts/repro-claude-p-edit-permissions.sh --help
#
# Exit codes:
#   0   variant's expected outcome was observed (or Variant C, observational)
#   1   variant's expected outcome diverged from observed
#   2   preflight failure (binaries missing, dirty tree, bad arg)
#   3   PROBE_STATUS=skipped_no_claude (claude binary not on PATH)

set -euo pipefail

# Variables referenced by the cleanup trap MUST be initialized before the trap
# is registered, so `set -u` does not error on first cleanup-time check.
SETTINGS_BACKUP=""
SETTINGS_RENAMED_AWAY=""
LOCAL_SETTINGS_RENAMED_AWAY=""
REPRO_WORKDIR=""

# Stall signature pinned to the canonical phrase from #566.
STALL_SIGNATURE="Edit tool is repeatedly returning"

# Edit target (must be tracked in git so `git checkout --` can restore it).
EDIT_TARGET="skills/umbrella/SKILL.md"

# Variant outcome bookkeeping.
VARIANT=""
SMOKE_TEST=0
KERNEL_FLAGS=""
SETTINGS_OP="none"
EXPECTED=""
RESULT=""
REPO_ROOT=""
TIMEOUT_CMD=""

usage() {
  sed -n '2,/^$/p' "$0" | sed 's/^# \{0,1\}//'
}

require_value() {
  local flag="$1" val="${2-}"
  if [[ -z "$val" || "$val" == --* ]]; then
    echo "ERROR: $flag requires a value" >&2
    exit 2
  fi
}

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --variant)
        require_value "$1" "${2-}"
        VARIANT="$2"
        shift 2
        ;;
      --smoke-test)
        SMOKE_TEST=1
        shift
        ;;
      --help|-h)
        usage
        exit 0
        ;;
      *)
        echo "ERROR: unknown argument: $1" >&2
        usage >&2
        exit 2
        ;;
    esac
  done

  case "$VARIANT" in
    A|B|C|D) ;;
    "") echo "ERROR: --variant {A|B|C|D} is required" >&2; exit 2 ;;
    *)  echo "ERROR: --variant must be one of A, B, C, D (got '$VARIANT')" >&2; exit 2 ;;
  esac
}

# shellcheck disable=SC2329,SC2317  # cleanup() is invoked indirectly via `trap`.
cleanup() {
  local rc=$?

  if [[ -n "$SETTINGS_BACKUP" && -f "$SETTINGS_BACKUP" ]]; then
    mv -f "$SETTINGS_BACKUP" .claude/settings.json 2>/dev/null || true
  fi
  if [[ -n "$SETTINGS_RENAMED_AWAY" && -f "$SETTINGS_RENAMED_AWAY" ]]; then
    mv -f "$SETTINGS_RENAMED_AWAY" .claude/settings.json 2>/dev/null || true
  fi
  if [[ -n "$LOCAL_SETTINGS_RENAMED_AWAY" && -f "$LOCAL_SETTINGS_RENAMED_AWAY" ]]; then
    mv -f "$LOCAL_SETTINGS_RENAMED_AWAY" .claude/settings.local.json 2>/dev/null || true
  fi

  # Restore edit target if it was modified (no-op when clean).
  git checkout -- "$EDIT_TARGET" 2>/dev/null || true

  if [[ -n "$REPRO_WORKDIR" && -d "$REPRO_WORKDIR" ]]; then
    rm -rf "$REPRO_WORKDIR"
  fi

  exit "$rc"
}

register_cleanup_trap() {
  trap cleanup EXIT INT TERM
}

require_binary() {
  local bin="$1"
  command -v "$bin" >/dev/null 2>&1
}

resolve_timeout_cmd() {
  # Require the GNU `--kill-after` flag so SIGKILL margin works as documented.
  if command -v timeout >/dev/null 2>&1 && timeout --help 2>&1 | grep -q kill-after; then
    echo timeout
  elif command -v gtimeout >/dev/null 2>&1 && gtimeout --help 2>&1 | grep -q kill-after; then
    echo gtimeout
  else
    echo ""
  fi
}

preflight() {
  # Repo root + cwd normalization (resolve symlinks via pwd -P).
  local repo_root
  repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -z "$repo_root" ]]; then
    echo "ERROR: not inside a git repository" >&2
    exit 2
  fi
  cd "$repo_root"
  REPO_ROOT="$(pwd -P)"

  # Required binaries.
  if ! require_binary git; then
    echo "ERROR: git not on PATH" >&2
    exit 2
  fi
  if ! require_binary jq; then
    echo "ERROR: jq not on PATH (required for safe Variant C JSON build)" >&2
    exit 2
  fi
  TIMEOUT_CMD="$(resolve_timeout_cmd)"
  if [[ -z "$TIMEOUT_CMD" ]]; then
    echo "ERROR: neither 'timeout' nor 'gtimeout' on PATH" >&2
    exit 2
  fi
  if ! require_binary claude; then
    echo "PROBE_STATUS=skipped_no_claude"
    echo "claude binary not on PATH; nothing to reproduce. Exiting 3."
    exit 3
  fi

  # Edit target must exist and be tracked.
  if [[ ! -f "$EDIT_TARGET" ]]; then
    echo "ERROR: edit target not found: $EDIT_TARGET" >&2
    exit 2
  fi
  if ! git ls-files --error-unmatch -- "$EDIT_TARGET" >/dev/null 2>&1; then
    echo "ERROR: edit target is not tracked in git: $EDIT_TARGET" >&2
    exit 2
  fi

  # Refuse to start if the edit target or settings files are dirty —
  # we never want to clobber operator work.
  if ! git diff --quiet -- "$EDIT_TARGET"; then
    echo "ERROR: $EDIT_TARGET is dirty in working tree; refusing to start" >&2
    exit 2
  fi
  if [[ -f .claude/settings.json ]] && ! git diff --quiet -- .claude/settings.json; then
    echo "ERROR: .claude/settings.json is dirty in working tree; refusing to start" >&2
    exit 2
  fi

  # Variants C and D mutate .claude/settings.json in place; require it to exist.
  if [[ "$VARIANT" == "C" || "$VARIANT" == "D" ]] && [[ ! -f .claude/settings.json ]]; then
    echo "ERROR: .claude/settings.json is required for Variant $VARIANT but not found" >&2
    exit 2
  fi

  # defaultMode-vs-Variant-A consistency warning.
  if [[ "$VARIANT" == "A" && -f .claude/settings.json ]]; then
    local default_mode
    default_mode="$(jq -r '.permissions.defaultMode // ""' .claude/settings.json 2>/dev/null || true)"
    if [[ "$default_mode" == "bypassPermissions" ]]; then
      cat >&2 <<'WARN'
**⚠ WARNING:** the live `.claude/settings.json` has `permissions.defaultMode == "bypassPermissions"`.
Variant A is defined as "no kernel flag + current settings"; #566's stall reproduced on this same
shape, so the test is meaningful, but the outcome may diverge from EXPECTED=stall on this tree.
The script will report the actual observed outcome.
WARN
    fi
  fi

  # Scratch dir for the prompt + output captures.
  REPRO_WORKDIR="$(mktemp -d -t repro-claude-p-edit-permissions.XXXXXX)"
}

stage_variant() {
  local local_settings=".claude/settings.local.json"

  case "$VARIANT" in
    A)
      KERNEL_FLAGS=""
      SETTINGS_OP="none"
      EXPECTED="stall"
      # Stage settings.local.json aside so it does not pollute the test.
      if [[ -f "$local_settings" ]]; then
        LOCAL_SETTINGS_RENAMED_AWAY="${local_settings}.repro.bak"
        mv -f "$local_settings" "$LOCAL_SETTINGS_RENAMED_AWAY"
      fi
      ;;
    B)
      KERNEL_FLAGS="--permission-mode bypassPermissions"
      SETTINGS_OP="none"
      EXPECTED="edit_completed"
      # Variant B's invariant: do NOT mutate any settings file.
      ;;
    C)
      KERNEL_FLAGS=""
      SETTINGS_OP="replace"
      EXPECTED="observational_only"
      # Stage local settings aside, then replace .claude/settings.json with the
      # path-qualified Read+Edit+Write allow rule. Build via jq to handle
      # paths with quotes/whitespace safely.
      if [[ -f "$local_settings" ]]; then
        LOCAL_SETTINGS_RENAMED_AWAY="${local_settings}.repro.bak"
        mv -f "$local_settings" "$LOCAL_SETTINGS_RENAMED_AWAY"
      fi
      SETTINGS_BACKUP=".claude/settings.json.repro.bak"
      cp -f .claude/settings.json "$SETTINGS_BACKUP"
      local staging=".claude/settings.json.repro.new"
      jq -n --arg p "$REPO_ROOT" '{permissions:{allow:["Read(\($p)/skills/**)","Edit(\($p)/skills/**)","Write(\($p)/skills/**)"]}}' \
        > "$staging"
      mv -f "$staging" .claude/settings.json
      ;;
    D)
      KERNEL_FLAGS="--permission-mode bypassPermissions"
      SETTINGS_OP="rename"
      EXPECTED="edit_completed"
      # Stage local settings + rename main settings file aside.
      if [[ -f "$local_settings" ]]; then
        LOCAL_SETTINGS_RENAMED_AWAY="${local_settings}.repro.bak"
        mv -f "$local_settings" "$LOCAL_SETTINGS_RENAMED_AWAY"
      fi
      SETTINGS_RENAMED_AWAY=".claude/settings.json.repro.bak"
      mv -f .claude/settings.json "$SETTINGS_RENAMED_AWAY"
      ;;
  esac

  echo "VARIANT=$VARIANT"
  echo "KERNEL_FLAGS=${KERNEL_FLAGS:-(none)}"
  echo "SETTINGS_OP=$SETTINGS_OP"
  echo "EXPECTED=$EXPECTED"
}

write_prompt() {
  local prompt_file="$1"
  local marker
  marker="$(date +%s)-$$-$VARIANT"
  cat > "$prompt_file" <<EOF
Append a single trailing HTML comment line to the file $EDIT_TARGET. The comment must be exactly the line:

<!-- repro-claude-p-edit-permissions $marker -->

Do not modify any other line. After the edit, exit immediately.
EOF
}

invoke_claude_p() {
  local prompt_file="$REPRO_WORKDIR/prompt.txt"
  local out_file="$REPRO_WORKDIR/out"
  local err_file="$REPRO_WORKDIR/err"

  write_prompt "$prompt_file"

  # Build claude argv: --plugin-dir and (for B/D) --permission-mode.
  # KERNEL_FLAGS is intentionally word-split on whitespace.
  local timeout_exit=0
  set +e
  # shellcheck disable=SC2086
  "$TIMEOUT_CMD" --kill-after=10s 60s claude -p $KERNEL_FLAGS --plugin-dir "$REPO_ROOT" \
    < "$prompt_file" > "$out_file" 2> "$err_file"
  timeout_exit=$?
  set -e

  echo "TIMEOUT_EXIT=$timeout_exit"

  # Classification on combined stdout+stderr.
  if grep -q -F "$STALL_SIGNATURE" "$out_file" "$err_file" 2>/dev/null; then
    RESULT="stall"
  elif ! git diff --quiet -- "$EDIT_TARGET"; then
    RESULT="edit_completed"
  elif [[ "$timeout_exit" == "124" || "$timeout_exit" == "137" ]]; then
    RESULT="timeout"
  else
    RESULT="inconclusive"
  fi
  echo "RESULT=$RESULT"
}

verify_against_expected() {
  if [[ "$EXPECTED" == "observational_only" ]]; then
    echo "OUTCOME=observational"
    echo "Variant $VARIANT is observational; recorded RESULT=$RESULT. Exiting 0."
    exit 0
  fi
  if [[ "$RESULT" == "$EXPECTED" ]]; then
    echo "OUTCOME=match"
    echo "Variant $VARIANT: RESULT=$RESULT matches EXPECTED=$EXPECTED. Exiting 0."
    exit 0
  fi
  echo "OUTCOME=divergence"
  echo "Variant $VARIANT: RESULT=$RESULT diverged from EXPECTED=$EXPECTED. Exiting 1." >&2
  exit 1
}

main() {
  parse_args "$@"
  preflight
  register_cleanup_trap
  stage_variant
  if [[ "$SMOKE_TEST" -eq 1 ]]; then
    echo "SMOKE_TEST=1; skipping claude invocation. Cleanup will restore staged state."
    exit 0
  fi
  invoke_claude_p
  verify_against_expected
}

main "$@"
