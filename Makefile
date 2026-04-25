# Larch Makefile
# Thin wrapper around pre-commit. Linter definitions live in .pre-commit-config.yaml.

.PHONY: lint lint-only test-harnesses shellcheck markdownlint jsonlint actionlint agent-lint agnix gitleaks trufflehog setup test-redact test-validate-research-output test-parse-input test-parse-args test-parse-prose-blockers test-issue-lifecycle test-fix-issue-bail-detection test-fix-issue-step-order test-find-lock-issue test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-render-lane-status test-render-deep-lane-status test-verify-skill-called test-check-bump-version test-lint-skill-invocations test-anti-halt test-orchestrator-scope-sync test-design-structure test-implement-rebase-macro test-implement-structure test-quick-mode-docs-sync test-references-headers test-render-reviewer-prompt test-research-structure test-research-adjudication test-review-structure test-run-research-planner test-subskill-anchors test-loop-improve-skill-driver test-loop-improve-skill-skill-md test-loop-review-driver test-loop-review-skill-md test-improve-skill-iteration test-improve-skill-skill-md test-parse-skill-judge-grade test-lib-halt-ledger test-tracking-issue-write test-tracking-issue-read-sentinel test-assemble-anchor smoke-dialectic halt-rate-probe eval-research test-eval-set-structure test-eval-research-baseline-flag

# CI splits `lint` into `lint-only` (pre-commit) and `test-harnesses`
# (regression harnesses). `lint` remains the local-dev convenience target
# that runs both, defined in terms of the two split targets to prevent drift.
lint: test-harnesses lint-only

lint-only:
	pre-commit run --all-files

test-harnesses: test-redact test-validate-research-output test-parse-input test-parse-args test-parse-prose-blockers test-issue-lifecycle test-fix-issue-bail-detection test-fix-issue-step-order test-find-lock-issue test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-render-lane-status test-render-deep-lane-status test-verify-skill-called test-check-bump-version test-lint-skill-invocations test-anti-halt test-orchestrator-scope-sync test-design-structure test-implement-rebase-macro test-implement-structure test-quick-mode-docs-sync test-references-headers test-render-reviewer-prompt test-research-structure test-research-adjudication test-review-structure test-run-research-planner test-subskill-anchors test-loop-improve-skill-driver test-loop-improve-skill-skill-md test-loop-review-driver test-loop-review-skill-md test-improve-skill-iteration test-improve-skill-skill-md test-parse-skill-judge-grade test-lib-halt-ledger test-tracking-issue-write test-tracking-issue-read-sentinel test-assemble-anchor

test-redact:
	bash scripts/test-redact-secrets.sh

test-validate-research-output:
	bash scripts/test-validate-research-output.sh

test-parse-input:
	bash skills/issue/scripts/test-parse-input.sh

test-parse-args:
	bash scripts/test-parse-args.sh

test-parse-prose-blockers:
	bash skills/fix-issue/scripts/test-parse-prose-blockers.sh

test-issue-lifecycle:
	bash skills/fix-issue/scripts/test-issue-lifecycle.sh

test-fix-issue-bail-detection:
	bash skills/fix-issue/scripts/test-fix-issue-bail-detection.sh

test-fix-issue-step-order:
	bash skills/fix-issue/scripts/test-fix-issue-step-order.sh

test-find-lock-issue:
	bash skills/fix-issue/scripts/test-find-lock-issue.sh

test-sessionstart:
	bash scripts/test-sessionstart-health.sh

test-audit-edit-write:
	bash scripts/test-audit-edit-write.sh

test-block-submodule:
	bash scripts/test-block-submodule-edit.sh

test-deny-edit-write:
	bash scripts/test-deny-edit-write.sh

test-post-scaffold-hints:
	bash scripts/test-post-scaffold-hints.sh

test-render-skill:
	bash skills/create-skill/scripts/test-render-skill-md.sh

test-render-lane-status:
	bash scripts/test-render-lane-status.sh

test-render-deep-lane-status:
	bash scripts/test-render-deep-lane-status.sh

test-verify-skill-called:
	bash scripts/test-verify-skill-called.sh

test-check-bump-version:
	bash scripts/test-check-bump-version.sh

test-lint-skill-invocations:
	bash scripts/test-lint-skill-invocations.sh

test-anti-halt:
	bash scripts/test-anti-halt-banners.sh

test-orchestrator-scope-sync:
	bash scripts/test-orchestrator-scope-sync.sh

test-design-structure:
	bash scripts/test-design-structure.sh

test-implement-rebase-macro:
	bash scripts/test-implement-rebase-macro.sh

