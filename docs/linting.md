# Linting

Larch uses [pre-commit](https://pre-commit.com/) as the source of truth for linter configuration. Linter definitions, versions, and file filters live in `.pre-commit-config.yaml`. CI adds dedicated per-tool jobs on top of pre-commit for the most safety-relevant checks (secret scanning, agent-config linting) so individual failures can be diagnosed and re-run independently.

## Linters

| Linter | File Types | Description |
|--------|-----------|-------------|
| [shellcheck](https://www.shellcheck.net/) | `.sh` | Shell script analysis |
| [markdownlint](https://github.com/igorshubovych/markdownlint-cli) | `.md` | Markdown style enforcement (config: `.markdownlint.json`) |
| [jq](https://jqlang.github.io/jq/) | `.json` | JSON syntax validation |
| [actionlint](https://github.com/rhysd/actionlint) | `.yml`, `.yaml` | GitHub Actions workflow validation |
| [agnix](https://github.com/agent-sh/agnix) | `SKILL.md`, `CLAUDE.md`, agent configs | AI agent configuration linting (config: `.agnix.toml`) |
| [gitleaks](https://github.com/gitleaks/gitleaks) | all tracked files | Secret detection (pre-commit + dedicated CI job, full-history). Path allowlist in `.gitleaks.toml`. See `SECURITY.md` → "Layered secret scanning". |

## Usage

There are three pre-commit-driven paths:

- **CI** — The `lint` job runs `make lint-only` (repo-wide pre-commit over all files). CI also runs separate dedicated jobs on top of the `lint` job: `agent-lint`, `agnix`, `gitleaks` (installs the same pinned engine and runs a full git-history scan on its own so the signal is independently re-runnable), `trufflehog` (CI-only; see "CI secret scanning" below), and `agent-sync` / `smoke-dialectic` for internal invariants.
- **`/relevant-checks`** — Runs `pre-commit run --files <changed-files>` scoped to branch changes. Invoked automatically by `/implement` and `/review`. Hooks with `pass_filenames: false` (gitleaks) scan the full tree regardless of the scoped path argument — intentional so scoped checks cannot silently miss secrets outside the changed file set.
- **Local git hook** — Run `make setup` (or `pre-commit install`) to enable pre-commit hooks on every commit. Bypassable via `git commit --no-verify`; the CI jobs are the enforced backstop.

## CI secret scanning

Two scanners run as dedicated CI jobs in `.github/workflows/ci.yaml`:

- **`gitleaks`** — Installs the same pinned `v8.18.4` engine used by the pre-commit hook (via a checksum-verified direct download of `gitleaks_8.18.4_linux_x64.tar.gz`) and scans the git log (`gitleaks detect --source .`) with `fetch-depth: 0`. Complementary to the `lint` job, which runs the pre-commit hook in `--no-git` mode over the working tree only — together they cover working-tree + full history with one pinned engine version.
- **`trufflehog`** — Runs `trufflesecurity/trufflehog` pinned to its commit SHA for `v3.82.13` (supply-chain: tags are mutable) with `version: 3.82.13` pinning the Docker image and `--only-verified`, so findings fire only for credentials that authenticate against a live provider API.

See `SECURITY.md` → "Layered secret scanning" for the full three-layer model and allowlist discussion.

## Makefile Targets

| Target | Description |
|--------|-------------|
| `make lint` | Run all linters repo-wide |
| `make shellcheck` | Run shellcheck only |
| `make markdownlint` | Run markdownlint only |
| `make jsonlint` | Run JSON validation only |
| `make actionlint` | Run actionlint only |
| `make agnix` | Run agnix only |
| `make gitleaks` | Run gitleaks only (via pre-commit; scans the working tree with `--no-git`) |
| `make trufflehog` | Run trufflehog via Docker in `filesystem` mode over the working tree (same pinned image and `--only-verified` flag as the CI `trufflehog` job, but CI uses the action's default `git` mode over the PR range — local and CI are not byte-identical invocations). Requires Docker daemon running locally |
| `make setup` | Install pre-commit git hooks |
| `make smoke-dialectic` | Run the offline fixture-driven smoke test for `/design` Step 2a.5 (dialectic parser + tally + structural-invariant guard). Exercises `scripts/dialectic-smoke-test.sh` against `tests/fixtures/dialectic/`. |
| `make test-block-submodule` | Run the regression harness for `scripts/block-submodule-edit.sh` (the PreToolUse hook that denies edits inside submodules). Exercises `scripts/test-block-submodule-edit.sh` end-to-end against a temporary superproject + submodule fixture. |
| `make test-deny-edit-write` | Run the regression harness for `scripts/deny-edit-write.sh` (the skill-scoped PreToolUse hook registered by `/research` that permits `Edit`/`Write`/`NotebookEdit` only when the target path resolves under canonical `/tmp`, denies otherwise). Exercises `scripts/test-deny-edit-write.sh` — repo-deny, `/tmp`-allow, traversal-deny, relative-deny, `notebook_path` allow/deny, fail-closed on empty path, malformed JSON, idempotency, and `jq`-absent fallback byte-identity. |
| `make test-lib-halt-ledger` | Run the offline regression harness for `scripts/lib-loop-improve-halt-ledger.sh` (the sourced-only halt-location classifier consumed by the halt-rate probe). Exercises `scripts/test-lib-loop-improve-halt-ledger.sh` — empty dir, nonexistent dir, each per-substep sentinel, multi-iteration highest-iter scan, and empty-sentinel-treated-as-missing cases. A `make lint` prerequisite. |
| `make halt-rate-probe` | Run the **opt-in** halt-rate regression probe for `/larch:loop-improve-skill` (closes #278). Exercises `scripts/test-loop-improve-skill-halt-rate.sh` end-to-end against a throwaway fixture skill to measure how often the loop halts mid-turn after `/skill-judge` returns (the recurring failure from #273). **Not a `make lint` prerequisite** — too slow and non-deterministic for CI. See "Halt-rate regression harness" below for the output contract and caveats. |
| `make test-quick-mode-docs-sync` | Run the regression harness for `/implement --quick` public-docs sync (closes #370) plus required cross-references (closes #377). Exercises `scripts/test-quick-mode-docs-sync.sh` in both default mode (positive-anchor + stale-phrase checks against `README.md`, `docs/review-agents.md`, `docs/workflow-lifecycle.md`, and `skills/implement/SKILL.md`, plus a required cross-reference check for `docs/review-agents.md` → `skills/shared/voting-protocol.md`) and `--self-test` mode (two `check_file` fixtures + three `check_xref` fixtures proving both check mechanics). Canonical source of truth for the enforced markers, stale-phrase list, and cross-references is the script itself + sibling `scripts/test-quick-mode-docs-sync.md`. A `make lint` prerequisite. |

## Halt-rate regression harness

Opt-in probe that measures how often `/larch:loop-improve-skill` halts mid-iteration. Closes #278; tracks the halt-problem umbrella #273. Invocation:

```bash
make halt-rate-probe
# or with custom flags:
bash scripts/test-loop-improve-skill-halt-rate.sh --runs 10 --timeout-per-run 2400
```

**Flags**: `--runs N` (default 5), `--timeout-per-run SEC` (default 1800), `--keep-tmpdirs` (skip cleanup for forensics).

**Prerequisites**: `claude` CLI on `PATH` (headless mode) + GNU `timeout` (macOS: `brew install coreutils`, then `gtimeout` is detected automatically). The harness provisions a per-run bare git origin under `mktemp -d`, copies the fixture skill from `tests/fixtures/loop-halt-rate/SKILL.md`, PATH-shims `gh` to a no-op stub (so no live GitHub side effects), then invokes `claude --plugin-dir <larch-root> -p "/larch:loop-improve-skill loop-halt-rate"` bounded by `timeout --kill-after=10`.

**Output contract** (stdout — automation should grep these tokens):

```
RUN <i>: status=<completed_by_outer|halt_mid_turn|halt_detected_by_outer|timeout|tool_failure|error> last_completed=<token> clause="<halt-location clause>" elapsed=<s>s
...
HALT_RATE=<halted>/<measured>
MEASURED_RUNS=<measured>
PROBE_STATUS=ok|skipped_no_claude|error
PER_STATUS_BREAKDOWN: completed=<n> halt_mid_turn=<n> halt_detected_by_outer=<n> timeout=<n> tool_failure=<n> error=<n>
PER_LOCATION_BREAKDOWN: none=<n> 3j=<n> 3jv=<n> 3d-pre-detect=<n> 3d-post-detect=<n> 3d-plan-post=<n> 3i=<n> done=<n>
```

- `HALT_RATE` numerator = `halt_mid_turn + halt_detected_by_outer`. Denominator = `MEASURED_RUNS` = runs excluding `error` and `tool_failure` (infrastructure failures that prevented measurement). Automation should check `PROBE_STATUS` before consuming `HALT_RATE`; the KV format `HALT_RATE=0/0` with `PROBE_STATUS=error` signals "no measurement" and must not be conflated with "zero halts observed".
- `halt_mid_turn` is the halt-of-interest from #273: the outer skill itself ended its turn before reaching its Step 5 close-out.
- `halt_detected_by_outer` is a LEGACY branch from the pre-rewrite split-skill topology (outer `/loop-improve-skill` delegating to inner `/loop-improve-skill-iter` via the Skill tool with a `#231` mechanical gate catching `iteration sentinel missing`). Under the new bash-driver topology (`skills/loop-improve-skill/scripts/driver.sh`, #273) this branch is never emitted and is expected to report `0` — the driver eliminates the inner-halt class by construction. True mid-turn halts under the new topology manifest as `claude -p` subprocess exit-code failures, which the driver handles via `break` with category-specific `EXIT_REASON` (e.g. `subprocess failure at /skill-judge iteration N`), classified as `completed_by_outer` since the outer itself reaches Step 5 close-out.
- `completed_by_outer` includes all normal loop exits: `grade_a_achieved`, `max iterations (10) reached`, and infeasibility exits like `im_verification_failed`. `/im` is expected to fail under the stubbed `gh` — this is NOT the halt-of-interest; the halt-of-interest fires much earlier, at `/skill-judge` return.
- `timeout` covers both `timeout --kill-after` TERM (exit 124) and SIGKILL escalation (exit 137 = 128+9).
- `tool_failure` covers wrapper exits other than 0/124/137 where no LOOP_TMPDIR was ever emitted — claude itself crashed or the plugin failed to load.
- `PROBE_STATUS=error` can be emitted from two paths with different exit codes — consumers should treat both the same way (don't consume `HALT_RATE` as signal), but should not rely on the exit code to distinguish: (a) **post-measurement** `PROBE_STATUS=error` with **exit 0** when `MEASURED_RUNS=0` OR any `error`/`tool_failure` run occurred; (b) **preflight** `PROBE_STATUS=error` with **exit 1** when a startup check fails (missing `timeout`/`gtimeout`, bad repo root, missing fixture). The stdout token is identical; check `PROBE_STATUS` before `HALT_RATE`.
- `PROBE_STATUS=skipped_no_claude` is emitted (and the harness exits **non-zero**) when the `claude` binary is absent, per issue #278's explicit contract.
- `PER_LOCATION_BREAKDOWN` tokens correspond to the `LAST_COMPLETED` taxonomy owned by `clause_for_last_completed()` in `scripts/lib-loop-improve-halt-ledger.sh`.

**Caveats**:

- Runtime is highly variable (~5-30min per run). Budget accordingly.
- The fixture is a minimal deliberately-deficient skill; measured halt rate is a *lower bound* on production halt rate — real target skills produce longer reviewer chains that amplify the turn-end cue. Document this when publishing comparative numbers.
- Each run consumes real Claude API tokens + external reviewer (Cursor/Codex) latency.
- `gh` is PATH-shimmed to a no-op stub — no live GitHub issue creation, no PR creation, no live CI. `/im` will typically fail with `ITER_STATUS=im_verification_failed` (classified as `completed_by_outer`, not a halt).
- Not wired into `make lint` by design — opt-in only.
