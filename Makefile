# Larch Makefile
# Thin wrapper around pre-commit. Linter definitions live in .pre-commit-config.yaml.

.PHONY: lint shellcheck markdownlint jsonlint actionlint agent-lint agnix setup test-redact

lint: test-redact
	pre-commit run --all-files

test-redact:
	bash scripts/test-redact-secrets.sh

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
