# Larch Makefile
# Thin wrapper around pre-commit. Linter definitions live in .pre-commit-config.yaml.

.PHONY: lint shellcheck markdownlint jsonlint actionlint agent-lint agnix setup test-redact test-parse-input test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-verify-skill-called test-check-bump-version test-lint-skill-invocations smoke-dialectic

lint: test-redact test-parse-input test-sessionstart test-audit-edit-write test-block-submodule test-deny-edit-write test-post-scaffold-hints test-render-skill test-verify-skill-called test-check-bump-version test-lint-skill-invocations
	pre-commit run --all-files

test-redact:
	bash scripts/test-redact-secrets.sh

test-parse-input:
	bash skills/issue/scripts/test-parse-input.sh

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

smoke-dialectic:
	bash scripts/dialectic-smoke-test.sh

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