test-implement-structure:
	bash scripts/test-implement-structure.sh

test-quick-mode-docs-sync:
	bash scripts/test-quick-mode-docs-sync.sh
	bash scripts/test-quick-mode-docs-sync.sh --self-test

test-references-headers:
	bash scripts/test-references-headers.sh

test-render-reviewer-prompt:
	bash scripts/test-render-reviewer-prompt.sh

test-research-structure:
	bash scripts/test-research-structure.sh

test-research-adjudication:
	bash scripts/test-research-adjudication.sh

test-review-structure:
	bash scripts/test-review-structure.sh

test-run-research-planner:
	bash skills/research/scripts/test-run-research-planner.sh

test-subskill-anchors:
	bash scripts/test-subskill-anchors.sh

test-loop-improve-skill-driver:
	bash scripts/test-loop-improve-skill-driver.sh

test-loop-improve-skill-skill-md:
	bash scripts/test-loop-improve-skill-skill-md.sh

test-loop-review-driver:
	bash scripts/test-loop-review-driver.sh

test-loop-review-skill-md:
	bash scripts/test-loop-review-skill-md.sh

test-improve-skill-iteration:
	bash scripts/test-improve-skill-iteration.sh

test-improve-skill-skill-md:
	bash scripts/test-improve-skill-skill-md.sh

test-parse-skill-judge-grade:
	bash scripts/test-parse-skill-judge-grade.sh

test-lib-halt-ledger:
	bash scripts/test-lib-loop-improve-halt-ledger.sh

test-tracking-issue-write:
	bash scripts/test-tracking-issue-write.sh

test-tracking-issue-read-sentinel:
	bash scripts/test-tracking-issue-read-sentinel.sh

test-assemble-anchor:
	bash scripts/test-assemble-anchor.sh

smoke-dialectic:
	bash scripts/dialectic-smoke-test.sh

# Opt-in halt-rate regression probe (closes #278). NOT a lint prerequisite —
# too slow and non-deterministic for CI. See docs/linting.md "Halt-rate regression harness".
halt-rate-probe:
	bash scripts/test-loop-improve-skill-halt-rate.sh

# Opt-in /research evaluation harness (closes #419 under umbrella #413). NOT a
# lint prerequisite — runs ~20 questions × ~30-60s each, costs real tokens.
# Operator instrumentation for prompt-side iteration on /research. See
# docs/linting.md "/research evaluation harness". Pass flags via ARGS=,
# e.g.: `make eval-research ARGS="--id eval-1 --timeout 4200"`. Direct
# `bash scripts/eval-research.sh ...` is the documented primary path.
eval-research:
	bash scripts/eval-research.sh $(ARGS)

# Standalone offline structural test for the /research eval set + harness
# (closes #419). NOT a `test-harnesses` prerequisite by design — the runtime
# harness it tests is opt-in operator instrumentation explicitly carved out
# from CI. The structural test is itself cheap (no API cost) but kept
# standalone for symmetry. See scripts/test-eval-set-structure.md.
test-eval-set-structure:
	bash scripts/test-eval-set-structure.sh

# Standalone offline regression harness for the `--baseline` flag handling
# in scripts/eval-research.sh (closes #441). NOT a `test-harnesses`
# prerequisite — the eval-research surface is opt-in operator
# instrumentation explicitly carved out from CI by repo contract
# (see Makefile:148, docs/linting.md, scripts/eval-research.md). Runs
# offline by PATH-stubbing claude + jq so it works on machines without
# the real binaries. See scripts/test-eval-research-baseline-flag.md.
test-eval-research-baseline-flag:
	bash scripts/test-eval-research-baseline-flag.sh

shellcheck:
	pre-commit run shellcheck --all-files

markdownlint:
	pre-commit run markdownlint --all-files

jsonlint:
	pre-commit run jsonlint --all-files

actionlint:
	pre-commit run actionlint --all-files

agent-lint:
	pre-commit run agent-lint --all-files

agnix:
	pre-commit run agnix --all-files

gitleaks:
	pre-commit run gitleaks --all-files

# Trufflehog is CI-only (not a pre-commit hook). This target runs the same
# pinned Docker image as CI but in `filesystem` mode over the working tree;
# CI's `trufflehog` job uses the upstream action's default `git` mode over
# the PR range (different subcommand and scan scope). Image/tag and
# `--only-verified` are identical between the two — the rest is not.
trufflehog:
	docker run --rm -v "$(PWD):/repo" ghcr.io/trufflesecurity/trufflehog:3.82.13 \
		filesystem /repo --only-verified

setup:
	pre-commit install
