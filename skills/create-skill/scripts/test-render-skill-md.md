# test-render-skill-md.sh contract

`skills/create-skill/scripts/test-render-skill-md.sh` is the regression harness for `skills/create-skill/scripts/render-skill-md.sh`. It is a black-box test: it invokes `render-skill-md.sh` with controlled flag combinations into `mktemp` directories and asserts on stdout content, exit code, and the rendered `SKILL.md` file's frontmatter + body. The harness is wired into `make lint` via the `test-render-skill` Makefile target and the broader `test-harnesses` target.

## Case matrix

The harness exercises every observable contract surface of `render-skill-md.sh`. Add a new case whenever the renderer's CLI grammar, frontmatter contract, body-vs-frontmatter contract, or error-message strings change. Edits to the renderer that pass `make lint` without harness updates indicate missing coverage.

| Case | What it tests |
|------|---------------|
| `multi-step plugin-mode` | Renders the multi-step variant under a `/skills/<name>/` target dir; asserts `RENDERED=` line, frontmatter `name:` + YAML-quoted `description:`, `## Sub-skill Invocation` section, `${CLAUDE_PLUGIN_ROOT}/skills/shared/subskill-invocation.md` and `${CLAUDE_PLUGIN_ROOT}/skills/shared/skill-design-principles.md` references, the literal `Anti-halt continuation reminder` substring (closes #177). |
| `minimal consumer-mode` | Renders the minimal variant under a `.claude/skills/<name>/` target dir; asserts the same surface as the multi-step case for backward-compat parity. |
| `empty plugin-token rejected` | Invokes the renderer with `--plugin-token ""`; asserts non-zero exit and `ERROR=Missing required argument --plugin-token` (guards against the silent `/skills/shared/subskill-invocation.md` rooted-path emission described in `render-skill-md.md`). |
| `feature-spec-file multi-line` (closes #568) | Invokes with `--feature-spec-file <multi-line-file>` distinct from `--description`; asserts the rendered body's opening paragraph contains the multi-line file content verbatim while the frontmatter `description:` still matches `--description`. |
| `backward-compat body falls back to description` (closes #568) | Invokes WITHOUT `--feature-spec-file`; asserts the rendered body's opening paragraph contains the `--description` value (explicit assertion, NOT inferred from the existing two cases — the prior cases assert frontmatter only). |
| `missing feature-spec-file rejected` (closes #568) | Invokes with `--feature-spec-file /nonexistent/path`; asserts non-zero exit and `ERROR=Cannot read --feature-spec-file: <path>` on stderr. |

## Helper structure

The harness uses a `run_case` helper that takes label, multi-step flag, target dir, name, description, and (optionally) a feature-spec-file path, then runs the renderer and applies a fixed assertion battery. The empty-`--plugin-token` and missing-`--feature-spec-file` cases are inline (out-of-helper) because their assertion shape differs (non-zero exit + stderr ERROR= line vs the helper's success-path SKILL.md content checks).

`PASS_COUNT` and `FAIL_COUNT` are tracked at the script level; each case prints `PASS:` / `FAIL:` to stdout. The harness exits 0 if `FAIL_COUNT == 0`, exit 1 otherwise.

## Makefile wiring

The Makefile defines a `test-render-skill` target whose recipe runs `bash skills/create-skill/scripts/test-render-skill-md.sh`. The target is included in the `test-harnesses` umbrella target (which `make lint` runs). It is also independently invocable via `make test-render-skill` for fast local iteration during render-script edits.

The harness is excluded from `agent-lint.toml`'s dead-script check (matches `scripts/test-parse-args.sh` etc. — test harnesses are not invoked by the runtime SKILL.md flow, so they would otherwise look orphaned).

## Edit-in-sync rules

When changing this harness:

1. Keep the case matrix in sync with `render-skill-md.md`'s "Test coverage" section.
2. Keep error-string assertions byte-identical with `render-skill-md.sh`'s `ERROR=` literals — a typo in either side will manifest as a regression on next CI run.
3. When adding a new test case for a new flag or edge case, document it in this file's case matrix table.

When changing `render-skill-md.sh`:

1. Update this harness in the same PR to cover the new behavior.
2. Update `render-skill-md.md`'s "Test coverage" section to mirror this file's case matrix.
3. Run `make test-render-skill` locally before committing.
