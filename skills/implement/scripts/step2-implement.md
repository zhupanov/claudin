# step2-implement.sh

**Purpose**: Single dispatcher entrypoint for `/implement` Step 2. Branches on `--codex-available`; on the Codex path, drives the full Codex implementer loop end-to-end (spawn → manifest → mechanical validation → sanitization → final KV envelope) so SKILL.md Step 2 only needs to parse a deterministic key/value summary. There is no main-agent code-edit path reachable from Step 2 when `--codex-available true` — Claude fallback occurs ONLY when `--codex-available false` is passed in (i.e., the orchestrator's own `CODEX_AVAILABLE && CODEX_HEALTHY` test reported unavailable at Step 0).

**Invariants**:
- Mandatory Codex spawn when `--codex-available true`: there is exactly one branch on `--codex-available`, exactly one place that emits `STATUS=claude_fallback`. If the operator wants Claude to write code, the orchestrator's Step 0 availability test must report Codex unavailable.
- Two distinct roots: `PLUGIN_ROOT` (resolved from `SCRIPT_DIR/../../..`) is the plugin tree this script ships in — used for sibling plugin assets (`agents/codex-implementer.md`, `scripts/launch-codex-implement.sh`, `scripts/redact-secrets.sh`). `REPO_ROOT` (resolved from `git rev-parse --show-toplevel` against cwd) is the consumer git repo this run targets — used for every `git -C "$REPO_ROOT"` call and the `.claude-plugin/plugin.json` reference. The split is load-bearing: when the plugin is installed, `PLUGIN_ROOT` points inside `~/.claude/plugins/cache/...` which has no `.git`, so reusing it for git ops would make the first `git -C "$REPO_ROOT" ...` (the baseline write) abort the script with a non-zero exit and no KV envelope under `set -euo pipefail` — the orchestrator would then have no `STATUS=` line to parse and the operator would have to manually re-invoke with `--codex-available false` to obtain `STATUS=claude_fallback`. If cwd is not inside a git working tree on the Codex path, the dispatcher exits 2 (caller / invocation error) rather than spawning Codex against an undefined repo.
- Stdout is KV-only — `STATUS`, `MANIFEST`, `QA_PENDING`, `REASON`, `TRANSCRIPT`, `SIDECAR_LOG`. The launcher's progress chatter is captured to the sidecar log; the Codex transcript is captured to disk; neither leaks to stdout. SKILL.md Step 2's parser is a fixed grammar.
- Spawn-time baseline files are written ONCE on the first invocation under `$TMPDIR_ARG`: `step2-baseline.txt` (HEAD SHA), `step2-spawn-branch.txt` (branch name), `step2-plugin-json-baseline.txt` (`git hash-object` of `.claude-plugin/plugin.json`). All resume invocations reuse them. The baseline SHA is the anchor for the post-Codex `git diff --name-only $BASELINE..HEAD` set-equality cross-check.
- Resume counter is incremented ONLY when `--answers PATH` is supplied. Cap is 5; the 6th `--answers` invocation emits `STATUS=bailed REASON=qa-loop-exceeded` without spawning Codex.
- Single retry on transient launcher failure (no manifest written): retry only when post-failure state is fully clean (`git status --porcelain` empty, no `.git/index.lock`, HEAD == `BASELINE_SHA`). A dirty post-failure state emits `STATUS=bailed REASON=dirty-state-after-timeout`.
- The dispatcher does NOT git reset, NOT git checkout, NOT touch the working tree. Validation is read-only against git state. Codex's hard guard #1 (no `git reset --hard`) is mirrored here as "the dispatcher never destroys operator work either."
- Path validation rejects `..`, leading `/`, NUL, `.claude-plugin/plugin.json`, and any path under a submodule (per `git submodule status --recursive`). The reserved-file check is a defense-in-depth duplicate of `hooks/pre-commit-block-bump-version-edit.sh`'s contract.
- `bailed` manifests pass through verbatim (no working-tree-clean / diff-cross-check / commit-count enforcement) — Codex deliberately did not commit, and the orchestrator must see the reason token Codex chose.
- Exit code is 0 on every documented outcome (including `STATUS=bailed`). Exit 2 is reserved for caller-error (missing flag, bad path, bad enum value) before any Codex spawn.

**Stdout contract**:
```
STATUS=<complete|needs_qa|bailed|claude_fallback>
MANIFEST=<path>          # set when STATUS=complete or needs_qa or bailed (if manifest was written)
QA_PENDING=<path>        # set ONLY when STATUS=needs_qa
REASON=<token>           # set ONLY when STATUS=bailed
TRANSCRIPT=<path>        # set when launcher actually ran
SIDECAR_LOG=<path>       # set when launcher actually ran
```

**Flags**:

| Flag | Required | Purpose |
|------|----------|---------|
| `--tmpdir PATH` | yes | `$IMPLEMENT_TMPDIR` (where baseline / counter / manifest / transcript / sidecar log live) |
| `--plan-file PATH` | yes | The plan to implement (passed through to Codex) |
| `--feature-file PATH` | yes | The original feature description (passed through to Codex) |
| `--auto-mode VALUE` | yes | `true` or `false`; forwarded as context for the agent prompt; the dispatcher itself does not branch on it |
| `--codex-available VALUE` | yes | `true` or `false`; when `false`, immediately emits `STATUS=claude_fallback` and exits |
| `--answers PATH` | optional | Operator answers to a prior `needs_qa` cycle; presence increments the resume counter |

**Outcomes** (`STATUS` values):
- `complete` — Codex committed; all post-Codex mechanical checks passed; manifest sanitized and emitted at `$TMPDIR/manifest.json`.
- `needs_qa` — Codex wrote `qa-pending.json` with operator questions; SKILL.md Step 2 collects answers and re-invokes the dispatcher with `--answers`.
- `bailed` — Codex itself emitted `status=bailed`, OR the dispatcher overrode `complete` because mechanical validation failed. `REASON` token list is in `skills/implement/references/codex-manifest-schema.md` (Bail-reason tokens section). When the dispatcher overrides Codex, the dispatcher's reason wins.
- `claude_fallback` — Only when `--codex-available false`; the caller proceeds with the main-agent code-edit path.

**Bail-reason tokens emitted by the dispatcher** (set internally; full list in `codex-manifest-schema.md`):
`qa-loop-exceeded`, `qa-pending-missing`, `manifest-missing`, `manifest-schema-invalid`, `manifest-diff-mismatch`, `protected-path-modified`, `submodule-dirty`, `branch-changed`, `dirty-tree-after-codex`, `dirty-state-after-timeout`, `codex-runtime-failure`, `no-commit-since-baseline`, `commit-subject-mismatch`, `redactor-not-executable`. Codex-authored bail tokens (e.g., `resume-incompatible`, free-form) pass through verbatim — they are sanitized only for KV-grammar safety (whitespace and control characters collapsed to single spaces; capped at ~200 characters) before being emitted on `REASON=`.

**Call sites**:
- `skills/implement/SKILL.md` Step 2 — the only authorized caller.

**Edit-in-sync**:
- `skills/implement/references/codex-manifest-schema.md` — manifest schema and bail-reason tokens.
- `agents/codex-implementer.md` — the system prompt this dispatcher invokes.
- `scripts/launch-codex-implement.sh` — the leaf launcher this dispatcher calls.
- `skills/implement/SKILL.md` Step 2 — the caller; any change to the KV envelope must be mirrored in Step 2's parser.
- `skills/implement/scripts/test-step2-dispatch.sh` — the offline harness; any new outcome / reason token must be exercised.

**Test harness**: `skills/implement/scripts/test-step2-dispatch.sh` (offline) — covers the dispatcher branches that do not require launching Codex: the `--codex-available false` claude_fallback branch, argument-validation exit codes, missing `--answers` file, and the resume-counter cap (pre-seeded `codex-resume-count.txt` at 5; the 6th `--answers` invocation auto-bails with `qa-loop-exceeded` before any Codex spawn). Codex-spawning paths (manifest schema validation, `git diff` set-equality cross-check, sanitization, single-retry on transient failure, commit-subject check, post-Codex mechanical checks) are out of scope for this offline harness — see `skills/implement/scripts/test-step2-dispatch.md` for the full coverage list and rationale.

**Makefile wiring**: `make test-step2-dispatch` (added in the same change that introduces the harness).

**Note on Codex's hook bypass**: Codex's `--full-auto` mode does NOT route through Claude Code's `Edit`/`Write` PreToolUse hook chain (`hooks/block-submodule-edit.sh`, `hooks/pre-commit-block-bump-version-edit.sh` apply to Edit/Write only — Codex writes via raw shell). The dispatcher's post-Codex mechanical checks (`.claude-plugin/plugin.json` unchanged via `git hash-object`; submodule status clean; baseline-rooted diff cross-check) ARE the trust boundary in the Codex path. See `SECURITY.md` for the full trust model.
