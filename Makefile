# Larch Makefile
# Thin wrapper around pre-commit. Linter definitions live in .pre-commit-config.yaml.

.PHONY: lint shellcheck markdownlint jsonlint actionlint agent-lint agnix setup test-redact test-parse-input smoke-dialectic

lint: test-redact test-parse-input
	pre-commit run --all-files

test-redact:
	bash scripts/test-redact-secrets.sh

test-parse-input:
	bash skills/issue/scripts/test-parse-input.sh

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
