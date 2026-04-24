# Larch Makefile
# Thin wrapper around pre-commit. Linter definitions live in .pre-commit-config.yaml.

.PHONY: lint lint-only test-harnesses shellcheck markdownlint jsonlint actionlint agent-lint agnix setup test-redact test-parse-input test-parse-prose-blockers test-issue-lifecycle test-fix-issue-bail-detection test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-verify-skill-called test-check-bump-version test-lint-skill-invocations test-anti-halt test-orchestrator-scope-sync test-design-structure test-implement-rebase-macro test-implement-structure test-references-headers test-research-structure test-review-structure test-subskill-anchors test-loop-improve-skill-driver test-loop-improve-skill-skill-md test-parse-skill-judge-grade test-lib-halt-ledger test-tracking-issue-write test-tracking-issue-read-sentinel smoke-dialectic halt-rate-probe

# CI splits `lint` into `lint-only` (pre-commit) and `test-harnesses`
# (regression harnesses). `lint` remains the local-dev convenience target
# that runs both, defined in terms of the two split targets to prevent drift.
lint: test-harnesses lint-only

lint-only:
	pre-commit run --all-files

test-harnesses: test-redact test-parse-input test-parse-prose-blockers test-issue-lifecycle test-fix-issue-bail-detection test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-verify-skill-called test-check-bump-version test-lint-skill-invocations test-anti-halt test-orchestrator-scope-sync test-design-structure test-implement-rebase-macro test-implement-structure test-references-headers test-research-structure test-review-structure test-subskill-anchors test-loop-improve-skill-driver test-loop-improve-skill-skill-md test-parse-skill-judge-grade test-lib-halt-ledger test-tracking-issue-write test-tracking-issue-read-sentinel

test-redact:
	bash scripts/test-redact-secrets.sh

test-parse-input:
	bash skills/issue/scripts/test-parse-input.sh

test-parse-prose-blockers:
	bash skills/fix-issue/scripts/test-parse-prose-blockers.sh

test-issue-lifecycle:
	bash skills/fix-issue/scripts/test-issue-lifecycle.sh

test-fix-issue-bail-detection:
	bash skills/fix-issue/scripts/test-fix-issue-bail-detection.sh

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

test-references-headers:
	bash scripts/test-references-headers.sh

test-research-structure:
	bash scripts/test-research-structure.sh

test-review-structure:
	bash scripts/test-review-structure.sh

test-subskill-anchors:
	bash scripts/test-subskill-anchors.sh

test-loop-improve-skill-driver:
	bash scripts/test-loop-improve-skill-driver.sh

test-loop-improve-skill-skill-md:
	bash scripts/test-loop-improve-skill-skill-md.sh

test-parse-skill-judge-grade:
	bash scripts/test-parse-skill-judge-grade.sh

test-lib-halt-ledger:
	bash scripts/test-lib-loop-improve-halt-ledger.sh

test-tracking-issue-write:
	bash scripts/test-tracking-issue-write.sh

test-tracking-issue-read-sentinel:
	bash scripts/test-tracking-issue-read-sentinel.sh

smoke-dialectic:
	bash scripts/dialectic-smoke-test.sh

# Opt-in halt-rate regression probe (closes #278). NOT a lint prerequisite —
# too slow and non-deterministic for CI. See docs/linting.md "Halt-rate regression harness".
halt-rate-probe:
	bash scripts/test-loop-improve-skill-halt-rate.sh

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

setup:
	pre-commit install
