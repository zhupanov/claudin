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
| `make test-validate-research-output` | Run the regression harness for `scripts/validate-research-output.sh` (the substantive-content validator invoked by `collect-reviewer-results.sh --substantive-validation` — Phase 3 of umbrella #413, closes #416, #447, #473). Exercises `scripts/test-validate-research-output.sh` — 51 cases covering the word-count threshold, fence-stripping word count, file/URL/code-fence/Makefile/leading-dot citation probes (probe 1 with the #447-broadened 51-extension list and trailing-token boundary that rejects fake citations like `file.mdjunk:42`, `file.md:garbage`, `file.md/child`, plus the #473 short-extension strict-mode rule that requires a path-likeness signal — `/`, `_`, `-`, or `:line-ref` — for short / generic-English-overlapping extensions like `lock`, `env`, `txt`, `c`, `h`, `m`, `r`), `--no-require-citations`, the `--validation-mode` preset (NO_ISSUES_FOUND short-circuit + 30-word floor), and error paths. A `make lint` prerequisite via `test-harnesses`. |
| `make test-collect-reviewer-bash32` | Run the regression harness for the bash 3.2 portability hazard at `scripts/collect-reviewer-results.sh:405` (closes #511). Exercises `scripts/test-collect-reviewer-bash32.sh` — Case 1 statically pins the safe-expansion idiom `"${VAL_ARGS[@]+"${VAL_ARGS[@]}"}"` at the validator call site (always-on regression backstop regardless of bash version; bash 4.4+ does not exhibit the empty-array nounset hazard at runtime); Case 2 exercises the actual collector under any `/bin/bash` whose version is `< 4.4` (bash 3.x or bash 4.0-4.3 — both still vulnerable) with a ≥200-word substantive fixture and asserts `STATUS=OK` plus clean stderr (skip-with-loud-message on bash 4.4+); Case 3 pins `--validation-mode` flag forwarding under the same vulnerable-bash gate using a literal `NO_ISSUES_FOUND` fixture with both a positive assertion (`--validation-mode` present → `STATUS=OK`) and a negative control (`--validation-mode` absent → `STATUS=NOT_SUBSTANTIVE` from the 200-word floor). A `make lint` prerequisite via `test-harnesses`. |
| `make test-run-research-planner` | Run the offline regression harness for `skills/research/scripts/run-research-planner.sh` (the planner-output validator invoked by `/research --plan` Step 1.1 — closes #420). Exercises `skills/research/scripts/test-run-research-planner.sh` — 22 cases covering the `2 ≤ count ≤ 4` gate, the trailing-`?` question heuristic (defends against prose preambles), bullet-prefix stripping, control-character stripping, whitespace trim, empty-input fail-closed, and the `REASON` token vocabulary (`empty_input` / `count_below_minimum` / `count_above_maximum` / `missing_arg` / `bad_path`). A `make lint` prerequisite via `test-harnesses`. |
| `make test-standard-angle-prompts` | Run the offline structural regression harness for the `/research --scale=standard` per-lane angle-prompt mapping (closes #508). Exercises `skills/research/scripts/test-standard-angle-prompts.sh` — pins `RESEARCH_PROMPT_BASELINE` literal in `research-phase.md`, all four angle-prompt identifiers, and the section-scoped per-lane mapping inside the Step 1.3 `### Standard` subsection (Cursor → ARCH, Codex → EDGE/EXT with `external_evidence_mode` switching language, Claude inline → SEC). Section extraction is H2-then-H3 nested (`## 1.3` → `### Standard`) so other `### Standard` subsections in 1.4/1.5 cannot satisfy the pins. A `make lint` prerequisite via `test-harnesses`. |
| `make eval-research [ARGS="--id ..."]` | Run the **opt-in** `/research` evaluation harness (closes #419 under umbrella #413). Reads `skills/research/references/eval-set.md`, runs each entry through `/research` as a fresh `claude -p` subprocess, scores the output along deterministic + LLM-as-judge axes, and emits a markdown summary table (or a populated `eval-baseline.json`-shaped file with `--write-baseline`). **Not a `make lint` prerequisite** — runs ~20 questions × ~30-60s each, costs real tokens. Pass flags via `ARGS=` or invoke `bash scripts/eval-research.sh ...` directly. See `scripts/eval-research.md` for the full contract. |
| `make test-eval-set-structure` | Run the **standalone** offline structural test for the `/research` eval set + harness (closes #419). Exercises `scripts/test-eval-set-structure.sh` — entry count, category coverage, schema validity, ≥2 adversarial entries, baseline JSON schema, harness self-test (`bash scripts/eval-research.sh --smoke-test`). Cheap (no API cost). **NOT** a `test-harnesses` prerequisite — kept standalone for symmetry with the runtime harness's opt-in shape. |
| `make test-eval-research-baseline-flag` | Run the **standalone** offline regression harness for the `--baseline` flag handling in `scripts/eval-research.sh` (closes #441). Exercises `scripts/test-eval-research-baseline-flag.sh` — three flag-state paths (no-flag, valid-ref, bad-ref) with PATH-stubbed `claude` and `jq` so the test runs without those binaries. Pins the post-#441 PREVIEW MODE banner + exit-2-on-bad-ref behavior. Cheap (no API cost). **NOT** a `test-harnesses` prerequisite — same opt-in shape as `test-eval-set-structure` and the runtime harness. |
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
