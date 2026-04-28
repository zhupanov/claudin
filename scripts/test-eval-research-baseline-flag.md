# test-eval-research-baseline-flag.sh

## Purpose

Regression harness for the `--baseline` flag handling in `scripts/eval-research.sh`. Pins the post-#441, post-#477, and post-#780 behavior so these flag-state paths cannot silently regress:

1. **Sub-1** — `--baseline` not set: no `PREVIEW MODE` banner on stdout; exit 0; no cache file at `$WORK_DIR/baseline-rows.json`.
2. **Sub-2** — `--baseline <valid-ref>` (using `HEAD` against the committed `skills/research/references/eval-baseline.json` schema-only stub): exit 0; `PREVIEW MODE` banner present on stdout (visible alongside the summary table); baseline cached to `$WORK_DIR/baseline-rows.json`.
3. **Sub-3** — `--baseline <bogus-ref>`: exit 2; stderr error names the unresolvable ref AND surfaces a tail of `git show`'s captured stderr (so operators can distinguish ref-missing / file-missing-at-ref / non-git-checkout); no cache file left behind.
4. **Sub-4** — trailing `--baseline` with no following value: exit 2; stderr names `--baseline` as the flag missing its value. Pins the issue #477 fix that separated this case from the schema-validation exit-1 path; pre-fix, `shift 2` aborted under `set -e` with exit 1, indistinguishable from a real schema failure.
5. **Sub-5** — `--baseline` followed by another flag (e.g. `--baseline --scale standard`): exit 2; stderr names `--baseline` as the flag missing its value. Pins the issue #780 fix that extended `require_value` to take a third arg (the candidate value) and reject when it starts with `--`. Pre-fix, the validity regex `^[0-9A-Za-z._/-]+$` permitted `--scale` (hyphens are allowed), so `BASELINE_REF` was silently set to `--scale` and `git show --scale:...` produced a confusing downstream error. Mirrors `take_value` in `scripts/render-reviewer-prompt.sh`.

## Invocation

```bash
bash scripts/test-eval-research-baseline-flag.sh
```

Or via the standalone Makefile target:

```bash
make test-eval-research-baseline-flag
```

## Wiring

- **Standalone Makefile target** in the project `Makefile` — `test-eval-research-baseline-flag`. **NOT a `test-harnesses` prerequisite** by design (the runtime harness it tests is opt-in operator instrumentation explicitly carved out from CI; see `Makefile:148` and `docs/linting.md`'s `/research evaluation harness` section). Pattern follows `test-eval-set-structure` (Makefile:157-163).
- **`agent-lint.toml`** — listed in the `[lint].exclude` array so agent-lint's G004 dead-script rule does not flag this Makefile-only harness in CI. The matching pattern is the same as for `test-eval-set-structure.sh` and other Makefile-only harnesses.
- **CI**: locally `make lint` runs `test-harnesses` then `lint-only`; in CI those are separate jobs (`lint` + `test-harnesses`). This test runs in **neither** by default — operators invoke it on demand or as part of fixing/validating the `--baseline` flag area.

## Offline operation (PATH stubs)

`.github/workflows/ci.yaml`'s `test-harnesses` job only installs PyYAML — no `claude` or `jq`. Even though this harness is not wired into `test-harnesses`, it is designed to run offline so an operator on any machine can exercise it without the real Claude CLI:

- A stub `claude` is planted in a `mktemp -d` PATH-prefix so `eval-research.sh`'s `require_tool claude` check succeeds. The real binary is never invoked because `--id nonexistent-id-zzz` causes the eval loop to iterate zero entries.
- A stub `jq` is planted similarly. The only `jq` call before the baseline block is `validate_baseline_json`'s `jq -e '.version and .scale and (.entries | type == "array")' <file>`, which only checks exit status. The stub returns exit 0 unconditionally. The committed `eval-baseline.json` is a schema-only stub, so any real `jq` would also pass.
- The PATH-stub pattern mirrors `scripts/test-loop-improve-skill-driver.sh:25` and is the repo precedent for offline operation in tests that exercise `claude`-dependent scripts.

## Edit-in-sync

When editing this script, update this `.md` in the same PR (per AGENTS.md per-script-contract rule). Also update the matching contract bullets in `scripts/eval-research.md` if the assertions change in a way that revises `eval-research.sh`'s observable contract for the `--baseline` flag.
